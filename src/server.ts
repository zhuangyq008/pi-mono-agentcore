import Fastify from "fastify";
import { createAwsSaAgent } from "./agent/factory.js";
import { loadSkillsFromDirs } from "./skills/loader.js";
import { renderSkillsForPrompt } from "./skills/renderer.js";
import { syncSkillsFromS3 } from "./skills/s3-sync.js";
import { createWorkspaceManager } from "./workspace/manager.js";
import type { Config } from "./config/index.js";

export async function startServer(config: Config) {
  // 1. Initialize workspace manager (persistent filesystem)
  const workspace = await createWorkspaceManager(config);
  console.log(`[workspace] initialized at ${workspace.basePath} (persistent=${workspace.isAvailable})`);

  // 2. Sync S3 skills (use workspace cache if available)
  const skillsCacheDir = workspace.skillsCacheDir();
  await syncSkillsFromS3(config, { cacheDir: skillsCacheDir });

  // 3. Load all skills (built-in + S3 cached)
  const skillsDirs = [config.skillsLocalDir, skillsCacheDir];
  const skills = await loadSkillsFromDirs(skillsDirs);
  const skillsPrompt = renderSkillsForPrompt(skills);

  // 4. Start HTTP server
  const app = Fastify({ logger: true });

  // AgentCore Runtime may send payload as application/octet-stream
  // Register content type parser to handle raw bytes as JSON
  app.addContentTypeParser(
    "application/octet-stream",
    { parseAs: "string" },
    (_req, body, done) => {
      try {
        const json = JSON.parse(body as string);
        done(null, json);
      } catch (err) {
        done(err as Error, undefined);
      }
    }
  );

  // Also handle missing content-type
  app.addContentTypeParser(
    "*",
    { parseAs: "string" },
    (_req, body, done) => {
      try {
        const json = JSON.parse(body as string);
        done(null, json);
      } catch (err) {
        done(err as Error, undefined);
      }
    }
  );

  // Health check — AgentCore Runtime contract
  app.get("/ping", async () => ({ status: "healthy" }));

  // Agent invocation — AgentCore Runtime contract
  app.post<{
    Body: {
      prompt: string;
      context?: unknown[];
      sessionId?: string;
    };
  }>("/invocations", async (request, reply) => {
    const { prompt, context, sessionId } = request.body;

    if (!prompt || typeof prompt !== "string") {
      return reply.status(400).send({ error: "Missing required field: prompt" });
    }

    // Create agent instance per request
    const agent = createAwsSaAgent(config, skillsPrompt);

    // Load session history: prefer client context, fallback to workspace history
    let messages: unknown[] = [];
    if (context && Array.isArray(context) && context.length > 0) {
      messages = context;
    } else if (workspace.isAvailable) {
      messages = await workspace.loadSessionHistory();
    }

    if (messages.length > 0) {
      agent.state.messages = messages as any[];
    }

    // Execute agent
    try {
      await agent.prompt(prompt);
      await agent.waitForIdle();
    } catch (err) {
      console.error("[agent] execution error:", err);
      return reply.status(500).send({
        error: "Agent execution failed",
        detail: err instanceof Error ? err.message : String(err),
      });
    }

    // Collect result
    const allMessages = agent.state.messages;
    const lastAssistant = [...allMessages]
      .reverse()
      .find((m) => m.role === "assistant") as any;

    const resultText = lastAssistant
      ? lastAssistant.content
          .filter((c: any) => c.type === "text")
          .map((c: any) => c.text)
          .join("\n")
      : "No response generated";

    // Persist session history to workspace (non-blocking)
    if (workspace.isAvailable) {
      workspace.saveSessionHistory(allMessages).catch((err) => {
        console.error("[workspace] failed to save session history:", err);
      });
    }

    return {
      result: resultText,
      messages: allMessages,
      usage: lastAssistant?.usage ?? null,
      workspace: {
        persistent: workspace.isAvailable,
        artifactsDir: workspace.artifactsDir(),
      },
    };
  });

  await app.listen({ port: config.port, host: "0.0.0.0" });
  console.log(`[server] Listening on port ${config.port}`);
}

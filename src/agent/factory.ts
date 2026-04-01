import { Agent } from "@mariozechner/pi-agent-core";
import type { AgentTool } from "@mariozechner/pi-agent-core";
import type { ThinkingLevel } from "@mariozechner/pi-ai";
import { getModel } from "@mariozechner/pi-ai";
import { createBashTool } from "../tools/bash.js";
import { createAwsCliTool } from "../tools/aws-cli.js";
import { buildSystemPrompt } from "./system-prompt.js";
import { createBeforeToolCallHook, createAfterToolCallHook } from "./hooks.js";
import type { Config } from "../config/index.js";

export function createAwsSaAgent(config: Config, skillsPrompt: string): Agent {
  // getModel returns a frozen model object; we need to override the id
  // to use an inference profile (e.g., "us.anthropic.claude-sonnet-4-6")
  const baseModel = getModel("amazon-bedrock", config.modelId as any);
  const model = { ...baseModel, id: config.inferenceProfileId ?? baseModel.id };

  const tools: AgentTool<any>[] = [
    createBashTool(config),
    createAwsCliTool(config),
  ];

  const thinkingLevel = config.thinkingLevel as ThinkingLevel;

  const agent = new Agent({
    initialState: {
      systemPrompt: buildSystemPrompt(skillsPrompt),
      model,
      tools,
      thinkingLevel,
    },
    toolExecution: "sequential",
    beforeToolCall: createBeforeToolCallHook(config),
    afterToolCall: createAfterToolCallHook(config),
  });

  return agent;
}

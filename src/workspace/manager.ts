import { mkdir, writeFile, readFile, access } from "node:fs/promises";
import { join } from "node:path";
import type { Config } from "../config/index.js";

export interface WorkspaceManager {
  readonly basePath: string;
  readonly isAvailable: boolean;
  sessionDir(): string;
  artifactsDir(): string;
  skillsCacheDir(): string;
  saveSessionHistory(messages: unknown[]): Promise<void>;
  loadSessionHistory(): Promise<unknown[]>;
  saveArtifact(name: string, content: string, subdir?: string): Promise<string>;
}

export async function createWorkspaceManager(config: Config): Promise<WorkspaceManager> {
  const basePath = config.workspacePath;
  let isAvailable = false;

  try {
    await access(basePath);
    isAvailable = true;
  } catch {
    console.log(`[workspace] ${basePath} not available, falling back to /tmp/workspace`);
  }

  const effectivePath = isAvailable ? basePath : "/tmp/workspace";

  const dirs = [
    join(effectivePath, ".session"),
    join(effectivePath, ".skills-cache"),
    join(effectivePath, "artifacts", "reports"),
    join(effectivePath, "artifacts", "configs"),
    join(effectivePath, "artifacts", "diagrams"),
    join(effectivePath, "tmp"),
  ];
  await Promise.all(dirs.map((d) => mkdir(d, { recursive: true })));

  return {
    basePath: effectivePath,
    isAvailable,

    sessionDir: () => join(effectivePath, ".session"),
    artifactsDir: () => join(effectivePath, "artifacts"),
    skillsCacheDir: () => join(effectivePath, ".skills-cache"),

    async saveSessionHistory(messages: unknown[]): Promise<void> {
      const path = join(effectivePath, ".session", "history.jsonl");
      const lines = messages.map((m) => JSON.stringify(m)).join("\n") + "\n";
      await writeFile(path, lines, "utf-8");
    },

    async loadSessionHistory(): Promise<unknown[]> {
      try {
        const path = join(effectivePath, ".session", "history.jsonl");
        const content = await readFile(path, "utf-8");
        return content
          .trim()
          .split("\n")
          .filter(Boolean)
          .map((line) => JSON.parse(line));
      } catch {
        return [];
      }
    },

    async saveArtifact(name: string, content: string, subdir = "reports"): Promise<string> {
      const dir = join(effectivePath, "artifacts", subdir);
      await mkdir(dir, { recursive: true });
      const path = join(dir, name);
      await writeFile(path, content, "utf-8");
      return path;
    },
  };
}

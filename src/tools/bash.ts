import { Type, type Static } from "@sinclair/typebox";
import type { AgentTool, AgentToolResult } from "@mariozechner/pi-agent-core";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { Config } from "../config/index.js";

const execFileAsync = promisify(execFile);

const BashParams = Type.Object({
  command: Type.String({ description: "The bash command to execute" }),
  timeout: Type.Optional(
    Type.Number({
      description: "Timeout in milliseconds (default: 120000, max: 600000)",
      default: 120000,
    })
  ),
});

type BashParamsType = Static<typeof BashParams>;

export function createBashTool(config: Config): AgentTool<typeof BashParams> {
  return {
    name: "bash",
    label: "Bash",
    description: `Execute a bash command on the system. Use for:
- System diagnostics (top, df, netstat, ss, ip, etc.)
- File operations (ls, cat, find, grep)
- Network troubleshooting (ping, traceroute, dig, nslookup, curl)
- Package management (yum, apt)
- Process management (ps, kill, systemctl)
- Log analysis (journalctl, tail)
Do NOT use for AWS API calls — use the aws_cli tool instead.`,
    parameters: BashParams,

    async execute(
      _toolCallId: string,
      params: BashParamsType,
      signal?: AbortSignal,
    ): Promise<AgentToolResult<{ exitCode: number }>> {
      const timeout = Math.min(params.timeout ?? 120_000, config.maxCommandTimeout);

      try {
        const { stdout, stderr } = await execFileAsync(
          "/bin/bash",
          ["-c", params.command],
          {
            timeout,
            maxBuffer: 1024 * 1024,
            signal,
            env: {
              ...process.env,
              HOME: "/tmp",
            },
          }
        );

        const output = [stdout, stderr].filter(Boolean).join("\n");
        return {
          content: [{ type: "text", text: output || "(no output)" }],
          details: { exitCode: 0 },
        };
      } catch (err: unknown) {
        const error = err as { code?: number; stdout?: string; stderr?: string; message?: string };
        const output = [error.stdout, error.stderr, error.message]
          .filter(Boolean)
          .join("\n");
        throw new Error(output || "Command failed");
      }
    },
  };
}

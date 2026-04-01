import { Type, type Static } from "@sinclair/typebox";
import type { AgentTool, AgentToolResult } from "@mariozechner/pi-agent-core";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { Config } from "../config/index.js";

const execFileAsync = promisify(execFile);

const AwsCliParams = Type.Object({
  command: Type.String({
    description:
      "The AWS CLI command (without 'aws' prefix). Example: 's3 ls', 'ec2 describe-instances --region us-east-1'",
  }),
  region: Type.Optional(
    Type.String({
      description: "AWS region override (default: agent's configured region)",
    })
  ),
  output: Type.Optional(
    Type.Union([Type.Literal("json"), Type.Literal("text"), Type.Literal("table")], {
      description: "Output format (default: json)",
      default: "json",
    })
  ),
});

type AwsCliParamsType = Static<typeof AwsCliParams>;

const BLOCKED_PATTERNS: readonly RegExp[] = [
  /\bdelete-\w+/,
  /\bterminate-instances\b/,
  /\bdelete-stack\b/,
  /\bderegister\b/,
  /\bpurge\b/,
  /\bremove-\w+/,
  /\bdrop\b/,
  /--force\b/,
];

export function createAwsCliTool(config: Config): AgentTool<typeof AwsCliParams> {
  return {
    name: "aws_cli",
    label: "AWS CLI",
    description: `Execute AWS CLI commands to interact with AWS services. Use for:
- Resource inspection (describe, list, get)
- Configuration analysis (get-*, describe-*)
- Monitoring (cloudwatch get-metric-data, logs filter-log-events)
- Cost analysis (ce get-cost-and-usage)
- Network diagnostics (ec2 describe-vpcs, describe-subnets, describe-security-groups)
- IAM review (iam list-roles, get-policy)
Destructive operations (delete, terminate, purge) are blocked by default.`,
    parameters: AwsCliParams,

    async execute(
      _toolCallId: string,
      params: AwsCliParamsType,
      signal?: AbortSignal,
    ): Promise<AgentToolResult<{ exitCode: number }>> {
      for (const pattern of BLOCKED_PATTERNS) {
        if (pattern.test(params.command)) {
          throw new Error(
            `Blocked: destructive operation detected in "${params.command}". ` +
            `This agent is configured for read/diagnostic operations only.`
          );
        }
      }

      const args = params.command.split(/\s+/);
      const region = params.region ?? config.awsRegion;
      const output = params.output ?? "json";

      try {
        const { stdout, stderr } = await execFileAsync(
          "aws",
          [...args, "--region", region, "--output", output],
          {
            timeout: 300_000,
            maxBuffer: 5 * 1024 * 1024,
            signal,
            env: process.env,
          }
        );

        const result = [stdout, stderr].filter(Boolean).join("\n");
        return {
          content: [{ type: "text", text: result || "(no output)" }],
          details: { exitCode: 0 },
        };
      } catch (err: unknown) {
        const error = err as { stdout?: string; stderr?: string; message?: string };
        const output = [error.stdout, error.stderr, error.message]
          .filter(Boolean)
          .join("\n");
        throw new Error(output || "AWS CLI command failed");
      }
    },
  };
}

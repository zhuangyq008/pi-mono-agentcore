import type {
  BeforeToolCallContext,
  BeforeToolCallResult,
  AfterToolCallContext,
  AfterToolCallResult,
} from "@mariozechner/pi-agent-core";
import type { Config } from "../config/index.js";

const SENSITIVE_PATTERNS: readonly RegExp[] = [
  /(?:AKIA|ASIA)[A-Z0-9]{16}/g,
  /(?:aws_secret_access_key\s*=\s*)\S+/gi,
  /-----BEGIN.*PRIVATE KEY-----[\s\S]*?-----END.*PRIVATE KEY-----/g,
  /(?:password|passwd|secret)\s*[=:]\s*\S+/gi,
];

export function createBeforeToolCallHook(_config: Config) {
  return async (
    ctx: BeforeToolCallContext,
    _signal?: AbortSignal,
  ): Promise<BeforeToolCallResult | undefined> => {
    console.log(
      `[tool:preflight] ${ctx.toolCall.name} args=${JSON.stringify(ctx.args).slice(0, 200)}`
    );
    return undefined;
  };
}

export function createAfterToolCallHook(_config: Config) {
  return async (
    ctx: AfterToolCallContext,
    _signal?: AbortSignal,
  ): Promise<AfterToolCallResult | undefined> => {
    let hasRedacted = false;
    const filtered = ctx.result.content.map((block) => {
      if (block.type !== "text") return block;
      let text = block.text;
      for (const pattern of SENSITIVE_PATTERNS) {
        const regex = new RegExp(pattern.source, pattern.flags);
        const replaced = text.replace(regex, "[REDACTED]");
        if (replaced !== text) hasRedacted = true;
        text = replaced;
      }
      return { ...block, text };
    });

    if (hasRedacted) {
      return { content: filtered };
    }
    return undefined;
  };
}

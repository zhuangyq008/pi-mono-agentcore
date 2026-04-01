# AWS SA Agent — 技术实现规格文档

> **项目名称**: pi-on-agentcore  
> **版本**: v0.1.0  
> **日期**: 2026-04-01  
> **状态**: Draft

---

## 目录

1. [概述](#1-概述)
2. [架构总览](#2-架构总览)
3. [技术栈](#3-技术栈)
4. [核心组件设计](#4-核心组件设计)
5. [Agent 定义](#5-agent-定义)
6. [Tools 实现](#6-tools-实现)
7. [Skills 系统](#7-skills-系统)
8. [System Prompt 设计](#8-system-prompt-设计)
9. [HTTP 服务层](#9-http-服务层)
10. [持久化文件系统与状态管理](#10-持久化文件系统与状态管理)
11. [容器化与部署](#11-容器化与部署)
12. [IAM 与安全](#12-iam-与安全)
13. [配置管理](#13-配置管理)
14. [可观测性](#14-可观测性)
15. [约束与限制](#15-约束与限制)
16. [项目结构](#16-项目结构)
17. [实施路线图](#17-实施路线图)

---

## 1. 概述

### 1.1 目标

构建一个 **AWS Solutions Architect (SA) Agent**，具备以下能力：

- 通过 `bash` 和 `aws_cli` 工具直接操作 AWS 环境
- 精通网络、操作系统相关知识并能实际执行诊断和配置
- 通过 SKILL.md 系统加载可扩展的专业知识（支持从 S3 动态导入）
- 基于 `@mariozechner/pi-agent-core` 框架构建
- 部署在 Amazon Bedrock AgentCore Runtime（容器模式）

### 1.2 设计原则

| 原则 | 说明 |
|------|------|
| **框架精简** | 仅依赖 `pi-agent-core`（agent runtime）+ `pi-ai`（LLM 抽象），不引入 coding-agent |
| **技能可扩展** | Skills 从本地 + S3 bucket 加载，运行时可刷新 |
| **安全第一** | IAM 最小权限、工具执行沙箱、输入验证 |
| **无状态部署** | 每次 session 独立 microVM，无持久化依赖 |

---

## 2. 架构总览

```
┌─────────────────────────────────────────────────────────┐
│                  AgentCore Runtime                       │
│                  (Serverless microVM)                    │
│                                                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │              HTTP Server (port 8080)               │  │
│  │          POST /invocations  GET /ping              │  │
│  └──────────────────────┬────────────────────────────┘  │
│                         │                               │
│  ┌──────────────────────▼────────────────────────────┐  │
│  │              Request Router                        │  │
│  │     (parse payload, manage session context)        │  │
│  └──────────────────────┬────────────────────────────┘  │
│                         │                               │
│  ┌──────────────────────▼────────────────────────────┐  │
│  │           pi-agent-core Agent                      │  │
│  │                                                    │  │
│  │  ┌─────────┐  ┌──────────┐  ┌─────────────────┐  │  │
│  │  │ System  │  │  Model   │  │     Tools       │  │  │
│  │  │ Prompt  │  │ Bedrock  │  │  bash | aws_cli │  │  │
│  │  │ + Skills│  │ Claude   │  │                 │  │  │
│  │  └─────────┘  └──────────┘  └─────────────────┘  │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
│  ┌───────────────────────────────────────────────────┐  │
│  │              Skills Loader                         │  │
│  │     Local SKILL.md + S3 Bucket Sync               │  │
│  └───────────────────────────────────────────────────┘  │
│                                                         │
└─────────────────────────────────────────────────────────┘
         │                              │
         ▼                              ▼
   Amazon Bedrock                 AWS Services
   (Claude Sonnet 4.6)          (via aws cli)
```

---

## 3. 技术栈

| 层级 | 技术选型 | 版本 |
|------|---------|------|
| **Runtime** | Node.js | >= 20.0.0 |
| **Language** | TypeScript | 5.x |
| **Agent Framework** | `@mariozechner/pi-agent-core` | ^0.64.0 |
| **LLM Abstraction** | `@mariozechner/pi-ai` | ^0.64.0 |
| **LLM Model** | `anthropic.claude-sonnet-4-6-v1:0` via Bedrock | - |
| **HTTP Server** | Fastify (轻量、TypeScript 友好) | 5.x |
| **Schema Validation** | `@sinclair/typebox` (pi-agent-core 依赖) | - |
| **S3 Client** | `@aws-sdk/client-s3` | 3.x |
| **Container** | Docker (linux/arm64) | - |
| **Registry** | Amazon ECR | - |
| **Deployment** | Bedrock AgentCore Runtime (Container mode) | - |

---

## 4. 核心组件设计

### 4.1 组件依赖图

```
src/
├── server.ts              # HTTP server (Fastify)
├── agent/
│   ├── factory.ts         # Agent 实例创建
│   ├── system-prompt.ts   # System prompt 构建
│   └── hooks.ts           # beforeToolCall / afterToolCall
├── tools/
│   ├── bash.ts            # Bash tool
│   └── aws-cli.ts         # AWS CLI tool
├── skills/
│   ├── loader.ts          # Skills 加载器 (local + S3)
│   ├── s3-sync.ts         # S3 bucket 同步
│   └── renderer.ts        # Skills → system prompt XML
├── config/
│   └── index.ts           # 环境变量 & 配置
└── index.ts               # 入口
```

### 4.2 数据流

```
Client Request (POST /invocations)
  │
  ├─ payload: { prompt: string, sessionId?: string, context?: Message[] }
  │
  ▼
Request Router
  │
  ├─ 解析 payload
  ├─ 加载/创建 agent 实例
  │
  ▼
Agent.prompt(userMessage)
  │
  ├─ 构建 system prompt (identity + skills + safety rules)
  ├─ 调用 Bedrock Claude Sonnet 4.6 (streaming)
  │
  ├─ [LLM 返回 tool_use] ──► Tool Execution
  │     ├─ beforeToolCall hook (安全检查)
  │     ├─ bash.execute() 或 aws-cli.execute()
  │     ├─ afterToolCall hook (输出过滤)
  │     └─ 结果返回 LLM 继续推理
  │
  ├─ [LLM 返回 stop] ──► 收集最终回复
  │
  ▼
Response: { result: string, messages: Message[], usage: Usage }
```

---

## 5. Agent 定义

### 5.1 Agent 实例化

```typescript
// src/agent/factory.ts
import { Agent, type AgentTool } from "@mariozechner/pi-agent-core";
import { getModel } from "@mariozechner/pi-ai";
import { buildSystemPrompt } from "./system-prompt";
import { createBeforeToolCallHook, createAfterToolCallHook } from "./hooks";
import { createBashTool } from "../tools/bash";
import { createAwsCliTool } from "../tools/aws-cli";
import type { Config } from "../config";

export function createAwsSaAgent(config: Config, skillsPrompt: string): Agent {
  const model = getModel("anthropic.claude-sonnet-4-6-v1:0");
  // pi-ai 的 getModel 对 Bedrock 模型会自动设置:
  //   api: "bedrock-converse-stream"
  //   provider: "amazon-bedrock"
  // 认证通过 AWS SDK 默认凭证链 (IAM Role in AgentCore Runtime)

  const tools: AgentTool[] = [
    createBashTool(config),
    createAwsCliTool(config),
  ];

  const agent = new Agent({
    initialState: {
      systemPrompt: buildSystemPrompt(skillsPrompt),
      model,
      tools,
      thinkingLevel: "medium",
    },
    toolExecution: "sequential",  // AWS CLI 命令通常有依赖关系，顺序执行更安全
    beforeToolCall: createBeforeToolCallHook(config),
    afterToolCall: createAfterToolCallHook(config),
  });

  return agent;
}
```

### 5.2 Model ID 映射

| 用户配置 | pi-ai Model ID | Bedrock Model ID |
|----------|----------------|------------------|
| `bedrock/global.anthropic.claude-sonnet-4-6` | `anthropic.claude-sonnet-4-6-v1:0` | `anthropic.claude-sonnet-4-6-v1:0` |

> **注意**: `pi-ai` 使用 `bedrock-converse-stream` API，通过 AWS SDK 默认凭证链认证。
> 在 AgentCore Runtime 中，凭证由 Execution Role 自动提供，无需配置 API key。

### 5.3 Thinking Level 配置

```typescript
// Agent 层 ThinkingLevel: "off" | "minimal" | "low" | "medium" | "high" | "xhigh"
// 默认使用 "medium"，平衡推理深度和延迟

thinkingBudgets: {
  minimal: 256,
  low: 1024,
  medium: 4096,
  high: 8192,
}
```

---

## 6. Tools 实现

### 6.1 Bash Tool

```typescript
// src/tools/bash.ts
import { Type, type Static } from "@sinclair/typebox";
import type { AgentTool, AgentToolResult } from "@mariozechner/pi-agent-core";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { Config } from "../config";

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
      toolCallId: string,
      params: BashParamsType,
      signal?: AbortSignal,
    ): Promise<AgentToolResult<{ exitCode: number }>> {
      const timeout = Math.min(params.timeout ?? 120_000, 600_000);

      try {
        const { stdout, stderr } = await execFileAsync(
          "/bin/bash",
          ["-c", params.command],
          {
            timeout,
            maxBuffer: 1024 * 1024, // 1MB
            signal,
            env: {
              ...process.env,
              // 安全: 限制 PATH，移除敏感变量
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
        // pi-agent-core: throw on failure → creates isError: true tool result
        throw new Error(output || "Command failed");
      }
    },
  };
}
```

### 6.2 AWS CLI Tool

```typescript
// src/tools/aws-cli.ts
import { Type, type Static } from "@sinclair/typebox";
import type { AgentTool, AgentToolResult } from "@mariozechner/pi-agent-core";
import { execFile } from "node:child_process";
import { promisify } from "node:util";
import type { Config } from "../config";

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

// 高风险操作黑名单
const BLOCKED_PATTERNS = [
  /\bdelete-\w+/,                   // delete-* 操作
  /\bterminate-instances\b/,
  /\bdelete-stack\b/,
  /\bderegister\b/,
  /\bpurge\b/,
  /\bremove-\w+/,
  /\bdrop\b/,
  /--force\b/,
] as const;

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
      toolCallId: string,
      params: AwsCliParamsType,
      signal?: AbortSignal,
    ): Promise<AgentToolResult<{ exitCode: number }>> {
      // 安全检查: 阻止高风险操作
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
            timeout: 300_000, // 5 min for AWS API calls
            maxBuffer: 5 * 1024 * 1024, // 5MB (AWS responses can be large)
            signal,
            env: process.env, // 继承 IAM Role 凭证
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
```

### 6.3 Safety Hooks

```typescript
// src/agent/hooks.ts
import type {
  BeforeToolCallContext,
  BeforeToolCallResult,
  AfterToolCallContext,
  AfterToolCallResult,
} from "@mariozechner/pi-agent-core";
import type { Config } from "../config";

// 敏感信息过滤正则
const SENSITIVE_PATTERNS = [
  /(?:AKIA|ASIA)[A-Z0-9]{16}/g,              // AWS Access Key
  /(?:aws_secret_access_key\s*=\s*)\S+/gi,   // Secret Key in config
  /-----BEGIN.*PRIVATE KEY-----[\s\S]*?-----END.*PRIVATE KEY-----/g,
  /(?:password|passwd|secret)\s*[=:]\s*\S+/gi,
];

export function createBeforeToolCallHook(config: Config) {
  return async (
    ctx: BeforeToolCallContext,
    signal?: AbortSignal,
  ): Promise<BeforeToolCallResult | undefined> => {
    // 记录工具调用日志
    console.log(
      `[tool:preflight] ${ctx.toolCall.name} args=${JSON.stringify(ctx.args).slice(0, 200)}`
    );

    // 可扩展: 添加额外的安全策略检查
    return undefined; // 不阻止
  };
}

export function createAfterToolCallHook(config: Config) {
  return async (
    ctx: AfterToolCallContext,
    signal?: AbortSignal,
  ): Promise<AfterToolCallResult | undefined> => {
    // 过滤输出中的敏感信息
    const filtered = ctx.result.content.map((block) => {
      if (block.type !== "text") return block;
      let text = block.text;
      for (const pattern of SENSITIVE_PATTERNS) {
        text = text.replace(pattern, "[REDACTED]");
      }
      return { ...block, text };
    });

    if (filtered !== ctx.result.content) {
      return { content: filtered };
    }
    return undefined;
  };
}
```

---

## 7. Skills 系统

### 7.1 SKILL.md 格式

遵循 pi-mono 标准格式：

```markdown
---
name: vpc-troubleshooting
description: VPC 网络故障诊断，包括子网路由、安全组分析、NAT Gateway 排查
---

## VPC 故障诊断指南

### 1. 连通性检查
- 检查路由表配置 ...
- 检查安全组规则 ...
- 检查 NACL ...

### 2. 常用命令
...
```

**格式规则**：
- `name`: 小写字母 + 数字 + 连字符，最多 64 字符
- `description`: 最多 1024 字符，用于 LLM 判断是否加载此 skill
- `disable-model-invocation`: 可选，设为 `true` 时不渲染到 system prompt
- Content: Markdown 格式的详细知识内容

### 7.2 Skills 目录结构

```
skills/
├── aws-networking/
│   └── SKILL.md          # VPC, Subnet, SG, NACL, Transit Gateway
├── aws-compute/
│   └── SKILL.md          # EC2, ECS, EKS, Lambda
├── aws-storage/
│   └── SKILL.md          # S3, EBS, EFS, FSx
├── aws-database/
│   └── SKILL.md          # RDS, DynamoDB, ElastiCache, Aurora
├── aws-security/
│   └── SKILL.md          # IAM, KMS, Secrets Manager, GuardDuty
├── aws-cost-optimization/
│   └── SKILL.md          # Cost Explorer, Savings Plans, Reserved Instances
├── linux-administration/
│   └── SKILL.md          # systemd, networking, performance tuning
└── troubleshooting/
    └── SKILL.md          # 通用故障排除方法论
```

### 7.3 S3 Skills 同步

```typescript
// src/skills/s3-sync.ts
import {
  S3Client,
  ListObjectsV2Command,
  GetObjectCommand,
} from "@aws-sdk/client-s3";
import { mkdir, writeFile } from "node:fs/promises";
import { join, dirname } from "node:path";
import type { Config } from "../config";

export async function syncSkillsFromS3(config: Config): Promise<string[]> {
  if (!config.skillsS3Bucket) return [];

  const s3 = new S3Client({ region: config.awsRegion });
  const prefix = config.skillsS3Prefix ?? "skills/";
  const localDir = config.skillsLocalDir;
  const syncedPaths: string[] = [];

  const listResult = await s3.send(
    new ListObjectsV2Command({
      Bucket: config.skillsS3Bucket,
      Prefix: prefix,
    })
  );

  for (const obj of listResult.Contents ?? []) {
    if (!obj.Key?.endsWith("SKILL.md") && !obj.Key?.endsWith(".md")) continue;

    const relativePath = obj.Key.slice(prefix.length);
    const localPath = join(localDir, "s3", relativePath);

    const getResult = await s3.send(
      new GetObjectCommand({
        Bucket: config.skillsS3Bucket,
        Key: obj.Key,
      })
    );

    const body = await getResult.Body?.transformToString();
    if (!body) continue;

    await mkdir(dirname(localPath), { recursive: true });
    await writeFile(localPath, body, "utf-8");
    syncedPaths.push(localPath);
  }

  console.log(`[skills] Synced ${syncedPaths.length} skills from s3://${config.skillsS3Bucket}/${prefix}`);
  return syncedPaths;
}
```

### 7.4 Skills 加载与渲染

```typescript
// src/skills/loader.ts
import { readdir, readFile, stat } from "node:fs/promises";
import { join, basename, dirname } from "node:path";
import { parse as parseYaml } from "yaml";

export interface Skill {
  name: string;
  description: string;
  content: string;
  filePath: string;
  disableModelInvocation: boolean;
}

interface SkillFrontmatter {
  name?: string;
  description?: string;
  "disable-model-invocation"?: boolean;
}

export async function loadSkillsFromDirs(dirs: string[]): Promise<Skill[]> {
  const skills: Skill[] = [];
  const seen = new Set<string>();

  for (const dir of dirs) {
    const found = await scanDir(dir);
    for (const skill of found) {
      if (seen.has(skill.name)) continue; // 先加载的优先
      seen.add(skill.name);
      skills.push(skill);
    }
  }

  console.log(`[skills] Loaded ${skills.length} skills: ${skills.map((s) => s.name).join(", ")}`);
  return skills;
}

async function scanDir(dir: string): Promise<Skill[]> {
  const skills: Skill[] = [];

  try {
    const entries = await readdir(dir, { withFileTypes: true });

    // 检查当前目录是否是 skill root
    const hasSkillMd = entries.some((e) => e.isFile() && e.name === "SKILL.md");
    if (hasSkillMd) {
      const skill = await parseSkillFile(join(dir, "SKILL.md"), dir);
      if (skill) skills.push(skill);
      return skills; // 不再递归
    }

    // 递归子目录
    for (const entry of entries) {
      if (entry.name.startsWith(".") || entry.name === "node_modules") continue;
      if (entry.isDirectory()) {
        skills.push(...(await scanDir(join(dir, entry.name))));
      }
    }
  } catch {
    // 目录不存在或无权限，静默跳过
  }

  return skills;
}

async function parseSkillFile(filePath: string, baseDir: string): Promise<Skill | null> {
  const raw = await readFile(filePath, "utf-8");
  const fmMatch = raw.match(/^---\n([\s\S]*?)\n---\n([\s\S]*)$/);
  if (!fmMatch) return null;

  const frontmatter = parseYaml(fmMatch[1]) as SkillFrontmatter;
  const content = fmMatch[2].trim();

  const name = frontmatter.name ?? basename(baseDir);
  const description = frontmatter.description;
  if (!description) return null; // description 必须

  return {
    name,
    description,
    content,
    filePath,
    disableModelInvocation: frontmatter["disable-model-invocation"] ?? false,
  };
}
```

```typescript
// src/skills/renderer.ts
import type { Skill } from "./loader";

export function renderSkillsForPrompt(skills: readonly Skill[]): string {
  const visible = skills.filter((s) => !s.disableModelInvocation);
  if (visible.length === 0) return "";

  const entries = visible
    .map(
      (s) =>
        `  <skill>\n    <name>${s.name}</name>\n    <description>${s.description}</description>\n  </skill>`
    )
    .join("\n");

  return `
<available_skills>
${entries}
</available_skills>

When a user's request matches a skill's description, load the skill content for detailed guidance.
Skills contain expert knowledge including commands, best practices, and troubleshooting steps.`;
}
```

---

## 8. System Prompt 设计

```typescript
// src/agent/system-prompt.ts

export function buildSystemPrompt(skillsSection: string): string {
  return `# Identity

You are an AWS Solutions Architect (SA) Agent. You are an expert in:
- AWS services architecture, deployment, and operations
- Networking (VPC, subnets, routing, DNS, load balancing, Transit Gateway)
- Operating systems (Linux administration, performance tuning, troubleshooting)
- Security best practices (IAM, encryption, compliance)
- Cost optimization and Well-Architected Framework

# Capabilities

You have two tools:
1. **bash** — Execute system commands for diagnostics, file operations, and network troubleshooting
2. **aws_cli** — Execute AWS CLI commands for resource inspection and management

# Rules

- ALWAYS verify current state before making recommendations (use tools to check)
- NEVER execute destructive operations (delete, terminate, purge) — these are blocked
- When diagnosing issues, follow a structured approach:
  1. Gather symptoms (logs, metrics, status)
  2. Form hypotheses
  3. Test each hypothesis with targeted commands
  4. Provide root cause analysis and remediation steps
- Output JSON format from AWS CLI for precise data extraction
- When showing commands to the user, explain what each flag does
- For cost questions, always specify the time range and granularity
- For network issues, check from both VPC and instance perspective

# Safety

- Never output AWS credentials, private keys, or secrets
- If a command output contains sensitive data, redact it before presenting
- Always use --query and --filter to minimize data returned from AWS APIs
- Prefer read-only operations; explain write operations before executing

# Skills

${skillsSection}
`;
}
```

---

## 9. HTTP 服务层

### 9.1 AgentCore Service Contract

AgentCore Runtime 要求容器暴露：

| 端点 | 方法 | 用途 |
|------|------|------|
| `/ping` | GET | 健康检查，返回 200 |
| `/invocations` | POST | Agent 调用入口 |

端口: **8080** (HTTP)

### 9.2 Server 实现

```typescript
// src/server.ts
import Fastify from "fastify";
import { createAwsSaAgent } from "./agent/factory";
import { loadSkillsFromDirs } from "./skills/loader";
import { renderSkillsForPrompt } from "./skills/renderer";
import { syncSkillsFromS3 } from "./skills/s3-sync";
import { loadConfig } from "./config";

const config = loadConfig();

export async function startServer() {
  // 1. 同步 S3 skills → 本地
  await syncSkillsFromS3(config);

  // 2. 加载所有 skills (本地内置 + S3 同步)
  const skills = await loadSkillsFromDirs([
    config.skillsLocalDir,        // 包含 built-in + s3 synced
  ]);
  const skillsPrompt = renderSkillsForPrompt(skills);

  // 3. 启动 HTTP server
  const app = Fastify({ logger: true });

  // 健康检查
  app.get("/ping", async () => ({ status: "healthy" }));

  // Agent 调用
  app.post<{
    Body: {
      prompt: string;
      context?: unknown[];  // 可选: 历史消息
    };
  }>("/invocations", async (request, reply) => {
    const { prompt, context } = request.body;

    if (!prompt || typeof prompt !== "string") {
      return reply.status(400).send({ error: "Missing required field: prompt" });
    }

    const agent = createAwsSaAgent(config, skillsPrompt);

    // 如果有历史上下文，注入
    if (context && Array.isArray(context)) {
      agent.state.messages = context as any[];
    }

    // 执行 agent
    await agent.prompt(prompt);
    await agent.waitForIdle();

    // 收集结果
    const messages = agent.state.messages;
    const lastAssistant = [...messages]
      .reverse()
      .find((m) => m.role === "assistant");

    const resultText = lastAssistant
      ? lastAssistant.content
          .filter((c: any) => c.type === "text")
          .map((c: any) => c.text)
          .join("\n")
      : "No response generated";

    return {
      result: resultText,
      messages, // 完整对话历史，客户端可用于下一轮
      usage: lastAssistant?.usage ?? null,
    };
  });

  await app.listen({ port: 8080, host: "0.0.0.0" });
  console.log("[server] Listening on port 8080");
}
```

```typescript
// src/index.ts
import { startServer } from "./server";
startServer().catch((err) => {
  console.error("[fatal]", err);
  process.exit(1);
});
```

---

## 10. 持久化文件系统与状态管理

### 10.1 概述

AgentCore Runtime 提供 **Persistent Filesystem** (Preview)，允许 agent 在同一 `runtimeSessionId` 的多次 stop/resume 之间保留文件状态。这对 SA Agent 的以下场景至关重要：

| 场景 | 说明 |
|------|------|
| **Skills 缓存** | S3 下载的 skills 缓存到 workspace，避免每次调用重复下载 |
| **分析产物** | agent 生成的架构图、报告、配置文件持久保存 |
| **对话历史** | 多轮对话上下文写入 filesystem，实现 session 续接 |
| **工作检查点** | 长时间分析任务的中间状态 |

### 10.2 部署配置

```bash
aws bedrock-agentcore-control create-agent-runtime \
  --agent-runtime-name "aws-sa-agent" \
  --filesystem-configurations '[{
    "sessionStorage": {
      "mountPath": "/mnt/workspace"
    }
  }]' \
  # ... 其他参数
```

### 10.3 Workspace 目录结构

```
/mnt/workspace/                    # Persistent filesystem mount point
├── .session/
│   ├── history.jsonl              # 对话历史 (append-only JSONL)
│   └── metadata.json              # Session 元数据 (model, start time, etc.)
├── .skills-cache/                 # S3 skills 本地缓存
│   ├── .last-sync                 # 最后同步时间戳
│   └── <skill-name>/
│       └── SKILL.md
├── artifacts/                     # Agent 产物输出目录
│   ├── reports/                   # 分析报告
│   ├── configs/                   # 生成的配置文件
│   └── diagrams/                  # 架构图 (Mermaid/PlantUML 源文件)
└── tmp/                           # 临时工作文件 (不保证持久化)
```

### 10.4 Workspace Manager 实现

```typescript
// src/workspace/manager.ts
import { mkdir, writeFile, readFile, access, readdir } from "node:fs/promises";
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
  const basePath = config.workspacePath; // /mnt/workspace or /tmp/workspace
  let isAvailable = false;

  // 检测 persistent filesystem 是否可用 (仅 invocation 阶段可用，init 阶段不可用)
  try {
    await access(basePath);
    isAvailable = true;
  } catch {
    // 降级到临时目录
    console.log(`[workspace] ${basePath} not available, falling back to /tmp/workspace`);
  }

  const effectivePath = isAvailable ? basePath : "/tmp/workspace";

  // 确保目录结构存在
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
      const path = join(effectivePath, "artifacts", subdir, name);
      await writeFile(path, content, "utf-8");
      return path;
    },
  };
}
```

### 10.5 Skills 缓存策略

S3 sync 优先写入 persistent workspace（如果可用），避免冷启动重复下载：

```
首次调用 (workspace 为空):
  S3 → download → /mnt/workspace/.skills-cache/ → 加载到 agent

后续调用 (同 session resume):
  检查 .last-sync 时间戳
    → 如果 < 1 小时: 直接用缓存
    → 如果 >= 1 小时: 增量同步 S3 (仅下载变更)
```

### 10.6 对话历史持久化

```typescript
// HTTP handler 中的 session 续接逻辑
// POST /invocations
//   1. 尝试从 workspace 加载历史 messages
//   2. 合并客户端传入的 context (如果有)
//   3. 执行 agent
//   4. 执行完成后保存完整历史到 workspace
```

### 10.7 Persistent Filesystem 约束

| 约束 | 说明 |
|------|------|
| 仅 invocation 期间可用 | init/startup 阶段 mount path 不可用 |
| 不支持 hard links | 使用 symlinks 替代 |
| 不支持 device files/FIFO/socket | 纯文件操作 |
| 不支持 xattr | 不依赖扩展属性 |
| 14 天不活动自动清除 | 长期存储用 S3 |
| 版本更新后重置 | 部署新版本时 workspace 清空 |
| 权限存储但不强制 | agent 是 microVM 唯一用户 |

### 10.8 降级策略

```
if (persistent filesystem 可用):
  workspace = /mnt/workspace
  skills cache = /mnt/workspace/.skills-cache
  session history = /mnt/workspace/.session/history.jsonl
  artifacts = /mnt/workspace/artifacts/

else (fallback):
  workspace = /tmp/workspace
  skills cache = /tmp/workspace/.skills-cache   # 不跨 session 保留
  session history = 仅依赖客户端 context 传递
  artifacts = /tmp/workspace/artifacts/         # session 结束后丢失
```

---

## 11. 容器化与部署

### 11.1 Dockerfile

```dockerfile
# Build stage
FROM --platform=linux/arm64 node:20-slim AS builder

WORKDIR /app
COPY package.json package-lock.json tsconfig.json ./
RUN npm ci --production=false

COPY src/ src/
COPY skills/ skills/
RUN npm run build

# Prune dev dependencies
RUN npm prune --production

# Runtime stage
FROM --platform=linux/arm64 node:20-slim

# Install system tools needed by the agent
RUN apt-get update && apt-get install -y --no-install-recommends \
    curl \
    unzip \
    less \
    groff \
    net-tools \
    iproute2 \
    iputils-ping \
    traceroute \
    dnsutils \
    procps \
    jq \
    && rm -rf /var/lib/apt/lists/*

# Install AWS CLI v2 (ARM64)
RUN curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-aarch64.zip" -o "awscliv2.zip" \
    && unzip -q awscliv2.zip \
    && ./aws/install \
    && rm -rf aws awscliv2.zip

WORKDIR /app
COPY --from=builder /app/dist/ dist/
COPY --from=builder /app/node_modules/ node_modules/
COPY --from=builder /app/package.json .
COPY --from=builder /app/skills/ skills/

ENV NODE_ENV=production
EXPOSE 8080

CMD ["node", "dist/index.js"]
```

### 11.2 镜像大小预估

| 组件 | 大小 |
|------|------|
| Node.js 20 slim | ~180 MB |
| AWS CLI v2 | ~120 MB |
| System tools | ~50 MB |
| App + node_modules | ~80 MB |
| Skills | ~5 MB |
| **Total** | **~435 MB** |

> AgentCore 限制: Docker image ≤ 2 GB ✅

### 11.3 部署步骤

```bash
# 1. 构建 ARM64 镜像
docker buildx build --platform linux/arm64 -t aws-sa-agent:latest .

# 2. 推送到 ECR
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=us-west-2
ECR_URI=${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/aws-sa-agent

aws ecr get-login-password --region ${REGION} | docker login --username AWS --password-stdin ${ECR_URI}
aws ecr create-repository --repository-name aws-sa-agent --region ${REGION} || true
docker tag aws-sa-agent:latest ${ECR_URI}:latest
docker push ${ECR_URI}:latest

# 3. 创建 AgentCore Runtime
aws bedrock-agentcore-control create-agent-runtime \
  --agent-runtime-name "aws-sa-agent" \
  --agent-runtime-artifact '{
    "containerConfiguration": {
      "containerUri": "'${ECR_URI}':latest"
    }
  }' \
  --network-configuration '{"networkMode": "PUBLIC"}' \
  --role-arn "arn:aws:iam::${ACCOUNT_ID}:role/AgentCoreAwsSaAgentRole" \
  --filesystem-configurations '[{
    "sessionStorage": {
      "mountPath": "/mnt/workspace"
    }
  }]' \
  --lifecycle-configuration '{
    "idleRuntimeSessionTimeout": 600,
    "maxLifetime": 3600
  }' \
  --region ${REGION}
```

### 10.4 调用方式

```bash
# 同步调用 (HTTP, 15 min timeout)
aws bedrock-agentcore invoke-agent-runtime \
  --agent-runtime-arn "arn:aws:bedrock-agentcore:us-west-2:${ACCOUNT_ID}:runtime/aws-sa-agent-xxx" \
  --runtime-session-id "session-$(uuidgen)-$(date +%s)" \
  --payload '{"prompt": "Analyze my VPC configuration in us-east-1"}' \
  --qualifier DEFAULT \
  --region us-west-2
```

---

## 11. IAM 与安全

### 11.1 AgentCore Execution Role

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Sid": "BedrockModelInvocation",
      "Effect": "Allow",
      "Action": [
        "bedrock:InvokeModel",
        "bedrock:InvokeModelWithResponseStream"
      ],
      "Resource": "arn:aws:bedrock:*::foundation-model/anthropic.claude-sonnet-4-6-v1:0"
    },
    {
      "Sid": "S3SkillsRead",
      "Effect": "Allow",
      "Action": [
        "s3:GetObject",
        "s3:ListBucket"
      ],
      "Resource": [
        "arn:aws:s3:::${SKILLS_BUCKET}",
        "arn:aws:s3:::${SKILLS_BUCKET}/skills/*"
      ]
    },
    {
      "Sid": "CloudWatchLogs",
      "Effect": "Allow",
      "Action": [
        "logs:CreateLogGroup",
        "logs:CreateLogStream",
        "logs:PutLogEvents"
      ],
      "Resource": "arn:aws:logs:*:*:log-group:/aws/bedrock-agentcore/*"
    },
    {
      "Sid": "XRayTracing",
      "Effect": "Allow",
      "Action": [
        "xray:PutTraceSegments",
        "xray:PutTelemetryRecords"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ECRImagePull",
      "Effect": "Allow",
      "Action": [
        "ecr:GetDownloadUrlForLayer",
        "ecr:BatchGetImage",
        "ecr:GetAuthorizationToken"
      ],
      "Resource": "*"
    },
    {
      "Sid": "ReadOnlyAWSAccess",
      "Effect": "Allow",
      "Action": [
        "ec2:Describe*",
        "s3:Get*",
        "s3:List*",
        "rds:Describe*",
        "elasticloadbalancing:Describe*",
        "cloudwatch:GetMetricData",
        "cloudwatch:ListMetrics",
        "logs:FilterLogEvents",
        "logs:GetLogEvents",
        "iam:Get*",
        "iam:List*",
        "lambda:Get*",
        "lambda:List*",
        "ecs:Describe*",
        "ecs:List*",
        "ce:GetCostAndUsage",
        "ce:GetCostForecast",
        "route53:List*",
        "route53:Get*",
        "cloudfront:List*",
        "cloudfront:Get*",
        "sts:GetCallerIdentity"
      ],
      "Resource": "*"
    }
  ]
}
```

### 11.2 Trust Policy

```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Service": "bedrock-agentcore.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
```

### 11.3 安全层级

```
Layer 1: AgentCore microVM 隔离 (硬件级别)
Layer 2: IAM Execution Role (API 级别权限控制)
Layer 3: AWS CLI Tool 黑名单 (应用层阻止 destructive 操作)
Layer 4: afterToolCall Hook (输出敏感信息过滤)
Layer 5: Bash Tool 环境限制 (PATH 限制, HOME=/tmp)
```

---

## 12. 配置管理

```typescript
// src/config/index.ts

export interface Config {
  // Server
  port: number;

  // AWS
  awsRegion: string;

  // Model
  modelId: string;
  thinkingLevel: string;

  // Skills
  skillsLocalDir: string;
  skillsS3Bucket: string | undefined;
  skillsS3Prefix: string | undefined;

  // Safety
  blockedCommandPatterns: string[];
  maxCommandTimeout: number;
}

export function loadConfig(): Config {
  return {
    port: parseInt(process.env.PORT ?? "8080", 10),
    awsRegion: process.env.AWS_REGION ?? "us-west-2",
    modelId: process.env.MODEL_ID ?? "anthropic.claude-sonnet-4-6-v1:0",
    thinkingLevel: process.env.THINKING_LEVEL ?? "medium",
    skillsLocalDir: process.env.SKILLS_DIR ?? "/app/skills",
    skillsS3Bucket: process.env.SKILLS_S3_BUCKET ?? undefined,
    skillsS3Prefix: process.env.SKILLS_S3_PREFIX ?? "skills/",
    blockedCommandPatterns: (process.env.BLOCKED_PATTERNS ?? "").split(",").filter(Boolean),
    maxCommandTimeout: parseInt(process.env.MAX_COMMAND_TIMEOUT ?? "600000", 10),
  };
}
```

### 环境变量清单

| 变量 | 必须 | 默认值 | 说明 |
|------|------|--------|------|
| `AWS_REGION` | 否 | `us-west-2` | AWS 区域 |
| `MODEL_ID` | 否 | `anthropic.claude-sonnet-4-6-v1:0` | Bedrock 模型 ID |
| `THINKING_LEVEL` | 否 | `medium` | 推理深度 |
| `SKILLS_DIR` | 否 | `/app/skills` | 本地 skills 目录 |
| `SKILLS_S3_BUCKET` | 否 | - | S3 skills bucket |
| `SKILLS_S3_PREFIX` | 否 | `skills/` | S3 skills 前缀 |
| `MAX_COMMAND_TIMEOUT` | 否 | `600000` | 命令最大超时 (ms) |

---

## 13. 可观测性

### 13.1 日志

通过 Fastify logger 自动写入 stdout → AgentCore 转发到 CloudWatch Logs：

```
Log Group: /aws/bedrock-agentcore/runtimes/aws-sa-agent-xxx
```

日志格式（结构化 JSON）:
```json
{
  "level": "info",
  "time": 1743465600000,
  "msg": "[tool:preflight] aws_cli args={\"command\":\"ec2 describe-vpcs\"}"
}
```

### 13.2 Agent 事件追踪

通过 `agent.subscribe()` 记录完整的 agent 执行轨迹：

```typescript
agent.subscribe(async (event) => {
  switch (event.type) {
    case "agent_start":
      console.log("[agent] started");
      break;
    case "tool_execution_start":
      console.log(`[tool:start] ${event.toolName}`);
      break;
    case "tool_execution_end":
      console.log(`[tool:end] ${event.toolName} error=${event.isError}`);
      break;
    case "agent_end":
      console.log(`[agent] ended, ${event.messages.length} messages`);
      break;
  }
});
```

### 13.3 Metrics

利用 AgentCore 内置 CloudWatch metrics namespace `bedrock-agentcore`:

| Metric | 说明 |
|--------|------|
| `InvocationCount` | 调用次数 |
| `InvocationLatency` | 端到端延迟 |
| `SessionCount` | 活跃 session 数 |
| `ErrorCount` | 错误次数 |

自定义 metric (可选):
- `ToolExecutionCount` — 按 tool name 分组
- `TokenUsage` — LLM token 消耗
- `SkillsLoaded` — 加载的 skills 数量

---

## 14. 约束与限制

### 14.1 AgentCore Runtime 硬限制

| 约束 | 值 |
|------|-----|
| 架构 | linux/arm64 only |
| 镜像大小 | ≤ 2 GB |
| 每 session 资源 | 2 vCPU / 8 GB RAM |
| 同步请求超时 | 15 分钟 |
| 最大 payload | 100 MB |
| Session 最长生命周期 | 8 小时 |
| 默认空闲超时 | 15 分钟 |
| Session 存储 | 1 GB |
| 并发 sessions | 1,000 (us-east-1/us-west-2) |

### 14.2 本项目设计约束

| 约束 | 值 | 原因 |
|------|-----|------|
| Tool 执行模式 | sequential | AWS CLI 命令通常有依赖关系 |
| 破坏性操作 | 阻止 | Agent 仅做只读/诊断 |
| 交互模式 | 同步 HTTP | 单轮请求-响应 |
| 无 Session 持久化 | 每次调用独立 | 上下文由客户端传递 |

---

## 15. 项目结构

```
pi-on-agentcore/
├── docs/
│   └── TECH-SPEC.md              # 本文档
├── src/
│   ├── index.ts                   # 入口
│   ├── server.ts                  # Fastify HTTP server
│   ├── agent/
│   │   ├── factory.ts             # Agent 实例创建
│   │   ├── system-prompt.ts       # System prompt builder
│   │   └── hooks.ts               # beforeToolCall / afterToolCall
│   ├── tools/
│   │   ├── bash.ts                # Bash tool
│   │   └── aws-cli.ts             # AWS CLI tool
│   ├── skills/
│   │   ├── loader.ts              # SKILL.md 加载器
│   │   ├── s3-sync.ts             # S3 bucket 同步
│   │   └── renderer.ts            # Skills → prompt XML
│   └── config/
│       └── index.ts               # 配置
├── skills/                         # 内置 skills
│   ├── aws-networking/
│   │   └── SKILL.md
│   ├── aws-compute/
│   │   └── SKILL.md
│   ├── aws-security/
│   │   └── SKILL.md
│   └── ...
├── Dockerfile                     # ARM64 容器
├── package.json
├── tsconfig.json
├── deploy/
│   ├── iam-trust-policy.json
│   ├── iam-execution-policy.json
│   └── deploy.sh                  # ECR push + AgentCore create
└── README.md
```

---

## 16. 实施路线图

### Phase 1: 基础框架 (MVP)

- [ ] 项目初始化 (package.json, tsconfig.json)
- [ ] 安装依赖 (`@mariozechner/pi-agent-core`, `@mariozechner/pi-ai`, `fastify`, `@sinclair/typebox`)
- [ ] 实现 Config 模块
- [ ] 实现 Bash Tool
- [ ] 实现 AWS CLI Tool (含安全黑名单)
- [ ] 实现 System Prompt
- [ ] 实现 Agent Factory
- [ ] 实现 HTTP Server (`/ping` + `/invocations`)
- [ ] 本地测试 (直接 `node` 运行)

### Phase 2: Skills 系统

- [ ] 实现 SKILL.md 加载器
- [ ] 实现 Skills → prompt 渲染
- [ ] 编写核心 skills (networking, compute, security)
- [ ] 实现 S3 skills 同步
- [ ] Skills 集成到 agent system prompt

### Phase 3: 容器化与部署

- [ ] 编写 Dockerfile (ARM64 + AWS CLI)
- [ ] 本地 Docker 构建测试
- [ ] 编写 IAM policies
- [ ] 编写部署脚本
- [ ] ECR 推送
- [ ] AgentCore Runtime 创建与验证

### Phase 4: 加固与可观测性

- [ ] Safety hooks 完善 (敏感信息过滤)
- [ ] Agent 事件日志
- [ ] CloudWatch metrics 集成
- [ ] 错误处理 & 重试
- [ ] 端到端测试

---

## 附录 A: 关键 API 参考

### pi-agent-core Agent 生命周期

```
agent.prompt(msg)
  → agent_start
  → turn_start
  → message_start → message_update* → message_end
  → [tool_execution_start → tool_execution_update* → tool_execution_end]*
  → turn_end
  → (如有 tool_use 继续下一个 turn)
  → agent_end
```

### pi-ai Bedrock 认证

```
pi-ai 使用 AWS SDK 默认凭证链:
1. 环境变量 (AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY)
2. 共享凭证文件 (~/.aws/credentials)
3. ECS 容器凭证
4. EC2/AgentCore 实例角色 ← AgentCore Runtime 使用此方式
```

### AgentCore Service Contract

```
POST /invocations
  Request:  { prompt: string, context?: Message[] }
  Response: { result: string, messages: Message[], usage: Usage | null }

GET /ping
  Response: { status: "healthy" } (200 OK)
```

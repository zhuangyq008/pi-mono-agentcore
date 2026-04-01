export interface Config {
  port: number;
  awsRegion: string;
  modelId: string;
  inferenceProfileId: string | undefined;
  thinkingLevel: string;
  skillsLocalDir: string;
  skillsS3Bucket: string | undefined;
  skillsS3Prefix: string | undefined;
  workspacePath: string;
  blockedCommandPatterns: string[];
  maxCommandTimeout: number;
}

export function loadConfig(): Config {
  return {
    port: parseInt(process.env.PORT ?? "8080", 10),
    awsRegion: process.env.AWS_REGION ?? "us-west-2",
    modelId: process.env.MODEL_ID ?? "anthropic.claude-sonnet-4-6",
    inferenceProfileId: process.env.INFERENCE_PROFILE_ID ?? "us.anthropic.claude-sonnet-4-6",
    thinkingLevel: process.env.THINKING_LEVEL ?? "medium",
    skillsLocalDir: process.env.SKILLS_DIR ?? "/app/skills",
    skillsS3Bucket: process.env.SKILLS_S3_BUCKET ?? undefined,
    skillsS3Prefix: process.env.SKILLS_S3_PREFIX ?? "skills/",
    workspacePath: process.env.WORKSPACE_PATH ?? "/mnt/workspace",
    blockedCommandPatterns: (process.env.BLOCKED_PATTERNS ?? "").split(",").filter(Boolean),
    maxCommandTimeout: parseInt(process.env.MAX_COMMAND_TIMEOUT ?? "600000", 10),
  };
}

import {
  S3Client,
  ListObjectsV2Command,
  GetObjectCommand,
} from "@aws-sdk/client-s3";
import { mkdir, writeFile, readFile } from "node:fs/promises";
import { join, dirname } from "node:path";
import type { Config } from "../config/index.js";

interface SyncOptions {
  cacheDir?: string;
  maxAgeMs?: number;
}

export async function syncSkillsFromS3(
  config: Config,
  options: SyncOptions = {},
): Promise<string[]> {
  if (!config.skillsS3Bucket) return [];

  const cacheDir = options.cacheDir ?? join(config.skillsLocalDir, "..", ".skills-cache");
  const maxAgeMs = options.maxAgeMs ?? 3600_000; // 1 hour default

  // Check if cache is fresh enough
  const lastSyncPath = join(cacheDir, ".last-sync");
  try {
    const lastSync = await readFile(lastSyncPath, "utf-8");
    const elapsed = Date.now() - parseInt(lastSync, 10);
    if (elapsed < maxAgeMs) {
      console.log(`[skills] S3 cache fresh (${Math.round(elapsed / 1000)}s old), skipping sync`);
      return [];
    }
  } catch {
    // No cache or invalid — proceed with sync
  }

  const s3 = new S3Client({ region: config.awsRegion });
  const prefix = config.skillsS3Prefix ?? "skills/";
  const syncedPaths: string[] = [];

  try {
    const listResult = await s3.send(
      new ListObjectsV2Command({
        Bucket: config.skillsS3Bucket,
        Prefix: prefix,
      })
    );

    for (const obj of listResult.Contents ?? []) {
      if (!obj.Key?.endsWith("SKILL.md") && !obj.Key?.endsWith(".md")) continue;

      const relativePath = obj.Key.slice(prefix.length);
      const localPath = join(cacheDir, relativePath);

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

    // Update last sync timestamp
    await mkdir(cacheDir, { recursive: true });
    await writeFile(lastSyncPath, Date.now().toString(), "utf-8");

    console.log(`[skills] Synced ${syncedPaths.length} skills from s3://${config.skillsS3Bucket}/${prefix}`);
  } catch (err) {
    console.error(`[skills] S3 sync failed:`, err);
  }

  return syncedPaths;
}

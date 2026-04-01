import { readdir, readFile } from "node:fs/promises";
import { join, basename } from "node:path";
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
      if (seen.has(skill.name)) continue;
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

    const hasSkillMd = entries.some((e) => e.isFile() && e.name === "SKILL.md");
    if (hasSkillMd) {
      const skill = await parseSkillFile(join(dir, "SKILL.md"), dir);
      if (skill) skills.push(skill);
      return skills;
    }

    for (const entry of entries) {
      if (entry.name.startsWith(".") || entry.name === "node_modules") continue;
      if (entry.isDirectory()) {
        skills.push(...(await scanDir(join(dir, entry.name))));
      }
    }
  } catch {
    // Directory doesn't exist or no permissions — silently skip
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
  if (!description) return null;

  return {
    name,
    description,
    content,
    filePath,
    disableModelInvocation: frontmatter["disable-model-invocation"] ?? false,
  };
}

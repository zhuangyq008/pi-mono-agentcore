import type { Skill } from "./loader.js";

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

import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { randomUUID } from "node:crypto";
import type { ExtensionAPI } from "@earendil-works/pi-coding-agent";

const levels = ["off", "minimal", "low", "medium", "high", "xhigh", "max"];
type Preset = { model: string; thinkingLevel: string };
type Config = { defaultProfile: string; profiles: Record<string, Preset> };
const settingsPath = join(homedir(), ".pi/agent/subagents.json");

async function load(): Promise<Config> {
  let value;
  try {
    value = JSON.parse(await readFile(settingsPath, "utf8"));
  } catch (error) {
    if ((error as NodeJS.ErrnoException).code === "ENOENT") return { defaultProfile: "", profiles: {} };
    throw error;
  }
  // Keep the old single-model configuration until the user saves a preset.
  if (typeof value?.model === "string") {
    value = { defaultProfile: "legacy", profiles: { legacy: { model: value.model, thinkingLevel: value.thinkingLevel ?? "off" } } };
  }
  if (!value || typeof value.defaultProfile !== "string" || !value.profiles || typeof value.profiles !== "object" || Array.isArray(value.profiles)) {
    throw new Error(`Invalid ${settingsPath}`);
  }
  for (const preset of Object.values(value.profiles) as Preset[]) {
    if (!preset || typeof preset.model !== "string" || !/^[^/\s]+\/\S+$/.test(preset.model) || !levels.includes(preset.thinkingLevel)) {
      throw new Error(`Invalid subagent preset in ${settingsPath}`);
    }
  }
  if (Object.keys(value.profiles).length && !Object.hasOwn(value.profiles, value.defaultProfile)) {
    throw new Error("Missing or unknown default subagent profile");
  }
  return value;
}

async function save(config: Config): Promise<void> {
  await mkdir(dirname(settingsPath), { recursive: true });
  const temporary = `${settingsPath}.${randomUUID()}.tmp`;
  await writeFile(temporary, JSON.stringify(config, null, 2) + "\n", { mode: 0o600 });
  await rename(temporary, settingsPath);
}

export default function (pi: ExtensionAPI) {
  if (process.env.PI_SUBAGENT_ROLE === "child") return;
  pi.on("session_start", async (_event, ctx) => {
    if (!ctx.hasUI) return;
    try {
      const config = await load();
      if (!Object.keys(config.profiles).length) {
        ctx.ui.notify("No subagent profiles configured. Run /subagents to add presets and choose a default.", "warning");
      }
    } catch (error) {
      ctx.ui.notify(`Invalid ${settingsPath}: ${error instanceof Error ? error.message : String(error)}. Fix the file, then run /subagents.`, "warning");
    }
  });
  pi.registerCommand("subagents", {
    description: "Configure shared subagent model presets and default",
    handler: async (_args, ctx) => {
      if (!ctx.hasUI) return;
      try {
        const config = await load();
        while (true) {
          const names = Object.keys(config.profiles);
          const entries = names.map((name) => {
            const preset = config.profiles[name];
            return `${name}${name === config.defaultProfile ? " (default)" : ""}: ${preset.model} · ${preset.thinkingLevel}`;
          });
          const action = await ctx.ui.select("Subagent presets — shared across Pi profiles", [...entries, "Add preset", "Set default", "Done"]);
          if (!action || action === "Done") return;
          if (action === "Set default") {
            const name = await ctx.ui.select("Default subagent preset", names);
            if (!name) continue;
            config.defaultProfile = name;
          } else {
            const name = action === "Add preset"
              ? (await ctx.ui.input("Preset name (e.g. light or deep)"))?.trim()
              : names[entries.indexOf(action)];
            if (!name) continue;
            if (!/^[a-zA-Z0-9_-]+$/.test(name) || ["__proto__", "constructor", "prototype"].includes(name)) {
              ctx.ui.notify("Use letters, numbers, underscores or hyphens", "error");
              continue;
            }
            // Explicit provider IDs distinguish upstream Codex from Codex Auto.
            const models = [...new Set(ctx.modelRegistry.getAll().map((model) => `${model.provider}/${model.id}`))].sort();
            const model = await ctx.ui.select(`Model for ${name}`, models);
            if (!model) continue;
            const thinkingLevel = await ctx.ui.select(`Thinking level for ${name}`, levels);
            if (!thinkingLevel) continue;
            config.profiles[name] = { model, thinkingLevel };
            if (!config.defaultProfile) config.defaultProfile = name;
          }
          await save(config);
          ctx.ui.notify(`Saved ${settingsPath}. Applies to future subagent launches.`, "info");
        }
      } catch (error) {
        ctx.ui.notify(error instanceof Error ? error.message : String(error), "error");
      }
    },
  });
}

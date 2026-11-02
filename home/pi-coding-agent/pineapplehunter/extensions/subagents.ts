import { mkdir, readFile, rename, writeFile } from "node:fs/promises";
import { dirname, join } from "node:path";
import { randomUUID } from "node:crypto";
import { DynamicBorder, type ExtensionAPI, type ExtensionContext } from "@earendil-works/pi-coding-agent";
import { fuzzyFilter, Input, SelectList, truncateToWidth } from "@earendil-works/pi-tui";

const levels = ["off", "minimal", "low", "medium", "high", "xhigh", "max"];
type Preset = { model: string; thinkingLevel: string };
type Config = { defaultProfile: string; profiles: Record<string, Preset> };
const agentDir = process.env.PI_CODING_AGENT_DIR;
if (!agentDir) throw new Error("PI_CODING_AGENT_DIR is required for subagent configuration");
const settingsPath = join(agentDir, "subagents.json");

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

async function selectModel(ctx: ExtensionContext, name: string, current?: string): Promise<string | undefined> {
  // RPC clients cannot render a custom terminal component.
  if (ctx.mode !== "tui") {
    const query = await ctx.ui.input(`Filter models for ${name}`, "Provider, model ID or name");
    if (query === undefined) return undefined;
    const matches = fuzzyFilter(ctx.modelRegistry.getAvailable(), query, (model) => `${model.provider}/${model.id} ${model.name}`);
    return ctx.ui.select(`Model for ${name}`, matches.map((model) => `${model.provider}/${model.id}`));
  }
  const models = ctx.modelRegistry.getAvailable().map((model) => ({
    value: `${model.provider}/${model.id}`,
    label: `${model.id} [${model.provider}]`,
    search: `${model.provider}/${model.id} ${model.name}`,
  })).sort((a, b) => a.value.localeCompare(b.value));
  return ctx.ui.custom<string | undefined>((tui, theme, kb, done) => {
    const input = new Input();
    const border = new DynamicBorder((text) => theme.fg("accent", text));
    let filtered = models;
    let visible = 0;
    let list: SelectList;
    const buildList = () => {
      visible = Math.max(1, Math.min(10, tui.terminal.rows - 7));
      list = new SelectList(filtered, visible, {
        selectedPrefix: (text) => theme.fg("accent", text),
        selectedText: (text) => theme.fg("accent", text),
        description: (text) => theme.fg("muted", text),
        scrollInfo: (text) => theme.fg("dim", text),
        noMatch: (text) => theme.fg("warning", text),
      });
      list.onSelect = (item) => done(item.value);
      list.onCancel = () => done(undefined);
    };
    buildList();
    list.setSelectedIndex(Math.max(0, models.findIndex((model) => model.value === current)));
    return {
      get focused() { return input.focused; },
      set focused(value: boolean) { input.focused = value; },
      render(width: number) {
        if (visible !== Math.max(1, Math.min(10, tui.terminal.rows - 7))) {
          const selected = list.getSelectedItem()?.value;
          buildList();
          list.setSelectedIndex(Math.max(0, filtered.findIndex((model) => model.value === selected)));
        }
        return [
          ...border.render(width),
          theme.fg("accent", `Model for ${name} — type to filter`),
          ...input.render(width),
          ...(filtered.length ? list.render(width) : [theme.fg("warning", "  No matching models")]),
          theme.fg("dim", "↑↓ navigate · enter select · esc cancel"),
          ...border.render(width),
        ].map((line) => truncateToWidth(line, width));
      },
      invalidate() { input.invalidate(); list.invalidate(); border.invalidate(); },
      handleInput(data: string) {
        if ((["tui.select.up", "tui.select.down", "tui.select.confirm", "tui.select.cancel"] as const).some((key) => kb.matches(data, key))) {
          list.handleInput(data);
        } else {
          input.handleInput(data);
          filtered = fuzzyFilter(models, input.getValue(), (model) => model.search);
          buildList();
        }
        tui.requestRender();
      },
    };
  });
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
          const action = await ctx.ui.select("Subagent presets — shared across Pi profiles", [
            ...entries, "Add preset", ...(names.length ? ["Set default", "Delete preset"] : []), "Done",
          ]);
          if (!action || action === "Done") return;
          if (action === "Set default") {
            const name = await ctx.ui.select("Default subagent preset", names);
            if (!name) continue;
            config.defaultProfile = name;
          } else if (action === "Delete preset") {
            const name = await ctx.ui.select("Delete subagent preset", names);
            if (!name || !await ctx.ui.confirm("Delete preset?", `Delete "${name}"? This affects future launches, not existing agents.`)) continue;
            const remaining = names.filter((entry) => entry !== name);
            let defaultProfile = config.defaultProfile;
            if (name === defaultProfile) {
              const replacement = remaining.length
                ? await ctx.ui.select("Choose replacement default", remaining)
                : "";
              if (replacement === undefined) continue;
              defaultProfile = replacement;
            }
            delete config.profiles[name];
            config.defaultProfile = defaultProfile;
          } else {
            const name = action === "Add preset"
              ? (await ctx.ui.input("Preset name (e.g. light or deep)"))?.trim()
              : names[entries.indexOf(action)];
            if (!name) continue;
            if (!/^[a-zA-Z0-9_-]+$/.test(name) || ["__proto__", "constructor", "prototype"].includes(name)) {
              ctx.ui.notify("Use letters, numbers, underscores or hyphens", "error");
              continue;
            }
            const model = await selectModel(ctx, name, config.profiles[name]?.model);
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

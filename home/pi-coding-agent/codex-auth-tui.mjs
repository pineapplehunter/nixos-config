import { spawn } from "node:child_process";
import { existsSync } from "node:fs";
import { readFile } from "node:fs/promises";
import { join } from "node:path";
import { decodeKittyPrintable, Input, Key, matchesKey, ProcessTerminal, SelectList, Text, TuiAltScreen, truncateToWidth } from "@PI_TUI@";

const [cli, state] = process.argv.slice(2);
const accounts = ["personal", "work"];
const names = { personal: "Personal", work: "Work", off: "Off" };
const style = (open, close) => (text) => process.env.NO_COLOR === undefined ? `\x1b[${open}m${text}\x1b[${close}m` : text;
const bold = style(1, 22);
const muted = style(2, 22);
const focus = style(7, 27);
const listTheme = { selectedPrefix: bold, selectedText: focus, description: muted, scrollInfo: muted, noMatch: muted };
const item = (value, label) => ({ value, label });
const text = (value) => new Text(value, 0, 0);

class ReserveInput extends Input {
  handleInput(data) {
    if (data.startsWith("\x1b[200~")) {
      // A reserve only needs decimal digits. Don't echo unrelated clipboard text.
      if (!/^\x1b\[200~\s*[0-9.]+\s*\x1b\[201~$/.test(data)) return;
    } else {
      const key = decodeKittyPrintable(data) ?? data;
      if (!/^[0-9.]$/.test(key) && !/^[\x00-\x1f\x7f]/.test(key)) return;
    }
    super.handleInput(data);
  }
}

// Only accept the known status/exit-code pairs. Never render subprocess diagnostics.
async function accountStatus(scope, account) {
  const { code, output } = await run([scope === "chat" ? "status" : "image-status", account], { status: true });
  if (scope === "chat") {
    if (code === 0 && output === "ready") return "Ready";
    if (code === 1 && output === "not_ready") return "Not ready";
  } else {
    if (code === 0 && output === "configured") return "Configured";
    if (code === 1 && output === "not configured") return "Not configured";
  }
  return "Unavailable";
}

async function setting(file, fallback, valid) {
  try {
    const value = (await readFile(join(state, file), "utf8")).trim();
    return valid(value) ? value : undefined;
  } catch (error) {
    return error.code === "ENOENT" ? fallback : undefined;
  }
}

const decimal = (value) => /^(?:100|[0-9]{1,2})(?:\.\d+)?$/.test(value) && Number(value) <= 100;

async function snapshot() {
  const [personalChat, workChat, personalImages, workImages, route, reserve] = await Promise.all([
    ...accounts.map((account) => accountStatus("chat", account)),
    ...accounts.map((account) => accountStatus("images", account)),
    setting("image-account", "work", (value) => Object.hasOwn(names, value)),
    setting("reserve", "15", decimal),
  ]);
  return {
    chat: { personal: personalChat, work: workChat },
    images: { personal: personalImages, work: workImages },
    route,
    reserve,
  };
}

let oauth;
function run(args, { interactive = false, status = false } = {}) {
  return new Promise((resolve) => {
    const child = spawn(cli, args, {
      stdio: interactive ? "inherit" : ["ignore", status ? "pipe" : "ignore", "ignore"],
    });
    if (interactive) oauth = child;
    let output = "";
    child.stdout?.setEncoding("utf8").on("data", (chunk) => {
      if (output.length <= 128) output += chunk.slice(0, 129 - output.length);
    });
    const timer = status ? setTimeout(() => child.kill("SIGKILL"), 8_000) : undefined;
    child.once("error", () => resolve({}));
    child.once("close", (code, signal) => {
      if (interactive) oauth = undefined;
      clearTimeout(timer);
      resolve({ code, signal, output: output.trim() });
    });
  });
}

async function dashboard() {
  // No terminal transcripts, even if Pi's diagnostics are enabled in the environment.
  delete process.env.PI_TUI_WRITE_LOG;
  const terminal = new ProcessTerminal();
  const tui = new TuiAltScreen(terminal, false, undefined, { mouse: false });
  let running = false;
  let shuttingDown = false;
  let interruptedLogin = false;
  let data;
  let feedback = "";

  function start() {
    running = true;
    tui.start();
  }

  function stop() {
    if (!running) return;
    tui.stop({ preserveScreen: true });
    running = false;
  }

  function interrupt() {
    // In cooked mode the foreground process group also receives SIGINT. Let the
    // auth child handle it and return here; don't forward a second interrupt.
    if (oauth) {
      interruptedLogin = true;
      return;
    }
    stop();
    process.exit(130);
  }

  function terminate() {
    if (oauth) {
      shuttingDown = true;
      oauth.kill("SIGINT");
      return;
    }
    stop();
    process.exit(143);
  }

  const header = {
    invalidate() {},
    render(width) {
      const heading = bold("Codex host authentication");
      if (!data) return [truncateToWidth(heading, width)];
      const route = data.route ? names[data.route] : "Invalid (off)";
      const reserve = data.reserve === undefined ? "Invalid" : `${data.reserve}%`;
      const settings = [`Image route: ${bold(route)}`, `Auto reserve: ${bold(reserve)}`];
      const lines = [heading];
      // Keep actions visible on short terminals. On narrow terminals use one line per slot.
      if (terminal.rows >= 16) {
        if (width >= 44) {
          lines.push(muted("            Chat          Images"));
          for (const account of accounts) {
            lines.push(`${names[account].padEnd(12)}${data.chat[account].padEnd(14)}${data.images[account]}`);
          }
        } else {
          for (const account of accounts) {
            lines.push(`${names[account]} chat: ${data.chat[account]}`, `${names[account]} images: ${data.images[account]}`);
          }
        }
      }
      lines.push(...(width >= 56 ? [settings.join("    ")] : settings));
      return lines.map((line) => truncateToWidth(line, width));
    },
  };

  function show(title, control, hint) {
    tui.setFocus(null);
    tui.clear();
    tui.addChild(header);
    tui.addChild(text(`\n${bold(title)}`));
    if (control) {
      tui.addChild(control);
      tui.setFocus(control);
    }
    if (control && feedback) tui.addChild(text(feedback));
    if (hint) tui.addChild(text(muted(hint)));
    tui.requestRender();
  }

  function interact(title, widget, hint, bind, shortcut) {
    return new Promise((resolve) => {
      const remove = tui.addInputListener((key) => {
        const choice = shortcut?.(key);
        if (choice !== undefined) {
          done(choice);
          return { consume: true };
        }
      });
      function done(value) {
        remove();
        tui.setFocus(null);
        resolve(value);
      }
      bind(done);
      show(title, widget, hint);
    });
  }

  function choose(title, items, { index = 0, hint = "↑/↓ move   Enter select   Esc back", shortcut } = {}) {
    const list = new SelectList(items, items.length, listTheme);
    list.setSelectedIndex(index);
    return interact(title, list, hint, (done) => {
      list.onSelect = (choice) => done(choice.value);
      list.onCancel = () => done();
    }, shortcut);
  }

  const confirm = async (title, action) => (await choose(title, [item("cancel", "Cancel"), item("confirm", action)])) === "confirm";

  async function refresh() {
    show("Checking local sign-ins…");
    data = await snapshot();
  }

  async function manageAccount(scope, account) {
    const label = `${names[account]} ${scope}`;
    const command = scope === "chat" ? "" : "image-";
    const choice = await choose(`${label}: ${data[scope][account]}`, [
      item("login", "Sign in with OAuth"), item("logout", "Remove sign-in"),
    ]);
    if (choice === "logout" && await confirm(`Remove ${label} sign-in?`, "Remove sign-in")) {
      const { code } = await run([`${command}logout`, account]);
      feedback = code === 0 ? `Removed ${label} sign-in.` : `Could not remove ${label} sign-in.`;
      await refresh();
    }
    if (choice === "login") {
      await terminal.drainInput(200, 30);
      stop();
      interruptedLogin = false;
      let result;
      try {
        console.log(`Signing in: ${label}`);
        result = await run([`${command}login`, account], { interactive: true });
      } finally {
        if (!shuttingDown) start();
      }
      if (shuttingDown) return;
      feedback = result.code === 0 ? `Finished ${label} sign-in.`
        : interruptedLogin || result.code === 130 || result.signal === "SIGINT" ? `Cancelled ${label} sign-in.`
          : `${label} sign-in did not complete. See the sign-in prompt in terminal scrollback.`;
      await refresh();
    }
  }

  async function editRoute() {
    const items = ["work", "personal", "off"].map((value) => item(value, names[value]));
    const route = await choose("Route image requests to", items, { index: items.findIndex(({ value }) => value === data.route) });
    if (!route) return;
    const { code } = await run(["images", route]);
    feedback = code !== 0 ? "Could not save the image route."
      : route === "off" ? "Image routing is off. Sign-ins are unchanged."
        : `Image requests now route to ${names[route]}.`;
    await refresh();
  }

  async function editReserve() {
    const input = new ReserveInput({ placeholder: "0–100", placeholderStyle: muted });
    while (true) {
      const value = await interact("Auto reserve for Personal (%)", input, "Enter save   Esc cancel", (done) => {
        input.onSubmit = done;
        input.onEscape = () => done();
      });
      if (value === undefined) return;
      const { code } = await run(["reserve", value.trim()]);
      if (code === 2) {
        feedback = "Enter a number from 0 to 100.";
        continue;
      }
      feedback = code === 0 ? "Saved the Auto reserve." : "Could not save the Auto reserve.";
      await refresh();
      return;
    }
  }

  const actions = [
    ...["chat", "images"].flatMap((scope) => accounts.map((account) => item(`${scope}:${account}`, `${names[account]} ${scope}`))),
    item("route", "Set image route"), item("reserve", "Edit Auto reserve"),
  ];
  let index = 0;

  process.on("SIGINT", interrupt);
  process.on("SIGTERM", terminate);
  try {
    start();
    await refresh();
    while (!shuttingDown) {
      const action = await choose("Manage", actions, {
        index,
        hint: "↑/↓ move   Enter open   r refresh   Esc quit",
        shortcut: (key) => matchesKey(key, Key.escape) || matchesKey(key, "q") ? "quit"
          : matchesKey(key, "r") ? "refresh" : undefined,
      });
      feedback = "";
      if (!action || action === "quit") return 0;
      if (action === "refresh") {
        await refresh();
        feedback = "Refreshed local sign-in status.";
        continue;
      }
      index = actions.findIndex(({ value }) => value === action);
      if (action === "route") await editRoute();
      else if (action === "reserve") await editReserve();
      else await manageAccount(...action.split(":"));
    }
    return 143;
  } finally {
    stop();
    process.off("SIGINT", interrupt);
    process.off("SIGTERM", terminate);
  }
}

if (existsSync("/.flatpak-info") || existsSync("/run/pi-subagent")) {
  console.error("Run pi-codex-auth in a host terminal, not inside Pi.");
  process.exitCode = 1;
} else {
  try {
    process.exitCode = await dashboard();
  } catch {
    console.error("Could not open the Codex host dashboard. Use pi-codex-auth status to check sign-ins.");
    process.exitCode = 1;
  }
}

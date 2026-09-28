import { execFile } from "node:child_process";
import * as crypto from "node:crypto";
import * as fs from "node:fs";
import * as path from "node:path";
import { fileURLToPath } from "node:url";
import { promisify } from "node:util";
import type { ExtensionAPI, ExtensionContext } from "@earendil-works/pi-coding-agent";
import { Type } from "typebox";

const execFileAsync = promisify(execFile);

// Types

export interface SubagentPaths {
	projectPath: string;
	statePath: string;
	baselinePath: string;
	workspacePath: string;
	tmpPath: string;
	sessionsPath: string;
	promptPath: string;
	responsePath: string;
	stdoutPath: string;
	taskIdPath: string;
	bwrapInfoPath: string;
	queuedPath: string;
}

export interface SubagentState extends SubagentPaths {
	name: string;
	sessionId: string;
	turnId: number;
	pueueTaskId?: number;
	model?: string;
	thinkingLevel?: string;
	trustedProject: boolean;
}

export interface RunContext {
	runPath: string;
	projectPath: string;
}

export interface StartOptions {
	name: string;
	task: string;
	model?: string;
	thinkingLevel?: string;
	trustedProject: boolean;
}

// Snapshots

const CP = "@coreutilsCp@";
const NAME_PATTERN = /^[a-z0-9][a-z0-9-]{0,62}$/;

export function validateSubagentName(name: string): void {
	if (!NAME_PATTERN.test(name)) {
		throw new Error("Invalid subagent name. Use 1-63 lowercase letters, digits, or hyphens, starting with a letter or digit.");
	}
}

export function pathsFor(run: RunContext, name: string): SubagentPaths {
	const statePath = path.join(run.runPath, name);
	return {
		projectPath: run.projectPath,
		statePath,
		baselinePath: path.join(statePath, "baseline"),
		workspacePath: path.join(statePath, "workspace"),
		tmpPath: path.join(statePath, "tmp"),
		sessionsPath: path.join(statePath, "sessions"),
		promptPath: path.join(statePath, "prompt.md"),
		responsePath: path.join(statePath, "response.md"),
		stdoutPath: path.join(statePath, "stdout.log"),
		taskIdPath: path.join(statePath, "task-id"),
		bwrapInfoPath: path.join(statePath, "bwrap-info.json"),
		queuedPath: path.join(statePath, "queued"),
	};
}

export async function createSnapshot(run: RunContext, name: string, prompt: string): Promise<SubagentPaths> {
	validateSubagentName(name);
	const paths = pathsFor(run, name);
	try {
		fs.mkdirSync(paths.statePath, { mode: 0o700 });
		for (const directory of [
			paths.baselinePath,
			paths.workspacePath,
			paths.tmpPath,
			paths.sessionsPath,
		]) {
			fs.mkdirSync(directory, { mode: 0o700 });
		}
		await execFileAsync(CP, ["-a", "--reflink=always", `${run.projectPath}/.`, `${paths.baselinePath}/`]);
		await execFileAsync(CP, ["-a", "--reflink=always", `${paths.baselinePath}/.`, `${paths.workspacePath}/`]);
		fs.writeFileSync(paths.promptPath, prompt, { encoding: "utf8", mode: 0o600 });
		fs.writeFileSync(paths.responsePath, "", { encoding: "utf8", mode: 0o600 });
		fs.writeFileSync(paths.stdoutPath, "", { encoding: "utf8", mode: 0o600 });
		return paths;
	} catch (error) {
		fs.rmSync(paths.statePath, { recursive: true, force: true });
		const detail = error instanceof Error ? error.message : String(error);
		throw new Error(`Could not create the snapshot for ${name}. Check that the project and /tmp are on the same reflink-capable filesystem, then retry. ${detail}`);
	}
}

// Pueue submission

const BASH = "@bash@";
const BWRAP = "@bubblewrap@";
const PI = "@pi@";
const PUEUE = "@pueue@";
const EXTENSION = fileURLToPath(import.meta.url);
const RUN_SCRIPT = 'info=$1; queued=$2; shift 2; exec 3>"$info"; rm -f "$queued"; exec "$@"';
const LAUNCH_SCRIPT = `
pi=$1
response=$2
output=$3
shift 3
exec </dev/null
mkdir -p /run/pi-pueue
chmod 700 /run/pi-pueue
if ! pueue status >/dev/null 2>&1; then
  rm -f /run/pi-pueue/pueue.pid /run/pi-pueue/pueue.socket
  pueued -d >/dev/null
  for _ in $(seq 1 50); do
    pueue status >/dev/null 2>&1 && break
    sleep 0.1
  done
fi
if "$pi" "$@" >/run/pi-subagent/stdout.log 2>&1; then
  printf 'The subagent has run successfully. The response can be found at \`%s\`.\\n' "$response"
else
  status=$?
  printf 'The subagent failed. Its output can be found at \`%s\`.\\n' "$output" >&2
  exit "$status"
fi
`;

export async function launchTask(state: SubagentState): Promise<number> {
	const args = [
		"--info-fd", "3",
		"--die-with-parent",
		"--unshare-pid",
		"--bind", "/", "/",
		"--proc", "/proc",
		"--dev-bind", "/dev", "/dev",
		"--tmpfs", "/run",
		"--dir", "/run/pi-pueue",
		"--dir", "/run/pi-subagent",
		"--bind", state.workspacePath, state.projectPath,
		"--bind", state.sessionsPath, "/run/pi-subagent/sessions",
		"--ro-bind", state.promptPath, "/run/pi-subagent/prompt.md",
		"--bind", state.responsePath, "/run/pi-subagent/response.md",
		"--bind", state.stdoutPath, "/run/pi-subagent/stdout.log",
		"--bind", state.tmpPath, "/tmp",
		"--setenv", "PI_SUBAGENT_ROLE", "child",
		"--setenv", "PI_CODING_AGENT_SESSION_DIR", "/run/pi-subagent/sessions",
		"--setenv", "TMPDIR", "/tmp",
		"--chdir", state.projectPath,
		"--",
		BASH,
		"-c",
		LAUNCH_SCRIPT,
		"subagent-launch",
		PI,
		state.responsePath,
		state.stdoutPath,
		"--print",
		"--extension", EXTENSION,
		"--session-dir", "/run/pi-subagent/sessions",
		"--session-id", state.sessionId,
		"--name", `subagent: ${state.name}`,
		state.trustedProject ? "--approve" : "--no-approve",
	];
	if (state.model) args.push("--model", state.model);
	if (state.thinkingLevel) args.push("--thinking", state.thinkingLevel);
	args.push("@/run/pi-subagent/prompt.md");

	try {
		fs.writeFileSync(state.queuedPath, "", { mode: 0o600 });
	} catch (error) {
		const detail = error instanceof Error ? error.message : String(error);
		throw new Error(`Could not create the queued marker for ${state.name}. Inspect \`${state.statePath}\`, fix its permissions, then retry. ${detail}`);
	}

	let stdout: string;
	try {
		({ stdout } = await execFileAsync(PUEUE, [
			"add",
			"--immediate",
			"--group", "subagent",
			"--label", `${state.name}:turn-${state.turnId}`,
			"--working-directory", state.projectPath,
			"--print-task-id",
			"--escape",
			BASH,
			"-c",
			RUN_SCRIPT,
			"subagent-run",
			state.bwrapInfoPath,
			state.queuedPath,
			BWRAP,
			...args,
		], { encoding: "utf8", maxBuffer: 4 * 1024 * 1024 }));
	} catch (error) {
		fs.rmSync(state.queuedPath, { force: true });
		const value = error as Error & { stderr?: string };
		const detail = value.stderr?.trim() || value.message;
		throw new Error(`Could not submit ${state.name} to Pueue. Run \`pueue status --group subagent\` and ensure \`subagents_enable\` created the group, then retry. ${detail}`);
	}
	const taskId = Number.parseInt(stdout.trim(), 10);
	if (!Number.isSafeInteger(taskId) || taskId < 0) {
		throw new Error(`Pueue returned an invalid task ID for ${state.name}. Run \`pueue status --group subagent\` to inspect the submission before retrying. Output: ${stdout.trim()}`);
	}
	try {
		fs.writeFileSync(state.taskIdPath, `${taskId}\n`, { encoding: "utf8", mode: 0o600 });
	} catch (error) {
		const detail = error instanceof Error ? error.message : String(error);
		throw new Error(`Pueue task ${taskId} was submitted, but its ID could not be written to \`${state.taskIdPath}\`. Use that task ID directly and fix the state-directory permissions before the next turn. ${detail}`);
	}
	return taskId;
}

// Supervisor

const RUN_ROOT = "/tmp/pi-subagents";

export class SubagentSupervisor {
	private run?: RunContext;
	private states = new Map<string, SubagentState>();

	initialize(ctx: ExtensionContext): void {
		if (this.run) return;
		const runPath = RUN_ROOT;
		const projectPath = fs.realpathSync(ctx.cwd);
		try {
			fs.mkdirSync(runPath, { recursive: true, mode: 0o700 });
		} catch (error) {
			const detail = error instanceof Error ? error.message : String(error);
			throw new Error(`Could not create the subagent directory. Check that \`${RUN_ROOT}\` is writable, then reload Pi. ${detail}`);
		}
		this.run = { runPath, projectPath };
	}

	private requireRun(): RunContext {
		if (!this.run) throw new Error("Subagents have not been initialized. Reload Pi, call `subagents_enable`, and retry.");
		return this.run;
	}

	private selected(names?: string[]): SubagentState[] {
		if (!names?.length) return [...this.states.values()].sort((a, b) => a.name.localeCompare(b.name));
		return [...new Set(names)].map(name => {
			validateSubagentName(name);
			const state = this.states.get(name);
			if (!state) throw new Error(`Unknown subagent: ${name}. Call \`subagent_status\` without names to list known subagents.`);
			return state;
		});
	}

	private isBusy(state: SubagentState): boolean {
		if (fs.existsSync(state.queuedPath)) return true;
		let info: { "child-pid"?: unknown };
		try {
			info = JSON.parse(fs.readFileSync(state.bwrapInfoPath, "utf8")) as { "child-pid"?: unknown };
		} catch (error) {
			if ((error as NodeJS.ErrnoException).code === "ENOENT") return false;
			throw new Error(`Cannot read Bubblewrap process information for ${state.name}. Run \`pueue status --group subagent\` to check whether its task is starting, then retry.`);
		}
		const pid = info["child-pid"];
		if (typeof pid !== "number" || !Number.isSafeInteger(pid) || pid < 1) {
			throw new Error(`Bubblewrap process information for ${state.name} has no valid child PID. Run \`pueue status --group subagent\` and inspect \`${state.bwrapInfoPath}\` before retrying.`);
		}
		try {
			process.kill(pid, 0);
			return true;
		} catch (error) {
			if ((error as NodeJS.ErrnoException).code === "ESRCH") return false;
			throw new Error(`Cannot check Bubblewrap PID ${pid} for ${state.name}. Run \`pueue status --group subagent\` to inspect the task before retrying.`);
		}
	}

	private prompt(name: string, task: string): string {
		return [
			`# Subagent prompt: ${name}`,
			"",
			"You are a direct subagent of the main Pi agent working in a private copy of the project.",
			"Write your response to `/run/pi-subagent/response.md` before ending this turn. The main agent reads that file, not your normal final message.",
			"If you need more information, write exactly what you need to that response file and ask the main agent to provide it and restart you.",
			"When work is complete, include a concise report, test results, and every changed file. Write file paths relative to your current working directory, never as absolute paths.",
			"Do not create or invoke other subagents.",
			"",
			"## Task",
			"",
			task.trim(),
			"",
		].join("\n");
	}

	async start(options: StartOptions): Promise<SubagentState> {
		const run = this.requireRun();
		validateSubagentName(options.name);
		if (!options.task.trim()) throw new Error("Subagent task must not be empty. Provide the instructions as non-empty Markdown in `task`.");

		let state = this.states.get(options.name);
		const prompt = this.prompt(options.name, options.task);
		if (state) {
			if (this.isBusy(state)) throw new Error(`Subagent ${options.name} is queued or running. Run \`pueue status --group subagent\` to inspect agent tasks, then wait for or stop the current task before retrying. If no task exists, remove the stale marker at \`${state.queuedPath}\`.`);
			state.turnId += 1;
			state.model = options.model;
			state.thinkingLevel = options.thinkingLevel;
			state.trustedProject = options.trustedProject;
			try {
				fs.writeFileSync(state.promptPath, prompt, { encoding: "utf8", mode: 0o600 });
				fs.writeFileSync(state.responsePath, "", { encoding: "utf8", mode: 0o600 });
			} catch (error) {
				const detail = error instanceof Error ? error.message : String(error);
				throw new Error(`Could not prepare the next turn for ${options.name}. Inspect \`${state.statePath}\`, fix its permissions or missing files, then retry. ${detail}`);
			}
		} else {
			const paths = await createSnapshot(run, options.name, prompt);
			state = {
				...paths,
				name: options.name,
				sessionId: crypto.randomUUID(),
				turnId: 1,
				model: options.model,
				thinkingLevel: options.thinkingLevel,
				trustedProject: options.trustedProject,
			};
			this.states.set(state.name, state);
		}
		try {
			fs.rmSync(state.bwrapInfoPath, { force: true });
		} catch (error) {
			const detail = error instanceof Error ? error.message : String(error);
			throw new Error(`Could not clear old Bubblewrap process information for ${options.name}. Inspect \`${state.bwrapInfoPath}\`, fix its permissions, then retry. ${detail}`);
		}
		state.pueueTaskId = await launchTask(state);
		return state;
	}

	status(names?: string[]): string {
		const states = this.selected(names);
		if (states.length === 0) return "No subagents exist in this run.";
		return states.map(state => [
			`## Subagent paths: ${state.name}`,
			"",
			`- **statePath:** \`${state.statePath}\``,
			`- **baselinePath:** \`${state.baselinePath}\``,
			`- **workspacePath:** \`${state.workspacePath}\``,
			`- **tmpPath:** \`${state.tmpPath}\``,
			`- **sessionsPath:** \`${state.sessionsPath}\``,
			`- **promptPath:** \`${state.promptPath}\``,
			`- **responsePath:** \`${state.responsePath}\``,
			`- **stdoutPath:** \`${state.stdoutPath}\``,
			`- **taskIdPath:** \`${state.taskIdPath}\``,
			`- **bwrapInfoPath:** \`${state.bwrapInfoPath}\``,
			`- **queuedPath:** \`${state.queuedPath}\``,
		].join("\n")).join("\n\n");
	}

	cleanup(name: string): void {
		validateSubagentName(name);
		const state = this.states.get(name);
		if (!state) throw new Error(`Unknown subagent: ${name}. Call \`subagent_status\` without names to list known subagents.`);
		if (this.isBusy(state)) throw new Error(`Subagent ${name} is queued or running. Run \`pueue status --group subagent\` to find its task, stop or wait for it, then retry cleanup. If no task exists, remove the stale marker at \`${state.queuedPath}\`.`);
		try {
			fs.rmSync(state.statePath, { recursive: true, force: true });
		} catch (error) {
			const detail = error instanceof Error ? error.message : String(error);
			throw new Error(`Could not delete the snapshot for ${name}. Inspect \`${state.statePath}\`, fix its permissions, then retry cleanup. ${detail}`);
		}
		this.states.delete(name);
	}

	shutdown(): void {
		if (this.run) fs.rmSync(this.run.runPath, { recursive: true, force: true });
		this.states.clear();
		this.run = undefined;
	}
}

// Extension

const LOADER_NAME = "subagents_enable";
const CHILD_DISABLED_TOOLS = new Set(["notify"]);

function parentTools(pi: ExtensionAPI): string[] {
	return pi.getAllTools().map(tool => tool.name).filter(name => name.startsWith("subagent_"));
}

export default function (pi: ExtensionAPI) {
	if (process.env.PI_SUBAGENT_ROLE === "child") {
		pi.on("session_start", () => {
			pi.setActiveTools(pi.getActiveTools().filter(name => !CHILD_DISABLED_TOOLS.has(name)));
		});
		return;
	}

	const supervisor = new SubagentSupervisor();

	pi.registerTool({
		name: LOADER_NAME,
		label: "Enable Subagents",
		description: "Enable asynchronous snapshot subagent orchestration tools. Does not start a subagent. Enabled tools are available on the next model request.",
		promptSnippet: "Call subagents_enable to activate asynchronous snapshot subagent tools; use them on the next model request.",
		parameters: Type.Object({}, { additionalProperties: false }),
		async execute() {
			try {
				await execFileAsync(PUEUE, ["group", "add", "--parallel", "4", "subagent"]);
			} catch (error) {
				const value = error as Error & { stderr?: string };
				const detail = value.stderr?.trim() || value.message;
				if (!detail.includes('Group "subagent" already exists')) {
					throw new Error(`Could not create the Pueue subagent group. Run \`pueue status\` to check the daemon, fix the reported problem, then retry. ${detail}`);
				}
			}
			const tools = parentTools(pi);
			pi.setActiveTools([...new Set([...pi.getActiveTools(), ...tools])]);
			return {
				content: [{ type: "text" as const, text: `Enabled subagent tools: ${tools.join(", ")}.` }],
				details: { enabled: tools },
			};
		},
	});

	const namesParameter = Type.Optional(Type.Array(Type.String({ minLength: 1 }), {
		description: "Optional subagent names; omit to select every subagent in this run",
		uniqueItems: true,
	}));

	pi.registerTool({
		name: "subagent_start",
		label: "Start Subagent",
		description: "Submit a named Pi subagent turn to Pueue. Reusing a name resumes its existing snapshot and session; ensure the previous task has finished first.",
		parameters: Type.Object({
			name: Type.String({ description: "Stable name reused by every other subagent tool", pattern: "^[a-z0-9][a-z0-9-]{0,62}$" }),
			task: Type.String({ description: "Complete task brief in Markdown", minLength: 1 }),
		}, { additionalProperties: false }),
		executionMode: "sequential",
		async execute(_toolCallId, params, _signal, _onUpdate, ctx) {
			const state = await supervisor.start({
				name: params.name,
				task: params.task,
				model: ctx.model ? `${ctx.model.provider}/${ctx.model.id}` : undefined,
				thinkingLevel: ctx.thinkingLevel,
				trustedProject: ctx.isProjectTrusted(),
			});
			return {
				content: [{
					type: "text" as const,
					text: `Subagent state: \`${state.statePath}\`\nPueue task_id: \`${state.pueueTaskId}\``,
				}],
				details: state,
			};
		},
	});

	pi.registerTool({
		name: "subagent_status",
		label: "Subagent Status",
		description: "Return the state-directory paths for selected named subagents, including task ID, response, and stdout files.",
		parameters: Type.Object({ names: namesParameter }, { additionalProperties: false }),
		async execute(_toolCallId, params) {
			return { content: [{ type: "text" as const, text: supervisor.status(params.names) }], details: { names: params.names } };
		},
	});

	pi.registerTool({
		name: "subagent_cleanup",
		label: "Clean Up Subagent",
		description: "Delete a named subagent snapshot. Ensure its Pueue task has finished or been stopped first.",
		parameters: Type.Object({
			name: Type.String({ pattern: "^[a-z0-9][a-z0-9-]{0,62}$" }),
		}, { additionalProperties: false }),
		executionMode: "sequential",
		async execute(_toolCallId, params) {
			supervisor.cleanup(params.name);
			return {
				content: [{ type: "text" as const, text: `Removed the snapshot for subagent **${params.name}**.` }],
				details: { name: params.name, removed: true },
			};
		},
	});

	pi.on("session_start", (_event, ctx) => {
		const tools = parentTools(pi);
		pi.setActiveTools([...pi.getActiveTools().filter(name => !tools.includes(name)), LOADER_NAME]);
		supervisor.initialize(ctx);
	});
	pi.on("session_shutdown", () => supervisor.shutdown());
}

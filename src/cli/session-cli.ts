/**
 * session-cli — continuity entry point for humans, workflows and future
 * sessions. The Arena session ends on merge; this CLI is how the next actor
 * (new session, human, or GitHub Actions job) picks up the thread.
 *
 * Usage:
 *   node src/cli/session-cli.ts resume                 # markdown briefing
 *   node src/cli/session-cli.ts show                   # state JSON
 *   node src/cli/session-cli.ts checkpoint --note "..." [--event e] [--sha s] [--status s]
 *   node src/cli/session-cli.ts set-next --actions "a1,a2"
 *   node src/cli/session-cli.ts branch-name            # suggested continuity branch
 */

import { SessionStore, type SessionStatus } from "../session/store.ts";

interface Args {
  command: string;
  flags: Record<string, string>;
}

function parseArgs(argv: string[]): Args {
  const [command = "resume", ...rest] = argv;
  const flags: Record<string, string> = {};
  for (let i = 0; i < rest.length; i += 1) {
    const token = rest[i] as string;
    if (token.startsWith("--")) {
      const key = token.slice(2);
      const next = rest[i + 1];
      if (next !== undefined && !next.startsWith("--")) {
        flags[key] = next;
        i += 1;
      } else {
        flags[key] = "true";
      }
    }
  }
  return { command, flags };
}

function main(): void {
  const { command, flags } = parseArgs(process.argv.slice(2));
  const store = new SessionStore(process.env["ARENA_SESSION_ROOT"] ?? process.cwd());

  switch (command) {
    case "resume": {
      console.log(store.resumeBriefing());
      return;
    }
    case "show": {
      console.log(JSON.stringify(store.read(), null, 2));
      return;
    }
    case "checkpoint": {
      const statusFlag = flags["status"];
      if (statusFlag !== undefined && statusFlag !== "true") {
        store.setStatus(statusFlag as SessionStatus);
      }
      const state = store.checkpoint({
        note: flags["note"] ?? "(sem nota)",
        event: flags["event"] === "true" ? undefined : flags["event"],
        sha: flags["sha"] === "true" ? undefined : flags["sha"],
      });
      console.log(JSON.stringify({ ok: true, checkpoints: state.checkpoints.length, status: state.status }, null, 2));
      return;
    }
    case "set-next": {
      const actions = (flags["actions"] ?? "")
        .split(",")
        .map((a) => a.trim())
        .filter((a) => a !== "");
      const state = store.setNextActions(actions);
      console.log(JSON.stringify({ ok: true, nextActions: state.nextActions }, null, 2));
      return;
    }
    case "branch-name": {
      console.log(store.suggestBranchName());
      return;
    }
    default: {
      console.error(`Unknown session command "${command}"`);
      console.error("Commands: resume | show | checkpoint | set-next | branch-name");
      process.exitCode = 2;
    }
  }
}

main();

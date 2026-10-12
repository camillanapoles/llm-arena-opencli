/**
 * gate-cli — command-line entry point used by both developers and GitHub
 * Actions workflows (the workflow runner *is* the driver runtime).
 *
 * Usage:
 *   node src/cli/gate-cli.ts serve [--port 8787]
 *   node src/cli/gate-cli.ts seed
 *   node src/cli/gate-cli.ts receive --event <type> [--repo r] [--ref refs/heads/main]
 *                                   [--actor a] [--payload '<json>']
 *   node src/cli/gate-cli.ts list
 *   node src/cli/gate-cli.ts opencli --command <cmd> [--url u] [--args a,b]
 *
 * Exit code of `receive` is 0 when all blocking gates pass, 1 otherwise —
 * exactly the semantics a CI gate needs.
 */

import { createApp, seedDefaults, type App } from "../app.ts";
import { createHttpServer } from "../server.ts";
import { normalizeEvent } from "../gate/events.ts";

interface Args {
  command: string;
  flags: Record<string, string>;
}

function parseArgs(argv: string[]): Args {
  const [command = "help", ...rest] = argv;
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

function parseJson(text: string | undefined): Record<string, unknown> {
  if (text === undefined || text.trim() === "") return {};
  try {
    return JSON.parse(text) as Record<string, unknown>;
  } catch (err) {
    console.error(`Invalid --payload JSON: ${err instanceof Error ? err.message : err}`);
    process.exit(2);
  }
}

async function main(): Promise<void> {
  const { command, flags } = parseArgs(process.argv.slice(2));

  if (command === "help" || command === "--help" || command === "-h") {
    console.log(`Commands:
  serve     Start the HTTP backend (ARENA_PORT or --port, default 8787)
  seed      Insert default functions and gates
  receive   Ingest one gate event and run matching gates (exit 1 on red gate)
  list      List gates, functions and recent runs
  opencli   Dispatch one OpenCLI command through the Actions runtime`);
    return;
  }

  const app: App = createApp();
  try {
    switch (command) {
      case "seed": {
        const result = seedDefaults(app);
        console.log(JSON.stringify({ seeded: result }, null, 2));
        return;
      }

      case "serve": {
        const port = Number(flags["port"] ?? process.env["ARENA_PORT"] ?? 8787);
        seedDefaults(app);
        const server = createHttpServer(app);
        server.listen(port, "0.0.0.0", () => {
          console.log(`arena driver backend listening on 0.0.0.0:${port}`);
        });
        // Keep the process alive; close DB on shutdown.
        const shutdown = (): void => {
          server.close(() => {
            app.close();
            process.exit(0);
          });
        };
        process.on("SIGINT", shutdown);
        process.on("SIGTERM", shutdown);
        return;
      }

      case "receive": {
        const event = normalizeEvent({
          type: flags["event"] ?? "manual",
          repo: flags["repo"],
          ref: flags["ref"],
          actor: flags["actor"],
          payload: parseJson(flags["payload"]),
        });
        const result = await app.driver.receive(event);
        console.log(
          JSON.stringify(
            {
              ok: result.ok,
              event: { id: result.event.id, type: result.event.type, repo: result.event.repo, ref: result.event.ref },
              outcomes: result.outcomes.map((outcome) => ({
                gateId: outcome.gate.id,
                policy: outcome.gate.policy,
                status: outcome.run.status,
                steps: outcome.run.steps.map((step) => ({
                  functionId: step.functionId,
                  kind: step.kind,
                  status: step.status,
                  error: step.error,
                })),
              })),
            },
            null,
            2,
          ),
        );
        if (!result.ok) process.exitCode = 1;
        return;
      }

      case "list": {
        console.log(
          JSON.stringify(
            {
              functions: app.functions.list(),
              gates: app.gates.list(),
              runs: app.runs.list().slice(-10),
            },
            null,
            2,
          ),
        );
        return;
      }

      case "opencli": {
        const result = await app.opencli.run({
          command: flags["command"] ?? "ping",
          url: flags["url"],
          args: (flags["args"] ?? "").split(",").filter((a) => a !== ""),
        });
        console.log(JSON.stringify(result, null, 2));
        if (!result.ok) process.exitCode = 1;
        return;
      }

      default: {
        console.error(`Unknown command "${command}"`);
        process.exitCode = 2;
      }
    }
  } finally {
    if (command !== "serve") {
      app.close();
    }
  }
}

await main();

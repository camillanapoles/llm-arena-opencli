/**
 * Application wiring: builds the full dependency container
 * (SQLite + cache + repos + function factory + gate driver + actions driver).
 */

import { Database } from "./db/database.ts";
import { migrate } from "./db/schema.ts";
import { ArenaCache, SqliteCachePersistence } from "./cache/cache.ts";
import { EventsRepo, FunctionsRepo, GatesRepo, RunsRepo } from "./crud/repos.ts";
import { createDefaultFactory } from "./functions/builtins.ts";
import type { FunctionFactory } from "./functions/factory.ts";
import { GateDriver } from "./gate/gate-driver.ts";
import { GitHubActionsDriver } from "./drivers/github-actions.driver.ts";
import { OpenCLIDriver } from "./drivers/opencli.driver.ts";
import type { ActionsTransport } from "./drivers/transport.ts";
import type { GateDefinition, FunctionSpec } from "./core/types.ts";

export interface AppOptions {
  dbPath?: string | undefined;
  actionsRepo?: string | undefined;
  actionsToken?: string | undefined;
  transport?: ActionsTransport | undefined;
  log?: ((message: string) => void) | undefined;
  /** secret do webhook real (X-Hub-Signature-256); vazio ⇒ sem verificação */
  webhookSecret?: string | undefined;
}

export interface App {
  db: Database;
  cache: ArenaCache;
  functions: FunctionsRepo;
  gates: GatesRepo;
  runs: RunsRepo;
  events: EventsRepo;
  factory: FunctionFactory;
  actions: GitHubActionsDriver;
  opencli: OpenCLIDriver;
  driver: GateDriver;
  /** secret do operador para validar entregas do GitHub (webhook real) */
  webhookSecret: string;
  close(): void;
}

export function createApp(options: AppOptions = {}): App {
  const db = new Database(options.dbPath ?? process.env["ARENA_DB_PATH"] ?? "data/arena.db");
  migrate(db);

  const cache = new ArenaCache({
    maxEntries: 2048,
    defaultTtlMs: 60_000,
    persistence: new SqliteCachePersistence(db),
  });

  const functions = new FunctionsRepo(db);
  const gates = new GatesRepo(db);
  const runs = new RunsRepo(db);
  const events = new EventsRepo(db);
  const factory = createDefaultFactory();

  const actions = new GitHubActionsDriver({
    repo: options.actionsRepo ?? process.env["OPENCLI_REPO"] ?? "jackwener/OpenCLI",
    token: options.actionsToken ?? process.env["GITHUB_TOKEN"],
    transport: options.transport,
  });
  const opencli = new OpenCLIDriver(actions);

  const driver = new GateDriver({
    db,
    cache,
    gates,
    functions,
    runs,
    events,
    factory,
    actions,
    log: options.log,
  });

  return {
    db,
    cache,
    functions,
    gates,
    runs,
    events,
    factory,
    actions,
    opencli,
    driver,
    webhookSecret: options.webhookSecret ?? process.env["GITHUB_WEBHOOK_SECRET"] ?? "",
    close: () => db.close(),
  };
}

/**
 * Seed a minimal but useful set of functions + gates so a fresh checkout is
 * immediately demonstrable (`npm run seed`).
 */
export function seedDefaults(app: App): { functions: string[]; gates: string[] } {
  const fnDefaults: FunctionSpec[] = [
    {
      id: "fn-log-start",
      name: "Log run start",
      kind: "log",
      params: { message: "gate run started" },
      cacheTtlMs: 0,
      enabled: true,
    },
    {
      id: "fn-cache-event",
      name: "Cache event summary",
      kind: "cache.put",
      params: { key: "last-event" },
      cacheTtlMs: 300_000,
      enabled: true,
    },
    {
      id: "fn-opencli-smoke",
      name: "OpenCLI smoke dispatch",
      kind: "opencli.dispatch",
      params: { command: "ping", url: "https://arena.ai/agent" },
      cacheTtlMs: 0,
      enabled: true,
    },
  ];

  const gateDefaults: GateDefinition[] = [
    {
      id: "gate-ci-blocking",
      name: "CI blocking gate (push + PR)",
      policy: "blocking",
      trigger: { events: ["push", "pull_request"], refs: ["refs/heads/"] },
      functions: ["fn-log-start", "fn-cache-event"],
      enabled: true,
    },
    {
      id: "gate-opencli-advisory",
      name: "OpenCLI advisory gate (manual + dispatch)",
      policy: "advisory",
      trigger: { events: ["workflow_dispatch", "repository_dispatch", "manual"] },
      functions: ["fn-log-start", "fn-opencli-smoke"],
      enabled: true,
    },
  ];

  const functionIds: string[] = [];
  for (const spec of fnDefaults) {
    if (app.functions.get(spec.id) === undefined) {
      app.functions.create(spec);
      functionIds.push(spec.id);
    }
  }

  const gateIds: string[] = [];
  for (const gate of gateDefaults) {
    if (app.gates.get(gate.id) === undefined) {
      app.gates.create(gate);
      gateIds.push(gate.id);
    }
  }

  return { functions: functionIds, gates: gateIds };
}

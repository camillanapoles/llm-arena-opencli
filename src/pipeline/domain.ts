/**
 * Modelo de domínio OO do pipeline gate-driven (blueprint/BPMN) com backend
 * SQLite — a camada orientada a objetos ("OOM") pedida na solicitação T4.
 *
 *   PipelineIssue   — entidade OO (issue indexada + máquina de estados)
 *   IssueRepository — persistência SQLite (CRUD OO)
 *   IssueFactory    — FACTORY event-driven: cria issues a partir do blueprint
 *                     e de eventos do gate (conforme o pattern gate-driven BPMN)
 *   PipelineEngine  — orquestra ciclos DETERMINÍSTICOS de teste da entrega e
 *                     decide a DIREÇÃO da continuidade: continue | fix | debt |
 *                     complete | hold
 */

import { spawnSync } from "node:child_process";
import { writeFileSync } from "node:fs";
import type { Database } from "../db/database.ts";
import type { Blueprint, BlueprintStep } from "./chain.ts";
import { getStep, runChainStep, validateBlueprint } from "./chain.ts";
import {
  errorEnvelope,
  makeEnvelope,
  successEnvelope,
  decideDirection,
  type ActionEnvelope,
  type Addendum,
  type Direction,
} from "./envelope.ts";

// ------------------------------------------------------------------ estados

export const ISSUE_STATES = ["pending", "in_progress", "delivered", "failed", "debt"] as const;
export type IssueState = (typeof ISSUE_STATES)[number];

export interface IssueFields {
  id: string;
  title: string;
  instruction: string;
  acceptance: string;
  state: IssueState;
  attempts: number;
  next: string | null;
  lastError: string | null;
}

/** Entidade OO da issue indexada (máquina de estados do BPMN). */
export class PipelineIssue {
  readonly id: string;
  title: string;
  instruction: string;
  acceptance: string;
  state: IssueState;
  attempts: number;
  next: string | null;
  lastError: string | null;

  constructor(fields: IssueFields) {
    this.id = fields.id;
    this.title = fields.title;
    this.instruction = fields.instruction;
    this.acceptance = fields.acceptance;
    this.state = fields.state;
    this.attempts = fields.attempts;
    this.next = fields.next;
    this.lastError = fields.lastError;
  }

  /** Transição: entra em ciclo de teste (determinístico). */
  start(): void {
    this.state = "in_progress";
    this.attempts += 1;
  }

  /** Transição: entrega testada com sucesso COMPLETO. */
  deliver(): void {
    this.state = "delivered";
    this.lastError = null;
  }

  /** Transição: falha na validação (continuidade: fix ou debt). */
  fail(reason: string, direction: Direction): void {
    this.state = direction === "debt" ? "debt" : "failed";
    this.lastError = reason;
  }

  toFields(): IssueFields {
    return {
      id: this.id,
      title: this.title,
      instruction: this.instruction,
      acceptance: this.acceptance,
      state: this.state,
      attempts: this.attempts,
      next: this.next,
      lastError: this.lastError,
    };
  }
}

// ------------------------------------------------------------- repositório

interface IssueRow {
  id: string;
  title: string;
  instruction: string;
  acceptance: string;
  state: string;
  attempts: number;
  next: string | null;
  last_error: string | null;
}

const CREATE_TABLE_SQL = `
CREATE TABLE IF NOT EXISTS pipeline_issues (
  id           TEXT PRIMARY KEY,
  title        TEXT NOT NULL,
  instruction  TEXT NOT NULL,
  acceptance   TEXT NOT NULL,
  state        TEXT NOT NULL DEFAULT 'pending',
  attempts     INTEGER NOT NULL DEFAULT 0,
  next         TEXT,
  last_error   TEXT,
  updated_at   TEXT NOT NULL
);`;

/** Persistência SQLite OO (backend da cadeia de issues). */
export class IssueRepository {
  private readonly db: Database;

  constructor(db: Database) {
    this.db = db;
    this.db.exec(CREATE_TABLE_SQL);
  }

  save(issue: PipelineIssue): void {
    const f = issue.toFields();
    this.db.run(
      `INSERT INTO pipeline_issues (id, title, instruction, acceptance, state, attempts, next, last_error, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
       ON CONFLICT(id) DO UPDATE SET title = excluded.title,
                                     instruction = excluded.instruction,
                                     acceptance = excluded.acceptance,
                                     state = excluded.state,
                                     attempts = excluded.attempts,
                                     next = excluded.next,
                                     last_error = excluded.last_error,
                                     updated_at = excluded.updated_at`,
      f.id,
      f.title,
      f.instruction,
      f.acceptance,
      f.state,
      f.attempts,
      f.next,
      f.lastError,
      new Date().toISOString(),
    );
  }

  get(id: string): PipelineIssue | undefined {
    const row = this.db.get<IssueRow>("SELECT * FROM pipeline_issues WHERE id = ?", id);
    return row === undefined ? undefined : this.hydrate(row);
  }

  list(): PipelineIssue[] {
    return this.db
      .query<IssueRow>("SELECT * FROM pipeline_issues ORDER BY id")
      .map((row) => this.hydrate(row));
  }

  listPending(): PipelineIssue[] {
    return this.list().filter((issue) => issue.state === "pending" || issue.state === "in_progress");
  }

  private hydrate(row: IssueRow): PipelineIssue {
    return new PipelineIssue({
      id: String(row.id),
      title: String(row.title),
      instruction: String(row.instruction),
      acceptance: String(row.acceptance),
      state: (ISSUE_STATES as readonly string[]).includes(String(row.state))
        ? (row.state as IssueState)
        : "pending",
      attempts: Number(row.attempts ?? 0),
      next: row.next == null ? null : String(row.next),
      lastError: row.last_error == null ? null : String(row.last_error),
    });
  }
}

// ------------------------------------------------------------------ factory

export interface PipelineEvent {
  /** issue.completed | issue.failed | gate.checked | issue.requested */
  type: string;
  issueId?: string | undefined;
  result?: 0 | 1 | 2 | undefined;
}

/**
 * FACTORY event-driven: materializa issues indexadas (do blueprint ou criadas
 * por demanda via evento) seguindo o pattern gate-driven BPMN. Toda criação
 * de issue passa por aqui — nunca por string solta.
 */
export class IssueFactory {
  private readonly blueprint: Blueprint;

  constructor(blueprint: Blueprint) {
    const validation = validateBlueprint(blueprint);
    if (!validation.ok) {
      throw new Error(`blueprint inválido: ${validation.problems.join("; ")}`);
    }
    this.blueprint = blueprint;
  }

  create(step: BlueprintStep): PipelineIssue {
    return new PipelineIssue({
      id: step.id,
      title: step.title,
      instruction: step.instruction,
      acceptance: step.acceptance,
      state: "pending",
      attempts: 0,
      next: step.next,
      lastError: null,
    });
  }

  createById(id: string): PipelineIssue {
    const step = getStep(this.blueprint, id);
    if (step === undefined) {
      throw new Error(`issue indexada "${id}" não existe no blueprint`);
    }
    return this.create(step);
  }

  materializeAll(): PipelineIssue[] {
    return this.blueprint.chain.map((step) => this.create(step));
  }

  /**
   * Criação por EVENTO (event-driven): um evento do gate pode demandar uma
   * issue (ex.: `issue.requested` com id livre fora do blueprint).
   */
  createFromEvent(event: PipelineEvent): PipelineIssue {
    if (event.issueId !== undefined && getStep(this.blueprint, event.issueId) === undefined) {
      return new PipelineIssue({
        id: event.issueId,
        title: `Issue demandada por evento (${event.issueId})`,
        instruction: "Instrução gerada pelo factory event-driven — completar critério de aceitação.",
        acceptance: "npm run ci",
        state: "pending",
        attempts: 0,
        next: null,
        lastError: null,
      });
    }
    if (event.issueId !== undefined) {
      return this.createById(event.issueId);
    }
    throw new Error(`evento sem issueId: ${event.type}`);
  }
}

// --------------------------------------------------------- runner + engine

export interface CommandResult {
  exitCode: number;
  log: string;
}

export interface CommandRunner {
  run(command: string): CommandResult;
}

/** Runner determinístico via `bash -c` (mesmo comando, mesmo cwd, mesmo env). */
export class BashRunner implements CommandRunner {
  run(command: string): CommandResult {
    const result = spawnSync("bash", ["-c", command], { encoding: "utf8", timeout: 600_000 });
    return {
      exitCode: result.status ?? 1,
      log: `${result.stdout ?? ""}${result.stderr ?? ""}`,
    };
  }
}

/**
 * Validação de SUCESSO COMPLETADA: exit code 0 E nenhum "# fail <n>" com n>0
 * no SUMÁRIO TAP (linhas exatas "# fail N" — nomes de testes que contenham
 * "# fail 3" no título não podem mascarar o resultado).
 */
export function isCompleteSuccess(exitCode: number, log: string): boolean {
  if (exitCode !== 0) return false;
  const failMatch = /^# fail (\d+)\s*$/m.exec(log);
  if (failMatch !== null && Number(failMatch[1]) > 0) return false;
  return true;
}

export interface EngineDeps {
  repo: IssueRepository;
  factory: IssueFactory;
  runner: CommandRunner;
  blueprint?: Blueprint | undefined;
}

/** Motor gate-driven BPMN: eventos, ciclos determinísticos, envelopes JSON. */
export class PipelineEngine {
  private readonly deps: EngineDeps;

  constructor(deps: EngineDeps) {
    this.deps = deps;
  }

  private stepOf(issue: PipelineIssue): BlueprintStep {
    return {
      id: issue.id,
      title: issue.title,
      instruction: issue.instruction,
      acceptance: issue.acceptance,
      next: issue.next,
    };
  }

  /**
   * Ciclo DETERMINÍSTICO de teste da entrega:
   *   1. carrega/cria a issue indexada (factory) e persiste (repo OO + SQLite)
   *   2. executa o acceptance (runner injetável — determinístico)
   *   3. valida SUCESSO COMPLETO (exit 0 + nenhum "# fail n>0")
   *   4. emite o envelope JSON padrão com a DIREÇÃO da continuidade
   */
  runCycle(issueId: string, id?: string, logFile?: string): ActionEnvelope {
    let issue: PipelineIssue;
    try {
      issue = this.deps.repo.get(issueId) ?? this.deps.factory.createById(issueId);
    } catch (err) {
      return errorEnvelope({
        id,
        message: err instanceof Error ? err.message : String(err),
        sameIssue: issueId,
        errorType: 2,
        continuityReason: "pré-condição violada — issue desconhecida/inacessível (continuidade)",
        direction: "hold",
      });
    }

    const step = this.stepOf(issue);
    issue.start();
    this.deps.repo.save(issue);

    const result = this.deps.runner.run(step.acceptance);
    if (logFile !== undefined && logFile !== "") {
      try {
        writeFileSync(logFile, result.log, "utf8");
      } catch {
        /* log em arquivo é melhor esforço */
      }
    }
    const complete = isCompleteSuccess(result.exitCode, result.log);
    const addenda: Addendum[] = [
      {
        kind: "log",
        ref: logFile ?? result.log.slice(0, 2000),
        description: `acceptance: ${step.acceptance}`,
      },
    ];

    if (complete) {
      issue.deliver();
      this.deps.repo.save(issue);
      return runChainStep(
        step,
        {
          exitCode: 0,
          message: `entrega de ${step.id} testada com SUCESSO COMPLETO (acceptance: ${step.acceptance})`,
          addenda,
        },
        id,
      );
    }

    const reason =
      result.exitCode === 0
        ? "acceptance com exit 0 mas SUCESSO MASCARADO (# fail n>0 no sumário) — validação completa de sucesso não atingida"
        : `acceptance falhou (exit ${result.exitCode}) — validação completa de sucesso não atingida`;
    issue.fail(reason, "fix");
    this.deps.repo.save(issue);
    return runChainStep(
      step,
      {
        exitCode: 1,
        message: reason,
        addenda,
      },
      id,
    );
  }

  /**
   * Evento do gate (BPMN): `issue.completed` / `issue.failed` / `gate.checked`
   * → transição + envelope com a direção da continuidade.
   */
  onEvent(event: PipelineEvent, id?: string): ActionEnvelope {
    if (event.type === "gate.checked") {
      return makeEnvelope({
        id,
        status: "gate-event",
        message: "evento de gate recebido — sem transição de issue",
        addenda: [],
        nextIssue: event.issueId ?? null,
        exitCode: 0,
        direction: "continue",
      });
    }

    let issue: PipelineIssue;
    try {
      issue = this.deps.repo.get(event.issueId ?? "") ?? this.deps.factory.createFromEvent(event);
    } catch (err) {
      return errorEnvelope({
        id,
        message: err instanceof Error ? err.message : String(err),
        sameIssue: event.issueId ?? "",
        errorType: 2,
        continuityReason: "evento sem issue válida (continuidade)",
        direction: "hold",
      });
    }
    this.deps.repo.save(issue);

    if (event.type === "issue.requested") {
      // Evento de CRIAÇÃO (event-driven): materializa a issue como pendente.
      // Ainda não houve teste da entrega — a MESMA issue é o próximo movimento.
      return makeEnvelope({
        id,
        status: "created",
        message: `issue.requested: ${issue.id} materializada pelo factory event-driven`,
        addenda: [{ kind: "path", ref: "pipeline/blueprint.json", description: "blueprint da cadeia" }],
        nextIssue: issue.id,
        exitCode: 0,
        direction: "continue",
        continuity: {
          required: true,
          reason: "issue pendente criada — ciclo de teste virá para validar a entrega (continuidade)",
        },
      });
    }

    const result = event.result ?? 0;
    if (event.type === "issue.completed" && result === 0) {
      issue.deliver();
      this.deps.repo.save(issue);
      return successEnvelope({
        id,
        message: `issue.completed: ${issue.id} entregue`,
        status: issue.next === null ? "chain-complete" : "delivered",
        nextIssue: issue.next,
        addenda: [{ kind: "path", ref: "pipeline/blueprint.json", description: "blueprint da cadeia" }],
      });
    }

    const outcome: 0 | 1 | 2 = result === 0 ? 1 : (result as 1 | 2);
    const direction = decideDirection(outcome, issue.next !== null);
    issue.fail(`evento ${event.type} com resultado ${result}`, direction);
    this.deps.repo.save(issue);
    return errorEnvelope({
      id,
      message: `evento ${event.type}: ${issue.id} com resultado ${result}`,
      sameIssue: issue.id,
      errorType: outcome === 2 ? 2 : 1,
      continuityReason: `direção de continuidade: ${direction} — MESMA issue como nextIssue`,
      direction,
      addenda: [{ kind: "path", ref: "pipeline/blueprint.json", description: "blueprint da cadeia" }],
    });
  }
}

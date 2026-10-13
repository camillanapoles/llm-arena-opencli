/**
 * pipeline-cli — interface PADRÃO de actions do fluxo gate-driven
 * (blueprint/BPMN via GitHub Actions). TODO action imprime UMA vez o objeto
 * JSON ActionEnvelope { id, message, addenda, status, nextIssue, exitCode }
 * e termina com process exit = exitCode (0 sucesso · 1 erro tipo 1 · 2 erro
 * tipo 2). Mensagem/status são strings (message pode ser vazia ou log).
 *
 * Uso:
 *   node src/cli/pipeline-cli.ts gate \
 *     --open-issues N --ci-failures N --tests-total N --tests-passed N
 *   node src/cli/pipeline-cli.ts step --id ISSUE-2 --result 0|1|2 \
 *     [--message "..."] [--addendum kind:ref:description] [--action-id id]
 *   node src/cli/pipeline-cli.ts cycle --id ISSUE-2 [--log-file ci.log] \
 *     [--action-id id]          # ciclo determinístico: roda acceptance e valida
 *                               # SUCESSO COMPLETO -> envelope com DIREÇÃO
 *   node src/cli/pipeline-cli.ts event --type issue.completed|issue.failed|gate.checked \
 *     [--issue ISSUE-2] [--result 0|1|2] [--action-id id]
 *   node src/cli/pipeline-cli.ts pending [--action-id id]
 *   node src/cli/pipeline-cli.ts interop --from FILE | --to FILE
 *     # converte envelopes entre os dialetos das duas sessões (docs/INTEGRATION.md)
 *   node src/cli/pipeline-cli.ts registry [--cnj-backlog FILE] [--out FILE]
 *     # registra unificado das duas sessões (blueprint nosso + backlog CNJ)
 *   node src/cli/pipeline-cli.ts next [--after ISSUE-1]
 *   node src/cli/pipeline-cli.ts validate
 */

import {
  makeEnvelope,
  decideDirection,
  type ActionEnvelope,
  type Addendum,
  type ExitCode,
} from "../pipeline/envelope.ts";
import { evaluateContinuityGate, gateEnvelope, type GateSnapshot } from "../pipeline/gates.ts";
import {
  getStep,
  loadBlueprint,
  nextStepAfter,
  runChainStep,
  validateBlueprint,
} from "../pipeline/chain.ts";
import {
  BashRunner,
  IssueFactory,
  IssueRepository,
  PipelineEngine,
} from "../pipeline/domain.ts";
import {
  fromCnjEnvelope,
  loadCnjBacklog,
  mergeRegistry,
  toCnjEnvelope,
  writeRegistry,
  type CnjEnvelope,
} from "../pipeline/interop.ts";
import { Database } from "../db/database.ts";
import { readFileSync } from "node:fs";

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

function num(flags: Record<string, string>, key: string, fallback: number): number {
  const raw = flags[key];
  if (raw === undefined) return fallback;
  const value = Number(raw);
  return Number.isFinite(value) ? value : fallback;
}

function parseAddendum(raw: string | undefined): Addendum[] {
  if (raw === undefined) return [];
  // formato: kind:ref:description (description opcional)
  const parts = raw.split(":");
  const kind = (parts[0] ?? "path") as Addendum["kind"];
  const ref = parts[1] ?? "";
  const description = parts.slice(2).join(":");
  return [{ kind, ref, description }];
}

function emit(envelope: ActionEnvelope): void {
  console.log(JSON.stringify(envelope, null, 2));
  process.exitCode = envelope.exitCode;
}

function blueprintPath(flags: Record<string, string>): string {
  return flags["blueprint"] ?? "pipeline/blueprint.json";
}

function buildEngine(flags: Record<string, string>): PipelineEngine {
  const db = new Database(process.env["ARENA_DB_PATH"] ?? "data/arena.db");
  const repo = new IssueRepository(db);
  const factory = new IssueFactory(loadBlueprint(blueprintPath(flags)));
  return new PipelineEngine({ repo, factory, runner: new BashRunner() });
}

function main(): void {
  const { command, flags } = parseArgs(process.argv.slice(2));
  const actionId = flags["action-id"];

  switch (command) {
    case "gate": {
      const snapshot: GateSnapshot = {
        openIssues: num(flags, "open-issues", 0),
        ciFailures: num(flags, "ci-failures", 0),
        testsTotal: num(flags, "tests-total", 0),
        testsPassed: num(flags, "tests-passed", 0),
      };
      const decision = evaluateContinuityGate(snapshot);
      emit(gateEnvelope(decision, snapshot, actionId));
      return;
    }

    case "step": {
      const bp = loadBlueprint(blueprintPath(flags));
      const id = flags["id"] ?? "";
      const step = getStep(bp, id);
      if (step === undefined) {
        emit(
          makeEnvelope({
            id: actionId,
            status: "error",
            message: `issue indexada "${id}" não existe no blueprint`,
            addenda: [{ kind: "path", ref: blueprintPath(flags), description: "blueprint da cadeia" }],
            nextIssue: id === "" ? null : id,
            exitCode: 2,
            continuity: { required: true, reason: "passo desconhecido — corrigir índice ou blueprint" },
          }),
        );
        return;
      }
      const result = num(flags, "result", 0) as ExitCode;
      const outcomeCode = result === 0 ? 0 : result === 1 ? 1 : 2;
      emit(
        runChainStep(
          step,
          {
            exitCode: outcomeCode,
            message: flags["message"] === "true" ? undefined : flags["message"],
            addenda: parseAddendum(flags["addendum"]),
          },
          actionId,
        ),
      );
      return;
    }

    case "next": {
      const bp = loadBlueprint(blueprintPath(flags));
      const after = flags["after"];
      const step = after === undefined ? bp.chain[0] ?? null : nextStepAfter(bp, after);
      if (step === null || step === undefined) {
        emit(
          makeEnvelope({
            id: actionId,
            status: "chain-complete",
            message: "cadeia completa — nenhuma issue indexada restante",
            addenda: [{ kind: "path", ref: blueprintPath(flags), description: "blueprint da cadeia" }],
            nextIssue: null,
            exitCode: 0,
          }),
        );
        return;
      }
      emit(
        makeEnvelope({
          id: actionId,
          status: "next",
          message: `${step.id} — ${step.title}: ${step.instruction}`,
          addenda: [
            { kind: "path", ref: blueprintPath(flags), description: "blueprint da cadeia" },
            { kind: "log", ref: step.acceptance, description: `acceptance de ${step.id}` },
          ],
          nextIssue: step.id,
          exitCode: 0,
          continuity: { required: true, reason: "cadeia em andamento — próxima issue indexada pronta para construir" },
        }),
      );
      return;
    }

    case "validate": {
      const bp = loadBlueprint(blueprintPath(flags));
      const validation = validateBlueprint(bp);
      emit(
        makeEnvelope({
          id: actionId,
          status: validation.ok ? "valid" : "invalid",
          message: validation.ok ? "blueprint íntegro" : validation.problems.join("; "),
          addenda: [{ kind: "path", ref: blueprintPath(flags), description: "blueprint da cadeia" }],
          nextIssue: null,
          exitCode: validation.ok ? 0 : 2,
          continuity: validation.ok
            ? { required: false, reason: "" }
            : { required: true, reason: "blueprint inválido — corrigir cadeia antes de prosseguir" },
        }),
      );
      return;
    }

    case "cycle": {
      const engine = buildEngine(flags);
      const id = flags["id"] ?? "";
      const logFile = flags["log-file"] === "true" ? undefined : flags["log-file"];
      emit(engine.runCycle(id, actionId, logFile));
      return;
    }

    case "event": {
      const engine = buildEngine(flags);
      const result = num(flags, "result", 0);
      const envelope = engine.onEvent(
        {
          type: flags["type"] ?? "gate.checked",
          issueId: flags["issue"] === "true" ? undefined : flags["issue"],
          result: result === 0 ? 0 : result === 1 ? 1 : 2,
        },
        actionId,
      );
      emit(envelope);
      return;
    }

    case "pending": {
      const bp = loadBlueprint(blueprintPath(flags));
      const db = new Database(process.env["ARENA_DB_PATH"] ?? "data/arena.db");
      const repo = new IssueRepository(db);
      const factory = new IssueFactory(bp);
      for (const issue of factory.materializeAll()) {
        if (repo.get(issue.id) === undefined) repo.save(issue);
      }
      const pending = repo.listPending();
      emit(
        makeEnvelope({
          id: actionId,
          status: pending.length === 0 ? "no-pending" : "pending",
          message: pending
            .map((p) => `${p.id} [${p.state}] ${p.title} — ${p.instruction}`)
            .join("\n"),
          addenda: [
            { kind: "path", ref: blueprintPath(flags), description: "blueprint da cadeia" },
            ...pending.map((p) => ({
              kind: "filename" as const,
              ref: p.id,
              description: `${p.title} (acceptance: ${p.acceptance})`,
            })),
          ],
          nextIssue: pending[0]?.id ?? null,
          exitCode: 0,
          direction: pending.length === 0 ? "complete" : "continue",
          continuity: {
            required: pending.length > 0,
            reason:
              pending.length === 0
                ? ""
                : `${pending.length} issue(s) pendente(s) com instrução — continuidade em andamento`,
          },
        }),
      );
      return;
    }

    case "interop": {
      const fromPath = flags["from"];
      const toPath = flags["to"];
      if (fromPath !== undefined && fromPath !== "true") {
        const cnj = JSON.parse(readFileSync(fromPath, "utf8")) as CnjEnvelope;
        const converted = fromCnjEnvelope(cnj);
        emit(
          makeEnvelope({
            id: actionId,
            status: "converted",
            message: `envelope CNJ -> ActionEnvelope (${fromPath})`,
            addenda: [{ kind: "path", ref: fromPath, description: "envelope de origem (dialeto CNJ)" }],
            nextIssue: converted.nextIssue,
            exitCode: converted.exitCode,
            direction: converted.direction,
            data: { converted },
          }),
        );
        return;
      }
      if (toPath !== undefined && toPath !== "true") {
        const ours = JSON.parse(readFileSync(toPath, "utf8")) as ActionEnvelope;
        const converted = toCnjEnvelope(ours);
        emit(
          makeEnvelope({
            id: actionId,
            status: "converted",
            message: `ActionEnvelope -> envelope CNJ (${toPath})`,
            addenda: [{ kind: "path", ref: toPath, description: "envelope de origem (dialeto d917)" }],
            nextIssue: ours.nextIssue,
            exitCode: ours.exitCode,
            direction: ours.direction,
            data: { converted },
          }),
        );
        return;
      }
      emit(
        makeEnvelope({
          id: actionId,
          status: "error",
          message: "interop requer --from FILE (CNJ->nosso) ou --to FILE (nosso->CNJ)",
          addenda: [],
          nextIssue: null,
          exitCode: 2,
          direction: "hold",
          continuity: { required: true, reason: "uso inválido do interop" },
        }),
      );
      return;
    }

    case "registry": {
      const bp = loadBlueprint(blueprintPath(flags));
      const backlogPath = flags["cnj-backlog"] ?? "pipeline/backlog-cnj.json";
      const outPath = flags["out"] ?? "pipeline/registry.json";
      try {
        const backlog = loadCnjBacklog(backlogPath);
        const registry = mergeRegistry(bp, backlog, {
          ourBranch: flags["our-branch"] ?? "arena/d917b13b-llm-arena-opencli",
          ourPr: Number(flags["our-pr"] ?? 1),
          theirBranch: flags["their-branch"] ?? "arena/ed79bd77-llm-arena-opencli",
          theirPr: Number(flags["their-pr"] ?? 2),
        });
        writeRegistry(registry, outPath);
        emit(
          makeEnvelope({
            id: actionId,
            status: "merged",
            message: `registro unificado: ${registry.entries.length} issues de ${registry.sessions.length} sessões (${registry.sessions.map((s) => `${s.source}:${s.pending} pendentes`).join(" · ")})`,
            addenda: [
              { kind: "path", ref: outPath, description: "registro unificado das duas sessões" },
              { kind: "path", ref: backlogPath, description: "backlog CNJ (sessão paralela)" },
              { kind: "path", ref: blueprintPath(flags), description: "blueprint d917 (esta sessão)" },
            ],
            nextIssue: registry.entries.find((e) => e.status === "pendente")?.id ?? null,
            exitCode: 0,
            direction: registry.entries.some((e) => e.status === "pendente") ? "continue" : "complete",
            data: { registry },
          }),
        );
      } catch (err) {
        emit(
          makeEnvelope({
            id: actionId,
            status: "error",
            message: err instanceof Error ? err.message : String(err),
            addenda: [{ kind: "path", ref: backlogPath, description: "backlog CNJ esperado" }],
            nextIssue: null,
            exitCode: 2,
            direction: "hold",
            continuity: {
              required: true,
              reason: "não foi possível mesclar os backlogs — exporte o backlog da sessão paralela (ver docs/INTEGRATION.md)",
            },
          }),
        );
      }
      return;
    }

    default: {
      emit(
        makeEnvelope({
          status: "error",
          message: `comando desconhecido "${command}" — use: gate | step | next | validate`,
          addenda: [],
          nextIssue: null,
          exitCode: 2,
          continuity: { required: true, reason: "uso inválido do pipeline-cli" },
        }),
      );
    }
  }
}

main();

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
 *   node src/cli/pipeline-cli.ts next [--after ISSUE-1]
 *   node src/cli/pipeline-cli.ts validate
 */

import {
  makeEnvelope,
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

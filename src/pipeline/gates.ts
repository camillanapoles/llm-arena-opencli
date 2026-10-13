/**
 * ContinuityGate — o gatilho de prontidão do pipeline.
 *
 * Verifica a NÃO existência de:
 *   - issues abertas
 *   - CI/CD com erros
 *   - ausência de testes (ou testes não aprovados)
 *
 * Enquanto o gate não estiver positivo → CONTINUIDADE (o fluxo segue).
 * Quando positivo → produção pronta para uso (`status: "production-ready"`).
 */

import {
  makeEnvelope,
  type ActionEnvelope,
  type ExitCode,
} from "./envelope.ts";

export interface GateSnapshot {
  /** Issues abertas no repositório (0 = condição satisfeita). */
  openIssues: number;
  /** Execuções de workflow com falha recentes (0 = condição satisfeita). */
  ciFailures: number;
  /** Total de testes descobertos (0 = SEM TESTES = condição violada). */
  testsTotal: number;
  /** Testes aprovados (deve ser igual a testsTotal). */
  testsPassed: number;
}

export interface GateDecision {
  positive: boolean;
  reasons: string[];
}

export function evaluateContinuityGate(snapshot: GateSnapshot): GateDecision {
  const reasons: string[] = [];
  if (snapshot.openIssues > 0) {
    reasons.push(`${snapshot.openIssues} issue(s) aberta(s)`);
  }
  if (snapshot.ciFailures > 0) {
    reasons.push(`CI/CD com ${snapshot.ciFailures} execução(ões) com erro`);
  }
  if (snapshot.testsTotal <= 0) {
    reasons.push("sem testes (nenhum teste descoberto)");
  } else if (snapshot.testsPassed < snapshot.testsTotal) {
    reasons.push(`testes não aprovados (${snapshot.testsPassed}/${snapshot.testsTotal})`);
  }
  return { positive: reasons.length === 0, reasons };
}

/**
 * Envelope do gate:
 *   positivo        -> status "production-ready", exitCode 0
 *   não positivo    -> status "continuity",        exitCode 2 (erro tipo 2:
 *                      pré-condição de produção não satisfeita; o fluxo
 *                      continua — é o estado normal do loop)
 */
export function gateEnvelope(
  decision: GateDecision,
  snapshot: GateSnapshot,
  id?: string,
): ActionEnvelope {
  const addenda = [
    {
      kind: "log" as const,
      ref: `openIssues=${snapshot.openIssues} ciFailures=${snapshot.ciFailures} tests=${snapshot.testsPassed}/${snapshot.testsTotal}`,
      description: "snapshot do gate de continuidade",
    },
  ];
  if (decision.positive) {
    return makeEnvelope({
      id,
      status: "production-ready",
      message: "gate positivo: sem issues abertas, CI/CD verde, testes presentes e aprovados — PRONTO PARA USO",
      addenda,
      nextIssue: null,
      exitCode: 0,
    });
  }
  return makeEnvelope({
    id,
    status: "continuity",
    message: decision.reasons.join("; "),
    addenda,
    nextIssue: null,
    exitCode: 2 satisfies ExitCode,
    continuity: {
      required: true,
      reason: `gate não positivo: ${decision.reasons.join("; ")} — enquanto não positivo, significa CONTINUIDADE`,
    },
  });
}

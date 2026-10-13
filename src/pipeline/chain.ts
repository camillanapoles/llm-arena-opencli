/**
 * ChainExecutor — cadeia de issues indexadas estilo blueprint/BPMN.
 *
 * Regra do fluxo (gate-driven pipeline):
 *   - Cada issue indexada (ISSUE-1, ISSUE-2, …) tem uma instrução e uma
 *     aceitação (comando de teste da entrega).
 *   - QUANDO uma issue termina com SUCESSO testado -> constrói a SEGUINTE
 *     indexada (nextIssue = próxima).
 *   - SE ERRO -> retorna erro (tipo 1 ou 2) + informações de continuidade
 *     (nextIssue = MESMA issue, continuidade.required = true).
 */

import { existsSync, readFileSync } from "node:fs";
import {
  errorEnvelope,
  successEnvelope,
  type ActionEnvelope,
  type Addendum,
} from "./envelope.ts";

export interface BlueprintStep {
  id: string;
  title: string;
  instruction: string;
  /** Comando que TESTA a entrega desta issue (ex.: "npm run ci"). */
  acceptance: string;
  /** Próxima issue indexada, ou null no fim da cadeia. */
  next: string | null;
}

export interface Blueprint {
  version: number;
  chain: BlueprintStep[];
}

export interface BlueprintValidation {
  ok: boolean;
  problems: string[];
}

export function loadBlueprint(path: string): Blueprint {
  if (!existsSync(path)) {
    throw new Error(`blueprint não encontrado: ${path}`);
  }
  return JSON.parse(readFileSync(path, "utf8")) as Blueprint;
}

/** Integridade da cadeia: ids indexados, next válido, aceitação presente. */
export function validateBlueprint(bp: Blueprint): BlueprintValidation {
  const problems: string[] = [];
  const ids = new Set<string>();
  for (const [index, step] of bp.chain.entries()) {
    const expected = `ISSUE-${index + 1}`;
    if (step.id !== expected) {
      problems.push(`posição ${index}: id "${step.id}" deveria ser "${expected}" (indexação)`);
    }
    if (ids.has(step.id)) problems.push(`id duplicado: ${step.id}`);
    ids.add(step.id);
    if (step.acceptance.trim() === "") {
      problems.push(`${step.id}: acceptance vazio (não há como testar a entrega)`);
    }
    if (step.next !== null && !/^ISSUE-\d+$/.test(step.next)) {
      problems.push(`${step.id}: next inválido (${step.next})`);
    }
  }
  for (const step of bp.chain) {
    if (step.next !== null && !ids.has(step.next)) {
      problems.push(`${step.id}: next "${step.next}" não existe na cadeia`);
    }
  }
  return { ok: problems.length === 0, problems };
}

export function getStep(bp: Blueprint, id: string): BlueprintStep | undefined {
  return bp.chain.find((step) => step.id === id);
}

export function nextStepAfter(bp: Blueprint, id: string): BlueprintStep | null {
  const step = getStep(bp, id);
  if (step === undefined || step.next === null) return null;
  return getStep(bp, step.next) ?? null;
}

export interface ChainOutcome {
  /** 0 = sucesso testado · 1 = erro tipo 1 · 2 = erro tipo 2 */
  exitCode: 0 | 1 | 2;
  message?: string | undefined;
  addenda?: Addendum[] | undefined;
}

/**
 * Resultado padronizado de um passo da cadeia:
 *   sucesso -> nextIssue = próxima indexada (ou null se cadeia completa)
 *   erro    -> nextIssue = MESMA issue + continuidade explícita
 */
export function runChainStep(
  step: BlueprintStep,
  outcome: ChainOutcome,
  id?: string,
): ActionEnvelope {
  const addenda = [
    { kind: "path" as const, ref: "pipeline/blueprint.json", description: "blueprint da cadeia indexada" },
    ...(outcome.addenda ?? []),
  ];

  if (outcome.exitCode === 0) {
    return successEnvelope({
      id,
      message: outcome.message ?? `entrega de ${step.id} testada com sucesso (acceptance: ${step.acceptance})`,
      addenda,
      status: step.next === null ? "chain-complete" : "delivered",
      nextIssue: step.next,
    });
  }

  const errorType = outcome.exitCode === 1 ? 1 : 2;
  return errorEnvelope({
    id,
    message: outcome.message ?? "",
    addenda,
    sameIssue: step.id,
    errorType,
    continuityReason:
      errorType === 1
        ? `falha de execução/validação em ${step.id} — correção necessária; a MESMA issue permanece como nextIssue (continuidade)`
        : `pré-condição/continuidade violada em ${step.id} — resolver condição de contorno; a MESMA issue permanece como nextIssue (continuidade)`,
  });
}

/**
 * ActionEnvelope — o objeto JSON PADRÃO que TODO action do pipeline
 * (gate-driven, estilo blueprint/BPMN via GitHub Actions) deve retornar.
 *
 * Campos obrigatórios (contrato do usuário):
 *   id         string   — identificador único do action
 *   message    string   — mensagem/log (pode ser string vazia)
 *   addenda    Addendum[] — anexos gerados: paths, filenames, artefatos
 *   status     string   — estado do action ("success", "error", "continuity", …)
 *   nextIssue  string|null — MESMA issue (erro) ou PRÓXIMA indexada (sucesso testado)
 *   exitCode   0 | 1 | 2 — 0 sucesso · 1 erro tipo 1 · 2 erro tipo 2
 *
 * Semântica dos códigos de saída (também aplicada ao exit code do processo):
 *   0 = SUCESSO — entrega validada; avança para a próxima issue indexada
 *   1 = ERRO TIPO 1 — falha de execução/validação do passo (testes vermelhos,
 *       gate do passo falhou); retorna a MESMA issue + info de continuidade
 *   2 = ERRO TIPO 2 — falha de continuidade/pré-condição (issues abertas,
 *       CI/CD com erros, sem testes, infra); retorna a MESMA issue + info de
 *       continuidade explícita (`continuity`)
 */

import { randomUUID } from "node:crypto";

export type ExitCode = 0 | 1 | 2;

export const EXIT_CODES = {
  SUCCESS: 0,
  ERROR_TYPE_1: 1,
  ERROR_TYPE_2: 2,
} as const;

export interface Addendum {
  /** attachment = artefato gerado · path = diretório/arquivo · filename = arquivo · log = saída · url = link */
  kind: "attachment" | "path" | "filename" | "log" | "url";
  ref: string;
  description: string;
}

export interface ContinuityInfo {
  required: boolean;
  reason: string;
}

export interface ActionEnvelope {
  id: string;
  message: string;
  addenda: Addendum[];
  status: string;
  nextIssue: string | null;
  exitCode: ExitCode;
  at: string;
  continuity: ContinuityInfo;
}

export interface EnvelopeInput {
  id?: string | undefined;
  message?: string | undefined;
  addenda?: Addendum[] | undefined;
  status: string;
  nextIssue: string | null;
  exitCode: ExitCode;
  continuity?: ContinuityInfo | undefined;
  at?: string | undefined;
}

export function makeEnvelope(input: EnvelopeInput): ActionEnvelope {
  return {
    id: input.id ?? `action-${randomUUID()}`,
    message: input.message ?? "",
    addenda: input.addenda ?? [],
    status: input.status,
    nextIssue: input.nextIssue,
    exitCode: input.exitCode,
    at: input.at ?? new Date().toISOString(),
    continuity: input.continuity ?? { required: false, reason: "" },
  };
}

export function successEnvelope(input: {
  id?: string | undefined;
  message?: string | undefined;
  addenda?: Addendum[] | undefined;
  status?: string | undefined;
  nextIssue: string | null;
}): ActionEnvelope {
  return makeEnvelope({
    ...input,
    status: input.status ?? "success",
    exitCode: EXIT_CODES.SUCCESS,
    continuity: { required: input.nextIssue !== null, reason: input.nextIssue !== null ? "cadeia avança para a próxima issue indexada" : "" },
  });
}

export function errorEnvelope(input: {
  id?: string | undefined;
  message?: string | undefined;
  addenda?: Addendum[] | undefined;
  status?: string | undefined;
  sameIssue: string;
  errorType: 1 | 2;
  continuityReason: string;
}): ActionEnvelope {
  return makeEnvelope({
    id: input.id,
    message: input.message ?? "",
    addenda: input.addenda,
    status: input.status ?? (input.errorType === 1 ? "error" : "continuity"),
    nextIssue: input.sameIssue,
    exitCode: input.errorType,
    continuity: { required: true, reason: input.continuityReason },
  });
}

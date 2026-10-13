/**
 * Webhook real (GitHub → POST /api/events): autenticidade por assinatura.
 *
 * O GitHub assina cada entrega com `X-Hub-Signature-256`:
 *   "sha256=" + hex(HMAC-SHA256(secret, corpo_cru_da_requisição))
 *
 * Regras:
 *   - a comparação é TIMING-SAFE (crypto.timingSafeEqual);
 *   - o HMAC é calculado sobre o corpo CRU (bytes exatos recebidos) — nunca
 *     sobre JSON re-serializado;
 *   - secret vem do operador (env `GITHUB_WEBHOOK_SECRET` ou opção do server);
 *     nós nunca criamos nem guardamos credenciais.
 */

import { createHmac, timingSafeEqual } from "node:crypto";

/** "sha256=<hex>" do corpo cru — o mesmo valor que o GitHub envia. */
export function signWebhook(secret: string, rawBody: string): string {
  const mac = createHmac("sha256", secret).update(rawBody, "utf8").digest("hex");
  return `sha256=${mac}`;
}

/**
 * Verifica o header `X-Hub-Signature-256` contra o corpo cru.
 * Retorna false para header vazio, formato inválido, tamanho diferente
 * ou HMAC divergente — nunca lança.
 */
export function verifyWebhookSignature(
  secret: string,
  rawBody: string,
  signatureHeader: string,
): boolean {
  if (secret === "" || signatureHeader === "") return false;
  const expected = Buffer.from(signWebhook(secret, rawBody), "utf8");
  const received = Buffer.from(signatureHeader, "utf8");
  if (expected.length !== received.length) return false;
  return timingSafeEqual(expected, received);
}

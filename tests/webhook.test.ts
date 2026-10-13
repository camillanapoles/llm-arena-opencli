/**
 * Webhook real (ISSUE-2): autenticidade (X-Hub-Signature-256) + ingestão
 * (X-GitHub-Event) respondendo envelope/JSON de gates.
 */
import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import type { Server } from "node:http";
import type { AddressInfo } from "node:net";
import { createApp, seedDefaults, type App } from "../src/app.ts";
import { createHttpServer } from "../src/server.ts";
import { MockTransport } from "../src/drivers/transport.ts";
import { signWebhook, verifyWebhookSignature } from "../src/gate/webhook.ts";

const SECRET = "segredo-do-operador-para-o-webhook";

let app: App;
let server: Server;
let base: string;

before(async () => {
  const transport = new MockTransport();
  app = createApp({ dbPath: ":memory:", transport, log: () => {}, webhookSecret: SECRET });
  seedDefaults(app);
  server = createHttpServer(app);
  await new Promise<void>((resolve) => {
    server.listen(0, "127.0.0.1", () => resolve());
  });
  base = `http://127.0.0.1:${(server.address() as AddressInfo).port}`;
});

after(async () => {
  await new Promise<void>((resolve) => server.close(() => resolve()));
  app.close();
});

/** POST assinado como o GitHub faz: HMAC-SHA256 sobre o corpo CRU. */
async function postSigned(
  event: string,
  payload: unknown,
  options: { secret?: string | false; bodyText?: string } = {},
) {
  const bodyText = options.bodyText ?? JSON.stringify(payload);
  const headers: Record<string, string> = {
    "Content-Type": "application/json",
    "X-GitHub-Event": event,
  };
  const secret = options.secret === false ? undefined : (options.secret ?? SECRET);
  if (secret !== undefined) headers["X-Hub-Signature-256"] = signWebhook(secret, bodyText);
  const response = await fetch(`${base}/api/events`, { method: "POST", headers, body: bodyText });
  const text = await response.text();
  return {
    status: response.status,
    body: text === "" ? null : (JSON.parse(text) as Record<string, unknown>),
  };
}

// ------------------------------------------------------------ primitiva HMAC

test("signWebhook: vetor conhecido HMAC-SHA256 (RFC 4231 caso 2)", () => {
  assert.equal(
    signWebhook("Jefe", "what do ya want for nothing?"),
    "sha256=5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843",
  );
});

test("verifyWebhookSignature: aceita assinatura correta e rejeita adulteração", () => {
  const raw = JSON.stringify({ action: "opened" });
  const signature = signWebhook(SECRET, raw);
  assert.equal(verifyWebhookSignature(SECRET, raw, signature), true);
  assert.equal(verifyWebhookSignature(SECRET, raw + " ", signature), false, "corpo adulterado");
  assert.equal(verifyWebhookSignature("outro-secret", raw, signature), false, "secret errado");
  assert.equal(verifyWebhookSignature(SECRET, raw, ""), false, "header vazio");
  assert.equal(verifyWebhookSignature(SECRET, raw, "sha256=aa"), false, "tamanho errado");
  assert.equal(verifyWebhookSignature("", raw, signature), false, "sem secret não valida");
});

// --------------------------------------------------- ingestão com assinatura

test("webhook real: entrega assinada (push) é aceita e responde JSON de gates", async () => {
  const result = await postSigned("push", {
    ref: "refs/heads/arena/d917b13b-llm-arena-opencli",
    repository: { full_name: "camillanapoles/llm-arena-opencli" },
    pusher: { name: "x" },
  });
  assert.equal(result.status, 200);
  assert.equal(result.body?.["ok"], true);
  assert.ok(Array.isArray(result.body?.["outcomes"]), "resposta carrega outcomes dos gates");
  const outcomes = result.body?.["outcomes"] as Array<{ gateId: string; runId: string }>;
  assert.ok(outcomes.length > 0, "ao menos um gate processou o evento");
  assert.ok(outcomes[0]?.runId !== "", "cada outcome referencia o run");
});

test("webhook real: assinatura inválida ⇒ 401 e evento NÃO processado", async () => {
  const before = app.events.list().length;
  const result = await postSigned("push", { ref: "refs/heads/x" }, { secret: "secret-errado" });
  assert.equal(result.status, 401);
  assert.equal(result.body?.["ok"], false);
  assert.equal(app.events.list().length, before, "nada foi ingestado");
});

test("webhook real: secret configurado e entrega sem assinatura ⇒ 401", async () => {
  const result = await postSigned("push", { ref: "refs/heads/x" }, { secret: false });
  assert.equal(result.status, 401);
});

test("webhook real: corpo adulterado rejeita a assinatura original", async () => {
  const original = JSON.stringify({ ref: "refs/heads/ok" });
  const tampered = JSON.stringify({ ref: "refs/heads/ok", extra: 1 });
  const result = await postSigned("push", undefined, {
    bodyText: tampered,
  });
  // assinatura calculada sobre o corpo enviado (tampered) ⇒ passa;
  // agora reenvia o corpo com assinatura do original
  const response = await fetch(`${base}/api/events`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "X-GitHub-Event": "push",
      "X-Hub-Signature-256": signWebhook(SECRET, original),
    },
    body: tampered,
  });
  assert.equal(result.status, 200, "entrega coerente passa");
  assert.equal(response.status, 401, "assinatura do corpo original não valida o corpo editado");
});

// ---------------------------------------------------------------- ping

test("webhook real: handshake ping responde pong sem executar gates", async () => {
  const before = app.events.list().length;
  const result = await postSigned("ping", { zen: "Keep it logically awesome.", hook_id: 42 });
  assert.equal(result.status, 200);
  assert.equal(result.body?.["pong"], true);
  assert.equal(result.body?.["zen"], "Keep it logically awesome.");
  assert.equal(result.body?.["hook_id"], 42);
  assert.equal(app.events.list().length, before, "ping não ingere evento de gate");
});

// ------------------------------------------------------- modo legado (sem secret)

test("modo legado: sem secret configurado o fluxo X-GitHub-Event continua funcionando", async () => {
  const transporte = new MockTransport();
  const app2 = createApp({
    dbPath: ":memory:",
    transport: transporte,
    log: () => {},
    webhookSecret: "",
  });
  seedDefaults(app2);
  const servidor = createHttpServer(app2);
  await new Promise<void>((resolve) => servidor.listen(0, "127.0.0.1", () => resolve()));
  const porta = `http://127.0.0.1:${(servidor.address() as AddressInfo).port}`;
  const response = await fetch(`${porta}/api/events`, {
    method: "POST",
    headers: { "Content-Type": "application/json", "X-GitHub-Event": "repository_dispatch" },
    body: JSON.stringify({ action: "opencli-command" }),
  });
  const body = (await response.json()) as Record<string, unknown>;
  assert.equal(response.status, 200);
  assert.equal(body["ok"], true);
  await new Promise<void>((resolve) => servidor.close(() => resolve()));
  app2.close();
});

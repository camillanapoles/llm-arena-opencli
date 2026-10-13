# WEBHOOK.md — webhook real conectado ao `POST /api/events`

> **ISSUE-2** (issue #4). O backend já fala o protocolo real do GitHub:
> assinatura `X-Hub-Signature-256` (HMAC-SHA256, comparação timing-safe),
> handshake `ping`, ingestão por `X-GitHub-Event` respondendo o JSON de
> gates. Este guia cobre o **registro** do webhook — a credencial (secret) é
> criada **por você**; nenhum token ou secret é pedido, criado ou guardado
> por nós.

---

## 1. O que o backend valida

| Cabeçalho | Uso |
| --- | --- |
| `X-GitHub-Event` | tipo do evento (`push`, `pull_request`, `repository_dispatch`, `ping`, …) → normalizado e disparado nos gates |
| `X-Hub-Signature-256` | `sha256=hex(HMAC-SHA256(secret, corpo cru))` — **obrigatório** quando `GITHUB_WEBHOOK_SECRET` está configurado; assinatura inválida ⇒ **401** e o evento **não** é processado |
| `X-GitHub-Delivery` | UUID da entrega (para reenvio/rastreio; ignorado pela lógica) |

Fluxo:

```
GitHub (push/PR/dispatch/…)
   │  POST + X-GitHub-Event + X-Hub-Signature-256
   ▼
POST /api/events ── valida HMAC ──► parseWebhook ──► GateDriver ──► runs
   │                                                            (SQLite)
   └── 200 { ok, event, outcomes: [{gateId, status, blocking, runId, steps}] }
        ping  ──► 200 { ok: true, pong: true, zen }
        HMAC ✗ ──► 401 { ok: false, error }
```

## 2. Configurar o secret (você faz, uma vez)

```bash
# gere um valor forte (ex.: 32 bytes aleatórios) e guarde no SEU cofre
openssl rand -hex 32

# no servidor/backend: exportar a MESMA variável
export GITHUB_WEBHOOK_SECRET="<valor que você gerou>"
```

- Local/UI: *Settings → Secrets and variables → Actions* **não serve** (é de
  workflows); o secret do webhook é digitado **na tela de registro do webhook**
  (passo 3).
- Nunca commite o valor. `GITHUB_WEBHOOK_SECRET` vazio = modo legado (sem
  verificação) — não use em produção.

## 3. Registrar o webhook no repositório

### Opção A — interface (Settings → Webhooks → Add webhook)

| Campo | Valor |
| --- | --- |
| Payload URL | `https://<host-do-backend>/api/events` |
| Content type | `application/json` |
| Secret | o valor do passo 2 |
| SSL | ✅ *Enable SSL verification* |
| Events | *Let me select individual events*: `push`, `pull_request`, `repository_dispatch`, `issues`, `issue_comment`, `workflow_run`, `workflow_dispatch` |
| Active | ✅ |

Ao salvar, o GitHub envia um **`ping`** — a entrega deve aparecer como
*200 OK* e a resposta contém `"pong": true`.

### Opção B — `gh api` (script pronto)

```bash
GITHUB_WEBHOOK_SECRET="<seu secret>" \
  bash scripts/registrar-webhook.sh https://<host-do-backend>/api/events
```

O script cria (ou atualiza) o hook via `gh api repos/{owner}/{repo}/hooks`
com a lista de eventos padrão. Requer `gh` autenticado com permissão de
administração do repositório (**seu** login; nada é retido).

## 4. Testar

1. **Ping:** na tela do webhook, *Recent Deliveries → ping → Redeliver* (ou `gh api …/hooks/{id}/pings`).
2. **Evento real:** `git push` qualquer → *Recent Deliveries* mostra `push` 200 e
   `{"ok":true,...,"outcomes":[...]}`.
3. **Reenvio:** *Redeliver* na entrega — o servidor é idempotente por evento
   (runs novos por entrega; gates bloqueantes/advisory inalterados).

Sem endpoint público (ambiente local/efêmero)? Use o **fluxo equivalente**
(§5) — a cadeia evento→gate→JSON é a mesma.

## 5. Fluxo equivalente (já exercitado em CI)

| Via | Comando | Observação |
| --- | --- | --- |
| `workflow_dispatch` | `gh workflow run opencli-driver.yml -f mode=dispatch -f command=ping -f target_repo=camillanapoles/OpenCLI` | dispara `repository_dispatch` no fork com `OPENCLI_TOKEN` |
| `repository_dispatch` direto | `gh api -X POST repos/camillanapoles/OpenCLI/dispatches -f event_type=opencli-command -f client_payload[command]=ping` | exige token com `contents: write` no alvo |
| CLI local | `npm run gate -- receive --event push --ref refs/heads/main` | injeta o evento no driver sem HTTP |

Todos terminam no mesmo `GateDriver.receive` do `POST /api/events`.

## 6. Segurança (resumo)

- HMAC-SHA256 sobre o **corpo cru** + `timingSafeEqual` (sem oracle de timing).
- Secret apenas do operador (env `GITHUB_WEBHOOK_SECRET`); repositórios,
  tokens e credenciais **nunca** ficam no código ou no histórico.
- Recomendado: HTTPS obrigatório no host do backend; rotacione o secret em
  *Recent Deliveries → Update secret*.
- `401` derruba a entrega sem tocar nos gates (evento não entra no SQLite).

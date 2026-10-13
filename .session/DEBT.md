# DEBT.md — débitos técnicos (IGC v1.0, M5)

> Débito é cidadão de primeira classe: descrição, causa, impacto,
> gatilho de retomada. Evento `DEBT` é emissão legítima.

## D1 — Deploy público do backend + registro efetivo do webhook

- **Descrição:** o `POST /api/events` está pronto para webhook real (assinatura
  HMAC `X-Hub-Signature-256` + handshake `ping`), mas o registro efetivo do
  webhook no GitHub exige uma **URL pública de payload** (o backend roda em
  ambiente efêmero sem endpoint público).
- **Causa:** infraestrutura de deploy fora do escopo do sandbox.
- **Impacto:** baixo — o fluxo equivalente `repository_dispatch` /
  `workflow_dispatch` já exercita a mesma cadeia evento→gate→JSON, e o
  registro fica documentado (`docs/WEBHOOK.md` + `scripts/registrar-webhook.sh`).
- **Gatilho de retomada:** usuário definir host/URL do backend (ou fazer merge
  e publicar) → rodar `scripts/registrar-webhook.sh` com a URL e o secret.

## D2 — Testes de dispatch do OPENCLI_TOKEN no terminal do usuário

- **Descrição:** os 2 comandos de teste do secret (`gh api …/dispatches` e
  `gh workflow run opencli-driver.yml …`) ainda não foram confirmados fora do sandbox.
- **Causa:** token do sandbox sem `actions: write` (403 verificado).
- **Impacto:** médio — validação final do modo `dispatch` do opencli-driver.
- **Gatilho de retomada:** usuário rodar os comandos de `docs/SECRETS.md`.

## D3 — Merge do PR #1 (ação humana)

- **Descrição:** PR #1 está MERGEABLE/CLEAN com gate de teste verde; merge é
  exclusivamente do mantenedor (e encerra a sessão Arena).
- **Gatilho de retomada:** decisão do usuário.

## D4 — ISSUE-3 da cadeia (publicar arena-runtime.wasm)

- **Descrição:** próximo passo indexado após ISSUE-2 (`pipeline/blueprint.json`).
- **Gatilho de retomada:** ciclo `npm run pipeline -- cycle --id ISSUE-3` após ISSUE-2 `delivered`.

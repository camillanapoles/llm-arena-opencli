# INTENT.md — objetivo global, escopo e critérios de aceite (IGC v1.0)

## Objetivo global

Fork `llm-arena-opencli` com **duas pilhas unificadas** sob o mesmo fluxo
gate-driven (decisão em `docs/04-decisao-unificacao.md`):

- **Pilha A (Node/TS + WASM):** GitHub Actions runtime como driver — gate
  events → gates → funções de runtime (factory), backend cache+SQLite+CRUD,
  envelope único de pipeline, WASM para web (`arena.ai/agent`).
- **Pilha B (Python/CJK CNJ):** consulta processual DataJud + DJEN, pipeline
  de gates JSON 0/1/2, fábrica de issues POO+SQLite.

Governança de continuidade: **IGC v1.0** (esta) — sessão efêmera, repositório
é a memória; worktree = território, branch = linhagem; nada sem commit;
emissões rotuladas (`FIX`/`CONTINUE`/`IMPLEMENT`/`DEBT`); resumibilidade
absoluta via `.session/`.

## Escopo desta sessão (`d917b13b`)

1. **IMPLEMENT — IGC v1.0**: infraestrutura `.session/` (WAL, STATE.yml,
   INTENT, CONTEXT, DEBT, CHECKPOINT, bootstrap.sh + hooks) e disciplina de
   emissão rotulada.
2. **IMPLEMENT — ISSUE-2** (issue #4): *Webhook real conectado ao POST
   `/api/events`* — verificação de assinatura `X-Hub-Signature-256` (HMAC
   SHA-256, comparação timing-safe), handshake `ping`, roteiro + script de
   registro do webhook no GitHub, e fluxo equivalente via
   `repository_dispatch`/`workflow_dispatch` já exercitado.

## Critérios de aceite

| # | Critério | Fonte |
| --- | --- | --- |
| A1 | `npm run ci` verde (typecheck + wasm + testes) | issue #4 `ACCEPTANCE` |
| A2 | Teste de ingestão de evento (`X-GitHub-Event`) respondendo envelope/JSON de gates, **com validação de assinatura** | issue #4 |
| A3 | Handshake `ping` do GitHub respondido sem executar gates | webhook real |
| A4 | Roteiro reproduzível de registro do webhook (UI + `gh api`) + secret criado **pelo usuário** (nunca por nós) | IGC + política de credenciais |
| A5 | `.session/` completo e consistente: WAL append-only, FSM em STATE.yml, CHECKPOINT coerente com `git fsck`, bootstrap verde | IGC Art. 2 |
| A6 | Emissão ao GitHub rotulada + SHA de checkpoint + âncora no WAL | IGC E3 |

## Fora de escopo (registrado em `DEBT.md`)

- Deploy público do backend (URL real de payload) — depende de infra do usuário.
- `OPENCLI_TOKEN` dispatch tests no terminal do usuário; merge do PR #1 (ação humana).

## M6 (v2.1) — skips NUNCA são silenciosos
- **Únicos skips da suíte Python** (`make testes`, `testar_pipeline`): `mock_sinc_desabilitado` e `mock_sinc_habilitado` **pulam com `pytest.skip` quando PyYAML não está instalado** (2 casos, ~120ms). Motivo: PyYAML não é dependência do kit (bootstrap Python puro); os mocks de sincronização YAML exigem o módulo. Não afetam gates reais — os casos restantes cobrem o contrato. Registrado aqui conforme M6; se PyYAML entrar no kit, os skips deixam de existir.
- **Desvio A2'** (branch fixa da Arena atuando como linhagem designada) declarado em `CONTEXT.md` e registrado no registry/profile.

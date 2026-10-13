# Contexto de sessão — llm-arena-opencli

> **Contrato de continuidade:** este arquivo + `session/state.json` são a
> memória oficial da sessão. Se a sessão do Arena terminar (ex.: após merge do
> PR), qualquer novo ator retoma por aqui — via nova sessão apontando para este
> arquivo, via `/session continue` na issue de continuidade, via
> `gh workflow run continuity.yml` ou via `repository_dispatch: session-continue`.

## 1. Objetivo original (pedido do usuário)

Criar uma versão de desenvolvimento (branch do fork) voltada a **interação
autônoma via GitHub Actions + CI/CD**:

1. **Gate driver por triggers/gate events** — a automação dispara por gatilhos
   do GitHub (`push`, `pull_request`, `workflow_run`, `repository_dispatch`,
   `issue_comment`, `schedule`, `workflow_dispatch`).
2. **Backend + cache + SQLite + CRUD + functions com pattern factory** para
   criação de funções.
3. **Usar o runtime do GitHub Actions como driver do repositório**
   [jackwener/OpenCLI](https://github.com/jackwener/OpenCLI).
4. **WebAssembly best practices** para uso web em
   [arena.ai/agent](https://arena.ai/agent).

## 2. Estado atual

| Item | Valor |
| --- | --- |
| Branch de desenvolvimento | `arena/d917b13b-llm-arena-opencli` |
| PR | [#1](https://github.com/camillanapoles/llm-arena-opencli/pull/1) (aberto, base `main`) |
| Commit base do driver | `70d10f4` |
| Pipeline local | `npm run ci` verde (typecheck + wasm + testes) |
| Continuidade | `continuity.yml` + `session/` (este documento) |

## 3. Arquitetura entregue

```
src/
├── core/types.ts          # domínio: GateEvent, GateDefinition, FunctionSpec, RunRecord
├── db/                    # SQLite (node:sqlite): schema + Database
├── cache/cache.ts         # TTL+LRU com write-through SQLite
├── crud/                  # CrudRepository<T> + FunctionsRepo/GatesRepo/RunsRepo/EventsRepo
├── functions/factory.ts   # FunctionFactory (pattern factory, sem eval)
├── functions/builtins.ts  # echo, cache.*, sql.query, github.event, opencli.dispatch, log
├── gate/events.ts         # normalização de webhooks → GateEvent + matchesTrigger
├── gate/gate-driver.ts    # executa pipelines dos gates; blocking vs advisory
├── drivers/               # GitHubActionsDriver + OpenCLIDriver (transport injetável)
├── server.ts              # API REST (node:http, zero deps de produção)
├── session/store.ts       # ESTA continuidade: estado + briefing de retomada
└── cli/                   # gate-cli.ts (servir/seed/receive/list/opencli) e session-cli.ts
wasm/                      # AssemblyScript (335B, 0 imports) + loader web best-practice
.github/workflows/         # ci.yml · gate-driver.yml · opencli-driver.yml · continuity.yml
```

- Gates **blocking** derrubam o CI (exit 1); **advisory** só reportam.
- Funções CRUD nunca são `eval`adas: o factory instancia `RuntimeFunction` a
  partir de `FunctionBlueprint`.
- `opencli.dispatch` dispara `repository_dispatch` (`opencli-command`) no repo
  alvo; `opencli-driver.yml` executa o manifesto no runtime do Actions.

## 4. Convenções do repositório

- TypeScript **erasable-syntax only** (Node roda `.ts` direto via type
  stripping) — sem `enum`, sem parameter properties, imports com extensão `.ts`.
- Zero dependências de produção; dev deps: `typescript`, `@types/node`,
  `assemblyscript`.
- Testes com `node:test` em `tests/*.test.ts` (46+ testes).
- Artefatos gerados (`wasm/dist/`, `data/`, `node_modules/`) fora do git.

## 5. Próximas ações declaradas

1. Aguardar review/merge do PR #1 — **o merge encerra a sessão do Arena**;
   o `continuity.yml` reage ao merge criando `arena/continuity-<ts>` +
   draft PR com briefing (mesmo repo).
2. Configurar secret `OPENCLI_TOKEN` (repo scope) para o modo `dispatch` do
   `opencli-driver.yml` atuar de verdade em `jackwener/OpenCLI`.
3. Conectar o endpoint `/api/events` ao webhook real do GitHub (ou manter o
   fluxo via `gh workflow run` / `repository_dispatch`).
4. Publicar `arena-runtime.wasm` para consumo direto do front em arena.ai/agent
   (artifact `arena-runtime-wasm` já publicado pelo `ci.yml`).

## 6. Segunda via (continuidade sem sessão)

| Gatilho | Efeito |
| --- | --- |
| Merge do PR | `continuity.yml` cria branch `arena/continuity-<ts>` + draft PR com briefing + comentário no PR mesclado |
| Comentário `/session continue` (issue rotulada `session-continuity`) | briefing + checkpoint + branch de continuidade |
| Comentário `/session checkpoint [nota]` | checkpoint no `session/state.json` (commit bot) |
| Comentário `/session branch` | cria branch de continuidade imediatamente |
| Comentário `/session heartbeat` | roda os gates (`npm run ci`) e reporta |
| `gh workflow run continuity.yml -f action=...` | mesma superfície via GH CLI |
| `gh api repos/<owner>/<repo>/dispatches -f event_type=session-continue` | webhook externo |
| `schedule` (6/6h) | heartbeat dos gates + estado |

O heartbeat e o `gate-driver.yml` mantêm **todas as funções CI/CD ativas** no
GitHub Actions mesmo sem nenhuma sessão aberta.

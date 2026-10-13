# llm-arena-opencli

**CI/CD-native automation driver** — a fork-development branch of the
[OpenCLI](https://github.com/jackwener/OpenCLI) concept in which **the GitHub
Actions runtime is the driver**: gate events (workflow triggers) fire gates,
gates execute runtime functions created by a **factory**, and everything is
backed by a **cache + SQLite + CRUD** backend — with a **WebAssembly core** so
the same gate logic can run on the web at [arena.ai/agent](https://arena.ai/agent).

> **Branch note (pt-BR):** esta sessão está fixada na branch
> `arena/d917b13b-llm-arena-opencli`, que funciona como a *branch de
> desenvolvimento* deste fork. Todo o trabalho acontece aqui.

---

## Visão geral / Overview

```
 GitHub gate events                      GitHub Actions runtime
 (push, PR, workflow_run,                (o runner É o driver)
  repository_dispatch,                          │
  issue_comment "/gate run", ──►  GateDriver ───┼──► FunctionFactory
  schedule, workflow_dispatch)        │         │        │
                                      ▼         │        ▼
                                 SQLite runs ◄──┴── RuntimeFunctions
                                 + cache TTL        (echo, cache.*, sql.query,
                                 + CRUD API          github.event, opencli.dispatch,
                                                     log, …blueprints)
                                      │
                                      ▼
                          WASM core (arena-runtime.wasm)
                          mesmas decisões de gate no browser
                          → https://arena.ai/agent
```

### O que cada peça faz

| Camada | Onde | Papel |
| --- | --- | --- |
| **Gate events / triggers** | `src/gate/events.ts`, `.github/workflows/gate-driver.yml` | Normaliza webhooks do GitHub em `GateEvent` e decide quais gates disparam (`events`, `refs`, `actorAllow`) |
| **Gate driver** | `src/gate/gate-driver.ts` | Executa o pipeline de funções de cada gate, grava `runs` no SQLite, cacheia a última decisão; gates **blocking** derrubam o CI, **advisory** só reportam |
| **Backend** | `src/server.ts`, `src/cli/gate-cli.ts` | API HTTP REST (`node:http`, zero deps de produção) + CLI usada pelos workflows |
| **Cache** | `src/cache/cache.ts` | TTL + LRU em memória com *write-through* para SQLite (sobrevive a jobs) |
| **SQLite DB** | `src/db/` (`node:sqlite`) | `functions`, `gates`, `runs`, `events`, `cache` |
| **CRUD** | `src/crud/` | `CrudRepository<T>` genérico + repos concretos (`FunctionsRepo`, `GatesRepo`, `RunsRepo`, `EventsRepo`) |
| **Function factory** | `src/functions/factory.ts`, `builtins.ts` | **Pattern factory**: `FunctionBlueprint.create(spec) → RuntimeFunction`; CRUD nunca `eval`ua código — sempre instancia via factory |
| **GitHub Actions driver** | `src/drivers/github-actions.driver.ts` | `repository_dispatch` / `workflow_dispatch` / polling de runs — o runtime do Actions como atuador do repo alvo (`jackwener/OpenCLI` por padrão) |
| **OpenCLI driver** | `src/drivers/opencli.driver.ts` | Transforma intenções em *command manifests* executados pelo runtime do Actions |
| **WASM core** | `wasm/` | Primitivas de gate/cache em AssemblyScript + loader web com best practices (`instantiateStreaming`, scratch buffer, magic check, API congelada) |
| **Continuidade** | `src/session/`, `src/cli/session-cli.ts`, `.github/workflows/continuity.yml` | Contexto de sessão durável (`session/`) + handoff automático de branch/PR no merge + segunda via via GH CLI/webhook/comentário |
| **Pipeline BPMN** | `src/pipeline/`, `src/cli/pipeline-cli.ts`, `pipeline/blueprint.json`, `.github/workflows/blueprint.yml` | Envelope JSON padrão (id/message/addenda/status/nextIssue/exitCode 0/1/2) + gate de continuidade + cadeia de issues indexadas |

## Quick start

```sh
npm install
npm run ci            # typecheck + build:wasm + test

npm run seed          # cria functions + gates padrão
npm run gate -- --event push --ref refs/heads/main   # roda os gates (exit 1 se blocking falhar)
npm start             # backend em http://0.0.0.0:8787
```

## Backend API

| Método & rota | Descrição |
| --- | --- |
| `GET /health` | status + contagens |
| `GET /api/kinds` | blueprints registrados na factory |
| `GET/POST /api/functions`, `GET/PATCH/DELETE /api/functions/:id` | CRUD de funções (kind validado pela factory) |
| `GET/POST /api/gates`, `GET/PATCH/DELETE /api/gates/:id` | CRUD de gates |
| `GET /api/runs?gateId=`, `GET /api/runs/:id` | histórico de execuções |
| `POST /api/events` | ingere um gate event (JSON ou webhook `X-GitHub-Event`) e roda os gates |
| `GET /api/events` | eventos recebidos |
| `GET /api/cache/stats`, `GET/PUT/DELETE /api/cache/:key` | cache |
| `POST /api/opencli/run` | despacha um comando OpenCLI via Actions runtime |

CORS é configurável (`ARENA_CORS_ORIGIN`, default `*`) para chamadas vindas da
web em `arena.ai/agent`. Banco em `ARENA_DB_PATH` (default `data/arena.db`).

### Exemplo: criar função via factory + gate via CRUD

```sh
curl -X POST localhost:8787/api/functions -H 'content-type: application/json' -d '{
  "id": "fn-echo-1", "kind": "echo", "name": "Echo demo", "params": {}
}'

curl -X POST localhost:8787/api/gates -H 'content-type: application/json' -d '{
  "id": "gate-demo",
  "name": "Demo gate",
  "policy": "blocking",
  "trigger": { "events": ["push"], "refs": ["refs/heads/main"] },
  "functions": ["fn-echo-1"]
}'

curl -X POST localhost:8787/api/events -H 'content-type: application/json' \
  -d '{ "type": "push", "ref": "refs/heads/main", "payload": {} }'
```

## Workflows (CI/CD ➞ gate driver por triggers)

| Workflow | Gatilhos | Papel |
| --- | --- | --- |
| `ci.yml` | `push`, `pull_request`, `workflow_dispatch` | Gates do repo: typecheck, build do WASM, testes, smoke do backend; publica `arena-runtime-wasm` |
| `gate-driver.yml` | `workflow_run` (do `ci`), `repository_dispatch: gate-event`, `issue_comment` (`/gate run`), `schedule`, `workflow_dispatch` | **Gate driver**: transforma o evento em execução de gates, grava estado em SQLite, publica artifact, reage ao comentário `/gate run` |
| `opencli-driver.yml` | `workflow_dispatch`, `repository_dispatch: opencli-command` | **Driver do OpenCLI**: modo `runtime` (executa o manifesto dentro do runner) e modo `dispatch` (fira `repository_dispatch` em `jackwener/OpenCLI`) |
| `continuity.yml` | `pull_request: closed`, `push`, `repository_dispatch: session-*`, `issue_comment` (`/session …`), `schedule`, `workflow_dispatch` | **Continuidade da sessão**: handoff automático no merge (branch + draft PR), checkpoint do contexto, heartbeat |
| `blueprint.yml` | `issues: closed`, `workflow_dispatch`, `repository_dispatch: pipeline-*`, `schedule` | **Pipeline gate-driven (BPMN)**: gate de continuidade (issues/CI/testes) + cadeia de issues indexadas com envelope JSON |

Como `workflow_run` encadeia os fluxos: cada conclusão do `ci` volta a entrar
como *gate event* no `gate-driver` — a fiação de automação é self-hosted no
próprio Actions.

## 🔁 Continuidade da sessão (a "segunda via")

> **O merge do PR encerra a sessão do Arena — não encerra o fluxo.** Toda a
> continuidade é garantida por GitHub Actions + contexto versionado em git.

| Gatilho (GH CLI / webhook / UI) | Efeito |
| --- | --- |
| **Merge do PR** (`pull_request: closed`) | `continuity.yml` cria automaticamente a branch `arena/continuity-<ts>` **no mesmo repo** + draft PR com *briefing de retomada* + comentário no PR mesclado |
| `push` em `main`/`arena/**` | Checkpoint automático: `session/state.json` commitado pelo bot + artifact `session-context-*` |
| Comentário `/session continue` | Briefing + checkpoint + branch de continuidade |
| Comentário `/session checkpoint [nota]` | Checkpoint com nota |
| Comentário `/session branch` | Cria a branch de continuidade agora |
| Comentário `/session heartbeat` | Roda os gates (`npm run ci`) e reporta (verde/vermelho) |
| `gh workflow run continuity.yml -f action=continue` | Mesma superfície via GH CLI |
| `gh api repos/<owner>/<repo>/dispatches -f event_type=session-continue` | Webhook externo (`session-continue`, `session-checkpoint`, `session-branch`) |
| `schedule` (6/6h) | Heartbeat: gates vivos + re-dispara `gate-driver.yml` + reporta na issue `session-continuity` |

**Contexto durável:** `session/CONTEXT.md` (metas, arquitetura, convenções,
próximas ações) + `session/state.json` (checkpoints, status, PR/branch) —
versionados em git e publicados como artifacts. Qualquer novo ator retoma com:

```sh
npm run session -- resume          # briefing completo de retomada
npm run session -- checkpoint --note "..." --event manual
npm run session -- branch-name     # nome sugerido p/ próxima branch
```

Sem sessão aberta, a automação continua de pé: `gate-driver.yml` segue
reagindo a gate events, o heartbeat roda os gates a cada 6h e os comandos
`/session ...` na issue de continuidade operam tudo pela interface do GitHub.

## 🚦 Pipeline gate-driven (blueprint/BPMN) + envelope JSON padrão

**Relatório completo de entrega (solicitado → timeline → realizado → testado →
validado → produção): [`DELIVERY.md`](DELIVERY.md).**

Todo action do pipeline retorna **UM objeto JSON padrão**:

```json
{ "id": "…", "message": "…", "addenda": [{ "kind": "path", "ref": "…", "description": "…" }],
  "status": "…", "nextIssue": "ISSUE-2 | mesma | null", "exitCode": 0,
  "direction": "continue | fix | debt | complete | hold" }
```

`exitCode`: **0** sucesso (avança para a próxima issue indexada) · **1** erro
tipo 1 (validação/execução → MESMA issue + continuidade) · **2** erro tipo 2
(pré-condição/continuidade → MESMA issue + continuidade). `direction` norteia
o próximo movimento: `continue`/`complete` (aprovado) · `fix` (corrigir a
mesma issue) · `debt` (registrar débito e manter continuidade) · `hold`.

- **Gate de continuidade** (`blueprint.yml` → `pipeline-cli gate`): verifica a
  **não existência** de issues abertas ∨ CI/CD com erros ∨ SEM testes.
  Não positivo → `status: "continuity"` (o fluxo **continua**); positivo →
  `status: "production-ready"` (pronto para uso).
- **Cadeia indexada OO + SQLite** (`pipeline/blueprint.json`, domínio em
  `src/pipeline/domain.ts`): `PipelineIssue` (máquina de estados),
  `IssueRepository` (SQLite), `IssueFactory` (**event-driven**),
  `PipelineEngine` (**ciclos determinísticos** com validação de SUCESSO
  COMPLETO). A cada issue `[ISSUE-N]` completada, o acceptance testa a entrega;
  **sucesso → constrói a próxima issue indexada**; **erro → retorna erro +
  informações de continuidade** (reabre a MESMA issue).

```sh
npm run pipeline -- validate
npm run pipeline -- pending                                          # pendentes COM instrução
npm run pipeline -- cycle --id ISSUE-1 --log-file ci.log             # ciclo determinístico
npm run pipeline -- event --type issue.completed --issue ISSUE-1 --result 0
npm run pipeline -- gate --open-issues 0 --ci-failures 0 --tests-total 84 --tests-passed 84
npm run pipeline -- step --id ISSUE-1 --result 0
npm run pipeline -- next --after ISSUE-1
```

## WebAssembly (best practices para a web)

O núcleo `wasm/assembly/index.ts` exporta primitivas **puras** (`fnv1a`,
`gateMatch`, `evaluateGate`, `cacheEvictScore`, `combineHash`) — as mesmas
regras de `matchesTrigger` do driver — para o browser decidir gates sem
round-trip:

```js
import { loadArenaRuntime, maskFromTypes } from "./wasm/loader.mjs";
const rt = await loadArenaRuntime("./wasm/dist/arena-runtime.wasm");
const fires = rt.evaluateGate(maskFromTypes(["push"]), maskFromTypes(["push"]),
  0, 0, 0, 0, 0, 0); // 1 = gate dispara
```

Best practices aplicadas (detalhes em [`wasm/README.md`](wasm/README.md)):
magic-byte validation, `instantiateStreaming` + fallback, compilação separada
da instanciação (módulo cacheável), *scratch buffer* com comprimento explícito
(sem marshalling implícito), recriação de views após `memory.grow`, API
congelada, sem `eval`.

## Testes

`npm test` roda `node:test` sobre nove suítes (**84 testes**): `db`, `cache`,
`factory` (pattern factory + builtins), `gate-driver` (triggers, blocking vs
advisory, dispatch OpenCLI via mock transport), `server` (CRUD HTTP, webhooks,
CORS), `session` (continuidade: checkpoints, briefing, handoff), `pipeline`
(envelope JSON 0/1/2 + direction, continuity gate, chain executor), `domain`
(modelo OO: estados, SQLite, factory event-driven, ciclos determinísticos) e
`wasm` (vetores FNV-1a, paridade com a lógica TS de triggers).

## Créditos

- Conceito de “website como CLI para agentes”: [jackwener/OpenCLI](https://github.com/jackwener/OpenCLI)
- Runtime de automação web: [arena.ai/agent](https://arena.ai/agent)

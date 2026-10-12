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

Como `workflow_run` encadeia os fluxos: cada conclusão do `ci` volta a entrar
como *gate event* no `gate-driver` — a fiação de automação é self-hosted no
próprio Actions.

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

`npm test` roda `node:test` sobre seis suítes: `db`, `cache`, `factory`
(pattern factory + builtins), `gate-driver` (triggers, blocking vs advisory,
dispatch OpenCLI via mock transport), `server` (CRUD HTTP, webhooks, CORS) e
`wasm` (vetores FNV-1a, paridade com a lógica TS de triggers).

## Créditos

- Conceito de “website como CLI para agentes”: [jackwener/OpenCLI](https://github.com/jackwener/OpenCLI)
- Runtime de automação web: [arena.ai/agent](https://arena.ai/agent)

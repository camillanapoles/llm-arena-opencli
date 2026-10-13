# llm-arena-opencli

> **Um repositório, duas pilhas integradas pelo mesmo fluxo gate-driven** (decisão de
> unificação em [`docs/04-decisao-unificacao.md`](docs/04-decisao-unificacao.md), contrato
> único em [`pipeline/contract.schema.json`](pipeline/contract.schema.json), guia em
> [`docs/INTEGRATION.md`](docs/INTEGRATION.md)):
>
> **A)** driver de automação com o **GitHub Actions runtime como driver** (Node/TS + WASM,
> cache + SQLite + CRUD + factory) — PR #1, branch de desenvolvimento
> `arena/d917b13b-llm-arena-opencli`;
> **B)** **consulta processual nas APIs públicas do CNJ** (Python, DataJud + DJEN, pipeline
> de gates + fábrica de issues) — PRs #2/#5, já integrados ao `main`.

| Pilha | O que entrega | Entrada rápida |
| --- | --- | --- |
| **A — Driver (Node/TS + WASM)** | gate events → gates → funções de runtime (factory), backend cache+SQLite+CRUD, envelope único de pipeline, WASM para web | `npm run ci` · `npm run pipeline -- registry` |
| **B — CNJ (Python)** | relatório de processo (DataJud + DJEN), consultas agregadas, pipeline de gates JSON 0/1/2, fábrica event-driven POO+SQLite | `python3 main.py <numero-cnj>` · `bash tests/rodar-testes.sh` |

**Regra de merge (política do mantenedor):** o merge só pode "passar" quando os **testes
estiverem em sucesso** — as duas suítes (`npm run ci` = 92 testes Node/TS/WASM + suítes
Python offline) e o workflow `integration.yml` verdes. Conflitos com `main` resolvidos
neste branch (`.gitignore`, `README.md`, `pipeline/blueprint.json` unificado).

---


# Parte A — Driver de automação (Node/TS + WASM)


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

### Visão geral / Overview

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

#### O que cada peça faz

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

### Quick start

```sh
npm install
npm run ci            # typecheck + build:wasm + test

npm run seed          # cria functions + gates padrão
npm run gate -- --event push --ref refs/heads/main   # roda os gates (exit 1 se blocking falhar)
npm start             # backend em http://0.0.0.0:8787
```

### Backend API

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

#### Exemplo: criar função via factory + gate via CRUD

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

### Workflows (CI/CD ➞ gate driver por triggers)

| Workflow | Gatilhos | Papel |
| --- | --- | --- |
| `ci.yml` | `push`, `pull_request`, `workflow_dispatch` | Gates do repo: typecheck, build do WASM, testes, smoke do backend; publica `arena-runtime-wasm` |
| `gate-driver.yml` | `workflow_run` (do `ci`), `repository_dispatch: gate-event`, `issue_comment` (`/gate run`), `schedule`, `workflow_dispatch` | **Gate driver**: transforma o evento em execução de gates, grava estado em SQLite, publica artifact, reage ao comentário `/gate run` |
| `opencli-driver.yml` | `workflow_dispatch`, `repository_dispatch: opencli-command` | **Driver do OpenCLI**: modo `runtime` (executa o manifesto dentro do runner) e modo `dispatch` (`repository_dispatch` no fork `camillanapoles/OpenCLI` via `OPENCLI_TOKEN` — [guia](docs/SECRETS.md); fallback self-dispatch sem secret) |
| `continuity.yml` | `pull_request: closed`, `push`, `repository_dispatch: session-*`, `issue_comment` (`/session …`), `schedule`, `workflow_dispatch` | **Continuidade da sessão**: handoff automático no merge (branch + draft PR), checkpoint do contexto, heartbeat |
| `blueprint.yml` | `issues: closed`, `workflow_dispatch`, `repository_dispatch: pipeline-*`, `schedule` | **Pipeline gate-driven (BPMN)**: gate de continuidade (issues/CI/testes) + cadeia de issues indexadas com envelope JSON |

Como `workflow_run` encadeia os fluxos: cada conclusão do `ci` volta a entrar
como *gate event* no `gate-driver` — a fiação de automação é self-hosted no
próprio Actions.

### 🔁 Continuidade da sessão (a "segunda via")

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

### 🚦 Pipeline gate-driven (blueprint/BPMN) + envelope JSON padrão

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
npm run pipeline -- gate --open-issues 0 --ci-failures 0 --tests-total 92 --tests-passed 92
npm run pipeline -- step --id ISSUE-1 --result 0
npm run pipeline -- next --after ISSUE-1
npm run pipeline -- registry --cnj-backlog pipeline/backlog-cnj.json   # registro unificado (2 sessões)
npm run pipeline -- interop --from arquivo-cnj.json                  # dialeto CNJ -> canônico
```

**Integração entre sessões paralelas** (d917b13b × ed79bd77): contrato único
`pipeline/contract.schema.json`, adaptador `src/pipeline/interop.ts`, registro
unificado e workflow `integration.yml` — ver [`docs/INTEGRATION.md`](docs/INTEGRATION.md) e a
decisão registrada em [`docs/04-decisao-unificacao.md`](docs/04-decisao-unificacao.md).

### WebAssembly (best practices para a web)

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

### Testes

`npm test` roda `node:test` sobre dez suítes (**92 testes**): `db`, `cache`,
`factory` (pattern factory + builtins), `gate-driver` (triggers, blocking vs
advisory, dispatch OpenCLI via mock transport), `server` (CRUD HTTP, webhooks,
CORS), `session` (continuidade: checkpoints, briefing, handoff), `pipeline`
(envelope JSON 0/1/2 + direction, continuity gate, chain executor), `domain`
(modelo OO: estados, SQLite, factory event-driven, ciclos determinísticos) e
`wasm` (vetores FNV-1a, paridade com a lógica TS de triggers).

### Créditos

- Conceito de “website como CLI para agentes”: [jackwener/OpenCLI](https://github.com/jackwener/OpenCLI)
- Runtime de automação web: [arena.ai/agent](https://arena.ai/agent)

---

# Parte B — Consulta processual CNJ (Python, DataJud + DJEN)

> Documentação da pilha Python integrada ao repositório via PRs #2/#5. O
> `pipeline/blueprint.json` é **único e compartilhado**: carrega a planta BPMN
> (`gates`, `transicoes`, … — lida por `pipeline/gate.py`) **e** a cadeia indexada
> (`version`, `chain` — lida pelo `src/pipeline` TS). O registro unificado das duas
> sessões sai de `npm run pipeline -- registry`.


Consulta um processo judicial e gera um **relatório em Markdown** com tudo o que as APIs
públicas do CNJ entregam: capa, partes(*) e movimentações (DataJud) + publicações, intimações
e inteiro teor (DJEN).

```bash
python3 main.py 0001234-56.2024.8.17.2001            # relatório em Markdown no terminal
python3 main.py 0001234-56.2024.8.17.2001 -o rel.md  # grava em arquivo
python3 main.py 0001234-56.2024.8.17.2001 --json     # JSON cru das duas APIs
```

    (*) a API do DataJud não expõe nome/CPF das partes — veja "Anexos e documentos" abaixo.

| Arquivo | Para que serve |
| --- | --- |
| **`main.py`** | consulta **um processo** (DataJud + DJEN) e gera relatório completo em Markdown |
| `scripts/datajud.sh` | CLI `curl`+`jq`: contagens, agregações e relatórios **agregados** (por classe, vara, ano…) |
| `docs/01-api-datajud.md` | referência da API do DataJud (acesso, campos, DSL, erros, regras) |
| `docs/02-receitas-curl-tjpe.md` | receitas `curl` prontas para o TJPE |
| `docs/03-pipeline-gates.md` | manual do **pipeline de gates** (contrato JSON, 0/1/2, planta BPMN) |
| **`pipeline/gate.py`** + `pipeline/blueprint.json` + `pipeline/backlog.json` | **gatilho** de continuidade: mede issues/CI/testes/fábrica, diz o que fazer agora e devolve JSON |
| **`pipeline/factory.py`** | **fábrica de issues** event-driven (POO + SQLite): constrói a próxima indexada conforme o padrão do blueprint |
| `docs/exemplo-saida/` | exemplo do relatório de processo e do relatório agregado |
| `tests/` | mock local das APIs + 6 suítes de teste offline (**200 verificações**) |
| **`bootstrap.sh`** + `BOOTSTRAP.md` | recriam/configuram o projeto inteiro (arquivos, permissões, hashes) e validam tudo |
| `.github/workflows/gates.yml` | roda os gates no GitHub Actions (push, PR, issue, agenda, manual) |
| `.github/workflows/validacao-cnj.yml` | **validação ao vivo** contra o CNJ no runner (event-driven): 3 tentativas, diagnóstico de rede e, em caso de sucesso, conclui a **pendência que a execução provou** e constrói a próxima indexada |
| **`ENTREGA.md`** | relatório de entrega do branch: solicitado → incrementado → realizado → testado → validado → produção |

Requisitos: **Python 3.8+** (só biblioteca padrão) para o `main.py`; `bash`, `curl` e `jq` para o `scripts/datajud.sh`.

---

### 1. Consultar um processo (`main.py`)

```bash
python3 main.py 0001234-56.2024.8.17.2001               # TJPE (deduzido do número CNJ)
python3 main.py 0001234-56.2024.8.17.2001 -o processo.md
python3 main.py 0000832-35.2018.4.01.3202               # TRF1
python3 main.py 0001234-56.2024.8.17.2001 --todos       # varre TJPE, TRF5, TRT6, TRE-PE, STJ, TST, TSE, STM
python3 main.py 0001234-56.2024.8.17.2001 --sem-djen    # só DataJud
python3 main.py --chave-publica                         # imprime a chave pública vigente da wiki
```

O script lê o **número único (Resolução CNJ 65/2008)**: valida o dígito verificador (módulo 97
base 10), descobre o tribunal pelo campo `J.TR` e escolhe o índice correto do DataJud — inclusive
os casos especiais (`8.07` → `tjdft`, `6.07` → `tre-dft`, `5.00` → `tst`).

#### O que entra no relatório

1. **Resumo executivo** — tribunal, grau(s), classe, órgão julgador, ajuizamento, nº de movimentações, última movimentação, publicações no DJEN.
2. **Identificação e validação do número** — DV conferido, campos `NNNNNNN/DD/AAAA/J/TR/OOOO` decodificados.
3. **Capa do processo** — classe e assuntos (TPU), órgão julgador + município (IBGE), sigilo, formato, sistema, datas de atualização. Um bloco por grau encontrado (G1 e G2).
4. **Movimentações processuais** — tabela completa (data/hora, código TPU, nome, complementos tabelados, órgão).
5. **Panorama estatístico** — movimentações por ano (com gráfico de barras), movimentos mais frequentes, órgãos, maior intervalo sem movimentação, janela temporal e dias de inércia.
6. **Publicações e intimações (DJEN)** — disponibilização, tipo, órgão, texto e link do inteiro teor.
7. **Anexos e documentos** — o que é público, onde buscar os autos e o que a API não entrega.
8. **Links oficiais de consulta** — TJPE/PJe 1º e 2º grau, portal, DJe, DJEN.
9. **Índices consultados** — rastreabilidade (documentos por índice, erros).
10. **Notas, limitações e conformidade** — Termo de Uso e LGPD.

Exemplo completo: [`docs/exemplo-saida/relatorio-processo-exemplo.md`](docs/exemplo-saida/relatorio-processo-exemplo.md).

#### Opções

| Opção | Efeito |
| --- | --- |
| `-o, --saida ARQUIVO` | grava o relatório no arquivo (.md ou .json) |
| `--json` | devolve o JSON cru (DataJud + DJEN) em vez do Markdown |
| `--todos` | procura também em TRF5, TRT6, TRE-PE, STJ, TST, TSE e STM |
| `--buscar-em tjpe,trf5` | escolhe manualmente os índices do DataJud |
| `--sem-djen` | não consulta as publicações |
| `--chave-publica` | imprime a chave pública vigente da wiki do CNJ |
| `-k, --chave-api CHAVE` | usa outra chave do DataJud |
| `--debug` | mostra as requisições HTTP (com a chave mascarada) |
| `-q, --quieto` | silencia o progresso (stderr) |

Variáveis: `DATAJUD_API_KEY`, `DATAJUD_BASE_URL`, `DJEN_BASE_URL`, `DATAJUD_TIMEOUT`.

#### Anexos e documentos: o que dá e o que não dá

Ser honesto aqui evita frustração: **a API Pública do DataJud não devolve peças nem anexos** —
ela expõe metadados (número, classe, assuntos, órgão, datas, movimentações). O relatório deixa
isso explícito e aponta os caminhos públicos:

| O que | Onde |
| --- | --- |
| Movimentações e metadados | DataJud (já no relatório) |
| Publicações/intimações e **inteiro teor em PDF** | DJEN/Comunica (link no relatório) |
| **Autos, petições, decisões e anexos** | Consulta pública do tribunal: [PJe 1º grau TJPE](https://pje.cloud.tjpe.jus.br/1g/ConsultaPublica/listView.seam), [PJe 2º grau](https://pje.cloud.tjpe.jus.br/2g/ConsultaPublica/listView.seam), [consulta unificada](http://srv01.tjpe.jus.br/consultaprocessualunificada/) |
| Partes (nome, CPF/CNPJ), valores | autos no portal do tribunal — a API pública não expõe |
| Integração autenticada (advogado) | MNI do PJe, com certificado digital |

Processo em **segredo de justiça** não aparece em nenhuma consulta pública: o acesso é restrito
às partes e advogados habilitados.

---

### 2. Consultas agregadas (`scripts/datajud.sh`)


---

### Início rápido

```bash
# 1) contar os processos públicos do TJPE
./scripts/datajud.sh contar --tribunal tjpe

# 2) consultar um processo (numeração única CNJ, sem máscara)
./scripts/datajud.sh processo 0001234-56.2024.8.17.2001 --tribunal tjpe

# 3) gerar o relatório completo (Markdown + TSV/CSV) em ./saida
./scripts/datajud.sh relatorio --tribunal tjpe --saida saida

# 4) ver o curl equivalente a qualquer comando (para copiar/colar ou auditar)
./scripts/datajud.sh --debug contar --tribunal tjpe --classe 1116
```

O curl "cru", sem script, é só isto:

```bash
CHAVE="cDZHYzlZa0JadVREZDJCendQbXY6SkJlTzNjLV9TRENyQk1RdnFKZGRQdw=="

curl -sS -X POST "https://api-publica.datajud.cnj.jus.br/api_publica_tjpe/_search" \
  -H "Authorization: APIKey $CHAVE" \
  -H "Content-Type: application/json" \
  -d '{ "query": { "match_all": {} }, "size": 0, "track_total_hits": true }' \
  | jq '.hits.total'
```

> A chave é **pública**, publicada na [wiki do CNJ](https://datajud-wiki.cnj.jus.br/api-publica/acesso),
> e pode ser trocada a qualquer momento. Atualize com
> `export DATAJUD_API_KEY="$(bash scripts/datajud.sh chave)"`.

---

### Comandos do script

| Comando | O que faz |
| --- | --- |
| `chave` | lê a chave pública vigente na wiki do CNJ |
| `processo <numero>` | busca 1 processo pela numeração única CNJ (aceita máscara; normaliza para dígitos) |
| `contar` | conta processos do filtro (trata o teto de 10.000 / `relation: gte`) |
| `agregar <campo>` | agrupa e conta por classe, órgão julgador, assunto, grau, ano, mês… |
| `relatorio` | 1 requisição de total + 7 agregações → `.md` + `.tsv`/`.csv` |
| `paginar` | varre resultados com `search_after`, gravando JSONL |
| `ajuda` | manual completo |

Filtros disponíveis: `--tribunal`, `--classe`, `--assunto`, `--orgao`, `--municipio`, `--grau`, `--de`,
`--ate`, `--sigilo`. Opções: `--top`, `--json`, `--saida`, `--limite`, `--pagina`, `--pausa`, `--debug`.

```bash
# execuções fiscais (classe 1116) por vara, apenas de 2024
./scripts/datajud.sh agregar orgao-nome --classe 1116 --de 2024-01-01 --ate 2024-12-31 --top 20

# série anual de ajuizamentos de 1º grau
./scripts/datajud.sh agregar ano --grau G1

# 2.000 processos em JSONL, 100 por página
./scripts/datajud.sh paginar --limite 2000 --pagina 100 --saida processos-tjpe.jsonl
```

### Relatório

```bash
./scripts/datajud.sh relatorio --tribunal tjpe --saida saida
# → saida/relatorio-TJPE-AAAAMMDD-HHMM.md  (total, 7 agregações, notas legais)
# → saida/agg-*.tsv e saida/agg-*.csv      (dados para Excel/pandas)
```

Veja o formato em [`docs/exemplo-saida/relatorio-tjpe-exemplo.md`](docs/exemplo-saida/relatorio-tjpe-exemplo.md).

O relatório registra endpoint, hora UTC, filtros usados e nº de requisições — e traz as notas do Termo de
Uso (dados não garantidos pelo CNJ, uso não comercial, ciência ao CNJ ao divulgar, LGPD).

### Pipeline de gates (o gatilho)

```bash
make gates          # veredito: 0 = nada pendente · 1 = continuidade · 2 = exige humano
make gate-issues    # existem issues abertas?
make gate-cicd      # alguma execução de CI/CD terminou com erro?
make gate-testes    # os testes existem e passam?
make gate-issue     # executa a próxima issue do backlog (ISSUE=ISSUE-006 MARCAR=--marcar)
make gate-fabrica   # a fábrica de issues (padrão BPMN + SQLite) está íntegra?
make fabrica        # estado da fábrica: issues, eventos, esquema, direção de continuidade
```

Cada gate devolve **o mesmo objeto JSON** (`id`, `mensagem`, `anexos`, `status`, `next_issue`,
`direcao`, `proximo_passo`…) e o **exit code é igual ao `status`**: `"0"` sucesso, `"1"` erro tipo 1
(pendência tratável ⇒ **continuidade**), `"2"` erro tipo 2 (não foi possível avaliar ⇒ exige humano).
O **gatilho só é positivo** quando não há issue aberta **e** o CI não tem erro **e** os testes passam
**e** a fábrica está íntegra; enquanto não for positivo, `continuidade = true` e a direção
(`corrigir`/`depurar`/`proxima`) aponta o próximo passo. Cada issue traz **instrução de teste** e
**instrução de desenvolvimento**; ao passar, a **fábrica** marca **COMPLETADA** e constrói a
**próxima indexada**. Detalhes, diagrama BPMN e contrato completo:
[`docs/03-pipeline-gates.md`](docs/03-pipeline-gates.md). Entrega documentada: [`ENTREGA.md`](ENTREGA.md).

#### Validação ao vivo no runner (event-driven)

A consulta real ao CNJ não roda no sandbox de desenvolvimento (sem rota), mas roda no
**runner do GitHub**: o workflow `validacao-cnj` dispara em `push`, `pull_request`, agenda
(dias úteis, 08:00 BRT) e manualmente, tenta até 3 vezes com backoff (respeitando o `Retry-After`), publica o diagnóstico de rede
(DNS/HTTP) e, se o CNJ responder **200**, pergunta à fábrica **qual é a pendência que essa
execução prova** (`--pendencia-ao-vivo`), marca-a como **COMPLETADA** e constrói a **próxima
issue indexada** — com a URL da execução gravada como evidência. Pendência de
*desenvolvimento* não é concluída por aqui: nesse caso o job registra a continuidade e **não
cria issue nova** (idempotente).
Se a rede falhar ou o CNJ responder **429** (taxa compartilhada de 120 req/min), fica em
**continuidade** (warning), sem sucesso falso.

**Medido em 13/10 (runner do GitHub, sem mock):** a primeira execução levou `HTTP 429`
(taxa) e o pipeline respondeu com continuidade; a [segunda](https://github.com/camillanapoles/llm-arena-opencli/actions/runs/38451978473)
obteve **`HTTP 200` — índice `api_publica_tjpe`, `hits.total = 6852614`** e o kit curl
confirmou `Total: 6852614`. Então a fábrica marcou a `ISSUE-006` **COMPLETADA** (evidência =
URL do run) e construiu a `ISSUE-008` sozinha, com commit do bot no backlog: o laço
evento → teste → conclusão → próxima issue **fechou no runner**.

### Testes (sem internet)

```bash
make testes                          # todas as 6 suítes (229 verificações)
python3 tests/testar_conformidade.py # 29 — conformidade com a doc oficial do CNJ
python3 tests/testar_main.py         # 29 — NUP/DV, relatório, DJEN, erros
./tests/rodar-testes.sh              # 32 — datajud.sh (curl + jq)
python3 tests/testar_pipeline.py     # 67 — contrato JSON, 0/1/2, direção, blueprint, workflow
python3 tests/testar_fabrica.py      # 37 — fábrica de issues (SQLite, eventos, padrão BPMN)
./tests/testar_bootstrap.sh          # 27 — recria o projeto e compara byte a byte
```

As suítes sobem mocks locais das APIs (`tests/mock_apis.py` e `tests/mock_datajud.py`) que imitam
autenticação, erros 400/401/404/429, agregações e paginação. **Nenhuma requisição real ao CNJ é feita.**

#### Reconstruir o projeto do zero

```bash
bash bootstrap.sh                  # cria ./projeto-datajud, confere hashes e roda as 4 suítes
bash bootstrap.sh --verificar      # só valida uma cópia existente
python3 tools/gerar_bootstrap.py   # regera o bootstrap após editar algum arquivo
```

Detalhes de estrutura, permissões, etapas e saída esperada: [`BOOTSTRAP.md`](BOOTSTRAP.md).

### Requisitos

`bash` ≥ 4.3, `curl` e `jq`. Em Debian/Ubuntu: `sudo apt install curl jq`.

### Regras de uso (resumo do Termo de Uso v1.2)

- **120 requisições por minuto** no máximo (item 3.13); o CNJ pode limitar sem aviso (3.14).
- Uso **legal e não comercial** (3.3, 3.8).
- O CNJ **não garante** precisão, integridade ou atualidade (3.6).
- Ao divulgar relatórios, **dê ciência ao CNJ** (3.9).
- Não coletar, armazenar ou cruzar dados pessoais (4.2, LGPD).

Os dados são metadados de processos **públicos** (sem partes, sem peças). A atualização depende do envio
de cada tribunal ao DataJud — pode haver atraso de dias.

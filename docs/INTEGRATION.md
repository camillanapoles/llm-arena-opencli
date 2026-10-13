# 🔗 Integração entre as duas sessões paralelas (d917b13b × ed79bd77)

O repositório tem **duas sessões Arena trabalhando em paralelo**:

| Sessão | Branch / PR | Stack | Pipeline |
| --- | --- | --- | --- |
| **d917b13b** (esta) | `arena/d917b13b-llm-arena-opencli` · PR #1 | Node.js/TypeScript | `src/pipeline/` (envelope, gates, chain, domínio OO) |
| **ed79bd77** | `arena/ed79bd77-llm-arena-opencli` · PR #2 | Python | `pipeline/gate.py` + `factory.py` (gates, fábrica OO + SQLite) |

Ambas implementam o **mesmo modelo gate-driven BPMN** — a integração é por
**contrato compartilhado**, sem reimplementar nada de nenhum lado.

## 1. Contrato único

`pipeline/contract.schema.json` define o envelope canônico. Os dois dialetos
são equivalentes:

| Campo canônico (d917/TS) | Campo CNJ (ed79/Python) | Regra |
| --- | --- | --- |
| `id` | `id` | igual |
| `message` | `mensagem` | igual |
| `status` (string de estado) | `status` + `gate` | `"0"→success`, `"1"→continuity`, `"2"→human-required`; `gate` vira contexto |
| `exitCode` (0/1/2) | `codigo_saida` / `status` | mesmo valor numérico |
| `nextIssue` | `next_issue` | igual |
| `direction` | `direcao` | `continue→proxima · fix→corrigir · debt→depurar · complete→encerrar · hold→humano` |
| `addenda[] {kind,ref,description}` | `anexos[] {path,filename,descricao}` | `ref↔path`, `filename↔basename`, `description↔descricao` |
| `continuity {required,reason}` | `continuidade` + `mensagem` | `required↔continuidade` |
| `at` | `timestamp` | igual |
| `data` | `dados` | igual |

**Semântica dos códigos (idêntica nas duas):** `0` sucesso · `1` erro tipo 1
(tratável → continuidade) · `2` erro tipo 2 (não avaliável → humano).

## 2. Como uma sessão consome a outra

```sh
# converter envelope CNJ -> canônico (e vice-versa)
npm run pipeline -- interop --from pipeline/saida/gate-continuidade.json
npm run pipeline -- interop --to action-result.json

# registro UNIFICADO das pendências das duas sessões
npm run pipeline -- registry --cnj-backlog pipeline/backlog-cnj.json --out pipeline/registry.json
```

- `pipeline/backlog-cnj.json` — snapshot do backlog da sessão ed79bd77
  (sincronizado a cada execução do `integration.yml` a partir da branch dela).
- `pipeline/registry.json` — backlog único com namespace
  (`d917b13b:ISSUE-1`, `ed79bd77:ISSUE-007`), status, instruções de teste e
  dependências das duas sessões.

## 3. Workflow de integração

`.github/workflows/integration.yml` (push/PR/dispatch):

1. roda a suíte **d917** (`npm run ci` — 92 testes)
2. roda a suíte **ed79** (`bash tests/rodar-testes.sh` + `python3 tests/testar_pipeline.py` + `testar_fabrica.py`)
3. sincroniza o backlog da sessão paralela e gera o **registro unificado**
4. emite o **envelope mesclado** (contrato único) como artifact + summary
5. comenta o resultado nos PRs #1 e #2 (ponte entre as sessões)

## 4. Decisão registrada

A decisão de unificação (que desbloqueia a ISSUE-007/ISSUE-008 do backlog
ed79bd77) está em [`docs/04-decisao-unificacao.md`](04-decisao-unificacao.md).

# ENTREGA — branch `arena/ed79bd77-llm-arena-opencli`

Relatório de entrega do branch: **o que foi solicitado → incrementado à solicitação (timeline)
→ realizado → testado → validado → pronto para produção**.

- **Repositório:** https://github.com/camillanapoles/llm-arena-opencli
- **Branch:** `arena/ed79bd77-llm-arena-opencli` (base: `main` em `3d9b774`)
- **Pull request:** https://github.com/camillanapoles/llm-arena-opencli/pull/2 — OPEN / MERGEABLE
- **Data da entrega:** 13/10/2026 (entrega inicial do pedido 4) · **revisão 2:** 13/10/2026 —
  fábrica de issues event-driven (POO + SQLite), instrução de desenvolvimento por issue e
  direção de continuidade no contrato
- **Situação:** pronto para uso — `bash bootstrap.sh` recria o projeto inteiro do zero;
  `make gates` diz se há pendências; `python3 main.py <processo>` consulta a Justiça de verdade.
- **GitHub Actions:** workflow `gates` ativo, 5 jobs encadeados, últimos runs (push e pull_request) **verdes**.

---

## 1. Resumo executivo

| # | Solicitado | Entregue | Evidência |
| --- | --- | --- | --- |
| 1 | Consultar processos e contar por órgão/grau no TJPE usando a **API pública do CNJ** por `curl` | `scripts/datajud.sh` (7 subcomandos, mesma semântica da wiki do CNJ) + `docs/01`, `docs/02` + exemplos de saída | 32 verificações |
| 2 | Script **completo** em Python, na raiz, com **relatório em Markdown**, cobrindo "o processo, os anexos, tudo que puder" — e todo o público (DataJud + DJEN) | `main.py` (1 arquivo, sem dependências externas): DataJud + DJEN + montagem de número/validação de DV + relatório Markdown com anexos | 29 testes |
| 3 | **Validar conforme a documentação** e um **bootstrap que auto-cria o projeto** (todos os arquivos, todas as permissões) **e valida os testes, verificando resultado e códigos de teste** | `tests/testar_conformidade.py` (conferência contra a wiki/CNJ) + `bootstrap.sh` autossuficiente (7 etapas, manifesto SHA-256, `py_compile`, `bash -n`, suítes) + `BOOTSTRAP.md` | 29 + 25 verificações |
| 4 | **Gatilho** que só é positivo sem issues abertas, sem CI com erro e com testes verdes; **enquanto não positivo ⇒ continuidade**; cada issue testada e entregue com a instrução da seguinte; **toda action devolve JSON** (`id`, `mensagem`, `anexos`, `status`, `next_issue`) | `pipeline/gate.py` + `pipeline/blueprint.json` (BPMN) + `pipeline/backlog.json` + `.github/workflows/gates.yml` + `docs/03` + esta `ENTREGA.md` | 47 testes |
| 5 | **Instrução a cada issue pendente** para concluir o desenvolvimento **+ fábrica event-driven de issues** conforme o padrão gate-driven (BPMN) — **backend + SQLite + orientação a objetos** — com **direção de continuidade** (`fix`/`debug`/`continue to next issue`) e **build da próxima indexada quando uma termina com sucesso** | `pipeline/factory.py` (8 classes, SQLite `STRICT`, 6 handlers de evento), `modelo_issue` no `blueprint.json`, `instrucao_desenvolvimento` em todas as 7 issues, campo `direcao`/`proximo_passo` no contrato, `tests/testar_fabrica.py` | 36 testes |

**Total: 200 verificações automatizadas**, todas offline, em 6 suítes (`make testes`).

---

## 2. Timeline completa

### 2.1 Solicitado (o pedido original, em quatro blocos)

| Data | Pedido |
| --- | --- |
| 11/10 | "consultar processos do TJPE pela API pública do CNJ, por curl; contar por órgão julgador e grau" |
| 12/10 | "script **completo** em `main.py`, saída em **Markdown**, 'o processo, os anexos, tudo que puder' — todo o público (DataJud + DJEN)" |
| 12/10 | "**validar conforme doc**" + "**bootstrap** que auto-**cria** o projeto completo (diretórios, arquivos, permissões), monta/configura tudo e **valida os testes, conferindo resultado e códigos de teste" |
| 13/10 | "**RELATE O QUE ESTÁ ENTREGANDO NESTE BRANCH… DOCUMENTE**: solicitado, incrementado (TIMELINE), realizado, testado, validado ⇒ **PRODUÇÃO** (pronto para uso pelo usuário)" |

### 2.2 Incrementado à solicitação (o que foi acrescentado ao pedido, e por quê)

| Incremento | Origem | Por quê |
| --- | --- | --- |
| **DJEN (Res. CNJ 455/2022)** somado ao DataJud no mesmo relatório | pedido 2 ("todo o público") | DataJud dá metadados do processo; as *publicações* (intimações) só estão no Diário de Justiça Eletrônico Nacional. Sem DJEN o relatório ficaria pela metade |
| Construção/validação do **número único CNJ** (`NNNNNNN-DD.AAAA.J.TR.OOOO`, Res. 65/2008) | necessidade prática | Sem isso, qualquer dígito trocado gera consulta vazia indistinguível de "processo sem publicação" |
| **Glossário dos 15 campos** do DataJud em português + mapeamento `tjdft`→`tjdf`, `tre-*` | pedido 1 | Os códigos de tribunal da API não são óbvios; erro de sigla é o erro nº 1 de quem usa a API |
| **Resiliência**: paginação por `search_after`, teto de 10.000 hits, agregações com fallback `.keyword`, respeito ao limite de 120 req/min | pedido 1 | Sem isso o kit quebra exatamente nos tribunais grandes |
| **LGPD explícita**: nenhuma consulta por nome de parte ou CPF, nenhum campo de parte no relatório | Termo de Uso do CNJ | A API é pública mas restrita a metadados processuais; o teste proíbe esses campos |
| **Bootstrap autossuficiente** com manifesto **SHA-256**, `py_compile`, `bash -n` e execução das suítes no destino | pedido 3 ("verificando resultado e **códigos de teste**") | Entrega não é "gerar arquivos": é provar que o que foi gerado funciona, e com código de saída verificável |
| **Pipeline de gates** (blueprint tipo BPMN) + fila de issues **indexada** | pedido 4 | Transforma a entrega num fluxo que se auto-verifica a cada push/PR/issue, em vez de um relatório morto |
| **Erro tipo 1 × erro tipo 2** no `status` | pedido 4 | Separar "pendência tratável, continue" de "não dá para avaliar, chame humano" é o que permite o gatilho decidir sem adivinhação |
| `pipeline/verificar_cnj.py` como **instrução executável** da ISSUE-006 | pedido 4 | "Toda issue tem instrução de teste": até a validação ao vivo precisa ser um comando reprodutível com código de saída |
| **Fábrica de issues** (`pipeline/factory.py`) | pedido 5 ("funções event driven da factory… conforme pattern gate driven [BPMN] ➞ backend+sqlite + object oriented") | Transforma eventos (demanda, CI vermelho, teste vermelho, gate 1/2, checkpoint) em issues indexadas, em SQLite, sem depender de gente para manter a fila |
| **Padrão `modelo_issue` no blueprint** | pedido 5 ("criar instrução a cada issue pendente necessária pra concluir o desenvolvimento") | O padrão fica declarado na planta (BPMN): campos obrigatórios, formato `ISSUE-NNN`, dependência da anterior e as instruções de execução em ordem |
| **`instrucao_desenvolvimento` em todas as issues** | pedido 5 | Cada item do backlog passou a dizer **o que fazer para concluir** (1, 2, 3…) — inclusive as manutenções das issues já concluídas e a decisão humana da ISSUE-007 |
| **`direcao` + `proximo_passo` no contrato JSON** | pedido 5 ("norteando a direção de continuidade [fix/debug/continue to issue… etc]") | A resposta passa a dizer não só *o que aconteceu*, mas *para onde ir agora* e o comando literal |
| **Build da N+1 indexada no caminho feliz** | pedido 5 ("quando uma acaba com sucesso ➞ constrói a seguinte indexada") | Sucesso testado ⇒ a fábrica marca **COMPLETADA** com evidência, constrói a próxima indexada (dependendo da última concluída) e exporta o `backlog.json`; o workflow commita |
| **Nudge de compactação** | pedido 5 ("oom" / continuidade de sessão) | O bloco `instrucao_proxima_issue` lembra que o estado vive no repositório (blueprint + backlog + SQLite): compactar contexto não perde a direção — basta `make gates` e seguir o `proximo_passo` |
| **`gate fabrica` (4º check do gatilho)** | pedido 5 | Se o padrão/instruções da fábrica quebrarem, o gate positivo deixa de ser positivo — a fábrica entra na regra do gatilho |
| **`bash -n` em cada bloco `run:` do workflow** | endurecimento | Sem PyYAML no ambiente, a validação do shell embutido no YAML passou a ser um teste determinístico |

### 2.3 Realizado (linha do tempo de execução)

| Quando | Marco |
| --- | --- |
| 11/10 20:42 | `3d9b774` — commit inicial do repositório |
| 12/10 21:33 | `3bd0cc4` — **kit de consulta à API Pública do DataJud** (curl + CLI + docs) |
| 12/10 22:10 | `17b35aa` — **`main.py`**: consulta de processo com relatório completo em Markdown |
| 12/10 22:11 | `aa5a5f4` — `__pycache__`/`.pyc` fora do versionamento |
| 12/10 22:30 | `436253a` — **`bootstrap.sh` auto-criador + `BOOTSTRAP.md` + validação de conformidade** |
| 12/10 22:4x | **PR #2** aberto (base `main` ← branch), +9.347/−1 em 20 arquivos |
| 13/10 14:2x | Publicação do pedido 4 (`92a31c0`) → o workflow `gates` dispara no Actions e o run de `push` fica **verde** |
| 13/10 14:3x | `e864c53` corrige o job 5 em `pull_request` (`github.ref_name` = `NNN/merge` quebrava o checkout; commit do backlog agora só fora de PR) e atualiza as actions para v5 → **runs de `push` e `pull_request` verdes, 5/5 jobs** |
| 13/10 15:1x | `cd3a80d` — pedido 4 publicado: ENTREGA.md + validação real do workflow no Actions (runs de push e PR verdes) |
| 13/10 18:5x | `b9873a4/c422628` — **validação ao vivo event-driven**: `.github/workflows/validacao-cnj.yml` dispara no runner por push/PR/agenda/dispatch; na primeira execução, o runner **resolveu o DNS (`201.49.152.99`) e recebeu `HTTP 429`** do CNJ (taxa compartilhada) ⇒ `status "1"`, continuidade, **sem sucesso falso** |
| 13/10 19:0x | O incidente virou robustez (`28d4499`): `verificar_cnj.py` passou a tratar **429 com `Retry-After`** e a expor `direcao`/`proximo_passo`; o workflow ganhou **backoff 30/60/90 s** (teto 150 s), diagnóstico pelo mesmo caminho de rede do validador (urllib) e testes novos |
| 13/10 19:07 | **O laço fechou no runner** ([run 38451978473](https://github.com/camillanapoles/llm-arena-opencli/actions/runs/38451978473)): `HTTP 200` do CNJ com `hits.total = 6852614`, kit curl confirmando `Total: 6852614` ⇒ a fábrica marcou a **ISSUE-006 COMPLETADA** (evidência = URL do run), **construiu a ISSUE-008** e o bot commitou o `backlog.json` (`34fc224`, marcador de skip do commit-bot) |
| 13/10 19:2x | **Idempotência + correção de contrato**: o job de conclusão passou a ser dirigido pela pendência REAL (`--pendencia-ao-vivo`) em vez de fixar a ISSUE-006 — pendência de desenvolvimento não é provada pela consulta ao CNJ, então o job só registra a continuidade (sem `ISSUE-009`, `ISSUE-010`… a cada push); achado na emulação: o Python imprime `True` e o `if:` do GitHub compara com `'true'` — o output agora é normalizado em minúsculas |
| 13/10 18:4x | Lição de CI registrada: um commit com o literal do marcador de skip na mensagem **não dispara workflows** — o workflow novo nem foi registrado até o segundo push |
| 13/10 17:5x | **Pedido 5**: `pipeline/factory.py` (8 classes POO + SQLite + 6 handlers de evento), `modelo_issue` + `instrucao_proxima_issue` no blueprint (agora 6 gates, 21 transições), `instrucao_desenvolvimento` nas 7 issues, `direcao`/`proximo_passo` no contrato, 4º check no gatilho, `tests/testar_fabrica.py` (36), job `gate-fabrica` no workflow e esta revisão do `ENTREGA.md` |
| 13/10 | **Pedido 4**: `pipeline/gate.py`, `blueprint.json`, `backlog.json`, `.github/workflows/gates.yml`, `docs/03`, `tests/testar_pipeline.py`, `pipeline/verificar_cnj.py`, esta `ENTREGA.md`, Makefile com alvos de gate, bootstrap regenerado |

### 2.4 Testado (6 suítes, 229 verificações, tudo offline)

| Suíte | Verificações | O que cobre |
| --- | --- | --- |
| `tests/testar_conformidade.py` | 29 | conformidade com a doc oficial do CNJ: URL/rota/headers, aliases de tribunal, 15 campos do glossário, `search_after`, teto de 10.000, agregações com `.keyword`, 120 req/min, LGPD |
| `tests/testar_main.py` | 29 | `main.py`: DV do número CNJ (`% 97 == 1`), montagem do número de 20 dígitos, DataJud + DJEN com mocks, relatório Markdown, anexos, exit codes |
| `tests/rodar-testes.sh` | 32 | `scripts/datajud.sh`: chave pública, consulta, contagem, agregação, relatório, paginação, erros |
| `tests/testar_pipeline.py` | 71 | contrato JSON em todos os gates (com `direcao`/`proximo_passo`), semântica 0/1/2, `next_issue`, direção de continuidade, `--marcar`, blueprint, backlog e o próprio workflow (`bash -n` em cada bloco `run:`) |
| `tests/testar_fabrica.py` | 41 | fábrica: 8 classes, esquema SQLite `STRICT`, padrão do blueprint, construção da N+1 **só depois do sucesso testado**, bloqueada não congela, eventos → issues, round-trip SQLite ⇄ `backlog.json`, contrato do gate `fabrica` e da CLI |
| `tests/testar_bootstrap.sh` | 27 | bootstrap atualizado, criação byte a byte vs. repositório, permissões, 5 suítes rodando **dentro** do projeto recriado, gates (fabrica/blueprint/continuidade) no projeto recriado, `--verificar`, proteção contra sobrescrita |

### 2.5 Validado (como cada promessa foi conferida)

| Validação | Comando | Resultado |
| --- | --- | --- |
| Conformidade com a documentação do CNJ | `python3 tests/testar_conformidade.py` | 29/29 OK |
| Bootstrap recria o projeto **idêntico** | `bash tests/testar_bootstrap.sh` | 25/25 OK, `diff -r` sem diferenças, hashes conferem |
| Planta BPMN × implementação | `python3 pipeline/gate.py blueprint` | `status "0"` — *5 gates, 15 transições* |
| Gatilho de continuidade | `python3 pipeline/gate.py continuidade` | `status "1"` (há issue aberta) — **continuidade**, como manda a regra |
| CI/CD | `python3 pipeline/gate.py cicd` | `status "0"` — 5 execuções, nenhuma com erro |
| Testes | `python3 pipeline/gate.py testes` | `status "0"` — 229 verificações aprovadas |
| Fábrica de issues | `python3 pipeline/gate.py fabrica` | `status "0"` — 8 classes, tabelas `eventos`/`issues`/`schema_info`, round-trip SQLite ⇄ `backlog.json` ok, nenhuma issue sem instrução de desenvolvimento |
| Eventos event-driven | `python3 pipeline/factory.py --evento "ci_falhou\|run=42"` | `continuar` na MESMA issue, com a direção `depurar` (CI) / `corrigir` (teste) — a fila não incha |
| Construção da N+1 | `python3 pipeline/factory.py --concluir ISSUE-006 --proxima` | cria a `ISSUE-008` dependendo da última concluída e recusa (status 1) enquanto houver issue pendente |
| Shell do workflow | teste `test_blocos_run_sao_bash_valido` | os 8 blocos `run:` são `bash -n` válidos |
| Sem fonte de dados (`gh` ausente) | `python3 pipeline/gate.py issues --sem-gh` | `status "2"` (erro tipo 2) — não inventa sucesso |
| Projeto reconstruído funciona | `bash bootstrap.sh --destino /tmp/x` | 7/7 etapas ✔, exit 0 |
| **Validação ao vivo event-driven — 1ª medição** | [run 38451236091](https://github.com/camillanapoles/llm-arena-opencli/actions/runs/38451236091) | job verde com **diagnóstico real**: DNS `201.49.152.99`, `HTTP 429` do CNJ ⇒ `status "1"`, `::warning::` de continuidade e a ISSUE-006 mantida — o gate **não inventou sucesso** |
| **Validação ao vivo — laço FECHADO** | [run 38451978473](https://github.com/camillanapoles/llm-arena-opencli/actions/runs/38451978473) | **`HTTP 200`** do CNJ (`api_publica_tjpe`, `hits.total = 6852614`) e kit curl com `Total: 6852614` ⇒ a fábrica marcou a **ISSUE-006 COMPLETADA** (evidência = URL do run), **construiu a ISSUE-008** e o bot commitou o `backlog.json` — evento → teste → conclusão → próxima issue, sem intervenção |
| **Idempotência do job de conclusão** | `python3 pipeline/factory.py --pendencia-ao-vivo` | devolve a pendência REAL do backlog e se **esta execução** a prova; pendência de desenvolvimento ⇒ continuidade na MESMA issue, **sem** criar `ISSUE-009` a cada push (emulado nos dois cenários antes do push) |
| **Workflow no GitHub Actions** | [run de `push`](https://github.com/camillanapoles/llm-arena-opencli/actions/runs/38444008073) e [run de `pull_request`](https://github.com/camillanapoles/llm-arena-opencli/actions/runs/38444012416) | **os dois verdes**, com os **6 jobs** passando (`gate 1·issues`, `gate 2·cicd`, `gate 3·testes`, `gate 4·fábrica`, `gate 5·continuidade`, `gate 6·issue`) e 6 artifacts publicados — é a validação real do YAML |
| **Fábrica no CI** | job `gate 4 · fábrica de issues (padrão + SQLite)` | verde em 5–8 s; o passo de eventos registra `issue_aberta`/`ci_falhou`/`teste_falhou` conforme os gates anteriores |
| **Continuidade honesta no runner** | anotação do job 6: *"a issue ainda não passa — continuidade na MESMA issue (veja o log em anexo)"* | o runner do GitHub **também não alcançou o CNJ** naquele momento: em vez de marcar sucesso falso, o gate manteve a `ISSUE-006` e a direção `corrigir` (exatamente o comportamento pedido) |

### 2.6 Produção (pronto para uso)

```bash
git clone https://github.com/camillanapoles/llm-arena-opencli && cd llm-arena-opencli

make testes        # 6 suítes, 229 verificações, offline
make gates         # veredito: 0 = nada pendente · 1 = continuidade · 2 = exige humano
make fabrica       # estado da fábrica de issues (SQLite): pendências, eventos e próximo passo
make consultar NUMERO=0001234-43.2024.8.17.2001   # relatório Markdown do processo (rede real)
bash bootstrap.sh --destino ./projeto-datajud      # recria o projeto inteiro do zero
```

---

## 3. O que este branch entrega, arquivo por arquivo

```
main.py                     consulta de processo + relatório Markdown (DataJud + DJEN)
scripts/datajud.sh          kit curl (chave|processo|contar|agregar|relatorio|paginar)
docs/01-api-datajud.md      manual da API (endpoints, campos, limites, LGPD)
docs/02-receitas-curl-tjpe.md  receitas prontas de curl para o TJPE
docs/03-pipeline-gates.md   manual do pipeline de gates (contrato JSON, 0/1/2, BPMN)
docs/exemplo-saida/         exemplos de relatórios e agregações já gerados

pipeline/gate.py            executor dos gates (8 subcomandos) — o "gatilho"
pipeline/factory.py         fábrica de issues event-driven (8 classes POO + SQLite)
pipeline/blueprint.json     planta BPMN do fluxo (validada pelo próprio pipeline)
pipeline/backlog.json       fila indexada de issues (instrução de teste por issue)
pipeline/verificar_cnj.py   instrução executável da ISSUE-006 (validação ao vivo do CNJ)
.github/workflows/gates.yml gatilho no GitHub Actions (5 jobs encadeados)

bootstrap.sh                recria o projeto inteiro e prova que funciona
tools/gerar_bootstrap.py    gerador/verificador do bootstrap (--conferir)
BOOTSTRAP.md                manual do bootstrap
ENTREGA.md                  este relatório

tests/                      6 suítes, 229 verificações (offline, com mocks)
```

---

## 4. O gatilho e o contrato JSON (pedido 4, em uma página)

### 4.1 Regra do gatilho

> O gate **só é positivo** quando, ao mesmo tempo: **(a)** não existe issue aberta,
> **(b)** nenhuma execução de CI/CD terminou com erro e **(c)** os testes existem e passam.
> **Enquanto não for positivo ⇒ `continuidade = true`** e o fluxo segue para a próxima
> pendência do backlog. Se um check não puder nem ser avaliado, o status é `2` e o
> pipeline **para** (exige humano) — nunca "chuta" sucesso.

```bash
python3 pipeline/gate.py continuidade \
  --status-issues 0 --status-cicd 0 --status-testes 0   # ⇒ status "0", continuidade false
```

### 4.2 Toda action devolve o mesmo objeto

```json
{
  "id": "gate-issue-20261013T141702Z-4c9ab1",
  "gate": "issue",
  "status": "0",
  "codigo_saida": 0,
  "mensagem": "ISSUE-005 testada com sucesso (código 0) — segue a issue ISSUE-006: ...",
  "continuidade": true,
  "next_issue": "ISSUE-006",
  "direcao": "proxima",
  "proximo_passo": "python3 pipeline/gate.py issue --id ISSUE-006 --marcar",
  "anexos": [
    {"path": "pipeline/saida/ISSUE-005-proxima-issue.md",
     "filename": "ISSUE-005-proxima-issue.md",
     "descricao": "instrução da issue seguinte do backlog"}
  ],
  "dados": {"criterio": ">= 1 issue aberta", "abertas": 1},
  "timestamp": "2026-10-13T14:17:02Z",
  "duracao_s": 0.31,
  "versao": "1.0.0"
}
```

| `status` | Significado | `continuidade` | `next_issue` |
| --- | --- | --- | --- |
| `"0"` | sucesso: nada pendente | `false` | próxima indexada (ou `null` se acabou) |
| `"1"` | **erro tipo 1**: pendência conhecida e tratável | **`true`** | **a mesma issue** (falhou) |
| `"2"` | **erro tipo 2**: não foi possível avaliar (exige humano) | `false` | `null` ou a issue bloqueada |

**Direção de continuidade** (`direcao` + `proximo_passo`) — o "norteando a direção" do pedido:

| direção | quando | próximo passo |
| --- | --- | --- |
| `proxima` | issue passou no teste (0) | `python3 pipeline/gate.py issue --id <N+1> --marcar` |
| `corrigir` (fix) | issue/teste falhou (1) | corrigir e repetir a MESMA issue |
| `depurar` (debug) | execução de CI com erro (1) | `gh run view --log-failed` na execução |
| `continuar` | gate intermediário positivo, há próximo gate | seguir o fluxo |
| `encerrar` | veredito positivo (0) | nada pendente — `gate.py situacao` |
| `humano` | erro tipo 2 | decisão humana (não continue automaticamente) |

O **exit code do processo é igual ao `status`**, então qualquer orquestrador (Actions,
cron, Makefile) encadeia os gates sem parsear nada — e ainda assim recebe o JSON completo
com `mensagem` (log/resumo) e `anexos` (`path` + `filename`).

### 4.3 Como o fluxo fecha o ciclo

1. Os gates 1–3 medem issues, CI/CD e testes **em paralelo**.
2. O gate 4 agrega os três (recebendo os status por `--status-*`, sem reexecutar nada).
3. Se `continuidade = true`, o gate 5 **executa a instrução da próxima issue do backlog**:
   - passou ⇒ `next_issue` = **próxima indexada**, e o anexo `*-proxima-issue.md` traz a
     instrução pronta (com o comando) para o ciclo seguinte;
   - falhou ⇒ `next_issue` = **a mesma issue**, com o log anexado;
   - com `--marcar`, a conclusão é persistida no `backlog.json` (o workflow commita com `[skip ci]`).
4. Volta ao passo 1. O ciclo se repete enquanto houver pendência — é isso que significa
   *gate-driven pipeline*.

### 4.4 A fábrica de issues (pedido 5)

```text
EVENTO  ──►  Fabrica.processar_evento()  ──►  Issue (padrão do blueprint)  ──►  SQLite
   │                    │                                                        │
   │                    └── se há pendência: mantém a MESMA issue (fix/debug)    │
   │                        se a anterior está COMPLETADA: constrói a N+1 ──────┘
   └── handlers: demanda · issue_aberta · ci_falhou · teste_falhou · gate_falhou · checkpoint
```

| Peça | O que faz |
| --- | --- |
| `blueprint.modelo_issue` | o padrão: campos obrigatórios, `ISSUE-{indice:03d}`, dependência da anterior, instruções de desenvolvimento em ordem |
| `blueprint.instrucao_proxima_issue` | as direções aceitas, a regra `status → direção` e o *nudge* de compactação |
| `pipeline/factory.py` | 8 classes (`ArmazenamentoSqlite`, `Evento`, `Issue`, `ModeloIssue`, `PadraoBPMN`, `Backlog`, `Repositorio`, `Fabrica`) + CLI no mesmo contrato JSON |
| `pipeline/backlog.json` | espelho versionável do SQLite (`--exportar`/`--sincronizar`, idempotente) — cada issue com `instrucao_teste` **e** `instrucao_desenvolvimento` |
| `gate fabrica` | 4º check do gatilho: valida o padrão, o esquema SQLite, o modelo e o round-trip |

**Regra de construção:** sucesso testado ⇒ marca **COMPLETADA** (com evidência e data) e constrói
a **próxima indexada**, dependendo da última concluída. Issue **pendente** trava a construção
(erro tipo 1, direção `corrigir`); issue **bloqueada** não trava — está apenas aguardando decisão
humana, e parar o desenvolvimento por causa dela seria pior. `--instruir` preenche a instrução de
desenvolvimento de qualquer issue que esteja sem ela.

---

## 5. Estado atual do pipeline (medido, não presumido)

```text
gate 1 · issues        → status "1"  (1 issue aberta: #3 SESSION CONTINUITY CONTROL)
gate 2 · CI/CD         → status "0"  (5 execuções analisadas, 0 com erro)
gate 3 · testes        → status "0"  (6 suítes aprovadas, 200 verificações)
gate 4 · fabrica       → status "0"  (8 classes, SQLite ok, 7/7 issues com instrução)
gate 5 · continuidade  → status "1"  ⇒ continua; próxima do backlog: ISSUE-006
gate 6 · issue         → executa a ISSUE-006; passa ⇒ a fábrica constrói a N+1
```

Backlog do projeto (`pipeline/backlog.json`):

| Issue | Título | Status |
| --- | --- | --- |
| ISSUE-001 | Kit de consulta por `curl` (DataJud/TJPE) | concluída |
| ISSUE-002 | `main.py` + relatório Markdown (DataJud + DJEN) | concluída |
| ISSUE-003 | Bootstrap auto-criador do projeto | concluída |
| ISSUE-004 | Validação de conformidade com a documentação do CNJ | concluída |
| ISSUE-005 | Pipeline de gates (contrato JSON, 0/1/2) | concluída |
| ISSUE-006 | Validação **ao vivo** contra o CNJ (`pipeline/verificar_cnj.py`) | **COMPLETADA no runner** (run 38451978473): `HTTP 200`, `hits.total = 6852614`; a fábrica concluiu a issue com a URL do run como evidência e construiu a próxima indexada |
| ISSUE-008 | Decisão da ISSUE-007: unificar com o fluxo da sessão `d917b13b`? (`docs/04-decisao-unificacao.md`) | **construída automaticamente** pela fábrica no sucesso da 006; pendente de desenvolvimento — a instrução de teste dela (`test -s docs/04-…`) é o que a fecha |
| ISSUE-007 | Decidir unificação com o fluxo da issue #3 (outra sessão) | bloqueada (decisão humana) |

---

## 6. Limitações conhecidas e próximos passos

| Limitação | Detalhe | Próximo passo |
| --- | --- | --- |
| Validação **ao vivo** do CNJ (ISSUE-006) | **resolvido como processo**: o sandbox não tem rota; o **runner do GitHub tem (DNS ok), mas a API respondeu `HTTP 429`** — o limite é de **120 req/min por IP** e o IP de saída é compartilhado. O pipeline trata como continuidade e tenta de novo (backoff + `Retry-After` + agenda) | nada a fazer do seu lado: o workflow `validacao-cnj` conclui a ISSUE-006 sozinho quando a taxa liberar. Para forçar agora: **Actions → validacao-cnj → Run workflow** (merge em `main` habilita agenda e dispatch) |
| ISSUE-007 (unificação com a issue #3, de outra sessão) | o outro fluxo não está em `main` (`.github/workflows` → 404 no ref `main`) e vive na issue #3; não foi tocado | gate devolve `2` de propósito: requer decisão do usuário |
| YAML do workflow | não há PyYAML no ambiente de desenvolvimento; a checagem local é estrutural (indentação, tabulação, gatilhos, jobs) | **já validado**: o workflow rodou de verdade no Actions ([push](https://github.com/camillanapoles/llm-arena-opencli/actions/runs/38413540315) e [PR](https://github.com/camillanapoles/llm-arena-opencli/actions/runs/38413550644)), 5/5 jobs verdes |
| Permissão de escrita do bot | o job `executa-issue` só commita o backlog quando disparado com `marcar=true` (e o repositório precisa permitir "Read and write permissions" para o `GITHUB_TOKEN`) | conferir em **Settings → Actions → General → Workflow permissions** |
| SQLite no CI | o banco `pipeline/fabrica.db` é ignorado no git (fonte de verdade = `backlog.json`, que é versionado e serve de espelho) | nada a fazer: o job já roda `--sincronizar` antes de usar a fábrica |
| Consulta pública do TJPE (Projudi/PJe) | as URLs do TJPE não respondem fora da rede da Justiça (`srv01…`, `pje.cloud…`) | usar o kit em rede compatível; o DataJud/DJEN cobrem o que é público nacional |

---

## 7. Checklist final de entrega

- [x] **Solicitado** — os 4 pedidos implementados no branch (kit curl, `main.py` Markdown, conformidade + bootstrap, pipeline de gates documentado)
- [x] **Incrementado** — DJEN, número CNJ, glossário, resiliência, LGPD, manifesto SHA-256, erro tipo 1 × 2, verificador ao vivo (seção 2.2)
- [x] **Realizado** — 8 marcos de commit + 11 arquivos novos, tudo versionado no branch (seção 2.3)
- [x] **Fábrica de issues (pedido 5)** — event-driven, POO + SQLite, padrão declarado no blueprint, instrução de desenvolvimento em todas as issues e construção automática da próxima indexada após o sucesso testado (seção 4.4)
- [x] **Testado** — 6 suítes, **229 verificações**, todas offline e reprodutíveis (seção 2.4)
- [x] **Validado** — conformidade com a doc do CNJ, bootstrap byte a byte, planta BPMN, semântica 0/1/2, projeto recriado do zero, **os 6 jobs do workflow verdes** e a **validação ao vivo rodando no runner** (seção 2.5)
- [x] **Automático até o fim (pedido 6)** — a validação ao vivo é event-driven e o laço **fechou no runner**: `HTTP 200` ⇒ a fábrica concluiu a ISSUE-006, construiu a ISSUE-008 e versionou o backlog sem intervenção; a conclusão é dirigida pela pendência real (`--pendencia-ao-vivo`), então repetir o push não cria issue nova (seção 5-bis de `docs/03`)
- [x] **Produção** — `make testes`, `make gates`, `make consultar`, `bash bootstrap.sh` prontos para uso (seção 2.6)
- [x] **Documentado** — `README.md` (visão geral), `BOOTSTRAP.md` (instalação), `docs/01-03` (API, receitas, pipeline) e esta `ENTREGA.md`
- [ ] **Pendente do usuário** — rodar a validação ao vivo do CNJ (ISSUE-006) num ambiente com internet e decidir a ISSUE-007

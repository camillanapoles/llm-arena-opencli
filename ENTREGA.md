# ENTREGA — branch `arena/ed79bd77-llm-arena-opencli`

Relatório de entrega do branch: **o que foi solicitado → incrementado à solicitação (timeline)
→ realizado → testado → validado → pronto para produção**.

- **Repositório:** https://github.com/camillanapoles/llm-arena-opencli
- **Branch:** `arena/ed79bd77-llm-arena-opencli` (base: `main` em `3d9b774`)
- **Pull request:** https://github.com/camillanapoles/llm-arena-opencli/pull/2 — OPEN / MERGEABLE
- **Data da entrega:** 13/10/2026
- **Situação:** pronto para uso — `bash bootstrap.sh` recria o projeto inteiro do zero;
  `make gates` diz se há pendências; `python3 main.py <processo>` consulta a Justiça de verdade.

---

## 1. Resumo executivo

| # | Solicitado | Entregue | Evidência |
| --- | --- | --- | --- |
| 1 | Consultar processos e contar por órgão/grau no TJPE usando a **API pública do CNJ** por `curl` | `scripts/datajud.sh` (7 subcomandos, mesma semântica da wiki do CNJ) + `docs/01`, `docs/02` + exemplos de saída | 32 verificações |
| 2 | Script **completo** em Python, na raiz, com **relatório em Markdown**, cobrindo "o processo, os anexos, tudo que puder" — e todo o público (DataJud + DJEN) | `main.py` (1 arquivo, sem dependências externas): DataJud + DJEN + montagem de número/validação de DV + relatório Markdown com anexos | 29 testes |
| 3 | **Validar conforme a documentação** e um **bootstrap que auto-cria o projeto** (todos os arquivos, todas as permissões) **e valida os testes, verificando resultado e códigos de teste** | `tests/testar_conformidade.py` (conferência contra a wiki/CNJ) + `bootstrap.sh` autossuficiente (7 etapas, manifesto SHA-256, `py_compile`, `bash -n`, suítes) + `BOOTSTRAP.md` | 29 + 25 verificações |
| 4 | **Gatilho** que só é positivo sem issues abertas, sem CI com erro e com testes verdes; **enquanto não positivo ⇒ continuidade**; cada issue testada e entregue com a instrução da seguinte; **toda action devolve JSON** (`id`, `mensagem`, `anexos`, `status`, `next_issue`) | `pipeline/gate.py` + `pipeline/blueprint.json` (BPMN) + `pipeline/backlog.json` + `.github/workflows/gates.yml` + `docs/03` + esta `ENTREGA.md` | 36 testes |

**Total: 151 verificações automatizadas**, todas offline, em 5 suítes (`make testes`).

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

### 2.3 Realizado (linha do tempo de execução)

| Quando | Marco |
| --- | --- |
| 11/10 20:42 | `3d9b774` — commit inicial do repositório |
| 12/10 21:33 | `3bd0cc4` — **kit de consulta à API Pública do DataJud** (curl + CLI + docs) |
| 12/10 22:10 | `17b35aa` — **`main.py`**: consulta de processo com relatório completo em Markdown |
| 12/10 22:11 | `aa5a5f4` — `__pycache__`/`.pyc` fora do versionamento |
| 12/10 22:30 | `436253a` — **`bootstrap.sh` auto-criador + `BOOTSTRAP.md` + validação de conformidade** |
| 12/10 22:4x | **PR #2** aberto (base `main` ← branch), +9.347/−1 em 20 arquivos |
| 13/10 | **Pedido 4**: `pipeline/gate.py`, `blueprint.json`, `backlog.json`, `.github/workflows/gates.yml`, `docs/03`, `tests/testar_pipeline.py`, `pipeline/verificar_cnj.py`, esta `ENTREGA.md`, Makefile com alvos de gate, bootstrap regenerado |

### 2.4 Testado (5 suítes, 151 verificações, tudo offline)

| Suíte | Verificações | O que cobre |
| --- | --- | --- |
| `tests/testar_conformidade.py` | 29 | conformidade com a doc oficial do CNJ: URL/rota/headers, aliases de tribunal, 15 campos do glossário, `search_after`, teto de 10.000, agregações com `.keyword`, 120 req/min, LGPD |
| `tests/testar_main.py` | 29 | `main.py`: DV do número CNJ (`% 97 == 1`), montagem do número de 20 dígitos, DataJud + DJEN com mocks, relatório Markdown, anexos, exit codes |
| `tests/rodar-testes.sh` | 32 | `scripts/datajud.sh`: chave pública, consulta, contagem, agregação, relatório, paginação, erros |
| `tests/testar_pipeline.py` | 36 | contrato JSON em todos os gates, semântica 0/1/2, `next_issue`, `--marcar`, blueprint, backlog e o próprio workflow |
| `tests/testar_bootstrap.sh` | 25 | bootstrap atualizado, criação byte a byte vs. repositório, permissões, 4 suítes rodando **dentro** do projeto recriado, gates rodando no projeto recriado, `--verificar`, proteção contra sobrescrita |

### 2.5 Validado (como cada promessa foi conferida)

| Validação | Comando | Resultado |
| --- | --- | --- |
| Conformidade com a documentação do CNJ | `python3 tests/testar_conformidade.py` | 29/29 OK |
| Bootstrap recria o projeto **idêntico** | `bash tests/testar_bootstrap.sh` | 25/25 OK, `diff -r` sem diferenças, hashes conferem |
| Planta BPMN × implementação | `python3 pipeline/gate.py blueprint` | `status "0"` — *5 gates, 15 transições* |
| Gatilho de continuidade | `python3 pipeline/gate.py continuidade` | `status "1"` (há issue aberta) — **continuidade**, como manda a regra |
| CI/CD | `python3 pipeline/gate.py cicd` | `status "0"` — 5 execuções, nenhuma com erro |
| Testes | `python3 pipeline/gate.py testes` | `status "0"` — 151 verificações aprovadas |
| Sem fonte de dados (`gh` ausente) | `python3 pipeline/gate.py issues --sem-gh` | `status "2"` (erro tipo 2) — não inventa sucesso |
| Projeto reconstruído funciona | `bash bootstrap.sh --destino /tmp/x` | 7/7 etapas ✔, exit 0 |

### 2.6 Produção (pronto para uso)

```bash
git clone https://github.com/camillanapoles/llm-arena-opencli && cd llm-arena-opencli

make testes        # 5 suítes, 151 verificações, offline
make gates         # veredito: 0 = nada pendente · 1 = continuidade · 2 = exige humano
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

pipeline/gate.py            executor dos gates (7 subcomandos) — o "gatilho"
pipeline/blueprint.json     planta BPMN do fluxo (validada pelo próprio pipeline)
pipeline/backlog.json       fila indexada de issues (instrução de teste por issue)
pipeline/verificar_cnj.py   instrução executável da ISSUE-006 (validação ao vivo do CNJ)
.github/workflows/gates.yml gatilho no GitHub Actions (5 jobs encadeados)

bootstrap.sh                recria o projeto inteiro e prova que funciona
tools/gerar_bootstrap.py    gerador/verificador do bootstrap (--conferir)
BOOTSTRAP.md                manual do bootstrap
ENTREGA.md                  este relatório

tests/                      5 suítes, 151 verificações (offline, com mocks)
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

---

## 5. Estado atual do pipeline (medido, não presumido)

```text
gate 1 · issues        → status "1"  (1 issue aberta: #3 SESSION CONTINUITY CONTROL)
gate 2 · CI/CD         → status "0"  (5 execuções analisadas, 0 com erro)
gate 3 · testes        → status "0"  (5 suítes aprovadas, 151 verificações)
gate 4 · continuidade  → status "1"  ⇒ continua; próxima do backlog: ISSUE-006
gate 5 · issue         → executa a ISSUE-006 quando o ambiente tiver internet
```

Backlog do projeto (`pipeline/backlog.json`):

| Issue | Título | Status |
| --- | --- | --- |
| ISSUE-001 | Kit de consulta por `curl` (DataJud/TJPE) | concluída |
| ISSUE-002 | `main.py` + relatório Markdown (DataJud + DJEN) | concluída |
| ISSUE-003 | Bootstrap auto-criador do projeto | concluída |
| ISSUE-004 | Validação de conformidade com a documentação do CNJ | concluída |
| ISSUE-005 | Pipeline de gates (contrato JSON, 0/1/2) | concluída |
| ISSUE-006 | Validação **ao vivo** contra o CNJ (`pipeline/verificar_cnj.py`) | **pendente** |
| ISSUE-007 | Decidir unificação com o fluxo da issue #3 (outra sessão) | bloqueada (decisão humana) |

---

## 6. Limitações conhecidas e próximos passos

| Limitação | Detalhe | Próximo passo |
| --- | --- | --- |
| Validação **ao vivo** do CNJ (ISSUE-006) | o ambiente de desenvolvimento não tem rota até `api-publica.datajud.cnj.jus.br` (TLS encerrado pelo proxy) — `pipeline/verificar_cnj.py` devolve honestamente `status "1"`/continuidade | rodar `python3 pipeline/verificar_cnj.py` numa máquina com internet; `status "0"` ⇒ `gate.py issue --id ISSUE-006 --marcar` |
| ISSUE-007 (unificação com a issue #3, de outra sessão) | o outro fluxo não está em `main` (`.github/workflows` → 404 no ref `main`) e vive na issue #3; não foi tocado | gate devolve `2` de propósito: requer decisão do usuário |
| YAML do workflow | não há PyYAML no ambiente de desenvolvimento; a checagem local é estrutural (indentação, tabulação, gatilhos, jobs) | a validação definitiva é a execução real do workflow no GitHub Actions — visível em **Actions → gates** |
| Permissão de escrita do bot | o job `executa-issue` só commita o backlog quando disparado com `marcar=true` (e o repositório precisa permitir "Read and write permissions" para o `GITHUB_TOKEN`) | conferir em **Settings → Actions → General → Workflow permissions** |
| Consulta pública do TJPE (Projudi/PJe) | as URLs do TJPE não respondem fora da rede da Justiça (`srv01…`, `pje.cloud…`) | usar o kit em rede compatível; o DataJud/DJEN cobrem o que é público nacional |

---

## 7. Checklist final de entrega

- [x] **Solicitado** — os 4 pedidos implementados no branch (kit curl, `main.py` Markdown, conformidade + bootstrap, pipeline de gates documentado)
- [x] **Incrementado** — DJEN, número CNJ, glossário, resiliência, LGPD, manifesto SHA-256, erro tipo 1 × 2, verificador ao vivo (seção 2.2)
- [x] **Realizado** — 5 marcos de commit + 9 arquivos novos, tudo versionado no branch (seção 2.3)
- [x] **Testado** — 5 suítes, **151 verificações**, todas offline e reprodutíveis (seção 2.4)
- [x] **Validado** — conformidade com a doc do CNJ, bootstrap byte a byte, planta BPMN, semântica 0/1/2, projeto recriado do zero (seção 2.5)
- [x] **Produção** — `make testes`, `make gates`, `make consultar`, `bash bootstrap.sh` prontos para uso (seção 2.6)
- [x] **Documentado** — `README.md` (visão geral), `BOOTSTRAP.md` (instalação), `docs/01-03` (API, receitas, pipeline) e esta `ENTREGA.md`
- [ ] **Pendente do usuário** — rodar a validação ao vivo do CNJ (ISSUE-006) num ambiente com internet e decidir a ISSUE-007

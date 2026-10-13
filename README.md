# llm-arena-opencli — consulta processual nas APIs públicas do CNJ

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

## 1. Consultar um processo (`main.py`)

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

### O que entra no relatório

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

### Opções

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

### Anexos e documentos: o que dá e o que não dá

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

## 2. Consultas agregadas (`scripts/datajud.sh`)


---

## Início rápido

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

## Comandos do script

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

## Relatório

```bash
./scripts/datajud.sh relatorio --tribunal tjpe --saida saida
# → saida/relatorio-TJPE-AAAAMMDD-HHMM.md  (total, 7 agregações, notas legais)
# → saida/agg-*.tsv e saida/agg-*.csv      (dados para Excel/pandas)
```

Veja o formato em [`docs/exemplo-saida/relatorio-tjpe-exemplo.md`](docs/exemplo-saida/relatorio-tjpe-exemplo.md).

O relatório registra endpoint, hora UTC, filtros usados e nº de requisições — e traz as notas do Termo de
Uso (dados não garantidos pelo CNJ, uso não comercial, ciência ao CNJ ao divulgar, LGPD).

## Pipeline de gates (o gatilho)

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

### Validação ao vivo no runner (event-driven)

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

## Testes (sem internet)

```bash
make testes                          # todas as 6 suítes (228 verificações)
python3 tests/testar_conformidade.py # 29 — conformidade com a doc oficial do CNJ
python3 tests/testar_main.py         # 29 — NUP/DV, relatório, DJEN, erros
./tests/rodar-testes.sh              # 32 — datajud.sh (curl + jq)
python3 tests/testar_pipeline.py     # 67 — contrato JSON, 0/1/2, direção, blueprint, workflow
python3 tests/testar_fabrica.py      # 37 — fábrica de issues (SQLite, eventos, padrão BPMN)
./tests/testar_bootstrap.sh          # 27 — recria o projeto e compara byte a byte
```

As suítes sobem mocks locais das APIs (`tests/mock_apis.py` e `tests/mock_datajud.py`) que imitam
autenticação, erros 400/401/404/429, agregações e paginação. **Nenhuma requisição real ao CNJ é feita.**

### Reconstruir o projeto do zero

```bash
bash bootstrap.sh                  # cria ./projeto-datajud, confere hashes e roda as 4 suítes
bash bootstrap.sh --verificar      # só valida uma cópia existente
python3 tools/gerar_bootstrap.py   # regera o bootstrap após editar algum arquivo
```

Detalhes de estrutura, permissões, etapas e saída esperada: [`BOOTSTRAP.md`](BOOTSTRAP.md).

## Requisitos

`bash` ≥ 4.3, `curl` e `jq`. Em Debian/Ubuntu: `sudo apt install curl jq`.

## Regras de uso (resumo do Termo de Uso v1.2)

- **120 requisições por minuto** no máximo (item 3.13); o CNJ pode limitar sem aviso (3.14).
- Uso **legal e não comercial** (3.3, 3.8).
- O CNJ **não garante** precisão, integridade ou atualidade (3.6).
- Ao divulgar relatórios, **dê ciência ao CNJ** (3.9).
- Não coletar, armazenar ou cruzar dados pessoais (4.2, LGPD).

Os dados são metadados de processos **públicos** (sem partes, sem peças). A atualização depende do envio
de cada tribunal ao DataJud — pode haver atraso de dias.

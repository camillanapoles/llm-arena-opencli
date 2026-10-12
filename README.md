# llm-arena-opencli — API Pública do DataJud (CNJ) via curl

Kit para consultar a **API Pública do DataJud** (metadados de processos públicos do Judiciário brasileiro)
direto do terminal, com foco no **TJPE (Pernambuco)**:

- `scripts/datajud.sh` — CLI em `bash` + `curl` + `jq`: contagem, busca por processo, agregações,
  relatório em Markdown/CSV e paginação.
- `docs/01-api-datajud.md` — o que a API oferece, autenticação, campos (glossário), DSL, erros e regras.
- `docs/02-receitas-curl-tjpe.md` — **receitas `curl` prontas** para contar processos, gerar relatório e
  baixar listas do TJPE.
- `docs/exemplo-saida/` — exemplo do relatório gerado (saída de demonstração do mock, não são dados reais).
- `tests/` — mock local da API + suíte de testes (32 verificações), roda **sem internet e sem chave real**.

Baseado na documentação oficial: <https://datajud-wiki.cnj.jus.br/api-publica/acesso>

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

## Testes (sem internet)

```bash
./tests/rodar-testes.sh
```

Sobe `tests/mock_datajud.py` (API simulada: autenticação, erros 400/401/404/429, agregações, paginação) e
valida os 32 comportamentos do script. Nenhuma requisição real ao CNJ é feita.

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

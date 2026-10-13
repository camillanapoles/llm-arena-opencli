# API Pública do DataJud (CNJ) — guia de referência

Estudo da documentação oficial ([wiki do DataJud](https://datajud-wiki.cnj.jus.br/api-publica/acesso)) com
tudo o que é necessário para consultar os metadados processuais via `curl`.

---

## 1. O que é

A **API Pública do DataJud** dá acesso aos **metadados** dos processos **públicos** de todos os tribunais
brasileiros, a partir da Base Nacional de Dados do Poder Judiciário (CNJ), conforme a Portaria nº 160/2020.

O que vem no retorno (capa do processo + movimentações):

- número único (CNJ), tribunal, grau/instância, data de ajuizamento, nível de sigilo;
- classe processual e assuntos (Tabelas Processuais Unificadas — TPU);
- órgão julgador (vara/câmara/turma), código do município (IBGE);
- sistema processual (PJe, eproc…), formato (físico/eletrônico);
- lista de **movimentos** com código, nome, data/hora e complementos tabelados.

O que **não** vem: nome das partes, CPF/CNPJ, conteúdo das peças. A wiki cita expressamente o resguardo de
processos sigilosos e de dados das partes.

- `dataHoraUltimaAtualizacao`: milissegundos do `millisInsercao` na origem (quando o tribunal enviou o dado).
- `@timestamp`: quando o documento foi atualizado no índice do DataJud.

> A atualização depende de cada tribunal enviar os dados ao CNJ — costuma haver atraso de alguns dias.

---

## 2. Acesso e autenticação

| Item | Valor |
| --- | --- |
| URL base | `https://api-publica.datajud.cnj.jus.br/` |
| Rota | `POST /<alias_do_tribunal>/_search` |
| Cabeçalho | `Authorization: APIKey <chave pública>` |
| Cabeçalho | `Content-Type: application/json` |
| Corpo | Query DSL do Elasticsearch (JSON) |

A chave é **pública**, publicada na página [Acesso](https://datajud-wiki.cnj.jus.br/api-publica/acesso) e
**pode ser trocada pelo CNJ a qualquer momento**. O script deste repositório embute a chave vigente no
momento da escrita e permite atualizá-la com:

```bash
export DATAJUD_API_KEY="$(bash scripts/datajud.sh chave)"
```

Chave vigente na data desta documentação:

```
cDZHYzlZa0JadVREZDJCendQbXY6SkJlTzNjLV9TRENyQk1RdnFKZGRQdw==
```

Nos exemplos da wiki o esquema aparece como `ApiKey` e na página de acesso como `APIKey` — o cabeçalho HTTP
não diferencia maiúsculas/minúsculas no nome, e ambos os formatos de valor funcionam.

### Alias do tribunal (o que muda por tribunal)

O único trecho que muda entre tribunais é o alias na URL:

| Tribunal | Endpoint |
| --- | --- |
| **TJPE — Tribunal de Justiça de Pernambuco** | `https://api-publica.datajud.cnj.jus.br/api_publica_tjpe/_search` |
| TRF5 (Justiça Federal da 5ª Região) | `.../api_publica_trf5/_search` |
| TRT6 (Trabalho, 6ª Região) | `.../api_publica_trt6/_search` |
| TRE-PE (Eleitoral) | `.../api_publica_tre-pe/_search` |
| STJ / TST / TSE / STM | `.../api_publica_stj/_search` etc. |

A lista completa (superiores, federais, estaduais, trabalho, eleitoral e militar) está em
<https://datajud-wiki.cnj.jus.br/api-publica/endpoints>.

> ⚠️ Um processo de PE pode estar em outro índice: recursos ao TRF5 ficam em `api_publica_trf5`,
> execuções trabalhistas em `api_publica_trt6`, matéria eleitoral em `api_publica_tre-pe`.

---

## 3. Campos disponíveis (glossário)

| Campo | Tipo | Descrição |
| --- | --- | --- |
| `id` | text/keyword | Chave `Tribunal_Classe_Grau_OrgaoJulgador_NumeroProcesso` |
| `tribunal` | text/keyword | Sigla do tribunal (ex.: `TJPE`) |
| `numeroProcesso` | text/keyword | Numeração única CNJ **sem formatação** (20 dígitos) |
| `dataAjuizamento` | datetime | Data de ajuizamento da capa |
| `grau` | text/keyword | Instância: `G1`, `G2`, `JE`, … |
| `nivelSigilo` | long | Nível de sigilo |
| `formato.codigo` / `formato.nome` | long / text | Físico ou Eletrônico |
| `sistema.codigo` / `sistema.nome` | long / text | Sistema processual de origem |
| `classe.codigo` / `classe.nome` | long / text | Classe processual (TPU) |
| `assuntos[].codigo` / `.nome` | long / text | Assuntos (TPU) |
| `orgaoJulgador.codigo` / `.nome` | long / text | Vara/câmara atual |
| `orgaoJulgador.codigoMunicipioIBGE` | long | Município do órgão julgador |
| `movimentos[].codigo` / `.nome` / `.dataHora` | long / text / datetime | Movimentações |
| `movimentos[].complementosTabelados[]` | array | Complementos da movimentação |
| `dataHoraUltimaAtualizacao` | datetime | Marca da origem (controle interno) |
| `@timestamp` | datetime | Marca de atualização no índice (controle interno) |

Campos de texto normalmente possuem subcampo `.keyword` (agregável); campos `long` (códigos) são
agregáveis diretamente.

---

## 4. Consultas essenciais

### 4.1 Buscar por número do processo

```json
{ "query": { "match": { "numeroProcesso": "00008323520184013202" } } }
```

### 4.2 Combinar filtros (classe + órgão julgador)

```json
{
  "query": {
    "bool": {
      "must": [
        { "match": { "classe.codigo": 1116 } },
        { "match": { "orgaoJulgador.codigo": 13597 } }
      ]
    }
  }
}
```

### 4.3 Filtrar por período de ajuizamento

```json
{
  "query": {
    "bool": {
      "must": [
        { "range": { "dataAjuizamento": { "gte": "2024-01-01T00:00:00.000Z",
                                           "lte": "2024-12-31T23:59:59.999Z" } } }
      ]
    }
  }
}
```

### 4.4 Contar sem trazer documentos

```json
{ "query": { "match_all": {} }, "size": 0, "track_total_hits": true }
```

Resposta: `hits.total.value` e `hits.total.relation`. Quando `relation` for `"gte"`, o valor é **10.000**
e o total real é maior — a API trunca a contagem nesse teto.

### 4.5 Agregações (o "relatório" propriamente dito)

```json
{
  "size": 0,
  "query": { "match_all": {} },
  "aggs": { "por_classe": { "terms": { "field": "classe.codigo", "size": 10 } } }
}
```

- `terms` em campo de código (`classe.codigo`, `orgaoJulgador.codigo`, `grau.keyword`, …).
- Se a API responder `Fielddata is disabled on text fields`, use o subcampo `.keyword`
  (ex.: `orgaoJulgador.nome.keyword`) ou o campo de código correspondente.
- Para séries temporais: `date_histogram` em `dataAjuizamento` com `calendar_interval: year` (ou `month`)
  e `format: yyyy` (ou `yyyy-MM`).

### 4.6 Paginar com `search_after` (recomendado pelo CNJ)

`size` aceita de 1 a 10.000 documentos por página. Para volumes maiores, ordene por `@timestamp` e use o
vetor `sort` do último documento como `search_after` da página seguinte:

```json
{
  "size": 100,
  "query": { "match_all": {} },
  "sort": [ { "@timestamp": { "order": "asc" } } ],
  "search_after": [ 1681366085550 ]
}
```

---

## 5. Códigos de resposta

| HTTP | Significado | O que fazer |
| --- | --- | --- |
| 200 | OK | — |
| 400 | Query inválida (campo inexistente, agregação sem `fielddata`) | ajustar o corpo (usar `.keyword` / código) |
| 401/403 | Chave ausente, inválida ou trocada | reler a wiki e atualizar `DATAJUD_API_KEY` |
| 404 | Alias de tribunal inexistente | conferir a lista de endpoints |
| 429 | Excesso de requisições | reduzir o ritmo (limite: 120 req/min) |
| 5xx | Instabilidade do CNJ | tentar mais tarde, com backoff |

---

## 6. Regras de uso (Termo de Uso v1.2)

Fonte: [Termos-de-uso-api-publica-V1.2.pdf](https://formularios.cnj.jus.br/wp-content/uploads/2023/11/Termos-de-uso-api-publica-V1.2.pdf)
(versão de 27/11/2023 — a leitura da API implica aceitação tácita).

- **3.13 — no máximo 120 requisições por minuto** (salvo autorização expressa do CNJ).
- **3.14 —** o CNJ pode limitar requisições por usuário/chave sem aviso prévio.
- **3.3 / 3.8 —** uso exclusivamente legal e **não comercial**; proibido modificar, distribuir, vender ou
  explorar comercialmente a API ou informação derivada.
- **3.6 —** o CNJ **não garante** precisão, integridade ou atualidade dos dados.
- **3.9 —** quem divulgar estudo/relatório ao público deve **dar ciência ao CNJ**.
- **4.2 / 4.6 —** não coletar, armazenar, processar nem cruzar dados pessoais oriundos da API (LGPD).
- **3.19 —** comunicar ao CNJ falhas de segurança ou informação incorreta.

Na prática: identifique-se (`User-Agent`), coloque pausa entre páginas, prefira agregações a varrer a base,
não repita a consulta do que já foi obtido (`@timestamp` permite buscar só o que mudou).

---

## 7. Boas práticas

1. **Cache/checkpoint por `@timestamp`** — só reler o que mudou desde a última coleta.
2. **Reusar códigos** — descubra o código da vara/classe uma vez e guarde.
3. **Agregar em vez de paginar** — para relatórios, `aggs` custa 1 requisição e devolve o consolidado.
4. **Paciência** — 120 req/min é o teto global; com 1 req a cada 0,5 s você fica em 120/min. Deixe folga.
5. **Tratar `gte`** — total acima de 10.000 aparece truncado; refine o recorte ou use `aggs`.
6. **Não usar dados pessoais** — o índice é de metadados, mas a LGPD vale para qualquer cruzamento.

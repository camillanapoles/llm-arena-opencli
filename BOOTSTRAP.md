# BOOTSTRAP.md — criação, configuração, validação e testes do projeto

Este é o **documento único** do projeto: ele descreve como o `bootstrap.sh` recria
**tudo do zero** (todos os diretórios, todos os arquivos, todas as permissões), como
ele **valida e testa** o resultado, e qual é exatamente a **saída esperada** de cada
etapa. O `bootstrap.sh` é autossuficiente: traz o conteúdo dos 31 arquivos embutido —
não precisa de internet, Git nem de nenhum arquivo externo.

```bash
bash bootstrap.sh                      # cria ./projeto-datajud, valida e roda os 90 testes
bash bootstrap.sh --destino /opt/jus   # escolhe outro diretório
bash bootstrap.sh --verificar          # só confere um projeto já criado (hashes + permissões)
```

---

## 1. Uso em 30 segundos

| Situação | Comando |
| --- | --- |
| Recriar o projeto inteiro (local) | `bash bootstrap.sh` |
| Recriar em outro lugar | `bash bootstrap.sh --destino ~/projetos/datajud` |
| Sobrescrever um destino existente | `bash bootstrap.sh --destino ./x --forcar` |
| Criar sem rodar os testes | `bash bootstrap.sh --so-criar` |
| Conferir um projeto já criado | `bash bootstrap.sh --destino ./projeto-datajud --verificar` |
| Atualizar o bootstrap após editar um arquivo | `python3 tools/gerar_bootstrap.py` (ou `make bootstrap`) |
| Provar que o bootstrap recria o repo idêntico | `./tests/testar_bootstrap.sh` |

O `bootstrap.sh` não depende de rede. Só as consultas reais ao CNJ (comandos
`python3 main.py …` e `scripts/datajud.sh …`) precisam de internet.

---

## 2. Estrutura completa criada (diretórios, arquivos e permissões)

```
projeto-datajud/                        755   (diretório raiz)
├── .gitignore                          644
├── BOOTSTRAP.md                        644   este documento
├── Makefile                            644   atalhos (make consultar | relatorio | testes)
├── README.md                           644   porta de entrada
├── bootstrap.sh                        755   instalador/verificador (copia a si mesmo)
├── main.py                             755   consulta 1 processo → relatório Markdown
├── docs/                               755
│   ├── 01-api-datajud.md               644   referência da API pública do DataJud
│   ├── 02-receitas-curl-tjpe.md        644   receitas curl prontas (TJPE)
│   └── exemplo-saida/                  755
│       ├── relatorio-processo-exemplo.md   644   exemplo do relatório de processo
│       ├── relatorio-tjpe-exemplo.md       644   exemplo do relatório agregado
│       ├── agg-grau.tsv                    644   dados de exemplo (TSV)
│       └── agg-orgao-nome.csv              644   dados de exemplo (CSV)
├── scripts/                            755
│   └── datajud.sh                      755   CLI curl+jq: contar, agregar, relatório, paginar
├── tests/                              755
│   ├── mock_apis.py                    755   dublê local (DataJud + DJEN + wiki)
│   ├── mock_datajud.py                 755   dublê local (só DataJud, para o datajud.sh)
│   ├── rodar-testes.sh                 755   32 testes do scripts/datajud.sh
│   ├── testar_main.py                  755   29 testes do main.py
│   ├── testar_conformidade.py          755   29 testes de conformidade com a doc do CNJ
│   └── testar_bootstrap.sh             755   verificação do próprio bootstrap
└── tools/                              755
    └── gerar_bootstrap.py              755   regenera/conferê o bootstrap.sh
```

**Regra de permissões:** `755` para tudo que se executa (scripts, testes, `main.py`,
`bootstrap.sh`) e para diretórios; `644` para documentos e dados.

---

## 3. Pré-requisitos

| Dependência | Versão | Obrigatória? | Para quê |
| --- | --- | --- | --- |
| `bash` | 4.0+ | sim (para o bootstrap) | instalação, testes do `datajud.sh` |
| `python3` | 3.8+ | sim | `main.py`, mocks e suítes de teste |
| `curl` + `jq` | quaisquer | opcionais | apenas `scripts/datajud.sh` |
| internet | — | opcional | apenas consultas reais ao CNJ |

O bootstrap **para com erro claro** se faltar `bash`/`python3`. Se faltar `curl`/`jq`,
ele apenas avisa — porque o `main.py` não usa nenhum dos dois. Nada de `pip install`:
o projeto inteiro roda com a biblioteca padrão do Python.

---

## 4. As 7 etapas do bootstrap (e como cada uma falha)

| # | Etapa | O que faz | Falha se… |
| --- | --- | --- | --- |
| 1 | Pré-requisitos | valida bash 4+, python 3.8+, detecta curl/jq | versão mínima não atingida (sai com 1) |
| 2 | Diretórios | cria a raiz + `docs/`, `docs/exemplo-saida/`, `scripts/`, `tests/`, `tools/`; `chmod 755` | destino existe e não está vazio sem `--forcar` |
| 3 | Arquivos | escreve os 31 arquivos a partir do conteúdo embutido; aplica `755`/`644` | execução via pipe (avisa que o `bootstrap.sh` não pôde ser copiado) |
| 4 | Integridade | recalcula `sha256sum` de cada arquivo e compara com o manifesto | qualquer byte diferente → não segue (sai com 1) |
| 5 | Permissões | confere o modo de cada arquivo com `stat` | modo divergente → avisa (corrija com `chmod`) |
| 6 | Sintaxe | `python3 -m py_compile` em 11 arquivos ; `bash -n` em 4 scripts | qualquer erro de sintaxe |
| 7 | Testes | roda as 5 suítes offline e captura os códigos de saída | alguma suíte ≠ 0 |

O manifesto SHA-256 (na etapa 4) prova que o destino é **byte a byte** igual ao que o
bootstrap promete. É o que separa "criei arquivos" de "criei *este* projeto".

---

## 5. Validação conforme a documentação oficial do CNJ

Cada item abaixo é verificado automaticamente por `tests/testar_conformidade.py`
(29 testes). Fonte: wiki oficial do DataJud e Termo de Uso v1.2.

| Item da documentação | Onde está documentado | Como o projeto cumpre | Teste que verifica |
| --- | --- | --- | --- |
| URL base e rota `POST /api_publica_<alias>/_search` | [Acesso](https://datajud-wiki.cnj.jus.br/api-publica/acesso) / [Endpoints](https://datajud-wiki.cnj.jus.br/api-publica/endpoints) | `DATAJUD_BASE` + `api_publica_{alias}/_search` | `TesteAcesso.test_url_base_oficial`, `test_rota_search_com_alias` |
| Cabeçalho `Authorization: APIKey <chave>` | Acesso | enviado em todas as requisições | `test_cabecalho_authorization_apikey` |
| Cabeçalho `Content-Type: application/json` | Exemplos 1–3 | enviado em todo POST com corpo | `test_cabecalho_content_type_json` |
| Chave pública da wiki (pode mudar) | Acesso | embutida como default + comando `--chave-publica` relê a wiki | `test_chave_publica_vigente_embutida`, `test_comando_para_reler_a_chave_na_wiki` |
| Alias por tribunal | Endpoints | `J.TR` → alias (inclui `tjdft`, `tre-dft`, `tst`, `tse`) | `TesteEndpoints.*` |
| Campos do glossário | [Glossário](https://datajud-wiki.cnj.jus.br/api-publica/glossario) | 15 campos lidos e documentados | `TesteGlossario.*` |
| Busca por número | [Exemplo 1](https://datajud-wiki.cnj.jus.br/api-publica/exemplos/exemplo1) | `match` em `numeroProcesso` | `test_busca_por_numero_usa_match` |
| Filtros por classe/órgão | [Exemplo 2](https://datajud-wiki.cnj.jus.br/api-publica/exemplos/exemplo2) | `bool.must` com `classe.codigo`, `orgaoJulgador.codigo` | `test_filtros_por_classe_e_orgao` |
| Paginação `search_after` + `sort @timestamp asc` | [Exemplo 3](https://datajud-wiki.cnj.jus.br/api-publica/exemplos/exemplo3) | `paginar` usa o vetor `sort` da página anterior | `test_paginacao_com_search_after_e_sort_timestamp` |
| `size` entre 1 e 10.000 | Exemplo 3 | validado na CLI (`--pagina`) | `test_tamanho_de_pagina_dentro_do_limite` |
| Total truncado em 10.000 (`relation: gte`) | Considerações finais | avisa e sugere fatiar/agregar | `test_contagem_trata_teto_de_10000` |
| Agregações `terms` e `date_histogram` | Considerações finais | usa `calendar_interval` ano/mês | `test_agregacoes_terms_e_historico_de_datas` |
| `Fielddata is disabled` → usar `.keyword` | Exemplo 2 / boas práticas | fallback automático de campo | `test_fallback_para_campo_keyword` |
| **120 requisições/minuto** (Termo, 3.13) | [Termo de Uso](https://formularios.cnj.jus.br/wp-content/uploads/2023/11/Termos-de-uso-api-publica-V1.2.pdf) | pausas entre requisições e avisos | `TesteTermoDeUso.*` |
| Uso não comercial + ciência ao CNJ (3.3/3.8/3.9) | Termo | notas fixas no rodapé do relatório | `test_uso_nao_comercial_e_ciencia_ao_cnj_no_relatorio` |
| LGPD: não coletar dados pessoais (4.2/4.6) | Termo | nenhum campo de parte/CPF no código | `test_sem_dados_pessoais_coletados` |
| CNJ não garante precisão/atualidade (3.6) | Termo | aviso explícito na seção 10 do relatório | `test_avisos_de_limitacao_presentes_no_relatorio` |
| Numeração única e DV (Resolução CNJ 65/2008) | Res. 65, Anexo VIII | DV módulo 97 base 10, conferido contra números oficiais | `TesteNumeroCNJ.test_dv_de_numeros_reais_confere` |

**O que a API pública NÃO entrega** (e o relatório diz isso em vez de fingir): peças,
anexos, nomes/CPF das partes e valores. Autos e documentos ficam na consulta pública do
tribunal (PJe/e-SAJ) — o relatório inclui os links. Alternativa autenticada para
advogados: **MNI** do PJe, com certificado digital.

---

## 6. Códigos de teste: o que cada suíte cobre e o resultado esperado

Rode tudo de uma vez com `make testes`: são **6 suítes** e **228 verificações**, todas offline,
contra mocks locais (nenhuma requisição real ao CNJ).

| Suíte | Arquivo | Testes | Cobre | Saída esperada |
| --- | --- | --- | --- | --- |
| Conformidade | `tests/testar_conformidade.py` | **29** | itens da doc oficial (seção 5), ausência de dependências externas, shebang/permissões, sintaxe do shell | `Ran 29 tests` / `OK` / código **0** |
| Consulta de processo | `tests/testar_main.py` | **29** | DV e estrutura do NUP (4 números oficiais), decodificação de tribunais, as 10 seções do relatório, DJEN, `--json`, `-o`, erros 400/401/404/429 | `Ran 29 tests` / `OK` / código **0** |
| Consultas agregadas | `tests/rodar-testes.sh` | **32** | `contar`, `agregar` (com fallback de campo), `processo`, `paginar` (`search_after`), `relatorio`, tratamento de 401/404/429/rede, `--debug` | `32 passaram, 0 falharam` / código **0** |
| Pipeline de gates | `tests/testar_pipeline.py` | **67** | contrato JSON (`id`/`mensagem`/`anexos`/`status`/`next_issue`/`direcao`/`proximo_passo`), semântica 0/1/2, `next_issue` (mesma issue × próxima), direção de continuidade, `--marcar`, blueprint, backlog e o workflow (inclui `bash -n` em cada bloco `run:`) | `Ran 67 tests` / `OK` / código **0** |
| Fábrica de issues | `tests/testar_fabrica.py` | **37** | POO (8 classes), esquema SQLite, padrão do blueprint, construção da N+1 só após sucesso, eventos event-driven, round-trip SQLite ⇄ backlog.json, contrato da CLI e do gate `fabrica` | `Ran 37 tests` / `OK` / código **0** |
| Recriação | `tests/testar_bootstrap.sh` | **27** (7 grupos) | bootstrap atualizado, criação, `diff -r` contra o repo, permissões, suítes dentro do projeto novo, `--verificar`, proteção contra sobrescrita | `0 falharam` / código **0** |

Exemplo de saída final do `bootstrap.sh`:

```
== Resultado do bootstrap ==
  destino..... : /caminho/projeto-datajud
  arquivos.... : 31 no manifesto SHA-256 (+ bootstrap.sh)
  permissões.. : 755 em scripts/testes, 644 em docs/dados
  python...... : compila
  bash........ : sem erro de sintaxe
  teste conf.. : ok
  teste main.. : ok
  teste shell. : ok
  teste pipe.. : ok
  teste fabr.. : ok

  Próximos passos:
    cd /caminho/projeto-datajud
    python3 main.py 0001234-56.2024.8.17.2001   # consulta real (precisa de internet)
    make gates                                  # veredito de continuidade do pipeline
    make fabrica                                # estado da fábrica de issues (SQLite)
    make testes                                 # roda as 6 suítes de novo

Bootstrap concluído com sucesso.
```

## 7. Códigos de saída (exit codes)

| Artefato | Código | Significado |
| --- | --- | --- |
| `bootstrap.sh` | `0` | tudo criado, hashes conferidos e 90 testes passando |
| | `1` | pré-requisito ausente, hash divergente, sintaxe inválida ou suíte reprovada |
| `main.py` | `0` | relatório gerado |
| | `1` | uso incorreto (sem número do processo) |
| | `2` | falha de consulta (número inválido, 401/404/429, processo não encontrado) |
| | `130` | interrompido pelo usuário (Ctrl+C) |
| `scripts/datajud.sh` | `0` | comando concluído |
| | `1` | erro tratado (chave recusada, alias inexistente, limite de requisições, rede) |
| `tests/*` | `0` | todas as asserções passaram |
| | `1` | pelo menos uma falhou (a saída lista cada ✘) |

---

## 8. Verificação independente (como conferir sem confiar)

1. **Está atualizado?** `python3 tools/gerar_bootstrap.py --conferir` — falha se alguém
   editou um arquivo e esqueceu de regenerar o bootstrap.
2. **Recria idêntico?** `./tests/testar_bootstrap.sh` — cria num diretório temporário e
   roda `diff -r` contra o repositório; qualquer byte diferente é reportado.
3. **Integridade dos arquivos:** o próprio bootstrap recalcula `sha256sum` de cada
   arquivo e compara com o manifesto embutido (`--verificar` faz isso sozinho).
4. **Testes no projeto novo:** a suíte roda *dentro* da árvore recriada — não basta o
   código existir, ele precisa funcionar no destino.
5. **Sem efeitos colaterais:** nada é criado fora do `--destino`; os mocks usam portas
   efêmeras em `127.0.0.1` e nenhum teste acessa a internet.

---

## 9. Solução de problemas

| Sintoma | Causa | Solução |
| --- | --- | --- |
| `destino já existe e não está vazio` | proteção contra sobrescrita | use `--forcar` ou outro `--destino` |
| `hash diferente: …` | destino alterado após a criação | apague o destino e rode de novo |
| `HTTP 401` nas consultas reais | o CNJ trocou a chave pública | `python3 main.py --chave-publica` e exporte `DATAJUD_API_KEY` |
| `HTTP 429` | passou de 120 req/min | aguarde; o projeto já pausa entre requisições |
| `curl e/ou jq ausentes` | só o `datajud.sh` depende deles | instale (`apt install curl jq`) ou use só o `main.py` |
| `nenhum documento …` no `main.py` | processo sigiloso ou tribunal errado | confirme o DV/tribunal; use `--todos` para varrer TJPE, TRF5, TRT6, TRE-PE, STJ, TST, TSE e STM |
| `bootstrap.sh está DESATUALIZADO` | arquivos editados após a geração | `python3 tools/gerar_bootstrap.py` |

---

## 10. Regras de uso dos dados (Termo de Uso v1.2 + LGPD)

- **120 requisições por minuto** no máximo (item 3.13); o CNJ pode limitar sem aviso (3.14).
- Uso **legal e não comercial** (3.3, 3.8).
- O CNJ **não garante** precisão, integridade ou atualidade (3.6).
- Ao divulgar relatórios, **dê ciência ao CNJ** (3.9).
- Não coletar, armazenar ou cruzar dados pessoais (4.2, 4.6 — LGPD).
- A API expõe **metadados de processos públicos**; partes, valores e peças não são dela.

---

## 11. Manutenção

| Quando | Faça |
| --- | --- |
| Mudou qualquer arquivo do projeto | `python3 tools/gerar_bootstrap.py` (regenera) e `./tests/testar_bootstrap.sh` |
| O CNJ trocou a chave pública | nada a mudar no código: use `--chave-publica`/`DATAJUD_API_KEY`; opcionalmente atualize o default no `main.py` e no `scripts/datajud.sh` |
| Adicionou um arquivo novo | inclua-o em `ARQUIVOS` no `tools/gerar_bootstrap.py` (com a permissão) e regenere |
| Quer só validar | `bash bootstrap.sh --destino . --verificar` |

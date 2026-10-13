# 04 — Decisão de unificação dos fluxos (d917b13b × ed79bd77)

> **Registro de decisão** exigido pela ISSUE-007/ISSUE-008 do backlog da sessão
> `arena/ed79bd77` (`pipeline/backlog-cnj.json`). Este arquivo satisfaz
> `test -s docs/04-decisao-unificacao.md`.

## Decisão

**OPÇÃO (a)+(c) — UNIFICAR, com contrato compartilhado e registro único.**

Decidido pelo usuário em 2026-10-13: *“integrar ambas, pra que a outra siga
conforme ambas”*. As duas sessões continuam com suas implementações
(Node/TS × Python), mas passam a seguir **o mesmo fluxo gate-driven BPMN**:

1. **Contrato único de envelope** — `pipeline/contract.schema.json`
   (neutro de linguagem). O dialeto camelCase (`nextIssue`, `exitCode`,
   `direction`, `addenda`) é o canônico; o dialeto snake_case da sessão CNJ
   (`next_issue`, `codigo_saida`, `direcao`, `anexos`) é **equivalente e
   mapeável 1:1** (`src/pipeline/interop.ts`, tabela em `docs/INTEGRATION.md`).
2. **Registro unificado de pendências** — `pipeline/registry.json`
   (`pipeline-cli registry`): mescla a cadeia `pipeline/blueprint.json` (d917)
   com o `pipeline/backlog.json` (ed79) num backlog único com namespace de
   origem (`d917b13b:ISSUE-1`, `ed79bd77:ISSUE-007`).
3. **Gate de continuidade único** — a regra já é a mesma nas duas implementações:
   `positivo ⇔ (0 issues abertas) ∧ (CI sem erros) ∧ (testes presentes e
   aprovados)`; enquanto não positivo ⇒ **continuidade**.
4. **Workflow de integração** — `.github/workflows/integration.yml` roda as
   DUAS suítes (`npm run ci` + `bash tests/rodar-testes.sh` + testes Python) e
   publica o envelope mesclado + registro a cada push/PR.

## O que a sessão ed79bd77 passa a fazer (como a outra segue conforme ambas)

- A ISSUE-007 é **desbloqueada** com esta decisão; a ISSUE-008 pode ser
  concluída copiando este arquivo para `docs/04-decisao-unificacao.md` na
  branch dela (ou consumindo-o direto da branch d917b13b no merge).
- O `gate.py`/`factory.py` continuam em Python — **nenhuma reimplementação**;
  basta que os envelopes emitidos sejam aceitos pelo schema
  `pipeline/contract.schema.json` (o dialeto snake_case atual já é aceito pelo
  adaptador `fromCnjEnvelope`).
- O backlog dela é incluído automaticamente no registro unificado
  (`pipeline/backlog-cnj.json` é sincronizado pelo `integration.yml`).
- Quando ambos os PRs (#1 e #2) forem mesclados em `main`, o fluxo único passa
  a operar pelo `blueprint.yml` + `gate.py` lado a lado, com o registro como
  fonte única de pendências.

## Status

| Item | Estado |
| --- | --- |
| Contrato compartilhado (`pipeline/contract.schema.json`) | ✅ entregue (branch d917b13b) |
| Adaptador bidirecional (`src/pipeline/interop.ts`) | ✅ entregue + testado |
| Registro unificado (`pipeline-cli registry`) | ✅ entregue + testado |
| Workflow `integration.yml` (duas suítes + envelope mesclado) | ✅ entregue |
| Copiar este registro para `docs/04-decisao-unificacao.md` na branch ed79bd77 | ⏳ a cargo da sessão paralela (ou do merge) |

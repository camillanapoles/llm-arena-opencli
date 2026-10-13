## [IMPLEMENT] Integração IGC/UNIFY registrada no painel de continuidade

Atendendo ao deliverable da **ISSUE-009** (backlog da pilha CNJ) e ao fluxo de continuidade desta sessão (protocolo IGC v1.0):

- **Decisão de unificação:** [`docs/04-decisao-unificacao.md`](https://github.com/camillanapoles/llm-arena-opencli/blob/arena/d917b13b-llm-arena-opencli/docs/04-decisao-unificacao.md) — UNIFY (manter as duas implementações + contrato único + registro unificado)
- **Guia de integração (mapeamento camelCase ⇄ CNJ, incl. `debts↔debitos`):** [`docs/INTEGRATION.md`](https://github.com/camillanapoles/llm-arena-opencli/blob/arena/d917b13b-llm-arena-opencli/docs/INTEGRATION.md)
- **Protocolo de continuidade IGC v1.0:** memória em [`.session/WAL.md`](https://github.com/camillanapoles/llm-arena-opencli/blob/arena/d917b13b-llm-arena-opencli/.session/WAL.md) (WAL append-only + FSM + CHECKPOINT `fd6ca27`)
- **Contrato único de pipeline:** `pipeline/contract.schema.json` + `pipeline/blueprint.json` (planta CNJ + cadeia TS no mesmo arquivo)

Estado das linhagens: PR #1 (d917b13b, Node/TS) e PRs #2/#5 (ed79bd77, Python/CNJ) seguem o MESMO fluxo gate-driven — `integration.yml` roda as duas suítes a cada push/PR.

Emissão rotulada [IMPLEMENT] · checkpoint `fd6ca27` · WAL: `.session/WAL.md`

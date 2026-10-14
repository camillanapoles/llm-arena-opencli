# Guardião de Projeto — continuidade automática do **escopo global**

> Solicitação do usuário (2026-10-13): *“continue em desenvolvimento por spec a fim de
> atingir objetivo de projeto completo testado válido em completude gerenciável,
> garantindo qualidade impecável de entrega em fluxo automato, com guardião de
> projeto garantindo continuidade do escopo projeto global em desenvolvimento.”*

## O que o guardião é

Um ciclo automato **limitado e auditável** que varre o escopo global do projeto e
decide/executa **UMA** próxima ação por ciclo, sempre com `motivo` explícito
(M6 — nada é pulado ou decidido em silêncio) e `comando` de retorno para fix.

**Componentes**

| Peça | Papel |
|---|---|
| `src/guardian/guardian.ts` | retrato (`scanGlobal`) + decisão (`decidir`) — puro e testado |
| `src/cli/guardiao-cli.ts` | `scan` · `next` · `run [--executar]` (dry-run por padrão) |
| `tests/guardiao.test.ts` | garantias das 8 regras de decisão + scan real + limitação do run |
| `.github/workflows/guardian.yml` | fluxo automato: schedule (dias úteis 14:00 UTC) + dispatch + push |
| `pipeline/chain-state.json` | estado da cadeia TS (`delivered`/`pending` por ISSUE) |

## O escopo global (o que ele garante em continuidade)

1. **Memória IGC v2.1** — WAL/CHECKPOINT/registry/profile (`resumeCheck` M4/D3,
   órfãos G5, profile G6).
2. **Débitos de erro** — `.session/DEBT.md` com prioridade e retorno para fix
   (prioridade **urgente/alta vence qualquer desenvolvimento novo**).
3. **Cadeia TS** — `pipeline/blueprint.json` × `pipeline/chain-state.json`
   (ISSUE-n com acceptance explícito; `cycle` executa e testa).
4. **Backlog CNJ/fábrica** — `pipeline/backlog.json` (pendentes → gate 6;
   **bloqueadas → humano**, o guardião não destrava).

## Matriz de decisão (ordem = prioridade)

| # | Condição | Ação | Prioridade |
|---|---|---|---|
| 1 | débito urgente/alta com gatilho de fix | `fix` (executa o retorno) | urgente/alta |
| 2 | memória RECON (M4/D3) | `humano` (reconciliar) | urgente |
| 3 | profile inválido (G6) | `humano` (BOOT recusado) | alta |
| 4 | item CNJ **bloqueada** | `humano` (nunca auto-destrava) | média |
| 5 | cadeia TS com ISSUE pendente | `executar-cadeia` (`cycle --id`, acceptance interno) | alta |
| 6 | backlog CNJ com pendente | `fabrica` (`gate.py issue --id --marcar`) | média |
| 7 | linhagem órfã >30d (G5) | `fix` (registrar débito/retomar) | média |
| 8 | nada pendente | `vigiar` (monitora; reporta) | baixa |

## Limites de segurança (qualidade impecável sem atalhos)

- **UMA ação por ciclo** (limitado); a ação roda com o acceptance do próprio item
  (ex.: `npm run ci` dentro do `cycle`) — falha vira débito priorizado, nunca “seguir”.
- **Nunca** mescla PR, **nunca** destrava bloqueio, **nunca** pede/usa credenciais.
- `run` sem `--executar` é dry-run; `decisão humana` sai com exit 1 e motivo.
- Toda corrida termina em **checkpoint IGC** (Art. 8): `igc(ci): run <id>
  [igc-checkpoint] [skip ci]` — sem re-trigger, WAL append-only.

## Operação

```bash
node src/cli/guardiao-cli.ts scan          # retrato do escopo global (JSON)
node src/cli/guardiao-cli.ts next          # próxima decisão (JSON com motivo)
node src/cli/guardiao-cli.ts run           # dry-run da ação
node src/cli/guardiao-cli.ts run --executar # executa UMA ação (CI/schedule)
```

Manual: `gh workflow run guardiao` (input `executar=false` só reporta).

## AUDITORIA — O QUE FALTA

- Executor de `fix` para comandos DEBT arbitrários fica **opt-in** (`--executar`
  só cobre cycle/fábrica/fix seguro) — comandos perigosos continuam humanos.
- Métricas de qualidade por ciclo (tempo de ciclo, taxa de first-pass) — evoluir
  para `pipeline/saida/guardiao-<run>.json` versionado no checkpoint.

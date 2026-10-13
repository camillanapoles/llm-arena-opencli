# CONTEXT.md — mapa de reconstrução da sessão (IGC v1.0, M3)

> Meta: a próxima sessão reconstrói o ambiente em O(bootstrap), não em
> O(adivinhação).

## Linhagem (A2 — equivalência de nomes)

| Conceito IGC | Valor nesta sessão |
| --- | --- |
| `id-sessao` | `d917b13b` |
| branch de linhagem | `arena/d917b13b-llm-arena-opencli` |
| nome IGC equivalente | `sessao/d917b13b/llm-arena-opencli` |
| worktree | `/home/user/llm-arena-opencli` (checkout único da branch) |
| remoto | `origin` = `https://github.com/camillanapoles/llm-arena-opencli.git` |

**Adaptação registrada (A2):** a plataforma Arena fixa a branch da sessão em
`arena/<id>/<repo>` e proíbe criar/empurrar outras branches — por isso a
linhagem usa o nome da Arena em vez de `sessao/<id>/<slug>`. A semântica é a
mesma: 1 sessão ⇔ 1 worktree ⇔ 1 branch; fim da sessão ≠ fim da linhagem.
Sessões futuras fora da Arena devem usar `git worktree add ../<wt> -b
sessao/<id>/<slug> <base>` (IGC W1), com base em commit verificado.

## Bootstrap do ambiente (W2)

```bash
bash .session/bootstrap.sh     # toolchain + npm install + wasm + hooks do worktree
npm run ci                     # typecheck + build:wasm + testes Node/TS/WASM
make testes                    # 6 suítes Python/CNJ (gate 3 do gates.yml)
```

Toolchain exigido: `node >= 22` (`node:sqlite`), `npm`, `python3` (stdlib),
`bash`; opcional: `gh` (gates ao vivo), `git >= 2.30` (worktreeConfig).

## Arquivos-chave

| Área | Arquivos |
| --- | --- |
| Backend/webhook | `src/server.ts` (rotas, `POST /api/events`), `src/gate/webhook.ts` (HMAC `X-Hub-Signature-256`), `src/gate/events.ts` (normalização `X-GitHub-Event`), `src/app.ts` |
| Driver/gates | `src/gate/`, `src/drivers/`, `src/core/types.ts`, `wasm/` (trigger core) |
| Pipeline/contrato | `src/pipeline/{envelope,chain,domain,gates,interop}.ts`, `pipeline/contract.schema.json`, `pipeline/blueprint.json` (cadeia `chain` + planta CNJ `gates`) |
| Cadeia de issues | `pipeline/backlog.json` (CNJ), `pipeline/backlog-cnj.json` (snapshot), GitHub issues com label `pipeline-chain` |
| Docs | `DELIVERY.md`, `docs/INTEGRATION.md`, `docs/WEBHOOK.md`, `docs/SECRETS.md`, `docs/03-pipeline-gates.md`, `BOOTSTRAP.md` |
| Continuidade (bot) | `session/` (`CONTEXT.md`, `state.json`) + `.github/workflows/continuity.yml` — handoff entre turnos; **distinto** de `.session/` (memória IGC desta sessão) |
| Kit auto-criador CNJ | `bootstrap.sh` + `tools/gerar_bootstrap.py` (32 arquivos; qualquer mudança neles exige `python3 tools/gerar_bootstrap.py` no mesmo commit) |

## Invariantes do projeto

1. **Zero deps runtime** (Node builtins; devDeps: typescript, @types/node, assemblyscript, js-yaml).
2. TypeScript **erasable-syntax only** (`.ts` em imports, sem `require()` em ESM).
3. WASM AssemblyScript **pure-compute** (zero imports, nunca `--exportRuntime`).
4. Contrato de envelope: `{id, message, addenda, status, nextIssue, exitCode 0|1|2, direction, at, continuity, debts}`; exit = `exitCode`.
5. Direções: `0`→`continue|complete` · `1`→`fix` (mesma issue) · `2`→`debt|hold`; débitos com prioridade `urgent>high>medium` e ação `fix|human`.
6. TAP: `/# fail (\d+)/` **ancorado** (`/^# fail (\d+)\s*$/m`) — nomes de teste enganam o regex solto.
7. `make testes` inclui bootstrap do kit CNJ — arquivos do kit mudaram ⇒ regenerar.

## Ambiente efêmero (A1)

- `node_modules/`, `wasm/dist/`, `data/*.db` são regeneráveis (gitignored).
- Resincronização após reset do worktree: `git fetch origin arena/d917b13b-llm-arena-opencli:refs/remotes/origin/arena/d917b13b-llm-arena-opencli && git reset --hard origin/arena/d917b13b-llm-arena-opencli` (e `npm install`).

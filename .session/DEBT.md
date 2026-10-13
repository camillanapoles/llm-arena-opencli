# DEBT.md — débitos técnicos (IGC v1.0, M5)

> Débito é cidadão de primeira classe: descrição, causa, impacto,
> gatilho de retomada. Evento `DEBT` é emissão legítima.

## D1 — Deploy público do backend + registro efetivo do webhook

- **Descrição:** o `POST /api/events` está pronto para webhook real (assinatura
  HMAC `X-Hub-Signature-256` + handshake `ping`), mas o registro efetivo do
  webhook no GitHub exige uma **URL pública de payload** (o backend roda em
  ambiente efêmero sem endpoint público).
- **Causa:** infraestrutura de deploy fora do escopo do sandbox.
- **Impacto:** baixo — o fluxo equivalente `repository_dispatch` /
  `workflow_dispatch` já exercita a mesma cadeia evento→gate→JSON, e o
  registro fica documentado (`docs/WEBHOOK.md` + `scripts/registrar-webhook.sh`).
- **Gatilho de retomada:** usuário definir host/URL do backend (ou fazer merge
  e publicar) → rodar `scripts/registrar-webhook.sh` com a URL e o secret.

## D2 — Testes de dispatch do OPENCLI_TOKEN no terminal do usuário

- **Descrição:** os 2 comandos de teste do secret (`gh api …/dispatches` e
  `gh workflow run opencli-driver.yml …`) ainda não foram confirmados fora do sandbox.
- **Causa:** token do sandbox sem `actions: write` (403 verificado).
- **Impacto:** médio — validação final do modo `dispatch` do opencli-driver.
- **Gatilho de retomada:** usuário rodar os comandos de `docs/SECRETS.md`.

## D3 — Merge do PR #1 (ação humana)

- **Descrição:** PR #1 está MERGEABLE/CLEAN com gate de teste verde; merge é
  exclusivamente do mantenedor (e encerra a sessão Arena).
- **Gatilho de retomada:** decisão do usuário.

## D4 — ISSUE-3 da cadeia (publicar arena-runtime.wasm)

- **Descrição:** próximo passo indexado após ISSUE-2 (`pipeline/blueprint.json`).
- **Gatilho de retomada:** ciclo `npm run pipeline -- cycle --id ISSUE-3` após ISSUE-2 `delivered`.

## D5 — Comentário na issue #3 (deliverable ISSUE-009) bloqueado por permissão

- **Descrição:** o comentário de registro da integração IGC/UNIFY na issue #3
  foi rejeitado pelo GitHub (403 *Resource not accessible by integration*) —
  o token do sandbox escreve em PRs/issues criadas por ele, mas não comenta
  nesta issue.
- **Causa:** permissão do token de integração do ambiente.
- **Impacto:** baixo — o conteúdo está versionado e pronto; o deliverable de
  ISSUE-009 fica pendente só do POST.
- **Gatilho de retomada:** operador rodar do seu terminal (ou workflow com
  `issues: write`):
  `gh issue comment 3 --body-file .session/emissoes/issue-3-comentario.md`

## D6 (IGC Art. 7 / D2) — registry só alcança o default branch no merge
**O que é:** `.igc-registry.yml` e `.session/` vivem na linhagem `arena/d917b13b-llm-arena-opencli`; o Art. 7 pede o registry **no default branch** (main). Até o PR #1 ser mesclado (ação do usuário), a descoberta por default branch está incompleta — a descoberta atual é via branch + esta entrada.
**Gatilho / retorno para fix (E5):** no primeiro CI verde após o merge, `igc-checkpoint` commita `igc(ci)` em main e o registry passa a valer no default branch; até lá, `scan-orphans` corre na linhagem. Se o merge gerar conflito em `.session/WAL.md`, resolver por append (M1: nunca sobrescrever entradas).
**Prioridade:** baixa · **Quando:** próxima janela de merge (decisão do usuário).

## D7 (EV-5/T8) — transporte bundle sem artefatos npm offline
**O que é:** o round-trip de transporte (T8) valida `tar → commit → bundle → clone frio → make testes` 100% offline. O equivalente TS (`npm run ci`) exige `node_modules` (não versionáveis); o fallback do perfil (§5) é bootstrap 100% Python + `make testes`, que é o que o clone frio executa.
**Gatilho / retorno para fix:** se um runtime com rede executar `npm run ci` no clone do bundle, marcar a dívida como verificada e encerrar. Aceitação do HANDOFF continua: clone frio verde na suíte offline (validada em T8).
**Prioridade:** baixa · **Quando:** quando houver runner com rede disponível para verificação extra.

## M1 — correção de âncora (registro de correção, não edição)
**O que é:** a entrada WAL#12 (contração E5) cita "WAL#10" como âncora do EMIT do PR; a entrada correta do EMIT do PR (comentário 6155983956) é **WAL#7**. A identificação de #10 como "EMIT do webhook" também estava errada: **WAL#10 é AMENDA** (retificação do contrato) — ver WAL#19. A memória é append-only: as correções valem por entradas novas (WAL#13 e WAL#19).
**Gatilho:** n/a (correção registrada) · **Prioridade:** baixa.

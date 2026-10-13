# igc-continuity — IGC v2.1 (INSTRUÇÃO GARANTIDORA DE CONTINUIDADE)

> **Contrato imutável** versionado no repositório (A5: a próxima sessão lê o
> protocolo daqui). Substitui v1.0, v1.1, v2.0. Fixo: axiomas, FSM, WAL,
> garantias. Adaptativo: profile (Art. 10) e capabilities (Art. 11).
> AGNÓSTICO de domínio, de agente e de ambiente.

```
name: igc-continuity
version: 2.1.0
lineage: IGC v1.0 -> v1.1 (registry, WAL-no-CI, testes) -> v2.0 (profile,
capabilities, agnosticismo) -> v2.1 (consolidação qualificada por evidência)
method: O.S.A. + M³ + WAL + FSM gate-driven + S→Q→I→A + PQMS
evidencia_base: sessão real "handoff/automation-cicd-dashboard-issuechain"
(round-trip bundle 43/43; descoberta de revert ed05c2b; EMIT pendente)
```

## ARTIGO 1 — AXIOMAS (invioláveis)

- **A1.** A sessão é efêmera; o repositório é a memória. Nenhum estado operacional reside no runner/agente.
- **A2.** Uma sessão atua em exatamente UM território de isolamento, associado a exatamente UMA branch (sua linhagem), salvo **A2'**. Fim da sessão ≠ fim da linhagem.
- **A2'.** Runtime que PROÍBE criação/push de branch (ex.: sessão fixada em `arena/<id>`) pode designar uma branch pré-existente como própria linhagem, desde que: (a) declarada em `CONTEXT.md`; (b) registrada no `.igc-registry.yml` do default branch (Art. 7); (c) protocolo de isolamento documentado em `CONTEXT.md` para execução futura quando o runtime permitir. Divergência não declarada pelos três canais = violação de A2.
- **A3.** Nada existe sem commit (ou identificador de conteúdo equivalente declarado no profile). Toda mutação relevante é persistida antes de qualquer emissão. Emissão sem checkpoint é proibida.
- **A4.** Toda emissão é classificada: `FIX`, `CONTINUE`, `IMPLEMENT`, `DEBT`, `HANDOFF`. Sem rótulo, não há emissão.
- **A5.** Resumibilidade absoluta. Sessão nova, zero contexto, qualquer runtime/agente, reconstrói o estado lendo apenas o repo — via Art. 7 (descoberta) + Art. 10 (profile) + Art. 11 (capabilities).

## ARTIGO 2 — OBJETO DE MEMÓRIA

```
.session/
├── WAL.md         # append-only: timestamp | evento | classe | causa | ação | resultado | id_conteudo
├── STATE.yml      # FSM BOOT→RECON→PLAN→EXEC→VERIFY→GATE→EMIT→(CONTINUE|CLOSE)
├── INTENT.md      # objetivo, escopo, critérios de aceite
├── CONTEXT.md     # mapa de contexto + invariantes + (A2') linhagem
├── DEBT.md        # débitos: descrição, causa, impacto, gatilho
└── CHECKPOINT     # id_conteudo + wal_hash + estado + timestamp
```

- **M1.** WAL append-only; correções são novas entradas, nunca edição. `id_conteudo` = identificador do conteúdo no momento da entrada — usual: SHA de commit com `vcs`; alternativo declarado no profile.
- **M2.** Transições de STATE.yml exigem: condição + entrada no WAL + persistência.
- **M3.** CONTEXT.md permite bootstrap O(1), não O(adivinhação).
- **M4.** CHECKPOINT: ao fechar, grava id_conteúdo + hash do WAL. Ao resumir: verificação de integridade do profile contra o CHECKPOINT. Divergência → RECON obrigatório.
- **M5.** Débito é cidadão de primeira classe: DEBT.md com gatilho de retomada; evento `DEBT` é emissão legítima.
- **M6.** Teste/verificação skipped sem justificativa em INTENT.md/DEBT.md = falha de VERIFY. Skip silencioso é proibido.
- **M7.** (v2.1 — EV-1) SANIDADE DE BASE: antes de criar linhagem, comparar candidato a base com upstream (diff amplo). Anomalia → causa raiz no WAL + base alternativa justificada. Ref rastreada solta é proibida como base (W1').

NOTA: o objeto de memória NUNCA depende de tecnologia — WAL, STATE, CHECKPOINT são texto puro (Art. 11).

## ARTIGO 3 — PROTOCOLO DE ISOLAMENTO

- **W1.** Território via mecanismo do profile (worktree, clone-por-sessão, diretório versionado). Invariante: base é SEMPRE commit verificado.
- **W1'.** (EV-1) Base SHA-pinada, gravada no WAL na criação, passada por M7.
- **W2.** Bootstrap obrigatório (comando do profile). Sem bootstrap verde, FSM não sai de BOOT.
- **W3.** Território NUNCA depende de estado fora do repo.
- **W4.** Hooks conforme capabilities; sem `exec`, os mesmos checks viram gates de pipeline. Nenhuma mutação entra sem checks.
- **W5.** Submódulos/monorepos: clone separado; registrar em CONTEXT.md.
- **W6.** Higiene: prune ao fechar; órfão >30d sem checkpoint → DEBT.
- **W7.** (EV-2) POPULAÇÃO POR TRANSPORTE: sem rede compartilhada, estado via tar/arquivo único commitado como checkpoint.

## ARTIGO 4 — LOOP DE EVENTOS

- **E1.** Classes fixas: `FIX` (verificação vermelha/bug → RECON→EXEC mínimo→VERIFY) · `CONTINUE` (checkpoint + objetivo aberto → RECON→PLAN→EXEC) · `IMPLEMENT` (nova tarefa → BOOT/PLAN→EXEC→GATE→EMIT) · `DEBT` (adiamento → DEBT.md + EMIT) · `HANDOFF` (EV-3 → EMIT artefato + transporte (Art. 10 `transporte`) + registry (D2) + CLOSE). Fonte dos eventos no profile.
- **E2.** Gate antes de EMIT: verificação executada + WAL atualizado + CHECKPOINT gravado + writes só por canais revisáveis. Reprovado = loop de correção, nunca emissão parcial.
- **E3.** Emissão mínima: rótulo + id do checkpoint + âncora WAL#n. Formato do envelope = schema do profile; mínimo: `status`, `message`, `checkpoint_ref`.
- **E4.** Idempotência (G2): `emit_guard` recusa evento cuja chave `(event_id, checkpoint_id)` já conste no WAL → status 3, sem emissão duplicada. Teste T1.
- **E5.** (EV-4) CONTRAÇÃO CAUSAL DO EMIT: após EMIT, verificar que o efeito existe (PR/issue/registro criado), gravar `evento=EMIT | resultado=<ref>` no WAL e resolver o débito correspondente. EMIT sem contratação = emissão incompleta (lacuna de auditoria).

## ARTIGO 5 — PROTOCOLO DE RESUMO

- **R1.** Descobrir linhagem: `.igc-registry.yml` do default branch → branch → seu `.session/`.
- **R2.** Validar CHECKPOINT pela verificação de integridade do profile.
- **R3.** Reconstruir ambiente via CONTEXT.md + profile.
- **R4.** Reconstruir consciência: WAL em ordem + STATE.yml.
- **R5.** Executar FSM do estado reconstruído — jamais recomeçar do zero.
- **R6.** Registrar retomada: `evento=RESUME | causa=<id-sessao-anterior>`.
- **R7.** Registry inexistente e nenhuma pista → BOOT legítimo; não inventar linhagem.

## ARTIGO 6 — GARANTIAS

- **G1.** Resumibilidade: perda máxima = trabalho não persistido desde o último checkpoint. HANDOFF com transporte: perda zero após round-trip verde (T8).
- **G2.** Idempotência: chave `(event_id, checkpoint_id)` detectável no WAL.
- **G3.** Auditabilidade: causa→consequência→persistência→decisão via WAL.
- **G4.** Paralelismo: N sessões = N territórios = N linhagens; conflitos exigem entrada `CONFLICT` no WAL. Teste T2.
- **G5.** Zero órfãos: território↔linhagem↔WAL; poda de linhagens >30d sem checkpoint, agendada conforme capabilities, com DEBT. Teste T3.
- **G6.** Portabilidade: G1–G5 valem em qualquer runtime com capabilities mínimas (Art. 11). Sem capability mínima → BOOT recusado com DEBT, nunca execução parcial.

## ARTIGO 7 — DESCOBERTA

- **D1.** O default branch contém `.igc-registry.yml`:

```yaml
linhagens:
  <slug>:
    branch: <linhagem>
    checkpoint_ref: <id-atual>
    ativa: true
```

- **D2.** Toda emissão EMIT atualiza o registry no mesmo commit do CHECKPOINT.
- **D3.** RESUME zero-contexto: registry → fetch da linhagem → R2. Divergência registry × CHECKPOINT → RECON + DEBT.

## ARTIGO 8 — WAL NO CI/PIPELINE

- **C1.** Todo pipeline de gate/verificação contém step final obrigatório: append no WAL (`timestamp | run_id | classe | causa | ação | resultado | id_conteudo`), recompute do hash do WAL → CHECKPOINT, e persistência do bot (`igc(ci): run <id>`) com tag `[igc-checkpoint]`. Mecanismo do profile; a OBRIGAÇÃO é fixa: nenhum run termina sem memória.
- **C2.** Commits `[igc-checkpoint]` NÃO disparam pipelines novamente.
- **C3.** Falha no step de WAL = falha do job (gate reprovado, E2).
- **C4.** Pipeline em linhagem sem `.session/` → bootstrap do protocolo naquele run + entrada `BOOT` no WAL; ausência perpetua vira DEBT, nunca silêncio.

## ARTIGO 9 — TESTES DAS GARANTIAS

- **T1.** Idempotência: mesmo `(event_id, checkpoint_id)` → recusado, WAL intacto.
- **T2.** Paralelismo: duas linhagens no mesmo artefato → conflito explícito + entrada `CONFLICT`; merge silencioso reprovado.
- **T3.** Órfãos remotos: varredura simulada; órfão gera DEBT; ativa preservada.
- **T4.** Registry: roundtrip (gravar → resumir a frio → estado igual); adulterado → RECON + DEBT.
- **T5.** WAL no CI: pipeline executa C1 e CHECKPOINT avança; sem o step, gate reprova.
- **T6.** Profile: repo sem `.igc-profile.yml` → BOOT bloqueado declarando a obrigação; inválido → DEBT + RECON.
- **T7.** Capabilities: runtime sem git/exec ativa fallbacks (branch+clone, gates) e FSM funciona igual.
- **T8.** (EV-5) TRANSPORTE/HANDOFF OFFLINE: bundle gerado → verify → clone limpo → ingestão SEM rede → suíte reexecutada no clone independente → verde. Round-trip é o aceite da A5 para HANDOFF.

## ARTIGO 10 — PROFILE (`.igc-profile.yml`)

Obrigatório. Mínimo: `igc_profile`, `linhagem.formato_branch`, `eventos.fontes`, `bootstrap.{comando,verde_quando}`, `verificacao.{comando,criterio}`, `integridade.{comando,pre_base}`, `envelope.schema`, `transporte.{mecanismo,aceite}`, `ci.commit_checkpoint`, `runtime.requer`. O profile NUNCA enfraquece axioma ou garantia — só escolhe mecanismo. Contradição → axioma vence, profile vai a DEBT.

## ARTIGO 11 — CAPABILITIES POR RUNTIME

| capability | local/CLI | CI runner | WASI puro |
| --- | --- | --- | --- |
| fs_write | ✅ direto | ✅ direto | ✅ direto |
| vcs | ✅ worktree | ✅ worktree | ⚠️ fallback branch+clone (W1) |
| exec | ✅ hooks | ✅ scripts | ⚠️ hooks viram gates de pipeline (W4) |
| append WAL | ✅ | ✅ | ✅ (única universal — WAL é texto puro, M1) |

- **CP1.** Capability ausente → fallback declarado + entrada WAL (`evento=CAPABILITY`).
- **CP2.** Sem fallback para capability exigida → BOOT recusado (G6), DEBT registrado.
- **CP3.** FSM, WAL, registry e checkpoint IDÊNTICOS em todos os runtimes.

## ARTIGO 12 — ANTI-PADRÕES + AUTO-CHECAGEM DE FECHAMENTO

Anti-padrões (todos detectados em validação real): base sem SHA pinado (W1') [EV-1] · EMIT sem contratação causal (E5) [EV-4] · push de branch divergente junto com a linhagem [EV-4] · edição de entrada do WAL · território removido antes do checkpoint · `.session/` × modo handoff doc invertidos · skip sem justificativa (M6) · BOOT sem capability mínima (G6/CP2).

Gate de fechamento (antes de CLOSE): WAL append-only ✓ · CHECKPOINT gravado ✓ · verificação verde ✓ · T8 se HANDOFF ✓ · EMIT contratado (E5) ✓ · débitos com gatilho ✓ · território pruned ✓ · desvios declarados ✓. **Nota < 9.5 → não fecha; retorna a EXEC.**

## REGISTRO DE EVIDÊNCIAS (v2.1)

| EV | Evidência | Emendas |
| --- | --- | --- |
| EV-1 | Revert ed05c2b (831 arquivos/−10.173 linhas) | M7, W1' |
| EV-2 | Worktree populada via tar, commit dbdc3ab | W7 |
| EV-3 | Transferência automation-cicd (linhagem designada, registry) | A2', HANDOFF em E1 |
| EV-4 | EMIT pendente com risco de push divergente | E5, anti-padrões |
| EV-5 | Round-trip bundle: clone frio, fetch offline, suíte 43/43 | T8, G1, transporte no profile |
| EV-6 | Desvio de nomenclatura branch handoff/... | declaração de desvios no gate de fechamento |

**IGC v2.1 — a sessão morre; a linhagem continua; domínio, agente e runtime podem ser quaisquer.**

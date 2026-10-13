# WAL.md — append-only (IGC v1.0, M1)

> Formato: `timestamp | evento | classe | causa | ação | resultado | sha_commit`
> Nunca se edita ou apaga entrada — correções são novas entradas.
> `sha_commit` = commit observado/causador da entrada (base verificada no momento).

2026-10-13T21:40:00Z | BOOT | IMPLEMENT | retomada do trabalho: usuário pediu ISSUE-2 "porém siga as instruções de continuidade (IGC v1.0)" | montar objeto .session/ e cumprir protocolo | objeto .session/ criado | 3d9b774
2026-10-13T21:41:00Z | RECON | FIX | M4: worktree local divergiu da linhagem (HEAD 3d9b774 × remoto 9acbc18 — reset do ambiente) | git fetch + reset --hard origin/arena/d917b13b-llm-arena-opencli + npm install | linhagem restaurada em 9acbc18, tree limpa | 9acbc18
2026-10-13T21:42:00Z | PLAN | IMPLEMENT | escopo IGC v1.0 + ISSUE-2 (issue #4): assinatura X-Hub-Signature-256, ping, docs/registro, equivalência repository_dispatch | INTENT.md + CONTEXT.md + STATE.yml | plano aprovado (critérios A1–A6) | 9acbc18
2026-10-13T22:05:00Z | EXEC | IMPLEMENT | ISSUE-2 (issue #4) sob IGC v1.0: webhook real conectado ao POST /api/events | src/gate/webhook.ts (HMAC-SHA256 X-Hub-Signature-256, timing-safe) + rawBody/401/ping no server + docs/WEBHOOK.md + scripts/registrar-webhook.sh + fix da fábrica (nunca emite issue sem entregavel) + ISSUE-009 curada | código pronto; débito da fábrica (gate 3 reprovado) quitado no mesmo fluxo | fd6ca27
2026-10-13T22:08:00Z | VERIFY | IMPLEMENT | critérios A1–A4 do INTENT | npm run ci (108/108) + make testes (236 verificações, EXIT 0) + bootstrap .session/bootstrap.sh (W2) verde | verificado — gate de teste satisfeito | fd6ca27
2026-10-13T22:10:00Z | GATE | CONTINUE | ciclo determinístico da cadeia indexada (acceptance: npm run ci) | node src/cli/pipeline-cli.ts cycle --id ISSUE-2 | SUCESSO COMPLETO → status delivered · nextIssue ISSUE-3 · direction continue · debts [] | fd6ca27
2026-10-13T22:12:00Z | EMIT | IMPLEMENT | E2: gate aprovado (verificação verde + WAL + CHECKPOINT) antes de emitir | commit fd6ca27 (trabalho) + commit de fechamento .session/ + push + comentários rotulados [IMPLEMENT] no PR #1 e na issue #3 (E3: rótulo + SHA + âncora WAL) | emissão preparada com cadeia auditável | fd6ca27

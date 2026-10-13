# WAL.md — append-only (IGC v1.0, M1)

> Formato: `timestamp | evento | classe | causa | ação | resultado | sha_commit`
> Nunca se edita ou apaga entrada — correções são novas entradas.
> `sha_commit` = commit observado/causador da entrada (base verificada no momento).

2026-10-13T21:40:00Z | BOOT | IMPLEMENT | retomada do trabalho: usuário pediu ISSUE-2 "porém siga as instruções de continuidade (IGC v1.0)" | montar objeto .session/ e cumprir protocolo | objeto .session/ criado | 3d9b774
2026-10-13T21:41:00Z | RECON | FIX | M4: worktree local divergiu da linhagem (HEAD 3d9b774 × remoto 9acbc18 — reset do ambiente) | git fetch + reset --hard origin/arena/d917b13b-llm-arena-opencli + npm install | linhagem restaurada em 9acbc18, tree limpa | 9acbc18
2026-10-13T21:42:00Z | PLAN | IMPLEMENT | escopo IGC v1.0 + ISSUE-2 (issue #4): assinatura X-Hub-Signature-256, ping, docs/registro, equivalência repository_dispatch | INTENT.md + CONTEXT.md + STATE.yml | plano aprovado (critérios A1–A6) | 9acbc18

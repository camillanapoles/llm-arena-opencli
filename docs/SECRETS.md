# 🔐 Guia: como criar o `OPENCLI_TOKEN`

> **Resposta curta:** existem, sim, *actions* de marketplace para criar secrets
> a partir de workflows — **mas todas exigem um token inicial com permissão
> `secrets: write`** (o `GITHUB_TOKEN` do workflow **não** cria secrets; dá
> 403 "Resource not accessible by integration" — verificado). O **valor** do
> `OPENCLI_TOKEN` é um PAT que **você** gera em ~2 minutos. Depois disso, a
> configuração leva **30 segundos** por qualquer das 3 formas abaixo.

---

## 1. O que é o `OPENCLI_TOKEN` e quando ele é necessário

| Fluxo | Precisa do `OPENCLI_TOKEN`? |
| --- | --- |
| `opencli-driver.yml` modo **`runtime`** (executa o OpenCLI dentro do runner) | **NÃO** — funciona sem nenhum secret |
| `opencli-driver.yml` modo **`dispatch`** para `camillanapoles/OpenCLI` (seu fork) | **SIM** — `repository_dispatch` em outro repo exige token com write |
| `opencli-driver.yml` modo **`dispatch`** sem secret (fallback automático) | NÃO — o workflow cai em **self-dispatch** neste repo com `GITHUB_TOKEN` |
| `continuity.yml`, `gate-driver.yml`, `blueprint.yml`, `ci.yml` | **NÃO** — usam o `GITHUB_TOKEN` embutido |

**Fato verificado na auditoria:** o upstream `jackwener/OpenCLI` é **read-only**
para você (só `pull`). `repository_dispatch` lá sempre falharia. O alvo correto
é o **seu fork [`camillanapoles/OpenCLI`](https://github.com/camillanapoles/OpenCLI)**
(admin confirmado) — que é o default do workflow.

## 2. Criar o token (PAT) — ~2 minutos

### Opção A — Fine-grained PAT (RECOMENDADA, menor escopo)

1. Abra **[GitHub → Settings → Developer settings → Personal access tokens → Fine-grained tokens](https://github.com/settings/personal-access-tokens/new)**
2. **Token name:** `opencli-driver` · **Expiration:** a sua escolha (ex.: 90 days)
3. **Resource owner:** `camillanapoles`
4. **Repository access:** *Only select repositories* → **`camillanapoles/OpenCLI`**
5. **Repository permissions:** apenas **Contents: Read and write**
   (é o que o `repository_dispatch` exige)
6. **Generate token** → **copie o valor** (só aparece uma vez!)

### Opção B — Classic PAT (mais amplo)

1. **[Settings → Developer settings → Personal access tokens → Tokens (classic)](https://github.com/settings/tokens/new)**
2. Marque apenas **`public_repo`** (o fork é público) ou **`repo`**
3. Generate → copie o valor

## 3. Configurar o secret — 3 formas (escolha uma)

### Forma 1 — Interface do GitHub (mais simples, 30 segundos)

1. Abra **[camillanapoles/llm-arena-opencli → Settings → Secrets and variables → Actions](https://github.com/camillanapoles/llm-arena-opencli/settings/secrets/actions)**
2. **New repository secret** · Name: `OPENCLI_TOKEN` · Secret: (cole o valor)
3. **Add secret** ✅

### Forma 2 — `gh secret set` no seu terminal (recomendada p/ automação)

```sh
gh secret set OPENCLI_TOKEN          # prompt oculto — cole o valor
# ou, sem expor no histórico:
gh secret set OPENCLI_TOKEN < token.txt   # valor vindo de arquivo
```

Verificação:

```sh
gh secret list          # deve listar OPENCLI_TOKEN
```

### Forma 3 — Actions de marketplace (verificadas — para uso *dentro* de CI)

Existem actions que criam/atualizais secrets a partir de workflows:

| Action | Uso |
| --- | --- |
| [`actions/secrets-action@v1`](https://github.com/marketplace/actions/secrets-action) | `with: github-token, owner, repo, secret-name, secret-value` |
| [`jon-grey/github-actions-secrets-creator@v1`](https://github.com/marketplace/actions/github-actions-secrets-creator) | `with: name, value, pa_token` |
| [`kornicameister/gh-secrets-action`](https://github.com/marketplace/actions/gh-secrets) | `with: token, secrets: \|` |
| [`actions/github-script`](https://github.com/marketplace/actions/github-script) + API `createOrUpdateRepoSecret` | via API REST com criptografia NaCl |

⚠️ **Todas exigem um token bootstrap com permissão `secrets: write`** (PAT
fine-grained com *Secrets: Read and write*, ou classic `repo`). Elas servem
para **rotacionar/gerar** secrets em CI — **não** substituem a criação inicial
do valor do `OPENCLI_TOKEN`. E, como este repo é **público**, nunca passe o
valor de um token como `input` de `workflow_dispatch` (inputs ficam no
metadado do run, visíveis).

## 4. Testar (1 minuto)

```sh
# dispatch para o fork com OPENCLI_TOKEN:
gh workflow run opencli-driver.yml -f mode=dispatch -f command=ping \
  -f target_repo=camillanapoles/OpenCLI

# ou pelo painel: Actions → opencli-driver → Run workflow
gh run watch
```

- **Com o secret:** o job publica envelope `{"status":"dispatched","exitCode":0}`.
- **Sem o secret:** o workflow faz fallback e publica envelope
  `{"status":"missing-secret","exitCode":2}` + instruções (o fluxo core segue
  funcionando em modo `runtime`/self-dispatch).

## 5. Checklist da auditoria

- [ ] PAT criado (fine-grained, só `camillanapoles/OpenCLI`, Contents: write)
- [ ] `gh secret set OPENCLI_TOKEN` (ou via Settings UI)
- [ ] `gh secret list` mostra `OPENCLI_TOKEN`
- [ ] `gh workflow run opencli-driver.yml -f mode=dispatch` verde

# Atalhos para o kit DataJud (API Pública do CNJ)
TRIBUNAL ?= tjpe
SAIDA    ?= saida
LIMITE   ?= 1000
# processo de exemplo (DV válido) usado por `make consultar`
NUMERO   ?= 0001234-43.2024.8.17.2001

.PHONY: ajuda chave chave-publica consultar contar processo relatorio paginar testes limpar \
        bootstrap regenerar-bootstrap verificar \
        gates gate-issues gate-cicd gate-testes gate-issue gate-situacao blueprint testes-pipeline

ajuda: ## mostra o manual do script
	@bash scripts/datajud.sh ajuda

chave: ## imprime a chave pública vigente publicada na wiki do CNJ
	@bash scripts/datajud.sh chave

chave-publica: ## idem, usando o main.py (Python)
	@python3 main.py --chave-publica

consultar: ## relatório de UM processo: make consultar NUMERO=0001234-43.2024.8.17.2001
	@python3 main.py "$(NUMERO)" --todos

contar: ## conta os processos do tribunal informado (TRIBUNAL=tjpe)
	@bash scripts/datajud.sh contar --tribunal $(TRIBUNAL)

processo: ## consulta um processo: make processo NUMERO=0001234-56.2024.8.17.2001
	@bash scripts/datajud.sh processo "$(NUMERO)" --tribunal $(TRIBUNAL)

relatorio: ## gera o relatório em markdown/csv (SAIDA=saida)
	@bash scripts/datajud.sh relatorio --tribunal $(TRIBUNAL) --saida $(SAIDA)

paginar: ## baixa processos em JSONL (LIMITE=1000)
	@bash scripts/datajud.sh paginar --tribunal $(TRIBUNAL) --limite $(LIMITE) --saida processos-$(TRIBUNAL).jsonl

testes: ## roda as suítes offline (conformidade + main.py + datajud.sh + pipeline + bootstrap)
	@python3 tests/testar_conformidade.py
	@python3 tests/testar_main.py
	@bash tests/rodar-testes.sh
	@python3 tests/testar_pipeline.py
	@bash tests/testar_bootstrap.sh

testes-pipeline: ## roda só a suíte do pipeline de gates (offline)
	@python3 tests/testar_pipeline.py

gates: ## veredito de continuidade (0=sem pendências, 1=continuidade, 2=humano)
	@python3 pipeline/gate.py continuidade ; true

gate-issues: ## gate 1 — existem issues abertas?
	@python3 pipeline/gate.py issues ; true

gate-cicd: ## gate 2 — há execução de CI/CD com erro?
	@python3 pipeline/gate.py cicd ; true

gate-testes: ## gate 3 — testes presentes e verdes?
	@python3 pipeline/gate.py testes ; true

gate-issue: ## executa a próxima issue do backlog (ISSUE=ISSUE-00N, MARCAR=--marcar)
	@python3 pipeline/gate.py issue $$( [ -n "$(ISSUE)" ] && echo "--id $(ISSUE)" ) $(MARCAR) ; true

gate-situacao: ## histórico do pipeline (últimos resultados gravados)
	@python3 pipeline/gate.py situacao ; true

blueprint: ## valida a planta BPMN do pipeline (pipeline/blueprint.json)
	@python3 pipeline/gate.py blueprint ; true

bootstrap: ## cria o projeto completo do zero (DIR=./projeto-datajud)
	@bash bootstrap.sh --destino "$${DIR:-./projeto-datajud}"

regenerar-bootstrap: ## regera o bootstrap.sh a partir dos arquivos atuais
	@python3 tools/gerar_bootstrap.py

verificar: ## confere hashes e permissões do projeto atual (DIR=.)
	@bash bootstrap.sh --destino "$${DIR:-.}" --verificar

limpar: ## remove artefatos gerados
	rm -rf $(SAIDA) processos-*.jsonl

# Atalhos para o kit DataJud (API Pública do CNJ)
TRIBUNAL ?= tjpe
SAIDA    ?= saida
LIMITE   ?= 1000
# processo de exemplo (DV válido) usado por `make consultar`
NUMERO   ?= 0001234-43.2024.8.17.2001

.PHONY: ajuda chave chave-publica consultar contar processo relatorio paginar testes limpar \
        bootstrap regenerar-bootstrap verificar

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

testes: ## roda as suítes offline (conformidade + main.py + datajud.sh + bootstrap)
	@python3 tests/testar_conformidade.py
	@python3 tests/testar_main.py
	@bash tests/rodar-testes.sh
	@bash tests/testar_bootstrap.sh

bootstrap: ## cria o projeto completo do zero (DIR=./projeto-datajud)
	@bash bootstrap.sh --destino "$${DIR:-./projeto-datajud}"

regenerar-bootstrap: ## regera o bootstrap.sh a partir dos arquivos atuais
	@python3 tools/gerar_bootstrap.py

verificar: ## confere hashes e permissões do projeto atual (DIR=.)
	@bash bootstrap.sh --destino "$${DIR:-.}" --verificar

limpar: ## remove artefatos gerados
	rm -rf $(SAIDA) processos-*.jsonl

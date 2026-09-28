.DEFAULT_GOAL := help
SHELL := /bin/bash

COMPOSE  ?= docker compose
STAMP    := $(shell date +%Y-%m-%dT%H%M%S)
BACKUP   ?= backup-$(STAMP).sql.gz

.PHONY: help
help: ## Show available targets
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z_-]+:.*## / {printf "  \033[36m%-12s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: secret
secret: ## Generate a SECRET_KEY_BASE (paste into .env)
	@openssl rand -base64 48

.PHONY: up
up: ## Start the stack in the background
	$(COMPOSE) up -d

.PHONY: down
down: ## Stop the stack (data volume preserved)
	$(COMPOSE) down

.PHONY: destroy
destroy: ## Stop the stack AND delete the database volume (irreversible)
	$(COMPOSE) down -v

.PHONY: logs
logs: ## Tail logs from all services
	$(COMPOSE) logs -f --tail=200

.PHONY: ps
ps: ## Show service status
	$(COMPOSE) ps

.PHONY: pull
pull: ## Pull the latest image
	$(COMPOSE) pull

.PHONY: upgrade
upgrade: ## Pull the latest image and restart (migrations run automatically)
	$(COMPOSE) pull
	$(COMPOSE) up -d

.PHONY: backup
backup: ## Dump the database to backup-<timestamp>.sql.gz
	$(COMPOSE) exec -T db pg_dump -U postgres estimate | gzip > $(BACKUP)
	@echo "wrote $(BACKUP)"

.PHONY: restore
restore: ## Restore a dump: make restore FILE=backup-YYYY....sql.gz
	@test -n "$(FILE)" || (echo "usage: make restore FILE=backup-....sql.gz" && exit 1)
	gunzip -c $(FILE) | $(COMPOSE) exec -T db psql -U postgres estimate

.PHONY: shell
shell: ## Attach an IEx remote shell to the running app
	$(COMPOSE) exec app /app/bin/estimate remote

.PHONY: psql
psql: ## Open a psql session as postgres on the estimate database
	$(COMPOSE) exec db psql -U postgres estimate

SHELL := /usr/bin/env bash
.DEFAULT_GOAL := help

.PHONY: help
help: ## List available targets
	@awk 'BEGIN {FS = ":.*## "} /^[a-zA-Z0-9_-]+:.*## / {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}' $(MAKEFILE_LIST)

.PHONY: workspace
workspace: ## Clone every missing VeriTrace repository next to this one
	scripts/workspace.sh clone

.PHONY: status
status: ## Show branch, pending changes, and upstream divergence of every repository
	scripts/workspace.sh status

.PHONY: check-docs
check-docs: ## Check Markdown links and anchors in this repository
	python3 scripts/check-docs.py

.PHONY: check-workspace
check-workspace: ## Check docs links across all repositories and shared Go platform drift
	python3 scripts/check-docs.py --workspace
	scripts/check-platform-drift.sh

.PHONY: check-drift
check-drift: ## Report differences in shared Go platform packages across service repositories
	scripts/check-platform-drift.sh

.PHONY: github-settings
github-settings: ## Show the repository settings that scripts/github-settings.sh --apply would set
	scripts/github-settings.sh

.PHONY: lint
lint: check-docs ## Lint scripts and documentation
	shellcheck scripts/*.sh

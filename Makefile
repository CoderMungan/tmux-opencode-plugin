.PHONY: validate smoke
validate:
	@bash -n scripts/*.sh
	@tmux source-file ./opencode.tmux

smoke: validate
	@./scripts/opencode-list.sh >/dev/null
	@./scripts/opencode-status.sh >/dev/null

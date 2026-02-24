PREFIX ?= /usr/local
BINDIR ?= $(PREFIX)/bin
LIBDIR ?= $(PREFIX)/lib/git-sync-all

.PHONY: install uninstall test lint format format-fix check help

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-15s\033[0m %s\n", $$1, $$2}'

install: ## Install to $(PREFIX) (default: /usr/local)
	@echo "Installing git-sync-all to $(BINDIR)..."
	install -d $(DESTDIR)$(BINDIR)
	install -d $(DESTDIR)$(LIBDIR)
	install -m 755 bin/git-sync-all $(DESTDIR)$(BINDIR)/git-sync-all
	install -m 644 lib/*.sh $(DESTDIR)$(LIBDIR)/
	@sed -i 's|^readonly GSA_LIB_DIR=.*|readonly GSA_LIB_DIR="$(LIBDIR)"|' \
		$(DESTDIR)$(BINDIR)/git-sync-all
	@echo "Installed successfully. Run: git-sync-all --help"

uninstall: ## Remove installation
	rm -f $(DESTDIR)$(BINDIR)/git-sync-all
	rm -rf $(DESTDIR)$(LIBDIR)
	@echo "Uninstalled git-sync-all"

test: ## Run all tests
	@bash tests/run-tests.sh

lint: ## Run ShellCheck on all scripts
	@shellcheck bin/git-sync-all lib/*.sh
	@echo "ShellCheck: all clean"

format: ## Check formatting with shfmt
	@shfmt -d -i 4 -ci -bn bin/git-sync-all lib/*.sh
	@echo "shfmt: all clean"

format-fix: ## Apply shfmt formatting
	shfmt -w -i 4 -ci -bn bin/git-sync-all lib/*.sh

check: lint format test ## Run all checks (lint + format + test)

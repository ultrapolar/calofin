# calofin - one entry point per job.  Everything is stdlib Python; make
# is a convenience wrapper, so every target body is one command you can
# also paste by hand (Windows without make: run the python3 lines).

PY ?= python3

.PHONY: all check verify lint test test-shared parity fast help

all: check test

help:
	@echo "make check        tiers in step + generated tiers current + static checks"
	@echo "make verify       just the generated-file checks (mirror/releases/bundle/palette)"
	@echo "make lint         check_lisp + check_scope over every .lsp, check_vb over the palette"
	@echo "make test         full suite, standalone tier (lisp/)"
	@echo "make test-shared  full suite, grouped tier (shared/)"
	@echo "make parity       full suite at BOTH tiers - the drift check"
	@echo "make fast         quick loop: skips the slowest files, lisp/ tier"

check:
	$(PY) tools/check_standards.py
	$(PY) tools/check_lisp.py
	$(PY) tools/check_scope.py
	$(PY) tools/check_vb.py

verify:
	$(PY) tools/mirror_shared.py --check
	$(PY) tools/release_lisp.py --check
	$(PY) tools/build_shared_bundle.py --check
	$(PY) tools/gen_ui_data.py --check

lint:
	$(PY) tools/check_lisp.py
	$(PY) tools/check_scope.py
	$(PY) tools/check_vb.py

test:
	$(PY) tools/run_tests.py

test-shared:
	$(PY) tools/run_tests.py --tier shared

parity:
	$(PY) tools/run_tests.py --tier both

fast:
	$(PY) tools/run_tests.py --fast

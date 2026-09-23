# calofin - one entry point per job.  Everything is stdlib Python; make
# is a convenience wrapper, so every target body is one command you can
# also paste by hand (Windows without make: run the python3 lines).

PY ?= python3

.PHONY: all check verify lint test test-shared parity fast package help

all: check test

help:
	@echo "make check        tiers in step + generated tiers current + static checks"
	@echo "                  (including: every command reports its failures, every"
	@echo "                  error handler reaches its end in its error mode, what a"
	@echo "                  run borrows is given back on every way out, no write is"
	@echo "                  counted done unread, no answer is handed back unasked"
	@echo "                  that the prompt would refuse, a miss is told from Enter,"
	@echo "                  drawing text is DIMZIN-proof, both builds read the same"
	@echo "                  settings, the drafter gets their object snaps back, and"
	@echo "                  every generated dialog fits the screen)"
	@echo "make verify       just the generated-file checks (mirror/releases/bundle/palette/ribbon icons)"
	@echo "make lint         check_lisp + check_scope over every .lsp, check_vb over the palette"
	@echo "make test         full suite, standalone tier (lisp/)"
	@echo "make test-shared  full suite, grouped tier (shared/)"
	@echo "make parity       full suite at BOTH tiers - the drift check"
	@echo "make fast         quick loop: skips the slowest files, lisp/ tier"
	@echo "make package      the installable bundle + zip, into dist/"

check:
	$(PY) tools/check_standards.py
	$(PY) tools/check_lisp.py
	$(PY) tools/check_scope.py
	$(PY) tools/check_back.py
	$(PY) tools/check_lazdiag.py
	$(PY) tools/check_handlers.py
	$(PY) tools/check_leaks.py
	$(PY) tools/check_writes.py
	$(PY) tools/check_offered.py
	$(PY) tools/check_input.py
	$(PY) tools/check_values.py
	$(PY) tools/check_tier_parity.py
	$(PY) tools/check_osnap.py
	$(PY) tools/check_color.py
	$(PY) tools/check_perf.py
	$(PY) tools/check_vb.py
	$(PY) tools/check_dcl.py

verify:
	$(PY) tools/mirror_shared.py --check
	$(PY) tools/release_lisp.py --check
	$(PY) tools/build_shared_bundle.py --check
	$(PY) tools/gen_ui_data.py --check
	$(PY) tools/gen_ui_charts.py --check
	$(PY) tools/gen_knobs.py --check
	$(PY) tools/gen_ribbon_icons.py --check
	$(PY) tools/gen_agents_md.py --check

lint:
	$(PY) tools/check_lisp.py
	$(PY) tools/check_scope.py
	$(PY) tools/check_back.py
	$(PY) tools/check_vb.py

test:
	$(PY) tools/run_tests.py

test-shared:
	$(PY) tools/run_tests.py --tier shared

parity:
	$(PY) tools/run_tests.py --tier both

fast:
	$(PY) tools/run_tests.py --fast

# The one target that produces something a drafter can install.  Not part
# of `all`: it writes to dist/ and the checks above read the tree, so a
# packaging run has nothing to say about whether the tree is correct.
package:
	$(PY) tools/package.py

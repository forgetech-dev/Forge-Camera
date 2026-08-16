# AI Photographer
#
# Portable make syntax only: macOS ships GNU Make 3.81, so no $(file ...),
# no .ONESHELL, no ::= assignments.
#
# `build` and `test` must stay hardware-free forever: no camera, no API key,
# no network. That is the contributor promise.

.PHONY: help build test check lint format clean skills release

help:
	@echo "AI Photographer"
	@echo ""
	@echo "  make build    Build all targets (no hardware, no signing, no simulator)"
	@echo "  make test     Run unit, integration, and replay tests"
	@echo "  make check    format --lint + lint + build + test (the pre-push gate)"
	@echo "  make skills   Verify the shared agent skill setup"
	@echo "  make lint     Run SwiftLint if installed"
	@echo "  make format   Run SwiftFormat if installed"
	@echo "  make clean    Remove build artifacts"
	@echo ""
	@echo "Hardware and external-service tests are excluded from 'make test'."

build:
	swift build

test:
	swift test

release:
	swift build -c release

# The pre-push gate. Anything that fails here fails in CI.
check: format-check lint build test skills boundaries
	@echo ""
	@echo "check: all gates passed"

skills:
	@./.agents/verify-skills.sh

# The core domain must import Foundation only, and vendor names must stay inside
# vendor modules. Enforced here rather than left to code review.
boundaries:
	@./Tools/check-boundaries.sh

# Formatting and linting are optional locally and required in CI. A contributor
# without the tools installed can still build and test.
format:
	@if command -v swiftformat >/dev/null 2>&1; then \
		swiftformat . ; \
	else \
		echo "swiftformat not installed; skipping (brew install swiftformat)"; \
	fi

format-check:
	@if command -v swiftformat >/dev/null 2>&1; then \
		swiftformat --lint . ; \
	else \
		echo "swiftformat not installed; skipping (brew install swiftformat)"; \
	fi

# --strict matches CI exactly. Using --quiet here instead would let warnings pass
# locally and fail on push, which defeats the point of a local gate.
lint:
	@if command -v swiftlint >/dev/null 2>&1; then \
		swiftlint --strict --quiet ; \
	else \
		echo "swiftlint not installed; skipping (brew install swiftlint)"; \
	fi

clean:
	swift package clean
	rm -rf .build

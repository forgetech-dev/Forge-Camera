# AI Photographer
#
# Portable make syntax only: macOS ships GNU Make 3.81, so no $(file ...),
# no .ONESHELL, no ::= assignments.
#
# `build` and `test` must stay hardware-free forever: no camera, no API key,
# no network. That is the contributor promise.

.PHONY: help build test check lint format clean skills release project app sim device ios-typecheck boundaries format-check

SWIFT_FLAGS = -Xswiftc -warnings-as-errors
XCODEGEN_VERSION = 2.46.0

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
	swift build $(SWIFT_FLAGS)

test:
	swift test $(SWIFT_FLAGS)

# Forge.xcodeproj is generated from project.yml and is gitignored, so it can never
# drift from the spec or cause a merge conflict.
project:
	@if command -v xcodegen >/dev/null 2>&1; then \
		actual_version=$$(xcodegen --version | awk '{print $$2}'); \
		if [ "$$actual_version" != "$(XCODEGEN_VERSION)" ]; then \
			echo "xcodegen $(XCODEGEN_VERSION) required (found $$actual_version)"; exit 1; \
		fi; \
		xcodegen generate ; \
	else \
		echo "xcodegen $(XCODEGEN_VERSION) not installed (brew install xcodegen)"; exit 1; \
	fi

# Requires Xcode's first-launch components: sudo xcodebuild -runFirstLaunch
app: project
	xcodebuild -project Forge.xcodeproj -scheme ForgePhotographer \
		-destination 'generic/platform=iOS Simulator' \
		-configuration Debug build CODE_SIGNING_ALLOWED=NO

# Build and install onto a connected iPhone.
#
# Requires FORGE_DEVELOPMENT_TEAM (your free Personal Team id) and Developer Mode
# enabled on the device. Run the very first install from Xcode instead: it creates
# the provisioning profile interactively, which this cannot do.
device: project
	@if [ -z "$$FORGE_DEVELOPMENT_TEAM" ]; then \
		echo "FORGE_DEVELOPMENT_TEAM is not set."; \
		echo "Xcode > Settings > Accounts > + (Apple ID), then:"; \
		echo "  export FORGE_DEVELOPMENT_TEAM=<your team id>"; \
		exit 1; \
	fi
	xcodebuild -project Forge.xcodeproj -scheme ForgePhotographer \
		-destination 'generic/platform=iOS' -configuration Debug \
		-allowProvisioningUpdates build
	@echo "Built. Install and run from Xcode, or:"
	@echo "  xcrun devicectl device install app --device <udid> <path/to/ForgePhotographer.app>"

# Build, install, launch, and capture the app on a simulator without opening
# Simulator.app — works over SSH with no display. FORGE_SIM_DEVICE overrides the
# device; pass ARGS="--video 8" to record instead of screenshot.
sim:
	@./Tools/sim.sh $(ARGS)

# Verifies the iOS graph without xcodebuild, so a machine missing the installed iOS
# platform can still prove the app compiles under the app target's own settings.
# Does not link or produce a bundle; `make app` remains the real build.
ios-typecheck:
	@./Tools/typecheck-ios.sh

release:
	swift build -c release $(SWIFT_FLAGS)

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

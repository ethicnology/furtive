.PHONY: all setup clean deps build-runner build-runner-watch ios-pod-update drift-migrations devcontainer devcontainer-create devcontainer-start container-tools container-app apk fvm-check release debug translations verify-reproducible format analyze test viewer-deps viewer-analyze viewer-build share-boundary share-config check

fvm-check:
	@echo "🔍 Checking FVM"
	@if ! command -v fvm >/dev/null 2>&1; then \
		echo "❌ FVM is not installed. See https://fvm.app"; \
		exit 1; \
	fi
	@fvm install

all: setup
	@echo "✨ All tasks completed!"

setup: fvm-check clean deps build-runner
	@if [ "$$(uname)" = "Darwin" ]; then $(MAKE) ios-pod-update; fi
	@echo "🚀 Setup complete!"

clean:
	@echo "🧹 Clean generated build output"
	@fvm flutter clean

deps:
	@echo "🏃 Fetch dependencies"
	@fvm flutter pub get --enforce-lockfile
	@fvm dart pub get --directory packages/furtive_share --enforce-lockfile
	@fvm dart pub get --directory viewer --enforce-lockfile

build-runner:
	@echo "🏗️ Build runner"
	@fvm dart run build_runner build --delete-conflicting-outputs --force-jit

build-runner-watch:
	@echo "🏗️ Build runner (watch mode)"
	@fvm dart run build_runner watch --delete-conflicting-outputs --force-jit

drift-migrations:
	@echo "🔄 Create schema and sum migrations"
	@fvm dart run drift_dev make-migrations

translations:
	@echo "🌐 Generating localizations from lib/l10n/*.arb"
	@fvm flutter gen-l10n
	@echo "🔎 Checking ARB key parity against app_en.arb"
	@python3 -c "import json, os, sys; \
d = 'lib/l10n'; \
arbs = {f[4:-4]: {k for k in json.load(open(os.path.join(d,f))).keys() if not k.startswith('@')} \
        for f in sorted(os.listdir(d)) if f.startswith('app_') and f.endswith('.arb')}; \
en = arbs['en']; \
bad = [(loc, sorted(en - keys), sorted(keys - en)) for loc, keys in arbs.items() if loc != 'en' and (en - keys or keys - en)]; \
print(f'  {len(arbs)} locales, {len(en)} keys each'); \
sys.exit(0) if not bad else (print('PARITY ISSUES:'), [print(f'  {loc}: missing={m} extra={e}') for loc,m,e in bad], sys.exit(1))"

format:
	@echo "🎨 Checking formatting (dart format --set-exit-if-changed)"
	@fvm dart format --set-exit-if-changed lib test packages/furtive_share/lib packages/furtive_share/test viewer/lib viewer/test viewer/web tool/validate_share_config.dart

analyze:
	@echo "🔎 Running flutter analyze"
	@fvm flutter analyze
	@$(MAKE) viewer-analyze

test:
	@echo "🧪 Running flutter test"
	@fvm flutter test
	@echo "🔐 Running pure-Dart share package tests"
	@cd packages/furtive_share && fvm dart test
	@echo "🌐 Running web viewer logic tests"
	@cd viewer && fvm dart test

viewer-deps:
	@echo "🌐 Fetching viewer dependencies"
	@fvm dart pub get --directory viewer --enforce-lockfile

viewer-analyze:
	@echo "🔎 Analyzing shared package and web viewer"
	@fvm dart analyze packages/furtive_share
	@fvm dart analyze viewer

viewer-build:
	@echo "🌐 Compiling the Dart Web viewer"
	@mkdir -p build/viewer
	@fvm dart compile js -O4 -o build/viewer/main.dart.js viewer/web/main.dart
	@python3 tool/package_viewer.py build/viewer

# The path package is a real compiler boundary, and this denylist guards its
# product promise as well: no storage, sensor, Flutter, or app import. See
# docs/SHARE-TRACKING.md.
share-boundary:
	@echo "🚧 Checking the share-layer boundary"
	@python3 tool/check_share_boundary.py

share-config:
	@echo "🔐 Validating the live-share release configuration"
	@fvm dart run tool/validate_share_config.dart

# Everything CI runs on every push/PR (see .github/workflows/ci.yml) — kept
# as a single make target so it can also be run locally before pushing.
# `translations` both regenerates lib/l10n/app_localizations*.dart (gitignored,
# needed for analyze/test to see the generated AppLocalizations class) and
# checks ARB key parity across every locale.
check: deps build-runner translations format analyze share-boundary test viewer-build
	@echo "✅ All checks passed"

ios-pod-update:
	@if [ "$$(uname)" != "Darwin" ]; then echo "Skipping pod update (not macOS)"; exit 0; fi
	@echo "🍎 Fetching iOS dependencies"
	@fvm flutter precache --ios
	@cd ios && pod install --repo-update && cd -

# Container runtime — default podman, override with CONTAINER=docker for
# environments without podman.
CONTAINER ?= podman

container-tools:
	@echo "🔧 Building tools image"
	@$(CONTAINER) build -f Containerfile.tools -t furtive-tools \
		--build-arg FLUTTER_VERSION=$$(python3 -c 'import json; print(json.load(open(".fvmrc"))["flutter"])') \
		--build-arg JVM_TARGET=$$(grep 'android.jvmTarget' android/gradle.properties | cut -d= -f2) \
		--build-arg ANDROID_API_LEVEL=$$(grep 'android.compileSdk' android/gradle.properties | cut -d= -f2) \
		--build-arg ANDROID_BUILD_TOOLS=$$(grep 'android.buildToolsVersion' android/gradle.properties | cut -d= -f2) \
		--build-arg ANDROID_NDK=$$(grep 'android.ndkVersion' android/gradle.properties | cut -d= -f2) \
		.

container-app: container-tools
	@echo "📦 Building app image"
	@$(CONTAINER) build -f Containerfile.app -t furtive-app \
		--build-arg GRADLE_HEAP=$(or $(GRADLE_HEAP),4g) \
		.

MODE ?= release
FORMAT ?= apk

# Allow "make apk release" or "make apk debug" syntax
ifneq (,$(filter release,$(MAKECMDGOALS)))
  MODE := release
endif
ifneq (,$(filter debug,$(MAKECMDGOALS)))
  MODE := debug
endif
release debug:
	@:

# Flutter writes APK and AAB to different paths
ifeq ($(FORMAT),aab)
  CONTAINER_OUTPUT := /app/build/app/outputs/bundle/$(MODE)/app-$(MODE).aab
  HOST_OUTPUT := ./app-$(MODE).aab
  FLUTTER_BUILD := fvm flutter build appbundle --$(MODE)
else
  CONTAINER_OUTPUT := /app/build/app/outputs/flutter-apk/app-$(MODE).apk
  HOST_OUTPUT := ./app-$(MODE).apk
  FLUTTER_BUILD := fvm flutter build apk --$(MODE)
endif

# Pass secrets to the build via --dart-define if they are set in the host
# environment. Empty values produce a build without the secret (CI / FOSS
# reproducible path). Override per-invocation: `make apk PROTOMAPS_KEY=xxx`.
DART_DEFINES :=
ifneq ($(strip $(PROTOMAPS_KEY)),)
  DART_DEFINES += --dart-define=PROTOMAPS_KEY=$(PROTOMAPS_KEY)
endif
ifneq ($(strip $(PROTOMAPS_URL)),)
  DART_DEFINES += --dart-define=PROTOMAPS_URL=$(PROTOMAPS_URL)
endif
ifneq ($(strip $(SHARE_VIEWER_URL)),)
  DART_DEFINES += --dart-define=SHARE_VIEWER_URL=$(SHARE_VIEWER_URL)
endif
ifneq ($(strip $(SHARE_RELAYS)),)
  DART_DEFINES += --dart-define=SHARE_RELAYS=$(SHARE_RELAYS)
endif

# Pin every timestamp the build embeds (zip entries, .class files, manifest
# attrs) to the source commit so builds are reproducible across hosts and
# wall-clock times. Honored by Gradle/AGP, Kotlin compiler, Flutter tools.
SOURCE_DATE_EPOCH ?= $(shell git log -1 --format=%ct 2>/dev/null || echo 0)

apk: container-app
	@echo "🔨 Building $(FORMAT) ($(MODE)) via $(CONTAINER)"
	@echo "   SOURCE_DATE_EPOCH=$(SOURCE_DATE_EPOCH)"
	@$(CONTAINER) rm -f furtive-build > /dev/null 2>&1 || true
	@$(CONTAINER) run --name furtive-build \
		--ulimit nofile=65536:65536 \
		-e SOURCE_DATE_EPOCH=$(SOURCE_DATE_EPOCH) \
		furtive-app bash -c 'cd /app && $(FLUTTER_BUILD) $(DART_DEFINES)'
	@$(CONTAINER) cp furtive-build:$(CONTAINER_OUTPUT) $(HOST_OUTPUT)
	@$(CONTAINER) rm furtive-build > /dev/null
	@echo "✅ Output extracted: $(HOST_OUTPUT)"
	@sha256sum $(HOST_OUTPUT) 2>/dev/null || shasum -a 256 $(HOST_OUTPUT)

# Build twice with identical inputs and compare SHA-256. Passes if bytes
# match, fails loudly with a diff hint otherwise. Use this in CI to catch
# reproducibility regressions early.
verify-reproducible:
	@echo "🔁 Reproducibility check: building twice and comparing"
	@$(MAKE) apk MODE=$(or $(MODE),release) FORMAT=$(or $(FORMAT),apk) PROTOMAPS_KEY=$(PROTOMAPS_KEY) PROTOMAPS_URL=$(PROTOMAPS_URL)
	@mv $(HOST_OUTPUT) $(HOST_OUTPUT).run1
	@$(MAKE) apk MODE=$(or $(MODE),release) FORMAT=$(or $(FORMAT),apk) PROTOMAPS_KEY=$(PROTOMAPS_KEY) PROTOMAPS_URL=$(PROTOMAPS_URL)
	@mv $(HOST_OUTPUT) $(HOST_OUTPUT).run2
	@SUM1=$$(sha256sum $(HOST_OUTPUT).run1 2>/dev/null || shasum -a 256 $(HOST_OUTPUT).run1); \
	 SUM2=$$(sha256sum $(HOST_OUTPUT).run2 2>/dev/null || shasum -a 256 $(HOST_OUTPUT).run2); \
	 echo "run1: $$SUM1"; \
	 echo "run2: $$SUM2"; \
	 H1=$$(echo $$SUM1 | awk '{print $$1}'); \
	 H2=$$(echo $$SUM2 | awk '{print $$1}'); \
	 if [ "$$H1" = "$$H2" ]; then \
	   echo "✅ Bit-identical"; \
	   rm -f $(HOST_OUTPUT).run2; mv $(HOST_OUTPUT).run1 $(HOST_OUTPUT); \
	 else \
	   echo "❌ Differs. Investigate with: diffoscope $(HOST_OUTPUT).run1 $(HOST_OUTPUT).run2"; \
	   exit 1; \
	 fi

PROJECT := $(notdir $(CURDIR))

devcontainer-create:
	@echo "🏗️  Creating Dev Container"
	@devcontainer up --workspace-folder . --config ./.devcontainer/devcontainer.json

devcontainer-start:
	@echo "▶️  Starting Dev Container ($(PROJECT))"
	@$(CONTAINER) start $(PROJECT)
	@$(CONTAINER) exec -it $(PROJECT) bash

# Alias for backwards compatibility
devcontainer: devcontainer-create

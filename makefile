.PHONY: all setup clean deps build-runner build-runner-watch ios-pod-update drift-migrations devcontainer devcontainer-create devcontainer-start container-tools container-app apk fvm-check release debug translations

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
	@echo "🧹 Clean and remove pubspec.lock and ios/Podfile.lock"
	@fvm flutter clean && rm -f pubspec.lock && rm -f ios/Podfile.lock

deps:
	@echo "🏃 Fetch dependencies"
	@fvm flutter pub get

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
		--build-arg FLUTTER_VERSION=$$(jq -r .flutter .fvmrc) \
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

apk: container-app
	@echo "🔨 Building $(FORMAT) ($(MODE)) via $(CONTAINER)"
	@$(CONTAINER) rm -f furtive-build > /dev/null 2>&1 || true
	@$(CONTAINER) run --name furtive-build \
		--ulimit nofile=65536:65536 \
		furtive-app bash -c 'cd /app && $(FLUTTER_BUILD) $(DART_DEFINES)'
	@$(CONTAINER) cp furtive-build:$(CONTAINER_OUTPUT) $(HOST_OUTPUT)
	@$(CONTAINER) rm furtive-build > /dev/null
	@echo "✅ Output extracted: $(HOST_OUTPUT)"
	@sha256sum $(HOST_OUTPUT) 2>/dev/null || shasum -a 256 $(HOST_OUTPUT)

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

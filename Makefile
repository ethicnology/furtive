# Build the release artefact in the pinned container, on a host that has
# podman, git and make and nothing else.
#
# `melos run apk` does the same thing through tool/build_release.dart and stays
# the canonical path. This file exists because publishing a release should not
# require a Dart SDK on the machine that does it: everything below is podman
# driving the same two Containerfiles, with the same pinned inputs read from
# the same files, so the two routes cannot drift in their values.

CONTAINER ?= podman
MODE      ?= release
GRADLE_HEAP ?= 4g

# The pinned inputs, read from the files that own them rather than copied here.
FLUTTER_VERSION      := $(shell sed -n 's/.*"flutter"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' .fvmrc)
GRADLE_PROPERTIES    := apps/app/android/gradle.properties
JVM_TARGET           := $(shell sed -n 's/^android\.jvmTarget=//p' $(GRADLE_PROPERTIES))
ANDROID_API_LEVEL    := $(shell sed -n 's/^android\.compileSdk=//p' $(GRADLE_PROPERTIES))
ANDROID_BUILD_TOOLS  := $(shell sed -n 's/^android\.buildToolsVersion=//p' $(GRADLE_PROPERTIES))
ANDROID_NDK          := $(shell sed -n 's/^android\.ndkVersion=//p' $(GRADLE_PROPERTIES))

# Gradle, AGP and the Kotlin compiler stamp timestamps into the artefact, so a
# reproducible build needs a fixed one. The commit being built is the only
# value that is both fixed and meaningful.
SOURCE_DATE_EPOCH ?= $(shell git log -1 --format=%ct)

# The tile key is never stored here. It comes from the environment if it is
# already exported, otherwise the build asks for it on the terminal with the
# echo off, and it lives only in the shell that runs the container. An empty
# answer builds the tileless FOSS variant, which is a real build rather than a
# broken one.
#
# `read -rs` is bash, and make would otherwise use /bin/sh.
SHELL := /bin/bash

# Asks once, at the top of a build, and exports the answer for everything the
# recipe then runs. A terminal that cannot be read from is not an error: it is
# the keyless build, announced as such.
define ask_key
if [ -n "$${PROTOMAPS_KEY:-}" ]; then \
	echo "Tile key: taken from the environment."; \
elif [ -t 0 ] && read -rsp 'Protomaps key (hidden, empty for the tileless build): ' PROTOMAPS_KEY; then \
	echo; \
else \
	PROTOMAPS_KEY=''; \
	echo "Tile key: none — building the tileless variant."; \
fi; \
export PROTOMAPS_KEY;
endef

CONTAINER_NAME := furtive-build

.PHONY: apk aab clean images

# The key is asked for first and carried into the sub-makes through the
# environment: a recipe line is its own shell, so a prompt in a later target
# could not hand anything back, and asking after the image build would mean
# waiting out a download to answer one question.
apk:
	@$(call ask_key) $(MAKE) --no-print-directory images && \
	$(MAKE) --no-print-directory artefact FORMAT=apk \
		BUILD_CMD="fvm flutter build apk --$(MODE)" \
		IN_CONTAINER=/app/apps/app/build/app/outputs/flutter-apk/app-$(MODE).apk

aab:
	@$(call ask_key) $(MAKE) --no-print-directory images && \
	$(MAKE) --no-print-directory artefact FORMAT=aab \
		BUILD_CMD="fvm flutter build appbundle --$(MODE)" \
		IN_CONTAINER=/app/apps/app/build/app/outputs/bundle/$(MODE)/app-$(MODE).aab

images:
	$(CONTAINER) build -f Containerfile.tools -t furtive-tools \
		--build-arg FLUTTER_VERSION=$(FLUTTER_VERSION) \
		--build-arg JVM_TARGET=$(JVM_TARGET) \
		--build-arg ANDROID_API_LEVEL=$(ANDROID_API_LEVEL) \
		--build-arg ANDROID_BUILD_TOOLS=$(ANDROID_BUILD_TOOLS) \
		--build-arg ANDROID_NDK=$(ANDROID_NDK) .
	$(CONTAINER) build -f Containerfile.app -t furtive-app \
		--build-arg GRADLE_HEAP=$(GRADLE_HEAP) .

# Not meant to be called directly: `apk` and `aab` set FORMAT, BUILD_CMD and
# IN_CONTAINER for it.
artefact:
	@-$(CONTAINER) rm -f $(CONTAINER_NAME) >/dev/null 2>&1
	$(CONTAINER) run --name $(CONTAINER_NAME) --ulimit nofile=65536:65536 \
		-e SOURCE_DATE_EPOCH=$(SOURCE_DATE_EPOCH) \
		-e PROTOMAPS_KEY -e PROTOMAPS_URL -e SHARE_VIEWER_URL -e SHARE_RELAYS \
		furtive-app bash -c 'cd /app/apps/app && $(BUILD_CMD) \
			$${PROTOMAPS_KEY:+--dart-define=PROTOMAPS_KEY=$$PROTOMAPS_KEY} \
			$${PROTOMAPS_URL:+--dart-define=PROTOMAPS_URL=$$PROTOMAPS_URL} \
			$${SHARE_VIEWER_URL:+--dart-define=SHARE_VIEWER_URL=$$SHARE_VIEWER_URL} \
			$${SHARE_RELAYS:+--dart-define=SHARE_RELAYS=$$SHARE_RELAYS}'
	$(CONTAINER) cp $(CONTAINER_NAME):$(IN_CONTAINER) ./app-$(MODE).$(FORMAT)
	$(CONTAINER) rm $(CONTAINER_NAME)
	@shasum -a 256 ./app-$(MODE).$(FORMAT) 2>/dev/null || sha256sum ./app-$(MODE).$(FORMAT)
	@echo "The artefact is UNSIGNED by design: sign it out-of-band with zipalign and apksigner."

clean:
	-$(CONTAINER) rm -f $(CONTAINER_NAME)
	rm -f ./app-release.apk ./app-release.aab ./app-debug.apk ./app-debug.aab

# One-word entry points for humans and agents. `make check` before every PR.
.PHONY: setup check fmt run apk release-apk device-test ssh-test offline-test store-screenshots store-frames

setup:            ## Install dependencies
	cd app && flutter pub get

# Overrides the built-in OAuth App client ID (forks, SETUP.md § 1b). Public, not a secret.
DART_DEFINES := $(if $(filter undefined,$(origin GITHUB_CLIENT_ID)),,--dart-define=GITHUB_CLIENT_ID=$(GITHUB_CLIENT_ID))

check:            ## Everything CI runs: format, analyze, test
	cd app && dart format --output=none --set-exit-if-changed lib test integration_test test_driver tool
	cd app && flutter analyze
	cd app && flutter test

fmt:              ## Auto-format Dart sources
	cd app && dart format lib test integration_test test_driver tool

run:              ## Run the app on a connected device
	cd app && flutter run $(DART_DEFINES)

device-test:      ## On-device smoke test + screenshots: make device-test DEVICE=<id from `flutter devices`>
	cd app && flutter drive --driver=test_driver/integration_test.dart \
		--target=integration_test/device_smoke_test.dart $(if $(DEVICE),-d $(DEVICE)) $(DART_DEFINES)

ssh-test:         ## Real SSH from a device: make ssh-test DEVICE=<id> SSH_HOST=<ip> SSH_USER=<user> SSH_KEY=<private key file>
	cd app && flutter drive --driver=test_driver/integration_test.dart --target=integration_test/ssh_test.dart \
		$(if $(DEVICE),-d $(DEVICE)) --dart-define=SSH_HOST=$(SSH_HOST) --dart-define=SSH_USER=$(SSH_USER) \
		--dart-define=SSH_KEY_B64=$$(base64 < $(SSH_KEY) | tr -d '\n') \
		--dart-define=SSH_FP=$$(ssh-keyscan -t ed25519 $(SSH_HOST) 2>/dev/null | ssh-keygen -lf - | awk '{print $$2}')

offline-test:     ## Real offline download of a small public repo on a device: make offline-test DEVICE=<id>
	cd app && flutter drive --driver=test_driver/integration_test.dart \
		--target=integration_test/offline_test.dart $(if $(DEVICE),-d $(DEVICE))

store-screenshots: ## Store screenshots on demo data: make store-screenshots DEVICE=<id> NAME=<folder, see store/README.md>
	cd app && SCREENSHOT_DIR=build/store/raw/$(NAME) flutter drive --driver=test_driver/integration_test.dart \
		--target=integration_test/store_screenshots_test.dart $(if $(DEVICE),-d $(DEVICE))

store-frames:     ## Captioned store images from the raw screenshots → store/screenshots/
	cd app && flutter test tool/store/frame_test.dart
	python3 store/check_lengths.py

# `flutter test` regenerates the plugin registrant with test-only plugins (integration_test), which a release build
# can't compile; deleting it (git-ignored, generated) makes the build write a fresh one.
REGISTRANT := app/android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java

apk:              ## Release APK (see SETUP.md § Release signing)
	rm -f $(REGISTRANT)
	cd app && flutter build apk --release $(DART_DEFINES)

VERSION := $(shell sed -n 's/^version: *\([^+]*\).*/\1/p' app/pubspec.yaml)

release-apk:      ## The APK attached to a GitHub release: app/build/release/diffcat-<version>.apk + .sha256
	@test -f app/android/key.properties || { echo "app/android/key.properties is missing: the APK would be debug-signed (SETUP.md § 5)"; exit 1; }
	$(MAKE) apk
	mkdir -p app/build/release
	cp app/build/app/outputs/flutter-apk/app-release.apk app/build/release/diffcat-$(VERSION).apk
	cd app/build/release && shasum -a 256 diffcat-$(VERSION).apk > diffcat-$(VERSION).apk.sha256
	@cat app/build/release/diffcat-$(VERSION).apk.sha256

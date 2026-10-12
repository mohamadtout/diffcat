# One-word entry points for humans and agents. `make check` before every PR.
.PHONY: setup check fmt run apk release-apk aab ipa no-team-id device-test ssh-test offline-test store-screenshots store-frames

setup:            ## Install dependencies
	cd app && flutter pub get

# Overrides the built-in OAuth App client ID (forks, SETUP.md § 1b). Public, not a secret.
DART_DEFINES := $(if $(filter undefined,$(origin GITHUB_CLIENT_ID)),,--dart-define=GITHUB_CLIENT_ID=$(GITHUB_CLIENT_ID))

check: no-team-id ## Everything CI runs: format, analyze, test
	cd app && dart format --output=none --set-exit-if-changed lib test integration_test test_driver tool
	cd app && flutter analyze
	cd app && flutter test

fmt:              ## Auto-format Dart sources
	cd app && dart format lib test integration_test test_driver tool

run:              ## Run the app on a connected device: make run [DEVICE=<id from `flutter devices`>] [MODE=debug|profile|release]
	$(if $(filter $(or $(MODE),debug),debug profile release),,$(error MODE must be debug, profile or release, not "$(MODE)"))
	cd app && flutter run --$(or $(MODE),debug) $(if $(DEVICE),-d $(DEVICE)) $(DART_DEFINES)

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
	rm -rf app/build/store/raw/$(NAME)  # a failed or partial run must not leave older shots to be framed
	cd app && SCREENSHOT_DIR=build/store/raw/$(NAME) flutter drive --driver=test_driver/integration_test.dart \
		--target=integration_test/store_screenshots_test.dart $(if $(DEVICE),-d $(DEVICE))

store-frames:     ## Captioned store images from the raw screenshots → store/screenshots/
	cd app && flutter test tool/store/frame_test.dart
	python3 store/check_lengths.py

# The plugin registrant (generated, git-ignored) lists test-only plugins (integration_test) after `flutter test` or
# an editor's `pub get`, and a release build can't compile those. The build normally rewrites it for release, but
# one written mid-build still breaks it, so on that failure build once more.
REGISTRANT := app/android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java

VERSION := $(shell sed -n 's/^version: *\([^+]*\).*/\1/p' app/pubspec.yaml)

# Release builds keep Dart debug info out of the app (1.6 MB less per CPU type) and write it to app/build/symbols/,
# which `flutter symbolize` needs to read a logged stack trace (SETUP.md § 6c). Paths are relative to app/.
release_flags = --release --split-debug-info=build/symbols/$(1)-$(VERSION) $(DART_DEFINES)

# One APK per CPU type: a universal APK carries all three copies of the engine and Dart code (73 MB instead of 25).
ABIS := arm64-v8a armeabi-v7a x86_64

apk:              ## Release APKs, one per CPU type: app/build/app/outputs/flutter-apk/app-<abi>-release.apk
	rm -f $(REGISTRANT)
	cd app && { flutter build apk --split-per-abi $(call release_flags,apk) || { grep -q integration_test ../$(REGISTRANT) && \
		echo "Building again: the plugin registrant had test-only plugins" && \
		flutter build apk --split-per-abi $(call release_flags,apk); }; }

release-apk:      ## The APKs attached to a GitHub release: app/build/release/diffcat-<version>-<abi>.apk + .sha256
	@test -f app/android/key.properties || { echo "app/android/key.properties is missing: the APK would be debug-signed (SETUP.md § 5)"; exit 1; }
	$(MAKE) apk
	mkdir -p app/build/release
	for abi in $(ABIS); do \
		cp app/build/app/outputs/flutter-apk/app-$$abi-release.apk app/build/release/diffcat-$(VERSION)-$$abi.apk; done
	cd app/build/release && shasum -a 256 $(ABIS:%=diffcat-$(VERSION)-%.apk) > diffcat-$(VERSION).sha256
	rm -f app/build/release/diffcat-$(VERSION)-symbols.zip
	cd app/build/symbols/apk-$(VERSION) && zip -q ../../release/diffcat-$(VERSION)-symbols.zip *.symbols
	@cat app/build/release/diffcat-$(VERSION).sha256

aab:              ## Google Play bundle → app/build/app/outputs/bundle/release/app-release.aab
	@test -f app/android/key.properties || { echo "app/android/key.properties is missing: Play rejects a debug-signed bundle (SETUP.md § 5)"; exit 1; }
	rm -f $(REGISTRANT)
	cd app && flutter build appbundle $(call release_flags,aab)

# The Apple Team ID lives in the git-ignored app/ios/Flutter/Signing.xcconfig. Picking a team in Xcode's Signing tab
# writes it into project.pbxproj, which is public.
PBXPROJ := app/ios/Runner.xcodeproj/project.pbxproj

no-team-id:       ## Fails if Xcode wrote a Team ID into the committed project file
	@! grep -q DEVELOPMENT_TEAM $(PBXPROJ) || { echo "$(PBXPROJ) has DEVELOPMENT_TEAM (Xcode's Signing tab put it there). Remove those lines; the ID belongs in app/ios/Flutter/Signing.xcconfig (SETUP.md § 6)."; exit 1; }

ipa: no-team-id   ## App Store IPA → app/build/ios/ipa/ (needs Signing.xcconfig and Xcode signed in to your Apple ID)
	@test -f app/ios/Flutter/Signing.xcconfig || { echo "app/ios/Flutter/Signing.xcconfig is missing: copy Signing.xcconfig.example and add your Team ID (SETUP.md § 6)"; exit 1; }
	cd app && flutter build ipa --release $(DART_DEFINES)
	@ls app/build/ios/ipa/*.ipa

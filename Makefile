SHELL := /bin/zsh

ENV_FILE ?= .env
-include $(ENV_FILE)

DEVELOPER_DIR ?= /Applications/Xcode.app/Contents/Developer
SWIFT ?= xcrun --sdk macosx swift
PREK ?= prek
PREK_HOME ?= $(CURDIR)/.prek-cache
LOCAL_HOME ?= $(CURDIR)/.local-home
CLANG_CACHE ?= $(CURDIR)/.cache/clang
XCODE_SCHEME ?= PlantKeeperApp
SIMULATOR_NAME ?= iPhone 14 Pro Max
SIMULATOR_APP ?= Simulator
IOS_BUNDLE_ID ?= com.thekyz.plantkeeper
IOS_MIN_VERSION ?= 17.0
SIM_DERIVED_DATA ?= $(CURDIR)/.derivedData-sim
DEVICE_DERIVED_DATA ?= $(CURDIR)/.derivedData-device
SIM_RUN_DIR ?= $(CURDIR)/.run/sim
DEVICE_RUN_DIR ?= $(CURDIR)/.run/device
SIM_APP_DIR ?= $(SIM_RUN_DIR)/PlantKeeperApp.app
DEVICE_APP_DIR ?= $(DEVICE_RUN_DIR)/PlantKeeperApp.app
SIM_RESOLVED_UDID_FILE ?= $(SIM_RUN_DIR)/.simulator-udid
SIM_RESOLVED_NAME_FILE ?= $(SIM_RUN_DIR)/.simulator-name
APP_PLIST_TEMPLATE ?= $(CURDIR)/Config/iOS/AppBundleTemplate.plist
APP_ENTITLEMENTS_TEMPLATE ?= $(CURDIR)/Config/iOS/App.entitlements.template
DEVICE_UDID ?=
CODE_SIGN_IDENTITY ?=
MOBILEPROVISION_PATH ?=
MIRROR_APP_NAME ?= iPhone Mirroring
OPEN_IPHONE_MIRRORING ?= 0
DEPLOY_MODE ?= personal
DEVELOPMENT_TEAM ?=
ICLOUD_CONTAINER ?= iCloud.$(IOS_BUNDLE_ID)
DEVICE_SIGN_ENTITLEMENTS ?= $(DEVICE_RUN_DIR)/PlantKeeperApp.signing-entitlements.plist
BUILD_ENV := DEVELOPER_DIR="$(DEVELOPER_DIR)" HOME="$(LOCAL_HOME)" CLANG_MODULE_CACHE_PATH="$(CLANG_CACHE)" SWIFTPM_MODULECACHE_OVERRIDE="$(CLANG_CACHE)"
CACHE_PATH_STAMP := $(CLANG_CACHE)/.workspace-path
SWIFTPM_PATH_STAMP := $(CURDIR)/.build/.workspace-path
COVERAGE_BASELINE_MIN ?= 75
COVERAGE_HOOK_MIN ?= 70
COVERAGE_MIN ?= $(COVERAGE_BASELINE_MIN)
COVERAGE_PROFILE := $(CURDIR)/.build/arm64-apple-macosx/debug/codecov/default.profdata
COVERAGE_BINARY := $(CURDIR)/.build/arm64-apple-macosx/debug/PlantKeeperPackageTests.xctest/Contents/MacOS/PlantKeeperPackageTests

.PHONY: build test run build-sim run-sim run-ios deploy prek-install prek-run doctor prepare-cache clean ios-resolve ios-setup coverage coverage-hook coverage-threshold-check validate-ios-plist

prepare-cache:
	@mkdir -p "$(LOCAL_HOME)/Library/Caches" "$(CLANG_CACHE)" "$(PREK_HOME)"
	@if [ ! -f "$(CACHE_PATH_STAMP)" ] || [ "$$(cat "$(CACHE_PATH_STAMP)")" != "$(CURDIR)" ]; then \
		rm -rf "$(CLANG_CACHE)"; \
		mkdir -p "$(CLANG_CACHE)"; \
		printf '%s' "$(CURDIR)" > "$(CACHE_PATH_STAMP)"; \
	fi
	@if [ ! -f "$(SWIFTPM_PATH_STAMP)" ] || [ "$$(cat "$(SWIFTPM_PATH_STAMP)")" != "$(CURDIR)" ]; then \
		rm -rf "$(CURDIR)/.build"; \
		mkdir -p "$(CURDIR)/.build"; \
		printf '%s' "$(CURDIR)" > "$(SWIFTPM_PATH_STAMP)"; \
	fi

build: prepare-cache
	$(BUILD_ENV) $(SWIFT) build

test: prepare-cache
	$(BUILD_ENV) $(SWIFT) test

coverage-threshold-check:
	@awk -v baseline="$(COVERAGE_BASELINE_MIN)" -v hook="$(COVERAGE_HOOK_MIN)" 'BEGIN { \
		if ((baseline + 0) <= (hook + 0)) { \
			printf("Coverage configuration invalid: baseline %.2f%% must be higher than hook %.2f%%.\n", baseline, hook); \
			exit 1; \
		} \
	}'

coverage: coverage-threshold-check prepare-cache
	$(BUILD_ENV) $(SWIFT) test --enable-code-coverage
	@report="$$(DEVELOPER_DIR="$(DEVELOPER_DIR)" xcrun llvm-cov report "$(COVERAGE_BINARY)" -instr-profile "$(COVERAGE_PROFILE)")"; \
	printf '%s\n' "$$report"; \
	line_cov="$$(printf '%s\n' "$$report" | awk '/^TOTAL/ { gsub("%","",$$10); print $$10 }')"; \
	if [ -z "$$line_cov" ]; then echo "Failed to extract TOTAL line coverage."; exit 1; fi; \
	awk -v cov="$$line_cov" -v min="$(COVERAGE_MIN)" 'BEGIN { \
		if ((cov + 0) < (min + 0)) { \
			printf("Coverage check failed: %.2f%% < %.2f%% minimum.\n", cov, min); \
			exit 1; \
		} else { \
			printf("Coverage check passed: %.2f%% >= %.2f%% minimum.\n", cov, min); \
		} \
	}'

coverage-hook: coverage-threshold-check
	@$(MAKE) coverage COVERAGE_MIN="$(COVERAGE_HOOK_MIN)"

validate-ios-plist:
	./scripts/validate-ios-plist.sh

run: prepare-cache
	$(BUILD_ENV) $(SWIFT) run PlantKeeperApp

build-sim: validate-ios-plist
	@set -e; \
	mkdir -p "$(SIM_DERIVED_DATA)" "$(SIM_RUN_DIR)"; \
	devices="$$(DEVELOPER_DIR="$(DEVELOPER_DIR)" xcrun simctl list devices available | while IFS= read -r line; do \
		udid=$$(printf '%s\n' "$$line" | grep -Eo '[0-9A-F]{8}-[0-9A-F-]{27}' | head -n1 || true); \
		if [ -z "$$udid" ]; then continue; fi; \
		name=$$(printf '%s\n' "$$line" | sed -E "s/^[[:space:]]*//; s/ \\($$udid\\) \\((Booted|Shutdown)\\)[[:space:]]*$$//"); \
		printf '%s\t%s\n' "$$name" "$$udid"; \
	done)"; \
	if [ -z "$$devices" ]; then \
		echo "No available simulators found."; \
		echo "Install one in Xcode > Settings > Components, then run: make doctor"; \
		exit 1; \
	fi; \
	resolved_name="$(SIMULATOR_NAME)"; \
	resolved_udid="$$(printf '%s\n' "$$devices" | awk -F '\t' -v req="$(SIMULATOR_NAME)" '$$1==req{print $$2; exit}')"; \
	if [ -z "$$resolved_udid" ]; then \
		resolved_name="$$(printf '%s\n' "$$devices" | awk -F '\t' '/^iPhone /{print $$1; exit}')"; \
		if [ -z "$$resolved_name" ]; then \
			resolved_name="$$(printf '%s\n' "$$devices" | awk -F '\t' 'NR==1{print $$1; exit}')"; \
		fi; \
		resolved_udid="$$(printf '%s\n' "$$devices" | awk -F '\t' -v req="$$resolved_name" '$$1==req{print $$2; exit}')"; \
		echo "Requested simulator '$(SIMULATOR_NAME)' not available. Using '$$resolved_name'."; \
	fi; \
	printf '%s' "$$resolved_udid" > "$(SIM_RESOLVED_UDID_FILE)"; \
	printf '%s' "$$resolved_name" > "$(SIM_RESOLVED_NAME_FILE)"; \
	echo "Building for simulator: $$resolved_name ($$resolved_udid)"; \
	DEVELOPER_DIR="$(DEVELOPER_DIR)" xcodebuild -scheme "$(XCODE_SCHEME)" -destination "id=$$resolved_udid" -derivedDataPath "$(SIM_DERIVED_DATA)" -configuration Debug build

run-sim: build-sim
	@set -e; \
	resolved_udid="$$(cat "$(SIM_RESOLVED_UDID_FILE)" 2>/dev/null || true)"; \
	resolved_name="$$(cat "$(SIM_RESOLVED_NAME_FILE)" 2>/dev/null || true)"; \
	if [ -z "$$resolved_udid" ]; then \
		echo "Missing resolved simulator id. Re-run: make build-sim"; \
		exit 1; \
	fi; \
	rm -rf "$(SIM_APP_DIR)"; \
	mkdir -p "$(SIM_APP_DIR)"; \
	cp "$(SIM_DERIVED_DATA)/Build/Products/Debug-iphonesimulator/PlantKeeperApp" "$(SIM_APP_DIR)/PlantKeeperApp"; \
	cp "$(APP_PLIST_TEMPLATE)" "$(SIM_APP_DIR)/Info.plist"; \
	sed -i '' -e 's#__BUNDLE_ID__#$(IOS_BUNDLE_ID)#g' -e 's#__MIN_VERSION__#$(IOS_MIN_VERSION)#g' "$(SIM_APP_DIR)/Info.plist"; \
	if [ -f "$(CURDIR)/logo.png" ]; then cp "$(CURDIR)/logo.png" "$(SIM_APP_DIR)/logo.png"; fi; \
	echo "Launching on simulator: $$resolved_name ($$resolved_udid)"; \
	open -a "$(SIMULATOR_APP)" || echo "Simulator app could not be opened automatically."; \
	DEVELOPER_DIR="$(DEVELOPER_DIR)" xcrun simctl boot "$$resolved_udid" || true; \
	DEVELOPER_DIR="$(DEVELOPER_DIR)" xcrun simctl bootstatus "$$resolved_udid" -b; \
	DEVELOPER_DIR="$(DEVELOPER_DIR)" xcrun simctl install "$$resolved_udid" "$(SIM_APP_DIR)"; \
	DEVELOPER_DIR="$(DEVELOPER_DIR)" xcrun simctl launch "$$resolved_udid" "$(IOS_BUNDLE_ID)"

deploy: validate-ios-plist
	@if [ -z "$(DEVICE_UDID)" ]; then echo "DEVICE_UDID is required. Run 'make ios-setup' to save config in $(ENV_FILE), or pass vars inline."; exit 1; fi
	@if [ -z "$(CODE_SIGN_IDENTITY)" ]; then echo "CODE_SIGN_IDENTITY is required for physical device deployment."; exit 1; fi
	@set -e; \
	profile_path="$(MOBILEPROVISION_PATH)"; \
	deploy_mode="$(DEPLOY_MODE)"; \
	derived_data_path="$(DEVICE_DERIVED_DATA)-$$(date +%s)-$$$$"; \
	build_device_id="$(DEVICE_UDID)"; \
	build_destination="id=$$build_device_id"; \
	devicectl_device="$(DEVICE_UDID)"; \
	device_listing="$$(DEVELOPER_DIR="$(DEVELOPER_DIR)" xcrun devicectl list devices 2>/dev/null || true)"; \
	device_name="$$(printf '%s\n' "$$device_listing" | sed -E 's/[[:space:]]{2,}/\t/g' | awk -F '\t' -v id="$(DEVICE_UDID)" '$$3==id {print $$1; exit}')"; \
	xcode_destinations="$$(DEVELOPER_DIR="$(DEVELOPER_DIR)" xcodebuild -scheme "$(XCODE_SCHEME)" -showdestinations 2>/dev/null || true)"; \
	available_ios_destinations="$$(printf '%s\n' "$$xcode_destinations" | awk '/Available destinations for/{in_block=1; next} /Ineligible destinations/{in_block=0} in_block && /platform:iOS,/ && $$0 !~ /Any iOS Device/ {print}')"; \
	if ! printf '%s\n' "$$available_ios_destinations" | grep -Fq "id:$$build_device_id,"; then \
		if [ -n "$$device_name" ]; then \
			mapped_build_id="$$(printf '%s\n' "$$available_ios_destinations" | sed -nE 's/.*id:([^,}]+), name:([^}]+).*/\2\t\1/p' | awk -F '\t' -v name="$$device_name" '{gsub(/^[[:space:]]+|[[:space:]]+$$/,"",$$1); gsub(/^[[:space:]]+|[[:space:]]+$$/,"",$$2); if ($$1==name){print $$2; exit}}')"; \
			if [ -n "$$mapped_build_id" ]; then \
				build_device_id="$$mapped_build_id"; \
				build_destination="id=$$build_device_id"; \
				echo "Resolved Xcode destination id '$$build_device_id' for configured device '$$device_name' ($(DEVICE_UDID))."; \
			fi; \
		fi; \
	fi; \
	if [ -z "$$device_name" ]; then \
		device_name="$$(printf '%s\n' "$$available_ios_destinations" | sed -nE 's/.*id:([^,}]+), name:([^}]+).*/\1\t\2/p' | awk -F '\t' -v id="$$build_device_id" '{gsub(/^[[:space:]]+|[[:space:]]+$$/,"",$$1); gsub(/^[[:space:]]+|[[:space:]]+$$/,"",$$2); if ($$1==id){print $$2; exit}}')"; \
	fi; \
	if ! printf '%s\n' "$$available_ios_destinations" | grep -Fq "id:$$build_device_id,"; then \
		echo "Configured iPhone is not available to Xcode right now."; \
		echo "Configured DEVICE_UDID: $(DEVICE_UDID)$${device_name:+ ($$device_name)}"; \
		if [ "$$build_device_id" != "$(DEVICE_UDID)" ]; then \
			echo "Resolved Xcode destination id: $$build_device_id"; \
		fi; \
		if [ -n "$$available_ios_destinations" ]; then \
			echo "Reachable physical iOS destinations for scheme '$(XCODE_SCHEME)':"; \
			printf '%s\n' "$$available_ios_destinations"; \
		else \
			echo "No physical iOS destinations are currently reachable for scheme '$(XCODE_SCHEME)'."; \
		fi; \
		echo "Troubleshooting:"; \
		echo "  1) Connect your iPhone via USB once, unlock it, and tap Trust if prompted."; \
		echo "  2) If using wireless debugging, keep Mac + iPhone on the same Wi-Fi and enable Connect via network in Xcode."; \
		echo "  3) Confirm Developer Mode is enabled on the iPhone."; \
		echo "  4) Re-check with: DEVELOPER_DIR=$(DEVELOPER_DIR) xcodebuild -scheme $(XCODE_SCHEME) -showdestinations"; \
		echo "  5) Then retry: make run-ios"; \
		exit 1; \
	fi; \
	team_id="$(DEVELOPMENT_TEAM)"; \
	if [ -z "$$team_id" ]; then \
		team_id="$$(printf '%s\n' "$(CODE_SIGN_IDENTITY)" | sed -n 's/.*(\([A-Z0-9]\{10\}\)).*/\1/p')"; \
	fi; \
	if ! printf '%s\n' "$(CODE_SIGN_IDENTITY)" | grep -q '^Apple Development:'; then \
		echo "CODE_SIGN_IDENTITY looks invalid: $(CODE_SIGN_IDENTITY)"; \
		echo "Expected format: Apple Development: Your Name (TEAMID)"; \
		echo "Run: security find-identity -v -p codesigning"; \
		exit 1; \
	fi; \
	if [ "$$deploy_mode" = "personal" ] && [ ! -f "$$profile_path" ]; then \
		for p in $$(for d in "$$HOME/Library/MobileDevice/Provisioning Profiles" "$$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"; do \
			[ -d "$$d" ] || continue; \
			find "$$d" -maxdepth 1 -type f -name '*.mobileprovision' -print 2>/dev/null; \
		done | while IFS= read -r fp; do printf '%s\t%s\n' "$$(stat -f '%m' "$$fp" 2>/dev/null || echo 0)" "$$fp"; done | sort -nr | cut -f2-); do \
			xml="$$(security cms -D -i "$$p" 2>/dev/null || true)"; \
			if [ -z "$$xml" ]; then continue; fi; \
			if [ -n "$$team_id" ] && ! printf '%s\n' "$$xml" | grep -q "<string>$$team_id</string>"; then continue; fi; \
			if printf '%s\n' "$$xml" | grep -q "<string>$${team_id}.$(IOS_BUNDLE_ID)</string>" || \
			   printf '%s\n' "$$xml" | grep -q "<string>$${team_id}.\*</string>"; then \
				profile_path="$$p"; \
				break; \
			fi; \
		done; \
	fi; \
	if [ ! -f "$$profile_path" ]; then \
		echo "No provisioning profile found."; \
		if [ "$$deploy_mode" = "personal" ]; then \
			echo "Personal Team mode requires an Xcode-managed profile."; \
			echo "Create one by opening any simple iOS app in Xcode, set Team to Personal Team, use bundle id '$(IOS_BUNDLE_ID)', and run once on your iPhone."; \
			echo "Then re-run: make run-ios"; \
		else \
			echo "MOBILEPROVISION_PATH must point to an existing provisioning profile file."; \
		fi; \
		exit 1; \
	fi; \
	echo "Using deploy mode: $$deploy_mode"; \
	echo "Using provisioning profile: $$profile_path"; \
	echo "Using build destination: $$build_destination"; \
	echo "Using derived data path: $$derived_data_path"; \
	mkdir -p "$$derived_data_path" "$(DEVICE_RUN_DIR)"; \
	echo "$$profile_path" > "$(DEVICE_RUN_DIR)/.resolved.mobileprovision"; \
	echo "$$deploy_mode" > "$(DEVICE_RUN_DIR)/.resolved.deploymode"; \
	echo "$$devicectl_device" > "$(DEVICE_RUN_DIR)/.resolved.devicectl.device"; \
	echo "$$build_destination" > "$(DEVICE_RUN_DIR)/.resolved.build.destination"; \
	echo "$$derived_data_path" > "$(DEVICE_RUN_DIR)/.resolved.derived-data"
	DEVELOPER_DIR="$(DEVELOPER_DIR)" xcodebuild -scheme "$(XCODE_SCHEME)" -destination "$$(cat "$(DEVICE_RUN_DIR)/.resolved.build.destination")" -derivedDataPath "$$(cat "$(DEVICE_RUN_DIR)/.resolved.derived-data")" -configuration Debug build
	@rm -rf "$(DEVICE_APP_DIR)"
	@mkdir -p "$(DEVICE_APP_DIR)"
	@cp "$$(cat "$(DEVICE_RUN_DIR)/.resolved.derived-data")/Build/Products/Debug-iphoneos/PlantKeeperApp" "$(DEVICE_APP_DIR)/PlantKeeperApp"
	@cp "$(APP_PLIST_TEMPLATE)" "$(DEVICE_APP_DIR)/Info.plist"
	@sed -i '' -e 's#__BUNDLE_ID__#$(IOS_BUNDLE_ID)#g' -e 's#__MIN_VERSION__#$(IOS_MIN_VERSION)#g' "$(DEVICE_APP_DIR)/Info.plist"
	@if [ -f "$(CURDIR)/logo.png" ]; then cp "$(CURDIR)/logo.png" "$(DEVICE_APP_DIR)/logo.png"; fi
	@cp "$$(cat "$(DEVICE_RUN_DIR)/.resolved.mobileprovision")" "$(DEVICE_APP_DIR)/embedded.mobileprovision"
	@security cms -D -i "$(DEVICE_APP_DIR)/embedded.mobileprovision" > "$(DEVICE_RUN_DIR)/.resolved.mobileprovision.plist"
	@/usr/libexec/PlistBuddy -x -c "Print :Entitlements" "$(DEVICE_RUN_DIR)/.resolved.mobileprovision.plist" > "$(DEVICE_SIGN_ENTITLEMENTS)"
	@codesign --force --sign "$(CODE_SIGN_IDENTITY)" --entitlements "$(DEVICE_SIGN_ENTITLEMENTS)" "$(DEVICE_APP_DIR)"
	DEVELOPER_DIR="$(DEVELOPER_DIR)" xcrun devicectl device install app --device "$$(cat "$(DEVICE_RUN_DIR)/.resolved.devicectl.device")" "$(DEVICE_APP_DIR)"
	DEVELOPER_DIR="$(DEVELOPER_DIR)" xcrun devicectl device process launch --device "$$(cat "$(DEVICE_RUN_DIR)/.resolved.devicectl.device")" "$(IOS_BUNDLE_ID)"

ios-resolve:
	@set -e; \
	if [ -n "$(DEVICE_UDID)" ] && [ -n "$(CODE_SIGN_IDENTITY)" ] && printf '%s\n' "$(CODE_SIGN_IDENTITY)" | grep -q '^Apple Development:' && { [ "$(DEPLOY_MODE)" = "personal" ] || [ -f "$(MOBILEPROVISION_PATH)" ]; }; then \
		exit 0; \
	fi; \
	if [ ! -t 0 ]; then \
		echo "iOS deploy config is incomplete and no TTY is available for prompts."; \
		echo "Run 'make ios-setup' in a terminal to create $(ENV_FILE), or pass variables inline."; \
		exit 1; \
	fi; \
	echo "iOS deploy config is incomplete. Launching interactive setup..."; \
	$(MAKE) --no-print-directory ios-setup

ios-setup:
	@set -e; \
	device_listing="$$(DEVELOPER_DIR="$(DEVELOPER_DIR)" xcrun devicectl list devices 2>/dev/null || true)"; \
	xcode_destinations="$$(DEVELOPER_DIR="$(DEVELOPER_DIR)" xcodebuild -scheme "$(XCODE_SCHEME)" -showdestinations 2>/dev/null || true)"; \
	detected_udid="$$(printf '%s\n' "$$xcode_destinations" | awk '/Available destinations for/{in_block=1; next} /Ineligible destinations/{in_block=0} in_block && /platform:iOS,/ && $$0 !~ /Any iOS Device/ {print}' | sed -nE 's/.*id:([^,}]+),.*/\1/p' | head -n1 || true)"; \
	if [ -z "$$detected_udid" ]; then \
		detected_udid="$$(printf '%s\n' "$$device_listing" | grep -i 'iphone' | grep -Eo '[0-9A-Fa-f]{8}-[0-9A-Fa-f-]{27}' | head -n1 || true)"; \
	fi; \
	if [ -z "$$detected_udid" ]; then \
		detected_udid="$$(DEVELOPER_DIR="$(DEVELOPER_DIR)" xcrun xctrace list devices 2>/dev/null | grep -i 'iphone' | grep -vi simulator | grep -Eo '([0-9A-Fa-f]{8}-[0-9A-Fa-f]{16}|[0-9A-Fa-f]{8}-[0-9A-Fa-f-]{27})' | head -n1 || true)"; \
	fi; \
	identity_listing="$$(security find-identity -v -p codesigning 2>/dev/null || true)"; \
	detected_identity="$$(printf '%s\n' "$$identity_listing" | sed -n 's/.*\"\(Apple Development: [^\"]*\)\".*/\1/p' | head -n1 || true)"; \
	if [ -z "$$detected_identity" ]; then \
		detected_identity="$$(printf '%s\n' "$$identity_listing" | sed -n 's/.*\"\([^\"]*\)\".*/\1/p' | head -n1 || true)"; \
	fi; \
	profiles_listing="$$(for d in "$$HOME/Library/MobileDevice/Provisioning Profiles" "$$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"; do \
		[ -d "$$d" ] || continue; \
		find "$$d" -maxdepth 1 -type f -name '*.mobileprovision' -print 2>/dev/null; \
	done | while IFS= read -r p; do \
		printf '%s\t%s\n' "$$(stat -f '%m' "$$p" 2>/dev/null || echo 0)" "$$p"; \
	done | sort -nr | cut -f2-)"; \
	detected_profile="$$(printf '%s\n' "$$profiles_listing" | head -n1 || true)"; \
	device_udid="$(DEVICE_UDID)"; \
	code_sign_identity="$(CODE_SIGN_IDENTITY)"; \
	mobileprovision_path="$(MOBILEPROVISION_PATH)"; \
	ios_bundle_id="$(IOS_BUNDLE_ID)"; \
	deploy_mode="$(DEPLOY_MODE)"; \
	development_team="$(DEVELOPMENT_TEAM)"; \
	icloud_container="$(ICLOUD_CONTAINER)"; \
	if [ -z "$$device_udid" ]; then device_udid="$$detected_udid"; fi; \
	if [ -z "$$code_sign_identity" ]; then code_sign_identity="$$detected_identity"; fi; \
	if [ -n "$$code_sign_identity" ] && ! printf '%s\n' "$$code_sign_identity" | grep -q '^Apple Development:' && [ -n "$$detected_identity" ]; then \
		code_sign_identity="$$detected_identity"; \
	fi; \
	if [ -z "$$mobileprovision_path" ]; then mobileprovision_path="$$detected_profile"; fi; \
	if [ -z "$$development_team" ]; then \
		development_team="$$(printf '%s\n' "$$code_sign_identity" | sed -n 's/.*(\([A-Z0-9]\{10\}\)).*/\1/p')"; \
	fi; \
	echo "Connected devices from devicectl:"; \
	printf '%s\n' "$$device_listing"; \
	echo ""; \
	echo "Press Enter to accept detected/default values."; \
	echo ""; \
	if [ -z "$$device_udid" ]; then \
		echo "Missing DEVICE_UDID."; \
		echo "How to get it:"; \
		echo "  1) Connect + unlock iPhone, tap Trust, enable Developer Mode."; \
		echo "  2) Run: DEVELOPER_DIR=$(DEVELOPER_DIR) xcrun devicectl list devices"; \
		echo "  3) Copy your iPhone UDID."; \
		echo ""; \
	fi; \
	read "input?DEVICE_UDID [$$device_udid]: "; \
	if [ -n "$$input" ]; then device_udid="$$input"; fi; \
	if [ -z "$$code_sign_identity" ]; then \
		echo "Missing CODE_SIGN_IDENTITY."; \
		echo "Available signing identities:"; \
		if [ -n "$$identity_listing" ]; then printf '%s\n' "$$identity_listing"; else echo "  (none found)"; fi; \
		echo "How to create one: open Xcode > Settings > Accounts, sign in with Apple ID, then create/download development certs."; \
		echo ""; \
	fi; \
	read "input?CODE_SIGN_IDENTITY [$$code_sign_identity]: "; \
	if [ -n "$$input" ]; then code_sign_identity="$$input"; fi; \
	if [ -z "$$mobileprovision_path" ]; then \
		echo "Missing MOBILEPROVISION_PATH."; \
		echo "Recent local provisioning profiles:"; \
		if [ -n "$$profiles_listing" ]; then printf '%s\n' "$$profiles_listing" | sed -n '1,5p'; else echo "  (none found in $$HOME/Library/MobileDevice/Provisioning Profiles or $$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles)"; fi; \
		echo "How to get one (no paid account): in Xcode create/run a simple iOS app once with Team=Personal Team and bundle id '$$ios_bundle_id'."; \
		echo "This generates an Xcode-managed .mobileprovision in one of:"; \
		echo "  $$HOME/Library/MobileDevice/Provisioning Profiles"; \
		echo "  $$HOME/Library/Developer/Xcode/UserData/Provisioning Profiles"; \
		echo ""; \
	fi; \
	read "input?MOBILEPROVISION_PATH [$$mobileprovision_path]: "; \
	if [ -n "$$input" ]; then mobileprovision_path="$$input"; fi; \
	read "input?IOS_BUNDLE_ID [$$ios_bundle_id]: "; \
	if [ -n "$$input" ]; then ios_bundle_id="$$input"; fi; \
	read "input?DEPLOY_MODE [$$deploy_mode]: "; \
	if [ -n "$$input" ]; then deploy_mode="$$input"; fi; \
	read "input?DEVELOPMENT_TEAM [$$development_team]: "; \
	if [ -n "$$input" ]; then development_team="$$input"; fi; \
	default_icloud="iCloud.$$ios_bundle_id"; \
	if [ -z "$$icloud_container" ] || [ "$$icloud_container" = "iCloud.com.thekyz.plantkeeper" ]; then icloud_container="$$default_icloud"; fi; \
	read "input?ICLOUD_CONTAINER [$$icloud_container]: "; \
	if [ -n "$$input" ]; then icloud_container="$$input"; fi; \
	if [ -z "$$device_udid" ]; then echo "DEVICE_UDID cannot be empty. Use: DEVELOPER_DIR=$(DEVELOPER_DIR) xcrun devicectl list devices"; exit 1; fi; \
	if [ -z "$$code_sign_identity" ]; then echo "CODE_SIGN_IDENTITY cannot be empty. Use: security find-identity -v -p codesigning"; exit 1; fi; \
	if [ "$$deploy_mode" = "paid" ] && [ ! -f "$$mobileprovision_path" ]; then echo "MOBILEPROVISION_PATH does not exist: $$mobileprovision_path"; echo "Download/export a .mobileprovision and re-run make ios-setup."; exit 1; fi; \
	printf '%s\n' \
		"DEVICE_UDID=$$device_udid" \
		"CODE_SIGN_IDENTITY=$$code_sign_identity" \
		"MOBILEPROVISION_PATH=$$mobileprovision_path" \
		"IOS_BUNDLE_ID=$$ios_bundle_id" \
		"DEPLOY_MODE=$$deploy_mode" \
		"DEVELOPMENT_TEAM=$$development_team" \
		"ICLOUD_CONTAINER=$$icloud_container" \
		> "$(ENV_FILE)"; \
	echo "Saved iOS deploy config to $(ENV_FILE)."

run-ios:
	@$(MAKE) --no-print-directory ios-resolve
	@$(MAKE) --no-print-directory deploy
	@if [ "$(OPEN_IPHONE_MIRRORING)" = "1" ]; then \
		open -a "$(MIRROR_APP_NAME)" || echo "iPhone Mirroring app could not be opened automatically. Open it manually from Applications."; \
	else \
		echo "Skipping iPhone Mirroring (OPEN_IPHONE_MIRRORING=0)."; \
	fi

prek-install:
	@mkdir -p "$(PREK_HOME)"
	PREK_HOME="$(PREK_HOME)" $(PREK) install

prek-run:
	@mkdir -p "$(PREK_HOME)"
	PREK_HOME="$(PREK_HOME)" $(PREK) run --all-files

doctor:
	@echo "DEVELOPER_DIR=$(DEVELOPER_DIR)"
	@DEVELOPER_DIR="$(DEVELOPER_DIR)" xcrun --find swift
	@DEVELOPER_DIR="$(DEVELOPER_DIR)" xcrun swift --version
	@echo "Available iOS simulators:"
	@DEVELOPER_DIR="$(DEVELOPER_DIR)" xcrun simctl list devices available
	@echo "Connected devices:"
	@DEVELOPER_DIR="$(DEVELOPER_DIR)" xcrun devicectl list devices

clean:
	@rm -rf "$(CURDIR)/.build" "$(CLANG_CACHE)" "$(SIM_DERIVED_DATA)" "$(DEVICE_DERIVED_DATA)" "$(DEVICE_DERIVED_DATA)-"* "$(SIM_RUN_DIR)" "$(DEVICE_RUN_DIR)"
	@echo "Cleaned build artifacts and caches."

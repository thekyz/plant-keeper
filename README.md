# Plant Keeper (iOS)

Plant Keeper is a SwiftUI iOS app scaffold for tracking plants with urgency-based sorting, fast watering actions, camera-first add flow, and dual-language (EN/FR) plant names.

## Compatibility

- iPhone 14 Pro Max is supported.
- Minimum iOS version is 17.0 (required by SwiftData in this implementation).
- For `make deploy`, your device must be on iOS 17+.

## What is implemented

- SwiftUI list screen sorted by urgency.
- Inline per-row `Watered` button (`drop.fill`) using a shared service write path.
- Inline per-row `...` overflow menu with `Mark Checked`, `Edit`, `Delete`.
- `+` add flow with camera capture and editable review form.
- Hybrid AI analysis path: on-device first, OpenAI cloud fallback using user API key from Keychain.
- SwiftData persistence models and repository.
- CloudKit-enabled SwiftData model container configuration.
- Settings screen for OpenAI API key and home outdoor coordinates.
- Settings can autofill home coordinates from device location services.
- WeatherKit-powered outdoor weather snapshots (rain + temperature) feeding urgency adjustments.
- Daily digest + overdue reminder scheduling hooks.
- Core domain module (`PlantKeeperCore`) with urgency engine, weather adjustments, and plant service.
- Feature use-case layer (`PlantListUseCase`, `PlantEditorUseCase`, `SettingsUseCase`) so UI delegates business logic to shared flows.
- Unit tests for watering updates, urgency sorting, and weather adjustment rules.

## Project structure

- `Sources/PlantKeeperCore`: platform-independent domain logic.
- `Sources/PlantKeeperApp/Features/PlantList`: list use case orchestration.
- `Sources/PlantKeeperApp/Features/PlantEditor`: add/edit + AI draft use case orchestration.
- `Sources/PlantKeeperApp/Features/Settings`: settings form and save/load use case orchestration.
- `Sources/PlantKeeperApp/Services`: infrastructure adapters (SwiftData, WeatherKit, notifications, keychain, OpenAI client).
- `Sources/PlantKeeperApp/ViewModels` and `Views`: UI state + SwiftUI presentation.
- `Tests/PlantKeeperCoreTests`: domain tests.

## Notes

- Cloud OpenAI and WeatherKit integrations are wired; on-device analyzer remains a baseline placeholder.
- Keychain storage is implemented via `KeychainKeyStore`.
- `PlantListViewModel` is intentionally UI-focused; business logic lives in use cases and core services.
- `Makefile` includes `make build` and `make test` with repo-local cache/home paths for consistent local runs.
- `Makefile` includes `make build-sim` to compile the iOS Simulator build without installing/launching.
- `Makefile` includes `make coverage` to print Swift coverage and enforce a minimum threshold (`COVERAGE_MIN`, default `70`).
- `Makefile` includes `make clean` to reset build caches/artifacts (useful after moving/renaming the project folder).
- `Makefile` supports iPhone deploy config in a local `.env` file (created via `make ios-setup`).
- `Makefile` includes `make run-sim` (build/install/launch on iOS Simulator), `make deploy` (build/package/install/launch on a connected iPhone), and `make run-ios` (deploy + open iPhone Mirroring app on macOS).
- Place `logo.png` at the project root to have it displayed in-app and copied into simulator/device packaged app bundles.
- `prek` is configured through `.pre-commit-config.yaml`; install hook with `make prek-install` and run manually with `make prek-run`.
- `prek` includes local hooks for iOS plist validation (`make validate-ios-plist`) and coverage gate (`make coverage COVERAGE_MIN=70`).
- `make validate-ios-plist` verifies required iOS privacy keys are present and non-empty in both plist files and prevents template/static plist drift.
- Use Xcode (iOS 17+) to run the app target and wire real provider integrations.

## iOS Simulator and Device Deploy

### Run on iOS Simulator

1. List available simulator names:
   `make doctor`
2. Run on default simulator:
   `make run-sim`
3. Run on a specific simulator:
   `make run-sim SIMULATOR_NAME='iPhone 14 Pro Max'`
4. Build simulator binary only (no install/launch):
   `make build-sim`
5. `run-sim` opens the Simulator app automatically before launching the app.
6. If the requested simulator name is unavailable, the Makefile falls back to the first available iPhone simulator and prints which one was used.

### Deploy to iPhone (First-time setup)

1. Connect iPhone by cable (or trusted network pairing), unlock it, and trust this Mac.
2. On iPhone, enable Developer Mode:
   `Settings > Privacy & Security > Developer Mode`.
3. In Xcode:
   - Sign in with your Apple ID (`Xcode > Settings > Accounts`).
   - Open any iOS app target once and enable automatic signing for your Team to ensure development certificates/profiles exist.
4. Choose your signing mode:
   - Personal Team (no paid program): run any simple iOS app from Xcode once with Team set to your Personal Team and the same bundle id (`IOS_BUNDLE_ID`). This generates a local managed provisioning profile automatically.
   - Paid Apple Developer Program: export/download a development provisioning profile for your chosen bundle id.
5. Find your iPhone destination ID (preferred):
   `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer xcodebuild -scheme PlantKeeperApp -showdestinations`
   Use the physical iPhone entry (`platform:iOS, ... id:...`).
   Note: `make deploy` also accepts the `Identifier` value from `xcrun devicectl list devices` and maps it automatically.
6. Find your signing identity:
   `security find-identity -v -p codesigning`
7. Run interactive setup once:
   `make ios-setup`

This writes deploy variables into `.env` (gitignored), so future runs can use `make run-ios` without repeating flags.

### Deploy command

Use:
`make deploy DEVICE_UDID=<your-device-udid> CODE_SIGN_IDENTITY='Apple Development: Your Name (TEAMID)' MOBILEPROVISION_PATH=/absolute/path/to/profile.mobileprovision IOS_BUNDLE_ID=com.your.bundleid`

If your CloudKit container differs from the default:
`make deploy ... ICLOUD_CONTAINER=iCloud.com.your.container`

Notes:
- `IOS_BUNDLE_ID` must match the provisioning profile bundle id.
- `ICLOUD_CONTAINER` defaults to `iCloud.$(IOS_BUNDLE_ID)` in `Makefile`; it must match a CloudKit container included in your provisioning profile/capabilities.
- If install fails, verify Developer Mode, trust state, signing identity, and profile-device-team match.

### Personal Team Mode (Default)

- `DEPLOY_MODE` defaults to `personal`.
- In this mode, `make run-ios`/`make deploy` tries to auto-find an Xcode-managed profile in:
  `~/Library/MobileDevice/Provisioning Profiles`
- If none is found, create one by running any simple iOS app once from Xcode with:
  - Team = your Personal Team
  - Bundle Identifier = same as `IOS_BUNDLE_ID`
- Then rerun `make run-ios`.

### Run on iPhone with mirroring

Use:
`make run-ios`

If required values are missing, `make run-ios` now launches interactive setup and saves them to `.env`.
It then runs the deploy pipeline and opens the macOS `iPhone Mirroring` app.

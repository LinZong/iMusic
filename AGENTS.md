# Repository Guidelines

## Project Structure & Module Organization

- `Sources/iMusicKit/` is the shared SwiftPM library. Keep feature UI in `View/`, presentation state in `ViewModel/`, pure models in `Domain/`, and services in `Library/`, `Playback/`, `Import/`, `Sources/`, `Sync/`, and `Platform/`. `Application/AppModel.swift` assembles dependencies.
- `Apps/Shared/` contains native app entry points; `Apps/Resources/` contains icons and app localizations.
- `Web/WiFiUpload/` contains the React/TypeScript upload client. `Plugins/WiFiUploadBuild/` bundles its production assets during Swift builds.
- `Tests/iMusicKitTests/`, `UITests/iMusicUITests/`, and `Scripts/tests/` contain Swift, native UI, and Python regressions. UI hosts live in `Apps/Testing/`.
- Consult `Docs/Architecture.md` before changing state ownership or service boundaries.

## Build, Test, and Development Commands

Use full Xcode, Python 3.10+, and Node.js 22.12+. Native dependencies use SwiftPM; web dependencies use npm.

```sh
npm ci --prefix Web/WiFiUpload                 # Install locked web dependencies
npm run dev --prefix Web/WiFiUpload            # Local upload-page development
open iMusic.xcodeproj                         # Run iMusic or iMusicMac
swift test                                   # Package regressions
npm test --prefix Web/WiFiUpload              # Vitest regressions
python3 -m unittest discover -s Scripts/tests -p 'test_*.py'
./Scripts/run_ui_tests.py --macos             # Isolated native UI regressions
./Scripts/run_ui_tests.py --simulator '<UUID>' # iPhone/iPad UI regressions
./Scripts/build_macos_release.py              # Export macOS Release app
```

Device installation uses `Scripts/install_ios_release.py`; see `Docs/InstallRelease.md` for signing.

## Coding Style & Naming Conventions

Use four-space Swift indentation, 100-character lines, UpperCamelCase types, and lowerCamelCase members. Match filenames to feature types, such as `PlaylistDetailView.swift` and `PlaylistDetailViewModel.swift`.

Document every Swift member property and public method/initializer with English `///` comments; document exported TypeScript APIs and fields with JSDoc. Format Swift with `python3 Scripts/swift_style.py format` and web code with `npm run format --prefix Web/WiFiUpload`.

Add translated messages to `Localization/Strings.json`, then run `python3 Scripts/generate_localizations.py`. Before submission, run style checks, `Scripts/check_architecture.py`, and `Scripts/check_localizations.py` with Python.

## Testing Guidelines

Use XCTest/XCUIAutomation, Vitest/Testing Library, and Python unittest. Name Swift tests `*Tests.swift` with descriptive `test…` methods; web tests use `*.test.ts(x)`. Add meaningful behavior regressions; verify UI changes on iPhone, iPad, and macOS. Ordinary tests must remain silent. Real audio and iCloud acceptance require explicit opt-in; UI hosts do not certify either.

## Commit & Pull Request Guidelines

Use concise imperative commits matching history: `feat: …`, `fix: …`, or `refactor: …`. Follow `.github/pull_request_template.md`: explain behavior, link applicable issues, list actual validation/platforms, and attach sanitized screenshots for UI changes.

## Security & Data Ownership

Never commit signing secrets, personal media, or build products. Linked originals must remain untouched. Preserve lockfiles and third-party notices; report vulnerabilities through `SECURITY.md`.

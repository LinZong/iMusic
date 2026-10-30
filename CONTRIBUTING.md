# Contributing to iMusic

Thank you for helping improve iMusic. It is an actively developed native offline
music player for iPhone, iPad, and macOS. See [README.md](README.md) for prerequisites,
build instructions, supported features, and current limits.

## Issues and pull requests

Use GitHub Issues for reproducible bugs and feature requests. For bugs, include the
platform, OS version, device, app commit, reproduction steps, and expected result.
For playback problems, reproduce without LLDB using a Playback scheme and describe
the output route and audio format. Remove personal paths, identifiers, and private
library information from logs. Use an original or freely redistributable sample
when a test file is necessary; do not attach copyrighted music.

Discuss substantial behavior or architecture changes in an issue before spending
time on implementation. Keep pull requests focused, explain the resulting behavior,
and list the checks actually performed. Report vulnerabilities privately using
[SECURITY.md](SECURITY.md).

## Code organization and style

- Keep feature views in `View/` and their presentation state in `ViewModel/`.
  Follow the ownership rules in [Architecture.md](Docs/Architecture.md).
- Format owned Swift sources with `python3 Scripts/swift_style.py format`.
  The repository uses Xcode's `swift-format`, four-space indentation, and a
  100-character line limit. Do not reformat third-party sources.
- Document all Swift member properties and public methods/initializers with English
  `///` comments, including private properties and protocol APIs. Document exported
  TypeScript APIs and type fields with JSDoc. Explain purpose, units, state contracts,
  or relevant side effects instead of repeating a declaration's name.
- Add user-facing messages to `Localization/Strings.json` in all three languages,
  then run `python3 Scripts/generate_localizations.py`. See
  [Localization.md](Docs/Localization.md) for web message bindings and plural formats.
- Preserve the system appearance and platform interaction conventions. Check layout
  changes at compact and regular widths, with larger text and long translations.
- Never commit signing overrides, personal libraries, certificates, generated build
  products, or `node_modules`. Keep both package lockfiles in version control.

## Checks

Install web dependencies with `npm ci --prefix Web/WiFiUpload`, then run:

```sh
python3 Scripts/swift_style.py check
python3 Scripts/check_localizations.py
python3 -m unittest discover -s Scripts/tests -p 'test_*.py'
npm run format:check --prefix Web/WiFiUpload
npm test --prefix Web/WiFiUpload
swift test
```

Use the unsigned macOS and iOS simulator builds listed in the README when changing
shared or platform code. For conditional capabilities, also build the `iMusic Full`
scheme for an iOS simulator. CI runs these checks without requiring signing secrets.
Add regression tests when they can meaningfully demonstrate a behavior fix.

Ordinary tests must stay silent and use the controlled playback engine. The following
tests are deliberately opt-in; hardware audio fixtures contain zero-valued PCM:

```sh
IMUSIC_AUDIO_TESTS=1 swift test --filter AudioIntegrationTests
IMUSIC_PERFORMANCE_TESTS=1 swift test --filter PerformanceTests
```

`IMUSIC_SKIP_AUDIO_TESTS=1` forces hardware audio tests to skip. Do not enable hardware
tests in standard CI. Listen to real music only as an intentional manual device check.

After updating dependencies, run `swift package resolve`, install the npm lockfile,
and regenerate notices with `python3 Scripts/collect_licenses.py`. Include relevant
lockfile and notice changes in the pull request. Project generation is optional;
`Scripts/generate_project.rb` must not include machine-local signing configuration.

Contributions to the original project code are provided under the repository's
[MIT license](LICENSE). Preserve third-party notices and identify any newly added
third-party material and its license.

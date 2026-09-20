# Pantry

Pantry is an iOS 18 recipe browser and meal planner built with SwiftUI, SwiftData, and TheMealDB. It supports live search, category browsing, saved recipes, recently viewed recipes, offline images and API responses, and several planned meals per day.

## Requirements

- macOS with a recent Xcode version that supports iOS 18
- An iPhone Simulator or a signed physical device
- Internet access for the first recipe download

No API key or third-party package installation is required.

## Run the app

1. Open `Pantry.xcodeproj`.
2. Select an iPhone or iPad simulator.
3. Run the `Pantry` scheme.

For a physical device, choose your Apple development team and use a unique bundle identifier if Xcode requests one.

## Architecture

| Layer | Responsibility |
| --- | --- |
| `App` | Application startup and persistent-store recovery |
| `Views` | SwiftUI screens and reusable visual components |
| `ViewModels` | Browse and recipe-detail state transitions |
| `Network` | TheMealDB requests, decoding, errors, and response caching |
| `Models` | API data, instruction parsing, timing, and prep scheduling |
| `Persistence` | SwiftData models for saved, recent, and planned recipes |

The app never replaces the persistent store after an opening failure. It preserves existing data, logs the error, and presents a retry screen.

## Tests

Run the unit and UI suites:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test \
  -project Pantry.xcodeproj \
  -scheme Pantry \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest'
```

The UI tests use an isolated in-memory SwiftData store. Live TheMealDB contract tests are disabled by default; enable them with:

```sh
TEST_RUNNER_PANTRY_LIVE_API=1 xcodebuild test \
  -project Pantry.xcodeproj \
  -scheme Pantry \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest'
```

## Regenerate the project

The checked-in Xcode project is generated from `project.yml` using XcodeGen:

```sh
xcodegen generate
```

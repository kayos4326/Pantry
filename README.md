# Pantry

iOS Application Development (CSX4108), Assumption University

Team: Thar Lin Htet (6642062), Honey Linn (6726113), Su Eain Dray Myint (6726094)

Pantry is our recipe browser and meal planner for iOS 18. It uses [TheMealDB](https://www.themealdb.com) for recipe data and SwiftData for anything the user saves on the device.

You can browse or search for recipes, open full cooking instructions, save favourites, and plan several meals for a day. Saved and recently viewed recipes keep enough information to remain useful without a connection.

## Requirements

- Xcode with the iOS 18 SDK or newer
- An iPhone Simulator or a signed physical device
- Internet access for the first recipe download

No API key or third-party package installation is required.

## Getting started

1. Open `Pantry.xcodeproj`.
2. Select an iPhone or iPad simulator.
3. Run the `Pantry` scheme.

For a physical device, choose your Apple development team and use a unique bundle identifier if Xcode requests one.

## Project structure

- `App` starts the app and opens the SwiftData store.
- `Views` contains the screens and reusable SwiftUI components.
- `ViewModels` manages loading and screen state.
- `Network` calls TheMealDB and keeps a small response cache for offline use.
- `Models` contains API models and the recipe parsing logic.
- `Persistence` stores favourites, recent recipes, and meal plans.

If the saved-data store cannot open, Pantry shows a retry screen and leaves the existing data untouched.

## Tests

The project includes unit tests for networking, parsing, scheduling, and persistence, plus UI tests for the main user flows.

To run all tests from Terminal:

```sh
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer \
xcodebuild test \
  -project Pantry.xcodeproj \
  -scheme Pantry \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest'
```

UI tests use a separate in-memory store, so they cannot change normal app data. The live API checks are off by default because they require a network connection. To include them:

```sh
TEST_RUNNER_PANTRY_LIVE_API=1 xcodebuild test \
  -project Pantry.xcodeproj \
  -scheme Pantry \
  -destination 'platform=iOS Simulator,name=iPhone 17,OS=latest'
```

## XcodeGen

The Xcode project is already included. If you have XcodeGen installed, you can regenerate it after changing `project.yml`:

```sh
xcodegen generate
```

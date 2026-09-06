# Repository Guidelines

## Project Structure & Module Organization

- `TararebaToushi/` contains the SwiftUI application. `TararebaToushiApp.swift` is the `@main` entry point; `ContentView.swift` defines the initial screen and its `#Preview`.
- `TararebaToushi/Assets.xcassets/` holds the app icon, accent color, and future image/color assets.
- `TararebaToushi.xcodeproj/` defines the single application target and Debug/Release configurations. Its source folder uses Xcode filesystem synchronization; place new Swift files under `TararebaToushi/`.
- No test directories, external package dependencies, or build scripts are currently configured.

## Build, Test, and Development Commands

The project was created with Xcode 26.6, targets iOS 26.5+, and uses Swift 5 language mode. Use an Xcode installation with a compatible iOS SDK.

- `open TararebaToushi.xcodeproj`: open the project in Xcode. Select the `TararebaToushi` scheme and an iPhone or iPad simulator, then press **Cmd+R** to run.
- `xcodebuild -list -project TararebaToushi.xcodeproj`: inspect available targets, configurations, and schemes.
- Build for the simulator without device signing:

```sh
xcodebuild -project TararebaToushi.xcodeproj \
  -scheme TararebaToushi -configuration Debug \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/TararebaToushiDerivedData build
```

Use SwiftUI previews for quick layout feedback.

## Coding Style & Naming Conventions

Follow the existing four-space indentation and same-line opening braces. Use `UpperCamelCase` for types and matching filenames, and `lowerCamelCase` for properties and functions. Name view types with a `View` suffix and place chained modifiers on separate lines. Keep views focused and extract reusable components as screens grow. Default actor isolation is `MainActor`; respect that setting when adding concurrency. No SwiftLint or SwiftFormat configuration is present.

## Testing Guidelines

No automated testing framework, test target, or coverage threshold is configured. Validate changes with a simulator build and exercise affected screens on iPhone and iPad. When adding automated tests, create a unit-test target using Swift Testing or XCTest, name files `<Feature>Tests.swift`, and enable the target in the scheme before running **Cmd+U**.

## Commit & Pull Request Guidelines

Git history and a PR template are unavailable in this directory, so existing commit conventions cannot be verified. Use concise, imperative subjects such as `Add portfolio summary view`. Keep commits focused. PRs should describe behavior changes, link relevant issues, record validation performed, and include screenshots for UI changes. Exclude build output and personal Xcode state under `xcuserdata/`.

# Agent notes — FastWords

Conventions for coding agents working in this repository.

## After finishing app changes: always package + relaunch

When you complete a batch of changes that affect the running app (Swift sources under `Sources/`, resources, fonts, dictionary data, packaging scripts, etc.):

1. Ensure the project builds (`swift build` and/or `swift test` when logic changed).
2. **Always run the packaging script** — it builds `dist/FastWords.app`, **quits any running FastWords**, and **opens the new build** so the user can try it immediately:

   ```sh
   ./Scripts/package_app.sh
   ```

3. Tell the user the app was relaunched from `dist/FastWords.app` (menu bar `W` icon).

Do **not** wait for the user to ask for packaging or relaunch. Treat “package + relaunch” as part of “done”.

### When to skip packaging

- Pure docs / comments / plan files with no product binary impact.
- The user explicitly says not to package.
- Only tests or scripts that do not change the app binary (still package if unsure).

### Package without relaunch

```sh
./Scripts/package_app.sh --no-relaunch
# or
SKIP_RELAUNCH=1 ./Scripts/package_app.sh
```

### Full release zip (not automatic)

`./Scripts/release.sh` builds a versioned zip for GitHub Releases.  
Run that only when the user asks to **release / 发版**, not after every feature.  
Release packaging should not force-relaunch mid-CI; `release.sh` may call package with `--no-relaunch` if needed.

## Build & test

```sh
swift build
swift test
./Scripts/package_app.sh   # → dist/FastWords.app + quit old + open new
```

Requires Xcode command-line tools. Target: macOS 14+, Swift 6.

## Project shape

- `Sources/FastWordsCore` — pure logic (FSRS, dictionary, importer); unit-tested.
- `Sources/FastWords` — AppKit menu bar + SwiftUI UI; API keys in Keychain, not `state.json`.
- Data: local Application Support or iCloud Drive folder when sync is enabled.

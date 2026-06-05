# FastWords

FastWords is a native macOS menu bar vocabulary app built for fully local, user-owned word books.

## What works now

- Native menu bar app built with Swift, AppKit, and SwiftUI.
- Built-in sample word book for first launch.
- Import local `txt`, `csv`, or `json` word books.
- Sequential or random review.
- Mark words as mastered.
- Persist progress and settings in `~/Library/Application Support/FastWords/state.json`.
- Optional OpenAI-compatible AI insight generation, configured with your own endpoint, key, and model.

## Build

```sh
swift build
swift test
```

## Package as a macOS app

```sh
./Scripts/package_app.sh
open dist/FastWords.app
```

Xcode's command line tools or Xcode itself must be installed because the app links against the macOS SDK. The Xcode GUI is not required for normal development.

## Word book formats

Plain text:

```text
abandon	放弃
brisk	轻快的
```

CSV:

```csv
word,phonetic,meaning,example
abandon,/əˈbændən/,放弃,Do not abandon the tiny habit.
brisk,/brɪsk/,轻快的,Take a brisk walk before study.
```

JSON:

```json
[
  {
    "word": "abandon",
    "phonetic": "/əˈbændən/",
    "meaning": "放弃",
    "example": "Do not abandon the tiny habit."
  }
]
```

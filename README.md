# Mosby

A native macOS terminal emulator with AI-powered command completion and a persistent chat interface, built with SwiftUI.

![macOS 14.0+](https://img.shields.io/badge/macOS-14.0%2B-blue)
![Swift 5.9](https://img.shields.io/badge/Swift-5.9-orange)

## Features

- **Multi-session tabs** — manage multiple terminal sessions from a sidebar
- **AI command completion** — as you type, Mosby suggests completions using local history first, then falls back to an LLM via the OpenRouter API; accept with the Right Arrow key
- **Persistent chat panel** — a per-session AI chat interface backed by SwiftData
- **Global command history** — cross-session history with full-text search
- **Custom aliases & keybindings** — manage both from within the app UI
- **Dark theme** — native dark macOS appearance

## Requirements

- macOS 14.0 (Sonoma) or later
- An [OpenRouter](https://openrouter.ai) API key for AI features

## Building

### Development

```bash
swift build
swift run
```

### Release (creates a signed `.app` and `.dmg`)

```bash
./build.sh
```

The script compiles a release binary, assembles the `.app` bundle, signs it ad-hoc, and packages it into a `.dmg` disk image.

## Setup

1. Launch Mosby.
2. Open **AI Settings** from the menu and enter your OpenRouter API key and preferred model.
3. Aliases and keybindings can be customized from their respective menu items.

## Tech Stack

| Component | Library/Framework |
|---|---|
| UI | SwiftUI |
| Terminal emulation | [SwiftTerm](https://github.com/migueldeicaza/SwiftTerm) 1.11.2 |
| Chat persistence | SwiftData |
| AI completions & chat | OpenRouter API (streaming) |
| CLI argument parsing | Swift Argument Parser 1.7.0 |

## Project Structure

```
Sources/CustomTerminal/
├── main.swift / App.swift / AppDelegate.swift
├── Models/          # State stores (sessions, chat, AI, aliases, keybindings, history)
├── Services/        # AIService (OpenRouter streaming client)
└── Views/           # SwiftUI views (terminal, chat panel, sidebars, settings)
```

## License

MIT

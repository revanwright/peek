# AI Usage Tracker

A native macOS menu bar app that shows how much of my Claude plan limit I've used, built with SwiftUI.

**Status:** in progress. The Claude limit reading and the dropdown are working; Claude Code session status, notifications, and AI-app time tracking are next.

## What it does

- **Menu bar ring** that fills up with your current 5-hour Claude usage and shifts from green to orange to red.
- **Dropdown** with rings for the current session and the weekly limit, plus reset times.
- **Settings window** with standard Mac tabs: General, Sources, Notifications, Account.
- Full light and dark mode support, using system fonts and materials.

## How the limit reading works

Anthropic doesn't offer an official API for plan usage, so the app reads the same data claude.ai's own Usage page uses:

1. You sign in once in a small window showing claude.ai's real sign-in page.
2. The resulting session key is stored in the macOS Keychain. Nothing else about your login is saved to disk.
3. Every few minutes, a hidden copy of Safari's web engine asks claude.ai for your usage, so requests look like ordinary browser traffic.

Because this relies on an undocumented endpoint, it can break if claude.ai changes. The app shows your last reading with a warning if an update fails.

## Building

No Xcode required, only Apple's free Command Line Tools.

```bash
./scripts/run.sh                 # build, install to ~/Applications, and launch
./scripts/snapshot-design.sh     # save light/dark screenshots with sample data to build/design-shots
```

Notes:

- The build uses the macOS 26 SDK. The macOS 27 SDK's SwiftUI needs a compiler plugin that only ships with Xcode.
- If a code-signing certificate named `AI Usage Tracker Dev` exists in your login keychain, builds are signed with it; otherwise they're signed ad hoc.
- Diagnostic log: `~/Library/Logs/AIUsageTracker/app.log` (never contains secrets).

## Project layout

```
Sources/AIUsageTracker/
  App/          App entry point and design-preview mode
  ClaudeLimit/  claude.ai sign-in, usage reading, and refresh schedule
  Dashboard/    Menu bar icon and dropdown
  Design/       Shared colors, spacing, and the ring gauge
  Settings/     Settings window and saved preferences
  Support/      Keychain, logging, login item, helpers
```

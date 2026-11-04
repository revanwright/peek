# AI Usage Tracker

A native macOS menu bar app that shows how much of my Claude plan limit I've used, built with SwiftUI.

**Status:** feature-complete for its first version: Claude limit reading, the dropdown, live Claude Code and Cowork status, notifications, and time tracking for other AI apps.

## What it does

- **Menu bar ring** that fills up with your current 5-hour Claude usage and shifts from green to orange to red.
- **Dropdown** with rings for the current session and the weekly limit, plus reset times.
- **Sessions**: each open Claude Code session's project and status (working, needs permission, waiting for your reply, finished), reported by Claude Code hooks. Works in the terminal, the VS Code extension, and the Claude desktop app's Code tab. Cowork tasks in the Claude app are listed too (working, waiting for your reply, finished).
- **AI Apps Today**: time spent in other AI apps (ChatGPT, Muse, or any app you add), counted only while the app is in front and you're actually at the Mac (pauses when idle 2+ minutes, locked, or asleep). No special permissions needed.
- **Notifications** when you reach your warning level (80% by default), when a limit you pushed past it resets, and when a Claude Code session needs you.
- **Settings window** with standard Mac tabs: General, Sources, Notifications, Account.
- Full light and dark mode support, using system fonts and materials.

## How the limit reading works

Anthropic doesn't offer an official API for plan usage, so the app reads the same data claude.ai's own Usage page uses:

1. You sign in once in a small window showing claude.ai's real sign-in page.
2. The resulting session key is stored in the macOS Keychain. Nothing else about your login is saved to disk.
3. Every few minutes, a hidden copy of Safari's web engine asks claude.ai for your usage, so requests look like ordinary browser traffic.

Because this relies on an undocumented endpoint, it can break if claude.ai changes. The app shows your last reading with a warning if an update fails.

## How Claude Code status works

Claude Code can run a command on events like "a prompt was sent" or "Claude stopped" ([hooks](https://code.claude.com/docs/en/hooks)). The app ships a tiny helper, `ai-usage-hook`, that records each session's latest status in `~/Library/Application Support/AIUsageTracker/sessions/`. The helper prints nothing (hook output can reach Claude's conversation) and always exits immediately.

Cowork runs Claude Code with its own settings folder per task, so hooks don't fire there. Instead the app reads each Cowork task's turn log in the Claude app's data folder (the turn types only, never the text) to tell whether Claude is working, asking a question, or done. This relies on undocumented files.

Regular Claude chats aren't shown: they have no hooks, and the Claude app doesn't record when a reply starts or finishes.

Settings → Sources → **Connect** adds the hooks to `~/.claude/settings.json` (backing the file up first); **Disconnect** removes only the app's own entries.

## Building

No Xcode required, only Apple's free Command Line Tools.

```bash
./scripts/run.sh                 # build, install to ~/Applications, and launch
./scripts/snapshot-design.sh     # save light/dark screenshots with sample data to build/design-shots
./scripts/make-icon.sh           # redraw the app icon (design lives in scripts/make-icon.swift)
./scripts/test.sh                # run the checks (Cowork status rules, app-time counting rules)
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
  ClaudeCode/   Live session list (hook helper + Cowork task logs), hook install/remove
  Notifications/ Usage warnings, reset pings, and session nudges
  AppTime/      Time in other AI apps (counting rules in AppTimeLedger)
  Dashboard/    Menu bar icon and dropdown
  Design/       Shared colors, spacing, and the ring gauge
  Settings/     Settings window and saved preferences
  Support/      Keychain, logging, login item, helpers
Sources/Hook/   ai-usage-hook, the helper Claude Code runs for each hook event
Tests/          Checks run by scripts/test.sh
```

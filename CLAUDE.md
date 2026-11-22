# CLAUDE.md

Guidance for Claude Code working on Dyogène.

## What this is

Dyogène is a local, privacy-first macOS app that shows what takes space on the disk: a zoomable
map where area is size and "dust" is time since last use, a list of the heaviest items, and
known reclaimable places ("suspects"). It ships a metadata-only CLI (`dyogene`) and a Claude
skill (`skill/dyogene`). It is a cousin of Hector and Gustave (github.com/0xRD).

Read, in this order: `SPEC.md`, `SECURITY.md`, `docs/DESIGN.md`, `docs/DECISIONS.md`, `TASKS.md`.

## Hard rules (never break these, never "temporarily")

1. No network code of any kind. No URLSession, no sockets, no update checker, no analytics,
   no crash reporter. The scanner refuses to download iCloud placeholders.
2. Never read file contents. Scans use metadata only (`getattrlistbulk`). The only code that
   opens a file for writing is the secure erase, after the user confirmed it.
3. No third-party dependencies. `Package.swift` must never gain one.
4. No privileged helper, no entitlements. Full Disk Access is optional and granted by the user.
5. Every destructive action goes through `FileRemover`, which re-checks `RemovalPolicy`.
   Destructive buttons are never a single click: hold to confirm, in a sheet where Cancel is
   the default. The CLI has no destructive command.
6. The UI, docs and code are in English. No em dashes anywhere.
7. README images come only from demo mode (`DYOGENE_DEMO=1`), never from a real scan.
8. Do not add features that are not in `SPEC.md` without asking.

## Architecture

- `Sources/DyogeneCore`: scanner, tree model, treemap layout, analysis (hoard, suspects),
  removal policy and remover, JSON reports, demo data. No AppKit or SwiftUI. Unit tested.
- `Sources/DyogeneApp`: SwiftUI + AppKit. View state lives in `@Observable` models.
- `Sources/dyogene`: the CLI for the skill, shipped in `Dyogene.app/Contents/Helpers/dyogene`.
- `skill/dyogene/SKILL.md`: the Claude skill, installed by `scripts/install-skill.sh`.

## Toolchain (this Mac: Command Line Tools only, no Xcode)

- Run tests with `scripts/test.sh` (plain `swift test` misses the Swift Testing plugin path).
- Never use `@State` in the app target (it is an Xcode-only macro in this SDK): keep view state
  in `@Observable` classes owned by the app or the window.
- `scripts/check.sh`: release build with zero warnings, then tests. Run before each commit.
- `scripts/build-app.sh` signs with the "Dyogene Local Signing" certificate
  (`scripts/make-cert.sh`) so Full Disk Access survives rebuilds.
- Debug env vars: `DYOGENE_DEMO=1` (demo data), `DYOGENE_SCREEN=map|hoard|suspects`,
  `DYOGENE_APPEARANCE=light|dark`, `DYOGENE_SELECT=<relative path>`, `DYOGENE_SHEET=trash|permanent|secure`.
- Check UI with `screencapture -o -l <windowid>`.

## Workflow

Commits as `0xRD <29817618+0xRD@users.noreply.github.com>` with a Claude co-author trailer.
Never push without asking. GitHub Actions minutes are limited: verify locally, no automatic CI.

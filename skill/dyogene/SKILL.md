---
name: dyogene
description: Find what takes space on this Mac and where to clean up, using the Dyogène app's metadata-only CLI (names, sizes, dates; never file contents). Use when the user asks why their disk is full, what is big or forgotten, what they can delete, or wants help tidying their Mac's storage.
---

# Dyogène: help the user win back disk space

Dyogène ships a command line tool that reports **metadata only**: names, sizes, dates and a
guessed kind. It never reads file contents and it has **no command that deletes or moves
anything**. You help the user decide; the user removes things themselves, in the Dyogène app
(which asks for a confirmation and a long press) or in Finder.

## Find the tool

Use the first that exists:

1. `/Applications/Dyogene.app/Contents/Helpers/dyogene`
2. `~/Applications/Dyogene.app/Contents/Helpers/dyogene`
3. `dyogene` on the PATH

If none exists, tell the user Dyogène is not installed and stop.

If the tool is killed right away (exit code 137), macOS has not allowed the app yet: ask the user
to open Dyogène once and click "Open Anyway" in System Settings, Privacy & Security. Do not
remove quarantine attributes yourself.

## Rules (always)

- **Never read file contents** (no `cat`, `head`, Read tool, `strings`, hashes, Quick Look,
  opening documents) unless the user explicitly asks about one specific file. Names, sizes and
  dates are enough to advise.
- **Never delete, move, rename, empty the Trash or run cleanup commands yourself** (`rm`,
  `trash`, `brew cleanup`, `docker system prune`, `xcrun simctl delete`...). Suggest them; the
  user runs them or removes items in Dyogène.
- **Paths can be personal.** Keep them in this conversation. Do not send them to any web search,
  tool or service. Quote only what you need.
- Do not run the tools with `sudo`.
- macOS may ask the user for permission the first time folders like Desktop or Downloads are
  scanned. Say so before the first scan.

## Workflow

1. **One scan for the overview.** Run `dyogene report` (scans the home folder, takes seconds).
   Add `--path DIR` for another folder. It returns JSON with:
   - `summary`: disk use, how much the scan saw (`notSeenByScan`), `fullDiskAccess`, split by
     kind (`byKind`) and by time since last use (`byAge`), largest folders.
   - `largestItems`: heaviest files and packages (apps, libraries).
   - `foldersOfFiles`: folders whose weight is the files directly inside.
   - `unusedForAYear`: large items nobody opened or changed for a year.
   - `suspects`: known reclaimable places with `risk` (low, medium, high), what they are
     (`explanation`), what removing costs (`consequence`) and `advice`.
2. **Drill down when useful:** `dyogene tree DIR --depth 2`, `dyogene top --path DIR --limit 20`,
   `dyogene stale --older-than 6m --min-size 500MB`, `dyogene top --folders`.
3. **Advise.** Lead with the biggest wins, grouped:
   - Low risk first (caches, build data, installers, Trash), with the exact place and size.
   - Then large, long-unused personal items: the user decides; suggest archiving to an
     external drive instead of deleting when it may matter (videos, photos, projects).
   - Medium and high risk items with their consequence spelled out (simulators, VM disks,
     device backups). Prefer the tool's own cleanup when `advice` gives one.
   Give sizes, ages ("untouched for 2 years") and the honest consequence. Never invent what a
   file contains: say "a 38 GB video file", not what it shows.
4. **Help them act.** Offer `dyogene reveal PATH` to select an item in Finder, or tell them to
   find it in Dyogène (Hoard or Map), where they can move it to the Trash with a long press.
5. If `summary.fullDiskAccess` is false and `notSeenByScan` is large, explain that protected
   folders (Mail, Messages, app containers) were skipped and that granting Full Disk Access to
   Dyogène in System Settings shows them.

## Output reference

Every entry: `path`, `name`, `type` (file, folder, package, group-of-small-files, symlink),
`size` (bytes on disk), `sizeText`, `lastUsed` (date), `lastUsedAge`, `kind`, `items`.
"Last used" is the newest of the access and modification dates: a folder is as recent as its
most recent file.

Sizes are allocated bytes, like Finder's "on disk". APFS clones may be counted twice.

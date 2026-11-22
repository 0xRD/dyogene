# Dyogène specification

## Purpose

Show, at a glance, what takes space on a Mac and what has been forgotten, and make acting on
it one click away (reveal in Finder) while making accidental deletion impossible.

## Screens

1. **Map.** Squarified treemap of the focused folder, nested as deep as space allows.
   - Area is size on disk. Colour depends on the lens:
     - Dust (default): fresh is teal, old is sand with grain. A folder is as fresh as its most
       recently used content.
     - Kind: videos, photos, audio, apps, archives and installers, disk images and VMs,
       developer, caches, documents, other.
     - Plain: neutral.
   - Hover lights a tile (the lantern) and shows name, size, share of parent, last use.
   - Click selects (inspector), double click or Return zooms in, Escape or Cmd+Up zooms out,
     breadcrumb jumps to any ancestor.
   - Items too small to see are grouped into one "N smaller items" tile.
   - Folders Dyogène cannot see are shown as such ("needs Full Disk Access", "unreadable",
     "in iCloud", "other volume").
2. **Hoard.** The 100 heaviest items (files and packages, or folders of files), with filters
   (unused for, kind, minimum size). Each row reveals in Finder in one click.
3. **Suspects.** Known reclaimable places with what they are, what removing them costs, and a
   risk level.
4. **Settings.** Scan location, exclusions, Full Disk Access status.

A volume gauge shows used space split into what the scan saw and what it did not (system,
other users, snapshots, protected folders), purgeable space and free space.

## Actions

Reveal in Finder, Open, Quick Look, Copy Path. Destructive actions, each in a sheet:

| Action | Confirmation | Notes |
| --- | --- | --- |
| Move to Trash | hold 1.5 s | "Put back" offered afterwards |
| Delete Permanently | checkbox + hold 2 s | |
| Erase Securely | checkbox + hold 3 s | overwrite with random data, flush, delete. Best effort on SSD, the sheet says why and shows FileVault, snapshots and Time Machine status |

`RemovalPolicy` refuses system folders, the home folder and its standard folders, mount
points, other users' files.

## CLI and skill

`dyogene report|summary|top|stale|suspects|tree|reveal`, JSON by default. Metadata only, no
destructive command. The skill tells Claude to never read contents unless asked for a given
file, never delete, and to treat paths as personal.

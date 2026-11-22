# Security and privacy

## What Dyogène does and does not do

- No network access of any kind. There is no networking code in the app or the CLI.
- Scans read metadata only (names, sizes, dates, flags) with `getattrlistbulk`. File contents
  are never read. Spotlight's "last opened" date is read for the items on screen.
- The scanner tells the kernel never to download iCloud placeholders
  (`IOPOL_MATERIALIZE_DATALESS_FILES_OFF`) and does not list folders that are only in iCloud.
- Scan results stay in memory. Nothing is written to disk.
- No helper, no root, no entitlements. Full Disk Access is optional; without it, folders
  macOS protects are skipped and shown as such instead of triggering permission prompts.
- The `dyogene` CLI cannot delete, move or write anything (except selecting a file in Finder
  with `reveal`).

## Removal safety

All removals go through `FileRemover`, which re-checks `RemovalPolicy` on every call. The UI
needs a press-and-hold of 1.5 to 3 seconds inside a sheet where Cancel is the default button;
Return never confirms.

## About "Erase Securely"

Overwriting a file before deleting it was reliable on spinning disks. On the SSDs and APFS
volumes of current Macs it is **best effort**:

- SSDs spread writes over spare cells (wear levelling): the old cells may keep the old data
  until the drive erases them.
- APFS is copy-on-write: the overwrite may land in new blocks, and clones or snapshots of the
  file keep the old blocks.
- Local Time Machine snapshots, Time Machine backups and cloud copies are not touched.

Apple removed `srm` and "Secure Empty Trash" for these reasons. What makes deleted data
unrecoverable on a Mac is **FileVault**: everything on disk is encrypted, and freed blocks are
trimmed. Dyogène shows the FileVault, local snapshot and Time Machine status before an erase.
Erase refuses hard-linked files (their other names would keep the content) and iCloud
placeholders.

## Full Disk Access probe

Dyogène checks Full Disk Access by opening, and immediately closing without reading,
`~/Library/Application Support/com.apple.TCC/TCC.db`.

## Reporting

Report vulnerabilities privately through GitHub security advisories on the repository.

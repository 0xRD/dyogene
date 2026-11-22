# Decisions

D1. **No helper, optional Full Disk Access.** A root helper walking the whole disk is a large
privilege for a viewer. The app runs as the user; the volume gauge shows what it could not see.

D2. **getattrlistbulk, metadata only.** One call returns names, types, dates and allocated
sizes of many entries. Home folder of 500 GB and 820k files: 3.9 s, 270 MB peak on an M-series
Mac (2026-11-22). Totals match `du -sk` exactly on a 46 GB folder.

D3. **Small files are grouped.** Per folder, the 16 largest files and every file of 512 KB or
more stay as nodes; the rest become one "N small files" node. Keeps memory bounded on trees
with millions of files; the map groups them anyway.

D4. **Protected folders are skipped without Full Disk Access.** Opening
`~/Library/Containers/<other app>` blocks inside `open()` until the user answers a "would
like to access data from other apps" prompt. A scan without Full Disk Access hung there.
Those folders are now skipped and marked "needs Full Disk Access"; directory reads run on
their own OperationQueue so a blocked read never holds the Swift concurrency pool.

D5. **Size is allocated size.** Like `du` and Finder's "on disk". APFS clones share blocks and
are counted once per name, so totals can exceed real use; the UI says so.

D6. **Last used = newest of access and modification dates**, from the scan. Spotlight's
`kMDItemLastUsedDate` is read lazily for the inspector and the Hoard. Unknown dates count as
fresh (no dust without evidence).

D7. **Secure erase is offered, honestly labelled best effort.** See SECURITY.md.

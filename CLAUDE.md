# Ream

> Scan paper documents into clean, searchable PDFs. Free forever, entirely on-device.

## Quick Reference
- **Language:** Swift 6, SwiftUI
- **Min deployment:** iOS 26.0
- **Pattern:** MV (Model-View) — no per-view ViewModels
- **Dependencies:** None — all first-party Apple frameworks
- **Bundle ID:** `com.lavailabs.ream`
- **Project:** XcodeGen (`project.yml`) — `.xcodeproj` is generated and gitignored

## Build & test
```bash
xcodegen generate   # after any file add/remove or project.yml change
set -o pipefail; xcodebuild -scheme Ream \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' build 2>&1 \
  | grep -q "BUILD SUCCEEDED" && echo BUILD_OK
xcodebuild test -scheme Ream -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max'
```
Never gate on `grep error:` — it exits 0 on a match, and a broken build shipped in riplist
that way. `ReamTests` is a **hosted** unit-test target (Swift Testing), so SwiftData and the
bundle resolve exactly as they do at runtime.

## What this app is reacting to

Every incumbent scanner app (CamScanner, Adobe Scan, iScanner, Genius Scan) monetizes
through weekly subscriptions, watermarks on the free tier, full-screen video ads, or
paywalling *combine-into-one-PDF* — the literal core use case. iScanner users report
being charged the moment they tap a "free" trial.

Ream's entire product position is the negative space around that. These are product
constraints, not preferences — do not erode them:

- **No subscription.** Ever. The Supporter unlock is a one-time non-consumable.
- **No account, no cloud, no network calls.** Scans never leave the device.
- **No watermarks, no ads.**
- **No feature gating.** Free tier == all features.
- **No paywall on launch or before a scan.**

Marginal cost of running this app is $0, so none of the above requires a business
justification.

## Architecture

MV pattern. Views observe SwiftData directly via `@Query`. Services are stateless enums or
actors; only `ScanPipeline`, `SupporterService`, `Engagement` and `CrossPromoState` are
`@Observable`, because they own transient or cross-screen state.

**The scan flow, in order:**
1. `DocumentCameraView` — `VNDocumentCameraViewController` wrapper → `[UIImage]`
2. `OCRService` — `RecognizeDocumentsRequest` per page → `[PageOCR]`
3. `PDFBuilder` — images + OCR lines → searchable PDF `Data`
4. `DocumentStore` — writes the PDF to disk (**before** the SwiftData insert)
5. `ScanPipeline` — inserts `ScannedDocument`, explicit `context.save()`

Step ordering matters: if the SwiftData row were inserted first and the file write
failed, the library would list a document whose PDF doesn't exist.

## Project Structure
```
Ream/
  App/          ReamApp.swift, StoreManager.swift
  Models/       ScannedDocument, ScanLabel  (SwiftData @Model)
  Services/     DocumentCameraView, OCRService, PDFBuilder, DocumentStore, ScanPipeline,
                ThumbnailService, SupporterService, Engagement, CrossPromoState,
                BackupArchive, LibraryManifest, OrphanRecovery, MarkupRenderer,
                FieldSuggester, InboundDocument, SampleScans (DEBUG)
  Views/        DocumentListView, DocumentDetailView, SettingsView, SupporterView,
                LabelPickerView, LabelManagerView, CrossPromoView, OnboardingView,
                FillSignView
    Components/ ReamRow, LabelChip, DocumentThumbnail, ShareSheet, SignatureCanvas,
                OnboardingArt
  Resources/    Assets.xcassets
  Theme.swift   design tokens + AccentFinish + AppearanceMode
ReamTests/      hosted unit tests (Swift Testing)
spike/          standalone Swift CLI that validated the searchable-PDF pipeline
```

## The searchable PDF (the only hard part)

`PDFBuilder` draws the scanned image, then draws the OCR'd text on top in **invisible
render mode** (`CGTextDrawingMode.invisible`) positioned at each line's Vision bounding
box. Result looks like a flat image but is fully selectable and searchable.

Non-obvious details, all of which cost real debugging time — don't undo them:

- **UIKit's PDF context is top-left origin.** Vision reports bounding boxes bottom-left.
  `PDFBuilder` flips the context once up front so both live in the same space, then uses
  `NormalizedRect.toImageCoordinates(_:origin:.lowerLeft)`.
- **Font must be scaled per line** so the glyph run spans the width Vision reported.
  Skip this and selection highlights drift off the words they cover.
- **Use `.invisible`, not clear-colored text.** Some PDF tools strip clear text as a no-op.
- **Never JPEG-compress document scans.** Measured: JPEG q=0.7 produced *larger* files
  than lossless (217 vs 183 KB/page), and q=0.4 visibly degraded glyph edges. JPEG is
  tuned for photographs. Grayscale lossless is the default at ~117 KB/page.

To re-validate the pipeline outside the app:
```bash
cd spike && swiftc -O main.swift -o ream-spike
./ream-spike gen page.png && ./ream-spike scan 1.0 out.pdf page.png
pdftotext -layout out.pdf -    # text should extract with columns intact
```

## Fill & Sign

`MarkupRenderer` burns typed text and drawn signatures into a PDF. **The load-bearing
decision is how the original page is carried across:** it is drawn with
`PDFPage.draw(with:to:)` into a **PDF** context, which copies the page's operators rather
than its pixels. Rasterizing instead — the obvious implementation — would silently destroy
the invisible OCR layer, making a filled form unsearchable forever with nothing looking
wrong. `MarkupRendererTests` asserts exactly this and names the cause in its failure message.

Filled text is drawn as real text, not an image, so a completed form is searchable too.
`render` returns **nil** (never empty `Data`) on an unreadable source, so a failure can't
overwrite a real document with a blank one.

Placement is **free**, not detected. A scan of paper has no fields; `FieldSuggester` only
*suggests* — it reads the line boxes Vision already produced and applies text heuristics
(a line ending `Name:` has a blank to its right; a run of underscores is a blank). No new
computer vision, and it degrades to the existing free placement when it finds nothing.
Guarded against false targets: prose ending in a keyword is rejected, labels with no room
are skipped, overlapping targets on one line collapse.

Editor positions markups against a rasterized preview; saving re-renders from the untouched
original. Markups are stored **normalized to the page**, since those two coordinate spaces
differ.

**Markups are editable, not welded in.** `MarkupStore` keeps two files per marked-up
document: `Scans/<id>.pdf` (flattened — what the viewer, thumbnails, share, search and
export all read, unchanged) and `Scans/originals/<id>.pdf` (the pristine scan, written once
before the first flatten). ⚠️ **Every save re-renders from the ORIGINAL**, never from the
current file, or edits compound: moving a signature twice would leave a ghost at the first
position. Markup metadata lives on `ScannedDocument.markupData` and in the manifest;
drawings are PNGs in `Scans/markups/`. Both directories are inside `Scans/`, so the export
ZIP carries them and a restored backup gets **editable** markups rather than a flat page.
Deleting a document must call `MarkupStore.purge` or the original and its drawings outlive it.

⚠️ **Gesture note:** the editor uses ONE `DragGesture(minimumDistance: 0)` for touch-down,
drag and tap. A separate `.onTapGesture` plus a distance-gated drag meant the tap could only
be recognised after the drag declined the touch, so nothing acknowledged the finger until it
had moved. Also: `translation` is cumulative from gesture start — anchor to the origin
captured at touch-down, never to the current one, or it compounds and flings the markup off
the page.

## Asking the user for things

`Engagement` returns **at most one** prompt per completed scan, priority
**review > supporter > cross-promo**, so a single scan can't stack three asks.

- **Review** milestones escalate: 10 / 45 / 130, min 45 days apart. iOS caps `requestReview`
  at **3 prompts per 365 days** and silently ignores the rest, so a fixed "every N" cadence
  doesn't ask more often — it spends the year's budget in month one on the least experienced
  users. Never retry: a failed prompt is indistinguishable from a shown one.
- **Supporter pitch** at 5 / 30 / 60 / 110, then every 100, min 7 days apart. Early first ask
  is deliberate (peak goodwill); the widening gaps are the trade. Stops permanently once
  `isSupporter`. It is the only thing in the app that asks for money.
- A "scan" is one completed capture session regardless of page count. **Imports count too**
  (settled 2026-08-08) — same value delivered.

## Inbound documents

`CFBundleDocumentTypes` declares PDF + images, which is what puts Ream in the share sheet's
app row, "Open in…", and Files' open-with menu — **no extension target needed**. A Share
Extension would only add an inline UI on top of this.

`onOpenURL` is handled in `DocumentListView`, not at the app root, so an inbound file drives
the SAME `ScanPipeline` as a camera scan and therefore shows the same progress overlay.
Inbound files are security-scoped; `startAccessingSecurityScopedResource` is required or the
read silently returns nothing. **`simctl openurl` cannot simulate this** — verification needs
a device.

## Vision notes

Uses `RecognizeDocumentsRequest` (iOS 26+), **not** `VNRecognizeTextRequest`. The old API
returns unordered line fragments — a two-column invoice comes back interleaved and tables
lose their structure. The new one resolves reading order and exposes `.tables`, `.lists`,
`.barcodes`, and `.title`. Document auto-naming uses `.title` / `isTitle`.

Pages are OCR'd **sequentially**, not concurrently. Vision already saturates the Neural
Engine on one request; fanning out mostly adds memory pressure on a 20-page scan.

## Data safety — the layers, and why each exists

**The invariant: the app may fail to open your data, but it may never destroy it trying.**

1. **Versioned schema from commit one.** `ReamSchemaV1` + `ReamMigrationPlan` in
   `StoreManager`. Never `.modelContainer(for:)` — it `fatalError`s on a failed migration,
   crash-looping the app and leaving the user unable to even export. Retrofitting versioning
   after ship is a sequenced two-release migration; poke-rip's cost a user their collection.
2. **Quarantine, never delete.** A failed open moves the store to `broken-<ISO-date>/` intact
   and boots an empty container.
3. **Pre-open snapshots**, ~7 daily, rotated, in `Application Support/Ream/Backups/`. Copied
   *before* the container exists so the files are quiescent — no WAL hazard. Never set
   `isExcludedFromBackup` on any of it.
4. **Shrink tripwire.** A launch that starts from zero rows does NOT snapshot while non-empty
   snapshots exist. Without it, a library emptied by accident is faithfully snapshotted as
   empty and seven launches later every good copy has rotated out — the backup system
   becomes the thing that destroys the data. Delete-all is the one exempt caller
   (`markIntentionalWipe`).
5. **`OrphanRecovery` — the layer the siblings can't have.** In riplist/PokeArtist the store
   *is* the collection. Here the PDFs are the artifacts and live as ordinary UUID-named
   files, so a lost store costs metadata, never a document. It runs on **every** launch, and
   covers four failures at once: a quarantined store, a restored snapshot predating a scan, a
   kill between writing the PDF and saving the row, and files copied back via Files.app.
6. **`manifest.json` lives INSIDE `Documents/Scans/`.** That's the whole trick — it rides
   along in the export ZIP for free, sits beside the PDFs in Files.app, and is what recovery
   reads to restore titles, labels and transcripts. ⚠️ **Rebuild it after any mutation that
   changes what a scan is** (create, rename, relabel, delete); a stale manifest makes the next
   launch try to re-adopt deleted documents.
7. **Round-trip test.** `ReamTests/LibraryManifestTests` is what keeps the format honest — a
   field added to `ScannedDocument` and forgotten in `LibraryManifest.Entry` silently stops
   surviving a backup, and nothing else would notice.

Verified end-to-end by corrupting `Ream.store` with garbage and relaunching: store
quarantined, all documents re-adopted with labels and transcripts intact, user informed.

## Data

SwiftData holds metadata + the OCR transcript. PDFs live in `Documents/Scans/` and are
exposed to Files.app (`UIFileSharingEnabled`) so users can get their documents out
without the app's cooperation.

The transcript is intentionally duplicated between SwiftData and the PDF's invisible
layer — it makes search a `@Query` predicate instead of parsing every PDF per keystroke.

**Always call `try? context.save()` explicitly** after mutating a document. Autosave has a
~3 second delay and a scan is user-created content that cannot be regenerated.

## Monetization

`SupporterService`, **RevenueCat** (matching PokeArtist and the -rip family). ⚠️ The API key
in `SupporterService.apiKey` is a placeholder — replace it with Ream's own public `appl_` key
or offerings resolve empty and no tiers appear. Entitlement identifier is `Supporter`,
case-sensitive; if it disagrees with the dashboard every supporter silently becomes a
non-supporter.

Source of truth is `CustomerInfo`, never local storage. The owned-products fallback after the
entitlement check is NOT redundant: an entitlement that hasn't propagated would otherwise lock
out someone who has already paid.

**Three tiers, identical entitlement, all NON-CONSUMABLE:**
`…supporter` ($2.99), `…supporter.plus` ($4.99), `…supporter.max` ($9.99).

Three rather than two for **anchoring** — the top tier's job is not to be bought, it's to
make the middle read as modest. With two options most people take the lower one. (PokeArtist
went the other way, cutting three membership levels to two; that was a different case, where
the levels carried real perceived weight and the floor was $9.99. Here every tier grants the
same thing, so there is no decision to agonise over, only "how much.")

They stack, so someone can tip once now and again later and keep both. That is also why
entitlement is a plain `Bool` and not a level: nothing grants more than anything else, so
there is no tier to demote anyone to when a second purchase lands. `Ream.storekit` drives
the simulator.

**They must stay non-consumable.** A consumable that grants permanent functionality is a
guideline 3.1.1 rejection, and with no accounts and no cloud an Apple ID restore is the only
way a supporter who reinstalls gets their finishes back. This is the same call already
settled in PokeArtist. A pure tip jar granting *nothing*, if ever wanted, is a separate
consumable. `restore()` is required and wired.

**Supporting unlocks accent finishes and nothing else.** Never gate a scanning, OCR, PDF or
export feature — the free tier is the whole product.

Apple requires this to go through IAP; an external "buy me a coffee" link is a 3.1.1
rejection. Commission is 15% under the Small Business Program.

## Labels

`ScanLabel` — named that, **not `Label`**, because SwiftUI owns that name and the collision
is silent (`Label("Taxes")` resolves to the wrong type inside a view body).

Many-to-many with `ScannedDocument` via `document.labels` / `label.documents`.
⚠️ **The delete rule is `.nullify` and must stay that way.** `.cascade` would mean deleting
a label destroys every document filed under it — data loss wearing the costume of a tidy-up.

Filtering is **OR across selected labels**, not AND. Picking Taxes + Medical means "show me
both piles"; AND would return almost nothing, since documents rarely carry two specific
labels at once. When a filter hides everything the list says so explicitly — otherwise it
reads as an empty library and the user goes hunting for scans they still have.

Chips render as the color's text on a 15% tint of itself, so the contrast pair that matters
is **color vs. its own tint**, not color vs. background. All 8 palette entries clear 4.5:1
on that measure in both schemes; `LabelColor.tintOpacity` is load-bearing — changing it
invalidates every ratio in `ScanLabel.swift`.

## Cross-promo

`CrossPromoView` + `CrossPromoState`, mirroring the -rip family's `SiblingApp` pattern.
Fires after the user's **second completed scan** — never on launch, never before they've
gotten value. Seen-state is a *set of keys*, so adding a sibling later surfaces only the new
one and preserves existing dismissals. Renaming a `key` re-shows that app to everyone.

Targets are **curated, not "everything Lavai Labs makes"**: Perennial and Unfrozen only.
The -rip cross-promo works because it's the same activity in another game; these apps share
only a maker, so the list is limited to adjacent problems (life admin). Deck of Pain is
defined but not shipped in `crossPromoTargets`.

## Design System

All tokens in `Theme.swift`. Semantic names only; no raw colors, radii, or spacing in views.

**Accent finishes** (`AccentFinish`): Blueprint is the free default; Graphite, Manila,
Red Pen and Chalkboard need Supporter. Named as desk materials, never as a color picker.
Locked finishes render at **full color** — never greyed, never padlocked, never badged.

⚠️ **A filled control needs a DIFFERENT accent value than an icon does.** `color(for:)` goes
light in dark mode so an icon reads on a near-black canvas — but a prominent button fills
with the tint and puts a **white** label on it *in both schemes*. Light fill + white label
measured ~2:1 and the scan button was nearly illegible. `fillColor(for:)` exists for this and
must satisfy two constraints at once: white label ≥4.5:1, and pill-vs-black ≥3:1 (WCAG
1.4.11). **Never style a prominent button by hand — use `.reamProminent(glass:)`,** which
picks the right one so no call site has to remember.

⚠️ **`.glassProminent` composites the tint under a translucent veil, so measuring the raw
hex overstates contrast by ~40%.** The first Manila (`#8A5A2B`) measured 5.87:1 against
white and *rendered* at 3.98:1 — a real failure that looked fine on paper. Every finish is
verified ≥4.5:1 after modelling an 18% veil, on both canvases. This also rules out vivid
blues: `#1268B0` pops hardest and lands at 4.05:1 glassed.

- `fieldBorder` (~12%) is deliberately higher contrast than `subtleBorder` (~8%).
- `tertiaryText` is `secondaryLabel` at 85%, not `.tertiaryLabel` — the system tertiary
  fails WCAG AA at body sizes.
- Minimum tap target 44pt (`Theme.minTapTarget`); use `.contentShape(Rectangle())` so the
  full padded area of a row or card is tappable, not just its text.
- Never set `presentationCornerRadius` on sheets — iOS matches device screen corners itself.
- **Light/dark override** (`AppearanceMode`, Settings → Theme) applies via
  `.preferredColorScheme` on `RootView`. The tint is resolved in a **child** (`TintedRoot`):
  `.preferredColorScheme` affects the subtree *below* it, so reading `\.colorScheme` in the
  same view that sets it returns the previous value and the accent lags one toggle behind.

## Single sources of truth

Repeated literals are a rename waiting to break silently, so these each live in exactly one
place. Adding a fifth copy of any of them is the regression:

- **`AppPaths`** — every on-disk location. `Documents/Scans` used to be rebuilt inline in five
  files; drift there is silent and nasty (recovery scanning a folder nothing writes to, an
  export zipping the wrong directory).
- **`DefaultsKey`** — `@AppStorage` keys. Change a raw string in four views and miss the
  fifth, and that view reads a key nothing writes.
- **`ExternalLink`** — privacy, terms, support mailto, App Store URLs.
- **`LaunchArgument`** (DEBUG) — the simulator flags.
- **`AppVersion.display`** — the one place Info.plist version keys are read.
- **`\.accentFinish` environment value** — the finish, already resolved against entitlement.
  Six views each used to read `@AppStorage`, pull in `SupporterService` and re-run
  `AccentFinish.resolved(...)`. One of them getting it wrong is exactly the bug that let a
  locked finish stay applied after a refund.
- **`Theme` / `AccentFinish` / `MarkupInk`** — all colours, spacing and radii.
- **`ReamRow` / `.reamProminent()`** — row and prominent-button styling.

## Lists and rows — one idiom, no exceptions

Every list in the app is a native `List` + `Section`, and every row goes through
**`ReamRow`** (`Views/Components/ReamRow.swift`). The Supporter sheet and cross-promo were
originally hand-built `ScrollView` + `VStack` cards and were converted — writing a row
eleven times produced eleven answers to "how tall is a row" and three rounds of spacing bugs.

⚠️ **Never put `.frame(minHeight: Theme.minTapTarget)` on a row inside a `List`.** The list
already clears 44pt from its own insets; the frame stacks on top and yields a ~66pt row that
reads as mostly empty space. This shipped across Settings, the label picker and the label
manager before it was caught. Set an explicit minimum *only* on controls that are not inside
a List (the filter chips, the empty-state button, swatch buttons).

Where a row needs non-standard height, use `.listRowInsets` with values that add up to 44 —
e.g. 10pt above and below a 24pt chip — rather than a minimum on top of the default.

Trailing accessories are a closed enum (`RowAccessory`), so "what can appear on the right of
a row" stays reviewable. The rule: **rows that OPEN something get `.chevron`; rows that DO
something get none.** Export and Rate have no chevron; Manage Labels and Privacy Policy do.

Custom row *content* inside a native container is fine and expected — the document row's
thumbnail and the cross-promo's icon/Get layout both do it. `List` still owns height,
insets, dividers and press states.

## Thumbnails

`ThumbnailService` renders page 1 and caches in memory (`NSCache`, 200 items) and on disk.
Disk cache lives in **`Caches/`, not `Documents/`** — it's derived data, so it must
regenerate silently after a purge and must never inflate the user's iCloud backup.
`invalidate(fileName:)` on delete, `invalidateAll()` on delete-everything; a thumbnail that
outlives its PDF is a stale row that looks like a real document.

## Navigation

**No tab bar.** One destination (your scans) and one action (scan). Tabs are for peer
locations, not verbs.

The bottom bar is iOS 26's shared row: `DefaultToolbarItem(kind: .search, placement: .bottomBar)`
places the system search field, `ToolbarSpacer` splits the glass groups, and the Scan pill
sits in its own group. The empty state carries a prominent CTA separately, since a small
pill is weak first-run discovery.

## Simulator gotchas

- **`VNDocumentCameraViewController` cannot run in the Simulator.** `SampleScans` (DEBUG)
  renders synthetic pages through the real pipeline instead. Launch args: `--seed-samples`,
  `--show-finishes`.
- **`simctl launch` does NOT apply the scheme's StoreKit configuration.** Products come back
  empty and the sheet says the App Store isn't reachable. Prices and purchases can only be
  verified by running from Xcode (⌘R) or on device with a sandbox account.
- SourceKit "No such module 'UIKit'" on freshly edited files is indexing noise on this
  setup. `xcodebuild` is the only truth.
- **`simctl` cannot tap.** Anything behind a gesture is unreachable from the command line,
  which is why the debug launch arguments exist. Gestures themselves can only be verified on
  a device — AppleScript clicking into the Simulator window was tried and does not land.
- DEBUG launch args: `--seed-samples`, `--show-settings`, `--show-detail`,
  `--onboarding-page N`. Debug section in Settings: Supporter Mode override, Replay
  Onboarding.

⚠️ **`Color(.systemBackground)` is PURE BLACK in dark mode.** This has caused three separate
bugs in this app: invisible onboarding rows, an invisible "sheet of paper", and a no-op PDF
background fix. For a card on a grouped background use `Theme.cardBackground`; for something
representing *paper*, use `OnboardingArt.paper` — a fixed off-white, because paper does not
change colour with the appearance setting (and the app icon draws white pages on dark).

## ASO / positioning

Search for `document scanner` / `pdf scanner` is closed: CamScanner (1.86M ratings),
Adobe Scan (1.58M), iScanner (1.39M), Genius Scan (1.35M). Do not spend title characters
competing there.

The one measured opening is **`image to pdf`** (opportunity 57, difficulty 41, #1 result
had ~100 ratings). Planned listing:

```
Title:     Ream: Image to PDF Scanner
Subtitle:  Scan to PDF, no subscription
```

Never repeat a word across title/subtitle/keyword field — Apple indexes all three.

## Engineering Standards

### Systems Thinking
Map the ripple before implementing: view → `@Query` → SwiftData → `ModelContext` → save →
other `@Query` views. Ask "what else re-renders?" for every mutation.

### Failure Modes First
Ask "how does this fail?" before "how does this work?" Here that means: camera permission
revoked mid-scan, OCR returning nothing on a blank page, disk full on PDF write, StoreKit
unavailable. Every one of those must degrade gracefully — a failed OCR pass still produces
a valid (non-searchable) PDF rather than losing the user's scan.

### Trade-offs Must Be Explicit
Name them in comments. Hierarchy: **user keeps their scan > UI responsiveness > file size**.
No silent compromises.

### Review Mindset
Before completing a feature: would this pass code review? Check for missing `withAnimation`
on model mutations, mutation during navigation, missing explicit `save()`, hardcoded colors
or strings, and empty/loading/error states.

### Code Quality
Boring and readable over clever. Precise names. Comments explain *why*, never *what*.

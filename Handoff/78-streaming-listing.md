# Streaming directory listings (#78)

Contract v5 sends 2,048-entry JSON ListChunk callbacks keyed by operation ID on the existing
sandbox XPC connection. The final ArchiveListing remains authoritative (including legacy ZIP
raw names, physical size, offsets and tail size). Only descriptors and archive metadata cross
the boundary; the official 7zz executable and extract/create/edit contracts are unchanged.

The app consumes callbacks in order, maps the first 2,048 entries off the main actor, and shows
the browser before the final reply. Subsequent snapshots grow geometrically (4,096, 8,192, …),
bounding accumulated model work rather than rebuilding the full model for every chunk.
The current folder and surviving selection are preserved. Search indexing and edits wait for
the authoritative result. Smaller listings go straight to finalization without a partial model.
Odd formats retain their existing parser and can deliver a single final chunk.

Closing the main window/archive, opening another archive, or opening sample data cancels the
opening task. Its cancellation handler cancels the producer, whose handler sends cancel(id).
The engine registers listing tasks in running, so cancel and connection invalidation terminate
7zz through its existing ChildProcess path. The engine closes its archive descriptor on every
exit; handlers are unregistered on the app side. Generation checks reject stale model updates.

## Reproducible 100,000-entry benchmark

StreamingListingBenchmark.hundredThousandEntriesStreamed generates a 100,000-entry TAR, warms
the file cache, and prints:

- The existing #22 parse-after versus parse-during measurements.
- #78 baseline: full listing, full JSON encode/decode, full browser model.
- First 2,048-entry callback and first chunk JSON encode/decode plus partial model.
- Complete streaming listing and full authoritative reply/model costs.
- Equality of accumulated chunks and final entries.

The chunk-wire/model measurement is a scripted first-paint readiness proxy, not a measured
SwiftUI frame or actual XPC scheduling latency. Run on a Mac with Xcode 27:

    scripts/fetch-7zip.sh
    xcodegen generate
    xcodebuild test -project Stow.xcodeproj -scheme Stow -destination 'platform=macOS' \
      -only-testing:StowTests/StreamingListingBenchmark \
      CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO DEVELOPMENT_TEAM=

Also run the full test suite (including normal small ZIP EngineTests) and the existing
-StowScrollBenchmark in Release to compare actual grid/list scrolling. Rendering and scrolling
code is unchanged; listing/model updates cease before the ordinary final-list scrolling case.

No Swift/Xcode/macOS SDK or bundled 7zz is installed on the implementation Linux host.
Consequently no Apple tests, measured Swift timings, first-frame timings, or new scroll numbers
are claimed here. The benchmark is automated and ready to print results in macOS CI; measured
macOS performance and compilation remain validation items.

## Added tests (MIN_TESTS 377 → 385)

- drainPreservesFinalListingAndLegacyIndices
- chunkBoundariesAndFinalRemainder
- chunksRoundTripOverTheWire
- drainingLargeFixtureMatchesFullParse
- cancelledListDoesNotLaunch
- cancellingAfterFirstChunkStopsRunningProcess
- partialBrowserKeepsFolderAndSelectionUntilFinalListing
- provisionalBrowserCannotStageEdits

The slow executable fixture emits a chunk then execs sleep; cancellation must return cancelled
within five seconds, rather than waiting for its thirty-second normal exit.

## Suggested PR body

- Stream directory-entry chunks through sandbox XPC v5 and paint an initial browser snapshot
  before the authoritative full reply.
- Cancel listing/7zz on close, replacement open and connection loss; preserve folder/selection
  across bounded partial snapshots and defer indexing/editing until completion.
- Add eight parser, wire, cancellation and browser regressions, extend the 100k benchmark,
  translate listing status into Simplified Chinese, and update parity/roadmap and CI ratchet.
- Validation: Linux static checks only; run Xcode 27 tests and quote benchmark/scroll output
  before describing measured performance improvements.

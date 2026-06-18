# Changelog

All notable changes to EasyNavigation are documented here.

## [2.5.0] — 2026-06-18

This release is the outcome of a multi-axis deep-dive review of **2.4.4**
(memory/retain cycles, Swift concurrency, SwiftUI navigation correctness, and
"native-API loss"). It fixes correctness issues, gives back native SwiftUI
capabilities the wrapper had hidden, and adds value-based + adaptive navigation.

**Verification:** 52 tests / 6 suites pass on the iOS 18 simulator. The consuming
app (centauri-ios) builds clean against 2.5.0.

### Added

- **`TypedRouter` + `TypedNavigationWrapper`** — value-based, type-safe navigation
  driven by the consumer's own `Hashable` route type on a native `NavigationStack`.
  - *Why:* the closure-boxed `[DestinationWrapper]` path (UUID identity, `AnyView`)
    made value-based deep-linking and state restoration impossible. A plain `[Route]`
    path restores both. When `Route: Codable`, `encodedPath()`/`restore(from:)` enable
    scene/state restoration after process death.
- **`SplitNavigationWrapper`** — adaptive `NavigationSplitView` (sidebar + detail) container.
  - *Why:* the library hardcoded a single `NavigationStack`, so iPad/Mac split layouts
    were impossible.
- **`PresentationConfiguration`** — `detents`, drag-indicator visibility, and
  `interactiveDismissDisabled`, threaded through `present`/`sheet`.
  - *Why:* routing every presentation through child routers hid native sheet
    configuration (`.presentationDetents`, `.interactiveDismissDisabled`, …).
- **Opt-in native navigation bar** via `showsNavigationBar` on `push`, `present`,
  `sheet`, `Router.init`, and `ViewNavigationWrapper.init`.
  - *Why:* the wrapper force-hid the navigation bar everywhere, so a screen's own
    `.navigationTitle`/`.toolbar`/native back button never rendered. Default stays
    `false` to preserve the existing custom-header behavior; set `true` per screen to
    get native chrome back.

### Fixed

- **`NavigationInformations` is now cached per `Router`.** It was re-allocated as a
  fresh `@Observable` instance on every `body` render, churning the environment
  identity and forcing every consumer to re-render.
- **`replacingPush` replaces the top in place** instead of append-then-remove. Removes
  the transient extra element / double animation, and stays correct if SwiftUI mutates
  the path (system back / swipe) between queued operations.
- **`present`/`sheet` queue instead of silently dropping** when a presentation is
  already in flight; the queued request is drained once the current one dismisses.
- **`dismissPresented` clears its own destination directly** instead of hopping onto
  the child router's separate queue, which could race a replacement.
- **Fire-once dismiss callbacks.** `resetToRoot`, `dismissToRoot`, and deep-link
  replacement now fire `onDismiss` instead of silently dropping it; the `[weak router]`
  capture in the view-layer `onDismiss` was removed.
- **`dismissToRoot` rewritten** to walk to the root in a single operation (matches
  `resetToRoot`) rather than cascading across each ancestor's queue.
- **`BackSwipeConfigurator` preserves and restores** SwiftUI's original pop-gesture
  delegate instead of permanently hijacking the shared `UINavigationController`.
- Removed a dead `.toolbar(.hidden, for: .navigationBar)` applied outside the
  `NavigationStack` (no-op).
- `DeepLinkCenter.clearPending` logs the count *before* `removeAll` (it always logged 0).

### Changed (potentially source-breaking for consumers)

- `present` / `sheet` / `removeAllPush` destination closures are now `@Sendable`
  (consistent with `push`). Call sites that capture non-`Sendable` state may need
  adjustment — the same discipline `push` already required.
- Dropped the redundant explicit `Sendable` conformance on `Router` / `DeepLinkCenter`
  (already implied by `@MainActor`; no behavior change).

### Notes

- `nonisolated(unsafe)` on the `ViewDestination` routing overloads is intentionally
  kept — it is sound by construction (the view is built on the main actor and only read
  back on the main actor at render), and a clean removal would break the public API.
- Two headline review findings were investigated and **rejected as false positives** by
  first-principles analysis: the alleged "Critical retain leak" (SwiftUI's dual
  ownership — item binding + presented `@State` — correctly releases child routers on
  dismiss) and "the operation-processor `Task` runs off the main actor" (`Task {}`
  inherits `@MainActor` via `@_inheritActorContext`).
- Device QA is recommended for the UI-only behaviors that unit tests cannot cover:
  navigation-bar visibility, sheet detents / interactive dismissal, and back-swipe.

[2.5.0]: https://github.com/palgroup/EasyNavigation/releases/tag/v2.5.0

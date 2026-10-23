# Changelog

All notable changes to EasyNavigation are documented here.

## [4.0.1] — 2026-10-24

### Fixed

- **A root swap crossfades instead of cutting.** `replacingPush` on an empty
  path and `removeAllPush` replace the stack's root inside
  `withAnimation(.default)`, but `ViewNavigationWrapper` drew every root under
  one identity: the new root took the old one's place in a single frame. The
  root now carries `rootViewID` as its identity, with an opacity transition,
  so the old root fades out and the new one fades in, in place.
  - *Measured* (iOS 26.4 simulator, 20 ms frames, Flokk's onboarding name →
    layover step): before, one frame from the old screen to the new; after, a
    crossfade over ~160 ms, no slide. A `.transition` on the app's own view
    did nothing — the identity has to change where the root is drawn.

**Verification:** 74 tests / 8 suites pass on the iOS 26.4 simulator. The
crossfade is a rendering change the tests do not draw; it was measured on the
simulator as above.

## [4.0.0] — 2026-10-02

### Breaking

- **Navigation takes a closure that builds the destination, and the closure
  runs on the main actor.** `push`, `replacingPush`, `removeAllPush`, `sheet`
  and `present` take `@MainActor @Sendable` closures, so a screen's builder —
  main-actor code in a Swift 6 app — is called in them directly:

      router.push { NoteDetailBuilder.build(id: note.id) }
      router.sheet(onDismiss: reload) { NoteEditorBuilder.build() }

  - *Why:* with plain `@Sendable` closures, calling a main-actor builder inside
    them did not compile, which is what pushed apps to `ViewDestination` route
    enums. The enum added a type per feature and nothing else: the router
    turned it into a view at once.
- **`ViewDestination` and `ViewDestinationRepresentable` are removed**, with
  the `push(_:)`, `sheet(_:)` and `present(_:)` overloads that took them.
- **`sheet` and `present` take the destination last**, after `configuration`
  and `onDismiss`, as SwiftUI's own `.sheet(isPresented:onDismiss:content:)`
  does — so the closure can trail.
- **The destination is built when it is first drawn**, not when `push` is
  called (the 3.x route overloads evaluated `body` at the call). It is built
  once per destination, on the main actor. This matters only for a builder
  with side effects.

### Migration from 3.x

| 3.x | 4.0 |
|-----|-----|
| `router.push(AppRoute.profile(id: id))` | `router.push { ProfileBuilder.build(id: id) }` |
| `router.sheet(AppRoute.editor, onDismiss: reload)` | `router.sheet(onDismiss: reload) { EditorBuilder.build() }` |
| `router.present(AppRoute.paywall)` | `router.present { PaywallBuilder.build() }` |
| `router.sheet({ Editor() }, onDismiss: reload)` | `router.sheet(onDismiss: reload) { Editor() }` |
| `router.sheet { Editor() } onDismiss: { reload() }` | `router.sheet(onDismiss: { reload() }) { Editor() }` |
| `router.present({ Editor() }) { reload() }` | `router.present(onDismiss: { reload() }) { Editor() }` |
| `enum AppRoute: ViewDestination { … }` | delete it — or keep it as plain code: drop the conformance, mark `body` `@MainActor @ViewBuilder var body: some View`, and write `router.push { AppRoute.profile(id: id).body }` |

Every old call shape fails to compile with 4.0 rather than doing something
else; the compiler points at each one.

**Verification:** 74 tests / 8 suites pass on the iOS 26.5 simulator. Every
navigation closure — on the internal router and on the public `Router` — is
called with a main-actor builder in a test, which compiles only because the
closures are `@MainActor`.

## [3.0.0] — 2026-10-02

### Breaking

- **A view reads its router only with `@Router`.** `Router` is now the property
  wrapper — and its own value, so calls look the same as before:

      @Router private var router
      router.push(AppRoute.profile(id: "123"))

  The class behind it is internal (`_Router`), so `@Environment(Router.self)`
  can no longer be written.
  - *Why:* reading the environment by hand skipped the missing-router
    handling: a screen previewed on its own crashed the canvas, and the app
    crashed with SwiftUI's generic message. `RouterWrapper` was a second name
    for the same thing. Now every read handles a missing router — a detached
    router in a preview, a stop with a message in the app. (`@NavigationWrapper`
    still exists for the router together with how the view was reached; it
    behaves the same way.)
- `RouterWrapper` is removed.
- `Router` is a value, not an object: it is no longer `Identifiable` or
  `Observable`, has no `id`, cannot be compared with `===`, held `weak`, or put
  in the environment with `.environment(router)`. It is `Sendable`.
- `Navigation.router` is a `Router`.
- `cleanup()` is no longer public.

### Changed

- The missing-router stop is a `fatalError` (a `preconditionFailure` drops its
  message in optimized builds) and its message no longer points to
  `TypedNavigationWrapper` / `SplitNavigationWrapper`, which provide no router.

### Migration from 2.x

| 2.x | 3.0 |
|-----|-----|
| `@Environment(Router.self) var router` | `@Router private var router` |
| `@RouterWrapper private var router` | `@Router private var router` |
| `@State var router = Router { Root() }` + `ViewNavigationWrapper(router: router)` | unchanged — a container may still own a stack's router and read `router.path` / `router.isPresenting` from outside it |
| `deepLinkCenter.setRootRouter(router)` | unchanged — pass the owned router, or the root screen's `@Router` in `.onAppear` |
| `.environment(router)` on a view outside the stack (a window overlay) | pass `router` to the view's initializer |
| `weak var router: Router?` | hold the `Router` value; it keeps the stack's router alive, so do not store it in an object the stack's root captures |

Everything called on the router — `push`, `replacingPush`, `removeAllPush`,
`pop`, `popToRoot`, `sheet`, `present`, `dismiss`, `dismissPresented`,
`dismissToRoot`, `resetToRoot`, `path`, `isPresenting`, `isBackSwipeAllowed` —
is unchanged.

A screen previewed on its own needs no `ViewNavigationWrapper`; it renders, and
navigating from it does nothing. Wrap a preview only to try navigation in it.

**Verification:** 73 tests / 8 suites pass on the iOS 26.5 simulator. The
`@Router` suite covers every forwarded call with its options, reading the stack
the view is in, an owned router, and the preview fallback.

## [2.6.0] — 2026-10-01

### Changed

- **`RouterWrapper` and `NavigationWrapper` no longer crash in Xcode previews
  when there is no `Router` in the environment.** A screen previewed on its own
  gets a detached router: it renders, and navigating from it does nothing.
  - *Why:* every screen that read the router needed its preview wrapped in a
    `ViewNavigationWrapper` just to render, or the canvas crashed with SwiftUI's
    generic "No Observable object of type Router found".
- **In the app, a missing router now stops with a message that names the fix**
  ("the view is outside every navigation wrapper … put it under
  ViewNavigationWrapper") instead of SwiftUI's generic crash. The app still
  stops: a view whose navigation silently does nothing would be a worse bug.
- `NavigationWrapper` falls back to the router's root navigation information
  when none is in the environment.

### Added

- `MissingRouter` (internal): the decision above in one place, with tests.

**Verification:** 56 tests / 7 suites pass on the iOS 26.5 simulator.

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

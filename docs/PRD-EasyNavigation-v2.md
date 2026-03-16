# PRD: EasyNavigation v2.0 — Refactor & Production Hardening

**Author:** Claude (Expert Code Review)
**Date:** 2026-03-13 (updated 2026-03-16)
**Status:** Phase 1-4 COMPLETE, RouterStack REJECTED
**Package:** `seklabsnet/EasyNavigation`
**Current Version:** 2.2.1 (was 1.0.2)
**Platform:** iOS 18+
**Swift Tools Version:** 6.1
**Detailed Changelog:** `docs/CHANGELOG-v2.md`
**Phase 3 Analysis:** `docs/Phase3-AnyView-Elimination.md`

### Phase Completion Status

| Phase | Version | Tag | Status |
|-------|---------|-----|--------|
| Phase 1 — Critical Fixes | 1.0.3 | `v1.0.3-phase1` | DONE |
| Phase 2 — AsyncStream + Tests | 2.0.0 | `v2.0.0-phase2` | DONE |
| Phase 3 — Performance + ViewDestination | 2.1.0 | `v2.1.0-phase3` | DONE |
| Phase 3.5 — BackSwipeConfigurator | - | latest main | DONE |
| Phase 4 — DeepLinkCenter | 2.2.0 | `v2.2.0-phase4` | DONE |
| Phase 4.1 — Router.path public | 2.2.1 | `2.2.1` | DONE |
| RouterStack | - | - | REJECTED (not needed) |

---

## Table of Contents

1. [Executive Summary](#1-executive-summary)
2. [Current Architecture Analysis](#2-current-architecture-analysis)
3. [Issue Registry — Full Detail](#3-issue-registry--full-detail)
4. [Target Architecture](#4-target-architecture)
5. [Detailed Specifications per Goal](#5-detailed-specifications-per-goal)
6. [Dependency Graph](#6-dependency-graph)
7. [Migration Plan & Phases](#7-migration-plan--phases)
8. [Testing Strategy](#8-testing-strategy)
9. [Versioning & Release Strategy](#9-versioning--release-strategy)
10. [Risk Analysis](#10-risk-analysis)
11. [Success Criteria](#11-success-criteria)
12. [Open Questions](#12-open-questions)
13. [Appendix](#13-appendix)

---

## 1. Executive Summary

EasyNavigation is a SwiftUI navigation framework that wraps `NavigationStack`, `fullScreenCover`, `sheet`, and window-level overlays behind a single `Router` API. The **external API is well-designed and ergonomic**. However, the **internal implementation has critical issues** spanning concurrency, type safety, performance, and stability.

This PRD documents every issue found during expert code review and provides a phased remediation plan. The goals are:

- **Zero crashes** from navigation operations
- **Zero thread blocking** (eliminate `Thread.sleep`)
- **Zero global side effects** (eliminate retroactive conformances and global mutable state)
- **Honest type system** (eliminate `@unchecked Sendable` lies)
- **Production-grade logging** (eliminate raw `print()`)
- **Test coverage** for all public API surface

### Impact Summary

| Category | Current State | Target State |
|----------|--------------|--------------|
| Crash safety | `replacingPush` crashes on small stacks | All operations bounds-checked |
| Thread safety | `Thread.sleep` blocks threads | `AsyncStream` + `Task.yield()` |
| Global side effects | UINavigationController extension affects all nav controllers | Scoped to EasyNavigation only |
| Type safety | `@unchecked Sendable` on non-Sendable types | Honest conformances |
| Logging | `print()` in release builds | `os.Logger` debug-level only |
| Test coverage | 0% | 100% of public Router API |
| Dead code | 3 unused files shipped | Removed or moved to extras target |

---

## 2. Current Architecture Analysis

### 2.1 File Inventory

```
Sources/EasyNavigation/
├── Package.swift                        # iOS 18+, Swift 6.1
├── EasyNavigation.swift                 # Empty entry point (no-op)
├── Router.swift                         # ⭐ Core — navigation engine (347 lines)
├── ViewNavigationWrapper.swift          # NavigationStack + sheet/fullscreen bindings (92 lines)
├── AppRoot.swift                        # GlobalRouter environment injection (33 lines)
├── GlobalRouter.swift                   # Window overlay management (61 lines)
├── WindowOverlay.swift                  # PassThroughWindow + overlay modifier (96 lines)
├── NavigationWrapper.swift              # @NavigationWrapper property wrapper (30 lines)
├── RouterWrapper.swift                  # @RouterWrapper property wrapper (22 lines)
├── DestinationWrapper.swift             # NavigationPath item wrapper (27 lines)
├── NavigationInformations.swift         # isPushed/isPresented state (33 lines)
├── ViewDestinationRepresentable.swift   # Deep link protocol (13 lines)
├── RouterStack.swift                    # ⚠️ DEAD — commented out everywhere (83 lines)
├── DeepLinkCenter.swift                 # ⚠️ DEAD — commented out everywhere (62 lines)
└── RouterStressTest.swift               # ⚠️ DEMO — should not ship in library (1161 lines)
```

**Total:** 14 files, ~2,160 lines
**Active:** 11 files, ~854 lines
**Dead/Demo:** 3 files, ~1,306 lines (60% of codebase!)

### 2.2 Object Graph

```
┌─────────────────────────────────────────────────────┐
│ AppRoot<Content>                                     │
│   @State globalRouter = GlobalRouter()               │
│   .environment(globalRouter)                         │
│   .environment(globalRouter.overlayProperties)       │
└──────────────┬──────────────────────────────────────┘
               │ injects into environment
               ▼
┌─────────────────────────────────────────────────────┐
│ GlobalRouter (@Observable, @MainActor)               │
│   keyWindow: UIWindow?                               │
│   overlayProperties: UniversalOverlayProperties      │
│   show(id:content:) / dismiss(id:)                   │
└──────────────┬──────────────────────────────────────┘
               │ manages
               ▼
┌─────────────────────────────────────────────────────┐
│ PassThroughWindow (UIWindow subclass)                │
│   hitTest override — pass through when no overlays   │
│   overlayProperties: weak ref                        │
└─────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────┐
│ ViewNavigationWrapper (per tab, per modal)            │
│   @State router: Router                              │
│   NavigationStack(path: $router.path)                │
│   .fullScreenCover(item: $router.fullScreenDestination)
│   .sheet(item: $router.sheetDestination)             │
└──────────────┬──────────────────────────────────────┘
               │ owns
               ▼
┌─────────────────────────────────────────────────────┐
│ Router (@Observable, @MainActor, Identifiable)       │
│   id: String (UUID)                                  │
│   root: AnyView                    ◄── type erased   │
│   path: [DestinationWrapper]       ◄── type erased   │
│   fullScreenDestination: Router?   ◄── child router  │
│   sheetDestination: Router?        ◄── child router  │
│   parent: Router? (weak)           ◄── dismiss chain │
│   operationQueue: OperationQueue   ◄── serial queue  │
│                                                      │
│   push() / pop() / popToRoot()                       │
│   present() / sheet() / dismiss()                    │
│   replacingPush() / removeAllPush()                  │
│   dismissPresented() / dismissToRoot()               │
│   cleanup()                                          │
└─────────────────────────────────────────────────────┘
               │ path contains
               ▼
┌─────────────────────────────────────────────────────┐
│ DestinationWrapper (Identifiable, Hashable)          │
│   id: UUID                                           │
│   destination: AnyView            ◄── type erased    │
│   allowsBackSwipe: Bool                              │
│   @unchecked Sendable             ◄── LIE            │
└─────────────────────────────────────────────────────┘
```

### 2.3 Navigation Flow

```
User calls router.push { MyView() }
    │
    ▼
executeOperation() — adds to OperationQueue (serial, max 1)
    │
    ▼
OperationQueue background thread picks up operation
    │
    ├── DispatchQueue.main.async { operation() }  ← hops to main thread
    │
    └── Thread.sleep(0.01)  ← BLOCKS background thread for 10ms
    │
    ▼
Main thread: path.append(DestinationWrapper(AnyView(MyView())))
    │
    ▼
SwiftUI observes @Observable path change
    │
    ▼
NavigationStack renders new destination via .navigationDestination(for:)
    │
    ▼
AnyView forces full diff (no static type info)
```

### 2.4 Modal Presentation Flow

```
User calls router.present { ModalView() }
    │
    ▼
Router creates child: Router(parent: self, root: { ModalView() })
    │
    ▼
self.fullScreenDestination = childRouter
    │
    ▼
ViewNavigationWrapper observes change via $router.fullScreenDestination
    │
    ▼
.fullScreenCover presents new ViewNavigationWrapper(router: childRouter)
    │
    ▼
Child ViewNavigationWrapper has its own NavigationStack
    │
    ▼
User calls router.dismiss() from inside modal
    │
    ▼
router.parent?.fullScreenDestination = nil  (weak parent ref)
    │
    ▼
SwiftUI dismisses the fullScreenCover
```

---

## 3. Issue Registry — Full Detail

### ISSUE-001: Thread.sleep on OperationQueue [CRITICAL]

**File:** `Router.swift:97-112`
**Severity:** Critical
**Category:** Concurrency

**What happens:**
```swift
private func executeOperation(_ operation: @escaping @MainActor () -> Void) {
    let delay = waitForUIUpdate ? operationDelay : 0

    operationQueue.addOperation { [weak self] in
        // 1. Hop to main thread
        DispatchQueue.main.async {
            guard self != nil else { return }
            operation()
        }

        // 2. Block the background thread
        if delay > 0 {
            Thread.sleep(forTimeInterval: delay)
        }
    }
}
```

**Why it's critical:**

1. **Thread starvation:** `OperationQueue` has limited threads. Blocking one for 10ms per navigation operation means rapid pushes can exhaust the pool. With `maxConcurrentOperationCount = 1`, only one thread is used, but it's blocked between every single operation.

2. **Timing fragility:** 10ms is a magic number. On an iPhone SE 1st gen under memory pressure, SwiftUI might need 30-50ms to commit a view update. On an M4 iPad, 2ms is enough. The delay is either too long (sluggish navigation) or too short (race condition, SwiftUI path corruption).

3. **DispatchQueue.main.async + Thread.sleep ordering is not guaranteed:** The main.async block may not execute before the sleep finishes. The operation completes the sleep, next operation starts, and the main thread hasn't processed the first operation yet. This breaks the entire "serial execution" guarantee.

4. **Mixing GCD + OperationQueue + MainActor:** Three different concurrency primitives interacting creates hard-to-reason-about timing issues.

**Reproduction:**
- Push 5+ views rapidly in quick succession
- On slower devices, some pushes may be skipped or doubled
- Under high main thread load (complex UI), path corruption can occur

**Impact on centauri-ios:** Every navigation action in the app goes through this code path. If 2 rapid taps happen (e.g., double-tap on a button), the serial queue's timing guarantee is unreliable.

---

### ISSUE-002: AnyView Everywhere [HIGH]

**Files:** `Router.swift:15,53,125,147,188`, `DestinationWrapper.swift:13`
**Severity:** High
**Category:** Performance

**What happens:**
```swift
var root: AnyView                              // Router root
self.root = AnyView(root())                    // init
AnyView(destination())                         // every push
DestinationWrapper(destination: AnyView(...))  // every path item
```

**Why it's a problem:**

SwiftUI's rendering engine uses **static type information** to perform efficient diffs. When you wrap a view in `AnyView`, the engine loses the ability to know what changed. Instead of updating just the changed properties, it must:

1. Tear down the entire previous view hierarchy
2. Rebuild the entire new view hierarchy
3. Diff the two complete hierarchies

For a simple text change in a pushed view, this means potentially re-evaluating hundreds of views.

**Performance impact measurement:**

```
Without AnyView: View update = O(changed properties)
With AnyView:    View update = O(total view hierarchy size)
```

For a navigation stack 5 levels deep with complex views, this can mean:
- **Without AnyView:** ~1-2ms per state update
- **With AnyView:** ~10-50ms per state update (device dependent)

At 60fps, you have 16.6ms per frame. AnyView can cause visible frame drops during navigation animations.

**Why it exists:** The `Router` needs to store arbitrary views without knowing their type at compile time. This is a fundamental tension in SwiftUI — `any View` isn't `Hashable`, so it can't go in `NavigationPath` directly.

**Solution complexity:** High — this is the hardest issue to fix while maintaining the current API ergonomics.

---

### ISSUE-003: @unchecked Sendable Lie [HIGH]

**File:** `DestinationWrapper.swift:11`
**Severity:** High
**Category:** Type Safety

**What happens:**
```swift
public struct DestinationWrapper: Identifiable, Hashable, @unchecked Sendable {
    let destination: AnyView  // AnyView does NOT conform to Sendable
}
```

**Why it's a problem:**

`@unchecked Sendable` tells the compiler: "Trust me, this type is safe to send across concurrency boundaries." But `AnyView` wraps arbitrary view closures that can capture `@MainActor`-isolated state. Sending this across actor boundaries causes:

1. **Data races** if the captured state is mutated from another isolation context
2. **Runtime crashes** in strict concurrency mode (Swift 6)
3. **Undefined behavior** that may appear as random UI glitches

**Why it exists:** The compiler complains when putting non-Sendable types in collections used across isolation boundaries. `@unchecked Sendable` silences the warning.

**Why it's not immediately crashing:** In practice, `DestinationWrapper` is only used within `Router.path` which is `@MainActor`. So it never actually crosses isolation boundaries... *yet*. But any future change that moves path operations off `@MainActor` will trigger real data races.

**The right fix:** Since `Router` is `@MainActor` and `DestinationWrapper` only lives in `Router.path`, we should remove `Sendable` entirely — it's not needed and it's not true.

---

### ISSUE-004: Global SwipeConfiguration [HIGH]

**File:** `ViewNavigationWrapper.swift:10-13`
**Severity:** High
**Category:** Bug (Active)

**What happens:**
```swift
struct SwipeConfiguration {
    @MainActor static var backSwipeAvailable: Bool = false
}
```

This is a **global static boolean** that controls back swipe for **all** navigation stacks in the app.

**Bug scenario:**
```
1. App has TabView with 3 tabs, each with ViewNavigationWrapper
2. Tab A: user pushes view with allowBackSwipe: false
   → SwipeConfiguration.backSwipeAvailable = false
3. User switches to Tab B
4. Tab B: user pushes a normal view (allowBackSwipe: true)
   → SwipeConfiguration.backSwipeAvailable = true
5. User switches back to Tab A
6. Tab A: back swipe NOW WORKS even though it was disabled
   → BUG: The view in Tab A was pushed with allowBackSwipe: false
      but global state was overwritten by Tab B
```

**Impact on centauri-ios:** The app uses a TabView with multiple tabs. Every tab switch can corrupt the back swipe state of other tabs.

**Where the static is set:**
```swift
// Router.swift:128 — on every push
SwipeConfiguration.backSwipeAvailable = allowBackSwipe

// Router.swift:213 — on every pop
SwipeConfiguration.backSwipeAvailable = destination.allowsBackSwipe
```

---

### ISSUE-005: UINavigationController Retroactive Conformance [HIGH]

**File:** `ViewNavigationWrapper.swift:15-24`
**Severity:** High
**Category:** Stability

**What happens:**
```swift
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return viewControllers.count > 1 && SwipeConfiguration.backSwipeAvailable
    }
}
```

**Why it's dangerous:**

1. **Affects ALL UINavigationControllers in the entire app** — not just EasyNavigation's. Any UIKit-based navigation (including 3rd party SDKs like CometChat, Firebase UI, etc.) will have its `viewDidLoad` behavior modified.

2. **Method override in extension is undefined behavior.** The Swift documentation explicitly states: "Extensions can add new functionality to a type, but they cannot override existing functionality." Overriding `viewDidLoad` in an extension works by accident (Objective-C runtime dispatch), not by design. A future Swift compiler version could break this.

3. **`@retroactive` protocol conformance** means `UINavigationController` already has `UIGestureRecognizerDelegate` conformance somewhere. Adding another conformance causes ambiguity.

4. **Import side effects:** Simply `import EasyNavigation` in any file changes the behavior of ALL navigation controllers. The consumer has no opt-in mechanism.

**Real-world impact on centauri-ios:**
- CometChat SDK uses its own UINavigationController for chat screens
- Any UIKit-based screen presented via `UIViewControllerRepresentable` gets affected
- If another SPM package also overrides `UINavigationController.viewDidLoad`, behavior is undefined (last-write-wins in Objective-C runtime)

---

### ISSUE-006: replacingPush Index Math Crash [CRITICAL]

**File:** `Router.swift:179-192`
**Severity:** Critical
**Category:** Crash

**What happens:**
```swift
public func replacingPush<Content: View>(@ViewBuilder _ destination: @escaping () -> Content) {
    if self.path.isEmpty {
        executeOperation { [weak self] in
            self?.replaceRootWithAnimation(destination)
        }
    } else {
        executeOperation {
            self.path.append(DestinationWrapper(destination: AnyView(destination())))
            self.path.remove(at: self.path.count - 3)  // ← CRASH POINT
        }
    }
}
```

**Crash scenario:**
```
1. path has 1 element: [ViewA]
2. User calls replacingPush { ViewB() }
3. path.isEmpty is false → enters else branch
4. path.append(ViewB) → path = [ViewA, ViewB], count = 2
5. path.remove(at: 2 - 3) → path.remove(at: -1)
6. 💥 CRASH: Array index out of range
```

**Also crashes when path has 2 elements:**
```
1. path = [ViewA, ViewB], count = 2
2. append ViewC → path = [ViewA, ViewB, ViewC], count = 3
3. remove(at: 3 - 3) → remove(at: 0) → removes ViewA
4. Result: [ViewB, ViewC]
5. ❓ Is this correct? The method is "replacingPush" — it should replace
   the current top (ViewB) with ViewC, giving [ViewA, ViewC]
   But instead it removes the BOTTOM, giving [ViewB, ViewC]
```

**So there are TWO bugs:**
1. **Crash** when `path.count < 2` before append (path.count < 3 after append)
2. **Wrong behavior** when `path.count == 2` — removes bottom instead of replacing top

**Expected behavior of `replacingPush`:**
- "Push new view, removing the current top view"
- Before: `[A, B, C]` → After `replacingPush(D)`: `[A, B, D]` (C replaced by D)
- Before: `[A]` → After `replacingPush(D)`: `[D]` (A replaced by D)
- Before: `[]` → After `replacingPush(D)`: root replaced with D

**Correct index math:**
```swift
// After append, remove the second-to-last (which was the old top)
let removeIndex = self.path.count - 2  // NOT count - 3
```

---

### ISSUE-007: Dead Code Shipped [MEDIUM]

**Files:** `RouterStack.swift`, `DeepLinkCenter.swift`, `RouterStressTest.swift`
**Severity:** Medium
**Category:** Maintainability

**RouterStack.swift (83 lines):**
- Fully implemented class with push/pop/topMostRouter
- Referenced nowhere — all usage in `GlobalRouter.swift` and `ViewNavigationWrapper.swift` is commented out
- Contains public API surface that consumers might try to use but has no effect

**DeepLinkCenter.swift (62 lines):**
- Actor-based deep link queue
- Referenced nowhere — all usage in `GlobalRouter.swift` is commented out
- Has its own concurrency issues (actor + @MainActor mixing)

**RouterStressTest.swift (1,161 lines):**
- Demo/test views for stress testing navigation
- Ships with the library — consumers get `StressTestTabView` as a public type
- Contains 1,161 lines of demo code — **more than the actual library**

**Impact:**
- Binary size: ~1,300 lines of unused code compiled into every consuming app
- API surface pollution: `StressTestTabView`, `RouterStack`, `DeepLinkCenter` are public but non-functional
- Confusion: developers exploring the package see dead/demo code alongside real code

---

### ISSUE-008: Print Statements in Production [MEDIUM]

**Files:** `Router.swift` (22 print calls), `RouterStack.swift` (10 print calls)
**Severity:** Medium
**Category:** Performance / Privacy

**Inventory of all print statements in Router.swift:**
```
Line 60:  print("🧹 [CLEANUP] Router...")
Line 89:  print("✅ [CLEANUP] Router...")
Line 93:  print("Router Deiniting...")
Line 118: print("❌ [PUSH] Router is nil...")
Line 122: print("🔵 [PUSH] Router...")
Line 130: print("✅ [PUSH] Router...")
Line 204: print("❌ [POP] Router is nil...")
Line 209: print("🔙 [POP] Router...")
Line 214: print("✅ [POP] Router...")
Line 216: print("⚠️ [POP] Router...")
Line 225: print("🏠 [POPTOROOT] Router...")
Line 228: print("✅ [POPTOROOT] Router...")
Line 237: print("❌ [PRESENT] Router is nil...")
Line 246: print("🟣 [PRESENT] Router...")
Line 257: print("❌ [SHEET] Router is nil...")
Line 267: print("🟡 [SHEET] Router...")
Line 278: print("❌ [DISMISS] Router is nil...")
Line 288: print("🔴 [DISMISS] Router...")
Line 291: print("✅ [DISMISS] Router...")
Line 295: print("✅ [DISMISS] Router...")
Line 299: print("⚠️ [DISMISS] Router...")
Line 337: print("❌ [PRESENT] Router already present a sheet...")
Line 342: print("❌ [PRESENT] Router already present a fullscreen...")
```

**Why it matters:**
- `print()` in Swift uses `stdout` which is **synchronized** — it acquires a lock. Under high-frequency navigation, this lock contention adds latency.
- `print()` calls are **not compiled out** in release builds. Unlike `assert()` or `precondition()`, `print()` always executes.
- The printed content includes `ObjectIdentifier` (memory addresses) which could leak information in crash logs or diagnostics.
- Each emoji + string interpolation creates allocations on every navigation action.

---

### ISSUE-009: GCD-era Concurrency [MEDIUM]

**File:** `Router.swift:29-112`
**Severity:** Medium
**Category:** Modernization

**Current pattern:**
```
OperationQueue (background, serial)
    → DispatchQueue.main.async (hop to main)
        → Thread.sleep (block background)
```

**Three different concurrency primitives** in 15 lines of code:
1. `OperationQueue` (Foundation)
2. `DispatchQueue.main.async` (GCD)
3. `Thread.sleep` (POSIX)

None of these integrate with Swift Concurrency's cooperative threading model. The `Thread.sleep` is particularly bad because it's a **non-cooperative block** — the Swift runtime can't schedule other tasks on that thread while it's sleeping.

**In the context of Swift 6 strict concurrency**, this pattern will become increasingly problematic as the compiler enforces more isolation rules.

---

### ISSUE-010: .id(router.id) Nuclear Rebuild [MEDIUM]

**File:** `ViewNavigationWrapper.swift:82`
**Severity:** Medium
**Category:** Performance

**What happens:**
```swift
// ViewNavigationWrapper body
NavigationStack(path: $router.path) { ... }
    .fullScreenCover(...)
    .sheet(...)
    .toolbar(.hidden, for: .navigationBar)
    .id(router.id)  // ← THIS
```

`.id()` tells SwiftUI: "When this value changes, destroy the entire view and recreate it from scratch." Since `router.id` is set once in `Router.init` and never changes, this specific instance doesn't cause rebuilds during the router's lifetime.

**However**, it prevents SwiftUI from reusing the `ViewNavigationWrapper` view across identity changes. If the parent view conditionally shows different `ViewNavigationWrapper` instances (e.g., tab switching), SwiftUI can't smoothly transition — it must destroy and recreate.

**Potential issue:** If `router.id` were ever changed (e.g., during a "reset navigation" flow), the entire NavigationStack and all its pushed views would be destroyed and recreated, losing all `@State` in child views.

**Verdict:** Low-risk but should be evaluated. If removing `.id(router.id)` doesn't break anything, remove it for better performance.

---

### ISSUE-011: No Unit Tests [HIGH]

**Severity:** High
**Category:** Quality

The package has **zero tests**. No `Tests/` directory exists. This means:

1. **No regression safety net** — any refactor can break existing behavior silently
2. **No contract documentation** — tests serve as executable documentation of expected behavior
3. **No CI enforcement** — no way to prevent broken code from merging

For a navigation framework that every screen in the app depends on, this is unacceptable.

---

### ISSUE-012: @ObservationIgnored on parent [LOW]

**File:** `Router.swift:27`
**Severity:** Low
**Category:** Correctness

```swift
@ObservationIgnored
weak var parent: Router?
```

`@ObservationIgnored` means SwiftUI views won't re-render when `parent` changes. Since `parent` is set once in `init` and is `weak`, this is technically fine. But if any future code path reassigns `parent`, views depending on parent state (like `dismiss()` logic) won't update.

**Verdict:** Acceptable for now, but add a comment explaining why it's ignored.

---

## 4. Target Architecture

### 4.1 Architecture Diagram — After Refactor

```
┌─────────────────────────────────────────────────────┐
│ AppRoot<Content>                                     │
│   @State globalRouter = GlobalRouter()               │
│   .environment(globalRouter)                         │
│   .environment(globalRouter.overlayProperties)       │
└──────────────┬──────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────┐
│ GlobalRouter (@Observable, @MainActor)               │
│   keyWindow: UIWindow?                               │
│   overlayProperties: UniversalOverlayProperties      │
│   show(id:content:) / dismiss(id:)                   │
│                                                      │
│   🆕 No more RouterStack/DeepLinkCenter refs         │
└──────────────┬──────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────┐
│ ViewNavigationWrapper                                │
│   @State router: Router                              │
│   NavigationStack(path: $router.path)                │
│   .fullScreenCover(item: $router.fullScreenDestination)
│   .sheet(item: $router.sheetDestination)             │
│                                                      │
│   🆕 No UINavigationController extension             │
│   🆕 No global SwipeConfiguration                    │
│   🆕 No .id(router.id) (evaluated)                   │
└──────────────┬──────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────┐
│ Router (@Observable, @MainActor)                     │
│                                                      │
│   🆕 AsyncStream-based serial execution              │
│   ┌──────────────────────────────────────┐           │
│   │ navigationContinuation.yield(op)     │           │
│   │         │                            │           │
│   │         ▼                            │           │
│   │ for await op in stream {             │           │
│   │     op.execute()     // @MainActor   │           │
│   │     await Task.yield() // let UI     │           │
│   │ }                                    │           │
│   └──────────────────────────────────────┘           │
│                                                      │
│   🆕 os.Logger instead of print()                    │
│   🆕 Fixed replacingPush index math                  │
│   🆕 Per-router backSwipeAllowed                     │
│   🆕 Bounds checks on all path operations            │
│                                                      │
│   path: [DestinationWrapper]                         │
│   fullScreenDestination: Router?                     │
│   sheetDestination: Router?                          │
│   parent: Router? (weak)                             │
└─────────────────────────────────────────────────────┘
               │
               ▼
┌─────────────────────────────────────────────────────┐
│ DestinationWrapper (Identifiable, Hashable)          │
│   🆕 No @unchecked Sendable                          │
│   destination: AnyView                               │
│   allowsBackSwipe: Bool                              │
└─────────────────────────────────────────────────────┘
```

### 4.2 Files — After Refactor

```
Sources/EasyNavigation/
├── EasyNavigation.swift                 # Entry point (no-op)
├── Router.swift                         # Core — AsyncStream based
├── ViewNavigationWrapper.swift          # Clean — no extensions
├── AppRoot.swift                        # Unchanged
├── GlobalRouter.swift                   # Clean — no dead refs
├── WindowOverlay.swift                  # Unchanged
├── NavigationWrapper.swift              # Unchanged
├── RouterWrapper.swift                  # Unchanged
├── DestinationWrapper.swift             # Fixed Sendable
├── NavigationInformations.swift         # Unchanged
├── ViewDestinationRepresentable.swift   # Unchanged
├── 🆕 NavigationLogger.swift            # os.Logger wrapper
└── 🆕 BackSwipeController.swift         # Scoped swipe control (if needed)

🗑️ REMOVED: RouterStack.swift
🗑️ REMOVED: DeepLinkCenter.swift
🗑️ REMOVED: RouterStressTest.swift

Tests/EasyNavigationTests/
├── 🆕 RouterTests.swift
├── 🆕 RouterPresentationTests.swift
├── 🆕 RouterEdgeCaseTests.swift
├── 🆕 NavigationInformationsTests.swift
└── 🆕 GlobalRouterTests.swift
```

---

## 5. Detailed Specifications per Goal

### G1: Replace Thread.sleep + OperationQueue with AsyncStream

**Goal:** Eliminate thread blocking, modernize concurrency.

**Affected files:** `Router.swift`

**Current implementation (to be removed):**
```swift
// Router.swift — REMOVE THESE

@ObservationIgnored
private let operationQueue: OperationQueue = {
    let queue = OperationQueue()
    queue.maxConcurrentOperationCount = 1
    queue.qualityOfService = .userInteractive
    return queue
}()

@ObservationIgnored
public var operationDelay: TimeInterval = 0.01

@ObservationIgnored
public var waitForUIUpdate: Bool = true

private func executeOperation(_ operation: @escaping @MainActor () -> Void) {
    let delay = waitForUIUpdate ? operationDelay : 0
    operationQueue.addOperation { [weak self] in
        DispatchQueue.main.async {
            guard self != nil else { return }
            operation()
        }
        if delay > 0 {
            Thread.sleep(forTimeInterval: delay)
        }
    }
}
```

**New implementation:**
```swift
// Router.swift — ADD THESE

@ObservationIgnored
private var navigationContinuation: AsyncStream<@MainActor @Sendable () -> Void>.Continuation?

@ObservationIgnored
private var processingTask: Task<Void, Never>?

/// Starts the serial navigation operation processor.
/// Called once during init. All navigation ops are queued and
/// executed one at a time on @MainActor with a yield between each.
private func startOperationProcessor() {
    let (stream, continuation) = AsyncStream<@MainActor @Sendable () -> Void>.makeStream(
        bufferingPolicy: .unbounded
    )
    self.navigationContinuation = continuation

    processingTask = Task { [weak self] in
        for await operation in stream {
            guard self != nil else { break }
            operation()
            // Yield to RunLoop — lets SwiftUI commit the state change
            // before the next operation executes
            await Task.yield()
        }
    }
}

/// Queues a navigation operation for serial execution.
/// Operations execute in FIFO order on @MainActor.
private func executeOperation(_ operation: @escaping @MainActor @Sendable () -> Void) {
    navigationContinuation?.yield(operation)
}

// Update init:
public init<Content: View>(
    parent: Router? = nil,
    @ViewBuilder root: @escaping () -> Content
) {
    self.parent = parent
    self.root = AnyView(root())
    self.rootViewID = UUID()
    startOperationProcessor()  // 🆕
}

// Update cleanup:
public func cleanup() {
    navigationContinuation?.finish()  // 🆕 graceful stream termination
    processingTask?.cancel()          // 🆕
    // ... rest of cleanup
}

// Update deinit:
deinit {
    navigationContinuation?.finish()  // 🆕
    processingTask?.cancel()          // 🆕
}
```

**Also remove public properties that exposed timing internals:**
```swift
// REMOVE — no longer needed
public var operationDelay: TimeInterval = 0.01
public var waitForUIUpdate: Bool = true
```

> **⚠️ Breaking change:** `operationDelay` and `waitForUIUpdate` were public. Removing them is API-breaking. If backward compatibility needed, deprecate instead:
> ```swift
> @available(*, deprecated, message: "No longer needed — operations use cooperative scheduling")
> public var operationDelay: TimeInterval = 0
> @available(*, deprecated, message: "No longer needed — operations use cooperative scheduling")
> public var waitForUIUpdate: Bool = true
> ```

**Edge cases to handle:**

| Scenario | Expected Behavior |
|----------|-------------------|
| 100 rapid pushes | All 100 execute in order, UI updates between each |
| Push during cleanup | Operation is dropped (continuation finished) |
| Push after deinit | Continuation is nil, yield is no-op |
| Push from background thread | Compiler error — Router is @MainActor |
| Cancel mid-stream | processingTask cancelled, remaining ops dropped |

**Acceptance criteria:**
- [ ] Zero `Thread.sleep` calls in codebase
- [ ] Zero `OperationQueue` usage in Router
- [ ] Zero `DispatchQueue.main.async` calls in Router
- [ ] All navigation operations execute on @MainActor
- [ ] Operations execute in FIFO order
- [ ] SwiftUI has time to commit state between operations
- [ ] Rapid push/pop (100+ operations) doesn't cause path corruption
- [ ] Cleanup properly terminates the stream

---

### G2: Fix replacingPush Crash

**Goal:** Eliminate crash + fix wrong index math.

**Affected files:** `Router.swift`

**Current implementation (buggy):**
```swift
public func replacingPush<Content: View>(@ViewBuilder _ destination: @escaping () -> Content) {
    if self.path.isEmpty {
        executeOperation { [weak self] in
            self?.replaceRootWithAnimation(destination)
        }
    } else {
        executeOperation {
            self.path.append(DestinationWrapper(destination: AnyView(destination())))
            self.path.remove(at: self.path.count - 3)  // BUG
        }
    }
}
```

**New implementation:**
```swift
public func replacingPush<Content: View>(@ViewBuilder _ destination: @escaping () -> Content) {
    executeOperation { [weak self] in
        guard let self else {
            NavigationLogger.debug("replacingPush: Router is nil")
            return
        }

        if self.path.isEmpty {
            // No pushed views — replace the root
            self.replaceRootWithAnimation(destination)
            NavigationLogger.debug("replacingPush: replaced root (path was empty)")
        } else {
            // Push new view, then remove the old top
            // Before append: path = [A, B, C] (C is current top)
            // After append:  path = [A, B, C, D]
            // Remove at count-2: removes C → path = [A, B, D] ✓
            self.path.append(DestinationWrapper(destination: AnyView(destination())))
            let removeIndex = self.path.count - 2
            guard removeIndex >= 0 else {
                NavigationLogger.debug("replacingPush: unexpected state, removeIndex=\(removeIndex)")
                return
            }
            self.path.remove(at: removeIndex)
            NavigationLogger.debug("replacingPush: replaced top, path count=\(self.path.count)")
        }
    }
}
```

**Behavior truth table:**

| Before | Operation | After | Animation |
|--------|-----------|-------|-----------|
| `[]` | `replacingPush(D)` | root = D | Root crossfade |
| `[A]` | `replacingPush(D)` | `[D]` | Push D, then remove A |
| `[A, B]` | `replacingPush(D)` | `[A, D]` | Push D, then remove B |
| `[A, B, C]` | `replacingPush(D)` | `[A, B, D]` | Push D, then remove C |

**Acceptance criteria:**
- [ ] `replacingPush` on empty path replaces root (no crash)
- [ ] `replacingPush` on path with 1 element works (no crash)
- [ ] `replacingPush` on path with 2 elements replaces correct view (top, not bottom)
- [ ] `replacingPush` on path with N elements replaces top, preserves rest
- [ ] Unit test for each row in truth table

---

### G3: Fix Global SwipeConfiguration

**Goal:** Back swipe state is per-router, not global.

**Affected files:** `ViewNavigationWrapper.swift`, `Router.swift`

**Remove entirely:**
```swift
// ViewNavigationWrapper.swift — DELETE
struct SwipeConfiguration {
    @MainActor static var backSwipeAvailable: Bool = false
}
```

**Remove from Router.swift:**
```swift
// Router.swift push — DELETE this line
SwipeConfiguration.backSwipeAvailable = allowBackSwipe

// Router.swift pop — DELETE this line
SwipeConfiguration.backSwipeAvailable = destination.allowsBackSwipe
```

**Add to Router.swift:**
```swift
/// Whether the current top-of-stack view allows back swipe.
/// Returns true when path is empty (root views always allow).
public var isBackSwipeAllowed: Bool {
    path.last?.allowsBackSwipe ?? true
}
```

**This property is reactive** (thanks to `@Observable`) — SwiftUI views that read it will automatically update when path changes.

**Acceptance criteria:**
- [ ] `SwipeConfiguration` struct no longer exists
- [ ] No global/static mutable state for swipe control
- [ ] Tab A's swipe setting doesn't affect Tab B
- [ ] `router.isBackSwipeAllowed` returns correct value after push/pop

---

### G4: Remove UINavigationController Retroactive Conformance

**Goal:** No global side effects from importing EasyNavigation.

**Affected files:** `ViewNavigationWrapper.swift`

**Remove entirely:**
```swift
// ViewNavigationWrapper.swift — DELETE THIS ENTIRE BLOCK
extension UINavigationController: @retroactive UIGestureRecognizerDelegate {
    override open func viewDidLoad() {
        super.viewDidLoad()
        interactivePopGestureRecognizer?.delegate = self
    }

    public func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        return viewControllers.count > 1 && SwipeConfiguration.backSwipeAvailable
    }
}
```

**Alternative — if back swipe control is required:**

Create a scoped solution using `UIViewControllerRepresentable`:

```swift
// New file: BackSwipeController.swift

import SwiftUI

/// Finds the hosting UINavigationController and configures its
/// interactive pop gesture based on the Router's current state.
struct BackSwipeConfigurator: UIViewControllerRepresentable {
    let isEnabled: Bool

    func makeUIViewController(context: Context) -> UIViewController {
        let controller = BackSwipeProxyController()
        controller.isSwipeEnabled = isEnabled
        return controller
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {
        guard let proxy = uiViewController as? BackSwipeProxyController else { return }
        proxy.isSwipeEnabled = isEnabled
        proxy.updateGesture()
    }
}

private class BackSwipeProxyController: UIViewController, UIGestureRecognizerDelegate {
    var isSwipeEnabled: Bool = true

    override func didMove(toParent parent: UIViewController?) {
        super.didMove(toParent: parent)
        updateGesture()
    }

    func updateGesture() {
        // Walk up to find the NavigationController
        var current: UIViewController? = self
        while let vc = current {
            if let nav = vc as? UINavigationController {
                nav.interactivePopGestureRecognizer?.delegate = self
                nav.interactivePopGestureRecognizer?.isEnabled = isSwipeEnabled
                return
            }
            current = vc.parent
        }
    }

    func gestureRecognizerShouldBegin(_ gestureRecognizer: UIGestureRecognizer) -> Bool {
        guard let nav = navigationController else { return false }
        return nav.viewControllers.count > 1 && isSwipeEnabled
    }
}
```

**Usage in ViewNavigationWrapper:**
```swift
// Inside NavigationStack's .navigationDestination
wrapper.destination
    .background(BackSwipeConfigurator(isEnabled: wrapper.allowsBackSwipe))
```

**Decision point:** Does centauri-ios actually need per-view back swipe control? If not, we can skip `BackSwipeController` entirely and just remove the extension. Back swipe will work normally (iOS default).

**Acceptance criteria:**
- [ ] No `extension UINavigationController` in codebase
- [ ] No `@retroactive` protocol conformances
- [ ] Importing EasyNavigation has zero side effects on UIKit types
- [ ] CometChat and other 3rd party navigation controllers unaffected
- [ ] If back swipe control is kept: scoped to EasyNavigation's own NavigationStack only

---

### G5: Production Logging

**Goal:** Zero print() in release, structured logging in debug.

**Affected files:** `Router.swift`, all files with print()

**New file: `NavigationLogger.swift`**
```swift
import os

enum NavigationLogger {
    private static let logger = Logger(
        subsystem: "com.seklabs.EasyNavigation",
        category: "Navigation"
    )

    /// Debug-level log. Compiled out in Release builds.
    static func debug(_ message: String) {
        logger.debug("\(message, privacy: .public)")
    }

    /// Warning-level log. Available in Release but only on-device Console.
    static func warning(_ message: String) {
        logger.warning("\(message, privacy: .public)")
    }

    /// Error-level log. Always available.
    static func error(_ message: String) {
        logger.error("\(message, privacy: .public)")
    }
}
```

**Migration pattern:**
```swift
// BEFORE
print("🔵 [PUSH] Router(\(routerId)) - Current path count: \(path.count)")

// AFTER
NavigationLogger.debug("PUSH - path count: \(path.count)")
```

**Log level mapping:**
| Current | New Level | When |
|---------|-----------|------|
| `print("✅ ...")` | `.debug` | Successful operations |
| `print("⚠️ ...")` | `.warning` | Non-critical issues (empty pop, etc.) |
| `print("❌ ...")` | `.error` | Failures (nil self, blocked operations) |
| `print("🧹 ...")` | `.debug` | Cleanup operations |
| `print("Router Deiniting")` | `.debug` | Lifecycle |

**Acceptance criteria:**
- [ ] Zero `print()` calls in entire package
- [ ] All logging uses `os.Logger` via `NavigationLogger`
- [ ] Debug-level logs don't appear in Release builds
- [ ] Logs are filterable in Console.app by subsystem `com.seklabs.EasyNavigation`

---

### G6: Dead Code Removal

**Goal:** Remove all non-functional code from the shipped library.

**Files to remove:**

| File | Lines | Reason |
|------|-------|--------|
| `RouterStack.swift` | 83 | All usage commented out |
| `DeepLinkCenter.swift` | 62 | All usage commented out |
| `RouterStressTest.swift` | 1,161 | Demo code, public type pollution |

**Also clean up references in GlobalRouter.swift:**
```swift
// GlobalRouter.swift — REMOVE commented-out lines
//    private(set) public var routerStack: RouterStack
//    private(set) public var deeplinkCenter: DeepLinkCenter

// init — REMOVE
//        let routerStack = RouterStack()
//        deeplinkCenter = DeepLinkCenter(routerStack: routerStack)
//        self.routerStack = routerStack
```

**Also clean up references in ViewNavigationWrapper.swift:**
```swift
// ViewNavigationWrapper.swift — REMOVE
//    @Environment(RouterStack.self) var stack

// onAppear — REMOVE
//            stack.push(router)

// onDisappear — REMOVE
//            stack.pop(router)
```

**Also clean up references in AppRoot.swift:**
```swift
// AppRoot.swift — REMOVE
//            .environment(globalRouter.routerStack)
//            .environmentObject(globalRouter.deeplinkCenter)
```

**Preservation strategy:** Create a git tag `v1.0.2-with-dead-code` before removal so the code can be referenced if DeepLinkCenter/RouterStack is revived in v2.2.

**Acceptance criteria:**
- [ ] `RouterStack.swift` removed from Sources
- [ ] `DeepLinkCenter.swift` removed from Sources
- [ ] `RouterStressTest.swift` removed from Sources
- [ ] All commented-out references to these types removed
- [ ] `StressTestTabView` no longer in public API
- [ ] Package compiles without these files
- [ ] Git tag created for reference

---

### G7: Fix Sendable Conformance

**Goal:** No `@unchecked Sendable` on types that aren't Sendable.

**Affected files:** `DestinationWrapper.swift`

**Change:**
```swift
// BEFORE
public struct DestinationWrapper: Identifiable, Hashable, @unchecked Sendable {

// AFTER
public struct DestinationWrapper: Identifiable, Hashable {
```

**Rationale:** `DestinationWrapper` is only used in `Router.path` which is `@MainActor`. There's no cross-isolation use case. Removing `Sendable` is the honest choice.

**If compiler complains** about `Router.path` being used across isolation:
```swift
// Option B — mark as MainActor-only instead
@MainActor
public struct DestinationWrapper: Identifiable, Hashable {
```

**Acceptance criteria:**
- [ ] Zero `@unchecked Sendable` in codebase
- [ ] Package compiles with strict concurrency checking
- [ ] No new compiler warnings

---

### G8: Unit Tests

**Goal:** Test coverage for all public Router operations.

**New directory:** `Tests/EasyNavigationTests/`

**Test Plan:**

#### RouterTests.swift — Core Navigation
```swift
@MainActor
final class RouterTests: XCTestCase {

    // MARK: - Push

    func test_push_appendsToPath() {
        let router = Router { EmptyView() }
        router.push { Text("A") }
        // Wait for async processing
        let expectation = expectation(description: "push")
        Task { @MainActor in
            await Task.yield()
            XCTAssertEqual(router.path.count, 1)
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 1.0)
    }

    func test_multiplePushes_maintainOrder() { ... }

    func test_push_withBackSwipeDisabled_setsFlag() { ... }

    // MARK: - Pop

    func test_pop_removesLastFromPath() { ... }

    func test_pop_emptyPath_doesNotCrash() { ... }

    func test_popToRoot_clearsEntirePath() { ... }

    // MARK: - replacingPush

    func test_replacingPush_emptyPath_replacesRoot() { ... }

    func test_replacingPush_singleElement_replacesIt() { ... }

    func test_replacingPush_multipleElements_replacesTopOnly() { ... }

    // MARK: - removeAllPush

    func test_removeAllPush_clearsPathAndReplacesRoot() { ... }
}
```

#### RouterPresentationTests.swift — Modal Navigation
```swift
@MainActor
final class RouterPresentationTests: XCTestCase {

    func test_present_setsFullScreenDestination() { ... }

    func test_present_createsChildWithParentRef() { ... }

    func test_sheet_setsSheetDestination() { ... }

    func test_doublePresent_isBlocked() { ... }

    func test_dismiss_clearsParentFullScreen() { ... }

    func test_dismiss_clearsParentSheet() { ... }

    func test_dismiss_withoutParent_isNoOp() { ... }

    func test_dismissPresented_dismissesSheet() { ... }

    func test_dismissPresented_dismissesFullScreen() { ... }

    func test_dismissToRoot_recursivelyDismisses() { ... }
}
```

#### RouterEdgeCaseTests.swift — Stress & Edge Cases
```swift
@MainActor
final class RouterEdgeCaseTests: XCTestCase {

    func test_rapidPushPop_doesNotCorruptPath() { ... }

    func test_cleanup_breaksRetainCycles() { ... }

    func test_cleanup_cancelsProcessingTask() { ... }

    func test_pushAfterCleanup_isNoOp() { ... }

    func test_presentWhilePresenting_isBlocked() { ... }

    func test_isPresenting_reflectsState() { ... }

    func test_isBackSwipeAllowed_reflectsTopOfStack() { ... }
}
```

#### NavigationInformationsTests.swift
```swift
final class NavigationInformationsTests: XCTestCase {

    func test_rootNavigation_isNotPushed_isNotPresented() { ... }

    func test_pushedNavigation_isPushed() { ... }

    func test_presentedNavigation_isPresented() { ... }

    func test_navigationTypes_areCorrect() { ... }
}
```

#### GlobalRouterTests.swift
```swift
@MainActor
final class GlobalRouterTests: XCTestCase {

    func test_showOverlay_addsToViews() { ... }

    func test_dismissOverlay_removesFromViews() { ... }

    func test_dismissNonexistentOverlay_isNoOp() { ... }

    func test_multipleOverlays_managedIndependently() { ... }
}
```

**Acceptance criteria:**
- [ ] Tests directory exists with 5 test files
- [ ] All public Router methods have at least one test
- [ ] Edge cases (empty path pop, double present, rapid operations) tested
- [ ] `swift test` passes
- [ ] Tests run in < 5 seconds total

---

## 6. Dependency Graph

```
G6 (Dead Code)     G7 (Sendable)     G5 (Logging)
     │                   │                │
     │                   │                │
     ▼                   ▼                ▼
G2 (replacingPush) ◄── PHASE 1 ──► Independent fixes
     │
     │ (needs clean codebase first)
     ▼
G1 (AsyncStream) ─────────────────── G3 (SwipeConfig)
     │                                    │
     │                                    │
     ▼                                    ▼
G4 (UINavController) ◄── PHASE 2 ──► G8 (Tests)
                                          │
                                          │ (tests validate all above)
                                          ▼
                                    PHASE 2 COMPLETE
```

**Execution order within phases:**

**Phase 1 (no dependencies between items):**
1. G6 — Remove dead code (clean working surface)
2. G7 — Fix Sendable (one-liner)
3. G2 — Fix replacingPush (localized fix)
4. G5 — Logging (search-and-replace)

**Phase 2 (has dependencies):**
1. G1 — AsyncStream (biggest change, must be first)
2. G3 — SwipeConfiguration (depends on G6 cleanup)
3. G4 — UINavigationController (depends on G3 decision)
4. G8 — Tests (must be last — tests validate everything above)

---

## 7. Migration Plan & Phases

### Phase 1 — Critical Fixes (v1.0.3 or v2.0-alpha)

**Scope:** No public API changes. Drop-in replacement.
**Effort:** ~3 hours
**Risk:** Low

| Step | Task | Files Changed | Effort |
|------|------|---------------|--------|
| 1.1 | Remove dead code files | -3 files | 15min |
| 1.2 | Clean commented-out refs | GlobalRouter, ViewNavWrapper, AppRoot | 15min |
| 1.3 | Fix `@unchecked Sendable` | DestinationWrapper.swift | 5min |
| 1.4 | Fix `replacingPush` index math | Router.swift | 30min |
| 1.5 | Create `NavigationLogger.swift` | +1 file | 15min |
| 1.6 | Replace all `print()` with logger | Router.swift, RouterStack.swift | 45min |
| 1.7 | Compile + manual test | — | 30min |

**Deliverable:** Branch `fix/phase-1-critical`, PR to main.

### Phase 2 — Internal Refactor (v2.0.0)

**Scope:** Internal implementation change. Public API change only if `operationDelay`/`waitForUIUpdate` are removed.
**Effort:** ~12 hours
**Risk:** Medium

| Step | Task | Files Changed | Effort |
|------|------|---------------|--------|
| 2.1 | Implement AsyncStream in Router | Router.swift | 4h |
| 2.2 | Remove SwipeConfiguration, add `isBackSwipeAllowed` | ViewNavWrapper, Router | 1h |
| 2.3 | Remove UINavigationController extension | ViewNavWrapper | 30min |
| 2.4 | Implement BackSwipeConfigurator (if needed) | +1 file, ViewNavWrapper | 2h |
| 2.5 | Deprecate/remove `operationDelay`, `waitForUIUpdate` | Router.swift | 15min |
| 2.6 | Evaluate removing `.id(router.id)` | ViewNavWrapper | 1h |
| 2.7 | Write unit tests | +5 files | 4h |
| 2.8 | Integration test with centauri-ios | — | 2h |

**Deliverable:** Branch `refactor/v2.0`, PR to main.

### Phase 3 — Performance (v2.1.0) — COMPLETED

**Scope:** `.id(wrapper.id)` bug fix, ViewDestination protocol, cleanup
**Effort:** ~2 hours
**Risk:** Low (no API breaking changes)
**Decision:** AnyView full elimination rejected — non-generic Router ile impossible. Detailed analysis in `docs/Phase3-AnyView-Elimination.md`

**What was done:**
- Removed `.id(wrapper.id)` from navigationDestination (biggest perf win — was forcing full view destruction)
- Removed `.id(router.id)` from ViewNavigationWrapper (unnecessary)
- Added `ViewDestination` protocol for opt-in enum routing
- Deprecated `ViewDestinationRepresentable`
- Removed unused `import Combine` from NavigationWrapper/RouterWrapper
- Added `BackSwipeConfigurator` (scoped replacement for removed UINavigationController extension)

### Phase 4 — DeepLinkCenter (v2.2.0) — DONE

**Scope:** URL-based deep linking via sheets.
**Effort:** ~2 hours
**Risk:** Low

#### Yapilan Degisiklikler

**1. DeepLinkCenter.swift olusturuldu (146 satir)**
- URL → View mapping: Consumer `register()` ile handler kaydeder, framework URL parse'a karismaz
- Deep link gelince **sheet** olarak acilir (push degil) — kullanicinin mevcut navigation state'i korunur
- Router hazir degilse URL'ler kuyrukta bekler, `setRootRouter()` cagrilinca son URL teslim edilir
- Zaten sheet/fullscreen aciksa otomatik dismiss edilir, yeni deep link acilir
- Router `weak` tutulur (retain cycle yok)
- `clearPending()` ile kuyruk temizlenebilir

**2. AppRoot.swift guncellendi**
- Opsiyonel `deepLinkCenter` parametreli yeni init eklendi
- Mevcut init degismedi (backward compatible)

**3. Router.path `public internal(set)` yapildi (v2.2.1)**
- Consumer'in `path.count`, `path.isEmpty` gibi read-only erisimi icin
- DevMode stress test yazarken ihtiyac ortaya cikti

**4. 9 unit test eklendi (DeepLinkCenterTests.swift)**
- handle, register, pending queue, clearPending, setRootRouter, dismiss-before-present, unknown URL, multiple handlers

**Consumer kullanimi:**
```swift
let deepLinkCenter = DeepLinkCenter()

deepLinkCenter.register { url in
    if url.path.contains("profile") {
        return ProfileView(userId: url.lastPathComponent)
    }
    return nil
}

// AppRoot'ta:
AppRoot(deepLinkCenter: deepLinkCenter) { ... }

// URL handle:
.onOpenURL { url in deepLinkCenter.handle(url) }
```

### RouterStack — REJECTED

**Karar:** RouterStack (global router tracking) implementasyonu gerekmedigine karar verildi.

**Nedenler:**
1. "Herhangi bir yerden ana sayfaya don" → `router.dismissToRoot()` zaten parent chain ile recursive calisiyor
2. "En ustteki router'a bir sey goster" → DeepLinkCenter root router uzerinden sheet acarak cozuyor
3. Analytics tracking → genelde analytics SDK'lari kendi tracking'ini yapar

**Sonuc:** Tum kullanim senaryolari mevcut API'larla zaten cozulmus. Eklemek speculative complexity olur. Gercek bir ihtiyac dogarsa sonra eklenebilir.

---

## 8. Testing Strategy

### 8.1 Unit Tests

See G8 specification above. All tests are `@MainActor` since Router is `@MainActor`.

**Challenge:** Router operations are async (queued via AsyncStream). Tests need to wait for operations to process.

**Testing pattern:**
```swift
/// Helper to wait for Router's async operations to process
func waitForRouterOperations() async {
    // Yield multiple times to allow stream processing
    await Task.yield()
    await Task.yield()
}

func test_push_appendsToPath() async {
    let router = Router { EmptyView() }
    router.push { Text("A") }
    await waitForRouterOperations()
    XCTAssertEqual(router.path.count, 1)
}
```

### 8.2 Integration Testing with centauri-ios

After Phase 2, update centauri-ios to use v2.0.0 and verify:

| Test Case | How to Verify |
|-----------|---------------|
| Basic push/pop | Navigate forward and back in any feature |
| Tab switching | Switch tabs, verify back swipe is correct per tab |
| Sheet presentation | Open any sheet, dismiss, verify no retain cycle |
| Fullscreen presentation | Open fullscreen modal, navigate inside, dismiss |
| Deep navigation (5+ levels) | Push 5+ views, pop to root, verify clean state |
| CometChat not affected | Open chat, verify navigation gestures work normally |
| Rapid navigation | Tap quickly on multiple navigation buttons |

### 8.3 Memory Testing

Use Xcode Instruments to verify:
- No Router retain cycles after `cleanup()`
- No leaked `AnyView` closures
- No leaked `OperationQueue` threads (should be zero after refactor)

---

## 9. Versioning & Release Strategy

| Version | Contains | Breaking | Release Type |
|---------|----------|----------|--------------|
| **1.0.3** | Phase 1 only (fixes, no API change) | No | Patch — safe for all consumers |
| **2.0.0** | Phase 1 + Phase 2 | Yes (removes `operationDelay`, `waitForUIUpdate`, dead public types) | Major — update consumers |
| **2.1.0** | Phase 3 (AnyView reduction) | Maybe | Minor or Major depending on API impact |
| **2.2.0** | Phase 4 (DeepLinkCenter) | No (additive) | Minor |
| **2.2.1** | Router.path public readable | No (additive) | Patch |

**Recommended approach:**
1. Ship **1.0.3** immediately with Phase 1 fixes (no risk)
2. Ship **2.0.0** after Phase 2 is tested with centauri-ios
3. Update centauri-ios `Package.resolved` to 2.0.0

---

## 10. Risk Analysis

### Phase 1 Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| Removing dead code breaks something | Very Low | Low | Dead code is commented out everywhere |
| Logging change introduces regression | Very Low | Low | Same logic, different output mechanism |
| replacingPush fix changes animation timing | Low | Medium | Test both paths (empty and non-empty) manually |

### Phase 2 Risks

| Risk | Likelihood | Impact | Mitigation |
|------|------------|--------|------------|
| AsyncStream timing differs from Thread.sleep | Medium | High | Extensive testing with rapid navigation |
| Task.yield() not sufficient for SwiftUI render | Medium | High | Can add configurable `Task.sleep(nanoseconds:)` fallback |
| Removing UINavController ext breaks CometChat | Low | High | Test CometChat navigation specifically |
| Back swipe stops working entirely | Medium | Medium | BackSwipeConfigurator as fallback |
| Unit tests are flaky due to async timing | Medium | Low | Use generous timeouts, retry logic |

### Rollback Plan

Each phase is a separate branch/PR. If issues are found:
1. Revert the PR
2. Pin centauri-ios to previous version (1.0.2 or 1.0.3)
3. Investigate and fix on the feature branch

---

## 11. Success Criteria

### Phase 1 Complete When:
- [ ] Package compiles with zero warnings
- [ ] Zero `print()` calls in Sources/
- [ ] Zero `@unchecked Sendable` in Sources/
- [ ] Zero files in Sources/ that aren't imported/used
- [ ] `replacingPush` has bounds checks and correct index math
- [ ] centauri-ios builds and runs with updated package

### Phase 2 Complete When:
- [ ] Zero `Thread.sleep` calls in Sources/
- [ ] Zero `OperationQueue` in Sources/
- [ ] Zero `DispatchQueue.main.async` in Router.swift
- [ ] Zero `extension UINavigationController` in Sources/
- [ ] Zero global/static mutable state
- [ ] `swift test` passes with 100% of public Router API covered
- [ ] centauri-ios integration test passes all scenarios
- [ ] Xcode Instruments shows no Router retain cycles
- [ ] CometChat navigation unaffected

### Overall v2.0.0 Complete When:
All Phase 1 + Phase 2 criteria met, plus:
- [ ] `swift package diagnose-api-breaking-changes` shows only expected removals
- [ ] Git tag `v2.0.0` created
- [ ] centauri-ios updated to `2.0.0` and verified on device

---

## 12. Open Questions

| # | Question | Needs Answer From | Blocks |
|---|----------|-------------------|--------|
| **OQ-1** | AnyView elimination: Enum routing (A), Generic ViewBuilder (B), or Hybrid (C)? | Team | Phase 3 |
| **OQ-2** | Is per-view back swipe control a requirement? Or can we drop it entirely? | Product/UX | G4 approach |
| **OQ-3** | ~~Should DeepLinkCenter come back in v2.2?~~ | ~~Product~~ | **RESOLVED: Yes, implemented in v2.2.0** |
| **OQ-4** | ~~Should RouterStack come back?~~ | ~~Product~~ | **RESOLVED: No, REJECTED — all use cases covered by existing API** |
| **OQ-5** | iOS 18 minimum — is this acceptable? Or need iOS 17 support? | Product | Package.swift |
| **OQ-6** | StressTest views — move to a separate `EasyNavigationDemo` app target? | Team | G6 |
| **OQ-7** | `operationDelay`/`waitForUIUpdate` — deprecate or hard-remove in v2.0? | Team | G1 API surface |
| **OQ-8** | Should `.id(router.id)` be removed? Need testing to verify. | Investigation | G10 in Phase 2 |

---

## 13. Appendix

### A. Full File Diff Summary (Phase 1 + Phase 2)

| File | Phase 1 Changes | Phase 2 Changes |
|------|----------------|-----------------|
| `Router.swift` | Fix replacingPush, replace prints | AsyncStream, remove OperationQueue, remove SwipeConfig refs |
| `ViewNavigationWrapper.swift` | Remove commented refs | Remove UINavController ext, remove SwipeConfiguration, evaluate .id() |
| `GlobalRouter.swift` | Remove commented refs | — |
| `AppRoot.swift` | Remove commented refs | — |
| `DestinationWrapper.swift` | Remove @unchecked Sendable | — |
| `NavigationLogger.swift` | 🆕 Create | — |
| `BackSwipeController.swift` | — | 🆕 Create (if OQ-2 = yes) |
| `RouterStack.swift` | 🗑️ Delete (Phase 1) | REJECTED — not revived |
| `DeepLinkCenter.swift` | 🗑️ Delete (Phase 1) → 🆕 Recreated (Phase 4) | Sheet-based URL deep linking |
| `RouterStressTest.swift` | 🗑️ Delete | — |
| `Tests/*` | — | 🆕 Create 5 test files |

### B. Public API Changes (v1.0.2 → v2.0.0)

**Removed types:**
- `RouterStack` (was public but non-functional — REJECTED, not revived)
- Old `DeepLinkCenter` (was public but non-functional — recreated as new in v2.2.0)
- `StressTestTabView` (was public, demo code)

**Removed properties:**
- `Router.operationDelay` (or deprecated)
- `Router.waitForUIUpdate` (or deprecated)

**Added properties:**
- `Router.isBackSwipeAllowed: Bool` (computed, reactive)
- `Router.path: [DestinationWrapper]` (public internal(set), v2.2.1)

**Added types:**
- `NavigationLogger` (internal, not public)
- `BackSwipeConfigurator` (internal, not public)
- `DeepLinkCenter` (public, v2.2.0 — URL-based deep linking via sheets)
- `ViewDestination` protocol (public, v2.1.0 — enum-based type-safe routing)

**Unchanged public API:**
- `Router.push()`, `pop()`, `popToRoot()`
- `Router.present()`, `sheet()`, `dismiss()`
- `Router.replacingPush()`, `removeAllPush()`
- `Router.dismissPresented()`, `dismissToRoot()`
- `Router.cleanup()`
- `Router.isPresenting`
- `ViewNavigationWrapper` init and usage
- `AppRoot` init and usage
- `GlobalRouter.show()`, `dismiss()`
- `@RouterWrapper`, `@NavigationWrapper`
- `NavigationInformations`
- `ViewDestinationRepresentable`
- `.windowOverlay()` modifier

### C. Reference Links

- [Swift Concurrency: AsyncStream](https://developer.apple.com/documentation/swift/asyncstream)
- [os.Logger](https://developer.apple.com/documentation/os/logger)
- [SwiftUI NavigationStack](https://developer.apple.com/documentation/swiftui/navigationstack)
- [WWDC 2023: Beyond the basics of structured concurrency](https://developer.apple.com/videos/play/wwdc2023/10170/)
- [AnyView performance discussion](https://www.swiftbysundell.com/articles/avoiding-anyview-in-swiftui/)

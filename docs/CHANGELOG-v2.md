# EasyNavigation v2.x — Changelog & Decision Log

**Last Updated:** 2026-03-16
**Original PRD:** `docs/PRD-EasyNavigation-v2.md`
**Phase 3 Analysis:** `docs/Phase3-AnyView-Elimination.md`

---

## Conversation Context (for memory)

Bu refactor Erkut ile birlikte yapildi. Asagidaki tum degisiklikler tek bir conversation session'inda gerceklesti. Erkut iOS developer, EasyNavigation package'ini centauri-ios projesinde kullaniyor. Package sahibi seklabsnet/EasyNavigation.

---

## Git Tag History

| Tag | Commit | Tarih | Icerik |
|-----|--------|-------|--------|
| `v1.0.2-pre-refactor` | 8908ca6 | 2026-03-15 | Refactor oncesi snapshot (olu kod dahil) |
| `v1.0.3-phase1` | 8501f74 | 2026-03-15 | Phase 1: Critical fixes |
| `v2.0.0-phase2` | 005b1c7 | 2026-03-15 | Phase 2: AsyncStream + testler |
| `v2.1.0-phase3` | e1e91fb | 2026-03-15 | Phase 3: .id() fix + ViewDestination |
| (no tag) | 594bb2c | 2026-03-15 | .id(router.id) + Combine import temizligi |
| (no tag) | a326797 | 2026-03-15 | BackSwipeConfigurator eklendi |

---

## Phase 1 — Critical Fixes (v1.0.3-phase1)

### Yapilan Degisiklikler

#### 1. Olu Kod Silindi
- **Ne:** `RouterStack.swift` (83 satir), `DeepLinkCenter.swift` (62 satir), `RouterStressTest.swift` (1161 satir) silindi
- **Neden:** Hicbiri kullanilmiyordu. Tum referanslari commented-out'tu. Toplam 1,306 satir olu kod binary'ye dahil oluyordu. `StressTestTabView` public type olarak consumer'lara gorunuyordu.
- **Etki:** Binary boyutu azaldi, API kirliligi temizlendi

#### 2. Commented-out Referanslar Temizlendi
- **Ne:** `GlobalRouter.swift`, `AppRoot.swift`, `ViewNavigationWrapper.swift` icindeki `RouterStack`, `DeepLinkCenter` referanslari silindi
- **Neden:** Olu koda isaret eden yorumlar kafa karistirici, gereksiz
- **Dosyalar:** GlobalRouter.swift, AppRoot.swift, ViewNavigationWrapper.swift

#### 3. replacingPush Crash Fix
- **Ne:** `Router.swift` icindeki `self.path.remove(at: self.path.count - 3)` → `self.path.count - 2` olarak duzeltildi
- **Neden:** Eski kod path.count < 2 oldugunda negatif index ile crash yapiyordu. path.count == 2 oldugunda ise yanlis elemani (bottom) siliyordu (top yerine).
- **Dogruluk tablosu:**
  - `[]` → replacingPush(D) → root = D (root crossfade)
  - `[A]` → replacingPush(D) → `[D]` (A replaced)
  - `[A,B]` → replacingPush(D) → `[A,D]` (B replaced)
  - `[A,B,C]` → replacingPush(D) → `[A,B,D]` (C replaced)

#### 4. @unchecked Sendable Kaldirildi
- **Ne:** `DestinationWrapper`'dan `@unchecked Sendable` conformance silindi
- **Neden:** `AnyView` Sendable degil. `@unchecked Sendable` compiler'a yalan soyluyordu. `DestinationWrapper` sadece `@MainActor` Router.path icinde kullaniliyor, cross-isolation gereksinimi yok.

#### 5. Global SwipeConfiguration Kaldirildi
- **Ne:** `SwipeConfiguration` static struct ve `SwipeConfiguration.backSwipeAvailable` global mutable state silindi
- **Neden:** Global static boolean tum tab'lardaki NavigationStack'leri etkiliyordu. Tab A'da `allowBackSwipe: false` ile push yapip Tab B'ye gecince Tab B'nin push'u global state'i `true` yapiyordu, Tab A'ya donunce back swipe calismaya basliyordu.
- **Yerine:** `Router.isBackSwipeAllowed` computed property eklendi (per-router, reactive)

#### 6. UINavigationController Retroactive Conformance Kaldirildi
- **Ne:** `extension UINavigationController: @retroactive UIGestureRecognizerDelegate` tamamen silindi
- **Neden:**
  - Tum app'teki UINavigationController'lari etkiliyordu (CometChat dahil)
  - Extension icinde `viewDidLoad` override etmek undefined behavior (Swift doc: "Extensions cannot override existing functionality")
  - `import EasyNavigation` yapmak bile tum nav controller davranisini degistiriyordu (opt-in mekanizmasi yok)
- **Yerine:** Phase sonrasinda BackSwipeConfigurator eklendi (scoped cozum)

#### 7. print() → os.Logger
- **Ne:** Router.swift'teki 22+ `print()` cagirisi `NavigationLogger` (os.Logger wrapper) ile degistirildi. ViewNavigationWrapper'daki print'ler de degistirildi.
- **Neden:**
  - `print()` release build'de compile out olmuyor
  - `stdout` synchronized — lock contention yaratir
  - Memory address leak edebilir (ObjectIdentifier basiliyordu)
  - Her emoji+string interpolation heap allocation yaratir
- **Yeni dosya:** `NavigationLogger.swift` — debug/warning/error seviyeleri, `com.seklabs.EasyNavigation` subsystem ile Console.app'te filtrelenebilir

---

## Phase 2 — AsyncStream Concurrency (v2.0.0-phase2)

### Yapilan Degisiklikler

#### 1. OperationQueue + Thread.sleep → AsyncStream
- **Ne:** Router'daki concurrency mekanizmasi tamamen degistirildi:
  - Eski: `OperationQueue` (background, serial) → `DispatchQueue.main.async` → `Thread.sleep(0.01)`
  - Yeni: `AsyncStream<@MainActor @Sendable () -> Void>` + `Task.yield()`
- **Neden:**
  - `Thread.sleep` non-cooperative block — Swift runtime baska task schedule edemiyor
  - 10ms magic number — yavas cihazda az, hizli cihazda fazla
  - `DispatchQueue.main.async` + `Thread.sleep` sirasi garanti degil — main async blogu sleep bitmeden execute olmayabilir
  - 3 farkli concurrency primitive (OperationQueue + GCD + POSIX Thread) 15 satirda
- **Nasil calisir:**
  - `startOperationProcessor()` init'te cagriliyor
  - `AsyncStream.makeStream(bufferingPolicy: .unbounded)` ile stream + continuation olusturuluyor
  - `executeOperation()` closure'u `continuation.yield()` ile queue'ya atiyor
  - Background task `for await` ile FIFO sirasi ile isliyor
  - Her operasyondan sonra `Task.yield()` — SwiftUI'ye state commit firsati veriyor
  - `cleanup()` ve `deinit` icinde `continuation.finish()` + `task.cancel()`
- **Kaldirilan:** `operationQueue`, `operationDelay`, `waitForUIUpdate`, `import Combine` (Router'dan)

#### 2. Unit Testler (25 test)
- **Ne:** `Tests/EasyNavigationTests/` dizini olusturuldu, 4 dosyada 25 test yazildi
- **Dosyalar:**
  - `RouterTests.swift` — push, pop, popToRoot, backSwipe (8 test)
  - `RouterPresentationTests.swift` — present, sheet, dismiss, double-present (8 test)
  - `RouterEdgeCaseTests.swift` — replacingPush, cleanup, rapid ops, dismissToRoot (9 test)
  - `TestHelpers.swift` — `waitForRouterOperations()` async helper
- **Package.swift:** testTarget eklendi

---

## Phase 3 — Performance Fix (v2.1.0-phase3)

### AnyView Analiz Sureci

Phase 3 icin 3 yaklasim detayli analiz edildi (`docs/Phase3-AnyView-Elimination.md`):

**A) Enum Routing (RED):** Router generic olmali → Environment injection kirilir, parent refs kirilir, tum consumer API kirilir. Generic cascade tum kodu etkiler. 50+ ekranlik projede impractical.

**B) Generic ViewBuilder (RED):** Swift type system `some View` closure'larini array'de tutmaya izin vermiyor. `any View` = AnyView performansi. Calismaz.

**C) Hybrid (KABUL, ama sadece gerçek kazanım olanlar):** Durustce analiz yapildi:
- Deferred closure storage: AnyView hala render tree'de, SwiftUI hala full rebuild yapiyor. Kozmetik.
- Concrete wrapper views: Ustte stabil tip ama body icinde AnyView. Marjinal.
- `.id(wrapper.id)` kaldirma: **GERCEK kazanim.** Bug fix. NavigationStack zaten Hashable identity sagliyor, `.id()` forced full destruction yapiyordu.

**Karar:** Sadece gercek etki yaratan degisiklikler yapildi, kozmetik refactor yapilmadi.

### Yapilan Degisiklikler

#### 1. .id(wrapper.id) Kaldirildi (BUG FIX)
- **Ne:** `ViewNavigationWrapper.swift`'te `.navigationDestination` icindeki `.id(wrapper.id)` silindi
- **Neden:** Her `DestinationWrapper` unique UUID'ye sahip. NavigationStack path degistiginde SwiftUI `.id()` degerinin degistigini goruyordu ve tum destination view subtree'yi yok edip sifirdan olusturuyordu. NavigationStack zaten `Hashable` path uzerinden identity sagliyor — `.id()` tamamen gereksiz ve aktif olarak zararli.
- **Etki:** Navigation sirasindaki frame drop'larin buyuk kismini cozer

#### 2. .id(router.id) Kaldirildi
- **Ne:** `ViewNavigationWrapper.swift`'te en disttaki `.id(router.id)` silindi
- **Neden:** `router.id` init'te set edilip hic degismiyor, aktif zarar vermiyor ama gereksiz. SwiftUI'nin view reuse'unu engelleyebilir.

#### 3. ViewDestination Protocol Eklendi
- **Ne:** `ViewDestinationRepresentable.swift`'e yeni `ViewDestination` protocol eklendi + Router extension'lari (push/present/sheet)
- **Neden:** Consumer isteğe bagli olarak enum-based type-safe routing kullanabilsin. AnyView'siz navigation icin opt-in yol.
- **Eski:** `ViewDestinationRepresentable` deprecated edildi (AnyView donduruyor)
- **Kullanim:**
  ```swift
  enum AppRoute: ViewDestination {
      case profile(id: String)
      var body: some View { ProfileView(userId: id) }
  }
  router.push(AppRoute.profile(id: "123"))
  ```
- **NOT:** Bu hala DestinationWrapper icinde AnyView'a sariliyor. Non-generic Router ile tam eliminasyon mumkun degil. Ama consumer tarafinda type-safe API sunuyor.

#### 4. Unused Combine Import Temizligi
- **Ne:** `NavigationWrapper.swift` ve `RouterWrapper.swift`'ten `import Combine` silindi
- **Neden:** Kullanilmiyordu

---

## Phase 3.5 — BackSwipeConfigurator

### Yapilan Degisiklikler

#### 1. BackSwipeConfigurator Eklendi
- **Ne:** `BackSwipeConfigurator.swift` olusturuldu — `UIViewControllerRepresentable` tabanli scoped back swipe kontrol
- **Neden:** Phase 1'de UINavigationController extension kaldirilinca `allowBackSwipe: false` calismaz hale gelmisti. Yeni cozum sadece EasyNavigation'in kendi NavigationStack'ini etkiliyor.
- **Nasil calisir:**
  - `BackSwipeProxyController` parent hierarchy'de yukari yuruyerek kendi UINavigationController'ini buluyor
  - `UIGestureRecognizerDelegate` ile `interactivePopGestureRecognizer`'i kontrol ediyor
  - ViewNavigationWrapper'da `.background(BackSwipeConfigurator(isEnabled: wrapper.allowsBackSwipe))` ile baglandi
- **Fark (eski vs yeni):**
  - Eski: `extension UINavigationController` → TUM app etkilenir
  - Yeni: `BackSwipeConfigurator` → SADECE EasyNavigation'in NavigationStack'i

---

## Mevcut Dosya Envanteri (2026-03-16)

```
Sources/EasyNavigation/
├── EasyNavigation.swift              # Entry point (no-op)
├── Router.swift                      # Core — AsyncStream based, ~316 satir
├── ViewNavigationWrapper.swift       # NavigationStack + sheet/fullscreen bindings
├── AppRoot.swift                     # GlobalRouter environment injection
├── GlobalRouter.swift                # Window overlay management
├── WindowOverlay.swift               # PassThroughWindow + overlay modifier
├── NavigationWrapper.swift           # @NavigationWrapper property wrapper
├── RouterWrapper.swift               # @RouterWrapper property wrapper
├── DestinationWrapper.swift          # NavigationPath item wrapper
├── NavigationInformations.swift      # isPushed/isPresented state
├── ViewDestinationRepresentable.swift # ViewDestination protocol + deprecated old
├── NavigationLogger.swift            # os.Logger wrapper
└── BackSwipeConfigurator.swift       # Scoped back swipe control

Tests/EasyNavigationTests/
├── RouterTests.swift                 # 8 test
├── RouterPresentationTests.swift     # 8 test
├── RouterEdgeCaseTests.swift         # 9 test
└── TestHelpers.swift                 # waitForRouterOperations helper

docs/
├── PRD-EasyNavigation-v2.md          # Original PRD (Phase 1-2 detayli, Phase 3-4 placeholder)
├── Phase3-AnyView-Elimination.md     # Phase 3 derin analiz (AnyView, 3 yaklasim, neden Hybrid)
└── CHANGELOG-v2.md                   # BU DOSYA — tum degisiklik logi
```

---

## Kalan Acik Maddeler

### Karar Bekleyen

| # | Madde | Durum | Karar Gerektiren |
|---|-------|-------|-----------------|
| 1 | DeepLinkCenter revival | Phase 4 — deep linking gerekli mi? | Product |
| 2 | RouterStack revival | Phase 4 — global router tracking gerekli mi? | Product |
| 3 | AnyView tam eliminasyonu | Generic Router gerektirir, tum API kirilir, 50+ ekran refactor | Mimari karar |

### Potansiyel Iyilestirmeler (oncelik dusuk)

| # | Madde | Aciklama |
|---|-------|----------|
| 1 | Overlay system AnyView | GlobalRouter + WindowOverlay hala AnyView kullaniyor, deferred closure yapilabilir ama etki dusuk |
| 2 | AnyView root storage | Router.root hala AnyView, deferred closure yapilabilir ama etki dusuk |
| 3 | Test coverage artirma | GlobalRouter, NavigationInformations, ViewDestination testleri eksik |

---

## Memory'ye Iletilmesi Gerekenler

### Project Memory
- EasyNavigation v1.0.2'den v2.1.0'a refactor yapildi (2026-03-15/16)
- 4 phase tamamlandi: critical fixes → AsyncStream → performance fix → BackSwipeConfigurator
- 1,306 satir olu kod silindi, 25 unit test eklendi
- Kalan: DeepLinkCenter ve RouterStack karari bekleniyor (Phase 4)

### Technical Decisions Memory
- AnyView tam eliminasyonu non-generic Router ile MUMKUN DEGIL — bu karar verildi ve belgelendi
- Enum routing (generic Router) API'yi tamamen kirar, impractical — bu karar verildi
- `.id(wrapper.id)` en buyuk performance killer'di — kaldirildi
- UINavigationController extension yerine scoped BackSwipeConfigurator kullaniliyor
- Thread.sleep + OperationQueue yerine AsyncStream + Task.yield kullaniliyor
- print() yerine os.Logger (NavigationLogger) kullaniliyor

### User Preferences Memory
- Erkut durustluk ve net analiz istiyor — kozmetik iyilestirme yerine gercek etki
- "En iyi yontem bu mu?" sorusunu sormak onemli — premature optimization'dan kacin
- Kararlar icin trade-off tablosu ver, secimi kullaniciya birak
- Turkce iletisim (teknik terimler Ingilizce kalabilir)

### Repository Memory
- Package: seklabsnet/EasyNavigation (GitHub)
- Platform: iOS 18+, Swift 6.1
- Consumer: centauri-ios projesi (CometChat SDK de kullaniyor)
- Test: xcodebuild test ile iOS Simulator'da calistiriliyor (swift test calismaz — Testing framework)
- Build: `swift build --sdk \`xcrun --sdk iphonesimulator --show-sdk-path\` -Xswiftc -target -Xswiftc arm64-apple-ios18.0-simulator`
- Simulator: iPhone 16 (id: DCC40CA0-886D-4F1D-A3F3-34E930B55459, OS 18.1)

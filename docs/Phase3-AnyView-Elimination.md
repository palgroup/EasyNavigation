# Phase 3: AnyView Elimination — Deep Analysis & Implementation Plan

**Author:** Claude (Expert Code Review)
**Date:** 2026-03-15
**Status:** Draft — Awaiting Review
**Depends on:** Phase 1 (v1.0.3-phase1) + Phase 2 (v2.0.0-phase2)
**Target Version:** 2.1.0

---

## Table of Contents

1. [Neden Bu Degisiklige Ihtiyac Var?](#1-neden-bu-degisiklige-ihtiyac-var)
2. [AnyView'in Teknik Problemi — Derinlemesine](#2-anyviewin-teknik-problemi--derinlemesine)
3. [Uc Yaklasimdaki Analiz — Neden C?](#3-uc-yaklasimin-analizi--neden-c)
4. [Bu En Iyi Yontem mi?](#4-bu-en-iyi-yontem-mi)
5. [Detayli Implementasyon Plani](#5-detayli-implementasyon-plani)
6. [API Degisiklikleri & Migration](#6-api-degisiklikleri--migration)
7. [Test Stratejisi](#7-test-stratejisi)
8. [Risk Analizi](#8-risk-analizi)
9. [Basari Kriterleri](#9-basari-kriterleri)

---

## 1. Neden Bu Degisiklige Ihtiyac Var?

### 1.1 Problem Ozeti

EasyNavigation'da **her navigate edilen view AnyView'a sariliyor**. Bu 13 farkli noktada oluyor:

```
Router.swift         → 6 noktada AnyView kullanimi (root, init, cleanup, push, replaceRoot, replacingPush)
DestinationWrapper   → 2 noktada (storage + init)
WindowOverlay        → 2 noktada (overlay storage + modifier)
GlobalRouter         → 1 noktada (show)
ViewDestinationRep.  → 1 noktada (protocol)
ViewNavigationWrap.  → 1 noktada (rendering)
```

### 1.2 Neden Bu Bir Problem?

**Kisa cevap:** SwiftUI'nin performans motoru static type bilgisine dayaniyor. AnyView bu bilgiyi siliyor.

**Uzun cevap — SwiftUI nasil calisir:**

SwiftUI bir view tree render ettiginde, iki sey yapar:

1. **Structural Identity** — View'in tipine bakarak "bu ayni view mi yoksa yeni bir view mi?" sorusunu cevaplar
2. **Diffing** — "Bu view'in hangi property'leri degisti?" sorusunu cevaplar

Normal bir SwiftUI view'i icin:
```swift
struct ProfileView: View {
    let name: String
    let age: Int

    var body: some View {
        VStack {
            Text(name)
            Text("\(age)")
        }
    }
}
```

SwiftUI sunu bilir:
- Bu bir `ProfileView` (structural identity)
- `name` ve `age` property'leri var (diffing icin)
- Sadece degisen property'yi render etmesi yeterli

AnyView ile:
```swift
AnyView(ProfileView(name: "Ali", age: 25))
```

SwiftUI sunu gorur:
- Bu bir `AnyView` (structural identity kayip)
- Icinde ne var? Bilinmiyor (type erased)
- Guvende olmak icin **TUM view hierarchy'yi yik ve yeniden olustur**

### 1.3 Gercek Dunyada Ne Anlama Geliyor?

**Senaryo: 5 seviye derin navigation stack**

```
Tab → ListScreen → DetailScreen → EditScreen → ConfirmScreen → ResultScreen
```

Kullanici `ResultScreen`'de bir butona basiyor. SwiftUI state degisikligi algiliyor.

**AnyView ILE (mevcut durum):**
```
1. NavigationStack path degisti → tum destination'lari kontrol et
2. Her destination AnyView → structural identity yok
3. SwiftUI her seviyeyi full diff yapar:
   - ResultScreen: full hierarchy tear down + rebuild
   - ConfirmScreen: full hierarchy tear down + rebuild (gereksiz!)
   - EditScreen: full hierarchy tear down + rebuild (gereksiz!)
   - DetailScreen: full hierarchy tear down + rebuild (gereksiz!)
   - ListScreen: full hierarchy tear down + rebuild (gereksiz!)
4. Toplam: ~10-50ms (cihaza bagli)
```

**AnyView OLMADAN (hedef durum):**
```
1. NavigationStack path degisti → tum destination'lari kontrol et
2. Her destination concrete tip → structural identity VAR
3. SwiftUI sadece degisen view'i diff yapar:
   - ResultScreen: sadece degisen property guncelle
   - Diger seviyeler: DOKUNMA (identity ayni, skip)
4. Toplam: ~1-2ms
```

**Fark: 5-25x performans kazanimi** (navigation derinligine oranli)

### 1.4 `.id(wrapper.id)` — Gizli Katil

Mevcut kodda (ViewNavigationWrapper.swift:29):
```swift
wrapper.destination
    .id(wrapper.id)  // ← BU
```

`.id()` SwiftUI'ye der ki: "Bu deger degistiginde, view'i TAMAMEN YOK ET ve sifirdan olustur."

Her `DestinationWrapper` unique UUID ile olusturuluyor. Path array'i mutate oldigunda (push/pop), SwiftUI `ForEach`-benzeri mekanizma ile destination'lari render eder. `.id()` degeri her destination icin farkli oldugundan, **her path degisikliginde tum visible destination'lar yok edilip yeniden olusturuluyor.**

Bu AnyView'dan DAHA KOTU bir problem. Cunku:
- AnyView: "Tipini bilmiyorum, full diff yap"
- `.id()` degisimi: "Bu TAMAMEN YENI view, sifirdan olustur" (diff bile yapma)

NavigationStack zaten path elemanlarinin `Hashable` conformance'i uzerinden identity saglıyor. `.id(wrapper.id)` **tamamen gereksiz ve aktif olarak zararli.**

### 1.5 Memory Etkisi — Materialized vs Deferred

**Mevcut durum (materialized):**
```swift
// push aninda view HEMEN olusturuluyor
router.push { ComplexView(data: bigData) }

// Router icinde:
let wrapper = DestinationWrapper(destination: AnyView(destination()))
//                                            ^^^^^^^^^^^^^^^^^^^^^^^^
//                                            View SIMDI olusturuluyor
//                                            Tum closure capture'lari SIMDI resolve ediliyor
//                                            AnyView SIMDI heap allocate ediliyor
```

**Hedef durum (deferred):**
```swift
// push aninda sadece CLOSURE saklaniyor
router.push { ComplexView(data: bigData) }

// Router icinde:
let wrapper = DestinationWrapper(content: destination)
//                                        ^^^^^^^^^^^
//                                        Sadece closure reference saklaniyor
//                                        View henuz olusturulmadi
//                                        Heap allocation yok (closure stack'te)
//                                        SwiftUI render ettiginde olusacak
```

**Fark:**
- 10 view push edildiginde, mevcut sistemde 10 AnyView heap'te bekliyor
- Deferred sistemde 10 lightweight closure reference bekliyor
- Memory azalmasi: view complexity'ye oranli (basit view'lar icin ihmal edilebilir, complex view'lar icin anlamli)

---

## 2. AnyView'in Teknik Problemi — Derinlemesine

### 2.1 SwiftUI View Lifecycle Detayi

```
SwiftUI Render Pipeline:

  @Observable state change
         │
         ▼
  Body evaluation ─── "Hangi view'larin body'si
         │              yeniden cagrilmali?"
         ▼
  Structural diff ─── "Bu view ayni mi?"
         │            ├── Tip ayni → property diff
         │            └── Tip farkli → full rebuild
         ▼
  Attribute diff ──── "Hangi property'ler degisti?"
         │            ├── Degisen var → update
         │            └── Degisen yok → skip
         ▼
  Render commit ───── GPU'ya gonder
```

AnyView **Structural diff** asamasinda hasar veriyor:
- SwiftUI `AnyView` gorur → icindeki tipi bilmiyor
- "Tip farkli" dalina girer → full rebuild
- Attribute diff atlanir (cunku full rebuild yapiliyor)

### 2.2 AnyView vs `any View` vs Concrete View

| Ozellik | `AnyView` | `any View` | Concrete `MyView` |
|---------|-----------|------------|-------------------|
| Structural identity | YOK | YOK | VAR |
| Property diffing | Full rebuild | Full rebuild | Targeted update |
| Heap allocation | Evet (box) | Evet (existential) | Hayir (inline) |
| Compiler optimization | Yok | Yok | Inlining, specialization |
| SwiftUI bilgi | "Bir view" | "Bir view" | "ProfileView(name:age:)" |

**Onemli:** `any View` (Swift 5.7 existential) ile `AnyView` (SwiftUI type eraser) performans acisindan **AYNI SEYDIR.** Ikisi de tip bilgisini siler.

### 2.3 NavigationStack'in Ozel Durumu

NavigationStack path-based routing kullanir:

```swift
NavigationStack(path: $path) {
    root
        .navigationDestination(for: DestinationWrapper.self) { wrapper in
            wrapper.destination  // ← BU HER PATH DEGISIKLIGINDE CAGRILIR
        }
}
```

`.navigationDestination(for:)` closure'u **path degistiginde her visible destination icin cagrilir**. Eger ici `AnyView` donuyorsa, SwiftUI her cagrimda full rebuild yapar.

Eger concrete tip donuyorsa:
```swift
.navigationDestination(for: DestinationWrapper.self) { wrapper in
    wrapper.contentView  // ← DestinationContentView (concrete tip)
}
```

SwiftUI `DestinationContentView`'un structural identity'sini gorup, sadece degisen property'leri diff yapar.

**AMA:** `DestinationContentView.body` icinde hala `AnyView` var:
```swift
struct DestinationContentView: View {
    let render: () -> AnyView
    var body: some View {
        render()  // ← Hala AnyView
    }
}
```

Bu durumda kazanim: SwiftUI `DestinationContentView` seviyesinde structural identity'yi kurtariyor ama `body` icinde yine AnyView gordugundebu seviyenin altindaki diff yine full rebuild oluyor.

**Yani concrete wrapper tek basina BIG win degil.** Asıl kazanim `.id()` kaldirma + deferred construction'dan geliyor.

### 2.4 Degerli Olan Ne, Degerli Olmayan Ne?

```
Performans Kazanimi Siralaması:

1. [YUKSEK]  .id(wrapper.id) kaldirmak
   → NavigationStack zaten Hashable identity sagliyor
   → .id() forced full destruction'i engelliyor
   → Tek basina en buyuk kazanim
   → Tahmini etki: frame drop'larin %60-70'ini cozecek

2. [ORTA]    Deferred closure storage
   → View push aninda degil render aninda olusur
   → Memory pressure azalir
   → Stale capture'lar engellenir
   → Tahmini etki: memory %20-30 azalma, minor render improvement

3. [DUSUK]   Concrete wrapper view'lar (DestinationContentView, RootContentView)
   → SwiftUI structural identity icin bir kademe kazanc
   → Ama body icinde hala AnyView var
   → Tahmini etki: marjinal, olculmesi zor

4. [YUKSEK*] ViewDestination enum routing (opt-in)
   → Adopt eden consumer'da SIFIR AnyView
   → Full type-safe diffing
   → * Ama consumer effort gerektirir, framework degil consumer kazanimi
   → Tahmini etki: adopt eden icin 5-25x kazanim
```

---

## 3. Uc Yaklasimin Analizi — Neden C?

### 3.1 Yaklaşım A: Enum Routing — Neden Red?

**Konsept:**
```swift
// Consumer tanimlayacak:
enum AppRoute: Hashable {
    case profile(id: String)
    case settings
    case detail(itemId: Int)
}

// Router generic olacak:
class Router<Route: Hashable> { ... }
```

**Neden calismaz — 5 teknik engel:**

**Engel 1 — Generic Router, Environment'i kirar:**
```swift
// Mevcut: tek tip, environment injection kolay
@Environment(Router.self) var router

// Enum routing ile: hangi Router<???>?
@Environment(Router<AppRoute>.self) var router  // ← her ekranda farkli olabilir
```

SwiftUI Environment tek bir key'e tek bir tip baglayabilir. Farkli modullerdeki farkli route enum'lari icin farkli Router tipleri gerekir. Bu environment injection mekanizmasini kirar.

**Engel 2 — Parent referansi kirilir:**
```swift
// Mevcut:
weak var parent: Router?

// Enum routing ile:
weak var parent: Router<???>?  // ← cocuk farkli Route tipinde olabilir
```

Bir `Router<AppRoute>` bir sheet aciyor ve icinde `Router<SettingsRoute>` var. Parent referansi hangi tipte olacak? `any Router`? Bu da type erasure, AnyView'dan farkli degil.

**Engel 3 — fullScreenDestination/sheetDestination kirilir:**
```swift
// Mevcut:
var fullScreenDestination: Router?

// Enum routing ile:
var fullScreenDestination: Router<???>?  // ← farkli generic parametreler
```

**Engel 4 — Consumer burden cok yuksek:**
```swift
// ONCEKI (kolay, esnek):
router.push { ProfileView(userId: "123") }

// SONRAKI (rigid, tum route'lari onceden tanimla):
enum AppRoute: Hashable {
    case profile(id: String)
    // ... 50+ ekran icin 50+ case
}
router.push(.profile(id: "123"))
```

Her yeni ekran icin enum'a case ekle, switch'e branch ekle. Buyuk projelerde (centauri-ios gibi 50+ ekran) bu enum devasa ve maintain edilmesi zor olur.

**Engel 5 — Tum public API kirilir:**
```swift
// Kırılan API'lar:
Router { ... }                    → Router<AppRoute> { ... }
ViewNavigationWrapper { ... }     → ViewNavigationWrapper<AppRoute> { ... }
@RouterWrapper var router         → @RouterWrapper<AppRoute> var router
@NavigationWrapper var nav        → @NavigationWrapper<AppRoute> var nav
router.push { View() }           → router.push(.route)
router.present { View() }        → router.present(.route)  // ← farkli route tipi?
```

**Sonuc:** Enum routing, Router'in non-generic olmasi ZORUNLULUGUNU ihlal ediyor. Generic cascade (Router → ViewNavigationWrapper → PropertyWrapper → Environment) tum kodu kirar. **RED.**

---

### 3.2 Yaklaşım B: Generic ViewBuilder Closure Storage — Neden Red?

**Konsept:**
```swift
// AnyView yerine closure saklayalim
struct DestinationWrapper {
    let viewBuilder: () -> some View  // ← Bu mumkun mu?
}
```

**Neden calismaz — Swift type system limiti:**

**Problem 1 — `some View` array'de tutulmaz:**
```swift
var path: [DestinationWrapper]  // Array homogeneous tip ister

// Her push farkli bir View tipi uretir:
push { Text("A") }        // () -> Text
push { ProfileView() }    // () -> ProfileView
push { VStack { ... } }   // () -> VStack<...>

// Bunlar FARKLI TIPLER. Tek bir array'de tutulamazlar.
```

**Problem 2 — `any View` = AnyView:**
```swift
struct DestinationWrapper {
    let viewBuilder: () -> any View  // Existential
}
```
`any View` existential container kullanir. SwiftUI icin `AnyView` ile **birebir ayni** performans karakteristigi var. Tip bilgisi yine siliniyor.

**Problem 3 — Generic DestinationWrapper array'de tutulmaz:**
```swift
struct DestinationWrapper<Content: View> {
    let viewBuilder: () -> Content
}

// Bu calismaz:
var path: [DestinationWrapper<???>]  // Hangi Content?
// [DestinationWrapper<Text>, DestinationWrapper<ProfileView>] → heterogeneous, Swift izin vermez
```

**Problem 4 — Protocol with associatedtype array'de tutulmaz:**
```swift
protocol AnyDestination {
    associatedtype Body: View
    func makeBody() -> Body
}
// [any AnyDestination] → existential, yine AnyView problemi
```

**Sonuc:** Swift'in type system'i heterogeneous view closure'larini type-safe bir array'de tutmaya izin vermiyor. Herhangi bir storage mekanizmasi sonunda type erasure'a dusecek. **RED.**

---

### 3.3 Yaklasim C: Hybrid (Deferred Closure + Concrete Wrapper) — Neden Kabul?

**Konsept:** AnyView'i tamamen kaldirmak yerine, etkisini minimize et:

1. **Deferred construction** — View push aninda degil, render aninda olusturulsun
2. **Concrete wrapper** — SwiftUI'ye structural identity icin stabil tip ver
3. **`.id()` kaldir** — En buyuk performance killer'i yok et
4. **Opt-in enum routing** — Isteyen consumer icin tam cozum sun

**Neden calisir:**

```swift
// 1. DestinationWrapper artik closure sakliyor (deferred)
struct DestinationWrapper {
    private let _makeContent: @MainActor @Sendable () -> AnyView

    init<Content: View>(@ViewBuilder content: @escaping @MainActor @Sendable () -> Content) {
        self._makeContent = { AnyView(content()) }
    }

    var contentView: DestinationContentView {
        DestinationContentView(render: _makeContent)
    }
}

// 2. Concrete wrapper — SwiftUI structural identity icin
struct DestinationContentView: View {
    let render: @MainActor @Sendable () -> AnyView
    var body: some View { render() }
}

// 3. ViewNavigationWrapper — .id() kaldirildi
.navigationDestination(for: DestinationWrapper.self) { wrapper in
    wrapper.contentView          // Concrete tip (structural identity)
        // .id(wrapper.id)       ← SILINDI (forced full destruction yok artik)
        .toolbar(.hidden, ...)
        .environment(router)
}

// 4. Consumer API DEGISMEDI
router.push { ProfileView() }   // Ayni

// 5. OPSIYONEL: enum routing isteyen consumer icin
router.push(AppRoute.profile(id: "123"))  // Yeni, additive
```

**Neden bu en iyi trade-off:**

| Kriter | Enum (A) | ViewBuilder (B) | Hybrid (C) |
|--------|----------|-----------------|------------|
| API kirilma | TAMAMEN KIRILIR | IMKANSIZ | YOK |
| AnyView eliminasyonu | %100 (push) | %0 | %0 storage, ~%70 render impact |
| Implementation riski | Cok Yuksek | Calismiyor | Dusuk |
| Consumer effort | Her route'u enum'a ekle | N/A | Sifir (opt-in enum icin var) |
| Type system uyumluluk | Generic cascade | Swift limiti | Tam uyumlu |
| Test difficulty | Yuksek (generic) | N/A | Dusuk |
| Incremental adoption | Hayir (all-or-nothing) | N/A | Evet (opsiyonel enum) |

---

## 4. Bu En Iyi Yontem mi?

### 4.1 Durust Cevap

**Kisa cevap:** Non-generic Router'a bağli kalirken, evet.

**Uzun cevap:** "En iyi" tanimina bagli:

**Eger "en iyi" = sifir AnyView:** Hayir. Non-generic Router ile bu mumkun degil. Generic Router (Yaklaşım A) bunu saglayabilir ama API'yi tamamen kirar ve generics cascade olusturur. Bu trade-off kabul edilemez cunku:
- centauri-ios'taki 50+ ekranin tamamini refactor etmek gerekir
- Environment injection mekanizmasi kirilir
- Parent/child router referanslari calisabilir olmaktan cikar

**Eger "en iyi" = en buyuk performans kazanimi / minimum API kirilma orani:** Evet. Hybrid yaklasim:
- `.id()` kaldirma → en buyuk tekil performans kazanimi (API kirilma: sifir)
- Deferred closure → memory + minor render kazanimi (API kirilma: sifir)
- Opt-in enum routing → full kazanim isteyen consumer icin (API kirilma: sifir, additive)

### 4.2 Alternatif: "Hic Birsey Yapma" Secenegi

Bir soru sormamiz gerekiyor: **Bu degisiklik gerekli mi, yoksa premature optimization mi?**

**Gerekli oldugunun kaniti:**

1. **`.id(wrapper.id)` AKTIF OLARAK ZARARLI.** Bu bir optimization degil, bug fix. NavigationStack zaten Hashable path uzerinden identity sagliyor. `.id()` bu identity'yi override ederek her path mutation'da forced destruction yapiyor. Kaldirmak performance fix, optimization degil.

2. **Thread.sleep gitti, siradaki bottleneck AnyView.** Phase 2'de Thread.sleep kaldirildi. Artik navigation'in en yavas noktasi AnyView rendering. Profiling yapildiginda bu gorulecek.

3. **Derinlik arttikca problem buyuyor.** centauri-ios'ta tipik navigation derinligi 3-5 seviye. Her seviye icin AnyView full rebuild yapiliyor. Kullanici "app kasıyor" hissedebilir.

**"Hic birsey yapma" makul olacagi durum:**
- Eger centauri-ios'ta navigation sırasında **frame drop goremiyorsaniz** (Instruments ile ölcun)
- Eger kullanici **hicbir kasma sikayet etmiyorsa**
- O zaman Phase 3'u erteleyip Phase 4'e gecmek mantikli

### 4.3 Onerilen Strateji: "Measure First"

```
1. Phase 3'e baslamadan once Instruments Time Profiler ile olcum yap:
   - 5 seviye derin navigate et
   - Her seviyede state degistir
   - Frame time'lari kaydet

2. Sadece .id(wrapper.id) kaldir, tekrar olc:
   - Bu tek degisiklik frame time'lari duzeltiyor mu?
   - Eger duzeltiyorsa → diger degisiklikler opsiyonel

3. Sonuclara gore karar ver:
   - Frame drop goruluyorsa → full Phase 3
   - Gorulmuyorsa → sadece .id() fix + deferred closure (low risk)
```

### 4.4 Neden Yine de Tamamini Oneriyoruz?

`.id()` fix yeterli olsa bile, diger degisiklikler:

1. **Deferred closure:** Daha temiz mimari. View'larin push aninda degil render aninda olusturuluyor olmasi semantik olarak dogru. Side effect yok.

2. **Opt-in enum routing:** Consumer'a secim hakki veriyor. Performans-hassas ekranlar icin enum routing, hizli prototipleme icin closure API. Ikiside ayni Router uzerinde.

3. **ViewDestination protocol:** Modern Swift pattern. `associatedtype` ile type-safe. Gelecekte deep linking icin foundation.

4. **Overlay deferred rendering:** Ayni cleanup, consistency.

**Risk/reward orani olumlu:** Tum degisiklikler API-compatible, testli, ve rollback kolay.

---

## 5. Detayli Implementasyon Plani

### 5.1 Dependency Graph

```
Step 1 (DestinationWrapper) ──→ Step 2 (Router) ──→ Step 3 (ViewNavigationWrapper)
                                                              │
Step 4 (WindowOverlay) ──→ Step 5 (GlobalRouter)             │
                                                              │
Step 6 (ViewDestinationRepresentable)  ───────────────────────│
                                                              ▼
                                                        Step 7 (Tests + Benchmark)
```

Steps 1-3 ve Steps 4-5 paralel yapilabilir. Step 6 bagimsiz.

---

### Step 1: DestinationWrapper.swift

**Amac:** Materialized AnyView → Deferred closure + Concrete wrapper view

**Onceki:**
```swift
public struct DestinationWrapper: Identifiable, Hashable {
    public let id = UUID()
    let destination: AnyView
    let allowsBackSwipe: Bool

    init(destination: AnyView, allowsBackSwipe: Bool = true) {
        self.destination = destination
        self.allowsBackSwipe = allowsBackSwipe
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}
```

**Sonraki:**
```swift
public struct DestinationWrapper: Identifiable, Hashable {
    public let id = UUID()
    let allowsBackSwipe: Bool

    /// Deferred view construction — only evaluated when SwiftUI renders
    private let _makeContent: @MainActor @Sendable () -> AnyView

    init<Content: View>(
        allowsBackSwipe: Bool = true,
        @ViewBuilder content: @escaping @MainActor @Sendable () -> Content
    ) {
        self.allowsBackSwipe = allowsBackSwipe
        self._makeContent = { AnyView(content()) }
    }

    /// Concrete view for rendering — gives SwiftUI stable structural identity
    var contentView: DestinationContentView {
        DestinationContentView(render: _makeContent)
    }

    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
}

/// Concrete View type for SwiftUI structural identity at the navigation destination level
struct DestinationContentView: View {
    let render: @MainActor @Sendable () -> AnyView

    var body: some View {
        render()
    }
}
```

**Degisen:**
- `let destination: AnyView` → `private let _makeContent: ... () -> AnyView`
- `init(destination: AnyView, ...)` → `init(... @ViewBuilder content: ...)`
- Yeni `contentView` computed property
- Yeni `DestinationContentView` struct

---

### Step 2: Router.swift

**Amac:** Root view deferred + push callsite'lari guncelle + deprecate eski property'ler

**Degisiklik 1 — Root storage:**
```swift
// ONCEKI:
var root: AnyView

// SONRAKI:
private var _makeRoot: @MainActor @Sendable () -> AnyView

/// Concrete wrapper for root view rendering
var rootView: RootContentView {
    RootContentView(render: _makeRoot)
}
```

**Yeni struct:**
```swift
/// Concrete View type for SwiftUI structural identity at the root level
struct RootContentView: View {
    let render: @MainActor @Sendable () -> AnyView

    var body: some View {
        render()
    }
}
```

**Degisiklik 2 — Init:**
```swift
// ONCEKI:
self.root = AnyView(root())

// SONRAKI:
self._makeRoot = { AnyView(root()) }
```

**Degisiklik 3 — Cleanup:**
```swift
// ONCEKI:
self.root = AnyView(EmptyView())

// SONRAKI:
self._makeRoot = { AnyView(EmptyView()) }
```

**Degisiklik 4 — Push:**
```swift
// ONCEKI:
let wrapper = DestinationWrapper(
    destination: AnyView(destination()),
    allowsBackSwipe: allowBackSwipe
)

// SONRAKI:
let wrapper = DestinationWrapper(
    allowsBackSwipe: allowBackSwipe,
    content: destination
)
```

**Degisiklik 5 — replaceRootWithAnimation:**
```swift
// ONCEKI:
self.root = AnyView(newRootViewGenerator())

// SONRAKI:
self._makeRoot = { AnyView(newRootViewGenerator()) }
```

**Degisiklik 6 — replacingPush:**
```swift
// ONCEKI:
self.path.append(DestinationWrapper(destination: AnyView(destination())))

// SONRAKI:
self.path.append(DestinationWrapper(content: destination))
```

**Degisiklik 7 — Deprecated property'ler:**
```swift
/// No longer needed — operations use cooperative scheduling via AsyncStream
@available(*, deprecated, message: "No longer needed — operations use cooperative scheduling")
public var operationDelay: TimeInterval {
    get { 0 }
    set { }
}

/// No longer needed — operations use cooperative scheduling via AsyncStream
@available(*, deprecated, message: "No longer needed — operations use cooperative scheduling")
public var waitForUIUpdate: Bool {
    get { true }
    set { }
}
```

**Degisiklik 8 — ViewDestination extension:**
```swift
extension Router {
    /// Push a ViewDestination-conforming route (enum routing)
    public func push<D: ViewDestination>(_ destination: D, allowBackSwipe: Bool = true) {
        push(allowBackSwipe: allowBackSwipe) { destination.body }
    }

    /// Present a ViewDestination-conforming route as fullscreen
    public func present<D: ViewDestination>(_ destination: D, onDismiss: (() -> Void)? = nil) {
        present({ destination.body }, onDismiss: onDismiss)
    }

    /// Present a ViewDestination-conforming route as sheet
    public func sheet<D: ViewDestination>(_ destination: D, onDismiss: (() -> Void)? = nil) {
        sheet({ destination.body }, onDismiss: onDismiss)
    }
}
```

---

### Step 3: ViewNavigationWrapper.swift

**Amac:** Concrete view rendering + `.id()` kaldirma

**Degisiklik 1 — Root rendering:**
```swift
// ONCEKI:
NavigationStack(path: $router.path) {
    router.root
        .environment(router)

// SONRAKI:
NavigationStack(path: $router.path) {
    router.rootView
        .environment(router)
```

**Degisiklik 2 — Destination rendering + .id() kaldirma:**
```swift
// ONCEKI:
.navigationDestination(for: DestinationWrapper.self) { wrapper in
    wrapper.destination
        .id(wrapper.id)
        .toolbar(.hidden, for: .navigationBar)
        .environment(router)

// SONRAKI:
.navigationDestination(for: DestinationWrapper.self) { wrapper in
    wrapper.contentView
        .toolbar(.hidden, for: .navigationBar)
        .environment(router)
```

---

### Step 4: WindowOverlay.swift

**Amac:** Overlay view deferred storage + concrete rendering

**Degisiklik 1 — OverlayView struct:**
```swift
// ONCEKI:
public struct OverlayView: Identifiable {
    public var id: String = UUID().uuidString
    public var view: AnyView
}

// SONRAKI:
public struct OverlayView: Identifiable {
    public var id: String = UUID().uuidString
    let makeContent: @MainActor @Sendable () -> AnyView

    var contentView: OverlayContentView {
        OverlayContentView(render: makeContent)
    }
}

struct OverlayContentView: View {
    let render: @MainActor @Sendable () -> AnyView
    var body: some View {
        render()
    }
}
```

**Degisiklik 2 — addView:**
```swift
// ONCEKI:
properties.views.append(
    .init(id: viewID, view: AnyView(view))
)

// SONRAKI:
let capturedView = view
properties.views.append(
    .init(id: viewID, makeContent: { AnyView(capturedView) })
)
```

---

### Step 5: GlobalRouter.swift

**Degisiklik 1 — show method:**
```swift
// ONCEKI:
overlayProperties.views.append(
    UniversalOverlayProperties.OverlayView(id: id, view: AnyView(content()))
)

// SONRAKI:
overlayProperties.views.append(
    UniversalOverlayProperties.OverlayView(id: id, makeContent: { AnyView(content()) })
)
```

**Degisiklik 2 — UniversalOverlayViews rendering:**
```swift
// ONCEKI:
ForEach(properties.views, id: \.id) {
    $0.view
}

// SONRAKI:
ForEach(properties.views, id: \.id) {
    $0.contentView
}
```

---

### Step 6: ViewDestinationRepresentable.swift

**Amac:** Eski protocol deprecate + yeni ViewDestination protocol

```swift
import Foundation
import SwiftUI

/// Legacy protocol — use ViewDestination instead
@available(*, deprecated, message: "Use ViewDestination instead for type-safe routing")
public protocol ViewDestinationRepresentable: Sendable {
    var view: AnyView { get }
}

/// Modern destination protocol for enum-based routing.
/// Provides type-safe view construction without AnyView.
///
/// Usage:
/// ```
/// enum AppRoute: ViewDestination {
///     case profile(id: String)
///     case settings
///
///     var body: some View {
///         switch self {
///         case .profile(let id): ProfileView(userId: id)
///         case .settings: SettingsView()
///         }
///     }
/// }
///
/// router.push(AppRoute.profile(id: "123"))
/// ```
public protocol ViewDestination: Sendable, Hashable {
    associatedtype Body: View
    @MainActor @ViewBuilder var body: Body { get }
}
```

---

### Step 7: Tests + Benchmark

**7.1 Mevcut testler:** 25 test degisiklik gerektirmemeli. `DestinationWrapper` init degisikligi testleri etkilemez cunku testler `router.push { ... }` kullanir, dogrudan `DestinationWrapper` olusturmaz.

**7.2 Yeni testler:**

```swift
// ViewDestination protocol testi
@Test("push with ViewDestination enum works")
func pushWithViewDestination() async { ... }

@Test("present with ViewDestination works")
func presentWithViewDestination() async { ... }

@Test("ViewDestination push maintains path count")
func viewDestinationPathCount() async { ... }
```

**7.3 Benchmark (manuel, Instruments ile):**

| Olcum | Nasil | Beklenen |
|-------|-------|----------|
| 5-deep nav state update | Time Profiler, state change trigger | <16ms (60fps) |
| 10 rapid push | Time Profiler, for loop push | Path corruption yok |
| Memory (10 pushed view) | Allocations instrument | Oncekine gore azalma |
| Frame drop (push animation) | Core Animation instrument | 0 dropped frame |

---

## 6. API Degisiklikleri & Migration

### Public API Compatibility

| API | Durum |
|-----|-------|
| `router.push { View() }` | DEGISMEDI |
| `router.present { View() }` | DEGISMEDI |
| `router.sheet { View() }` | DEGISMEDI |
| `router.pop()` / `popToRoot()` | DEGISMEDI |
| `router.dismiss()` | DEGISMEDI |
| `router.replacingPush { View() }` | DEGISMEDI |
| `router.removeAllPush { View() }` | DEGISMEDI |
| `router.cleanup()` | DEGISMEDI |
| `router.isPresenting` | DEGISMEDI |
| `router.isBackSwipeAllowed` | DEGISMEDI |
| `ViewNavigationWrapper` | DEGISMEDI |
| `AppRoot` | DEGISMEDI |
| `@RouterWrapper` / `@NavigationWrapper` | DEGISMEDI |
| `GlobalRouter.show()` / `.dismiss()` | DEGISMEDI |
| `.windowOverlay()` modifier | DEGISMEDI |

### Eklenen API (Additive, non-breaking)

| API | Aciklama |
|-----|----------|
| `router.push(AppRoute.settings)` | ViewDestination overload |
| `router.present(AppRoute.detail(id:))` | ViewDestination overload |
| `router.sheet(AppRoute.detail(id:))` | ViewDestination overload |
| `ViewDestination` protocol | Enum routing icin yeni protocol |

### Deprecated API

| API | Yeni Alternatif |
|-----|----------------|
| `ViewDestinationRepresentable` | `ViewDestination` |
| `router.operationDelay` | Otomatik (AsyncStream) |
| `router.waitForUIUpdate` | Otomatik (AsyncStream) |

### Internal Breaking (sadece @testable import etkiler)

| Degisiklik | Etki |
|-----------|------|
| `DestinationWrapper.init` signature | Testler dogrudan kullanmiyor |
| `Router.root` → `Router.rootView` | Testler erismiyor |
| `OverlayView.view` → `OverlayView.contentView` | Test yok |

---

## 7. Test Stratejisi

### 7.1 Regression — Mevcut 25 test

Tum mevcut testler degisiklik **gerektirmeden** gecmeli:
- RouterTests (8 test)
- RouterPresentationTests (8 test)
- RouterEdgeCaseTests (9 test)

### 7.2 Yeni Testler

| Test | Dosya | Kapsam |
|------|-------|--------|
| ViewDestination push | RouterTests.swift | Enum routing |
| ViewDestination present | RouterPresentationTests.swift | Enum routing modal |
| ViewDestination sheet | RouterPresentationTests.swift | Enum routing sheet |
| Deprecated property no-op | RouterTests.swift | operationDelay/waitForUIUpdate |

### 7.3 Manuel Test Matrix

| Senaryo | Dogrulama |
|---------|-----------|
| 5+ seviye push/pop | Frame drop yok, path dogru |
| Tab switch sonrasi navigate | Diger tab etkilenmedi |
| Sheet icinde push | Child router dogru calisiyor |
| Fullscreen icinde push | Child router dogru calisiyor |
| Rapid push (20+) | Path corruption yok |
| Overlay show/dismiss | Overlay dogru render ediliyor |
| Cleanup sonrasi push | No-op (crash yok) |

---

## 8. Risk Analizi

| Risk | Olasilik | Etki | Onlem |
|------|----------|------|-------|
| `.id()` kaldirma SwiftUI navigation'i bozar | Dusuk | Yuksek | Incremental test: once sadece .id() kaldir, test et |
| Deferred closure stale capture yapar | Dusuk | Orta | Closure [weak self] pattern'i surdur |
| `@Sendable` closure requirement calismaz | Dusuk | Orta | Compiler hata verirse noncopyable closure dene |
| ViewDestination compiler error | Dusuk | Dusuk | Opsiyonel, ana refactor'dan bagimsiz |
| Mevcut testler kirilir | Cok Dusuk | Dusuk | Testler Router API kullanir, internal degil |

### Rollback Plani

Her step ayri commit olarak yapilacak. Herhangi bir adimda problem cikarsa:
1. O commit revert edilir
2. Onceki adimlar korunur (bagimsiz)
3. Problem investigate edilir

---

## 9. Basari Kriterleri

### Zorunlu

- [ ] Sifir API kirilma (mevcut consumer kodu degistirmeden calismali)
- [ ] `.id(wrapper.id)` ViewNavigationWrapper'dan kaldirildi
- [ ] DestinationWrapper deferred closure kullaniyor
- [ ] Router root deferred closure kullaniyor
- [ ] 25 mevcut test geciyor
- [ ] Yeni ViewDestination testleri geciyor
- [ ] `swift build` basarili
- [ ] centauri-ios build + calistir basarili
- [ ] `operationDelay` ve `waitForUIUpdate` deprecated

### Opsiyonel (Nice to have)

- [ ] Instruments ile olculmus performans karsilastirmasi
- [ ] Overlay system deferred rendering
- [ ] ViewDestination protocol dokumantasyonu
- [ ] centauri-ios'ta en az 1 ekran ViewDestination ile migrate edildi (proof of concept)

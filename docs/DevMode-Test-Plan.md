# DevMode Interactive Test Plan

**Version:** EasyNavigation v2.3.0
**Total Tests:** 41
**Date:** 2026-03-16

---

## 0. DevMode Erisim (4 test)

| ID | Test | Yapilacak | Beklenen | Fail If |
|----|------|-----------|----------|---------|
| ACCESS-001 | Shake ile ac | Cmd+Ctrl+Z | DevMode acilir, Device Info + Tools gorunur | Shake tetiklemiyorsa ShakeDetector bozuk |
| ACCESS-002 | Close butonu | DevMode'da X'e bas | DevMode kapanir, tab view geri gelir | Kapanmiyorsa binding sorunu |
| ACCESS-003 | Navigation Demo ac | Tools > Navigation Stress Test | FullScreen acilir, X butonu sag ustte | Acilmiyorsa ViewNavigationWrapper sorunu |
| ACCESS-004 | Navigation Demo kapat | X butonuna bas | Demo kapanir, DevMode'a doner | Ikisi birden kapanirsa binding hatasi |

---

## 1. Push / Pop / PopToRoot (5 test)

| ID | Buton | Beklenen | Fail If |
|----|-------|----------|---------|
| PUSH-001 | Push Single View | Depth: 1, Path count: 1, mavi arka plan, isPushed=YES | Path count yanlis, animasyon yok |
| PUSH-002 | Push 5 Deep Chain | Depth: 5, Path count: 5, pembe arka plan. Pop 4x ile geri don | Son depth 5 degil, sira bozuk |
| PUSH-003 | Push 10 Deep Chain | Depth: 10, Path count: 10. Pop to Root ile tek hamlede don | 10 view push olmamis, popToRoot calismamis |
| PUSH-004 | ReplacingPush | "Original" gorunur → 0.5s sonra "Replaced!" olur. Path count hep 1 | Path count 2 olursa replacement basarisiz |
| PUSH-005 | RemoveAllPush | 3 push → 1s sonra "NEW ROOT" gorunur, path count 0. Eski root'a donus yok | Path count 0 degil, eski root erisilebilir |

---

## 2. Sheet / FullScreen / Dismiss (7 test)

| ID | Buton | Beklenen | Fail If |
|----|-------|----------|---------|
| SHEET-001 | Present Sheet | Sheet yukari kayar, partial height, drag indicator var. navigationType=.sheet | FullScreen olarak acilir |
| SHEET-002 | Present FullScreen | Tam ekran, drag yok. navigationType=.present | Partial height, pull-to-dismiss calisiyor |
| SHEET-003 | Sheet with onDismiss | Dismiss edince console'da `[DevMode] Sheet onDismiss callback fired!` | Callback ateslenmedi veya 2 kez ateslendi |
| SHEET-004 | Nested Sheets (3 levels) | L1→L2→L3 acilir. L3'te "MAX DEPTH". Dismiss ile tek tek geri don | Level atliyor, MAX DEPTH yanlis yerde |
| SHEET-005 | Nested FullScreens (3 levels) | 3 fullscreen acilir. L3'te DismissToRoot → hepsi kapanir, demo'ya doner | Sadece 1 level kapaniyor |
| SHEET-006 | Sheet + Push inside | Sheet icinde push calisir. Dismiss ile tum sheet kapanir | Sheet icinde push calismiyor, parent etkileniyor |
| SHEET-007 | DismissToRoot (from deep) | 3 nested sheet → DismissToRoot → hepsi + ilk sheet kapanir | Bazi sheet'ler acik kaliyor |

---

## 3. Deep Links (4 test)

| ID | Buton | Beklenen | Fail If |
|----|-------|----------|---------|
| DEEP-001 | Deep Link: profile/123 | Sheet acilir: "Type: Profile", "ID: 123" | Sheet acilmiyor, yanlis type/ID |
| DEEP-002 | Deep Link: settings | Sheet acilir: "Type: Settings", ID yok | ID gorunuyor olmamali |
| DEEP-003 | Deep Link: unknown | Hicbir sey olmaz. Console'da handler returned nil | Sheet acilirsa handler yanlis match ediyor |
| DEEP-004 | Deep Link while sheet open | Turuncu sheet → 1s sonra profile sheet'e degisir | Iki sheet ayni anda, veya deep link acilmiyor |

---

## 4. Back Swipe (3 test)

| ID | Buton | Beklenen | Fail If |
|----|-------|----------|---------|
| SWIPE-001 | Push (swipe enabled) | Yesil arka plan, sol kenardan swipe ile geri don | Swipe calismiyor |
| SWIPE-002 | Push (swipe DISABLED) | Kirmizi arka plan, swipe calismaz. Pop butonu ile don | Swipe calisiyorsa BackSwipeConfigurator bozuk |
| SWIPE-003 | Mixed: on > off > on | Depth 3: swipe ON → Depth 2: swipe OFF → Depth 1: swipe ON | State "yapisiyor", disabled'dan sonra enabled calismiyor |

---

## 5. Stress Tests (5 test)

| ID | Buton | Beklenen | Fail If |
|----|-------|----------|---------|
| STRESS-001 | Rapid Push 20x | Depth: 20, Path: 20. PopToRoot ile don | 20'den az push, freeze, crash |
| STRESS-002 | Rapid Push 5 + Pop 3 | 5 push → 0.5s → 3 pop → final depth 2 | Son depth 2 degil, race condition |
| STRESS-003 | Push 10 + PopToRoot | 10 push → 1s → tek animasyonla root'a don | 10 ayri pop animasyonu gorunuyor |
| STRESS-004 | Sheet > Push 5 > DismissToRoot | Sheet icinde 5 push → 3s → hepsi + sheet kapanir | Sheet acik kaliyor |
| STRESS-005 | Double Present | Ilk sheet gorunur, ikinci BLOCKED. Console'da hata log | Iki presentation ayni anda |

---

## 6. Edge Cases (4 test)

| ID | Buton | Beklenen | Fail If |
|----|-------|----------|---------|
| EDGE-001 | Pop on empty stack | Hicbir sey olmaz, crash yok | CRASH (removeLast on empty array) |
| EDGE-002 | Dismiss without parent | Hicbir sey olmaz, crash yok | NavigationDemo kapaniyor |
| EDGE-003 | DismissPresented with nothing | Hicbir sey olmaz, console log | Crash |
| EDGE-004 | Push > Pop cycle (5x) | 5 kez push/pop, sonunda path count 0 | Path count 0 degil, state bozulmus |

---

## 7. Genel Kontroller (6 test)

| ID | Test | Beklenen | Fail If |
|----|------|----------|---------|
| GEN-MEMORY-001 | Instruments: tum testleri calistir → DevMode kapat | Router instance'lari temizlenir, deinit log gorunur | Router leak, memory surekli artiyor |
| GEN-MEMORY-002 | 5x Rapid Push 20x tekrarla | Her popToRoot sonrasi memory baseline'a doner | Linear memory artisi |
| GEN-ANIMATION-001 | Tum push/pop/sheet testleri | Smooth animasyonlar, frame drop yok | Animasyon yok veya stutter |
| GEN-TAB-001 | Tab switch ile nav state | Her tab kendi state'ini korur | Tab degisince state sifirlaniyor |
| GEN-TAB-002 | Farkli tab'da shake → DevMode | DevMode kapaninca ayni tab'a doner | Farkli tab'a donuyor |
| GEN-NAVINFO-001 | Push/Sheet/FullScreen'de NavInfoBar | isPushed, isPresenting, navigationType dogru | Yanlis degerler |

---

## 8. Kombinasyon Testleri (3 test)

| ID | Test | Beklenen | Fail If |
|----|------|----------|---------|
| COMBO-001 | Push → Sheet → Push inside → Pop → Dismiss → Pop | Her adimda dogru router calisir | Yanlis router etkileniyor |
| COMBO-002 | Push 5 → FullScreen → DismissToRoot | FullScreen kapanir, 5 push KALIR (dismissToRoot path'i temizlemez) | Push'lar da siliniyor |
| COMBO-003 | Sheet icinde ReplacingPush | Sheet'in router'inda path count 1 kalir | Parent router etkileniyor |

---

## Risk Alanlari

1. **DeepLinkCenter** dogrudan router property mutate ediyor (AsyncStream'i bypass ediyor) — race condition riski
2. **BackSwipeConfigurator** delegate lifecycle — rapid push'ta stale delegate riski
3. **dismissToRoot** push path'i temizlemiyor — dogru davranis ama kafa karistirabilir

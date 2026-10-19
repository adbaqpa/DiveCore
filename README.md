# DiveCore — Tüplü Dalış Bilgisayarı (watchOS)

Apple Watch Ultra için gerçek zamanlı dalış bilgisayarının **saf Swift çekirdeği**.
Kapsam: **ADIM 1–13 + ticaret/metin aşaması** tamamlandı — dekompresyon çekirdeği, sensörler ve
alarmlar, watchOS arayüzü, kalıcılık ve senkronizasyon, GF/çoklu gaz/derin
duraklar, su kilidi, uçuş yasağı ve tekrarlı dalış hesabı, komplikasyonlar,
iPhone tarafında harita + etkileşimli grafik + UDDF/FIT dışa aktarma,
pil optimizasyonu (kırmızı gece modu + dinamik örnekleme), sınır durum/stres
testleri ve TestFlight dağıtım hazırlığı.

> ⚠️ **Güvenlik notu:** Bu bir eğitim/proje çalışmasıdır. Dekompresyon
> parametreleri hayat kurtarıcı niteliktedir. Gerçek dalışlarda kullanılmadan
> önce çekirdek, üretici yazılımları (Shearwater, Subsurface, MultiDeco) ve
> deneysel tablolarla ayrıca çapraz doğrulamalıdır. Apple Watch'ta herkese açık
> bir **derinlik sensörü API'si yoktur**; ADIM 2'deki çözüm CoreMotion
> tabanlıdır (bkz. bölüm 3.1).

---

## 1. Dizin yapısı

```
Sources/DiveCore/                 ← Saf çekirdek (watchOS bağımsız, test edilebilir)
├── Models/
│   ├── DivePhysics.swift         Derinlik ↔ basınç, alveoler gaz fiziği
│   ├── GasMix.swift              Gaz karışımı (EAN/O2/trimix), MOD, güvenlik sabitleri
│   ├── DiveState.swift           Anlık dalış durumu, uyarılar, emniyet durağı, biçimlendirme
│   ├── LoggedDive.swift          Kalıcı/senkronize edilebilir dalış kaydı (ADIM 5)
│   ├── DiveReport.swift          Dalış sonu raporu + deko durakları (ADIM 4)
│   └── GasBlendPlanner.swift     Çoklu gaz planı, MOD, gaz değişimi (ADIM 6)
│   ├── DepthReading.swift        Sensör örneği (ADIM 2)
│   └── LogEntry.swift            DiveSample (profil noktası) + LogEntry (dalış günlüğü)
├── Services/
│   ├── TissueModel.swift         ZH-L16C katsayıları, Schreiner, tavan (ceiling), GF99
│   ├── GradientFactors.swift     GF Low/High ayarı ve derinliğe göre interpolasyon
│   ├── DecoEngine.swift          NDL, TTS, deko planı, GF99, uçuş yasağı
│   ├── DeepStopCalculator.swift  GUE tarzı yuvarlanmış derin duraklar (ADIM 6)
│   ├── DiveRoute.swift           GPS rota, Haversine, harita bölgesi (ADIM 10)
│   ├── EnergyManager.swift       Pil/termal durumu, enerji bütçesi, tema çözümü (ADIM 11)
│   ├── AdaptiveSampler.swift     Faz + harekete göre dinamik örnekleme (ADIM 11)
│   └── Commerce/             Monetizasyon çekirdeği (test edilebilir)
│       ├── Entitlement.swift        Kapsamlar, özellik anahtarları, yetkiler
│       ├── ProductCatalog.swift     Ürün kimlikleri, teklifler, günlük sınırı
│       ├── FeatureGate.swift        Erişim kararları ve paywall tetikleri
│       ├── SafetyPolicy.swift       Güvenlik kabiliyetleri (asla kilitlenmez)
│       ├── AppStoreListing.swift    Mağaza metinleri + Apple karakter sınırları
│       └── AppPrivacy.swift         App Store Connect gizlilik beyanı
│   ├── UDDFExporter.swift        UDDF 3.3.0 XML dışa aktarımı (ADIM 10)
│   ├── FITExporter.swift         FIT ikili dışa aktarımı + CRC-16 (ADIM 10)
│   ├── DiveExportService.swift   Çok biçimli dışa aktarma + veri denetimi (ADIM 10)
│   ├── OxygenToxicity.swift      CNS (NOAA) ve OTU hesapları
│   ├── DepthSensor.swift         Sensör protokolü + MockDepthSensor (ADIM 2)
│   ├── DiveSimulator.swift       Gerçekçi dalış profili üreteci (ADIM 2)
│   ├── AscentRateMonitor.swift   Hız yumuşatma + ihlal tespiti (ADIM 2)
│   ├── AlarmCoordinator.swift    Uyarı → titreşim/görsel alarm politikası (ADIM 2)
│   ├── DecoStopPlan.swift        Planlanan deko durakları (varış/kalış/kalkış) (ADIM 4)
│   ├── AscentAdvisor.swift       Çıkış rehberi: tavan tamponu, sonraki dura (ADIM 4)
│   ├── OxygenStatus.swift        PO₂/CNS/OTU risk seviyeleri ve alarmı (ADIM 4)
│   ├── DiveSyncEngine.swift      Watch⇄iPhone kuyruk/çakışma çözümü (ADIM 5)
│   ├── DiveChartData.swift       Grafik serileri + min/max indirgeme (ADIM 5)
│   ├── GradientFactorCatalog.swift GF ön ayarları + derinlik/süre önerisi (ADIM 6)
│   └── DeepStopCalculator.swift  GUE tarzı derin duraklar (ADIM 6)
└── Managers/
    ├── DiveConfiguration.swift   Oturum yapılandırması
    └── DiveSessionController.swift  Sensör → motor → durum akışı (ADIM 2)

Sources/DiveCore/Presentation/    ← Ekranda ne gösterileceğinin kararı (test edilebilir)
├── DiveDisplay.swift             Metinler, renk rolleri, göstergeler, AOD sadeleştirmesi
├── DiveAccessoryData.swift       Action Button niyeti, komplikasyon verisi, dalış özeti
├── DiveReportDisplay.swift       Deko planı, çıkış rehberi, oksijen kartı, zengin özet (ADIM 4)
└── DiveSettingsDisplay.swift      GF / gaz / derin durak ayar ekranı verisi (ADIM 6)

Sources/DiveWatch/                ← Yalnızca watchOS (ince donanım adaptörü)
├── WatchHapticEngine.swift       WKInterfaceDevice titreşimleri
├── CMAltimeterDepthSource.swift  CoreMotion derinlik/basınç
├── WatchHeadingSource.swift      CoreLocation/CoreMotion pusola
├── WatchWaterLockAdapter.swift    Extended runtime + su atma tonu (ADIM 7)
├── SurfaceIntervalBackgroundAdapter.swift Arka plan uçuş yasağı takibi (ADIM 8)
├── WatchPowerAdapter.swift       Pil/termal okuma + extended runtime politikası (ADIM 11)
└── DiveSystem.swift              Bileşenleri birleştiren sistem sınıfı

Sources/DiveStore/                ← Yalnızca iOS/watchOS (SwiftData)
└── SwiftDataDiveLogStore.swift   @Model eşlemesi + DiveLogStore uygulaması

Sources/DiveCharts/               ← watchOS + iOS (Swift Charts, yerelde derlenir)
├── DiveChartViews.swift          Profil grafiği, günlük OTU/CNS barları, aylık sütunlar

Sources/DivePhoneUI/              ← Yalnızca iOS (ADIM 10)
├── DiveRouteMapView.swift        MapKit haritası + kamera + sürüklenme uyarısı
├── DiveChartView.swift           Etkileşimli derinlik-zaman grafiği
├── DiveExportScreen.swift        UDDF / FIT / JSON dışa aktarma + denetim
└── DiveDetailScreen.swift        Grafik / harita / dışa aktarma ayrıntı ekranı

Sources/DiveWatchUI/              ← Yalnızca watchOS (SwiftUI)
├── DiveTheme.swift               DiveColorRole → Color, DiveTextRole → Font
├── DiveComponents.swift          Derinlik halkası, hız göstergesi, pusola, banner
├── DiveScreen.swift              Ana dalış ekranı + hazırlık + özet ekranı
├── DiveComplications.swift       accessoryCircular / Rectangular / Inline / Corner
├── DiveActionIntent.swift        Action Button (LiveActivityIntent) bağlantısı
├── DecoScreens.swift             Çıkış rehberi, oksijen kartı, deko planı, yüzey aralığı
├── DiveReportScreen.swift        Dalış sonu özeti (kesintiler, duraklar, istatistikler)
├── DiveLogbookScreen.swift       Dalış günlüğü listesi + istatistikler
├── DiveSettingsScreen.swift      GF kaydırıcısı, EAN seçici, derin durak (ADIM 6)
├── DiveLockOverlay.swift         Dokunma kilidi + su atma katmanı + acil menü (ADIM 7)
├── RepetitiveDiveScreen.swift    Tekrar dalış hesaplayıcısı ekranı (ADIM 8)
├── DiveSurfaceComplications.swift Yüzey aralığı / uçuş yasağı komplikasyonları (ADIM 9)
├── EnergySettingsScreen.swift    Profil, gece modu, AOD, canlı pil ölçümü (ADIM 11)
├── DiveRootView.swift            Mod seçimi + önizlemeler
└── DiveViewModel.swift           Controller → @Published sunum durumu

Tools/DiveCheck/                  Kalibrasyon raporu (`swift run DiveCheck`)
App/                             Dağıtım yapılandırması (ADIM 13)
├── watchOS/Info.plist           watchOS uygulaması (izinler + arka plan modları)
├── iOS/Info.plist               iOS eşlikçi (konum, HealthKit, BGTask)
├── WidgetExtension/Info.plist   Komplikasyon uzantısı
└── Assets.xcassets/             AppIcon + komplikasyon önizleme manifestleri
Sources/DiveCommerce/            StoreKit 2 servisi (iOS/watchOS)
└── StoreManager.swift         Satın alma, geri yükleme, yetki tazeleme
App/Store/                      Mağaza metinleri ve gizlilik belgeleri
├── AppStoreMetinleri.md       Ad, alt başlık, açıklama (TR/EN), anahtar kelime
├── GizlilikPolitikasi.md      Yayınlanabilir gizlilik politikası
└── AppPrivacyBeyani.md        App Store Connect beyanı (adım adım)
Config/                          Xcode derleme ayarları (ADIM 13)
├── Base.xcconfig / Debug / Release
└── Watch.xcconfig / iOS / Widget (hedef başına kimlik + plist)
Tools/PlistCheck/                Dağıtım doğrulayıcı (`swift run PlistCheck`)
Tests/DiveCoreTests/              1014 birim testi (XCTest)
```

### Katman mimarisi
```
Sensörler (DiveWatch) ──► DiveSessionController ──► DiveState ──► DiveDisplayBuilder ──► SwiftUI (DiveWatchUI)
                                  │                      │                    │
                                  │                      │                    └──► DiveComplicationBuilder (saat yüzü)
                                  │                      └──► DiveAccessoryData (Action Button, özet)
                                  ├──► DecoEngine ──► TissueModel (ZH-L16C)
                                  ├──► AscentRateMonitor ──► AlarmCoordinator ──► HapticEngine
                                  └──► LogEntry (ADIM 5'te SwiftData / WatchConnectivity)
```
Tüm **mantık** — dekompresyon algoritması, alarm politikası ve ekranda ne
gösterileceği — platformdan bağımsızdır. Donanım çağrıları `DiveWatch`,
görsel katman `DiveWatchUI` içindedir. Böylece 572 test Xcode/Simülatör
gerektirmeden koşar.

---

## 2. ADIM 1 — Dekompresyon çekirdeği (Bühlmann ZH-L16C)

Kaynaklar: Bühlmann (1984/2002), Wikipedia "Bühlmann decompression algorithm",
Subsurface `core/deco.c`.

### 2.1 Alveoler inert gaz basıncı
```
P_alv = (P_amb − P_H2O) · f_inert        P_H2O = 0.0627 bar
```

### 2.2 Doku yüklenmesi — Schreiner denklemi (16 kompartman)
```
P_t(t) = P_alv(0) + R·(t − 1/k) − (P_alv(0) − P_t(0) − R/k)·e^(−k·t)
k = ln2 / yarı_ömür
```
> Uygulamada **1–4 saniyelik adımlar** kullanılmalıdır. Schreiner denklemi sabit
> hızlı solunan basınç değişimi varsayar; çok büyük adımlar hızlı kompartmanlarda
> gecikme hatasına yol açar.

### 2.3 M-değeri ve tavan
```
P_igtol  = a + P_amb / b
P_amb_tol = (P_tissue − gf·a) / (gf/b + 1 − gf)      ← tavan basıncı
GF99    = (P_tissue − P_surface) / (P_igtol(P_surface) − P_surface)
```
- `gf` yüzeyde **GF High**, dalışın en derin tavanında **GF Low** olur, arada
  basınca göre lineer interpolasyonla değişir.
- **Tavan** = tüm kompartmanların `P_amb_tol` değerlerinin en büyüğü, 3 m'lik
  ızgaraya aşağı yuvarlanır.

### 2.4 Türetilen çıktılar
| Çıktı | Yöntem |
|---|---|
| **NDL** | Mevcut derinlikte sabit kalınarak ileri simülasyon |
| **TTS** | 9 m/dk çıkış + her durakta "tavan temizlenene kadar" bekleme (saf O2) |
| **Uçuş yasağı** | GF99 ≤ %20'ye düşme süresi + 60 dk pay, 15 dk'ya yuvarlanır |
| **CNS / OTU** | NOAA tek doz limit tablosu / `0.5/(PO₂−0.5)^0.83` |

### 2.5 Kalibrasyon (`swift run DiveCheck`, bölüm 2)
GF 100/100 ile üretilen NDL'ler PADI RDP ile örtüşür:

| Derinlik | Model | PADI RDP |
|---|---|---|
| 12 m | 178 dk | 147 dk |
| 18 m | 59 dk | 56 dk |
| 20 m | 46 dk | 45 dk |
| 30 m | 16 dk | 20 dk |
| 40 m | 7 dk | 9 dk |

---

## 3. ADIM 2 — Sensörler, Simülatör ve Alarmlar

### 3.1 watchOS derinlik ölçümü (donanım gerçekliği)
Apple Watch Ultra'da **derinlik ölçen herkese açık bir API yoktur** (Apple'ın Depth
uygulaması özel donanım kullanır ve dışarıya açık değildir). En yakın kamuya açık
sinyal `CMAltimeter`'ın **göreli yüksekliğidir**; su sütununun oluşturduğu basınç
farkı bu değere yansır.

`CMAltimeterDepthSource`:
1. Yüzeyde referans basıncı kalibre eder (`autoCalibrate()`),
2. `relativeAltitude` farkını derinliğe çevirir,
3. Gürültüyü yumuşatır (EMA),
4. İvmeölçerden hareket yoğunluğunu paralel toplar (nemeşik tespiti için).

> Sığ sularda (0-3 m) basınç farkı dalış filigranıyla karışabilir; üretim sürümünde
> zaman-filtreli hibrit çözüm önerilir. ADIM 3'te kalibrasyon ekranı planlanmıştır.

### 3.2 Dalış simülatörü (`DiveSimulator`)
- Senaryo tabanlı: `descent / hover / ascent / safetyStop / decoStop`
- Hız sınırları **aşılmaz** (9 m/dk çıkışta tepe 9.4 m/dk)
- Yumuşak başlangıç/bitiş eğrileri; telafi ile segment hedefe ulaşır
- Nefes salınımı + ölçüm gürültüsü (**tohumlanabilir**, deterministik)
- Termoklin profili ile sıcaklık
- `segmentRanges`: hangi ölçüm aralığının hangi aşamaya ait olduğu

Hazır senaryolar: `beginner`, `recreational30m`, `nitrox30m`, `deep45m`,
`fastAscentViolation` (18 m/dk), `safetyStopSkipped`, `decompressionDive`.

### 3.3 Çıkış hızı takibi ve alarm
```
ham hız (1 Hz) ──► EMA yumuşatma ──► 10 m/dk sınırı ──► 4 sn süreklilik ──► ALARM
```
- Tek ölçüm sıçraması alarm üretmez
- Aynı alarm için cooldown (varsayılan 10 sn; kritik 6 sn)
- Yüzeyde (<0.3 m) hız alarmı üretilmez
- İşaret kuralı: **pozitif = yukarı** (dalış bilgisayarı geleneği)
- 7-10 m/dk bandı yalnızca **görsel** (sarı) uyarıdır, titreşim üretmez

### 3.4 Alarm politikası
| Seviye | Dokunsal | Görsel | Tekrar |
|---|---|---|---|
| Bilgi | `.notification` | — | — |
| Dikkat | `.notification` | subtle | 30 sn |
| Uyarı | `.notification` | prominent | 20 sn |
| Kritik | `.failure` + `.retry` | **tam ekran** | 6 sn |

Uyarı türleri: `fastAscent`, `ceilingViolation`, `noDecoLimitReached`,
`oxygenWarning`, `cnsLimit`, `otuLimit`, `gasSwitch`, `safetyStopSkipped`,
`depthExceeded`.

### 3.5 Emniyet durağı sayacı
- Bölge: 5 m altı (±0.5 m tolerans bandı — salınım sayacı atlatmasın)
- Yalnızca önce bölgenin altına inmişse ve iniş yapmıyorsa sayar
- Histerezis ile tekrar tetiklenmez
- Süre dolmadan yüzeye çıkılırsa **terk edilmiş** işaretlenir

### 3.6 Senaryo bazlı doğrulama (`swift run DiveCheck`, bölüm 6)
```
senaryo                       max hız  tavan   GF99   alarmlar
30 m / 20 dk (güvenli)          9.4    0.74    89     ceilingViolation, ndlReached
Hızlı çıkış 18 m/dk             18.5    0.27    83     fastAscent, ndlReached, safetyStopSkipped
Emniyet durağı atlandı          12.4    0.00    58     fastAscent, safetyStopSkipped
Deko dalışı 30 m / 45 dk         9.4    4.82   148     ceilingViolation, ndlReached, otuLimit
```

---

## 4. ADIM 3 — Dalış Ekranı, AOD, Action Button, Pusola

### 4.1 Neden "sunum katmanı" ayrı?
SwiftUI görünümü içinde karar vermek test edilemez. Bu yüzden ekranda
görünecek **her metin, renk rolü ve gösterge değeri** `DiveCore.Presentation`
içinde saf fonksiyonlarla hesaplanır; `DiveWatchUI` yalnızca bunu çizer.

```
DiveState ──► DiveDisplayBuilder.build(state, isAlwaysOn:) ──► DiveDisplayState
```

`DiveDisplayState` şunları taşır:
- `depthText` / `maxDepthText` / `diveTimeText` / `temperatureText` / `gasLabel`
- `ndlText` (veya `—`), `deco` (tavan, sonraki dura, TTS, GF99)
- `safetyStop` (geri sayım, ilerleme, alt bilgi)
- `ascentRate` (seviye + dolgu + metin + AOD sembolü)
- `compass` (Türkçe 16 yön, normalize açı, şerit kaydırması)
- `banner` (en kritik uyarı) + `isAlarmActive`
- Renk rolleri: `depthColorRole`, `ndlColorRole`, `backgroundColorRole`
- Yazı rolleri: `depthTextRole`, `timeTextRole`

### 4.2 Always-On Display
AOD'da Apple satır sayısını ve kontrastı sınırlar. Bu yüzden:
- Yazı tipi `hero` (52 pt) yerine `alwaysOn` (26 pt bold) kullanılır,
- Pusola, gaz/PO₂ satırları ve hız çubuğu **gizlenir**,
- Yalnızca derinlik + süre + NDL/TTS kalır,
- **Bilgi** seviyesindeki banner gizlenir (gürültü), kritik banner kalır.

AOD'ya geçiş `onChange(of: \\.isAlwaysOn)` ile izlenir; veriler aynı kalır,
yalnızca sunum sadeleşir.

### 4.3 Action Button (Ultra)
`DiveActionButtonResolver` niyeti platformdan bağımsız belirler:

| Durum | Niyet | Etki |
|---|---|---|
| Kritik alarm var | `acknowledgeAlarm` | Alarımı sustur (güvenlik önce) |
| Dalış sürüyor | `placeMarker` | Yer imi ekle |
| Yüzeyde | `startDive` | Dalışı başlat |
| Bitti | `none` | — |

İkincil eylem (uzun basış / dijital taç): `endDive`.
Action Button, `LiveActivityIntent` (`DiveActionIntentHandler`) üzerinden bağlanır;
uygulama ön planda değilken de tetiklenebilir.

### 4.4 Saat yüzü komplikasyonları
`DiveComplicationBuilder` dört stil için veri üretir:

| Stil | İçerik |
|---|---|
| `accessoryInline` | `24.6m · 12:40` |
| `accessoryCircular` | Derinlik ortada, hız çubuğu çemberde |
| `accessoryRectangular` | Derinlik + azami, gaz, süre + NDL/TTS |
| `accessoryCorner` | Derinlik + yön oku |

Alarm aktifken vurgu rengi hız durumundan bağımsız olarak **kırmızıya** geçer.

### 4.5 NDL rengi kademesi
| Durum | Renk |
|---|---|
| NDL > 5 dk | yeşil |
| NDL ≤ 5 dk | sarı |
| NDL ≤ 2 dk | kırmızı |
| Tavan oluştu | mor (deko) |
| Tavan ihlali | kırmızı (her koşulda geçersiz kılar) |

### 4.6 Doğrulama (`swift run DiveCheck`, bölüm 7)
```
faz          derinlik  sure    NDL/tavan  hiz   banner        AOD
diving       29.9 m   02:20   NDL 07:30  -1.4  -             sade
decoObligation 29.8 m 22:37   T 3.6 m     1.8  DEKO ZORUNLU  uyari
safetyStop   5.0 m    26:23   T 2.2 m     0.2  DEKO ZORUNLU  uyari

HIZLI CIKIS: role=criticalBackground banner=HIZLI ÇIKIŞ hiz=14.1 (danger)
komplikasyon: circular vurgu=danger
action button: Aları Sustur
```

---

## 5. ADIM 4 — Deko Alarmları, Çıkış Rehberi, Dalış Sonu Özeti

### 5.1 Deko durağı planı (`DecoStopPlan`)
Mevcut doku durumundan **planlanan** durakları üretir: varış, kalış, kalkış
saatleri ve kullanılacak gaz. Hesaplama motorun TTS algoritmasıyla **birebir
aynı** yöntemi kullanır; bu yüzden plan süresi `timeToSurface` ile örtüşür
(`DecoStopPlanTests` bunu doğrular).

| Derinlik / süre | Tavan | Duraklar | Toplam |
|---|---|---|---|
| 30 m / 45 dk | 7.1 m | 6 m (2 dk) → 3 m (3:30) | 09:50 |
| 40 m / 60 dk | 14.4 m | 12 → 9 → 6 → 3 m | 29:27 |
| 45 m / 90 dk | 19.3 m | 18 → 15 → 12 → 9 → 6 → 3 m | 55:30 |

6 m'den sığ duraklarda **saf O₂** önerilir (ve TTS ile uyum için simülasyon da
O₂ ile yapılır).

### 5.2 Çıkış rehberi (`AscentAdvisor`)
Anlık yönlendirme metni ve renk:
- Tavan üstü tampon: **"6.3 m'nin üstüne çıkma"** (tavan + 1.5 m)
- Tavan ihlali → kritik: *"Tavanın ÜSTÜNDESİN — 5 m düş!"*
- Durağa yerleşince → bekleme süresi: *"6 m'de 02:00 bekle"*
- Hız ihlali (10 m/dk üstü) ve **aşırı hızlı iniş** (23 m/dk üstü) uyarıları

### 5.3 Oksijen değerlendirmesi (`OxygenStatus`)
PO₂, CNS ve OTU tek bir yapıda seviyelenir (`ok / caution / warning / critical`).
PO₂ > 1.4 bar ve CNS ≥ %80 **alarm** üretir.

### 5.4 Dalış sonu raporu (`DiveReport` / `DiveReportDisplay`)
Profil örneklerinden hesaplanan zengin özet: azami/ortalama derinlik, dipte
geçen süre, azami çıkış/iniş hızları, sıcaklık aralığı, gazlar, PO₂/GF99/CNS/OTU,
emniyet durağı, **zorunlu deko durakları** (varış/kalış/gaz) ve **kalite notu**.

Kalite notu 5 puandan başlar; kesintiler puan düşürür ve **nedeni açıkça yazılır**:
hızlı çıkış (−2), tavan ihlali (−2), hızlı iniş (−1), eksik emniyet durağı (−1),
MOD aşımı (−2), yüksek CNS (−1), derin (−1) ve uzun (−1) dalış.

> OTU **günlük** biriktirmedir; tek bir 18 m/30 dk hava dalışı zaten günlük
> limitin ~%175'ini harcar. Bu yüzden dalış notuna kesinti olarak yansıtılmaz,
> yalnızca bilgi olarak raporlanır (günlük toplam ADIM 5'te).

### 5.5 Zorunlu deko duraklarının kaydı
Dalgıç **gerçekten duraktan ayrılmadığı** anda kayıt açılır (tavan oluştu diye
dibine oturan dalgıç için "3 m'de 16 dk bekledi" gibi anlamsız kayıt oluşmasın).
20 saniyeden kısa dokunuşlar gürültü sayılıp atlanır.

### 5.6 Yüzey aralığı (`SurfaceIntervalManager`)
Dalış sonu doku yükünü devralır, yüzeyde (1 bar) ilerleterek GF99 düşüşünü,
desatürasyonu ve uçuş yasağını geri sayar. Kaba çözünürlük (60 sn) yalnızca
hedef ana kadar olan **farkı** işler, bu yüzden sık çağrılabilir.

### 5.7 Doğrulama (`swift run DiveCheck`, bölüm 8)
```
== Deko planı (30 m / 45 dk) ==
 2 durağ · toplam 9dk
   6 m  varış 02:40 → kalış 02:00 → 04:40  O₂
   3 m  varış 05:00 → kalış 03:30 → 08:30  O₂

== Dalış raporu ==
 30.0 m · 54dk · otta | not ★★★☆☆ (puan 2)
 hızlar ↑9.4 / ↓15 m/dk · gaz Air · PO₂ 0.83 · GF99 %165 · CNS 13%
 emniyet durağı: Tamamlandı (03:00) · deko: 03:17
 kesinti: Tavanın üstüne çıkıldı · Uzun dalış (54dk)

== Yüzey aralığı ==
 + 1 sa: GF99 %40 · desat 29:00 · uçuş 1:30:00 · Uçuş yasağı
 + 4 sa: GF99 %0  · desat 00:00 · uçuş 00:00 · Serbest
```

---

## 6. ADIM 5 — Kalıcılık, WatchConnectivity Senkronizasyonu, Grafikler

### 6.1 Katmanlar
| Modül | Platform | İçerik | Yerelde derleniyor |
|---|---|---|---|
| `DiveCore` | hepsi | `LoggedDive`, depo protokolü, senkronizasyon mantığı, grafik verisi | ✅ |
| `DiveStore` | iOS/watchOS | SwiftData `@Model` + `SwiftDataDiveLogStore` | ❌ (SwiftData makrosu yok) |
| `DiveCharts` | watchOS/iOS | Swift Charts görünümleri | ✅ |
| `DiveWatch`/`DiveWatchUI` | watchOS | donanım + SwiftUI | ❌ (watchOS SDK yok) |

**Neden bu ayrım?** SwiftData'nın `@Model` makrosu Xcode araç zincirinin parçasıdır;
yalnızca Command Line Tools bulunan bir makinede derlenemez. Bu yüzden kalıcılık
**veri modeli** ve **tüm iş mantığı** saf Swift olan `DiveCore`'da test edilir,
SwiftData yalnızca bir eşleme katmanıdır.

### 6.2 Kararlı kimlik (kopya önleme)
`LoggedDive.stableID(for:device:)` dalış başlangıç zamanından ve cihaz adından
türetilen **kararlı** bir UUID üretir. Böylece aynı dalış iki cihazda da aynı
kimliğe sahip olur ve senkronizasyonda kopya oluşmaz.

### 6.3 Senkronizasyon (Watch ⇄ iPhone)
```
Dalış biter ──► DiveLogbook.add() ──► depo + outbound kuyruğu
                                        │
                            DiveSyncEngine.flush(transport)
                                        │
              WCSession taşıması (asenkron teslim/onay)
                                        │
                   acknowledge(ids) ──► kuyruk temizlenir
Gelen kayıt ──► mergePlan(against:) ──► yeni / güncellenen / yerelde daha yeni / aynı
                                        │
                             applyMerge(to: store)
```
- **Çakışma kuralı:** aynı `id` için daha yeni `updatedAt` kazanır; eşitlikte yerel
  kayıt korunur. Yerelde daha yeni olan kayıt **karşı tarafa yeniden gönderilir**.
- **Dayanıklılık:** ulaşılamıyorsa kuyruk korunur, yeniden deneme sayacı artar
  (üst sınır 5); başarılı gönderimde sıfırlanır.
- **Tel biçimi:** JSON (`DiveSyncRecord`, şema sürümlü) → `WatchConnectivity`
  `userInfo`/`transferUserInfo` ile taşınır.

### 6.4 Günlük CNS/OTU toplamları
CNS ve OTU **günlük** kümülatif değerlerdir (NOAA: OTU limiti 80, CNS %100).
`DailyTotalsBuilder` kayıtları güne göre gruplar ve:
- OTU %100 (2 saat yarı ömür), CNS %100 (4 saat yarı ömür) eşikleriyle
  **önerilen bekleme süresini** hesaplar (15 dk'ya yuvarlanır),
- ekranda "Bugün: OTU %150 — 2s ara ver" gibi öneri metni üretir.

### 6.5 Grafikler ve indirgeme
watchOS'ta 30 m/45 dk bir dalış ~3300 örnek üretir; bu doğrudan çizilemez.
`ChartDownsampler.minMax` **zaman kovalarına** bölüp her kovada en derin ve en sığ
noktayı korur — basit "her N. nokta" yönteminin aksine **tepe noktalar ve
plato görünür kalır**. Bütçe 40'a indirgenen profilde en derin nokta (30.0 m)
kaybolmaz.

Görünümler (Swift Charts): profil grafiği (derinlik alanı + sıcaklık/GF99/tavan
serileri), günlük OTU/CNS barları, aylık dalış sütunları.

### 6.6 Doğrulama (`swift run DiveCheck`, bölüm 9)
```
== İstatistik ==
 3 dalış · toplam 2s 6dk · azami 30.0 m · deko: 2 · emniyet durağı: 2
== Günlük toplamlar ==
 2023-11-14: OTU %47 (%38) · CNS %6 → Günlük OTU/CNS sınırları içinde
== Senkronizasyon ==
 bekleyen: 3 → gönderim sonrası 0 (uploaded: 3)
 eski sürüm gönderilince: yerel korundu, bekleyen 1
== Grafik ==
 profil grafiği: 4 seri · indirgeme 40 nokta (bütçe 40)
 Derinlik aralık 0.0...30.0 · GF99 0.0...164.7
```

> **Xcode'da yapılacaklar:** `DiveStore` hedefini watchOS/iOS için eklemek,
> `WCSession` sarmalayıcısını (`WatchConnectivityTransport`) yazmak ve
> `ModelContainer`ı uygulama başlangıcında oluşturmak.

---

## 7. ADIM 6 — GF Ayarları, Çoklu Gaz, Derin Duraklar

### 7.1 Gradient Factors
`GradientFactorCatalog` kullanıcıya altı ön ayar sunar ve derinlik/süre +
deneyim düzeyine göre **öneri** üretir:

| Ön ayar | GF | Kimler için |
|---|---|---|
| Konservatif | 80/85 | Yeni başlayanlar, ≤ 24 m |
| **Dengeli** | **75/85** | 30–40 m rekreasyonel (en yaygın seçim) |
| **Gevşek** | **90/90** | Deneyimli, daha uzun dalış |
| Derin | 50/80 | 40–60 m |
| Teknik | 30/70 | Trimix / derin deko |
| Referans | 100/100 | Yalnızca doğrulama |

Öneri mantığı: ≤ 18 m veya yeni başlayan → Konservatif; 30 m'de ≤ 25 dk → Gevşek,
daha uzun → Dengeli; > 30 m → Derin; > 60 m veya teknik deneyim → Teknik.
Ayrıca "özel" GF girişi (Low/High kaydırıcıları) ve **çok geniş aralık uyarısı**
(> 70 puan) bulunur.

### 7.2 Çoklu gaz ve MOD
`GasPlan` silindir listesi tutar; her silindirin kendi PO₂ limiti olabilir:

- Dip gazı: **1.4 bar** → EAN32 MOD ≈ 34.4 m, EAN36 ≈ 29.5 m, hava ≈ 57.3 m
- Deko O₂: **1.6 bar** → MOD ≈ 6.6 m (sektör standardı)

Bu ayrım önemli: "O₂'nin MOD'u 6 m" değeri 1.6 bar içindir; 1.4 bar'da 4.6 m'dir.
`NitroxPicker.recommendedPercent(targetDepth:)` hedef derinliğe **güvenli en
zengin** karışımı seçer (EAN22–40 aralığında, geriye doğru arayarak).

`GasPlan` ayrıca şunları yapar:
- `requiresSwitch(at:currentIndex:)` — MOD geçildiğinde gaz değişimi uyarısı,
- `bestIndex(at:)` / `suggestion(at:)` — o derinlikte kullanılabilecek en iyi gaz
  (**MOD'u geçen gaz asla önerilmez**),
- `canReach(depth:)` — hiçbir gaz uygun değilse dalış sınırı aşılmıştır,
- `switchTable()` — ekranda gösterilecek "3 m'de EAN35 → O₂" tablosu,
- `validate()` — deko gazı 6 m kuralı, silindir sırası, başlangıç gazı kullanımı.

### 7.3 Derin duraklar (deep stops)
`DeepStopCalculator` GUE/Subsurface tarzı **yuvarlamalı (rounded-off)** yöntemi
uygular:

1. Dokular dalış sonundan ilk deko durağına (tavan) çıkarılır,
2. Her 3 m kademede dokuların N₂ basıncı **yukarı yuvarlanır**
   (`TissueModel.roundedOff(incrementPressure:)`),
3. Tavan yeniden hesaplanır; tavan bu kademeye ulaşıyorsa durak **canlıdır** ve
   tavan derinliğin altına inene kadar burada beklenir,
4. Durak yapıldığı kabul edilir ve bir sonraki kademe o durumdan hesaplanır.

Ölçülen sonuç (GF 80/85, 3 m aralık):

| Dalış | Tavan | Canlı derin durak |
|---|---|---|
| 30 m / 50 dk | 7.7 m | 9 m'de 06:20 |
| 40 m / 60 dk | 14.4 m | 15 m'de 08:30 |
| 45 m / 70 dk | 18.2 m | 21 m'de 02:50 |

Deko yükümlülüğü olmayan dalışlarda derin durak **hesaplanmaz** (tavan yüzeydedir,
yuvarlama hiçbir şeyi değiştirmez). Derin duraklar 3 m'lik zorunlu durakların
sürelerini **değiştirmez**; ek bilgi olarak plana eklenir.

> **Sadeleştirme notu:** Bu, GUE'nin tam Pyle dalgalanması benzetiminin
> sadeleştirilmiş hâlidir — doğrudan Bühlmann doku simülasyonu kullanılır.
> Üretim öncesi Shearwater/Subsurface ile çapraz doğrulama gerekir.

---

## 8. ADIM 7 — Su Kilidi ve Action Button

### 8.1 Donanım gerçekliği (önemli)
Apple Watch'ın **Water Lock'u bir uygulama API'siyle açılamaz**; sistem seviyesinde
bir güvenlik mekanizmasıdır ve kullanıcı Control Center'dan açar. Bu yüzden iki ayrı
mekanizma uygulanır:

| İstenen | Durum | Nasıl |
|---|---|---|
| Su altında yanlış dokunma | ✅ | `DiveLockController` + `.disabled()` / hit testing kapalı |
| Su atma (audio ejection) | ✅ | Hoparlörden ses + titreşim (`WatchWaterLockAdapter`) |
| Ekranın dalış boyunca açık kalması | ✅ | `WKExtendedRuntimeSession` |
| Sistem Water Lock'unu açmak | ❌ | Kullanıcıya yönlendirme metni gösterilir |

### 8.2 Kilit yaşam döngüsü
```
idle ──dalış başladı──► diving (dokunma kilitli)
                            │ dalış bitti
                            ▼
                        ejecting (kilit AÇIK — kullanıcı kolunu çevirmeli)
                            │ döngü tamam
                            ▼
                        unlocked
```
Kilit, su atma döngüsü boyunca **bilerek açık tutulur**: dalgıç kolunu çevirip
cihazı sallayabilmelidir. Acil durum menüsü hiçbir zaman kilitlenmez.

### 8.3 Action Button
| Basış | Durum | Eylem |
|---|---|---|
| Tek | Yüzeyde | Dalışı Başlat |
| Tek | Dalışta | **İşaret Koy** (bookmark) |
| Tek | Kritik alarm | Aları Sustur |
| **Basılı tut** | Dalışta | **Acil Durum** menüsü |
| Basılı tut | Yüzeyde | Dalışı Başlat |

Acil durum menüsü: Emniyet Durağı (5 m / 3 dk), Çıkış Yardımı (deko planı + tavan),
Dalışı Bitir; tavan ihlali varsa uyarı en üstte gösterilir.

### 8.4 Su atma döngüsü
`Titreşim → Ses → Titreşim → Ses` (toplam ≈ 4.4 sn), ardından kullanıcıya
*"Kolunu çevir ve cihazı iki kez salla"* yönlendirmesi gösterilir.

---

---

## 9. ADIM 8 — Arka Plan Modu, Uçuş Yasağı, Tekrar Dalış Hesaplayıcısı

### 9.1 Neden kabin basıncı?

Uçuş yasağı (GF99 ≤ %20 + 60 dk, 15 dk'ya yuvarlanır) **deniz seviyesinde**
tanımlıdır. Oysa uçak kabini 8000 ft'e (≈2440 m) ayarlıdır ve basıncı
deniz seviyesinin altındadır. Aynı doku yükü orada daha yavaş çözülür, yani
gerekli bekleme **daha uzundur**.

`FlightAltitudeCalculator` kabin profilini basınç çarpanı olarak alır:

| Profil | `cabinFactor` | Kabin basıncı | 30 m/45 dk deko dalışı sonrası |
|---|---|---|---|
| `seaLevel` | 1.00 | 1.00 bar | 6s 30dk |
| `standardFlight` (8000 ft) | 0.75 | 0.75 bar | 20s 0dk |
| `highAltitudeFlight` (9000 ft) | 0.70 | 0.70 bar | 22s 0dk |

> ⚠️ Teknik not: 0.75 bar deniz seviyesinin *altında* olduğu için derinlikle
> ifade edilemez (`depth ≤ 0` → yüzey basıncına döner). Bu nedenle
> `TissueModel.step(atAmbientPressure:duration:gas:)` ve
> `TissueModel.gf99(atAmbientPressure:)` yetenekleri eklendi. GF99 daima
> bir **referans basınca** göre tanımlıdır; `gf99(atDepth:)` referansı
> 1.0 bar'a sabitler (dalış bilgisayarlarındaki "yüzey GF99" gösterimi).

### 9.2 Arka plan izleme politikası

watchOS'ta uygulama arka planda sürekli çalışamaz. `BackgroundMonitoringPolicy`
bir sonraki kontrolün **ne zaman** yapılacağını önceden hesaplar:

1. **Faz kuralı** — >1 saat kaldıysa 15 dk, 15–60 dk arası 5 dk, son
   15 dakikada 1 dk aralıkla kontrol,
2. **Bütçe kuralı** — kalan süre, kalan kontrol sayısına eşit dağıtılacak
   şekilde aralık uzatılır (varsayılan: en fazla **60** kontrol).

6.5 saatlik bir uçuş yasağı 46 kontrol planına denk gelir; bütçe tükenirse
tek bir kapanış kontrolü yapılır. Durum her zaman `SurfaceIntervalManager`
ile anlık hesaplandığı için geç uyanma yalnızca gecikme yaratır, veri
kaybına yol açmaz.

`SurfaceIntervalBackgroundAdapter` (DiveWatch) bu politikayı
`WKExtendedRuntimeSession` + `WKApplicationRefreshBackgroundTask` ile
yürütür; **derlenmedi** (bkz. bölüm 11 notu).

### 9.3 Tekrar Dalış Hesaplayıcısı

`RepetitiveDiveCalculator` artık gaz yükünü devralarak sonraki dalışın
tamamını önceden simüle eder:

- **Gerçekçi NDL** (mevcut doku durumuyla) ve **taze NDL** karşılaştırması,
  yüzde kaybı gösterimi,
- Zorunlu deko planı ve toplam durak süresi,
- Dalış sonundaki uçuş yasağı **çıkış deko tamamlandıktan sonra**,
- MOD'a göre önerilen gaz (nitrox),
- Uyarı listesi (artık yük, deko zorunluluğu, kullanılamayan gaz…).

`sequence(dives:surfaceInterval:)` bir gün içindeki dalışları sırayla
planlar; her dalış kendi çıkışını tamamlar, yüzey aralığı dokuları
gevşetir.

Ölçüm (30 m/45 dk deko dalışı sonrası, 40 m/25 dk hedef):

| Yüzey aralığı | Gerçekçi NDL | Taze NDL | Uçuş yasağı |
|---|---|---|---|
| 6 dk | 00:00 (deko zorunlu) | 05:00 | 9s 30dk |
| 1 saat | 05:00 | 05:00 | 10s 0dk |
| 4 saat | 05:00 | 05:00 | 8s 45dk |

6. dakikada hızlı kompartmanlar henüz boşalmadığı için NDL sıfırlanır ve
deko zorunluluğu doğar; 1 saatten sonra yük hızla çözülmüş, NDL taze
değere dönmüştür.

---

## 10. ADIM 9 — Komplikasyon Modları

### 10.1 Modlar ve faz geçişi

Her komplikasyon tek bir veri kaynağı okur; bu nedenle dört mod tanımlandı:

| Mod | Birincil faz | İçerik |
|---|---|---|
| `liveDepth` | dalış | anlık derinlik, süre, gaz |
| `liveNDL` | dalış | anlık derinlik + kalan NDL (deko varsa tavan) |
| `surfaceInterval` | yüzey | yüzey süresi, GF99, desatürasyon |
| `noFly` | yüzey | uçuş yasağı geri sayımı + kabin profili |

`DiveComplicationModeResolver.effective(...)` kurulu modu o anki fazın
ailesine taşır: dalış sırasında yüzey modu `liveDepth`'e, yüzeyde canlı
mod uçuş yasağı varsa `noFly`'a düşer. Yasa kalktıysa `noFly` modu
`surfaceInterval`'a döner.

`isAlarmActive` yalnızca `noFly` modunda gerçek alarmdır; yüzey aralığı
modunda yüksek GF99 **bilgi** olarak sunulur.

### 10.2 Zaman çizelgesi (WidgetKit)

watchOS komplikasyonları anlık veri çekmez; sistem bir zaman çizelgesi verir.
`DiveComplicationTimeline`:

- dalış sırasında "şimdi + 3 dakika" ileri bakış üretir (4 giriş),
- yüzeyde geri sayımın sonuna doğru **seyrek** girişler üretir
  (`BackgroundMonitoringPolicy` ile aynı aralık kuralı, en fazla 24 giriş),
- `nextRefreshDate` ile sistemin bir sonraki uyanmasını belirler; yasa yoksa
  `nil` döner (gelecekte güncelleme = pil dostu).

---

## 11. ADIM 10 — iPhone Tarafı: Harita, İnteraktif Grafik, UDDF/FIT

### 11.1 GPS rota

Apple Watch'ta su altında GPS çözünürlüğü 5–10 m'dir ve hızla pil tüketir;
bu yüzden konum **yüzeyde** kaydedilir ve rota bu noktaları çizgi olarak
gösterir. `DiveRoute`:

- Haversine mesafe (toplam, segment, düz çizgi),
- **sürüklenme oranı** = ölçülen mesafe / düz mesafe (GPS kalitesi göstergesi),
- ortalama yüzey hızı,
- `mapRegion()` → merkez + delta (harita kamerası için; 180° ile sınırlı),
- `coordinate(atElapsed:)` → grafikle senkron işaretçi,
- 5 m minimum nokta aralığı ile GPS gürültüsü (1–3 m dalgalanma) ayıklanır.

### 11.2 İnteraktif grafik

`DiveChartModel` tüm etkileşim kararlarını verir (test edilebilir):

- metrik: derinlik, sıcaklık, gaz yükü, çıkış hızı, GF99,
- **yakınlaştırma** (en az 60 sn pencere), **sürükleme** (dalış sınırlarına
  kenetlenir), **sıfırlama**,
- **imleç/seçim** — en yakın örneğe oturur, araç ipucu üretir,
- görünür pencereye göre Y ekseni aralığı.

`DiveChartView` (iOS) bunları Swift Charts'a bağlar: `chartXScale(domain:)`,
`chartOverlay` + `DragGesture` + `MagnificationGesture` + `TapGesture`, deko
tavanı referans eğrisi ve seçim çizgisi.

### 11.3 Dışa aktarma

| Biçim | Boyut (30 m/25 dk) | Uyumluluk |
|---|---|---|
| UDDF 3.3.0 | 35 KB | Subsurface, Divelog, eğitim yazılımları |
| FIT | 2.4 KB | Garmin Connect, Strava, Suunto (14× küçük) |
| JSON | 64 KB | Kendi arşivimiz, yeniden içe aktarma |

**UDDF** XML'dir: `generator`, `profiledata/gasp` (gaz tanımları),
`samples/waypoint` (her örnek, `gps`, `gasiset`), `waypoints` (GPS ara
noktaları) ve `applicationdata` (özet + GF + CNS/OTU) üretilir. Tüm metin
alanları `escape(_:)` ile kaçırılır (`&`, `<`, `>`, `"`, `'`).

**FIT** ikilidir: 14 bayt başlık (`.FIT` imzası + veri boyutu + başlık CRC)
+ mesaj kayıtları + dosya CRC'si. Yazılan mesajlar `file_id` (well-known,
tanımsız), `event` (timer start/stop), `record` (derinlik, sıcaklık, GF99,
tavan), `lap` ve `session`. CRC-16 (0xA001) hem başlıkta hem dosya
gövdesinde hesaplanır ve doğrulanır.

`DiveExportService` üç biçimi tek yerden üretir, veri denetimi yapar
(örnek yok / süre sıfır / gaz yok → hata; çok örnek / yüksek CNS → uyarı;
GPS veya not yok → bilgi) ve `peekUDDF` ile dosyanın okunabilirliğini kontrol
eder.

> Not: `sources/DiveSample`'a isteğe bağlı `latitude`/`longitude` eklendi
> (ADIM 10). Alan `Optional` olduğu için `Codable` geriye uyumludur; eski
> kayıtlar sorunsuz okunur.

---

## 12. ADIM 11 — Pil Optimizasyonu, Kırmızı Gece Modu, Dinamik Örnekleme

### 12.1 Neden ekran rengi pil tüketir?

OLED'de her piksel kendi ışığını üretir: **siyah = 0 mA**, beyaz tam güç.
Ayrıca mavi alt piksel, yeşilden ve kırmızıdan daha pahalıdır. `DiveRGB`
kanal maliyetlerini modeller (`oledCost`, 1.0 = kırmızı):

| Renk | Algılanan parlaklık | Göreli OLED maliyeti |
|---|---|---|
| Siyah | 0.00 | **0.00** |
| Kırmızı | 0.30 | 1.00 |
| Yeşil | 0.59 | 1.35 |
| Mavi | 0.11 | **2.60** |
| Beyaz | 1.00 | 4.95 |

### 12.2 Kırmızı Gece Modu

`DiveDisplayTheme` üç tema tanımlar; **paletler tamamen kırmızı tondadır**
(`isRedDominant` testleriyle doğrulanır), arka plan tamamen siyahtır:

| Tema | Göreli güç | Ekran (AOD) | Saniye | Maks derinlik/gaz |
|---|---|---|---|---|
| `standard` | 2.11 | 244.6 mW | var | var |
| `nightShift` | 0.46 | 96.2 mW | var | var |
| `alwaysOnRed` | 0.38 | 89.1 mW | yok | gizli |

Kırmızı mod ekran gücünü **%61** düşürür. Kırmızı ışıkta görme eşiği de en
yüksek olduğu için gece dalışında hem görme hem pil kazanımı sağlar.

**Tema çözümlemesi** (`EnergyManager.resolveTheme`):

1. AOD açıkken → **her zaman** `alwaysOnRed` (Apple'ın AOD kısıtları da
   yalnızca kırmızı tonlarına izin verir),
2. `forced` tercihi → `nightShift`,
3. `auto` → pil < %30, düşük pil modu veya gece (21:00–06:00) ise
   `nightShift`,
4. aksi halde `standard`.

Ayrıntı sadeleştirmesi (`DiveDisplayBuilder.build(from:isAlwaysOn:theme:)`):
AOD kırmızı modda maksimum derinlik `—` olur, süre `15dk` biçimine düşer,
gaz etiketi ve sıcaklık gizlenir. **Kritik banner asla gizlenmez** — testle
doğrulanır.

### 12.3 Enerji bütçesi ve profiller

Tüketim dört kaleme ayrılır: deko motoru (18 mW), sensör (45 mW @1 Hz),
ekran (55 mW taban + piksel oranı), arka plan (25 mW). AOD kapalıyken
ekran yalnızca kol kaldırıldığında yanar; bu yüzden tema etkisi
`activeScreenFraction` (≈%25) ile ölçeklenir.

| Profil | Aralık | AOD kırmızı tüketim | Öngörü (pil %100) |
|---|---|---|---|
| Performans | 0.5 sn | 210.1 mW | 357 dk |
| Dengeli | 1.0 sn | 177.1 mW | 423 dk |
| Pil tasarrufu | 5.0 sn | 150.7 mW | **497 dk** |

Sistem kısıtlamaları profili **otomatik düşürür**: termal `serious`+ veya
pil < %10'da performans → dengeli; sistem düşük pil modunda da performans
kabul edilmez.

### 12.4 Dinamik örnekleme

`AdaptiveSampler` sensör okumalarını motora aktarmadan önce bir kapıdan
geçirir. Aralık şu kurallarla seçilir (öncelik sırasıyla):

| Durum | Aralık | Gerekçe |
|---|---|---|
| Kritik/durum uyarısı | 0.5 sn | güvenlik |
| Hızlı çıkış (> 9 m/dk) | 0.5 sn | ihlal yakalama |
| Tavana < 1.5 m | 0.5 sn | ihlal riski |
| Deko yükümlülüğü + yükseliş | 0.5 sn | hız doğruluğu |
| Deko durağında (durağan) | profil aralığı | gaz yükü yavaş değişiyor |
| Aktif hareket (\|hız\| > 2) | profil aralığı | — |
| Dipte sabit | 2 sn | enerji tasarrufu |
| Yüzey beklemesi | 5 sn | güvenlik yok |
| Dalış dışı | 10 sn | yalnızca geri sayım |

#### Güvenlik sınırı (kod düzeyinde)

1. **Asla 5 saniyeyi geçmez** ve güvenlik durumlarında **daima ≤ 1 sn** —
   `maximumInterval` / `safetyInterval` ile garanti, tüm profiller için test edilir.
2. **Ani derinlik değişimi** (> 0.5 m) her zaman işlenir.
3. **Güvenlik durumuna geçiş beklemez** — mevcut aralık 2 sn olsa bile
   anında 0.5 sn'ye düşer.
4. **Geçici uyarılar zaman aşımına uğrar** (120 sn). `DiveState.warnings`
   biriktiği için, dalış başındaki tek bir hızlı çıkış kalan 45 dakikayı
   yüksek örneklemede tutmasın diye *durum* uyarıları (tavan, oksijen, CNS,
   OTU, derinlik aşımı) kalıcı, *geçici* uyarılar (hızlı çıkış, gaz değişimi)
   ise yalnızca 120 saniye sayılır.
5. **Entegrasyon testi**: seyrekleştirilmiş dalışta dalış süresi ve maksimum
   derinlik değişmez, GF99 farkı < %12; deko yükümlülüğünde **yükseliş
   sırasında hiçbir okuma atlanmaz**; 15 m/dk çıkışta tüm okumalar işlenir.

#### Bulunan ve düzeltilen hata

Örnekleme politikası ilk yazıldığında `ascentRate` işareti **ters** yorumlanıyordu
(`-ascentRate > 9`). Dalış bilgisayarı geleneğinde `ascentRate` **pozitif =
yukarı** olduğu için, hızlı **iniş** "hızlı çıkış" sanılıyor ve asıl tehlikeli
olan **yükseliş** seyrekleştiriliyordu. entegrasyon testi (`testFastAscentIsAlwaysSampled`)
bunu ortaya çıkardı; `testAscentRateSignConventionIsUpward` kalıcı bir
güvence olarak eklendi.

### 12.5 Extended runtime optimizasyonu

`DiveRuntimeSessionAdapter` (DiveWatch, derlenmedi):

- ADIM 7'deki su kilidi oturumuyla **çakışmaz** (`isSurfaceSessionActive`),
- `.selfCare` kategorisini kullanır (`.mindfulness`'e göre daha uzun süre),
- AOD açıkken oturumu **kapatmaz** (ekran zaten yanık, oturum gerekiyor),
- pil < %20'de oturumu bilinçli olarak uzatmaz ve kullanıcıyı bilgilendirir,
- 2 saatten az kaldığında uyarı gösterir.

Pil/termal okuma `WatchPowerAdapter` ile yapılır: pil ölçümü 30 saniyede bir
yoklanır (dalışta saniyelik yoklama gereksiz pil tüketir).

---

## 13. ADIM 12 — Sınır Durum ve Stres Testleri

Toplam 134 yeni test (`AscentStressTests`, `ShallowWaterStressTests`,
`SyncStressTests`) kötü yolları kapsar: kullanıcı hatası, sensör arızası,
bağlantı kopması.

### 13.1 Aşırı hızlı çıkış ve alarm doğruluğu

| Test | Kanıt |
|---|---|
| `testExtremeAscentTriggersViolation` | 20 m/dk → ihlal + alarm |
| `testViolationRequiresSustainedDuration` | alarm yalnızca **4 sn sürekli** aşım sonrası |
| `testSingleSpikeDoesNotTriggerAlarm` | tek örneklik 10 m derinlik sıçraması alarm üretmez |
| `testAlarmRespectsCooldown` | alarmlar 8 sn cooldown aralığına uyar |
| `testDescentNeverTriggersAscentViolation` | 40 m/dk **iniş** çıkış ihlali üretmez |
| `testAscentRateSignIsUpward` | `ascentRate` pozitif = **yukarı** (regresyon) |
| `testTimeResetClearsMonitor` | saat sıfırlanınca hız ve ihlal sıfırlanır |
| `testAbsurdRateIsRejected` | >60 m/dk fiziksel olarak imkânsız → yok sayılır |
| `testViolationDuringDecoIsStillCaught` | deko tavanı varken hızlı çıkış yakalanır |
| `testVeryLongDiveDoesNotOverflow` | 6 saatlik dalışta NaN/sonsuz değer oluşmaz |

Uçtan uca doğrulama: 30 m'ye 12 m/dk ile inip 18 m/dk ile çıkıldığında
`[critical] ÇIKIŞ HIZI FAZLA! 18.0 m/dk (sınır 10 m/dk)` uyarısı ve 3
titreşim üretilir.

### 13.2 Sığ su ve dip zamanı sınırı

Ölçülen davranış (GF 80/85, tuzlu su) — modelin **doğru** olduğunu doğrulayan
değerler:

| Derinlik | 1 saat | 3 saat | 6 saat |
|---|---|---|---|
| 3 m | tavan yok | tavan yok | tavan yok |
| 5 m | tavan yok | tavan yok | tavan yok |
| 8 m | tavan yok | tavan yok | tavan yok (NDL 5s20dk) |
| 10 m | tavan yok (NDL 2s24dk) | tavan yok (NDL 24dk) | **tavan 0.7 m** |
| 12 m | tavan yok (NDL 46dk) | **tavan 1.1 m** | **tavan 2.1 m** |

Sığ sularda NDL çok uzundur; 5 m'de 6 saat geçse bile tavan oluşmaz — bu,
gerçek bilgisayarların davranışıyla örtüşür. Testler bu ölçülmüş
değerlere göre yazıldı. Ayrıca doğrulanır: tavan hiçbir koşulda 6 m'yi
aşmaz, deko yükümlülüğü her zaman yüzeye çıkış sağlayan bir plan üretir,
ardışık sığ dalışlarda NDL monoton azalır.

### 13.3 Senkronizasyon: kopma ve çakışma

| Senaryo | Sonuç |
|---|---|
| Ulaşılamazken gönderim | kuyruk **korunur**, hata sayacı artar |
| 3 denemeden sonra yeniden bağlanma | 5 kaydın **tamamı** taşınır |
| Yeniden deneme sınırı aşımı | veri **silinmez** |
| Kısmi onay | onaylananlar temizlenir, kalanı korunur |
| Kopma transfer ortasında | 6 kaydın tamamı yeniden gönderilir |
| Yeni uzak sürüm | uzak kazanır (güncelleme) |
| Eski uzak sürüm | yerel korunur, **geri gönderim** kuyruğa alınır |
| Eşit zaman damgaları | yerel korunur (**veri kaybı yok**) |
| Yinelenen kayıt | tekilleştirilir |
| 50 kopma/bağlanma döngüsü (soak) | **hiçbir dalış kaybolmaz** |
| 100 dalışlık tam gidiş-dönüş | 100/100 aktarılır |
| Bozuk/kesik paket | hata fırlatılır, motor durumu bozulmaz |
| Boş/yalnızca boşluk içeren paket | hata **fırlatmaz** (sessizce boş) |

### 13.4 ADIM 12'de bulunan ve düzeltilen performans kusuru

Sınır testleri ilk çalıştırıldığında takım **kilitlendi**: 10.800 sensör
okuması (3 saatlik sığ dalış) **392 saniye** sürüyordu. Nedeni: her
`ingest` çağrısında `DecoEngine.snapshot` dört **ileri simülasyon**
çalıştırıyordu — NDL için 6 saate, desatürasyon için 24 saate kadar adım
(ayrıca `noFlyTime()` aynı desatürasyonu **ikinci kez** hesaplıyordu).

Çözüm iki parçalı:

1. **Öneri değer önbelleği** (`DiveSessionController.advisoryValues`) —
   NDL/TTS/desatürasyon/uyuş yasağı **yalnızca görüntüleme** amaçlıdır ve
   10 saniyede bir tazelenir. Tavan, GF99, PO₂ ve gaz her zaman tam
   hesaplanır; deko yükümlülüğü başlayıp bittiğinde ve gaz değiştiğinde
   önbellek anında geçersiz kılınır.
2. **Bisection tabanlı süre arama** (`TissueModel.timeUntilCondition`) —
   doku basınçları zamanla monoton değiştiği için doğrusal tarama yerine
   "iki kat büyüyen adım + ikili arama" kullanılır: aynı doğruluk ~40 adımda.

Sonuç:

| | Önce | Sonra |
|---|---|---|
| 3 saat / 10.800 okuma | 392 sn | **4.1 sn** |
| Okuma başına | 36 ms | 0.38 ms |
| NDL hesabı | ~2160 adım | ~40 adım |
| GF99 sonucu (3 saat sığ) | %41 | **%41 (aynı)** |

**95 kat hızlanma**, sonuçlar birebir aynı. Bu kusur ADIM 11'in pil
hedeflerini de doğrudan etkiliyordu (her saniyede saniyelik CPU yükü).

---

## 14. ADIM 13 — TestFlight ve Dağıtım Hazırlığı

### 14.1 `Info.plist` doğrulaması — koda dönüşmüş gereksinimler

`Info.plist` hataları derlemede görünmez; uygulama yüklenir ve App Store'da
reddedilir. Bu yüzden gereksinimler `AppDistribution` (DiveCore) içinde **veri
olarak** tanımlandı ve gerçek plist dosyalarına karşı doğrulanıyor.

| Hedef | Bundle ID | Arka plan modları | İzin metni |
|---|---|---|---|
| watchOS | `com.divelog.watch.watchkitapp` | `workout-processing`, `dive-computer`, `location` | konum, hareket, HealthKit |
| iOS | `com.divelog.iphone` | `processing`, `fetch` | 6 metin (konum ×2, hareket, HealthKit ×2, Bluetooth) |
| Widget | `com.divelog.watch.complications` | — | — |

Kontroller: zorunlu anahtarlar, bundle kimliği, sürüm biçimi, build
numarası, **boş/kısa/eksik izin metni**, eksik/fazladan arka plan modu,
`MinimumOSVersion`, `UIDeviceFamily`, HealthKit yetkilendirmesi.

Doğrulayıcı Xcode olmadan çalışır ve CI'a eklenebilir:

```sh
swift run PlistCheck              # tüm plist'leri doğrula
swift run PlistCheck --checklist  # TestFlight kontrol listesi
swift run PlistCheck --usage      # izin metinlerini yazdır
```

> `dive-computer` arka plan modu, dalış dışındayken uçuş yasağı takibini
> sürdürmek için **zorunludur**; `workout-processing` ise su altı kaydını
> korur. Testler ikisinin de bulunmasını zorunlu kılar.

### 14.2 Bulunan ve düzeltilen doğrulama hatası

`MinimumOSVersion` denetimi sürümleri **sözlüksel** karşılaştırıyordu:
`"9.0" < "10.0"` ifadesi Swift'te `true` döndüğü için, watchOS 10 gerektiren
bir uygulamada `MinimumOSVersion = 9.0` sessizce geçiyordu. `AppDistribution.compare(_:_:)`
sayısal karşılaştırma ile değiştirildi ve
`testVersionComparisonIsNumericNotLexical` kalıcı güvence olarak eklendi.

### 14.3 Varlıklar (App Icon, komplikasyon önizlemeleri)

`App/Assets.xcassets/` altında Apple'ın beklediği `Contents.json`
manifestleri tanımlandı:

- `AppIcon.appiconset` — 1024×1024 tek boyut (App Store yüklemesi için zorunlu),
- `ComplicationCircularPreviews` — 44/52/40 px (Classic, Modular, Corner),
- `ComplicationRectangularPreviews` — 160×69 px.

> ⚠️ **Bu ortamda raster görsel üretilemiyor** (yalnızca Command Line Tools).
> Dosya adlarını verilen `Contents.json` ile birebir üretmek yeterlidir;
> PNG dosyaları tasarım aracından dışa aktarılmalıdır. 1024 kare App Icon
> **alfasız** ve tam opak olmalıdır.

### 14.4 Derleme ve imzalama yapılandırması

`Config/*.xcconfig` dosyaları hedef başına ayrılmıştır:

- `Base.xcconfig` — sürüm/build, uyarıları hataya çevirme,
  `SWIFT_STRICT_CONCURRENCY = complete`,
- `Release.xcconfig` — `-O` + `wholemodule` (ADIM 11 pil ölçümleri ancak
  optimize derlemede anlamlı), `dwarf-with-dsym` (çökme raporları için
  semboller yüklenmeli), `VALIDATE_PRODUCT = YES`,
- `Watch/iOS/Widget.xcconfig` — bundle kimliği, dağıtım hedefi, plist yolu,
  simge adı; widget'ta `SKIP_INSTALL = YES`.

TestFlight dağıtımı **Release + Distribution** yetkisiyle yapılır; otomatik
imzalama (`CODE_SIGN_STYLE = Automatic`) ekipte tanımlı geliştirici/distribution
profillerini kullanır. Sağlık verisi kullanıldığı için
`com.apple.developer.healthkit` yetkisi **her hedefte ayrı ayrı** eklenmelidir.

### 14.5 Kontrol listesi

`AppDistribution.releaseChecklist` 9 zorunlu + 1 önerilen madde içerir
(plist'ler, sürümleme, imzalama, yetkilendirme, simgeler, gizlilik bildirimi,
gerçek cihaz testi). `swift run PlistCheck --checklist` ile basılır.

### 14.6 Bu ortamın sınırı

Bu ortamda **Xcode kurulu değil** (`xcode-select -p` → CommandLineTools).
Dolayısıyla `.xcodeproj` üretilemez, hedefler derlenemez ve simgeler/önizleme
görselleri üretilemez. Teslim edilenler Xcode'a taşınabilir yapılandırmadır;
ilk watchOS/iOS derlemesi Xcode'da yapılmalıdır (README bölüm 15 notu).

---

## 15. Monetizasyon, Mağaza Metinleri ve Gizlilik

### 15.1 Ticaret modeli

| Kapsam | Ürün kimliği | İçerik |
|---|---|---|
| Temel | — | **Tüm güvenlik özellikleri** + son 3 dalış |
| Pro Aylık | `com.divelog.pro.monthly` | 13 Pro özelliği |
| Pro Yıllık | `com.divelog.pro.annual` | 13 Pro özelliği (önerilen) |
| Ömür Boyu | `com.divelog.pro.lifetime` | 13 Pro özelliği, yenilenmez |

**Kilitlenen (13):** sınırsız günlük, uzun dönem istatistik, profil grafikleri,
gelişmiş/özel GF, Nitrox + çoklu gaz, çoklu silindir, derin duraklar, GPS
harita, UDDF/FIT dışa aktarma, tekrarlı dalış hesaplayıcısı, uçuş planlama,
yüzey aralığı komplikasyonu.

**Kilitlenmeyen (31 kabilite):** anlık derinlik, süre, NDL, tavan, deko
durakları, TTS, GF99, gaz yükü, uçuş yasağı, emniyet durağı, hız sınırları,
hızlı çıkış/tavan/oksijen/MOD alarmları, acil durum menüsü, çıkış rehberi,
su kilidi, Action Button, dalış kaydı, aktif dalış görünümü.

### 15.2 Güvenlik garantisi (kod düzeyinde)

Bu, ADIM 1'in en önemli kabul kriteridir ve üç ayrı mekanizmayla
korunur:

1. **Ayrı tip** — `SafetyCapability` enum'u `FeatureKey` listesinde
   **bulunmaz**; yani güvenlik özellikleri katalogda yer almaz.
2. **Politika** — `SafetyPolicy.isAvailable(_:)` her zaman `true` döner;
   bir kabiliyeti kilitlemek için kodu değiştirmek gerekir.
3. **Kaynak taraması** — `CommerceSafetyTests`,
   `DecoEngine`/`AlarmCoordinator`/`TissueModel`/`DiveSessionController`
   gibi 10 güvenlik dosyasının `EntitlementSet`/`FeatureGate`/`DiveTier`
   **kullanmadığını** satır satır doğrular. Güvenlik motoru ticaret
   katmanını tanımaz.

> **Ekran davranışı:** Dalış sırasında paywall **hiç açılmaz**
> (`WatchPaywallPresentation`). Bu hem dikkat dağıtmayı önler hem de
> Action Button yanlışlıkla ekran değiştirmez.

### 15.3 Bulunan ve düzeltilen hata: ödeme tolerans penceresi

Abonelik yetkisi hesabında tolerans (grace period) kolu **ters yazılmıştı**:
süresi dolmuş abonelik için iki dal da `.free` döndürüyordu, yani kullanıcı
bileşik bildirim gecikmesi yaşadığında **aniden** erişimini kaybediyordu.
Doğrusu: bitiş + 7 gün içinde Pro açık kalır. Test
`testGracePeriodKeepsAccessBriefly` ve `testExpiredSubscriptionRelocks` bunu
kapatır.

### 15.4 StoreKit 2 tasarımı

- Yetkiler **yalnızca** `Transaction.currentEntitlements`'ten türetilir;
  uygulamada "satın alındı" bayrağı tutulmaz (iptal/geri ödemede "hayalet
  Pro" oluşmaz).
- Bağlantı yoksa hata **fırlatmaz**, yalnızca boş yetki döner.
- `Transaction.updates` dinlenir → yenileme/iptal anında arayüz güncellenir.
- `transaction.finish()` her durumda çağrılır (atlanırsa işlem yeniden
  teslim edilir).
- Önbelleğe **yalnızca olumlu** bilgi yazılır; cihaz sıfırlamasında hayalet
  Pro oluşmaz.
- Ürünler yüklenemezse uygulama bozulmaz, yalnızca satın alma düğmeleri
  devre dışı kalır.

### 15.5 Mağaza metinleri (ADIM 2)

`App/Store/AppStoreMetinleri.md`:

- **Ad / alt başlık:** `DiveLog: Dalış Bilgisayarı` / `Bühlmann ZHL-16C · Nitrox`
- **Açıklama:** Türkçe ve İngilizce, altı bölümlü (güvenlik, Ultra'ya özel,
  Pro, su altı, veri, uyarı)
- **Anahtar kelimeler:** TR 93/100, EN 88/100 karakter
- **4 başlık A/B adayı**, 8 ekran görüntüsü senaryosu, sürüm notu şablonu

Apple'ın karakter sınırları (`AppStoreListing.Limits`) koda alındı ve
`StoreTextTests` her derlemede doğruluyor. **Testler iki gerçek hata buldu:**

1. Alt başlık adayı 32 karakter ile 30 sınırını aşıyordu → kısaltıldı
   (`· UDDF` çıkarıldı).
2. "DiveLog — Tüplü Dalış Bilgisayarı" adayı 33 karakterdi → "DiveLog: Tüplü
   Bilgisayar" olarak düzeltildi.

Ayrıca "anahtar kelimelerde boşluk yasaktır" varsayımı testte yanlış çıktı:
Apple çok kelimeli ifadeleri tam olarak indeksler (`apple watch ultra`
geçerli). Doğru kural baştaki/sondaki boşluk ve boş girdi yasağıdır; test ve
doküman buna göre düzeltildi.

### 15.6 Gizlilik (ADIM 3)

`App/Store/GizlilikPolitikasi.md` (yayınlanabilir) ve
`App/Store/AppPrivacyBeyani.md` (App Store Connect adım adım).

| Veri tipi | Toplama | İzleme |
|---|---|---|
| Konum (kaba + hassas) | Özel iCloud | Hayır |
| Sağlık ve Fitness | Özel iCloud | Hayır |
| Kullanıcı İçeriği | Özel iCloud | Hayır |
| Tanımlayıcılar | **Toplanmıyor** | Hayır |
| Satın Alımlar | **Toplanmıyor** | Hayır |

Kritik noktalar: **sunucu yok**, **izleme yok** (dolayısıyla ATT uyarısı
gerekmez ve `NSUserTrackingUsageDescription` eklenmemelidir), tüm veri
silinebilir, konum yalnızca dalışta ve yüzeyde okunur. `AppPrivacy` (kodda)
beyanı tanımlar ve `StoreTextTests` "tracking/analytics/appServer yok" ve
"her veri tipi silinebilir" değişmezlerini doğrular.

---

## 16. Testler

```
Tests/DiveCoreTests/
├── DivePhysicsTests / GasMixTests / GradientFactorsTests
├── TissueModelTests       Katsayılar, Schreiner, yarı ömür, tavan, GF99, GF aralığı
├── DecoEngineTests        NDL (PADI karşılaştırması), TTS, GF duyarlılığı, senaryolar
├── OxygenToxicityTests    NOAA CNS tablosu ve OTU formülü
├── DiveStateTests / LogEntryTests
├── DepthSensorTests       DepthReading + MockDepthSensor + canlı simülasyon akışı
├── DiveSimulatorTests     Profil, hız sınırları, sıcaklık, determinizm
├── AscentRateMonitorTests Yumuşatma, süreklilik, cooldown
├── AlarmCoordinatorTests  Alarm politikası + sahte haptic motor
├── DiveSessionControllerTests  Uçtan uca: sensör → motor → durum → LogEntry
├── DiveDisplayTests       Metinler, renk rollerı, göstergeler, pusola, AOD
└── DiveAccessoryDataTests Action Button niyeti, komplikasyon, özet, not
```

**1014 test, tamamı geçiyor.** Xcode'da `⌘U` / `swift test` ile çalışır.

> Not: `Sources/DiveWatch`, `DiveWatchUI`, `DivePhoneUI` ve `DiveStore` yalnızca iOS/watchOS
> SDK'siyle derlenir; bu ortamda
> (yalnızca Command Line Tools) `#if os(watchOS)` koruması nedeniyle boş modül
> olarak derlenir ve **tip denetimi yapılamamıştır**. Xcode'da watchOS hedefiyle
> ilk derlemede doğrulanmalıdır.

---

## 17. GF ayarları

| Ön ayar | Değer | Kullanım |
|---|---|---|
| `.default` | 100/100 | Matematiksel referans (PADI'ye en yakın) |
| `.conservative` | 80/85 | 30 m sınırı için popüler |
| `.moderate` | 50/80 | 30–45 m sınırı |
| `.aggressive` | 30/75 | Derin/uzun dalış |
| `.technical` | 30/70 | Trimix / teknik dalış |

Düşük GF **daha muhafazakârdır**: daha yüksek tavan, daha kısa NDL, daha uzun
dekompresyon. (Belgian Navy çalışması: GF "conservatism" değil "deviation"
faktörüdür; çok düşük GF'ler yavaş dokularda aşırı doygunluk yaratabilir.)

---

## 18. Sonraki adımlar

- **ADIM 12 (sırada)**: Sınır durum ve stres testleri (aşırı hızlı çıkış,
  sığ suda dip zamanı aşımı, WatchConnectivity kopması/çakışma çözümü).
- **ADIM 13 (sırada)**: `Info.plist` izinleri (konum, HealthKit, arka plan
  modları), App Icon seti, komplikasyon önizleme görselleri, Release yapılandırma
  ve imzalama (TestFlight).
- **ADIM 14 (ileride)**: Trimix/He desteği (MOD, ppHe, tavan şeffaflığı),
  gaz kesme tablosu uyarısı, batarya/pil göstergesi, dalış planlayıcı.
- **Xcode'da ilk derleme**: watchOS/iOS hedeflerini ve WidgetKit uzantısını
  oluştur, `Config/*.xcconfig` dosyalarını bağla, simge PNG'lerini üret,
  gerçek Apple Watch Ultra'da `CMAltimeter` kalibrasyonunu ve su kilidi akışını
  doğrula.
- **Çapraz doğrulama**: çekirdek Shearwater/Subsurface/MultiDeco tablolarıyla
  karşılaştırılmalı; derin durak algoritması GUE'nin tam Pyle dalgalanmasıyla
  sınanmalı.
- **Action Button kısayol ataması** ve Water Lock kullanıcı akışı
  saha doğrulaması.# DiveCore

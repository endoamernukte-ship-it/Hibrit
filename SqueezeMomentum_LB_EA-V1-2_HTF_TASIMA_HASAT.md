# SqueezeMomentum_LB_EA V1-2 · HTF Taşıma + Hasat + Donchian Motoru (v1.50)

Bu belge, EA'ya eklenen **"yaşlanan pozisyonu üst zaman dilimine taşıma" (HTF Escort)** ve
**"ters yönden kâr toplama" (Harvest)** motorunun mantığını, ayarlarını ve risk noktalarını anlatır.

---

## 1. Fikrin özeti

Senin tarif ettiğin akış:

> "1 dakikalıkta başladı, long açtı, TP olmadı → long pozisyonlar açıldığı andan itibaren
> 1 saatlik grafiğe alınsın; aralarda da short'lardan kâr toplansın."

MT5'te bir pozisyonu **fiziksel olarak** başka bir grafiğe/zaman dilimine taşımak mümkün değildir.
Pozisyon tek bir ticket'tır; grafiğe bağlı değildir. Bu yüzden fikri, gerçekten uygulanabilir ve
tutarlı bir mekanizmaya çevirdim:

> **Pozisyon aynı kalır; değişen şey onu yöneten KARAR SERİSİDİR.**

Yani:

| Aşama | Pozisyonun çıkış kuralları |
|---|---|
| **Aşama 1 – Hızlı TF (örn. M1)** | Mevcut mantık: girişten sonraki 3. uygun sinyal = TP, 3. ters sinyal = SL |
| **Aşama 2 – Taşıma (HTF, örn. H1)** | Pozisyon hâlâ açık ve eşik doldu → çıkışlar artık **H1 Squeeze Momentum** sinyalleriyle: 2. uygun H1 sinyali = TP, 2. ters H1 sinyali = SL |
| **Paralel – Hasat (hızlı TF)** | Taşınan pozisyonun **tersine** açılan M1 işlemleri kendi hızlı kurallarıyla kâr toplar (para TP/SL, 1 sinyal TP, süre sınırı) |

Böylece:

* Long, M1'in gürültüsünde 3 sinyalde kapanmak yerine H1 trendine bırakılır (daha uzun nefes),
* M1 tarafı boş durmaz: her SELL sinyalinde küçük short'lar açıp kârı toplar,
* Toplanan kâr panelde birikir ve (opsiyonel) ana pozisyondan **kısmi kâr** almaya yarar.

---

## 2. Akış şeması

```
        M1 mumu kapandı
               │
               ▼
     Squeeze renk geçişi var mı?
               │ evet
               ▼
   Taşınan (escort) pozisyon var mı?
        │ evet                 │ hayır
        ▼                      ▼
 Sinyal taşınan yönün            Normal giriş
 tersinde mi?                   (dengeleme kuralları)
   │ evet      │ hayır
   ▼           ▼
HASAT       "Aynı yönde taşınan var"
girişi      → sinyal atlanır (risk filtresi)
```

```
     Her tick / saniyelik timer
               │
               ├─► Taşınan pozisyon için eşik doldu mu?
               │      (açılış + 60 dk veya N mum)
               │      evet → SL/TP seviyeleri bir kez yeniden yazılır
               │              (temizle veya yeni sabit seviyeler)
               │
               ├─► HTF sinyal sayımı (10 sn'de bir taranır)
               │      H1'de 2. uygun sinyal → TP, 2. ters sinyal → SL
               │
               ├─► Para bazlı çıkışlar
               │      hasat para TP/SL, taşınan pozisyon para SL,
               │      hasat / taşıma süre sınırları
               │
               └─► Hasat kâr birikimi + (opsiyonel) kısmi kâr
```

---

## 3. Ayar grupları

### Grup 8 — HTF TAŞIMA

| Girdi | Varsayılan | Anlamı |
|---|---|---|
| `InpEscortEnabled` | true | Taşıma motoru açık/kapalı |
| `InpEscortMode` | yalnızca LONG | Hangi yöndeki pozisyonlar taşınır (LONG / SHORT / her iki yön) |
| `InpEscortTimeframe` | H1 | Taşıma zaman dilimi. **İşlem TF'sinden büyük olmak zorunda** (M1 → H1 gibi) |
| `InpEscortAfterMinutes` | 60 | Açılıştan kaç dakika sonra taşınır. `0` = açılış anında taşınır |
| `InpEscortAfterBars` | 0 | Alternatif tetik: işlem TF'sinde kaç mum sonra. İki tetikten **erken dolan** kazanır |
| `InpEscortOnlyIfProfit` | false | Yalnızca kârdaki pozisyonlar taşınır (zarardaki pozisyon hızlı TF'de kalır) |
| `InpEscortAnchor` | taşıma anı | HTF sinyal sayımı nereden başlar: **taşıma anı** veya **pozisyon açılışı** |
| `InpEscortTpSignalCount` | 2 | Taşınan pozisyon TP'si: kaçıncı uygun HTF sinyali |
| `InpEscortSlSignalCount` | 2 | Taşınan pozisyon SL'i: kaçıncı ters HTF sinyali |
| `InpEscortFixedTpPoints` / `...SlPoints` | 0 | Taşımada yazılacak sabit TP/SL (point). 0 = kapalı |
| `InpEscortClearOldExits` | true | Taşımada eski sabit TP/SL seviyelerini sil (pozisyona nefes alanı aç) |
| `InpEscortMaxRideHours` | 24 | Taşımanın üst süre sınırı; dolarsa pozisyon piyasadan kapatılır. 0 = kapalı |
| `InpEscortStopLossMoney` | 0 | Taşınan pozisyonun para bazlı SL'i (hesap birimi). 0 = kapalı |
| `InpEscortBlockSameSide` | true | Taşınan yönde **yeni** hızlı TF pozisyonu açılmaz (trendin tersine birikmeyi önler) |

### Grup 9 — HASAT

| Girdi | Varsayılan | Anlamı |
|---|---|---|
| `InpHarvestEnabled` | true | Hasat motoru açık/kapalı |
| `InpHarvestLot` | 0 | Hasat lotu (0 = normal lot) |
| `InpHarvestMaxPositions` | 4 | Aynı anda en fazla kaç hasat pozisyonu (0 = sınırsız) |
| `InpHarvestTakeProfitMoney` | 1.0 | Hasat para TP'si (hesap birimi). 0 = kapalı |
| `InpHarvestStopLossMoney` | 2.0 | Hasat para SL'i (hesap birimi). 0 = kapalı |
| `InpHarvestTpSignalCount` | 1 | Hasatın sinyal TP'si (hızlı TF) |
| `InpHarvestSlSignalCount` | 2 | Hasatın sinyal SL'i (hızlı TF) |
| `InpHarvestMaxLifeMinutes` | 0 | Hasat üst süre sınırı. 0 = kapalı |
| `InpHarvestTrimEnabled` | false | Biriken hasat kârıyla taşınan pozisyondan kısmi kâr al |
| `InpHarvestTrimProfit` | 5.0 | Kısmi kâr için birikmesi gereken hasat kârı |
| `InpHarvestTrimPercent` | 50 | Her tetikte kapatılacak hacim (%) |
| `InpHarvestTrimOnlyIfRideProfit` | true | Kısmi kâr yalnızca taşınan pozisyon kârdayken yapılır |

---

## 4. Örnek senaryo (M1 → H1)

1. **10:00** — M1'de BUY sinyali, 0.10 lot long açıldı. TP sayacı M1'de işliyor (3 sinyal).
2. **10:00–11:00** — Fiyat yatay; 3 uygun M1 sinyali gelmedi, TP olmadı.
3. **11:00** — Eşik (60 dk) doldu. Pozisyon **taşınan** oldu:
   * Varsa eski sabit TP/SL temizlendi,
   * Çıkış kararları artık **H1 mum renklerinden** üretiliyor,
   * M1'deki eski sinyal sayımı bu pozisyon için **tamamen kapandı** (çift sayım yok).
4. **11:05** — M1'de SELL sinyali → taşınan long'un tersi olduğu için **hasat short'u** açıldı.
   * Kâr $1'e ulaşınca ya da 1 uygun SELL sinyalinde kapanır,
   * $2 zarara düşerse veya süre sınırı dolarsa kapanır.
5. Aynı sırada M1'de BUY sinyali gelirse → taşınan long yönünde olduğu için **atlanır**.
6. **13:00** — H1'de 2. ters (SELL) sinyali → taşınan long SL ile kapanır.
   Ya da H1'de 2. uygun (BUY) sinyali → TP ile kapanır.
   Ya da 24 saat / para SL'i dolarsa koruma devreye girer.

---

## 5. Kritik tasarım kararları (ve nedenleri)

* **Kalıcı durum yok, hesaplanabilir durum var.** "Taşınmış mı?" sorusunun cevabı
  `pozisyon açılış zamanı + eşik` ile her seferinde yeniden hesaplanır. EA yeniden başlatılsa
  bile pozisyonların taşınma durumu bozulmaz; ekstra dosya/global değişken gerekmez.
* **Çift sayım yok.** Taşınan pozisyon hızlı TF çıkış motorundan tamamen çıkarılır; HTF sayımı
  varsayılan olarak **taşıma anından** başlar (`InpEscortAnchor`). "Pozisyon açılışından say"
  seçilirse long, taşındığı anda geçmiş H1 sinyallerini de devralır (agresif mod).
* **Hasat işlemleri dengeleme farkını bilerek aşar.** Hasat, taşınan pozisyonun doğal hedge'idir;
  bu yüzden fark kuralına takılmaz. Kendi sert limitleri vardır: `InpHarvestMaxPositions`,
  para TP/SL, sinyal TP/SL, süre sınırı.
* **Panelde yaşayan muhasebe.** Kapanan her hasat işleminin net sonucu (kâr + swap + komisyon)
  `HistorySelectByPosition` ile hesaplanıp birikime yazılır; "toplanan kâr" ve "kısmi kâr kredisi"
  panelde görünür.
* **Kısmi kâr** `PositionClosePartial` ile yapılır: kalan hacim broker minimumunun altına
  düşecekse işlem tamamı kapatılır (hatalı emir gönderilmez).

---

## 6. Riskler ve dikkat edilecekler

* **Hedging hesap gerekir.** Taşınan long + hasat short aynı sembolde aynı anda açık olacağı için
  netting hesapta bu mantık çalışmaz (EA bunu başlangıçta uyarı olarak yazar).
* **Taşınan pozisyonun hızlı TF koruması kalkar.** Bu yüzden `InpEscortMaxRideHours`,
  `InpEscortStopLossMoney` ve `InpEscortSlSignalCount` üçlüsünü birlikte kullanmak en güvenli
  kurulumdur. Üçü de `0` yapılırsa EA başlangıçta uyarır.
* **H1 sinyali seyrektir.** Taşımadan sonra pozisyon saatlerce açık kalabilir; bu tasarımın
  doğasıdır, hata değildir.
* **Marj/teminat:** hasat + taşıma aynı anda ters yönde marj kullanır. `InpHarvestLot` ve
  `InpHarvestMaxPositions` bu yüzden var; hesap büyüklüğüne göre küçültün.
* **Yorum etiketi (comment) kırpılırsa:** bazı brokerlar emir yorumunu keser. EA, hasat
  pozisyonlarını ayrıca bellek içi bir listede tutar; EA kapanana kadar sorun olmaz. EA kapalıyken
  kapanan hasat işlemlerinin kârı birikime eklenmez (yalnızca panel rakamı etkilenir, işlem
  mantığı etkilenmez).
* **Otomatik sıfırlama** (grup 6) çalışırsa taşınan pozisyonlar da kapatılır; bu bilinçli bir
  güvenlik davranışıdır.

---

## 7. Strateji test cihazı (Strategy Tester) notları

* Test için `InpEscortAfterMinutes` değerini küçültün (örn. 5–15 dk) ki M1 testinde taşıma
  aşaması sık tetiklensin.
* HTF serisi test cihazında gerçek veriden okunur; "Model: every tick" ve sembolün H1 geçmişinin
  indirilmiş olması gerekir.
* `InpLogIndicator` + uzman günlüğü ile taşıma/hasat kararlarının sırasını takip edebilirsiniz:
  `Taşıma: ticket=... yeni seviyeler SL=... TP=...`, `Hasat kapandı: ...`, `Kısmi kâr: ...`.

---

## 8. Donchian Trend Ranges motoru (v1.50) — menüden sinyal seçimi

Pine kodu (`Donchian Trend Ranges [AlgoAlpha]`) MQL5'e **birebir** çevrildi ve EA'ya
ikinci bir *sinyal motoru* olarak eklendi. `InpSignalEngine` ile seçilir:

| Motor | Açıklama |
|---|---|
| `ENGINE_SQUEEZE` | Mevcut davranış: Squeeze Momentum renk geçişleri |
| `ENGINE_DONCHIAN` | Donchian Trend Ranges olayları (aşağıdaki menüler aktif) |

### 8.1 Açılır menüler (grup 10)

Her satır bir **açılır menü**dür; istediğin olayı seçersin:

| Girdi | Ne yapar |
|---|---|
| `InpDonLongEntry` | **LONG giriş sinyali** — örn. `Strong Short TP` seçersen, o olay oluştuğunda LONG açılır |
| `InpDonShortEntry` | **SHORT giriş sinyali** |
| `InpDonLongTp` | LONG pozisyonun **TP sinyali** |
| `InpDonLongSl` | LONG pozisyonun **SL sinyali** |
| `InpDonShortTp` | SHORT pozisyonun **TP sinyali** |
| `InpDonShortSl` | SHORT pozisyonun **SL sinyali** |
| `InpDonTpSignalCount` / `InpDonSlSignalCount` | Kaçıncı sinyalde kapatılsın (1 = ilk sinyal, 0 = kapalı) |
| `InpDonTpOnlyInProfit` / `InpDonSlOnlyInLoss` | TP sadece kârdayken / SL sadece zarardayken uygulanır |

Seçilebilen olaylar:

| Menü adı | Pine karşılığı | Anlam |
|---|---|---|
| Bullish Trend Shift | `crossover(close, fbasis)` | Fiyat basis'i yukarı keser |
| Bearish Trend Shift | `crossunder(close, fbasis)` | Fiyat basis'i aşağı keser |
| Strong Long TP | `crossunder(close, uu)` | Fiyat uu'nun altına iner |
| Weak Long TP | `crossunder(close, ul) and not (close,uu)` | ul altına iner, uu hariç |
| Strong Short TP | `crossover(close, ll)` | Fiyat ll'nin üstüne çıkar |
| Weak Short TP | `crossover(close, lu) and not (close,ll)` | lu üstüne çıkar, ll hariç |
| Squeeze BUY / SELL | Renk geçişleri | Donchian motorunda da seçilebilir |

> Not: Donchian motorunda Squeeze olayları da hesaplanır; yani örneğin girişi
> "Squeeze BUY", TP'yi "Strong Long TP" olarak karışık kurabilirsin.

### 8.2 Pine matematiği (birebir)

```
l      = ta.lowest(length)                  // en düşük DÜŞÜK
u      = ta.highest(length)                 // en yüksek YÜKSEK
basis  = avg(u, l)
fbasis := basis == basis[con] ? basis : fbasis[1]      // yapışkan
dev    = ta.stdev(close, length, false) * mult          // n-1 (unbiased)
vol    = ta.atr(14)                                     // RMA(TR)
rangge := fbasis != fbasis[1] ? dev : rangge[1]         // yapışkan
upper  = fbasis + rangge ; lower = fbasis - rangge
uu = upper + vol ; ul = upper - vol ; lu = lower + vol ; ll = lower - vol
```

* Pine'daki **na** davranışı korunur: karşılaştırmalarda na → `false` kabul edilir.
  Bu yüzden `fbasis` ancak `basis` bir mum boyunca değişmediğinde tanımlı olur ve
  seviyeler o andan sonra çizilir (grafikte ilk ~70-80 mum boş görünür — Pine'da da öyle).
* `ta.stdev(..., biased=false)` → n-1 bölmesi kullanılır.
* `ta.atr` → Wilder RMA; ilk değer ilk `length` TR'nin SMA'sı.
* Sinyaller yalnızca **kapanmış mumlarda** ve iki barın da seviyeleri geçerliyken üretilir.

### 8.3 Grafikte doğrulama

`DonchianTrendRanges.mq5` göstergesi aynı matematiği çizer:

* Renkli **basis** çizgisi (fiyat üstündeyse yukarı rengi),
* Üst/alt/basis **bulutları** (DRAW_FILLING), ara bölge noktalı çizgileri,
* **X** işaretleri: Strong Long/Short TP, **◆**: Weak Long/Short TP,
* Opsiyonel `Alert()` — Pine `alertcondition` karşılığı.

Göstergeyi aynı grafiğe ekleyip EA'nın ürettiği oklarla karşılaştırabilirsin.
(Pine'daki `barcolor()` MQL5 göstergesinde doğrudan yapılamaz; yerine basis rengi kullanılır.)

### 8.4 Örnek kurulum (senin tarifin)

```
InpSignalEngine  = Donchian
InpDonLongEntry  = Strong Short TP   -> bu olay geldiğinde LONG açılır
InpDonShortEntry = Strong Long TP    -> bu olay geldiğinde SHORT açılır
InpDonLongTp     = Weak Long TP      -> long, ilk zayıf long TP sinyalinde kâr alır
InpDonLongSl     = Bearish Trend Shift
InpDonTpSignalCount = 1
InpDonSlSignalCount = 1
```

Taşıma + hasat motorları bu kurulumda da çalışır: 60 dk sonra taşınan pozisyon H1
serisinde **aynı seçili olaylarla**, hasat pozisyonları kendi sayılarıyla kapatılır.

---

## 9. Değişen dosya

* `DonchianTrendRanges.mq5` — yeni gösterge (Pine birebir çeviri, sinyal işaretleri + alert)
* `SqueezeMomentum_LB_EA-V1-2.mq5` — sürüm **1.31 → 1.50**
  * Yeni: `ENUM_SQZ_ESCORT_MODE`, `ENUM_SQZ_ESCORT_ANCHOR`
  * Yeni: grup 8 (HTF taşıma) ve grup 9 (hasat) girdileri
  * Yeni: `EvaluateExitSeries()` (tek çıkış motoru, üç kullanım), `ProcessEscortPositions()`,
    `CheckPositionMoneyExits()`, `UpdateHarvestPocket()`, `CheckHarvestTrim()`,
    `ManageEscortAndHarvest()`
  * Değişen: `OpenOneTrade()` (hasat lotu + `HARV` etiketi), `OpenPositionBySignal()` (hasat
    ayrımı + taşıma filtresi), `ManageSignalExits()` (taşınanları atlar), `UpdateChartInfo()`
    (yeni panel satırları), `OnInit()` (doğrulama + loglar), `OnTick()/OnTimer()`
  * v1.50: `ENUM_SQZ_SIGNAL_ENGINE`, `ENUM_SQZ_EVENT`, `ComputeDonchianEvents()`,
    `SqueezeEventsFromColors()`, `EvaluateEventExit()`, `ManageDonchianExits()`;
    `ProcessClosedBar()` motor seçimine göre dallanır; HTF taşıma serisi de seçilen motorla
    hesaplanır (`g_escort_events`)

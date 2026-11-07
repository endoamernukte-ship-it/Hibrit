# APEX COMBAT ENGINE — Kurumsal Mimari Dokümanı

**Sürüm:** 2.00 · **Platform:** MetaTrader 5 (MQL5) · **Çekirdek:** Squeeze Momentum [LazyBear]
**Hesap tipi:** Hedging (zorunlu) — netting hesapta kısıtlı mod
**Durum:** Üretime hazır iskelet + tam parametre seti (backtest/optimizasyon zorunludur)

---

## 0. Yönetici Özeti

`SqueezeMomentum_LB_EA.mq5` içindeki LazyBear çekirdeği **hiç değiştirilmeden** bir
sınıfa (`CApexSqueeze`) taşındı. Onun üzerine dört bağımsız savaş katmanı ve tek bir
sermaye koruma güvenlik duvarı inşa edildi:

| Katman | Sınıf | Dosya | Görev |
|---|---|---|---|
| 2 — Analitik | `CApexAnalytics` | `Include/ApexAnalytics.mqh` | 5 boyutlu rejim tespiti |
| 3a — Grid | `CApexGrid` | `Include/ApexGrid.mqh` | Elastik bukalemun grid + mod evrimi |
| 3b — Scalp/Kalkan | `CApexScalp` | `Include/ApexScalp.mqh` | Mikro-scalp + delta-nötr savunma |
| 2 — Risk | `CApexRisk` | `Include/ApexRisk.mqh` | Sermaye koruma güvenlik duvarı |
| 1 — Yürütme | `CApexExecution` | `Include/ApexTrade.mqh` | Broker etkileşimi + rol etiketli defter |
| 1 — Çekirdek | `CApexSqueeze` | `Include/ApexSqueezeCore.mqh` | LazyBear momentum + türevler |
| 0 — Temel | — | `Include/ApexTypes.mqh` | Tipler, sabitler, etiket kodlama |

İstenen üç ana fonksiyon (sınıf metodu olarak, birebir bu isimlerle):

```
CApexAnalytics::DetectAdvancedMarketRegime()    -> 5 boyutlu rejim tespiti
CApexGrid::ManageAdaptiveElasticGrid()          -> elastik grid + yön değiştirme
CApexScalp::ExecuteHybridScalpAndDefense()      -> mikro-scalp + hedge kalkanı
```

---

## 1. Sınıf ve Modül Mimarisi

### 1.1 Bağımlılık Grafiği (katmanlar)

```
┌─────────────────────────────────────────────────────────────────────────┐
│ KATMAN 4 — ORKESTRASYON                                                 │
│   ApexCombatEngine.mq5                                                  │
│     ├─ Görev zamanlayıcı (cooperative, zaman dilimli)                    │
│     ├─ Çekirdek sinyal döngüsü (ORİJİNAL MANTIK - korundu)              │
│     ├─ Akıllı Çıkış Matrisi (Smart Exit Matrix)                         │
│     └─ Panel / telemetri / OnTester fitness                             │
└───────┬───────────────┬───────────────┬───────────────┬─────────────────┘
        │               │               │               │
        ▼               ▼               ▼               ▼
┌───────────────┐ ┌──────────────┐ ┌──────────────┐ ┌──────────────────┐
│ KATMAN 3      │ │ KATMAN 3     │ │ KATMAN 2     │ │ KATMAN 2         │
│ CApexGrid     │ │ CApexScalp   │ │ CApexRisk    │ │ CApexAnalytics   │
│ (bar hızı)    │ │ (tick hızı)  │ │ (güvenlik    │ │ (5 boyut)        │
│               │ │              │ │  duvarı)     │ │                  │
│ Mod evrimi    │ │ Mikro pivot  │ │ DD kademeleri│ │ D1 Squeeze       │
│ Elastik adım  │ │ Kalkan kilidi│ │ Lot sınırları│ │ D2 Hurst         │
│ Bacak kesme   │ │ Marjin nefesi│ │ Toksisite    │ │ D3 ATR bandı     │
│ Sepet hedefi  │ │ Zaman stopu  │ │ Kill-switch  │ │ D4 Hacim profili │
└───────┬───────┘ └──────┬───────┘ └──────┬───────┘ └────────┬─────────┘
        │                │                │                  │
        └────────────────┴────────┬───────┴──────────────────┘
                                  ▼
                    ┌───────────────────────────┐
                    │ KATMAN 1 — YÜRÜTME        │
                    │ CApexExecution (CTrade)   │
                    │ Rol etiketli defter       │
                    │ Geri çekilmeli yeniden    │
                    │ deneme / normalizasyon    │
                    └─────────────┬─────────────┘
                                  ▼
                    ┌───────────────────────────┐
                    │ KATMAN 1 — ÇEKİRDEK       │
                    │ CApexSqueeze (LazyBear)   │
                    │ linreg detrend + renk     │
                    │ + hız/ivme/mikro-pivot    │
                    └─────────────┬─────────────┘
                                  ▼
                    ┌───────────────────────────┐
                    │ KATMAN 0 — ApexTypes      │
                    │ enum / struct / yardımcı  │
                    └───────────────────────────┘
```

**Tasarım kuralı:** Katmanlar yalnızca aşağıya doğru konuşur. Grid ↔ Scalp birbirini
çağırmaz; ikisi de yalnızca `CApexRisk` ve `CApexExecution` üzerinden konuşur.
Bu, bir motorda yapılacak değişikliğin diğerini bozmasını engeller.

### 1.2 "Multi-thread" gerçeği ve çözümü

MQL5 EA'ları **tek iş parçacıklıdır**; `OnTick`/`OnTimer` aynı thread üzerinde çağrılır.
Gerçek thread açmak mümkün değildir (ve broker API'si thread-safe değildir). Bunun yerine
**cooperative (işbirlikçi) zaman dilimli görev mimarisi** kullanıldı:

| Görev | Tetikleyici | Frekans | İş |
|---|---|---|---|
| **G0** | `OnTick` / `OnTimer` | `InpTickThrottleMs` (vars. 250 ms) | Mikro-scalp + savunma kalkanı + risk güncelleme |
| **G1** | Yeni mum (sinyal TF) | 1 bar | Seri tazeleme → rejim tespiti → çekirdek sinyal → grid |
| **G2** | `ReconcileTask` | `InpReconcileSec` (vars. 20 sn) | Defter mutabakatı, yetim emir temizliği |
| **G3** | `OnTradeTransaction` | olay bazlı | Dolum sonrası iyileştirme bayrağı |
| **G4** | Panel | 400 ms | Telemetri |

Böylece yüksek frekanslı mikro motor (G0) ile ağır bar-bazlı motor (G1) aynı thread
içinde **birbirini bloke etmeden, eşzamanlı çalışıyor gibi** davranır. Ağır
hesaplar (Hurst, hacim profili) yalnızca G1'de, yani bar başına **bir kez** koşar;
G0 yalnızca O(1) tick işleri yapar. Bu, "multi-thread mantık"ın MQL5'teki doğru
karşılığıdır: **zaman dilimli eşzamanlılık (cooperative concurrency)**.

Ek olarak gerçek paralellik istenirse: aynı EA birden fazla sembol grafiğine
eklenir, her örnek kendi `magic` numarasıyla bağımsız çalışır, ortak risk
durumu `GlobalVariable` üzerinden paylaşılır.

### 1.3 Rol Etiketli Defter (Self-Healing temeli)

Her emir/pozisyon 8 karakterlik bir etiketle işaretlenir:

```
APX + [C|G|S|H] + [B|S] + [+00..+99]
 │        │         │          └─ grid seviyesi (0 = çekirdek/scalp/hedge)
 │        │         └─ yön (B=Buy, S=Sell)
 │        └─ rol: C=Çekirdek  G=Grid  S=Scalp  H=Hedge
 └─ sabit ön ek
```

**Neden önemli:** EA veya terminal çökerse, yeniden başlatmada `CApexExecution::RebuildBook()`
tüm açık pozisyonları tarar, yorum alanından rol/yön/seviyeyi geri okur ve grid planını
**hiçbir durum bilgisine ihtiyaç duymadan** yeniden kurar. Etiket okunamazsa (broker
yorumu kırparsa) pozisyon yetim kalmaz: tipinden yönü, magic'den aidiyeti alınır ve
`ROLE_CORE` olarak sahiplenilir. Bu, "kendini onaran" iddiasının somut karşılığıdır.

Kalıcı durum (restart sonrası da yaşar):

| GlobalVariable | İçerik |
|---|---|
| `APEX_<magic>_<symbol>_peak` | Zirve equity (drawdown referansı) |
| `APEX_<magic>_<symbol>_halt` | Kill-switch gün damgası (yeni günde otomatik sıfırlanır) |
| `APEX_<magic>_<symbol>_anchor` | Grid merkezi |

---

## 2. State Machine — 5 Boyutlu Rejim Analizi

### 2.1 Durum Uzayı

```
                    ┌──────────────┐
                    │  REGIME_BOOT │  (istatistik ısınması, InpBootBars)
                    └──────┬───────┘
                           │ skor motoru olgunlaşınca
     ┌─────────────────────┼─────────────────────┬────────────────────┐
     ▼                     ▼                     ▼                    ▼
┌─────────────┐   ┌─────────────────┐   ┌────────────────┐   ┌──────────────┐
│ ACCUMULATION│   │ BREAKOUT_ATTACK │   │ MEAN_REVERSION │   │VOLATILITY_   │
│ (gizli      │◄─►│ (mızrak modu)   │◄─►│ (çift yönlü    │◄─►│TRAP (fakeout)│
│  toplanma)  │   │                 │   │  hedged grid)  │   │              │
└─────────────┘   └─────────────────┘   └────────────────┘   └──────────────┘
     GRID: STEALTH     GRID: TREND RIDER     GRID: HEDGED        GRID: FORTRESS
     Scalp: yarım      Scalp: rüzgarla       Scalp: kenar fade   Scalp: KAPALI
                                                                       
        ┌──────────────────────────────────────────────┐
        │  SERMAYE KORUMA OVERRIDE (öncelikli, zorunlu)│
        │  DD ≥ InpDDDefense  |  günlük zarar limiti   │
        │  marjin seviyesi < %250                      │
        └───────────────────────┬──────────────────────┘
                                ▼
                    ┌───────────────────────┐
                    │  STATE_DEFENSE_LOCK   │  → GRID: FROZEN
                    │  (siper modu)         │  → Kalkan: delta-nötr
                    └───────────┬───────────┘
                                │ soğuma + DD iyileşmesi + ATR normalleşmesi
                                ▼
                        skor motoruna devir
```

### 2.2 Beş Boyut (ölçüm → üyelik → oy)

Her boyut önce **ham ölçüm**, sonra **0..1 üyelik (membership)** değerine dönüştürülür;
rejimler bu üyeliklerin ağırlıklı toplamıyla yarışır. Ham fiyat/ATR farklı sembollerde
ölçek değiştirdiği için **tüm üyelikler normalize edilir** — bu, sistemin sembolden
sembolle parametre değiştirmeden çalışmasını sağlar.

#### D1 — Squeeze Basıncı (`ComputeSqueezeDim`)

| Ölçüm | Tanım |
|---|---|
| `sqz_compress_bars` | Geriye doğru kesintisiz `sqzOn` bar sayısı |
| `sqz_energy` | `clamp(compress_bars / 12, 0, 1)` — depolanan enerji |
| `bars_since_release` | Son `ON → OFF` salınımından beri bar |
| `release_dir` | Salınım anındaki momentum işareti (std'nin %35'ini aşarsa) |
| `sqz_flicker` | Son 40 barda ON/OFF geçiş sayısı → **tuzak göstergesi** |

#### D2 — Hurst Üsteli (`ComputeHurst`)

Varyans-temelli tahmin (R/S'den daha kararlı, O(n·L)):

```
Var( ln P(t+L) − ln P(t) )  ∝  L^(2H)
log Var(L) = 2H · log L + c        →  doğrusal regresyon eğimi = 2H
H = eğim / 2,   L = 2..InpHurstMaxLag
```

Ana TF ağırlığı %65, bağlam (üst TF) ağırlığı %35 — çoklu zaman dilimi füzyonu.

| H | Sınıf | Anlam |
|---|---|---|
| > 0.56 | `PERSIST_TREND` | Trend kalıcı → kırılma takip edilir |
| 0.46–0.56 | `PERSIST_RANDOM` | Gürültü → sabırlı davranış |
| < 0.46 | `PERSIST_MEAN_REVERT` | Anti-kalıcı → ortalamaya dönüş gridi |

#### D3 — ATR Volatilite Bandı (`ComputeATR`)

```
TR(i)  = max(H−L, |H−C[i−1]|, |L−C[i−1]|)
ATR(i) = SMA(TR, InpATRPeriod)
atr_z  = (ATR − mean(ATR son N)) / std(ATR son N)
```

| `atr_z` | Band |
|---|---|
| ≤ −0.75 | `CRUSH` (ezilme — sıkışma habercisi) |
| −0.75 .. 0.85 | `NORMAL` |
| 0.85 .. 1.90 | `EXPANSION` |
| ≥ 1.90 | `EXPLOSIVE` (patlayıcı — fakeout riski) |

`atr_z` aynı zamanda **grid elastikiyetinin** ve **kilit açma koşulunun** girdisidir.

#### D4 — Hacim Profili / Likidite Dağılımı (`ComputeVolumeProfile`)

Son `InpVPLookback` bar, `InpVPBuckets` fiyat kovasına hacim olarak dağıtılır
(gerçek hacim yoksa tick hacmi; o da yoksa eşit ağırlık):

```
POC = en yüksek hacimli kova                     (Point of Control)
VA  = POC'tan dışa doğru hacmin %70'i toplanana kadar  → VAH / VAL
vp_pos:
   +1  fiyat VAH üstü   → PREMIUM  (kırılma KABULÜ)
    0  fiyat VA içinde  → DENGE    (rotasyon)
   −1  fiyat VAL altı   → İSKONTO  (kırılma REDDİ)
```

Ek likidite okumaları:

| Metrik | Formül | Yorum |
|---|---|---|
| `balance` | Merkezdeki 1/3'lük kovadaki hacim / toplam | ↑ = denge/range, ↓ = trend |
| `absorption` | Son 10 barda (dar menzil + yüksek hacim + uç kapanış) oranı | ↑ = **akıllı para emilimi** |
| `cvd_slope` | (yukarı bar hacmi − aşağı bar hacmi) / toplam | −1..+1 kümülatif akış |
| `vp_skew` | (POC üstü hacim − POC altı hacim) / toplam | profil asimetrisi |

#### D5 — Momentum Türevi (`ComputeMomentumDim`)

LazyBear momentum serisi `m[i]` üzerinden (fiyat değil — momentumun kendisi türevlenir):

```
hız  vel(i)   = (m[i] − m[i−k]) / k
ivme accel(i) = vel(i) − vel(i−k)
mom_z         = m[i] / std(m, 80)
vel_z, accel_z= normalize (std/k ölçeğinde)
flip_rate     = son 30 barda momentum işaret değişim sıklığı
vel_zero_cross= sign(vel(i)) ≠ sign(vel(i−1))
fatigue       = (|mom_z| > 0.9 VE |vel| < 0.35·max|vel|₈)  VEYA
                (sign(vel) ≠ sign(mom))                    VEYA
                vel_zero_cross
```

`fatigue` (momentum yorgunluğu) = **türevin sıfıra yakınsaması**. Akıllı Çıkış
Matrisi'nin ve Sepet Sweep'in tetikleyicisidir.

### 2.3 Oylama ve Histerezis

```
m_compress  = sqz_energy
m_release   = salınım tazeliği (0..InpReleaseWindow)
m_trend_p   = norm(H, hurst_mr → hurst_trend)      m_mr_p = 1 − m_trend_p
m_vol_exp   = norm(atr_z, −0.25 → atr_z_explosive) m_vol_calm = 1 − m_vol_exp
m_out_val   = |vp_pos| == 1 ? 1 : 0                m_in_val = 1 − m_out_val
m_mom_str   = norm(|mom_z|, 0.4 → 2.0)             m_mom_weak = 1 − m_mom_str
m_flip      = norm(flip_rate, 0.22 → 0.60)         m_flick = norm(sqz_flicker, 2 → 9)
m_align     = (release_dir, mom_dir, vp_pos, cvd_sign, vp_skew) oy birliği oranı
```

| Rejim | Skor (ağırlıklı toplam) |
|---|---|
| `ACCUMULATION` | `+34·compress +16·vol_calm +14·in_val +18·absorption +12·mom_weak +8·balance −25·release −18·vol_exp` |
| `BREAKOUT_ATTACK` | `+40·release +22·vol_exp +20·out_val +22·trend_p +18·mom_str +20·align −20·mom_weak −12·flip` |
| `MEAN_REVERSION` | `+30·mr_p +18·in_val +20·balance +14·mom_weak +16·flip +12·vol_calm −22·release −15·vol_exp −10·mom_str` |
| `VOLATILITY_TRAP` | `+38·vol_exp +26·flip +14·(1−align) +12·out_val +10·flick −25·vol_calm −10·trend_p` |
| `DEFENSE_LOCK` | **Oy dışı** — yalnızca sermaye koruma tetikler (override) |

**Histerezis (titreme önleyici):**

```
yeni_rejim_skoru ≥ mevcut_rejim_skoru + InpRegimeMargin  (vars. 12)
VE mevcut rejimde geçirilen bar ≥ InpRegimePersistence   (vars. 2)
```

`confidence = (en_iyi − ikinci) / en_iyi` → düşük güvende grid adımı %35 genişletilir,
dinamik R:R küçültülür. Yani **sistem ne kadar emin değilse o kadar ihtiyatlı davranır.**

---

## 3. Adaptif Bukalemun Grid — `ManageAdaptiveElasticGrid()`

### 3.1 Elastomer Adım Matematiği

Sabit pip aralığı **yasaktır**. Adım her barda yeniden hesaplanır:

```
temel_adım = ATR × InpGridStepATRMult                 (vars. 0.85 ATR)
elastikiyet= clamp(ATR / ATR_ortalama, min_mult, max_mult)   (vars. 0.60 .. 2.20)
mod_katsayı= STEALTH 1.70 | HEDGED 1.00 | TREND_RIDER 0.85 | FORTRESS 2.20
güven_kats.= 1 + (1 − confidence) × 0.35              (belirsizlikte seyrek ağ)

ADIM = temel_adım × elastikiyet × mod_katsayı × güven_katsayı
ADIM = max(ADIM, 2×stops_level, 4×spread, 10×point)   (broker fizik kuralları)
```

**Sonuç:** volatilite patlarsa ağ otomatik genişler (aynı fiyat bandına daha az
bacak → marjin şoku olmaz), volatilite ezilirse ağ daralır (fırsat kaçmaz).

### 3.2 Merkez (Anchor) Yönetimi

| Mod | Merkez |
|---|---|
| HEDGED / STEALTH / FORTRESS | Değer alanı ortası `(VAL+VAH)/2` — **likidite çekirdeği** |
| TREND_RIDER | Anlık fiyat (piramit, piyasadan yukarı/aşağı) |

Fiyat merkezden `InpGridRecenterATR × ATR` (vars. 3 ATR) uzaklaşırsa merkez
yeniden kurulur, tüm bekleyen emirler iptal edilir, yeni geometri kurulur.
Grid piyasanın arkasından sürüklenmez; **piyasanın gittiği yere yeniden konumlanır.**

### 3.3 Lot Eğrisi — Anti-Martingal

Klasik martingal (her seviyede lotu ikiye katlama) **yasaktır**:

| Mod | Lot(seviye i) |
|---|---|
| HEDGED | `base × (1 + 0.06·(i−1))`, **tavan `base × 1.60`** |
| TREND_RIDER | `base × max(0.45, 1.15 − 0.15·(i−1))` — **piramit: ilk ekleme en büyük** |
| STEALTH | `base × 0.5` (sabit) |
| FORTRESS | `base × 0.4` (sabit) |

Toplam bacağın üzerinde bir de **marjin ve toplam lot tavani** (`InpMaxTotalLots`)
uygulanır; her lot `OrderCalcMargin` ile **işlem öncesi** marjin testinden geçer
(`CanAfford`: işlem sonrası marjin seviyesi ≥ %400).

### 3.4 Mod Evrimi — Rejim Değişince Ne Olur?

| Geçiş | Anında Yapılan İşlem |
|---|---|
| → `TREND_RIDER` | 1) Tüm bekleyen emirler iptal 2) **ters yöndeki tüm grid bacakları kapatılır (Cut Loss)** — en zararlıdan başlayarak 3) Merkez = piyasa 4) Yalnızca trend yönünde **stop** emirleriyle piramit kurulur 5) Bacak TP'si yoktur: çıkışı sepet + izleyen stop yönetir |
| → `HEDGED` | Çift yönlü **limit** ağı; merkez = değer alanı; her bacağın TP'si `1.0 ATR`, güvenlik SL'si `4.0 ATR` |
| → `STEALTH` | 2 seviye, adım ×1.70, lot ×0.5 — gizli toplanma, minimum iz |
| → `FORTRESS` | 2 seviye, adım ×2.20, lot ×0.4 — sahte kırılmalara karşı seyrek ve küçük |
| → `FROZEN` | Tüm bekleyen emirler iptal, yeni bacak yok, yalnızca mevcutlar izlenir |
| Trend yönü tersine dönerse | Eski yönün bacakları kesilir, merkez piyasaya taşınır, piramit ters yönde kurulur |

### 3.5 Sepet (Basket) Yönetimi — Akıllı Çıkış Matrisi'nin grid ayağı

```
hedef = max( InpGridBasketATR × ATR × toplam_lot × point_value ,     (vars. 1.2 ATR)
             InpGridBasketEqPct% × equity )                           (vars. %0.35)
hedef = max(hedef − SAVAŞ SANDIĞI, 0.15 × ATR × lot × point_value)
stop  = −1.6 × hedef
```

1. **Hedef**: sepet kârı hedefe ulaşınca GRID + CORE beraber kapatılır, döngü sıfırlanır, 2 bar nefes.
2. **Smart Profit Sweep**: `fatigue = 1` ve sepet kârı > hedefin %25'i → **sinyal sayısı beklenmez**, sepet kapanır.
3. **Kısmi Sweep**: yorgunluk var ama sepet zararda → yalnızca kârlı bacaklar realize edilir (risk azaltma).
4. **Sepet stopu**: kademe RED ise tam kapanış; değilse en zararlı 2 bacak kapatılır (kontrollü azaltma).
5. **Chandelier trail** (TREND_RIDER): kâr 1 ATR'yi geçince SL girişe çekilir, sonra `1.2 ATR` ile izlenir.

**Savaş sandığı (War Chest):** mikro-scalp kârları bir havuzda birikir ve
**sepet hedefini düşürür** — yani scalp kazandıkça grid daha erken, daha küçük
hedefle kapanır. İstenen "ana grid kârını katlama" etkisinin mekanizması budur.

---

## 4. Hibrit Scalp ve Savunma Protokolü — `ExecuteHybridScalpAndDefense()`

### 4.1 Micro-Scalp Engine (tick hızı)

Ana grid bar hızında orta vadeli yapıyı yönetirken, içeride yüksek frekanslı bir
motor çalışır. Tetikleyici, **momentum histogramının kendi içindeki mikro tepeleridir**:

```
MicroPivot(i, span) :
   m[i] , [i−span, i+span] aralığındaki maksimum ise VE  m[i] >  0.45·std  →  −1 (SHORT)
   m[i] , [i−span, i+span] aralığındaki minimum  ise VE  m[i] < −0.45·std  →  +1 (LONG)
   (pivot, span bar geride doğrulanır — gelecek bar kullanılmaz)
```

| Rejim | Scalp Davranışı |
|---|---|
| `BREAKOUT_ATTACK` | Yalnızca trend yönünde — **rüzgârla** |
| `MEAN_REVERSION` | Değer alanı kenarlarından **fade** (VAH'ta sat, VAL'de al) |
| `ACCUMULATION` | Momentum yönünde, **yarım boyut** |
| `VOLATILITY_TRAP` | **KAPALI** (tuzakta mikro işlem yok) |
| `DEFENSE_LOCK` | **KAPALI** — kilitte yalnızca kalkan yaşar |

**Giriş filtreleri (hepsi birlikte):** mikro pivot ✓ · rejim yanlılığı ✓ ·
`scalp TF` son 3 bar ekstreminden uzaklık < `0.6 ATR` (**kovalama yasağı**) ✓ ·
spread ✓ · soğuma süresi ✓ · aynı yönde açık mikro işlem sayısı ✓ · risk izni ✓.

**Çıkış kuralları (tick bazlı):**

1. Mikro momentum hızı tersine döner dönmez kapanır (`vel` işaret değişimi)
2. Zaman stopu: `InpScalpMaxBars` (scalp TF barı)
3. **MFE koruması**: en iyi kârın %60'ı geri verilirse çıkış
4. Kilit açılırsa / rejim savunmaya geçerse tüm mikro işlemler kapanır
5. Hedefin yarısından sonra stop **başa-bas + 2 point**'e çekilir

### 4.2 Savunma Kalkanı — Delta-Nötr Kilitleme

**Tetikleyiciler (herhangi biri):**
`STATE_DEFENSE_LOCK` rejimi **veya** `g_risk.LockRequired()`
(DD ≥ `InpDDDefense`, günlük zarar limiti, marjin seviyesi < %250).

**Kilitlenme prosedürü (sırayla):**

1. Tüm bekleyen grid emirleri iptal → **yeni risk sıfır**
2. Tüm açık mikro-scalp pozisyonları kapatılır → kilitte sadece kalkan yaşar
3. Net pozisyon hesaplanır: `net = Σ(side × lot)` (HEDGE rolü hariç)
4. **Sentetik kilit**: `|net| × InpHedgeRatio` hacminde karşı yönde `ROLE_HEDGE` pozisyonu
   → net delta ≈ 0 → **zarar dondurulur** (swap/komisyon/spread dışında)
5. Netting hesaplarda karşıt pozisyon açılamaz → **marjin azaltma** modu devreye girer
   (en kârlı bacaklar kapatılarak marjin rahatlatılır)

**Kilit altında bakım:**

| Olay | Tepki |
|---|---|
| Marjin seviyesi < %350 | En kârlı bacaklardan başlayarak marjin rahatlatma |
| Kalkan zararı > `InpHedgeMaxLossPct` | Kademeli tasfiye (marjin azaltma) |
| DD ≥ `InpDDKill` (BLACK) | **Kontrollü geri çekilme**: tüm emirler iptal + tüm pozisyonlar kapatılır, gün sonuna kadar işlem durur |

**Kilit açma koşulları (hepsi birlikte):**
soğuma barı ✓ · risk kademesi RED altına indi ✓ · rejim artık DEFENSE değil ✓ ·
`atr_z` ≤ genişleme eşiği ✓ · DD `InpUnlockRecovery` puan iyileşti **veya** 3× soğuma süresi doldu.

---

## 5. Kendini Onaran Dinamik Risk — Akıllı Çıkış Matrisi

### 5.1 Çekirdek Pozisyon Çıkışları (ORİJİNAL MANTIK KORUNDU)

Orijinal EA'nın sinyal sayımı birebir korundu:

> **BUY**: TP = girişin **üstünde** gelen N. BUY sinyali · SL = girişin **altında** gelen N. SELL sinyali
> **SELL**: tam tersi · sayım pozisyonun açılış zamanından **sonra** kapanan mumlarla yapılır

Üzerine 4 katman daha eklendi (hepsi birlikte çalışır, biri diğerini iptal etmez):

| # | Mekanizma | Koşul |
|---|---|---|
| 1 | Sinyal sayımı (orijinal) | `InpTPSignalCount` / `InpSLSignalCount` |
| 2 | Sabit TP/SL (broker tarafı) | `InpFixedTPPoints` / `InpFixedSLPoints` |
| 3 | **Dinamik R:R** | kâr ≥ `RR × risk_birimi` → sweep |
| 4 | **Smart Profit Sweep** | `fatigue = 1` (momentum türevi sıfırlandı) ve kâr > 0 → sinyal beklenmez |
| 5 | Rejim evrimi çıkışı | BREAKOUT yönü pozisyonla çelişiyorsa ve güven > 0.35 |

**Dinamik risk-ödül matrisi:**

```
RR = 1.5
   × 1.30   (Hurst trend-kalıcı ise — trendde hedef büyütülür)
   × 0.75   (Hurst anti-kalıcı ise — çabuk al)
   × (0.75 + 0.45 × confidence)
   × 0.60   (VOLATILITY_TRAP)
   × 0.70   (risk kademesi AMBER+)
risk_birimi = ATR × lot × point_value
```

Yani **piyasa ne kadar kalıcı/güvenilir ise hedef o kadar büyür; ne kadar
belirsiz ise o kadar çabuk kâr realize edilir.**

### 5.2 Sermaye Koruma Güvenlik Duvarı (7 Katman)

```
 [1] SEMBOL/OTURUM HİJYENİ   spread ≤ limit · oturum saati · cuma kapanışı
 [2] POZİSYON BOYUTU         risk% × equity / (SL mesafesi × point_value)
                             + mutlak lot tavanı + toplam lot tavanı
                             + SERT TAVAN KURALI: risk modeli lotu yalnızca
                               KÜÇÜLTÜR; çekirdek ≤ 4×taban, grid ≤ 1.6×taban,
                               scalp ≤ (scalp_lot_mult)×taban
 [3] MARJİN TESTİ            OrderCalcMargin → işlem sonrası marjin seviyesi ≥ %400
 [4] REJİM RİSK ÇARPANLARI   tuzak/ısı → seviye sayısı ve lot kırpılır
 [5] DRAWDOWN KADEMELERİ     GREEN → AMBER → RED (kilit) → BLACK (kill-switch)
 [6] DELTA-NÖTR KİLİT        savunma kalkanı (bkz. §4.2)
 [7] KONTROLLÜ GERİ ÇEKİLME  tam tasfiye + gün sonuna kadar duruş
```

**Kademeler:**

| Kademe | DD (%) | Risk çarpanı | Davranış |
|---|---|---|---|
| GREEN | < 4 | 1.00 | Tam kapasite |
| AMBER | ≥ 4 | 0.55 | Seviye sayısı −1, onay sayısı +1, R:R × 0.70 |
| RED | ≥ 7 | 0.20 | **Savunma kilidi** → delta-nötr kalkan, yeni risk yok |
| BLACK | ≥ 12 | 0.00 | **Kill-switch**: tam tasfiye + gün sonuna kadar duruş |

**Kendini onarma (self-healing) mekanizmaları:**

| Mekanizma | Davranış |
|---|---|
| Risk kapasitesi | Hedefe **yavaş** yaklaşır (`InpHealRate`), kısıtlamaya **hızlı** geçer — aşırı tepki yok |
| Toksisite skoru | Ardışık kayıp/hatalarda yükselir, zamanla sönümlenir; onay sayısını ve lotu etkiler |
| Günlük veri | Deal geçmişinden **yeniden okunur** (restart sonrası bile günlük limit bilinir) |
| Yürütme hataları | Requote/off-quotes/timeout → geri çekilmeli 3 deneme; geçersiz lot → bir adım kırp; hata serisi loglanır |
| Defter mutabakatı | Her 20 sn + her trade olayında; etiketsiz pozisyon sahiplenilir, yetim emirler temizlenir |
| Plan sapması | Bekleyen emir plan fiyatından `0.35 × adım` saparsa iptal + yeni fiyattan kurulur |

---

## 6. Kurulum ve Çalıştırma

1. `ApexCombatEngine` klasörünü **olduğu gibi** `MQL5/Experts/` altına kopyalayın.
   Kritik kural: `ApexCombatEngine.mq5` ve 7 adet `.mqh` dosyası **aynı (düz) klasörde**
   durmalıdır.
   > **Neden:** MetaEditor, tırnaklı `#include "..."` yönergesinde **alt klasörlü göreli
   > yolu** (`#include "Include/ApexTypes.mqh"` gibi) güvenilir biçimde çözmez; `Experts\`
   > altında arayıp `file not found` verir. Bu yüzden tüm modüller tek düz klasörde
   > tutulur ve include'lar dosya adıyla yapılır (`#include "ApexTypes.mqh"`).
2. Alternatif yerleşim: `.mq5` dosyasını `MQL5/Experts/` içine, 7 `.mqh` dosyasını
   `MQL5/Include/` içine atabilirsiniz. MQL5 tırnaklı include'da önce kaynak klasöre,
   bulamazsa `MQL5/Include`'a bakar.
3. MetaEditor'da **Derle** (F7). `1 errors, 0 warnings` yerine `0 errors, 0 warnings`
   görmelisiniz.
4. **Hedging** hesaba, grafikte `InpTimeframe` ile aynı sembole ekleyin.
5. İlk çalıştırmada `InpBootBars` (vars. 40 bar) boyunca sistem ısınır, grid/agresif mod kapalıdır.
6. Önce **Strategy Tester**'da (her tick, gerçek tick) en az 6 ay–1 yıl doğrulayın,
   ardından `InpMaxTotalLots`, `InpDDDefense`, `InpGridStepATRMult`, `InpGridBasketATR`
   üzerinden optimizasyon yapın. `OnTester` fitness'ı kârı **DD ve Sharpe'a göre cezalandırır**.

### Önerilen başlangıç profilleri

| Profil | Sembol | TF | Önerilen değişiklikler |
|---|---|---|---|
| Majör FX | EURUSD | M15 | Varsayılanlar; `InpGridMaxLevels=4`, `InpGridBasketATR=1.0` |
| Altın | XAUUSD | M15 | `InpGridStepATRMult=1.0`, `InpMaxSpreadPoints=40`, `InpDDDefense=6` |
| Kripto | BTCUSD | M30 | `InpGridStepATRMult=1.2`, `InpGridMaxLevels=3`, `InpMaxTotalLots=1.0`, `InpUseSession=false` |
| Endeks | US30 | M5 | `InpScalpEnabled=true`, `InpScalpCooldownSec=30`, `InpGridBasketATR=1.5` |

---

## 7. Bilinen Kısıtlar ve Dürüst Uyarılar

1. **MQL5 tek iş parçacıklıdır.** "Multi-thread" talebi zaman dilimli cooperative
   görev mimarisiyle karşılanmıştır (bkz. §1.2). Gerçek paralellik, çoklu grafik
   örnekleriyle sağlanabilir.
2. **Backtest zorunludur.** Bu mimari, stratejik derinlik sağlar; kârlılık garantisi
   vermez. Parametreler sembol/rejime göre optimize edilmelidir.
3. **Hacim verisi:** gerçek hacim sunmayan brokerlarda tick hacmi, o da yoksa eşit
   ağırlık kullanılır → D4 boyutunun keskinliği azalır.
4. **Netting hesaplarda** sentetik kilit (karşıt pozisyon) açılamaz; yerine marjin
   azaltma uygulanır. Grid ve delta-nötr savunma için **hedging hesap şiddetle önerilir**.
5. **Bekleyen emir sayısı ve toplam pozisyon limitleri broker'a göre değişir**;
   `InpGridMaxLegs` ve `InpMaxTotalLots` broker limitlerinin altında tutulmalıdır.
6. Hurst, hacim profili ve momentum türevleri **istatistiksel tahminlerdir**;
   tek başlarına sinyal değil, **rejim oylamasının girdisidir**.

---

## 8. Dosya Haritası

```
ApexCombatEngine/                      <- MQL5/Experts/ altına OLDUĞU GİBİ kopyalanır
├── ApexCombatEngine.mq5              (922)  ana EA + orkestrasyon
├── ApexTypes.mqh                     (527)  katman 0: tipler/yardımcılar
├── ApexTrade.mqh                     (609)  katman 1: yürütme + defter
├── ApexSqueezeCore.mqh               (398)  katman 1: LazyBear çekirdeği
├── ApexAnalytics.mqh                 (716)  katman 2: 5 boyutlu rejim
├── ApexRisk.mqh                      (428)  katman 2: güvenlik duvarı
├── ApexGrid.mqh                      (760)  katman 3: elastik grid
├── ApexScalp.mqh                     (546)  katman 3: scalp + kalkan
└── Docs/
    └── APEX_COMBAT_ENGINE_MIMARI.md  bu doküman
```

> **Tüm dosyalar tek düz klasördedir.** Alt klasörlü göreli include
> (`#include "Include/ApexX.mqh"`) MetaEditor'da `file not found` üretir;
> bu yüzden her include yalnızca dosya adıyla yapılır.

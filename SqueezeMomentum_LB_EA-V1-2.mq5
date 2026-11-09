//+------------------------------------------------------------------+
//|  SqueezeMomentum_LB_EA.mq5                                       |
//|     Squeeze Momentum Indicator [LazyBear] -> MT5 Expert Advisor  |
//|                                                                  |
//|  SİNYAL KURALLARI (sadece KAPANMIŞ mumlar kullanılır):           |
//|   * Renk geçişleri GİRDİLERDEN seçilir (varsayılanlar):          |
//|     - SELL: Açık yeşil (lime) -> Koyu yeşil (green)              |
//|     - BUY : Kırmızı (red)     -> Bordo (maroon)                  |
//|   * BUY ve SELL için önceki/yeni renk AYRI AYRI ayarlanır;       |
//|     "Fark etmez" = herhangi bir renk. Kesişen geçişlerde BUY     |
//|     önceliklidir. Sinyal için gerçek renk değişimi gerekir.      |
//|                                                                  |
//|  ÇIKIŞ KURALLARI (pozisyon yönüne göre sayılır):                 |
//|   * BUY pozisyon : TP = girişten YUKARIDA gelen 3. BUY sinyali   |
//|                    SL = girişten AŞAĞIDA gelen 3. SELL sinyali   |
//|   * SELL pozisyon: TP = girişten AŞAĞIDA gelen 3. SELL sinyali   |
//|                    SL = girişten YUKARIDA gelen 3. BUY sinyali   |
//|     (Sayılar ayarlardan değiştirilebilir. Sayım, pozisyonun      |
//|      açıldığı sinyalden SONRA gelen sinyallerle yapılır.)        |
//|                                                                  |
//|  TERS İŞLEM (InpReverseTrading = true):                          |
//|   * BUY  sinyali -> SELL pozisyon açar                           |
//|   * SELL sinyali -> BUY  pozisyon açar                           |
//|     (Çıkış sayımı yine açılan pozisyonun yönüne göre yapılır.)   |
//|                                                                  |
//|  GÖSTERGE MATEMATİĞİ (LazyBear PineScript koduyla BİREBİR):      |
//|   basis = sma(close, BB Length)                                  |
//|   dev   = KC MultFactor * stdev(close, BB Length)                |
//|           (Pine'da "dev = multKC * stdev(...)" yazıyor;          |
//|            "mult" girdisi orada kullanılmıyor.)                  |
//|   upperBB/lowerBB = basis ± dev                                  |
//|   ma = sma(close, KC Length)                                     |
//|   range = TrueRange ? tr : (high - low)                          |
//|   rangema = sma(range, KC Length)                                |
//|   upperKC/lowerKC = ma ± rangema * KC MultFactor                 |
//|   val = linreg(close - avg(avg(highest(high,KC),                 |
//|               lowest(low,KC)), sma(close,KC)), KC, 0)            |
//|   renk = val>0 ? (val>val[1] ? lime : green)                     |
//|                : (val<val[1] ? red  : maroon)                    |
//|   nz(val[1]): önceki değer yoksa 0 kabul edilir                  |
//|   sqzOn  = lowerBB>lowerKC && upperBB<upperKC                    |
//|   sqzOff = lowerBB<lowerKC && upperBB>upperKC                    |
//|   noSqz  = ikisi de değil                                        |
//|                                                                  |
//|  OTOMATİK SIFIRLAMA:                                             |
//|   * Referans = robotun başladığı andaki bakiye. Anlık varlık     |
//|     (equity) referans + eşik (örn. +3$ kâr) olunca robotun TÜM   |
//|     pozisyonları kapatılır ve YENİ döngü başlar: yeni referans   |
//|     = o anki bakiye, işlemeye devam eder.                        |
//|   * Mod: sadece kâr (+), sadece zarar (-) veya her iki yön (±).  |
//|   * Eşik tutarı ve mod girdilerden değiştirilebilir (0 = kapalı) |
//|                                                                  |
//|  POZİSYON DENGELEME (long/short farkı):                          |
//|   * Long ile short sayısı arasındaki fark en fazla "maksimum     |
//|     fark" (varsayılan 2) olabilir.                               |
//|   * Sinyal geride kalan yöndeyse, farkı kapatacak kadar çok      |
//|     pozisyon açılır (örn. 7 long / 5 short + short sinyali =     |
//|     2 short -> 7 / 7).                                           |
//|   * Sinyal öndeki yöndeyse ve fark zaten limitteyse, fark        |
//|     büyümesin diye YENİ pozisyon açılmaz.                        |
//|   * Kapatılabilir; o zaman her sinyal tek pozisyon açar.         |
//|                                                                  |
//|  HTF TAŞIMA + HASAT (v1.40)                                      |
//|   * Hızlı TF'de (örn. M1) açılan pozisyon, ayarlanan süre veya   |
//|     mum sayısı kadar TP'ye ulaşamazsa "TAŞINAN" (escort) olur.   |
//|     MT5'te bir pozisyonu fiziksel olarak başka grafiğe taşımak   |
//|     mümkün değildir; değişen şey ÇIKIŞ YÖNETİMİDİR: taşınan      |
//|     pozisyonun TP/SL sayımı artık üst zaman diliminin (örn. H1)  |
//|     Squeeze Momentum sinyalleriyle yapılır. Pozisyon ve ticket   |
//|     aynı kalır, yalnızca karar veren seri değişir.               |
//|   * Taşınan pozisyon varken hızlı TF onun TERSİNE "HASAT"        |
//|     işlemleri açar (örn. long H1'de taşınırken short'lar M1'de   |
//|     hızlı kâr toplar). Hasat işlemleri kendi kurallarıyla        |
//|     kapanır (para TP/SL, hızlı sinyal sayımı, süre sınırı) ve    |
//|     toplanan kâr panelde birikir.                                |
//|   * Opsiyonel: biriken hasat kârı eşiği aşınca taşınan           |
//|     pozisyondan kısmi kâr alınır (PositionClosePartial).         |
//|   * Risk filtreleri: taşınan yönde yeni hızlı TF pozisyonu       |
//|     açılmaz, taşımanın maksimum süresi ve para SL'i tanımlı      |
//|     olabilir, hasat pozisyon sayısı sınırlanır.                  |
//|   * Bu motor HEDGING hesap gerektirir (aynı anda ters yönde      |
//|     pozisyon). Netting hesapta pozisyonlar netleşir.             |
//|                                                                  |
//|  SINYAL MOTORU SEÇİMİ (v1.50)                                    |
//|   * InpSignalEngine ile iki motor arasında geçiş yapılır:        |
//|       - Squeeze Momentum (renk geçişleri)  [mevcut davranış]     |
//|       - Donchian Trend Ranges [AlgoAlpha]  [birebir çeviri]      |
//|   * Donchian motorunda giriş / TP / SL sinyalleri AÇILIR         |
//|     MENÜLERDEN seçilir. Örnek: LONG giriş sinyalini              |
//|     "Strong Short TP" yaparsanız, o olay oluştuğunda LONG açılır.|
//|   * Seçilebilen olaylar: Bullish/Bearish Trend Shift, Strong     |
//|     Long TP, Weak Long TP, Strong Short TP, Weak Short TP        |
//|     (+ Squeeze BUY/SELL). Aynı mumda TP ve SL birlikte oluşursa  |
//|     TP öncelikli olur.                                           |
//|   * Donchian matematiği Pine ile birebir: ta.lowest/ta.highest   |
//|     -> basis, fbasis (basis == basis[con] iken güncellenir),     |
//|     dev = mult * stdev(close, length, biased=false),             |
//|     vol = ta.atr(14) (RMA), rangge fbasis değişince güncellenir. |
//|     Pine'daki na davranışı korunur.                              |
//|   * Taşıma (HTF) ve hasat motorları seçilen motorla birlikte     |
//|     çalışır: taşınan pozisyonlar HTF serisinde AYNI seçili       |
//|     olaylarla, hasat pozisyonları kendi sayılarıyla kapatılır.   |
//|                                                                  |
//|  NOT: TP/SL sinyal sayımıyla çalıştığı için bunlar sabit fiyat   |
//|  emri olarak brokera gönderilmez; sayım dolunca EA pozisyonu     |
//|  piyasadan kapatır. Bu yüzden EA'nın açık kalması gerekir.       |
//|  Ek güvenlik için sabit TP/SL (point) de tanımlanabilir.         |
//+------------------------------------------------------------------+
#property copyright "Squeeze Momentum [LazyBear] - MT5 EA"
#property version   "1.50"
#property strict
#property description "Squeeze Momentum [LazyBear] renk geçişi sinyalleriyle işlem açar"
#property description "HTF taşıma: yaşlanan pozisyon üst zaman diliminde (örn. H1) yönetilir"
#property description "Hasat: taşınan pozisyonun tersine hızlı TF kâr toplama"
#property description "Çıkışlar: sinyal sayımı + sabit TP/SL + para bazlı çıkışlar"
#property description "Otomatik sıfırlama ve long/short dengeleme"
#property description "Gösterge matematiği LazyBear PineScript ile birebir"
#property description "Donchian Trend Ranges motoru: giriş/TP/SL sinyalleri menüden seçilir"

#include <Trade/Trade.mqh>

CTrade trade;

//+------------------------------------------------------------------+
//| Tipler                                                           |
//+------------------------------------------------------------------+
enum ENUM_SQZ_BAR_COLOR
  {
   SQZ_COLOR_NONE   = 0, // Hesaplanamadı / veri yetersiz
   SQZ_COLOR_LIME   = 1, // Açık yeşil : val > 0 ve yükseliyor
   SQZ_COLOR_GREEN  = 2, // Koyu yeşil : val > 0 ve düşüyor
   SQZ_COLOR_RED    = 3, // Kırmızı    : val < 0 ve düşüyor
   SQZ_COLOR_MAROON = 4  // Bordo      : val < 0 ve yükseliyor
  };

enum ENUM_SQZ_STATE
  {
   SQZ_STATE_UNKNOWN = 0, // Bilinmiyor (veri yetersiz)
   SQZ_STATE_ON      = 1, // sqzOn  : sıkışma var
   SQZ_STATE_OFF     = 2, // sqzOff : sıkışma çözülmüş
   SQZ_STATE_NONE    = 3  // noSqz  : ikisi de değil
  };

// Sinyal geçişlerinde seçilebilecek mum rengi.
// Değerler ENUM_SQZ_BAR_COLOR ile birebir eşleşir (ANY hariç).
enum ENUM_SQZ_COLOR_CHOICE
  {
   SQZ_CHOICE_ANY    = 0, // Fark etmez (herhangi bir renk)
   SQZ_CHOICE_LIME   = 1, // Açık yeşil (lime)
   SQZ_CHOICE_GREEN  = 2, // Koyu yeşil (green)
   SQZ_CHOICE_RED    = 3, // Kırmızı (red)
   SQZ_CHOICE_MAROON = 4  // Bordo (maroon)
  };

// Otomatik sıfırlama tetikleme modu (referans = başlangıç/son sıfırlama bakiyesi)
enum ENUM_SQZ_RESET_MODE
  {
   SQZ_RESET_PROFIT = 0, // Kâr hedefi: referans +X kâr olunca (+3$)
   SQZ_RESET_LOSS   = 1, // Zarar eşiği: referans -X zarar olunca (-3$)
   SQZ_RESET_BOTH   = 2  // Her iki yön: ±X olunca
  };

// HTF taşıma (escort) kapsamı: hangi yöndeki pozisyonlar taşınır?
enum ENUM_SQZ_ESCORT_MODE
  {
   SQZ_ESCORT_LONG_ONLY  = 0, // Yalnızca LONG pozisyonlar taşınır
   SQZ_ESCORT_SHORT_ONLY = 1, // Yalnızca SHORT pozisyonlar taşınır
   SQZ_ESCORT_BOTH       = 2  // Her iki yön taşınır
  };

// Taşınan pozisyonun HTF sinyal sayımı nereden başlar?
enum ENUM_SQZ_ESCORT_ANCHOR
  {
   SQZ_ESCORT_ANCHOR_SWITCH = 0, // Taşıma anından itibaren say (güvenli)
   SQZ_ESCORT_ANCHOR_ENTRY  = 1  // Pozisyon açılışından itibaren say
  };

// Sinyal motoru: Squeeze Momentum renk geçişleri veya Donchian Trend Ranges
enum ENUM_SQZ_SIGNAL_ENGINE
  {
   ENGINE_SQUEEZE  = 0, // Squeeze Momentum (renk geçişleri)
   ENGINE_DONCHIAN = 1  // Donchian Trend Ranges [AlgoAlpha] (birebir)
  };

// Açılır menülerde seçilebilen olaylar (giriş / TP / SL sinyalleri)
enum ENUM_SQZ_EVENT
  {
   EVENT_NONE             = 0, // (yok / kapalı)
   EVENT_SQZ_BUY          = 1, // Squeeze BUY renk geçişi
   EVENT_SQZ_SELL         = 2, // Squeeze SELL renk geçişi
   EVENT_DON_BULL_SHIFT   = 3, // Bullish Trend Shift (close fbasis'i yukarı keser)
   EVENT_DON_BEAR_SHIFT   = 4, // Bearish Trend Shift (close fbasis'i aşağı keser)
   EVENT_DON_STRONG_LONG  = 5, // Strong Long TP (close uu altına iner)
   EVENT_DON_WEAK_LONG    = 6, // Weak Long TP (close ul altına iner, uu hariç)
   EVENT_DON_STRONG_SHORT = 7, // Strong Short TP (close ll üstüne çıkar)
   EVENT_DON_WEAK_SHORT   = 8  // Weak Short TP (close lu üstüne çıkar, ll hariç)
  };

//+------------------------------------------------------------------+
//| Giriş parametreleri                                              |
//+------------------------------------------------------------------+
input group "1) Squeeze Momentum [LazyBear] ayarları"
input ENUM_TIMEFRAMES InpTimeframe          = PERIOD_CURRENT; // İşlem zaman dilimi (PERIOD_CURRENT = grafik TF)
input int             InpBBLength           = 20;             // BB Length
input double          InpBBMultFactor       = 2.0;            // BB MultFactor (Pine birebir modda kullanılmaz)
input int             InpKCLength           = 20;             // KC Length
input double          InpKCMultFactor       = 1.5;            // KC MultFactor
input bool            InpUseTrueRange       = true;           // Use TrueRange (KC)
input bool            InpPineExactBB        = true;           // PINE BIREBIR: BB sapması = KC MultFactor (LazyBear kodu)
input int             InpHistoryBars        = 5000;           // Taranacak maksimum mum sayısı (sinyal + çıkış sayımı)
input bool            InpLogIndicator       = false;          // Her yeni mumda gösterge değerini logla (TradingView karşılaştırması)

input group "2) Sinyal renk geçişleri (BUY / SELL)"
input ENUM_SQZ_COLOR_CHOICE InpBuyFromColor  = SQZ_CHOICE_RED;   // BUY sinyali: önceki mum rengi
input ENUM_SQZ_COLOR_CHOICE InpBuyToColor    = SQZ_CHOICE_MAROON; // BUY sinyali: yeni mum rengi
input ENUM_SQZ_COLOR_CHOICE InpSellFromColor = SQZ_CHOICE_LIME;  // SELL sinyali: önceki mum rengi
input ENUM_SQZ_COLOR_CHOICE InpSellToColor   = SQZ_CHOICE_GREEN; // SELL sinyali: yeni mum rengi

input group "3) Sinyal ve ters işlem"
input bool            InpReverseTrading     = false; // TERS İŞLEM: true = BUY sinyali SELL, SELL sinyali BUY açar
input bool            InpOpenOnBuySignal    = true;  // BUY sinyalinde işlem aç
input bool            InpOpenOnSellSignal   = true;  // SELL sinyalinde işlem aç
input bool            InpAllowLongTrades    = true;  // BUY pozisyon açmaya izin ver
input bool            InpAllowShortTrades   = true;  // SELL pozisyon açmaya izin ver
input bool            InpDrawSignalArrows   = true;  // Grafikte sinyal okları çiz
input bool            InpShowChartInfo      = true;  // Grafikte bilgi paneli göster

input group "4) Çıkışlar - sinyal sayımı (0 = o çıkış kapalı)"
input int             InpTakeProfitSignalCount = 3;  // TP: girişle aynı yöndeki kaçıncı sinyalde kapat?
input int             InpStopLossSignalCount   = 3;  // SL: girişle ters yöndeki kaçıncı sinyalde kapat?
input int             InpFixedTakeProfitPoints = 0;  // Ekstra sabit TP (point) - 0 = kapalı
input int             InpFixedStopLossPoints   = 0;  // Ekstra sabit SL (point) - 0 = kapalı

input group "5) Pozisyon ve emir"
input double          InpLotSize              = 0.01;      // Lot
input ulong           InpMagicNumber          = 20261019;  // Magic Number
input int             InpDeviationPoints      = 20;        // Maksimum sapma (point)
input int             InpMaxSpreadPoints      = 0;         // Maksimum spread (point) - 0 = kapalı
input int             InpMaxOpenPositions     = 0;         // Aynı anda maks. pozisyon - 0 = sınırsız
input bool            InpRequireHedgingAccount = true;     // Hedging hesap zorunlu olsun mu?
input bool            InpDeleteArrowsOnExit   = true;      // EA kapanırken sinyal oklarını sil

input group "6) Otomatik sıfırlama (kâr hedefinde kapat, yeni döngü başlat)"
input bool                InpAutoResetEnabled = true;              // Otomatik sıfırlama açık
input ENUM_SQZ_RESET_MODE InpAutoResetMode    = SQZ_RESET_PROFIT; // Sıfırlama modu (referans = başlangıç bakiyesi)
input double              InpAutoResetLevel   = 3.0;              // Eşik tutarı (hesap para birimi, örn. 3 = 3$) - 0 = kapalı

input group "7) Pozisyon dengeleme (long/short farkı)"
input bool            InpBalanceEnabled  = true;                 // Dengeleme açık (kapalıysa her sinyal 1 pozisyon)
input int             InpBalanceMaxGap   = 2;                    // İki yöndeki maksimum pozisyon farkı (min 1)
input int             InpBalanceMaxBatch = 0;                    // Tek sinyalde en fazla kaç telafi pozisyonu - 0 = sınırsız

input group "8) HTF TAŞIMA - yaşlanan pozisyonu üst zaman diliminde yönet"
input bool                   InpEscortEnabled       = true;              // Taşıma motoru açık
input ENUM_SQZ_ESCORT_MODE   InpEscortMode          = SQZ_ESCORT_LONG_ONLY; // Hangi yöndeki pozisyonlar taşınır
input ENUM_TIMEFRAMES        InpEscortTimeframe     = PERIOD_H1;         // Taşıma zaman dilimi (işlem TF'sinden büyük olmalı)
input int                    InpEscortAfterMinutes  = 60;                // Açılıştan kaç dakika sonra taşınır (0 = hemen)
input int                    InpEscortAfterBars     = 0;                 // ... veya işlem TF'sinde kaç mum sonra (0 = kapalı)
input bool                   InpEscortOnlyIfProfit  = false;             // Yalnızca kârdaki pozisyonlar taşınsın
input ENUM_SQZ_ESCORT_ANCHOR InpEscortAnchor        = SQZ_ESCORT_ANCHOR_SWITCH; // HTF sayımı nereden başlasın
input int                    InpEscortTpSignalCount = 2;                 // Taşınan: TP için uygun HTF sinyal sayısı (0 = kapalı)
input int                    InpEscortSlSignalCount = 2;                 // Taşınan: SL için ters HTF sinyal sayısı (0 = kapalı)
input int                    InpEscortFixedTpPoints = 0;                 // Taşınan: sabit TP (point, 0 = kapalı)
input int                    InpEscortFixedSlPoints = 0;                 // Taşınan: sabit SL (point, 0 = kapalı)
input bool                   InpEscortClearOldExits = true;              // Taşımada eski sabit TP/SL seviyelerini temizle
input int                    InpEscortMaxRideHours  = 24;                // Taşıma üst süre sınırı (saat, 0 = kapalı)
input double                 InpEscortStopLossMoney = 0.0;               // Taşınan pozisyon para SL (hesap birimi, 0 = kapalı)
input bool                   InpEscortBlockSameSide = true;              // Taşınan yönde yeni hızlı TF pozisyonu açma

input group "9) HASAT - taşınan pozisyonun tersine hızlı TF kâr toplama"
input bool   InpHarvestEnabled              = true;   // Hasat motoru açık
input double InpHarvestLot                  = 0.0;    // Hasat lotu (0 = normal lot)
input int    InpHarvestMaxPositions         = 4;      // Aynı anda en fazla hasat pozisyonu (0 = sınırsız)
input double InpHarvestTakeProfitMoney      = 1.0;    // Hasat para TP (hesap birimi, 0 = kapalı)
input double InpHarvestStopLossMoney        = 2.0;    // Hasat para SL (hesap birimi, 0 = kapalı)
input int    InpHarvestTpSignalCount        = 1;      // Hasat TP: uygun hızlı TF sinyal sayısı (0 = kapalı)
input int    InpHarvestSlSignalCount        = 2;      // Hasat SL: ters hızlı TF sinyal sayısı (0 = kapalı)
input int    InpHarvestMaxLifeMinutes       = 0;      // Hasat üst süre sınırı (dakika, 0 = kapalı)
input bool   InpHarvestTrimEnabled          = false;  // Biriken hasat kârıyla taşınan pozisyondan kısmi kâr al
input double InpHarvestTrimProfit           = 5.0;    // Kısmi kâr için birikmesi gereken hasat kârı
input double InpHarvestTrimPercent          = 50.0;   // Her tetikte kapatılacak hacim (%)
input bool   InpHarvestTrimOnlyIfRideProfit = true;   // Kısmi kâr yalnızca taşınan pozisyon kârdayken

input group "10) Donchian Trend Ranges [AlgoAlpha] - birebir Pine çevirisi"
input ENUM_SQZ_SIGNAL_ENGINE InpSignalEngine  = ENGINE_SQUEEZE; // Sinyal motoru (Squeeze / Donchian)
input int    InpDonLength    = 50;   // Length (ta.lowest / ta.highest penceresi)
input double InpDonMult      = 3.0;  // Range Multiplier
input int    InpDonCon       = 1;    // con (Pine sabiti: basis == basis[con])
input int    InpDonAtrLength = 14;   // vol = ta.atr(length)
input ENUM_SQZ_EVENT InpDonLongEntry  = EVENT_DON_STRONG_SHORT; // LONG giriş sinyali (menüden seç)
input ENUM_SQZ_EVENT InpDonShortEntry = EVENT_DON_STRONG_LONG;  // SHORT giriş sinyali (menüden seç)
input ENUM_SQZ_EVENT InpDonLongTp     = EVENT_DON_STRONG_LONG;  // LONG TP sinyali (menüden seç)
input ENUM_SQZ_EVENT InpDonLongSl     = EVENT_DON_BEAR_SHIFT;   // LONG SL sinyali (menüden seç)
input ENUM_SQZ_EVENT InpDonShortTp    = EVENT_DON_STRONG_SHORT; // SHORT TP sinyali (menüden seç)
input ENUM_SQZ_EVENT InpDonShortSl    = EVENT_DON_BULL_SHIFT;   // SHORT SL sinyali (menüden seç)
input int    InpDonTpSignalCount = 1;      // TP için gereken sinyal sayısı (0 = kapalı)
input int    InpDonSlSignalCount = 1;      // SL için gereken sinyal sayısı (0 = kapalı)
input bool   InpDonTpOnlyInProfit = false; // TP sinyali yalnızca pozisyon kârdayken uygulanır
input bool   InpDonSlOnlyInLoss   = false; // SL sinyali yalnızca pozisyon zarardayken uygulanır

//+------------------------------------------------------------------+
//| Global durum                                                     |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES g_timeframe           = PERIOD_CURRENT;
datetime        g_last_bar_time       = 0;
int             g_last_raw_signal     = 0;      // +1 BUY sinyali, -1 SELL sinyali
datetime        g_last_signal_time    = 0;
double          g_last_signal_price   = 0.0;
double          g_last_momentum       = 0.0;
ENUM_SQZ_BAR_COLOR g_last_bar_color   = SQZ_COLOR_NONE;
ENUM_SQZ_BAR_COLOR g_prev_bar_color   = SQZ_COLOR_NONE;
ENUM_SQZ_STATE     g_last_sqz_state   = SQZ_STATE_UNKNOWN;
string          g_last_action         = "Başlatılıyor";
string          g_object_prefix       = "";
double          g_reset_start_balance = 0.0; // Referans bakiye (robot başlangıcı / son sıfırlama)
bool            g_reset_hold          = false; // Sıfırlama işlemi sürüyor (tekrar tetikleme koruması)
int             g_reset_count         = 0;     // Toplam otomatik sıfırlama sayısı
int             g_balance_fill_count  = 0;     // Dengeleme ile açılan ek pozisyon sayısı
int             g_balance_skip_count  = 0;     // Fark limiti nedeniyle atlanan sinyal sayısı
datetime        g_reset_last_try      = 0;     // Son kapatma denemesi (tekrar log/emir spam'i önlenir)

// --- HTF taşıma (escort) durumu ---
ENUM_TIMEFRAMES    g_escort_tf        = PERIOD_H1; // Çözümlenmiş taşıma zaman dilimi
datetime           g_escort_last_bar  = 0;         // Önbellekteki son HTF mumu
MqlRates           g_escort_rates[];               // HTF mum serisi (0 = en eski)
double             g_escort_values[];              // HTF momentum değerleri
ENUM_SQZ_BAR_COLOR g_escort_colors[];              // HTF mum renkleri
bool               g_escort_valid[];               // HTF geçerlilik
bool               g_escort_ready     = false;     // HTF serisi hazır mı?
datetime           g_escort_exit_check = 0;        // Son HTF sinyal taraması
ulong              g_escort_applied[];             // Emir seviyeleri güncellenmiş taşınan pozisyonlar
int                g_escort_count     = 0;         // Panel: taşınan pozisyon sayısı

// --- Hasat durumu ---
ulong  g_harvest_watch[];           // Kapanışı izlenen hasat pozisyon ticket'ları
double g_harvest_pocket       = 0.0; // Toplam gerçekleşen hasat sonucu
double g_harvest_credit       = 0.0; // Kısmi kâr için kullanılabilir birikim
int    g_harvest_opened       = 0;   // Açılan hasat pozisyonu sayısı
int    g_harvest_closed       = 0;   // Kapanan hasat pozisyonu sayısı
double g_harvest_trimmed_lot  = 0.0; // Kısmi kârla kapatılan toplam hacim

// --- Donchian Trend Ranges durumu ---
int    g_escort_events[];            // HTF mumları için olay bayrakları
double g_don_fbasis = 0.0;           // Panel: son kapalı mumun fbasis değeri
double g_don_uu     = 0.0;           // Panel: uu (upper + vol)
double g_don_ll     = 0.0;           // Panel: ll (lower - vol)
bool   g_don_ready  = false;         // Panel: Donchian seviyeleri hazır mı?
int    g_don_last_events = 0;        // Panel: son kapalı mumdaki olay bayrakları

//+------------------------------------------------------------------+
//| Yardımcılar                                                      |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES WorkingTimeframe()
  {
   if(InpTimeframe == PERIOD_CURRENT)
      return (ENUM_TIMEFRAMES)Period();
   return InpTimeframe;
  }

double TickSize()
  {
   double size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(size <= 0.0)
      size = _Point;
   return size;
  }

double NormalizePriceToTick(const double price, const int round_direction)
  {
   // round_direction: +1 yukarı, -1 aşağı, 0 en yakına yuvarla
   double tick = TickSize();
   if(price <= 0.0 || tick <= 0.0)
      return NormalizeDouble(price, _Digits);
   double units = price / tick;
   if(round_direction > 0)
      units = MathCeil(units - 1.0e-10);
   else if(round_direction < 0)
      units = MathFloor(units + 1.0e-10);
   else
      units = MathRound(units);
   return NormalizeDouble(units * tick, _Digits);
  }

double NormalizeVolume(const double requested)
  {
   double min_volume  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_volume  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double volume_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(min_volume <= 0.0 || volume_step <= 0.0)
      return 0.0;

   double volume = requested;
   if(max_volume > 0.0 && volume > max_volume)
      volume = max_volume;
   volume = MathFloor(volume / volume_step + 1.0e-10) * volume_step;
   volume = NormalizeDouble(volume, 8);
   if(volume < min_volume - 1.0e-10)
     {
      PrintFormat("Lot atlandı: istenen %.8f broker minimumu %.8f altında.", requested, min_volume);
      return 0.0;
     }
   return volume;
  }

bool TradeRetcodeOK(const bool call_ok)
  {
   if(!call_ok)
      return false;
   uint code = trade.ResultRetcode();
   return (code == TRADE_RETCODE_DONE ||
           code == TRADE_RETCODE_DONE_PARTIAL ||
           code == TRADE_RETCODE_PLACED ||
           code == TRADE_RETCODE_NO_CHANGES);
  }

int SideFromPositionType(const long type)
  {
   if(type == POSITION_TYPE_BUY)
      return 1;
   if(type == POSITION_TYPE_SELL)
      return -1;
   return 0;
  }

string SideName(const int side)
  {
   if(side > 0)
      return "BUY";
   if(side < 0)
      return "SELL";
   return "YOK";
  }

string ColorName(const ENUM_SQZ_BAR_COLOR clr)
  {
   switch(clr)
     {
      case SQZ_COLOR_LIME:   return "Açık yeşil (lime)";
      case SQZ_COLOR_GREEN:  return "Koyu yeşil (green)";
      case SQZ_COLOR_RED:    return "Kırmızı (red)";
      case SQZ_COLOR_MAROON: return "Bordo (maroon)";
      default:               return "hesaplanamadı";
     }
  }

string ColorChoiceName(const ENUM_SQZ_COLOR_CHOICE choice)
  {
   switch(choice)
     {
      case SQZ_CHOICE_ANY:    return "fark etmez";
      case SQZ_CHOICE_LIME:   return "açık yeşil";
      case SQZ_CHOICE_GREEN:  return "koyu yeşil";
      case SQZ_CHOICE_RED:    return "kırmızı";
      case SQZ_CHOICE_MAROON: return "bordo";
      default:                return "?";
     }
  }

string TransitionText(const ENUM_SQZ_COLOR_CHOICE from_choice,
                      const ENUM_SQZ_COLOR_CHOICE to_choice)
  {
   return ColorChoiceName(from_choice) + " -> " + ColorChoiceName(to_choice);
  }

// Seçim (fark etmez = herhangi bir renk) ile mum rengini karşılaştırır.
// NOT: İki farklı enum karşılaştırılamaz; bu yüzden (int) ile kıyaslanır.
bool ColorMatchesChoice(const ENUM_SQZ_BAR_COLOR bar_clr,
                        const ENUM_SQZ_COLOR_CHOICE choice)
  {
   if(bar_clr == SQZ_COLOR_NONE)
      return false;
   if(choice == SQZ_CHOICE_ANY)
      return true;
   return ((int)bar_clr == (int)choice);
  }

string SignalName(const int signal)
  {
   if(signal > 0)
      return StringFormat("BUY sinyali (%s)", TransitionText(InpBuyFromColor, InpBuyToColor));
   if(signal < 0)
      return StringFormat("SELL sinyali (%s)", TransitionText(InpSellFromColor, InpSellToColor));
   return "sinyal yok";
  }

string SqueezeStateName(const ENUM_SQZ_STATE state)
  {
   switch(state)
     {
      case SQZ_STATE_ON:   return "sqzOn (sıkışma var)";
      case SQZ_STATE_OFF:  return "sqzOff (sıkışma yok)";
      case SQZ_STATE_NONE: return "noSqz";
      default:             return "bilinmiyor";
     }
  }

//+------------------------------------------------------------------+
//| Squeeze Momentum hesaplamaları                                   |
//|                                                                  |
//| PineScript karşılığı:                                            |
//|  val = linreg(close - avg(avg(highest(high,KC),lowest(low,KC)),  |
//|                             sma(close,KC)), KC, 0)               |
//+------------------------------------------------------------------+
double LinearRegressionEnd(const double &series[], const int end_index, const int period)
  {
   int start = end_index - period + 1;
   if(start < 0 || period < 2)
      return 0.0;

   double sum_x  = period * (period - 1) / 2.0;
   double sum_x2 = (period - 1) * period * (2 * period - 1) / 6.0;
   double sum_y  = 0.0;
   double sum_xy = 0.0;
   for(int k = 0; k < period; k++)
     {
      double y = series[start + k];
      sum_y  += y;
      sum_xy += k * y;
     }

   double denominator = period * sum_x2 - sum_x * sum_x;
   if(MathAbs(denominator) < 1.0e-12)
      return sum_y / period;

   double slope     = (period * sum_xy - sum_x * sum_y) / denominator;
   double intercept = (sum_y - slope * sum_x) / period;
   // linreg(..., offset=0): doğrunun en son mumdaki değeri
   return intercept + slope * (period - 1);
  }

ENUM_SQZ_BAR_COLOR BarColor(const double value, const double previous_value)
  {
   // PineScript:
   //   bcolor = iff(val > 0, iff(val > nz(val[1]), lime, green),
   //                         iff(val < nz(val[1]), red,  maroon))
   if(value > 0.0)
      return (value > previous_value) ? SQZ_COLOR_LIME : SQZ_COLOR_GREEN;
   return (value < previous_value) ? SQZ_COLOR_RED : SQZ_COLOR_MAROON;
  }

// Mum serisi için momentum değerlerini ve çubuk renklerini hesaplar.
// rates kronolojik sıradadır (0 = en eski). Son index oluşan mumdur.
bool ComputeMomentum(const MqlRates &rates[],
                     double &values[],
                     ENUM_SQZ_BAR_COLOR &colors[],
                     bool &valid[])
  {
   int total = ArraySize(rates);
   if(total <= 0)
      return false;
   if(ArrayResize(values, total) < total ||
      ArrayResize(colors, total) < total ||
      ArrayResize(valid,  total) < total)
      return false;

   ArrayInitialize(values, 0.0);
   for(int i = 0; i < total; i++)
     {
      colors[i] = SQZ_COLOR_NONE;
      valid[i]  = false;
     }

   // 1) x = close - avg(avg(highest(high,KC), lowest(low,KC)), sma(close,KC))
   double detrend[];
   bool   detrend_valid[];
   if(ArrayResize(detrend, total) < total || ArrayResize(detrend_valid, total) < total)
      return false;
   ArrayInitialize(detrend, 0.0);
   for(int i = 0; i < total; i++)
      detrend_valid[i] = false;

   for(int i = InpKCLength - 1; i < total; i++)
     {
      double highest = rates[i].high;
      double lowest  = rates[i].low;
      double sum_close = 0.0;
      for(int j = i - InpKCLength + 1; j <= i; j++)
        {
         highest    = MathMax(highest, rates[j].high);
         lowest     = MathMin(lowest,  rates[j].low);
         sum_close += rates[j].close;
        }
      double sma_close = sum_close / InpKCLength;
      double hl_mid    = (highest + lowest) * 0.5;   // avg(highest, lowest)
      double mid       = (hl_mid + sma_close) * 0.5; // avg(avg(...), sma)
      detrend[i]       = rates[i].close - mid;
      detrend_valid[i] = true;
     }

   // 2) val = linreg(x, KC, 0)
   for(int i = 2 * InpKCLength - 2; i < total; i++)
     {
      bool ready = true;
      for(int j = i - InpKCLength + 1; j <= i; j++)
        {
         if(!detrend_valid[j])
           {
            ready = false;
            break;
           }
        }
      if(!ready)
         continue;
      values[i] = LinearRegressionEnd(detrend, i, InpKCLength);
      valid[i]  = true;
     }

   // 3) Çubuk renkleri (önceki mum yoksa nz(val[1]) = 0 kabul edilir)
   for(int i = 0; i < total; i++)
     {
      if(!valid[i])
         continue;
      double previous_value = (i > 0 && valid[i - 1]) ? values[i - 1] : 0.0;
      colors[i] = BarColor(values[i], previous_value);
     }
   return true;
  }

// İki komşu mum rengine bakarak sinyal üretir.
// Geçiş renkleri girdilerden seçilir (InpBuyFromColor -> InpBuyToColor,
// InpSellFromColor -> InpSellToColor). "Fark etmez" herhangi bir rengi
// temsil eder. Gerçek bir RENK DEĞİŞİMİ olmadan sinyal üretilmez.
// Kesişen geçişlerde BUY sinyali önceliklidir.
//   +1 = BUY sinyali, -1 = SELL sinyali, 0 = sinyal yok
int SignalFromTransition(const ENUM_SQZ_BAR_COLOR previous_color,
                         const ENUM_SQZ_BAR_COLOR current_color)
  {
   // Geçiş olması için iki mumun rengi farklı olmalı
   if(previous_color == SQZ_COLOR_NONE || current_color == SQZ_COLOR_NONE ||
      previous_color == current_color)
      return 0;

   // BUY sinyali: seçilen önceki renk -> seçilen yeni renk
   if(ColorMatchesChoice(previous_color, InpBuyFromColor) &&
      ColorMatchesChoice(current_color,  InpBuyToColor))
      return 1;

   // SELL sinyali: seçilen önceki renk -> seçilen yeni renk
   if(ColorMatchesChoice(previous_color, InpSellFromColor) &&
      ColorMatchesChoice(current_color,  InpSellToColor))
      return -1;

   return 0;
  }

// BB/KC sıkışma durumu (sqzOn/sqzOff/noSqz). Sinyal şartı DEĞİLDİR;
// sadece bilgi panelinde gösterilir (Pine'daki 0 çizgisi noktaları).
ENUM_SQZ_STATE ComputeSqueezeState(const MqlRates &rates[], const int index)
  {
   int needed = (int)MathMax(InpBBLength, InpKCLength);
   if(index < needed - 1)
      return SQZ_STATE_UNKNOWN;

   // Bollinger: basis = sma(close, BB), dev = <çarpan> * stdev(close, BB)
   // Pine kodu (LazyBear) BB sapmasında multKC kullanır:
   //     dev = multKC * stdev(source, length)
   // Bu yüzden varsayılan olarak KC MultFactor kullanılır (birebir).
   // "mult" (BB MultFactor) girdisi orijinal Pine kodunda hiç kullanılmaz.
   // InpPineExactBB=false yapılırsa klasik Bollinger davranışı (BB MultFactor) uygulanır.
   double basis = 0.0;
   for(int j = index - InpBBLength + 1; j <= index; j++)
      basis += rates[j].close;
   basis /= InpBBLength;

   double variance = 0.0;
   for(int j = index - InpBBLength + 1; j <= index; j++)
     {
      double diff = rates[j].close - basis;
      variance += diff * diff;
     }
   double dev_mult = (InpPineExactBB ? InpKCMultFactor : InpBBMultFactor);
   double dev = dev_mult * MathSqrt(variance / InpBBLength);
   double upper_bb = basis + dev;
   double lower_bb = basis - dev;

   // Keltner: ma = sma(close, KC), rangema = sma(range, KC)
   double ma = 0.0;
   double range_sum = 0.0;
   for(int j = index - InpKCLength + 1; j <= index; j++)
     {
      ma += rates[j].close;
      double range = rates[j].high - rates[j].low;
      if(InpUseTrueRange && j > 0)
        {
         double prev_close = rates[j - 1].close;
         range = MathMax(range, MathMax(MathAbs(rates[j].high - prev_close),
                                        MathAbs(rates[j].low  - prev_close)));
        }
      range_sum += range;
     }
   ma /= InpKCLength;
   double range_ma = range_sum / InpKCLength;
   double upper_kc = ma + range_ma * InpKCMultFactor;
   double lower_kc = ma - range_ma * InpKCMultFactor;

   bool sqz_on  = (lower_bb > lower_kc) && (upper_bb < upper_kc);
   bool sqz_off = (lower_bb < lower_kc) && (upper_bb > upper_kc);
   if(sqz_on)
      return SQZ_STATE_ON;
   if(sqz_off)
      return SQZ_STATE_OFF;
   return SQZ_STATE_NONE;
  }

// Belirtilen zaman dilimi için mum serisini yükler (0 = en eski mum).
int LoadRatesFor(const ENUM_TIMEFRAMES tf, MqlRates &rates[])
  {
   int needed = (int)MathMax(InpHistoryBars, (InpKCLength * 4) + 10);
   ArraySetAsSeries(rates, false); // 0 = en eski mum
   int copied = CopyRates(_Symbol, tf, 0, needed, rates);
   if(copied > 0)
      ArrayResize(rates, copied);
   return copied;
  }

int LoadRates(MqlRates &rates[])
  {
   return LoadRatesFor(g_timeframe, rates);
  }

//+------------------------------------------------------------------+
//| Pozisyon yardımcıları                                            |
//+------------------------------------------------------------------+
bool SelectOurPosition(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket))
      return false;
   if(PositionGetString(POSITION_SYMBOL) != _Symbol)
      return false;
   if((ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
      return false;
   return true;
  }

int CountOurPositions(const int side_filter = 0)
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      int side = SideFromPositionType(PositionGetInteger(POSITION_TYPE));
      if(side_filter == 0 || side == side_filter)
         count++;
     }
   return count;
  }

bool CloseOurPosition(const ulong ticket, const string reason)
  {
   if(!SelectOurPosition(ticket))
      return true; // Zaten kapanmis
   int side = SideFromPositionType(PositionGetInteger(POSITION_TYPE));
   bool sent = trade.PositionClose(ticket, InpDeviationPoints);
   if(!TradeRetcodeOK(sent))
     {
      PrintFormat("Kapatma başarısız ticket=%I64u neden=%s retcode=%u (%s)",
                  ticket, reason, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      return false;
     }
   if(PositionSelectByTicket(ticket))
     {
      PrintFormat("Pozisyon tamamen kapanmadı ticket=%I64u kalan hacim=%.8f",
                  ticket, PositionGetDouble(POSITION_VOLUME));
      return false;
     }
   PrintFormat("Pozisyon kapandı: ticket=%I64u side=%s neden=%s", ticket, SideName(side), reason);
   g_last_action = StringFormat("%s pozisyon kapatıldı (%s)", SideName(side), reason);
   return true;
  }

//+------------------------------------------------------------------+
//| Otomatik sıfırlama (kâr / zarar hedefi)                          |
//|                                                                  |
//| Referans = robotun başladığı andaki (veya son sıfırlamadaki)     |
//| bakiye. Varlık (equity) referanstan InpAutoResetLevel kadar      |
//| uzaklaşınca robotun TÜM pozisyonları kapatılır ve YENİ döngü     |
//| başlar: referans o anki bakiyeye çekilir, işlemeye devam eder.   |
//| Eşik tutarı ve mod girdilerden seçilir (0 = kapalı).             |
//+------------------------------------------------------------------+
string ResetModeName(const ENUM_SQZ_RESET_MODE mode)
  {
   if(mode == SQZ_RESET_LOSS)
      return "zarar eşiği";
   if(mode == SQZ_RESET_BOTH)
      return "her iki yön";
   return "kâr hedefi";
  }

double ResetDifference(const double equity)
  {
   return (equity - g_reset_start_balance);
  }

// Pozisyon yokken referans: bakiye ile varlığın büyüğü alınır.
// (Kapatma sonrası bakiyenin bir tick gecikmesi hatalı ikinci sıfırlamayı tetiklemesin.)
double FlatReferenceBalance()
  {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   return (equity > balance ? equity : balance);
  }

// Eşik koşulu sağlanmış mı? (equity = anlık varlık)
bool ResetCondition(const double equity)
  {
   double diff = ResetDifference(equity);
   if(InpAutoResetMode == SQZ_RESET_LOSS)
      return (diff <= -InpAutoResetLevel);
   if(InpAutoResetMode == SQZ_RESET_BOTH)
      return (MathAbs(diff) >= InpAutoResetLevel);
   return (diff >= InpAutoResetLevel); // SQZ_RESET_PROFIT
  }

void CloseAllOurPositions(const string reason)
  {
   ulong tickets[];
   ArrayResize(tickets, 0);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      int n = ArraySize(tickets);
      if(ArrayResize(tickets, n + 1) >= n + 1)
         tickets[n] = ticket;
     }
   for(int i = 0; i < ArraySize(tickets); i++)
      CloseOurPosition(tickets[i], reason);
  }

// Her tick/timer'da çağrılır.
void CheckAutoReset()
  {
   if(!InpAutoResetEnabled || InpAutoResetLevel <= 0.0)
      return;

   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   int    open_count = CountOurPositions(0);

   // Pozisyon yokken kapatılacak bir şey yoktur; referans bakiyeyi takip eder.
   // (Sıfırlama sonrası yeni döngü referansı da burada tazelenir.)
   if(open_count == 0 && !g_reset_hold)
     {
      g_reset_start_balance = FlatReferenceBalance();
      return;
     }

   if(!ResetCondition(equity))
     {
      if(g_reset_hold)
        {
         g_reset_hold = false;
         if(open_count == 0)
            g_reset_start_balance = FlatReferenceBalance();
         PrintFormat("Otomatik sıfırlama: hedef aralığa dönüldü, işlemeye devam. Varlık=%.2f", equity);
        }
      return;
     }

   // Aynı sıfırlama için yalnızca bir kez sayaç/log üret.
   if(!g_reset_hold)
     {
      g_reset_hold = true;
      g_reset_count++;
      PrintFormat("OTOMATİK SIFIRLAMA #%d: %s | eşik=%.2f referans=%.2f varlık=%.2f fark=%+.2f",
                  g_reset_count, ResetModeName(InpAutoResetMode),
                  InpAutoResetLevel, g_reset_start_balance, equity,
                  ResetDifference(equity));
      g_last_action = "Otomatik sıfırlama: hedef tutuldu, pozisyonlar kapatılıyor";
     }

   // Kapanmayan pozisyon varsa saniyede bir kez tekrar denenir.
   datetime now = TimeCurrent();
   if(g_reset_hold && g_reset_last_try > 0 && (now - g_reset_last_try) < 2)
      return;
   g_reset_last_try = now;

   CloseAllOurPositions("otomatik sıfırlama");
   int after_count = CountOurPositions(0);

   if(after_count == 0)
     {
      // Yeni döngü: referans = kapatma sonrası bakiye, işlemeye hemen devam.
      g_reset_start_balance = FlatReferenceBalance();
      g_reset_hold = false;
      g_last_action = StringFormat("Otomatik sıfırlama #%d tamamlandı: yeni döngü başladı (referans %.2f)",
                                   g_reset_count, g_reset_start_balance);
      PrintFormat("Otomatik sıfırlama tamam: tüm pozisyonlar kapandı. Yeni referans=%.2f (işlemeye devam)",
                  g_reset_start_balance);
     }
   else
     {
      // Kısmi kapanış: sonraki tick'te kalanlar tekrar denenir (sayaç artmaz).
      g_last_action = StringFormat("Otomatik sıfırlama: %d pozisyon kapatılamadı, tekrar denenecek", after_count);
      PrintFormat("Otomatik sıfırlama: %d pozisyon kapatılamadı, tekrar denenecek", after_count);
     }
  }

//+------------------------------------------------------------------+
//| Pozisyon dengeleme (long/short farkı)                            |
//|                                                                  |
//| Bu sinyalde kaç pozisyon açılacağını döndürür:                   |
//|  0            -> sinyal atlanır (fark büyümesin)                |
//|  1            -> normal tek pozisyon                            |
//|  >1           -> geride kalan yönü telafi eden ek pozisyonlar   |
//+------------------------------------------------------------------+
int PositionsToOpen(const int trade_side, string &note)
  {
   note = "";
   if(!InpBalanceEnabled || InpBalanceMaxGap <= 0 || trade_side == 0)
      return 1;

   int longs  = CountOurPositions(1);
   int shorts = CountOurPositions(-1);
   int gap    = longs - shorts;
   if(gap < 0)
      gap = -gap;
   note = StringFormat("%d long / %d short (fark %d)", longs, shorts, gap);

   int own = (trade_side > 0 ? longs : shorts);
   int other = (trade_side > 0 ? shorts : longs);

   int count = 1;
   if(own < other)
     {
      // Geride kalan yön: farkı kapatacak kadar aç (örn. 7L/5S + SELL = 2 SELL).
      count = (gap > 1 ? gap : 1);
     }
   else if(gap + 1 > InpBalanceMaxGap)
     {
      // Öndeki yön ve fark limitte: fark büyümesin diye açma.
      note = StringFormat("%s (fark limiti %d)", note, InpBalanceMaxGap);
      return 0;
     }

   if(InpBalanceMaxBatch > 0 && count > InpBalanceMaxBatch)
      count = InpBalanceMaxBatch;

   // Aynı anda açılabilecek pozisyon sınırına saygı göster.
   if(InpMaxOpenPositions > 0)
     {
      int room = InpMaxOpenPositions - CountOurPositions(0);
      if(room <= 0)
        {
         note = StringFormat("%s, maksimum pozisyon sınırı %d", note, InpMaxOpenPositions);
         return 0;
        }
      if(count > room)
         count = room;
     }
   return count;
  }

//+------------------------------------------------------------------+
//| Sinyal sayımına dayalı çıkış kontrolü (GENEL MOTOR)              |
//|                                                                  |
//| Bu motor üç farklı yerde kullanılır:                             |
//|   1) Hızlı TF: normal pozisyonlar  (sayım = pozisyon açılışı)    |
//|   2) Hızlı TF: hasat pozisyonları  (kendi TP/SL sayılarıyla)     |
//|   3) HTF     : taşınan pozisyonlar (sayım = taşıma anı)          |
//|                                                                  |
//| count_from zamanından SONRA kapanan mumların sinyalleri          |
//| kronolojik sırayla taranır. Pozisyon yönüyle aynı yönlü ve giriş |
//| fiyatını geçen sinyaller TP sayacını, ters yönlü ve giriş        |
//| fiyatını geçen sinyaller SL sayacını artırır. Sayacı önce        |
//| dolduran çıkış gerçekleşir. Sayım geçmiş mumlardan yeniden       |
//| hesaplanabildiği için EA yeniden başlatılsa da bozulmaz.         |
//+------------------------------------------------------------------+
int EvaluateExitSeries(const ulong ticket,
                       const MqlRates &rates[],
                       const ENUM_SQZ_BAR_COLOR &colors[],
                       const bool &valid[],
                       const ENUM_TIMEFRAMES series_tf,
                       const datetime count_from,
                       const int tp_needed,
                       const int sl_needed,
                       string &reason,
                       int &tp_count_out,
                       int &sl_count_out)
  {
   reason       = "";
   tp_count_out = 0;
   sl_count_out = 0;
   if(tp_needed <= 0 && sl_needed <= 0)
      return 0;
   if(!SelectOurPosition(ticket))
      return 0;

   int      side       = SideFromPositionType(PositionGetInteger(POSITION_TYPE));
   double   entry      = PositionGetDouble(POSITION_PRICE_OPEN);
   if(side == 0 || entry <= 0.0)
      return 0;

   int last_closed = ArraySize(rates) - 2; // Son index oluşan mumdur
   if(last_closed < 1)
      return 0;
   int period_seconds = PeriodSeconds(series_tf);
   if(period_seconds <= 0)
      period_seconds = 60;

   for(int i = 1; i <= last_closed; i++)
     {
      if(!valid[i] || !valid[i - 1])
         continue;
      int signal = SignalFromTransition(colors[i - 1], colors[i]);
      if(signal == 0)
         continue;

      // Sinyal, mum kapandığında oluşur. Sayımın başladığı anı (açılış veya
      // taşıma anı) geçmeyen sinyaller sayılmaz.
      datetime signal_close_time = rates[i].time + period_seconds;
      if(signal_close_time <= count_from)
         continue;

      double signal_price = rates[i].close;
      bool is_tp_signal = false;
      bool is_sl_signal = false;
      if(side > 0) // BUY pozisyon
        {
         is_tp_signal = (signal > 0 && signal_price > entry); // Yukarıda BUY sinyali
         is_sl_signal = (signal < 0 && signal_price < entry); // Aşağıda SELL sinyali
        }
      else         // SELL pozisyon
        {
         is_tp_signal = (signal < 0 && signal_price < entry); // Aşağıda SELL sinyali
         is_sl_signal = (signal > 0 && signal_price > entry); // Yukarıda BUY sinyali
        }

      if(is_tp_signal)
        {
         tp_count_out++;
         if(tp_needed > 0 && tp_count_out >= tp_needed)
           {
            reason = StringFormat("TP (sinyal sayımı, %s): %d. uygun %s sinyali, giriş=%.*f sinyal fiyatı=%.*f",
                                  EnumToString(series_tf), tp_count_out, SideName(signal),
                                  _Digits, entry, _Digits, signal_price);
            return 1;
           }
        }
      if(is_sl_signal)
        {
         sl_count_out++;
         if(sl_needed > 0 && sl_count_out >= sl_needed)
           {
            reason = StringFormat("SL (sinyal sayımı, %s): %d. uygun %s sinyali, giriş=%.*f sinyal fiyatı=%.*f",
                                  EnumToString(series_tf), sl_count_out, SideName(signal),
                                  _Digits, entry, _Digits, signal_price);
            return -1;
           }
        }
     }
   return 0;
  }

//+------------------------------------------------------------------+
//| Hızlı TF çıkışları (normal + hasat pozisyonları)                 |
//|                                                                  |
//| Taşınan (HTF) pozisyonlar burada ATLANIR; onların çıkışları      |
//| ProcessEscortPositions() içinde üst zaman dilimi serisiyle       |
//| yönetilir. Hasat pozisyonları ise kendi (daha hızlı) TP/SL       |
//| sayılarıyla kapatılır.                                           |
//+------------------------------------------------------------------+
void ManageSignalExits(const MqlRates &rates[],
                       const ENUM_SQZ_BAR_COLOR &colors[],
                       const bool &valid[])
  {
   if(InpTakeProfitSignalCount <= 0 && InpStopLossSignalCount <= 0 &&
      InpHarvestTpSignalCount <= 0 && InpHarvestSlSignalCount <= 0)
      return;

   ulong tickets[];
   ArrayResize(tickets, 0);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      int n = ArraySize(tickets);
      if(ArrayResize(tickets, n + 1) >= n + 1)
         tickets[n] = ticket;
     }

   for(int i = 0; i < ArraySize(tickets); i++)
     {
      ulong ticket = tickets[i];
      if(!SelectOurPosition(ticket))
         continue;
      if(IsEscorted(ticket))
         continue; // Taşınan pozisyon artık hızlı TF sinyalleriyle kapatılmaz

      bool harvest   = IsHarvestPosition(ticket);
      int  tp_needed = (harvest ? InpHarvestTpSignalCount : InpTakeProfitSignalCount);
      int  sl_needed = (harvest ? InpHarvestSlSignalCount : InpStopLossSignalCount);
      if(tp_needed <= 0 && sl_needed <= 0)
         continue;

      datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
      string reason = "";
      int tp_count = 0;
      int sl_count = 0;
      int result = EvaluateExitSeries(ticket, rates, colors, valid, g_timeframe,
                                      open_time, tp_needed, sl_needed,
                                      reason, tp_count, sl_count);
      if(result != 0)
         CloseOurPosition(ticket, reason);
     }
  }

//+------------------------------------------------------------------+
//| Olay (sinyal) yardımcıları                                       |
//|                                                                  |
//| Her mum için bir "olay bayrağı" (bit maskesi) hesaplanır. Böylece |
//| giriş / TP / SL sinyalleri menüden seçilen olaylarla aynı motor   |
//| üzerinden yönetilir; Squeeze ve Donchian olayları aynı yapıdadır. |
//+------------------------------------------------------------------+
int EventBit(const ENUM_SQZ_EVENT ev)
  {
   if(ev == EVENT_NONE)
      return 0;
   return (1 << ((int)ev - 1));
  }

bool HasEvent(const int flags, const ENUM_SQZ_EVENT ev)
  {
   if(ev == EVENT_NONE)
      return false;
   return ((flags & EventBit(ev)) != 0);
  }

bool IsSqueezeEvent(const ENUM_SQZ_EVENT ev)
  {
   return (ev == EVENT_SQZ_BUY || ev == EVENT_SQZ_SELL);
  }

bool IsDonchianEvent(const ENUM_SQZ_EVENT ev)
  {
   return (ev >= EVENT_DON_BULL_SHIFT && ev <= EVENT_DON_WEAK_SHORT);
  }

string EventName(const ENUM_SQZ_EVENT ev)
  {
   switch(ev)
     {
      case EVENT_SQZ_BUY:          return "Squeeze BUY";
      case EVENT_SQZ_SELL:         return "Squeeze SELL";
      case EVENT_DON_BULL_SHIFT:   return "Bullish Trend Shift";
      case EVENT_DON_BEAR_SHIFT:   return "Bearish Trend Shift";
      case EVENT_DON_STRONG_LONG:  return "Strong Long TP";
      case EVENT_DON_WEAK_LONG:    return "Weak Long TP";
      case EVENT_DON_STRONG_SHORT: return "Strong Short TP";
      case EVENT_DON_WEAK_SHORT:   return "Weak Short TP";
      default:                     return "yok";
     }
  }

string EngineName(const ENUM_SQZ_SIGNAL_ENGINE engine)
  {
   if(engine == ENGINE_DONCHIAN)
      return "Donchian Trend Ranges";
   return "Squeeze Momentum";
  }

string EventFlagsText(const int flags)
  {
   string text = "";
   if(HasEvent(flags, EVENT_DON_BULL_SHIFT))   text += "BullShift ";
   if(HasEvent(flags, EVENT_DON_BEAR_SHIFT))   text += "BearShift ";
   if(HasEvent(flags, EVENT_DON_STRONG_LONG))  text += "StrongLongTP ";
   if(HasEvent(flags, EVENT_DON_WEAK_LONG))    text += "WeakLongTP ";
   if(HasEvent(flags, EVENT_DON_STRONG_SHORT)) text += "StrongShortTP ";
   if(HasEvent(flags, EVENT_DON_WEAK_SHORT))   text += "WeakShortTP ";
   if(text == "")
      text = "yok";
   return text;
  }

//+------------------------------------------------------------------+
//| Donchian Trend Ranges [AlgoAlpha] - Pine koduyla BIREBIR          |
//|                                                                  |
//|  l        = ta.lowest(length)                                    |
//|  u        = ta.highest(length)                                   |
//|  basis    = math.avg(u, l)                                        |
//|  fbasis  := basis == basis[con] ? basis : fbasis[1]              |
//|  dev      = ta.stdev(close, length, false) * mult   (n-1 bölme)  |
//|  vol      = ta.atr(14)                              (RMA)        |
//|  rangge  := fbasis != fbasis[1] ? dev : rangge[1]                |
//|  upper = fbasis + rangge , lower = fbasis - rangge               |
//|  uu = upper + vol , ul = upper - vol , lu = lower + vol ,        |
//|  ll = lower - vol                                                |
//|                                                                  |
//|  Sinyaller (Pine plotchar / alertcondition ile aynı):            |
//|   Strong Long TP  = crossunder(close, uu)                        |
//|   Strong Short TP = crossover(close, ll)                         |
//|   Weak Long TP    = crossunder(close, ul) and not ...(uu)        |
//|   Weak Short TP   = crossover(close, lu)  and not ...(ll)        |
//|   Bullish Shift   = crossover(close, fbasis)                     |
//|   Bearish Shift   = crossunder(close, fbasis)                    |
//|                                                                  |
//|  na davranışı Pine ile aynıdır: na içeren karşılaştırma "false"  |
//|  kabul edilir, bu yüzden seviyeler ancak yeterli veri birikince   |
//|  (ve fbasis/rangge sabitlenince) geçerli olur.                    |
//+------------------------------------------------------------------+
bool ComputeDonchianEvents(const MqlRates &rates[],
                           int &events[],
                           double &last_fbasis,
                           double &last_uu,
                           double &last_ll,
                           bool &last_ok)
  {
   last_fbasis = 0.0;
   last_uu     = 0.0;
   last_ll     = 0.0;
   last_ok     = false;

   int total = ArraySize(rates);
   if(total < 3)
      return false;
   if(ArrayResize(events, total) < total)
      return false;
   for(int i = 0; i < total; i++)
      events[i] = 0;

   int length  = (int)MathMax(InpDonLength, 2);
   int atr_len = (int)MathMax(InpDonAtrLength, 1);
   int con     = (int)MathMax(InpDonCon, 0);
   if(con > total - 2)
      con = total - 2;

   double basis[], dev[], tr[], vol[];
   double fbasis[], rangge[], uu[], ul[], lu[], ll[];
   bool basis_ok[], dev_ok[], vol_ok[], fbasis_ok[], rangge_ok[], level_ok[];

   if(ArrayResize(basis, total) < total || ArrayResize(basis_ok, total) < total ||
      ArrayResize(dev, total) < total   || ArrayResize(dev_ok, total) < total ||
      ArrayResize(tr, total) < total    || ArrayResize(vol, total) < total ||
      ArrayResize(vol_ok, total) < total ||
      ArrayResize(fbasis, total) < total || ArrayResize(fbasis_ok, total) < total ||
      ArrayResize(rangge, total) < total || ArrayResize(rangge_ok, total) < total ||
      ArrayResize(uu, total) < total || ArrayResize(ul, total) < total ||
      ArrayResize(lu, total) < total || ArrayResize(ll, total) < total ||
      ArrayResize(level_ok, total) < total)
      return false;

   for(int i = 0; i < total; i++)
     {
      basis[i] = 0.0;      basis_ok[i]   = false;
      dev[i] = 0.0;        dev_ok[i]     = false;
      tr[i] = 0.0;
      vol[i] = 0.0;        vol_ok[i]     = false;
      fbasis[i] = 0.0;     fbasis_ok[i]  = false;
      rangge[i] = 0.0;     rangge_ok[i]  = false;
      uu[i] = 0.0; ul[i] = 0.0; lu[i] = 0.0; ll[i] = 0.0;
      level_ok[i] = false;
     }

   // 1) basis = avg(highest(high, length), lowest(low, length))
   for(int i = length - 1; i < total; i++)
     {
      double hi = rates[i].high;
      double lo = rates[i].low;
      for(int j = i - length + 1; j <= i; j++)
        {
         hi = MathMax(hi, rates[j].high);
         lo = MathMin(lo, rates[j].low);
        }
      basis[i]    = (hi + lo) * 0.5;
      basis_ok[i] = true;
     }

   // 2) dev = mult * ta.stdev(close, length, biased=false)  -> n-1
   for(int i = length - 1; i < total; i++)
     {
      double sum = 0.0;
      for(int j = i - length + 1; j <= i; j++)
         sum += rates[j].close;
      double mean = sum / length;
      double var  = 0.0;
      for(int j = i - length + 1; j <= i; j++)
        {
         double d = rates[j].close - mean;
         var += d * d;
        }
      var /= (double)(length - 1);
      dev[i]    = InpDonMult * MathSqrt(var);
      dev_ok[i] = true;
     }

   // 3) vol = ta.atr(atr_len) -> RMA(tr, atr_len); ilk değer SMA
   for(int i = 0; i < total; i++)
     {
      double tr_value = rates[i].high - rates[i].low;
      if(i > 0)
        {
         double prev_close = rates[i - 1].close;
         tr_value = MathMax(tr_value, MathMax(MathAbs(rates[i].high - prev_close),
                                              MathAbs(rates[i].low  - prev_close)));
        }
      tr[i] = tr_value;
     }
   for(int i = 0; i < total; i++)
     {
      if(i == atr_len - 1)
        {
         double sum = 0.0;
         for(int j = 0; j < atr_len; j++)
            sum += tr[j];
         vol[i]    = sum / atr_len;
         vol_ok[i] = true;
        }
      else
         if(i >= atr_len && vol_ok[i - 1])
           {
            vol[i]    = (vol[i - 1] * (atr_len - 1) + tr[i]) / atr_len;
            vol_ok[i] = true;
           }
     }

   // 4) fbasis (yapışkan) ve rangge (yapışkan) - Pine ile birebir
   double fb_value = 0.0;
   bool   fb_valid = false;
   double rg_value = 0.0;
   bool   rg_valid = false;
   for(int i = 0; i < total; i++)
     {
      // fbasis := basis == basis[con] ? basis : fbasis[1]
      if(basis_ok[i] && i - con >= 0 && basis_ok[i - con])
        {
         if(basis[i] == basis[i - con]) // Pine: tam eşitlik
           {
            fb_value = basis[i];
            fb_valid = true;
           }
        }
      fbasis[i]    = fb_valid ? fb_value : 0.0;
      fbasis_ok[i] = fb_valid;

      // rangge := fbasis != fbasis[1] ? dev : rangge[1]
      if(i > 0 && fbasis_ok[i] && fbasis_ok[i - 1] && dev_ok[i] &&
         fbasis[i] != fbasis[i - 1])
        {
         rg_value = dev[i];
         rg_valid = true;
        }
      rangge[i]    = rg_valid ? rg_value : 0.0;
      rangge_ok[i] = rg_valid;
     }

   // 5) Seviyeler
   for(int i = 0; i < total; i++)
     {
      if(!fbasis_ok[i] || !rangge_ok[i] || !vol_ok[i])
         continue;
      double upper = fbasis[i] + rangge[i];
      double lower = fbasis[i] - rangge[i];
      uu[i] = upper + vol[i];
      ul[i] = upper - vol[i];
      lu[i] = lower + vol[i];
      ll[i] = lower - vol[i];
      level_ok[i] = true;
     }

   // 6) Olaylar (crossover / crossunder)
   for(int i = 1; i < total; i++)
     {
      if(!level_ok[i] || !level_ok[i - 1])
         continue;

      double close_now  = rates[i].close;
      double close_prev = rates[i - 1].close;

      bool cross_under_uu = (close_now <  uu[i] && close_prev >= uu[i - 1]);
      bool cross_over_ll  = (close_now >  ll[i] && close_prev <= ll[i - 1]);
      bool cross_under_ul = (close_now <  ul[i] && close_prev >= ul[i - 1]);
      bool cross_over_lu  = (close_now >  lu[i] && close_prev <= lu[i - 1]);
      bool cross_over_fb  = (close_now > fbasis[i] && close_prev <= fbasis[i - 1]);
      bool cross_under_fb = (close_now < fbasis[i] && close_prev >= fbasis[i - 1]);

      int flags = 0;
      if(cross_under_fb)
         flags |= EventBit(EVENT_DON_BEAR_SHIFT);
      if(cross_over_fb)
         flags |= EventBit(EVENT_DON_BULL_SHIFT);
      if(cross_under_uu)
         flags |= EventBit(EVENT_DON_STRONG_LONG);
      if(cross_over_ll)
         flags |= EventBit(EVENT_DON_STRONG_SHORT);
      if(cross_under_ul && !cross_under_uu)
         flags |= EventBit(EVENT_DON_WEAK_LONG);
      if(cross_over_lu && !cross_over_ll)
         flags |= EventBit(EVENT_DON_WEAK_SHORT);

      events[i] = flags;
     }

   // Panel için son KAPANMIŞ mumun seviyeleri (index total-2)
   int panel_index = total - 2;
   if(panel_index >= 0 && level_ok[panel_index])
     {
      last_fbasis = fbasis[panel_index];
      last_uu     = uu[panel_index];
      last_ll     = ll[panel_index];
      last_ok     = true;
     }
   return true;
  }

// Squeeze renk geçişlerini de aynı olay maskesine çevirir (panel / ortak kullanım).
void SqueezeEventsFromColors(const ENUM_SQZ_BAR_COLOR &colors[], int &events[])
  {
   int total = ArraySize(colors);
   if(ArrayResize(events, total) < total)
      return;
   for(int i = 0; i < total; i++)
      events[i] = 0;
   for(int i = 1; i < total; i++)
     {
      int signal = SignalFromTransition(colors[i - 1], colors[i]);
      if(signal > 0)
         events[i] = EventBit(EVENT_SQZ_BUY);
      else
         if(signal < 0)
            events[i] = EventBit(EVENT_SQZ_SELL);
     }
  }

//+------------------------------------------------------------------+
//| Seçilen olaylara göre TP / SL sayımı                             |
//|                                                                  |
//| count_from'dan sonra kapanan mumlarda tp_event kaç kez            |
//| gerçekleştiyse TP, sl_event kaç kez gerçekleştiyse SL sayılır.    |
//| Aynı mumda iki olay varsa TP önceliklidir.                        |
//+------------------------------------------------------------------+
int EvaluateEventExit(const ulong ticket,
                      const MqlRates &rates[],
                      const int &events[],
                      const ENUM_TIMEFRAMES series_tf,
                      const datetime count_from,
                      const ENUM_SQZ_EVENT tp_event,
                      const ENUM_SQZ_EVENT sl_event,
                      const int tp_needed,
                      const int sl_needed,
                      const bool tp_only_in_profit,
                      const bool sl_only_in_loss,
                      string &reason,
                      int &tp_count_out,
                      int &sl_count_out)
  {
   reason       = "";
   tp_count_out = 0;
   sl_count_out = 0;
   if(tp_needed <= 0 && sl_needed <= 0)
      return 0;
   if(!SelectOurPosition(ticket))
      return 0;

   int side = SideFromPositionType(PositionGetInteger(POSITION_TYPE));
   if(side == 0)
      return 0;
   double profit_now = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

   int total       = ArraySize(rates);
   int event_total = ArraySize(events);
   int last_closed = total - 2; // Son index oluşan (canlı) mumdur
   if(last_closed < 1)
      return 0;
   if(event_total < total)
      last_closed = event_total - 2;

   int period_seconds = PeriodSeconds(series_tf);
   if(period_seconds <= 0)
      period_seconds = 60;

   for(int i = 1; i <= last_closed; i++)
     {
      datetime signal_close_time = rates[i].time + period_seconds;
      if(signal_close_time <= count_from)
         continue;

      if(tp_event != EVENT_NONE && HasEvent(events[i], tp_event))
        {
         tp_count_out++;
         if(tp_needed > 0 && tp_count_out >= tp_needed)
           {
            if(!tp_only_in_profit || profit_now >= 0.0)
              {
               reason = StringFormat("TP (olay sinyali, %s): %d. %s | %s",
                                     EnumToString(series_tf), tp_count_out,
                                     EventName(tp_event), TimeToString(rates[i].time));
               return 1;
              }
           }
        }

      if(sl_event != EVENT_NONE && HasEvent(events[i], sl_event))
        {
         sl_count_out++;
         if(sl_needed > 0 && sl_count_out >= sl_needed)
           {
            if(!sl_only_in_loss || profit_now < 0.0)
              {
               reason = StringFormat("SL (olay sinyali, %s): %d. %s | %s",
                                     EnumToString(series_tf), sl_count_out,
                                     EventName(sl_event), TimeToString(rates[i].time));
               return -1;
              }
           }
        }
     }
   return 0;
  }

//+------------------------------------------------------------------+
//| HTF taşıma (escort) + hasat yardımcıları                         |
//+------------------------------------------------------------------+
bool ListHas(const ulong &list[], const ulong ticket)
  {
   for(int i = 0; i < ArraySize(list); i++)
      if(list[i] == ticket)
         return true;
   return false;
  }

void ListAdd(ulong &list[], const ulong ticket)
  {
   if(ListHas(list, ticket))
      return;
   int n = ArraySize(list);
   if(ArrayResize(list, n + 1) == n + 1)
      list[n] = ticket;
  }

void ListRemove(ulong &list[], const ulong ticket)
  {
   int n = ArraySize(list);
   for(int i = n - 1; i >= 0; i--)
     {
      if(list[i] != ticket)
         continue;
      for(int j = i; j < n - 1; j++)
         list[j] = list[j + 1];
      ArrayResize(list, n - 1);
      return;
     }
  }

string PriceText(const double price)
  {
   if(price <= 0.0)
      return "yok";
   return DoubleToString(price, _Digits);
  }

string EscortModeName(const ENUM_SQZ_ESCORT_MODE mode)
  {
   if(mode == SQZ_ESCORT_LONG_ONLY)
      return "yalnızca LONG";
   if(mode == SQZ_ESCORT_SHORT_ONLY)
      return "yalnızca SHORT";
   return "her iki yön";
  }

bool EscortSideEnabled(const int side)
  {
   if(side == 0)
      return false;
   if(InpEscortMode == SQZ_ESCORT_LONG_ONLY)
      return (side > 0);
   if(InpEscortMode == SQZ_ESCORT_SHORT_ONLY)
      return (side < 0);
   return true;
  }

// Taşıma eşiği (saniye). Dakika ve mum tetiklerinden ÖNCE dolan geçerlidir.
// 0 = pozisyon açıldığı anda taşınır.
int EscortThresholdSeconds()
  {
   int work_seconds = PeriodSeconds(g_timeframe);
   if(work_seconds <= 0)
      work_seconds = 60;

   int by_minutes = 0;
   if(InpEscortAfterMinutes > 0)
      by_minutes = InpEscortAfterMinutes * 60;
   int by_bars = 0;
   if(InpEscortAfterBars > 0)
      by_bars = InpEscortAfterBars * work_seconds;

   if(by_minutes <= 0)
      return (by_bars > 0 ? by_bars : 0);
   if(by_bars > 0 && by_bars < by_minutes)
      return by_bars;
   return by_minutes;
  }

string EscortThresholdText()
  {
   int seconds = EscortThresholdSeconds();
   if(seconds <= 0)
      return "hemen";
   if(seconds % 3600 == 0)
      return StringFormat("%d saat", seconds / 3600);
   if(seconds % 60 == 0)
      return StringFormat("%d dakika", seconds / 60);
   return StringFormat("%d saniye", seconds);
  }

// Pozisyonun taşınmaya başladığı an (açılış + eşik).
datetime EscalationTime(const datetime open_time)
  {
   return (datetime)((long)open_time + (long)EscortThresholdSeconds());
  }

// Taşınan pozisyonun HTF sinyal sayımı hangi andan başlar?
datetime EscortCountFrom(const datetime open_time)
  {
   if(InpEscortAnchor == SQZ_ESCORT_ANCHOR_ENTRY)
      return open_time;
   return EscalationTime(open_time);
  }

bool IsHarvestPosition(const ulong ticket)
  {
   if(!SelectOurPosition(ticket))
      return false;
   if(ListHas(g_harvest_watch, ticket))
      return true;
   string comment = PositionGetString(POSITION_COMMENT);
   return (StringFind(comment, "HARV") >= 0);
  }

// Pozisyon taşınmış mı? (kapsam uygun + eşik doldu + hasat değil)
bool IsEscorted(const ulong ticket)
  {
   if(!InpEscortEnabled)
      return false;
   if(!SelectOurPosition(ticket))
      return false;
   if(IsHarvestPosition(ticket))
      return false;

   int side = SideFromPositionType(PositionGetInteger(POSITION_TYPE));
   if(!EscortSideEnabled(side))
      return false;

   datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
   if(TimeCurrent() < EscalationTime(open_time))
      return false;

   if(InpEscortOnlyIfProfit)
     {
      double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      if(profit < 0.0)
         return false;
     }
   return true;
  }

int CountEscortedPositions(const int side_filter = 0)
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsEscorted(ticket))
         continue;
      int side = SideFromPositionType(PositionGetInteger(POSITION_TYPE));
      if(side_filter == 0 || side == side_filter)
         count++;
     }
   return count;
  }

int CountHarvestPositions(const int side_filter = 0)
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsHarvestPosition(ticket))
         continue;
      int side = SideFromPositionType(PositionGetInteger(POSITION_TYPE));
      if(side_filter == 0 || side == side_filter)
         count++;
     }
   return count;
  }

// Verilen fiyattan sabit TP/SL seviyelerini hesaplar (0 = o seviye kapalı).
void BuildFixedPrices(const int side, const double entry,
                      const int tp_points, const int sl_points,
                      double &sl, double &tp)
  {
   sl = 0.0;
   tp = 0.0;
   if(side == 0 || entry <= 0.0)
      return;

   long stops_level  = (long)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze_level = (long)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double min_distance = MathMax((double)stops_level, (double)freeze_level) * _Point;

   if(tp_points > 0)
     {
      double distance = MathMax(tp_points * _Point, min_distance + TickSize());
      tp = NormalizePriceToTick(entry + side * distance, (side > 0 ? 1 : -1));
     }
   if(sl_points > 0)
     {
      double distance = MathMax(sl_points * _Point, min_distance + TickSize());
      sl = NormalizePriceToTick(entry - side * distance, (side > 0 ? -1 : 1));
     }
  }

// Taşınan pozisyonun emir seviyelerini (SL/TP) yalnızca BİR KEZ günceller.
// Dönen değer: 1 = tamam / yapılacak bir şey yok, -1 = başarısız (yeniden denenecek)
int ApplyEscortExits(const ulong ticket)
  {
   if(ListHas(g_escort_applied, ticket))
      return 1;
   if(!SelectOurPosition(ticket))
      return 1;

   int    side   = SideFromPositionType(PositionGetInteger(POSITION_TYPE));
   double entry  = PositionGetDouble(POSITION_PRICE_OPEN);
   double cur_sl = PositionGetDouble(POSITION_SL);
   double cur_tp = PositionGetDouble(POSITION_TP);

   double new_sl = 0.0;
   double new_tp = 0.0;
   BuildFixedPrices(side, entry, InpEscortFixedTpPoints, InpEscortFixedSlPoints, new_sl, new_tp);

   // Sabit seviye tanımlı değilse: eski seviyeler korunur ya da temizlenir.
   if(InpEscortFixedSlPoints <= 0 && !InpEscortClearOldExits)
      new_sl = cur_sl;
   if(InpEscortFixedTpPoints <= 0 && !InpEscortClearOldExits)
      new_tp = cur_tp;

   // Seviyeler güncel piyasaya göre geçerli aralıkta mı? Değilse içeri çekilir.
   MqlTick tick;
   if(SymbolInfoTick(_Symbol, tick) && tick.bid > 0.0 && tick.ask > 0.0)
     {
      long stops_level = (long)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      double min_distance = MathMax((double)stops_level, 1.0) * _Point + TickSize();
      if(side > 0)
        {
         if(new_sl > 0.0 && new_sl > tick.bid - min_distance)
            new_sl = NormalizePriceToTick(tick.bid - min_distance, -1);
         if(new_tp > 0.0 && new_tp < tick.ask + min_distance)
            new_tp = NormalizePriceToTick(tick.ask + min_distance, 1);
        }
      else
        {
         if(new_sl > 0.0 && new_sl < tick.ask + min_distance)
            new_sl = NormalizePriceToTick(tick.ask + min_distance, 1);
         if(new_tp > 0.0 && new_tp > tick.bid - min_distance)
            new_tp = NormalizePriceToTick(tick.bid - min_distance, -1);
        }
     }

   double tick_size = TickSize();
   bool sl_same = (MathAbs(new_sl - cur_sl) < tick_size * 0.5);
   bool tp_same = (MathAbs(new_tp - cur_tp) < tick_size * 0.5);
   if(sl_same && tp_same)
     {
      ListAdd(g_escort_applied, ticket);
      return 1;
     }

   bool sent = trade.PositionModify(ticket, new_sl, new_tp);
   if(!TradeRetcodeOK(sent))
     {
      PrintFormat("Taşıma: emir seviyeleri güncellenemedi ticket=%I64u retcode=%u (%s). Yeniden denenecek.",
                  ticket, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      return -1;
     }
   ListAdd(g_escort_applied, ticket);
   PrintFormat("Taşıma: ticket=%I64u yeni seviyeler SL=%s TP=%s | taşıma TF=%s",
               ticket, PriceText(new_sl), PriceText(new_tp), EnumToString(g_escort_tf));
   g_last_action = StringFormat("Pozisyon %s taşındı: SL=%s TP=%s",
                                IntegerToString((long)ticket),
                                PriceText(new_sl), PriceText(new_tp));
   return 1;
  }

// HTF (taşıma) zaman diliminin Squeeze Momentum serisini hazırlar.
// Seri yalnızca yeni HTF mumu oluştuğunda yeniden hesaplanır.
bool EnsureEscortData()
  {
   if(!InpEscortEnabled)
      return false;

   datetime bar_time = iTime(_Symbol, g_escort_tf, 0);
   if(bar_time <= 0)
     {
      g_escort_ready = false;
      return false;
     }
   bool need_events = (InpSignalEngine == ENGINE_DONCHIAN);
   if(g_escort_ready && bar_time == g_escort_last_bar &&
      ArraySize(g_escort_colors) > 0 &&
      (!need_events || ArraySize(g_escort_events) > 0))
      return true;

   int copied = LoadRatesFor(g_escort_tf, g_escort_rates);
   int min_bars = (int)MathMax((2 * InpKCLength) + 5, InpBBLength + 5);
   if(need_events)
     {
      int don_bars = (int)MathMax(InpDonLength + (int)MathMax(InpDonCon, 0) + 5,
                                  InpDonAtrLength + 5);
      min_bars = (int)MathMax(min_bars, don_bars);
     }
   if(copied < min_bars)
     {
      g_escort_ready = false;
      return false;
     }

   bool momentum_ok = ComputeMomentum(g_escort_rates, g_escort_values,
                                      g_escort_colors, g_escort_valid);
   if(need_events)
     {
      double fb = 0.0;
      double uu = 0.0;
      double ll = 0.0;
      bool   ok = false;
      if(!ComputeDonchianEvents(g_escort_rates, g_escort_events, fb, uu, ll, ok))
        {
         g_escort_ready = false;
         return false;
        }
      // Squeeze olayları da HTF maskesine eklenir (karışık seçim desteği).
      if(momentum_ok)
        {
         int sqz_flags[];
         SqueezeEventsFromColors(g_escort_colors, sqz_flags);
         int sqz_total = ArraySize(sqz_flags);
         for(int i = 0; i < ArraySize(g_escort_events) && i < sqz_total; i++)
            g_escort_events[i] |= sqz_flags[i];
        }
     }
   else
     {
      if(!momentum_ok)
        {
         g_escort_ready = false;
         return false;
        }
     }

   g_escort_last_bar = bar_time;
   g_escort_ready    = true;
   return true;
  }

// Taşınan pozisyon için HTF sinyal sayımı.
int EvaluateEscortExit(const ulong ticket, string &reason, int &tp_count_out, int &sl_count_out)
  {
   reason       = "";
   tp_count_out = 0;
   sl_count_out = 0;
   if(!g_escort_ready)
      return 0;
   if(!SelectOurPosition(ticket))
      return 0;

   int side = SideFromPositionType(PositionGetInteger(POSITION_TYPE));
   if(side == 0)
      return 0;
   datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);

   // Donchian motoru: seçilen olaylar HTF serisinde sayılır.
   if(InpSignalEngine == ENGINE_DONCHIAN)
     {
      ENUM_SQZ_EVENT tp_event = (side > 0 ? InpDonLongTp : InpDonShortTp);
      ENUM_SQZ_EVENT sl_event = (side > 0 ? InpDonLongSl : InpDonShortSl);
      return EvaluateEventExit(ticket, g_escort_rates, g_escort_events, g_escort_tf,
                               EscortCountFrom(open_time), tp_event, sl_event,
                               InpEscortTpSignalCount, InpEscortSlSignalCount,
                               false, false, reason, tp_count_out, sl_count_out);
     }

   if(InpEscortTpSignalCount <= 0 && InpEscortSlSignalCount <= 0)
      return 0;
   return EvaluateExitSeries(ticket, g_escort_rates, g_escort_colors, g_escort_valid,
                             g_escort_tf, EscortCountFrom(open_time),
                             InpEscortTpSignalCount, InpEscortSlSignalCount,
                             reason, tp_count_out, sl_count_out);
  }

// Taşınan pozisyonları yönetir: seviye güncellemesi + HTF sinyal çıkışları.
void ProcessEscortPositions()
  {
   if(!InpEscortEnabled)
      return;

   // Kapanmış ticket'ları listeden temizle (liste sınırsız büyümesin).
   for(int i = ArraySize(g_escort_applied) - 1; i >= 0; i--)
     {
      ulong applied = g_escort_applied[i];
      if(!PositionSelectByTicket(applied))
         ListRemove(g_escort_applied, applied);
     }

   int escorted = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsEscorted(ticket))
         continue;
      escorted++;
      ApplyEscortExits(ticket);
     }
   g_escort_count = escorted;
   if(escorted <= 0)
      return;

   // HTF sinyal taraması en fazla 10 saniyede bir yapılır (HTF mumu
   // değişmediği sürece sonuç aynı kalır, işlemci boşa yorulmaz).
   datetime now = TimeCurrent();
   if(g_escort_exit_check > 0 && (now - g_escort_exit_check) < 10)
      return;
   g_escort_exit_check = now;

   if(!EnsureEscortData())
      return;

   ulong tickets[];
   ArrayResize(tickets, 0);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsEscorted(ticket))
         continue;
      int n = ArraySize(tickets);
      if(ArrayResize(tickets, n + 1) == n + 1)
         tickets[n] = ticket;
     }

   for(int i = 0; i < ArraySize(tickets); i++)
     {
      string reason = "";
      int tp_count = 0;
      int sl_count = 0;
      int result = EvaluateEscortExit(tickets[i], reason, tp_count, sl_count);
      if(result != 0)
         CloseOurPosition(tickets[i], reason);
     }
  }

// Para birimi bazlı çıkışlar ve süre sınırları (her tick/timer).
void CheckPositionMoneyExits()
  {
   if(CountOurPositions(0) <= 0)
      return;

   ulong tickets[];
   ArrayResize(tickets, 0);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      int n = ArraySize(tickets);
      if(ArrayResize(tickets, n + 1) == n + 1)
         tickets[n] = ticket;
     }

   datetime now = TimeCurrent();
   for(int i = 0; i < ArraySize(tickets); i++)
     {
      ulong ticket = tickets[i];
      if(!SelectOurPosition(ticket))
         continue;

      datetime open_time   = (datetime)PositionGetInteger(POSITION_TIME);
      long     seconds_open = (long)(now - open_time);
      double   profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

      if(IsHarvestPosition(ticket))
        {
         if(InpHarvestTakeProfitMoney > 0.0 && profit >= InpHarvestTakeProfitMoney)
           {
            CloseOurPosition(ticket, StringFormat("hasat para TP (%.2f >= %.2f)", profit, InpHarvestTakeProfitMoney));
            continue;
           }
         if(InpHarvestStopLossMoney > 0.0 && profit <= -InpHarvestStopLossMoney)
           {
            CloseOurPosition(ticket, StringFormat("hasat para SL (%.2f <= -%.2f)", profit, InpHarvestStopLossMoney));
            continue;
           }
         if(InpHarvestMaxLifeMinutes > 0 && seconds_open >= (long)InpHarvestMaxLifeMinutes * 60)
           {
            CloseOurPosition(ticket, StringFormat("hasat süre sınırı (%d dk)", InpHarvestMaxLifeMinutes));
            continue;
           }
         continue;
        }

      if(!IsEscorted(ticket))
         continue;

      if(InpEscortStopLossMoney > 0.0 && profit <= -InpEscortStopLossMoney)
        {
         CloseOurPosition(ticket, StringFormat("taşınan pozisyon para SL (%.2f <= -%.2f)", profit, InpEscortStopLossMoney));
         continue;
        }
      if(InpEscortMaxRideHours > 0 && seconds_open >= (long)InpEscortMaxRideHours * 3600)
        {
         CloseOurPosition(ticket, StringFormat("taşınan pozisyon süre sınırı (%d saat)", InpEscortMaxRideHours));
         continue;
        }
     }
  }

// Bir pozisyonun kapanmış işlemlerinden net sonucu (kâr + swap + komisyon).
double PositionHistoryProfit(const ulong position_id)
  {
   if(!HistorySelectByPosition((long)position_id))
      return 0.0;

   double total = 0.0;
   int deals = HistoryDealsTotal();
   for(int i = 0; i < deals; i++)
     {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;
      total += HistoryDealGetDouble(deal, DEAL_PROFIT);
      total += HistoryDealGetDouble(deal, DEAL_SWAP);
      total += HistoryDealGetDouble(deal, DEAL_COMMISSION);
     }
   return total;
  }

// Hasat kâr birikimini günceller: kapanan hasat işlemlerinin net
// sonucu birikime eklenir, kısmi kâr kredisi buradan beslenir.
void UpdateHarvestPocket()
  {
   if(!InpHarvestEnabled)
      return;

   // 1) Açık hasat pozisyonlarını izleme listesine al.
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      if(!IsHarvestPosition(ticket))
         continue;
      ListAdd(g_harvest_watch, ticket);
     }

   // 2) Kapananların net sonucunu birikime ekle.
   for(int i = ArraySize(g_harvest_watch) - 1; i >= 0; i--)
     {
      ulong ticket = g_harvest_watch[i];
      bool still_open = false;
      if(PositionSelectByTicket(ticket))
        {
         if(PositionGetString(POSITION_SYMBOL) == _Symbol &&
            (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber)
            still_open = true;
        }
      if(still_open)
         continue;

      double pnl = PositionHistoryProfit(ticket);
      g_harvest_pocket += pnl;
      g_harvest_credit += pnl;
      if(g_harvest_credit < 0.0)
         g_harvest_credit = 0.0;
      g_harvest_closed++;
      PrintFormat("Hasat kapandı: ticket=%I64u net=%.2f | toplam hasat kârı=%.2f | kısmi kâr kredisi=%.2f",
                  ticket, pnl, g_harvest_pocket, g_harvest_credit);
      ListRemove(g_harvest_watch, ticket);
     }
  }

// Biriken hasat kârı eşiği aşınca taşınan pozisyondan kısmi kâr alır.
void CheckHarvestTrim()
  {
   if(!InpEscortEnabled || !InpHarvestEnabled || !InpHarvestTrimEnabled)
      return;
   if(InpHarvestTrimProfit <= 0.0 || InpHarvestTrimPercent <= 0.0)
      return;
   if(g_harvest_credit < InpHarvestTrimProfit)
      return;

   ulong  ticket      = 0;
   double best_volume = 0.0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong t = PositionGetTicket(i);
      if(t == 0 || !IsEscorted(t))
         continue;
      double volume = PositionGetDouble(POSITION_VOLUME);
      if(volume > best_volume)
        {
         best_volume = volume;
         ticket      = t;
        }
     }
   if(ticket == 0 || best_volume <= 0.0)
      return;
   if(!SelectOurPosition(ticket))
      return;

   double profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   if(InpHarvestTrimOnlyIfRideProfit && profit < 0.0)
      return;

   double close_volume = NormalizeVolume(best_volume * InpHarvestTrimPercent / 100.0);
   if(close_volume <= 0.0)
      return;
   double min_volume = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   if(best_volume - close_volume < min_volume - 1.0e-10)
      close_volume = best_volume; // Kalan hacim minimumun altında kalacaksa tamamı kapatılır

   if(close_volume >= best_volume - 1.0e-10)
     {
      if(!CloseOurPosition(ticket, "hasat kârı ile kısmi kâr (tamamı)"))
         return;
     }
   else
     {
      bool sent = trade.PositionClosePartial(ticket, close_volume, (ulong)InpDeviationPoints);
      if(!TradeRetcodeOK(sent))
        {
         PrintFormat("Kısmi kâr başarısız: ticket=%I64u hacim=%.8f retcode=%u (%s)",
                     ticket, close_volume, trade.ResultRetcode(), trade.ResultRetcodeDescription());
         return;
        }
      PrintFormat("Kısmi kâr: ticket=%I64u hacim=%.8f kapatıldı | hasat kredisi %.2f -> %.2f",
                  ticket, close_volume, g_harvest_credit, g_harvest_credit - InpHarvestTrimProfit);
      g_last_action = StringFormat("Hasat kârı ile %.8f lot kısmi kâr alındı", close_volume);
     }

   g_harvest_credit -= InpHarvestTrimProfit;
   if(g_harvest_credit < 0.0)
      g_harvest_credit = 0.0;
   g_harvest_trimmed_lot += close_volume;
  }

// Her tick/timer'da çalışan taşıma + hasat döngüsü.
void ManageEscortAndHarvest()
  {
   if(!InpEscortEnabled && !InpHarvestEnabled)
      return;
   UpdateHarvestPocket();
   ProcessEscortPositions();
   CheckPositionMoneyExits();
   CheckHarvestTrim();
  }

//+------------------------------------------------------------------+
//| Donchian motoru: hızlı TF TP/SL çıkışları                        |
//|                                                                  |
//| Her pozisyonun yönüne göre menüden seçilmiş TP ve SL olayları     |
//| sayılır. Taşınan (HTF) pozisyonlar burada atlanır; onlar          |
//| EvaluateEscortExit() içinde HTF serisiyle yönetilir.              |
//+------------------------------------------------------------------+
void ManageDonchianExits(const MqlRates &rates[], const int &events[])
  {
   if(InpDonTpSignalCount <= 0 && InpDonSlSignalCount <= 0 &&
      InpHarvestTpSignalCount <= 0 && InpHarvestSlSignalCount <= 0)
      return;

   ulong tickets[];
   ArrayResize(tickets, 0);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      int n = ArraySize(tickets);
      if(ArrayResize(tickets, n + 1) == n + 1)
         tickets[n] = ticket;
     }

   for(int i = 0; i < ArraySize(tickets); i++)
     {
      ulong ticket = tickets[i];
      if(!SelectOurPosition(ticket))
         continue;
      if(IsEscorted(ticket))
         continue; // Taşınan pozisyon HTF kurallarıyla yönetilir

      int side = SideFromPositionType(PositionGetInteger(POSITION_TYPE));
      if(side == 0)
         continue;

      bool harvest   = IsHarvestPosition(ticket);
      int  tp_needed = (harvest ? InpHarvestTpSignalCount : InpDonTpSignalCount);
      int  sl_needed = (harvest ? InpHarvestSlSignalCount : InpDonSlSignalCount);
      if(tp_needed <= 0 && sl_needed <= 0)
         continue;

      ENUM_SQZ_EVENT tp_event = (side > 0 ? InpDonLongTp : InpDonShortTp);
      ENUM_SQZ_EVENT sl_event = (side > 0 ? InpDonLongSl : InpDonShortSl);
      datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);

      string reason = "";
      int tp_count = 0;
      int sl_count = 0;
      int result = EvaluateEventExit(ticket, rates, events, g_timeframe, open_time,
                                     tp_event, sl_event, tp_needed, sl_needed,
                                     InpDonTpOnlyInProfit, InpDonSlOnlyInLoss,
                                     reason, tp_count, sl_count);
      if(result != 0)
         CloseOurPosition(ticket, reason);
     }
  }

//+------------------------------------------------------------------+
//| Sinyalde pozisyon açma                                           |
//+------------------------------------------------------------------+
bool BuildFixedExits(const int side, const double entry, double &sl, double &tp)
  {
   BuildFixedPrices(side, entry, InpFixedTakeProfitPoints, InpFixedStopLossPoints, sl, tp);
   return (tp > 0.0 || InpFixedTakeProfitPoints <= 0) &&
          (sl > 0.0 || InpFixedStopLossPoints <= 0);
  }

void DrawSignalArrow(const datetime bar_time, const double high, const double low, const int raw_signal)
  {
   if(!InpDrawSignalArrows)
      return;
   string name = g_object_prefix + IntegerToString((long)bar_time);
   if(ObjectFind(0, name) >= 0)
      return;
   double offset = MathMax((high - low) * 0.25, _Point * 20.0);
   if(raw_signal > 0)
     {
      if(!ObjectCreate(0, name, OBJ_ARROW_BUY, 0, bar_time, low - offset))
         return;
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrLimeGreen);
     }
   else
     {
      if(!ObjectCreate(0, name, OBJ_ARROW_SELL, 0, bar_time, high + offset))
         return;
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrTomato);
     }
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

bool OpenOneTrade(const int trade_side, const int raw_signal, const datetime signal_bar_time,
                  const double signal_price, const int index, const int total,
                  const bool is_harvest)
  {
   if(InpMaxOpenPositions > 0 && CountOurPositions(0) >= InpMaxOpenPositions)
     {
      g_last_action = "Maksimum pozisyon sayısına ulaşıldı";
      return false;
     }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick) || tick.ask <= 0.0 || tick.bid <= 0.0)
      return false;

   double spread_points = (tick.ask - tick.bid) / _Point;
   if(InpMaxSpreadPoints > 0 && spread_points > InpMaxSpreadPoints)
     {
      g_last_action = StringFormat("Spread yüksek: %.1f point", spread_points);
      return false;
     }

   // Hasat işlemleri kendi (opsiyonel) lotunu kullanır.
   double requested_lot = InpLotSize;
   if(is_harvest && InpHarvestLot > 0.0)
      requested_lot = InpHarvestLot;
   double volume = NormalizeVolume(requested_lot);
   if(volume <= 0.0)
     {
      g_last_action = "Lot hacmi broker sınırlarına uymuyor";
      return false;
     }

   double expected_entry = (trade_side > 0 ? tick.ask : tick.bid);
   double fixed_sl = 0.0;
   double fixed_tp = 0.0;
   if(!BuildFixedExits(trade_side, expected_entry, fixed_sl, fixed_tp))
     {
      g_last_action = "Sabit TP/SL fiyatı hesaplanamadı";
      return false;
     }

   string comment = (trade_side > 0 ? "SQZLB BUY" : "SQZLB SELL");
   if(is_harvest)
      comment = (trade_side > 0 ? "SQZLB HARV BUY" : "SQZLB HARV SELL");
   if(total > 1)
      comment = comment + " " + IntegerToString(index) + "/" + IntegerToString(total);

   bool sent = false;
   if(trade_side > 0)
      sent = trade.Buy(volume, _Symbol, 0.0, fixed_sl, fixed_tp, comment);
   else
      sent = trade.Sell(volume, _Symbol, 0.0, fixed_sl, fixed_tp, comment);

   if(!TradeRetcodeOK(sent))
     {
      PrintFormat("Giriş başarısız: sinyal=%s işlem yönü=%s lot=%.8f retcode=%u (%s)",
                  SignalName(raw_signal), SideName(trade_side), volume,
                  trade.ResultRetcode(), trade.ResultRetcodeDescription());
      g_last_action = "Emir broker tarafından reddedildi";
      return false;
     }

   if(is_harvest)
      g_harvest_opened++;
   PrintFormat("Giriş: %s | işlem=%s%s%s | sinyal mumu=%s sinyal fiyatı=%.*f | lot=%.8f",
               SignalName(raw_signal), SideName(trade_side),
               (is_harvest ? " (hasat)" : ""),
               (InpReverseTrading ? " (ters işlem)" : ""),
               TimeToString(signal_bar_time), _Digits, signal_price, volume);
   g_last_action = StringFormat("Yeni %s pozisyon açıldı (%s%s)",
                                SideName(trade_side), SignalName(raw_signal),
                                (InpReverseTrading ? ", ters işlem" : ""));
   return true;
  }

bool OpenPositionBySignal(const int raw_signal, const datetime signal_bar_time, const double signal_price)
  {
   if(raw_signal > 0 && !InpOpenOnBuySignal)
     {
      g_last_action = "BUY sinyali geldi ancak ayarlardan kapalı";
      return false;
     }
   if(raw_signal < 0 && !InpOpenOnSellSignal)
     {
      g_last_action = "SELL sinyali geldi ancak ayarlardan kapalı";
      return false;
     }

   // Ters işlem ayarı yalnızca AÇILIŞ yönünü değiştirir.
   int trade_side = InpReverseTrading ? -raw_signal : raw_signal;

   if(trade_side > 0 && !InpAllowLongTrades)
     {
      g_last_action = "BUY pozisyon açma ayarlardan kapalı";
      return false;
     }
   if(trade_side < 0 && !InpAllowShortTrades)
     {
      g_last_action = "SELL pozisyon açma ayarlardan kapalı";
      return false;
     }

   // --- HASAT mı, normal pozisyon mu? ---------------------------------
   // Taşınan (HTF'ye alınmış) bir pozisyonun TERSİNE açılan hızlı TF
   // işlemi "hasat" işlemidir: kendi hızlı çıkış kurallarıyla kâr toplar.
   bool harvest = false;
   if(InpEscortEnabled && InpHarvestEnabled && EscortSideEnabled(-trade_side) &&
      CountEscortedPositions(-trade_side) > 0)
     {
      if(InpHarvestMaxPositions > 0 &&
         CountHarvestPositions(trade_side) >= InpHarvestMaxPositions)
        {
         g_last_action = StringFormat("Hasat limiti: %d %s hasat pozisyonu açık",
                                      InpHarvestMaxPositions, SideName(trade_side));
         PrintFormat("Hasat atlandı (limit %d): %s",
                     InpHarvestMaxPositions, SignalName(raw_signal));
         return false;
        }
      harvest = true;
     }

   // Taşınan yönde yeni hızlı TF pozisyonu açılmasın (risk filtresi):
   // trendin tersine birikmek yerine taşınan pozisyon nefes alsın.
   if(!harvest && InpEscortEnabled && InpEscortBlockSameSide &&
      CountEscortedPositions(trade_side) > 0)
     {
      g_balance_skip_count++;
      g_last_action = StringFormat("%s yönünde taşınan pozisyon var: yeni pozisyon açılmadı",
                                   SideName(trade_side));
      PrintFormat("Sinyal atlandı (taşıma filtresi): %s | %s yönünde taşınan pozisyon açık",
                  SignalName(raw_signal), SideName(trade_side));
      return false;
     }

   // Dengeleme: bu sinyalde kaç pozisyon açılacağı (0 = atla).
   // Hasat işlemleri taşınan pozisyonun doğal hedge'i olduğu için
   // dengeleme farkını bilerek aşabilir; kendi limitleri vardır.
   string note = "";
   int count = 1;
   if(harvest)
     {
      note = StringFormat("hasat %d/%s", CountHarvestPositions(trade_side) + 1,
                          (InpHarvestMaxPositions > 0 ? IntegerToString(InpHarvestMaxPositions) : "sınırsız"));
      if(InpMaxOpenPositions > 0 && CountOurPositions(0) >= InpMaxOpenPositions)
        {
         g_last_action = "Maksimum pozisyon sayısına ulaşıldı (hasat)";
         return false;
        }
     }
   else
     {
      count = PositionsToOpen(trade_side, note);
      if(count <= 0)
        {
         g_balance_skip_count++;
         PrintFormat("Sinyal atlandı (dengeleme): %s | %s", SignalName(raw_signal), note);
         g_last_action = StringFormat("%s sinyali atlandı: %s",
                                      SideName(trade_side), (note == "" ? "fark limiti" : note));
         return false;
        }
     }

   int opened = 0;
   for(int i = 1; i <= count; i++)
     {
      if(!OpenOneTrade(trade_side, raw_signal, signal_bar_time, signal_price, i, count, harvest))
         break;
      opened++;
     }

   if(opened > 0 && harvest)
     {
      PrintFormat("Hasat: %s | %s pozisyonu açıldı (taşınan pozisyonun tersine)", note,
                  SideName(trade_side));
      g_last_action = StringFormat("Hasat pozisyonu açıldı: %s (%s)", SideName(trade_side), note);
     }
   else if(opened > 0 && count > 1)
     {
      g_balance_fill_count += (opened - 1);
      PrintFormat("Dengeleme: %s | tek sinyalde %d pozisyon açıldı", note, opened);
      g_last_action = StringFormat("Dengeleme: %s -> %d %s pozisyon açıldı",
                                   note, opened, SideName(trade_side));
     }
   return (opened > 0);
  }

//+------------------------------------------------------------------+
//| Kapanmış mum işleme                                              |
//+------------------------------------------------------------------+
void ProcessClosedBar()
  {
   MqlRates rates[];
   int copied = LoadRates(rates);
   int min_bars = (int)MathMax((2 * InpKCLength) + 5, InpBBLength + 5);
   if(InpSignalEngine == ENGINE_DONCHIAN)
     {
      int don_bars = (int)MathMax(InpDonLength + (int)MathMax(InpDonCon, 0) + 5,
                                  InpDonAtrLength + 5);
      min_bars = (int)MathMax(min_bars, don_bars);
     }
   if(copied < min_bars)
     {
      g_last_action = StringFormat("Yetersiz mum verisi: %d/%d", copied, min_bars);
      return;
     }

   int last_closed = copied - 2; // Son index oluşan (canlı) mumdur
   if(last_closed < 1)
     {
      g_last_action = "Yeterli kapalı mum yok";
      return;
     }

   double values[];
   ENUM_SQZ_BAR_COLOR colors[];
   bool valid[];
   bool momentum_ok = ComputeMomentum(rates, values, colors, valid);
   bool momentum_bar_ok = (momentum_ok &&
                           ArraySize(valid) > last_closed &&
                           valid[last_closed] && valid[last_closed - 1]);

   // --- DONCHIAN MOTORU --------------------------------------------
   if(InpSignalEngine == ENGINE_DONCHIAN)
     {
      int flags[];
      double don_fbasis = 0.0;
      double don_uu = 0.0;
      double don_ll = 0.0;
      bool   don_ok = false;
      if(!ComputeDonchianEvents(rates, flags, don_fbasis, don_uu, don_ll, don_ok) ||
         !don_ok || last_closed >= ArraySize(flags))
        {
         g_last_action = "Donchian: yeterli mum verisi yok";
         return;
        }

      // Squeeze olayları da aynı maskeye eklenir; menüde Squeeze
      // olayı seçilirse Donchian motorunda da çalışır.
      if(momentum_ok)
        {
         int sqz_flags[];
         SqueezeEventsFromColors(colors, sqz_flags);
         int sqz_total = ArraySize(sqz_flags);
         for(int i = 0; i < ArraySize(flags) && i < sqz_total; i++)
            flags[i] |= sqz_flags[i];
        }

      g_don_fbasis     = don_fbasis;
      g_don_uu         = don_uu;
      g_don_ll         = don_ll;
      g_don_ready      = true;
      g_don_last_events = flags[last_closed];

      // Squeeze panel değerleri (bilgi amaçlı)
      if(momentum_bar_ok)
        {
         g_last_momentum  = values[last_closed];
         g_last_bar_color = colors[last_closed];
         g_prev_bar_color = colors[last_closed - 1];
         g_last_sqz_state = ComputeSqueezeState(rates, last_closed);
        }

      // Önce mevcut pozisyonların seçili olay bazlı çıkışları,
      // ardından aynı mumun yeni giriş sinyali işlenir.
      ManageDonchianExits(rates, flags);

      int raw = 0;
      if(HasEvent(flags[last_closed], InpDonLongEntry))
         raw = 1;
      else
         if(HasEvent(flags[last_closed], InpDonShortEntry))
            raw = -1;

      if(raw == 0)
        {
         g_last_action = StringFormat("Donchian: yeni sinyal yok (%s)",
                                      EventFlagsText(flags[last_closed]));
         return;
        }

      g_last_raw_signal   = raw;
      g_last_signal_time  = rates[last_closed].time;
      g_last_signal_price = rates[last_closed].close;

      DrawSignalArrow(rates[last_closed].time, rates[last_closed].high,
                      rates[last_closed].low, raw);
      OpenPositionBySignal(raw, rates[last_closed].time, rates[last_closed].close);
      return;
     }

   // --- SQUEEZE MOTORU (mevcut davranış) ---------------------------
   if(!momentum_ok)
     {
      g_last_action = "Momentum hesaplanamadı";
      return;
     }

   if(!momentum_bar_ok)
     {
      g_last_action = "Momentum için yeterli kapalı mum yok";
      return;
     }

   g_last_momentum  = values[last_closed];
   g_last_bar_color = colors[last_closed];
   g_prev_bar_color = colors[last_closed - 1];
   g_last_sqz_state = ComputeSqueezeState(rates, last_closed);

   // TradingView'deki histogram değeri/renkleriyle birebir karşılaştırma için.
   if(InpLogIndicator)
     {
      double prev_val = (valid[last_closed - 1] ? values[last_closed - 1] : 0.0);
      PrintFormat("Gösterge[%s] val=%s val[1]=%s renk=%s | %s",
                  TimeToString(rates[last_closed].time, TIME_DATE | TIME_MINUTES),
                  DoubleToString(values[last_closed], _Digits + 2),
                  DoubleToString(prev_val, _Digits + 2),
                  ColorName(colors[last_closed]),
                  SqueezeStateName(g_last_sqz_state));
     }

   // Önce mevcut pozisyonların sinyal sayımlı çıkışları kontrol edilir;
   // böylece bu mumda oluşan sinyal önce eski pozisyonlara işletilir,
   // ardından aynı sinyal yeni pozisyon açabilir.
   ManageSignalExits(rates, colors, valid);

   int raw_signal = SignalFromTransition(colors[last_closed - 1], colors[last_closed]);
   if(raw_signal == 0)
     {
      g_last_action = "Yeni sinyal yok";
      return;
     }

   g_last_raw_signal   = raw_signal;
   g_last_signal_time  = rates[last_closed].time;
   g_last_signal_price = rates[last_closed].close;

   DrawSignalArrow(rates[last_closed].time, rates[last_closed].high,
                   rates[last_closed].low, raw_signal);
   OpenPositionBySignal(raw_signal, rates[last_closed].time, rates[last_closed].close);
  }

void CheckNewBar()
  {
   datetime current_bar_time = iTime(_Symbol, g_timeframe, 0);
   if(current_bar_time <= 0)
      return;
   if(g_last_bar_time == 0)
     {
      // EA açıldığında geçmiş sinyalden geriye dönük işlem açma.
      g_last_bar_time = current_bar_time;
      return;
     }
   if(current_bar_time == g_last_bar_time)
      return;
   g_last_bar_time = current_bar_time;
   ProcessClosedBar();
  }

//+------------------------------------------------------------------+
//| Bilgi paneli / nesneler                                          |
//+------------------------------------------------------------------+
void UpdateChartInfo()
  {
   if(!InpShowChartInfo)
     {
      Comment("");
      return;
     }

   string reverse_text = InpReverseTrading
                         ? "AÇIK (BUY sinyali -> SELL, SELL sinyali -> BUY)"
                         : "kapalı (sinyal yönünde işlem)";
   string last_signal_text = "henüz yok";
   if(g_last_raw_signal != 0 && g_last_signal_time > 0)
      last_signal_text = StringFormat("%s | %s | fiyat %.*f",
                                      SignalName(g_last_raw_signal),
                                      TimeToString(g_last_signal_time),
                                      _Digits, g_last_signal_price);

   string reset_text;
   if(!InpAutoResetEnabled || InpAutoResetLevel <= 0.0)
      reset_text = "kapalı";
   else
      reset_text = StringFormat("%s | eşik %.2f | referans %.2f | fark %+.2f | %s | toplam %d sıfırlama",
                                ResetModeName(InpAutoResetMode), InpAutoResetLevel,
                                g_reset_start_balance,
                                ResetDifference(AccountInfoDouble(ACCOUNT_EQUITY)),
                                (g_reset_hold ? "SIFIRLANIYOR" : "izleniyor"),
                                g_reset_count);

   string balance_text;
   if(!InpBalanceEnabled || InpBalanceMaxGap < 1)
      balance_text = "kapalı";
   else
      balance_text = StringFormat("maks. fark %d | telafi edilen pozisyon %d | atlanan sinyal %d",
                                  InpBalanceMaxGap, g_balance_fill_count, g_balance_skip_count);

   // Sinyal motoru bloğu (Squeeze veya Donchian)
   string engine_text = EngineName(InpSignalEngine);
   if(InpSignalEngine == ENGINE_DONCHIAN)
      engine_text = engine_text + StringFormat(" | LONG giriş: %s | SHORT giriş: %s",
                                               EventName(InpDonLongEntry),
                                               EventName(InpDonShortEntry));

   string engine_block = StringFormat("Motor: %s\n", engine_text);
   if(InpSignalEngine == ENGINE_DONCHIAN)
     {
      string donchian_text;
      if(!g_don_ready)
         donchian_text = "hesaplanıyor (yeterli mum bekleniyor)";
      else
         donchian_text = StringFormat("fbasis=%s | uu=%s | ll=%s | son olaylar: %s | TP: L=%s S=%s (%d) | SL: L=%s S=%s (%d)",
                                      DoubleToString(g_don_fbasis, _Digits + 2),
                                      DoubleToString(g_don_uu, _Digits + 2),
                                      DoubleToString(g_don_ll, _Digits + 2),
                                      EventFlagsText(g_don_last_events),
                                      EventName(InpDonLongTp), EventName(InpDonShortTp),
                                      InpDonTpSignalCount,
                                      EventName(InpDonLongSl), EventName(InpDonShortSl),
                                      InpDonSlSignalCount);
      engine_block = engine_block + StringFormat("Donchian: %s\n", donchian_text);
     }

   string escort_text;
   if(!InpEscortEnabled)
      escort_text = "kapalı";
   else
      escort_text = StringFormat("%s | taşıma TF %s | eşik %s | taşınan %d pozisyon | HTF çıkış TP %d / SL %d sinyal",
                                 EscortModeName(InpEscortMode), EnumToString(g_escort_tf),
                                 EscortThresholdText(), CountEscortedPositions(0),
                                 InpEscortTpSignalCount, InpEscortSlSignalCount);

   string harvest_text;
   if(!InpEscortEnabled || !InpHarvestEnabled)
      harvest_text = "kapalı";
   else
      harvest_text = StringFormat("açık %d | limit %s | para TP %.2f / SL %.2f | toplanan kâr %.2f | kredi %.2f | kısmi kâr %.2f lot",
                                  CountHarvestPositions(0),
                                  (InpHarvestMaxPositions > 0 ? IntegerToString(InpHarvestMaxPositions) : "sınırsız"),
                                  InpHarvestTakeProfitMoney, InpHarvestStopLossMoney,
                                  g_harvest_pocket, g_harvest_credit, g_harvest_trimmed_lot);

   Comment("Squeeze Momentum [LazyBear] + Donchian EA v1.50\n",
           "Sembol: ", _Symbol, " | TF: ", EnumToString(g_timeframe), "\n",
           engine_block,
           "Sinyal geçişleri: BUY: ", TransitionText(InpBuyFromColor, InpBuyToColor),
           " | SELL: ", TransitionText(InpSellFromColor, InpSellToColor), "\n",
           "Son kapalı mum momentum: ", DoubleToString(g_last_momentum, _Digits + 2), "\n",
           "Renk geçişi: ", ColorName(g_prev_bar_color), " -> ", ColorName(g_last_bar_color), "\n",
           "Squeeze durumu (bilgi): ", SqueezeStateName(g_last_sqz_state), "\n",
           "Son sinyal: ", last_signal_text, "\n",
           "Ters işlem: ", reverse_text, "\n",
           "Çıkış: TP ", IntegerToString(InpTakeProfitSignalCount), " uygun sinyal | SL ",
           IntegerToString(InpStopLossSignalCount), " uygun sinyal",
           (InpFixedTakeProfitPoints > 0 || InpFixedStopLossPoints > 0
              ? StringFormat(" | sabit TP %d / SL %d point", InpFixedTakeProfitPoints, InpFixedStopLossPoints)
              : " | sabit TP/SL kapalı"), "\n",
           "Açık pozisyon BUY/SELL: ", IntegerToString(CountOurPositions(1)), " / ",
           IntegerToString(CountOurPositions(-1)), "\n",
           "Otomatik sıfırlama: ", reset_text, "\n",
           "Dengeleme: ", balance_text, "\n",
           "HTF taşıma: ", escort_text, "\n",
           "Hasat: ", harvest_text, "\n",
           "Durum: ", g_last_action);
  }

void DeleteOwnObjects()
  {
   if(g_object_prefix == "")
      return;
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, g_object_prefix) == 0)
         ObjectDelete(0, name);
     }
  }

//+------------------------------------------------------------------+
//| Standart olaylar                                                 |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpBBLength < 2 || InpKCLength < 2 ||
      InpBBMultFactor <= 0.0 || InpKCMultFactor <= 0.0 ||
      InpHistoryBars < 100 || InpLotSize <= 0.0 ||
      InpTakeProfitSignalCount < 0 || InpStopLossSignalCount < 0 ||
      InpFixedTakeProfitPoints < 0 || InpFixedStopLossPoints < 0 ||
      InpDeviationPoints < 0 || InpMaxSpreadPoints < 0 ||
      InpMaxOpenPositions < 0 ||
      !MathIsValidNumber(InpBBMultFactor) || !MathIsValidNumber(InpKCMultFactor) ||
      !MathIsValidNumber(InpLotSize))
     {
      Print("Hatalı girdiler: BB/KC uzunluk ve çarpımları, lot, sinyal sayıları ve emir ayarlarını kontrol edin.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpAutoResetLevel < 0.0 || !MathIsValidNumber(InpAutoResetLevel))
     {
      Print("Hatalı girdiler: Otomatik sıfırlama eşik tutarı negatif veya geçersiz olamaz (0 = kapalı).");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpBalanceMaxBatch < 0 || (InpBalanceEnabled && InpBalanceMaxGap < 1))
     {
      Print("Hatalı girdiler: dengeleme maksimum farkı en az 1 olmalı, tek sinyaldeki telafi sınırı negatif olamaz.");
      return INIT_PARAMETERS_INCORRECT;
     }

   // Sinyal renk geçişleri doğrulaması
   if((InpBuyFromColor == SQZ_CHOICE_ANY && InpBuyToColor == SQZ_CHOICE_ANY) ||
      (InpSellFromColor == SQZ_CHOICE_ANY && InpSellToColor == SQZ_CHOICE_ANY))
     {
      Print("Hatalı girdiler: BUY/SELL sinyal geçişinde önceki ve yeni renk aynı anda 'Fark etmez' olamaz.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if((InpBuyFromColor != SQZ_CHOICE_ANY && InpBuyFromColor == InpBuyToColor) ||
      (InpSellFromColor != SQZ_CHOICE_ANY && InpSellFromColor == InpSellToColor))
     {
      Print("Hatalı girdiler: Bir sinyal geçişi için önceki ve yeni renk farklı olmalıdır (gerçek renk değişimi gerekir).");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpBuyFromColor == InpSellFromColor && InpBuyToColor == InpSellToColor)
     {
      Print("Hatalı girdiler: BUY ve SELL sinyal geçişleri birebir aynı olamaz.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if((InpBuyFromColor == SQZ_CHOICE_ANY || InpSellFromColor == SQZ_CHOICE_ANY ||
       InpBuyFromColor == InpSellFromColor) &&
      (InpBuyToColor == SQZ_CHOICE_ANY || InpSellToColor == SQZ_CHOICE_ANY ||
       InpBuyToColor == InpSellToColor))
      Print("UYARI: BUY ve SELL sinyal geçişleri kesişiyor. Kesişen geçişlerde BUY sinyali önceliklidir.");
   if(InpTakeProfitSignalCount == 0 && InpStopLossSignalCount == 0 &&
      InpFixedTakeProfitPoints == 0 && InpFixedStopLossPoints == 0)
      Print("UYARI: Tüm çıkışlar kapalı. Pozisyonlar yalnızca elle kapatılabilir.");

   if(InpRequireHedgingAccount &&
      AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      Print("EA başlatılamadı: sinyal bazlı TP/SL sayımı her pozisyon için ayrı takip gerektirir; hedging hesap gerekir. "
            "Netting hesapta kullanmak isterseniz InpRequireHedgingAccount=false yapın (pozisyonlar netleşebilir).");
      return INIT_FAILED;
     }
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("UYARI: Hesap hedging değil. Aynı sembolde pozisyonlar netleşebilir; çıkış sayımı tek net pozisyon üzerinden takip edilir.");
   if(InpBalanceEnabled && InpBalanceMaxGap >= 1 &&
      AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("UYARI: Pozisyon dengeleme netting hesapta çalışmaz (aynı sembolde tek net pozisyon tutulur). "
            "Dengeleme için hedging hesap gerekir.");

   g_timeframe = WorkingTimeframe();
   if(PeriodSeconds(g_timeframe) <= 0)
     {
      Print("EA başlatılamadı: geçersiz zaman dilimi.");
      return INIT_FAILED;
     }
   if(!SymbolSelect(_Symbol, true))
     {
      Print("EA başlatılamadı: sembol seçilemiyor.");
      return INIT_FAILED;
     }

   // --- HTF taşıma / hasat ayarlarının doğrulanması ---
   g_escort_tf = (InpEscortTimeframe == PERIOD_CURRENT
                  ? (ENUM_TIMEFRAMES)Period() : InpEscortTimeframe);
   if(InpEscortEnabled)
     {
      if(PeriodSeconds(g_escort_tf) <= 0)
        {
         Print("EA başlatılamadı: geçersiz taşıma zaman dilimi.");
         return INIT_PARAMETERS_INCORRECT;
        }
      if(PeriodSeconds(g_escort_tf) <= PeriodSeconds(g_timeframe))
        {
         Print("EA başlatılamadı: taşıma zaman dilimi işlem zaman diliminden BÜYÜK olmalı (örn. M1 -> H1).");
         return INIT_PARAMETERS_INCORRECT;
        }
      if(InpEscortAfterMinutes < 0 || InpEscortAfterBars < 0 ||
         InpEscortTpSignalCount < 0 || InpEscortSlSignalCount < 0 ||
         InpEscortFixedTpPoints < 0 || InpEscortFixedSlPoints < 0 ||
         InpEscortMaxRideHours < 0 || InpEscortStopLossMoney < 0.0 ||
         !MathIsValidNumber(InpEscortStopLossMoney))
        {
         Print("Hatalı girdiler: taşıma ayarları negatif veya geçersiz olamaz.");
         return INIT_PARAMETERS_INCORRECT;
        }
      if(InpEscortTpSignalCount <= 0 && InpEscortSlSignalCount <= 0 &&
         InpEscortFixedTpPoints <= 0 && InpEscortFixedSlPoints <= 0 &&
         InpEscortMaxRideHours <= 0 && InpEscortStopLossMoney <= 0.0)
         Print("UYARI: taşınan pozisyonun hiçbir çıkış kuralı yok; pozisyon süresiz açık kalabilir.");
      if(EscortThresholdSeconds() >= PeriodSeconds(g_escort_tf))
         Print("BİLGİ: taşıma eşiği taşıma zaman diliminden uzun; ilk HTF sinyali beklenirken pozisyon hızlı TF'de kalır.");
     }
   if(InpHarvestEnabled)
     {
      if(InpHarvestLot < 0.0 || InpHarvestMaxPositions < 0 ||
         InpHarvestTakeProfitMoney < 0.0 || InpHarvestStopLossMoney < 0.0 ||
         InpHarvestTpSignalCount < 0 || InpHarvestSlSignalCount < 0 ||
         InpHarvestMaxLifeMinutes < 0 || InpHarvestTrimProfit < 0.0 ||
         !MathIsValidNumber(InpHarvestTakeProfitMoney) ||
         !MathIsValidNumber(InpHarvestStopLossMoney) ||
         !MathIsValidNumber(InpHarvestLot))
        {
         Print("Hatalı girdiler: hasat ayarları negatif veya geçersiz olamaz.");
         return INIT_PARAMETERS_INCORRECT;
        }
      if(InpHarvestTrimPercent < 0.0 || InpHarvestTrimPercent > 100.0 ||
         !MathIsValidNumber(InpHarvestTrimPercent))
        {
         Print("Hatalı girdiler: kısmi kâr yüzdesi 0-100 arasında olmalı.");
         return INIT_PARAMETERS_INCORRECT;
        }
      if(InpHarvestTpSignalCount <= 0 && InpHarvestSlSignalCount <= 0 &&
         InpHarvestTakeProfitMoney <= 0.0 && InpHarvestStopLossMoney <= 0.0 &&
         InpHarvestMaxLifeMinutes <= 0)
         Print("UYARI: hasat pozisyonlarının hiçbir çıkış kuralı yok; hızlı TF sinyalleriyle kapanmazlar.");
      if(InpEscortEnabled &&
         AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
         Print("UYARI: taşıma + hasat aynı sembolde ters yönde pozisyon gerektirir; netting hesapta çalışmaz.");
     }

   // --- Sinyal motoru / Donchian doğrulaması ---
   if(InpSignalEngine == ENGINE_DONCHIAN)
     {
      if(InpDonLength < 2 || InpDonAtrLength < 1 || InpDonCon < 0 ||
         InpDonMult <= 0.0 || !MathIsValidNumber(InpDonMult))
        {
         Print("Hatalı girdiler: Donchian Length >= 2, ATR Length >= 1, con >= 0, Range Multiplier > 0 olmalı.");
         return INIT_PARAMETERS_INCORRECT;
        }
      if(InpDonTpSignalCount < 0 || InpDonSlSignalCount < 0)
        {
         Print("Hatalı girdiler: Donchian TP/SL sinyal sayıları negatif olamaz (0 = o çıkış kapalı).");
         return INIT_PARAMETERS_INCORRECT;
        }
      if(InpDonLongEntry == EVENT_NONE && InpDonShortEntry == EVENT_NONE)
        {
         Print("Hatalı girdiler: Donchian motorunda en az bir giriş sinyali (LONG veya SHORT) seçilmeli.");
         return INIT_PARAMETERS_INCORRECT;
        }
      if(IsSqueezeEvent(InpDonLongEntry) || IsSqueezeEvent(InpDonShortEntry) ||
         IsSqueezeEvent(InpDonLongTp) || IsSqueezeEvent(InpDonLongSl) ||
         IsSqueezeEvent(InpDonShortTp) || IsSqueezeEvent(InpDonShortSl))
         Print("BİLGİ: Donchian motorunda Squeeze olayları da menüden seçilebilir; renk geçişleri ayrıca hesaplanır.");
      if(InpDonLongEntry != EVENT_NONE && InpDonLongEntry == InpDonShortEntry)
         Print("BİLGİ: LONG ve SHORT giriş sinyali aynı seçilmiş. Aynı mumda iki olay oluşursa LONG önceliklidir.");
      if(InpDonLongTp != EVENT_NONE && InpDonLongTp == InpDonLongSl)
         Print("UYARI: LONG TP ve LONG SL sinyali aynı seçilmiş; aynı mumda TP öncelikli olur.");
      if(InpDonShortTp != EVENT_NONE && InpDonShortTp == InpDonShortSl)
         Print("UYARI: SHORT TP ve SHORT SL sinyali aynı seçilmiş; aynı mumda TP öncelikli olur.");
      if(InpDonTpSignalCount <= 0 && InpDonSlSignalCount <= 0 &&
         InpFixedTakeProfitPoints <= 0 && InpFixedStopLossPoints <= 0)
         Print("UYARI: Donchian TP/SL sayıları 0 ve sabit TP/SL kapalı; pozisyonlar sinyal sayımıyla kapanmaz.");
     }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetAsyncMode(false);
   trade.SetTypeFillingBySymbol(_Symbol);

   g_object_prefix = StringFormat("SQZLB_%I64u_%s_%s_",
                                  InpMagicNumber, _Symbol, EnumToString(g_timeframe));
   g_last_bar_time = iTime(_Symbol, g_timeframe, 0);

   // Otomatik sıfırlama referansı: robotun başladığı andaki bakiye
   g_reset_start_balance = FlatReferenceBalance();
   g_reset_hold          = false;

   EventSetTimer(1);
   PrintFormat("EA hazır: %s TF=%s BB=%d/%.2f KC=%d/%.2f TrueRange=%s | TP=%d sinyal SL=%d sinyal | ters işlem=%s",
               _Symbol, EnumToString(g_timeframe),
               InpBBLength, InpBBMultFactor, InpKCLength, InpKCMultFactor,
               (InpUseTrueRange ? "true" : "false"),
               InpTakeProfitSignalCount, InpStopLossSignalCount,
               (InpReverseTrading ? "true" : "false"));
   PrintFormat("Sinyal geçişleri: BUY: %s | SELL: %s",
               TransitionText(InpBuyFromColor, InpBuyToColor),
               TransitionText(InpSellFromColor, InpSellToColor));
   PrintFormat("Gösterge: LazyBear Pine birebir | BB sapma çarpanı=%s (%.2f) | KC çarpanı=%.2f | TrueRange=%s",
               (InpPineExactBB ? "KC MultFactor" : "BB MultFactor"),
               (InpPineExactBB ? InpKCMultFactor : InpBBMultFactor),
               InpKCMultFactor, (InpUseTrueRange ? "true" : "false"));
   if(!InpPineExactBB && MathAbs(InpBBMultFactor - InpKCMultFactor) > 1.0e-10)
      Print("NOT: InpPineExactBB=false. Pine kodunda BB sapması KC MultFactor ile hesaplanır; ",
            "bu ayarda sıkışma göstergesi Pine'dan farklı görünebilir (momentum ve sinyaller etkilenmez).");
   if(InpAutoResetEnabled && InpAutoResetLevel > 0.0)
      PrintFormat("Otomatik sıfırlama: %s | eşik=%.2f | referans bakiye=%.2f",
                  ResetModeName(InpAutoResetMode), InpAutoResetLevel, g_reset_start_balance);
   else
      Print("Otomatik sıfırlama: kapalı");
   if(InpBalanceEnabled && InpBalanceMaxGap >= 1)
      PrintFormat("Pozisyon dengeleme: açık | maksimum long/short farkı=%d | tek sinyalde telafi sınırı=%s",
                  InpBalanceMaxGap,
                  (InpBalanceMaxBatch > 0 ? IntegerToString(InpBalanceMaxBatch) : "sınırsız"));
   else
      Print("Pozisyon dengeleme: kapalı (her sinyal tek pozisyon açar)");
   PrintFormat("Sinyal motoru: %s", EngineName(InpSignalEngine));
   if(InpSignalEngine == ENGINE_DONCHIAN)
     {
      PrintFormat("Donchian Trend Ranges: length=%d mult=%.2f con=%d atr=%d",
                  InpDonLength, InpDonMult, InpDonCon, InpDonAtrLength);
      PrintFormat("Donchian eşleme: LONG giriş=%s | SHORT giriş=%s | LONG TP=%s / SL=%s | SHORT TP=%s / SL=%s | TP sayısı=%d | SL sayısı=%d",
                  EventName(InpDonLongEntry), EventName(InpDonShortEntry),
                  EventName(InpDonLongTp), EventName(InpDonLongSl),
                  EventName(InpDonShortTp), EventName(InpDonShortSl),
                  InpDonTpSignalCount, InpDonSlSignalCount);
      PrintFormat("Donchian çıkış filtresi: TP yalnızca kârda=%s | SL yalnızca zararda=%s",
                  (InpDonTpOnlyInProfit ? "evet" : "hayır"),
                  (InpDonSlOnlyInLoss ? "evet" : "hayır"));
     }
   else
      Print("Donchian motoru: kapalı (Squeeze renk geçişleri kullanılıyor). Donchian menüleri yalnızca motor Donchian iken geçerlidir.");

   if(InpEscortEnabled)
     {
      PrintFormat("HTF taşıma: AÇIK | kapsam=%s | %s -> %s | eşik=%s | HTF çıkış TP=%d / SL=%d sinyal | sabit TP=%d / SL=%d point | maks süre=%s | para SL=%s",
                  EscortModeName(InpEscortMode), EnumToString(g_timeframe), EnumToString(g_escort_tf),
                  EscortThresholdText(), InpEscortTpSignalCount, InpEscortSlSignalCount,
                  InpEscortFixedTpPoints, InpEscortFixedSlPoints,
                  (InpEscortMaxRideHours > 0 ? StringFormat("%d saat", InpEscortMaxRideHours) : "kapalı"),
                  (InpEscortStopLossMoney > 0.0 ? StringFormat("%.2f", InpEscortStopLossMoney) : "kapalı"));
      PrintFormat("Taşıma detayı: sayım başlangıcı=%s | eski sabit seviyeleri temizle=%s | taşınan yönde yeni pozisyon=%s",
                  (InpEscortAnchor == SQZ_ESCORT_ANCHOR_ENTRY ? "pozisyon açılışı" : "taşıma anı"),
                  (InpEscortClearOldExits ? "evet" : "hayır"),
                  (InpEscortBlockSameSide ? "kapalı" : "serbest"));
     }
   else
      Print("HTF taşıma: kapalı (yaşlanan pozisyon hızlı TF kurallarıyla yönetilir)");

   if(InpEscortEnabled && InpHarvestEnabled)
     {
      PrintFormat("Hasat: AÇIK | lot=%s | maks pozisyon=%s | para TP=%s / SL=%s | TP sinyal=%d / SL sinyal=%d | süre=%s | kısmi kâr=%s",
                  (InpHarvestLot > 0.0 ? StringFormat("%.2f", InpHarvestLot) : "normal lot"),
                  (InpHarvestMaxPositions > 0 ? IntegerToString(InpHarvestMaxPositions) : "sınırsız"),
                  (InpHarvestTakeProfitMoney > 0.0 ? StringFormat("%.2f", InpHarvestTakeProfitMoney) : "kapalı"),
                  (InpHarvestStopLossMoney > 0.0 ? StringFormat("%.2f", InpHarvestStopLossMoney) : "kapalı"),
                  InpHarvestTpSignalCount, InpHarvestSlSignalCount,
                  (InpHarvestMaxLifeMinutes > 0 ? StringFormat("%d dk", InpHarvestMaxLifeMinutes) : "kapalı"),
                  (InpHarvestTrimEnabled
                     ? StringFormat("%.0f%% / %.2f kâr birikimi", InpHarvestTrimPercent, InpHarvestTrimProfit)
                     : "kapalı"));
     }
   else
      Print("Hasat: kapalı");

   Print("Sinyaller yalnızca kapanmış mumlarda değerlendirilir. Açılışta geçmişe dönük sinyal işlenmez.");
   UpdateChartInfo();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(InpDeleteArrowsOnExit)
      DeleteOwnObjects();
   Comment("");
  }

void OnTick()
  {
   CheckAutoReset();
   CheckNewBar();
   ManageEscortAndHarvest();
   UpdateChartInfo();
  }

void OnTimer()
  {
   CheckAutoReset();
   CheckNewBar();
   ManageEscortAndHarvest();
   UpdateChartInfo();
  }

double OnTester()
  {
   // Strategy Tester optimizasyonunda net kârı sırala.
   return TesterStatistics(STAT_PROFIT);
  }
//+------------------------------------------------------------------+
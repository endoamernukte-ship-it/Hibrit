//==============================================================================
//|
//|  ***  DERLENECEK TEK DOSYA BUDUR  ***
//|
//|  Bu dosya KENDI KENDINE YETERLIDIR: hicbir .mqh dosyasina ihtiyac
//|  duymaz (7 modul icine gomuludur). Tek dis bagimlilik standart
//|  kutuphane olan  #include <Trade/Trade.mqh>  dir.
//|
//|  ONEMLI: MQL5\Experts klasorunde ApexCombatEngine.mq5,
//|  ApexCombatEngine (1).mq5, (2), (3) ... gibi ESKI KOPYALAR ile
//|  ApexTypes.mqh / ApexTrade.mqh / ... gibi .mqh dosyalari varsa
//|  SILIN. Onlar moduler kaynak surumudur ve yanlarinda .mqh
//|  dosyalari olmadan DERLENMEZ ('file not found' hatasi verir).
//|
//|  Kaynak: Source/ klasorundedir (gelistirme icin).
//|  Bu dosyayi duzenlemeyin; Source icindeki modulleri degistirip
//|  `python3 Source/Tools/build_single_file.py` ile yeniden uretin.
//|
//==============================================================================

//------------------------------------------------------------------------------
//  Asagidaki kisim Source/ApexCombatEngine.mq5 basligidir.
//------------------------------------------------------------------------------
//+------------------------------------------------------------------+
//|                                            ApexCombatEngine.mq5   |
//|           APEX COMBAT ENGINE - Hibrit Algoritmik Savas Makinesi   |
//|                                                                  |
//|  Cekirdek: Squeeze Momentum [LazyBear] (orijinal mantik korunur)  |
//|  Mimari : 5 boyutlu rejim state machine + elastik bukalemun grid  |
//|           + mikro-scalp motoru + delta-notr savunma kalkani       |
//|           + kendini onaran risk guvenlik duvari                   |
//|                                                                  |
//|  MODUL HARITASI (tum dosyalar bu .mq5 ile AYNI duz klasordedir)    |
//|   ApexTypes.mqh       : tipler, sabitler, yardimcilar             |
//|   ApexTrade.mqh       : yurutme + rol etiketli defter             |
//|   ApexSqueezeCore.mqh : LazyBear cekirdegi + turevler             |
//|   ApexAnalytics.mqh   : 5 boyutlu rejim analizi                   |
//|   ApexGrid.mqh        : elastik grid + mod evrimi                 |
//|   ApexScalp.mqh       : mikro-scalp + hedge kalkani               |
//|   ApexRisk.mqh        : sermaye koruma guvenlik duvari            |
//|                                                                  |
//|  ONEMLI: MetaEditor tırnakli include'larda alt klasorlu goreli    |
//|  yolu guvenilir bicimde cozmez ("file not found"). Bu yuzden      |
//|   DERLEMEYE HAZIR SURUM = ApexCombatEngine_SingleFile.mq5         |
//|   (Tools/build_single_file.py ile uretilir; hicbir .mqh gerektir- |
//|    mez, tek basina MQL5/Experts/ icine atilip derlenir).          |
//|                                                                  |
//|  "MULTI-THREAD" NOTU: MQL5 EA'lar tek is parcacikli calisir.      |
//|  Bu motor gercek thread acmaz; bunun yerine cooperative (isbirlik-
//|  ci) zaman dilimli gorev mimarisi kullanir:                       |
//|    G0 tick  (ms erteleme)  : mikro-scalp + savunma + akilli cikis |
//|    G1 bar   (yeni mum)     : rejim tespiti + grid + cekirdek      |
//|    G2 sn    (mutabakat)    : defter/emir senkronizasyonu          |
//|    G3 olay  (OnTrade*)     : dolum sonrasi iyilestirme            |
//|  Boylece yuksek frekansli motor ile bar bazli motor ayni thread   |
//|  icinde birbirini bloke etmeden eszamanli gibi calisir.           |
//+------------------------------------------------------------------+
#property copyright "Apex Combat Engine"
#property version   "2.00"
#property strict
#property description "Squeeze Momentum [LazyBear] cekirdekli hibrit algoritmik savas makinesi"

input group "0) Temel ayarlar"
input ulong  InpMagicNumber        = 20261107;  // Magic Number
input int    InpDeviationPoints    = 20;        // Maksimum sapma (point)
input bool   InpRequireHedging     = true;      // Hedging hesap zorunlu (grid + kilit icin)
input bool   InpShowPanel          = true;      // Grafikte bilgi paneli
input bool   InpDrawArrows         = true;      // Sinyal oklari
input bool   InpDeleteArrowsOnExit = true;      // Cikista oklari sil
input bool   InpVerboseLog         = false;     // Ayrintili log
input group "1) Squeeze Momentum [LazyBear]"
input ENUM_TIMEFRAMES InpTimeframe       = PERIOD_CURRENT; // Sinyal zaman dilimi
input ENUM_TIMEFRAMES InpContextTimeframe= PERIOD_H1;      // Baglam (ust TF) - Hurst/ATR icin
input ENUM_TIMEFRAMES InpScalpTimeframe  = PERIOD_M1;      // Mikro-scalp zaman dilimi
input int    InpBBLength           = 20;      // BB Length
input double InpBBMultFactor       = 2.0;     // BB MultFactor
input int    InpKCLength           = 20;      // KC Length
input double InpKCMultFactor       = 1.5;     // KC MultFactor
input bool   InpUseTrueRange       = true;    // Use TrueRange (KC)
input int    InpHistoryBars        = 3000;    // Taranacak maksimum mum
input group "2) Cekirdek sinyal ve ters islem"
input bool   InpReverseTrading     = false; // TERS ISLEM: BUY sinyali SELL acar
input bool   InpOpenOnBuySignal    = true;  // BUY sinyalinde islem ac
input bool   InpOpenOnSellSignal   = true;  // SELL sinyalinde islem ac
input bool   InpAllowLongTrades    = true;  // BUY pozisyona izin
input bool   InpAllowShortTrades   = true;  // SELL pozisyona izin
input int    InpTPSignalCount      = 3;     // TP: giris yonunde kacinci sinyal (0 = kapali)
input int    InpSLSignalCount      = 3;     // SL: ters yonde kacinci sinyal (0 = kapali)
input int    InpFixedTPPoints      = 0;     // Ek sabit TP (point) - 0 = kapali
input int    InpFixedSLPoints      = 0;     // Ek sabit SL (point) - 0 = kapali
input double InpBaseLot            = 0.01;  // Temel lot
input int    InpMaxCorePositions   = 2;     // Maks. cekirdek pozisyon
input int    InpMaxSpreadPoints    = 0;     // Maks spread (point) - 0 = kapali
input group "3) Rejim analizi (5 boyut)"
input int    InpHurstWindow        = 160;   // Hurst penceresi (bar)
input int    InpHurstMaxLag        = 20;    // Hurst maks gecikme
input double InpHurstTrend         = 0.56;  // H > bu deger = trend kalici
input double InpHurstMeanRevert    = 0.46;  // H < bu deger = ortalamaya donus
input int    InpATRPeriod          = 14;    // ATR periyodu
input int    InpATRBandLen         = 120;   // ATR bandi referans uzunlugu
input double InpATRzExpansion      = 0.85;  // ATR z: genisleme esigi
input double InpATRzExplosive      = 1.90;  // ATR z: patlayici esik
input int    InpVPLookback         = 120;   // Hacim profili penceresi
input int    InpVPBuckets          = 48;    // Hacim profili kova sayisi
input double InpValueAreaPct       = 0.70;  // Deger alani yuzdesi
input int    InpDerivLen           = 3;     // Momentum turev penceresi
input int    InpRegimeMargin       = 12;    // Rejim degisim esigi (skor farki)
input int    InpRegimePersistence  = 2;     // Rejim degisimi icin min. bar
input int    InpBootBars           = 40;    // Isinma bar sayisi
input group "4) Elastik bukalemun grid"
input bool   InpGridEnabled        = true;  // Grid motoru aktif
input int    InpGridMaxLevels      = 5;     // Yon basina maks. seviye
input double InpGridStepATRMult    = 0.85;  // Adim = ATR x carpan
input double InpGridMinMult        = 0.60;  // Elastik daralma tabani
input double InpGridMaxMult        = 2.20;  // Elastik genisleme tavani
input double InpGridLotSlope       = 0.06;  // Seviye basina lot egimi (ANTI-martingal)
input double InpGridLotMaxMult     = 1.60;  // Lot tavani (temel lotun kati)
input double InpGridRecenterATR    = 3.00;  // Merkez yeniden kurma esigi (ATR)
input double InpGridBasketATR      = 1.20;  // Sepet hedefi (ATR cinsinden)
input double InpGridBasketEqPct    = 0.35;  // Sepet hedefi (equity %)
input int    InpGridMaxLegs        = 8;     // Toplam maks. grid bacagi
input double InpGridCutRatio       = 1.00;  // Ters bacak kesme orani (0..1)
input double InpGridTPATR          = 1.00;  // Bacak TP (ATR x)
input double InpGridSLATR          = 4.00;  // Bacak SL (ATR x)
input group "5) Mikro-scalp motoru"
input bool   InpScalpEnabled       = true;  // Mikro-scalp aktif
input double InpScalpLotMult       = 1.50;  // Lot carpani (temel lot uzerine)
input int    InpScalpTPPoints      = 0;     // TP (point) - 0 = ATR tabanli
input int    InpScalpSLPoints      = 0;     // SL (point) - 0 = ATR tabanli
input int    InpScalpMaxOpen       = 2;     // Ayni anda maks. mikro islem
input int    InpScalpCooldownSec   = 45;    // Islemler arasi soguma (sn)
input int    InpScalpPivot         = 2;     // Mikro-pivot yaricapi (bar)
input double InpScalpPullbackATR   = 0.60;  // Kovalamama mesafesi (ATR)
input int    InpScalpMaxBars       = 12;    // Mikro islemde maks. bar (scalp TF)
input group "6) Savunma kilidi ve hedge kalkani"
input double InpHedgeRatio         = 1.00;  // Net pozisyonun kacina kalkan (1 = tam notr)
input int    InpLockCooldownBars   = 20;    // Kilit minimum sure (bar)
input double InpUnlockRecovery     = 0.35;  // Kilit acmak icin DD iyilesmesi (yuzde puan)
input double InpHedgeMaxLossPct    = 1.50;  // Kalkan zarar tavani (equity %)
input bool   InpAllowFullLiquidation = true;// Kill-switch'te tam tasfiye
input group "7) Risk guvenlik duvari"
input double InpRiskPerTrade       = 0.50;  // Isleme basina risk (equity %)
input double InpMaxLot             = 1.00;  // Mutlak lot tavani
input double InpMaxTotalLots       = 2.00;  // Toplam acik pozisyon lot tavani
input double InpDDWarn             = 4.00;  // AMBER kademe (DD %)
input double InpDDDefense          = 7.00;  // RED kademe - savunma kilidi (DD %)
input double InpDDKill             = 12.00; // BLACK kademe - kill-switch (DD %)
input double InpDailyLossLimit     = 3.00;  // Gunluk zarar limiti (equity %)
input double InpDailyProfitTarget  = 0.00;  // Gunluk kâr hedefi (equity %, 0 = kapali)
input double InpHealRate           = 0.05;  // Risk kapasitesi iyilesme hizi
input double InpToxicityDecay      = 0.01;  // Toksisite sönüm hizi
input group "8) Oturum ve gorev zamanlamasi"
input bool   InpUseSession         = false; // Oturum filtresi
input int    InpSessionStartHour   = 8;     // Baslangic saati (sunucu)
input int    InpSessionEndHour     = 20;    // Bitis saati (sunucu)
input int    InpFridayCloseHour    = 19;    // Cuma kapanis saati
input int    InpTickThrottleMs     = 250;   // Tick motoru ertelemesi (ms)
input int    InpReconcileSec       = 20;    // Defter mutabakat araligi (sn)

//==============================================================================
//| MODUL: ApexTypes.mqh
//==============================================================================
//+------------------------------------------------------------------+
//|                                                     ApexTypes.mqh |
//|        APEX COMBAT ENGINE - ortak tipler, sabitler, yardimcilar   |
//|                                                                  |
//|  Katman 0 (Foundation). Tum moduller bu dosyayi kullanir.        |
//|  Bilinçli kisitlar (MQL5 derleyici guvenligi):                   |
//|   * struct'lar saf veri tasir (metod/kurucu yok)                  |
//|   * struct icinde dinamik dizi yok                                |
//|   * enum <-> int donusumleri her zaman acik cast ile yapilir      |
//+------------------------------------------------------------------+
#ifndef __APEX_TYPES_MQH__
#define __APEX_TYPES_MQH__ 1

//+------------------------------------------------------------------+
//| REJIM UZAYI (State Machine durumlari)                             |
//+------------------------------------------------------------------+
enum E_APEX_REGIME
  {
   REGIME_BOOT            = 0, // Isinma: istatistikler henuz olgunlasmadi
   REGIME_ACCUMULATION    = 1, // STATE_ACCUMULATION   - gizli toplanma
   REGIME_BREAKOUT_ATTACK = 2, // STATE_BREAKOUT_ATTACK- mizrak modu
   REGIME_MEAN_REVERSION  = 3, // STATE_MEAN_REVERSION - cift yonlu grid
   REGIME_VOLATILITY_TRAP = 4, // STATE_VOLATILITY_TRAP- fakeout avcisi
   REGIME_DEFENSE_LOCK    = 5  // STATE_DEFENSE_LOCK   - siper modu
  };

// Grid'in evrim gecirdigi operasyonel modlar (rejim -> mod donusumu)
enum E_APEX_GRID_MODE
  {
   GRID_MODE_STEALTH     = 0, // Gizli toplanma: genis aralik, kucuk lot
   GRID_MODE_TREND_RIDER = 1, // Tek yonlu agresif trend binicisi
   GRID_MODE_HEDGED      = 2, // Cift yonlu elastik mean-reversion gridi
   GRID_MODE_FORTRESS    = 3, // Volatilite tuzagi: daralmis, onayli
   GRID_MODE_FROZEN      = 4  // Savunma kilidi: yeni bacak yok
  };

// Sistemin genel savas durusu (panel ve loglama icin)
enum E_APEX_POSTURE
  {
   POSTURE_PEACE    = 0,
   POSTURE_SKIRMISH = 1,
   POSTURE_ATTACK   = 2,
   POSTURE_SHIELD   = 3,
   POSTURE_RETREAT  = 4
  };

// Pozisyon/emir rolleri - her bilet bir rol tasir (oto-iyilestirme icin)
enum E_APEX_ROLE
  {
   ROLE_CORE  = 0, // Orijinal Squeeze Momentum sinyal pozisyonu
   ROLE_GRID  = 1, // Elastik grid bacagi
   ROLE_SCALP = 2, // Mikro-scalp pozisyonu
   ROLE_HEDGE = 3, // Savunma kilidi / delta-notr kalkan
   ROLE_UNKNOWN = 4
  };

// Hurst sureklilik sinifi
enum E_APEX_PERSIST
  {
   PERSIST_MEAN_REVERT = -1,
   PERSIST_RANDOM      =  0,
   PERSIST_TREND       =  1
  };

// ATR volatilite bandi
enum E_APEX_VOLBAND
  {
   VOLBAND_CRUSH     = 0, // Volatilite ezilmesi (sicakilma oncesi)
   VOLBAND_NORMAL    = 1,
   VOLBAND_EXPANSION = 2,
   VOLBAND_EXPLOSIVE = 3  // Patlayici - fakeout riski
  };

// Fiyatin hacim profiline gore konumu
enum E_APEX_VP_POS
  {
   VP_BELOW_VALUE = -1, // VAL alti: iskontolu / kirilma reddi
   VP_IN_VALUE    =  0, // Deger alani icinde: denge
   VP_ABOVE_VALUE =  1  // VAH ustu: primli / kirilma kabulu
  };

// Grid bacagi yasam dongusu
enum E_APEX_LEG_STATE
  {
   LEG_PLANNED = 0, // Planlandi, emir henuz yok
   LEG_ARMED   = 1, // Bekleyen emir piyasada
   LEG_FILLED  = 2, // Pozisyona donustu
   LEG_DEAD    = 3  // Kapandi/iptal
  };

// Risk seviyesi (sermaye koruma kademeleri)
enum E_APEX_RISK_TIER
  {
   TIER_GREEN  = 0, // Tam kapasite
   TIER_AMBER  = 1, // Kisitli: lot ve bacak sayisi kirpildi
   TIER_RED    = 2, // Savunma kilidi (DEFENSE_LOCK)
   TIER_BLACK  = 3  // Kontrollu geri cekilme / kill-switch
  };

//+------------------------------------------------------------------+
//| 5 BOYUTLU REJIM ANLIK GORUNTUSU                                  |
//| Her alan ya ham olcum ya normalize skordur. Paneller, loglar,    |
//| karar motoru ve backtest telemetrisi tek kaynaktan beslenir.      |
//+------------------------------------------------------------------+
struct SRegimeSnapshot
  {
   int      regime;              // E_APEX_REGIME
   int      prev_regime;         // E_APEX_REGIME
   int      posture;             // E_APEX_POSTURE
   int      bars_in_regime;
   double   confidence;          // 0..1 (kazanan - ikinci) / toplam
   double   score[6];            // her rejim icin ham oy
   int      trend_dir;           // +1 / -1 / 0 (islem yonu onerisi)
   datetime stamp;
   int      valid;               // 0 = istatistikler henuz hazir degil

   // --- D1: Squeeze (basinc / enerji) ---
   int      sqz_state;           // 1=sqzOn 2=sqzOff 3=noSqz
   int      sqz_compress_bars;   // kac bardir sikisma var
   int      bars_since_release;  // son ON->OFF gecisinden beri
   int      release_dir;         // salinim anindaki momentum yonu
   double   sqz_energy;          // 0..1 depolanan enerji
   int      sqz_flicker;         // ON/OFF titreme sayaci (tuzak gostergesi)

   // --- D2: Hurst (trend kaliciligi) ---
   double   hurst;               // 0..1
   int      persistence;         // E_APEX_PERSIST

   // --- D3: ATR volatilite bandi ---
   double   atr;
   double   atr_pct;             // ATR / fiyat
   double   atr_mean;
   double   atr_std;
   double   atr_z;               // normalize band sapmasi
   int      vol_band;            // E_APEX_VOLBAND

   // --- D4: Hacim profili / likidite dagilimi ---
   double   poc;                 // Point of control
   double   vah;                 // Value area high
   double   val;                 // Value area low
   int      vp_pos;              // E_APEX_VP_POS
   double   balance;             // 0..1 hacim merkezilesmesi (denge)
   double   absorption;          // 0..1 akilli para emilim skoru
   double   cvd_slope;           // -1..+1 kumulatif hacim dengesi egimi
   double   vp_skew;             // -1..+1 profil asimetrisi

   // --- D5: Momentum turevi (hiz + ivme) ---
   double   mom;                 // son momentum degeri
   double   mom_z;               // normalize momentum
   double   vel;                 // 1. turev (hiz)
   double   vel_z;
   double   accel;               // 2. turev (ivme)
   double   accel_z;
   double   flip_rate;           // 0..1 momentum isaret degisim sikligi
   int      fatigue;             // 1 = momentum yorgun (akilli cikis)
   int      vel_zero_cross;      // 1 = hiz sifir gecisi (tepede donus)
   int      mom_dir;             // +1 / -1 / 0

   // --- Bilesik ---
   double   elasticity;          // grid araligi carpani
   double   composite_heat;      // 0..1 piyasa isisi
  };

//+------------------------------------------------------------------+
//| CALISMA ZAMANI KONFIGURASYONU (input'lardan tek seferde dolar)   |
//+------------------------------------------------------------------+
struct SApexConfig
  {
   string   symbol;
   string   tf_signal_name;
   string   tf_context_name;
   string   tf_scalp_name;
   ENUM_TIMEFRAMES tf_signal;
   ENUM_TIMEFRAMES tf_context;
   ENUM_TIMEFRAMES tf_scalp;
   ulong    magic;
   int      deviation;

   // --- Squeeze Momentum (LazyBear) ---
   int      bb_len;
   double   bb_mult;
   int      kc_len;
   double   kc_mult;
   bool     use_true_range;
   int      history_bars;

   // --- Orijinal cekirdek sinyal mantigi ---
   bool     reverse;
   bool     open_buy;
   bool     open_sell;
   bool     allow_long;
   bool     allow_short;
   int      tp_sig_count;
   int      sl_sig_count;
   int      fixed_tp_points;
   int      fixed_sl_points;
   double   base_lot;
   int      max_positions;
   int      max_spread_points;

   // --- Analitik ---
   int      hurst_window;
   int      hurst_max_lag;
   int      atr_period;
   int      atr_band_len;
   int      vp_lookback;
   int      vp_buckets;
   double   va_pct;
   int      deriv_len;
   double   hurst_trend;
   double   hurst_mr;
   double   atr_z_expansion;
   double   atr_z_explosive;
   int      regime_margin;
   int      regime_persistence;
   int      boot_bars;

   // --- Elastik grid ---
   bool     grid_enabled;
   int      grid_max_levels;
   double   grid_step_atr_mult;
   double   grid_step_min_mult;
   double   grid_step_max_mult;
   double   grid_lot_slope;
   double   grid_lot_max_mult;
   double   grid_recenter_atr;
   double   grid_basket_atr;
   double   grid_basket_equity;
   int      grid_max_legs_total;
   double   grid_cut_ratio;
   double   grid_tp_atr;
   double   grid_sl_atr;

   // --- Mikro scalp ---
   bool     scalp_enabled;
   double   scalp_lot_mult;
   int      scalp_tp_points;
   int      scalp_sl_points;
   int      scalp_max_open;
   int      scalp_cooldown_sec;
   int      scalp_pivot;
   double   scalp_pullback_atr;
   int      scalp_max_bars;

   // --- Savunma / hedge ---
   double   hedge_ratio;
   int      lock_cooldown_bars;
   double   unlock_recovery;
   double   hedge_max_loss_pct;
   bool     allow_full_liquidation;

   // --- Risk firewall ---
   double   risk_per_trade_pct;
   double   max_lot;
   double   max_total_lots;
   double   max_margin_pct;
   double   dd_warn;
   double   dd_defense;
   double   dd_kill;
   double   daily_loss_limit;
   double   daily_profit_target;
   int      max_consec_loss;
   double   heal_rate;
   double   toxicity_decay;
   int      max_spread_atr_pct;

   // --- Operasyon ---
   bool     use_session;
   int      session_start_hour;
   int      session_end_hour;
   int      friday_close_hour;
   int      tick_throttle_ms;
   int      reconcile_sec;
   bool     show_panel;
   bool     draw_objects;
   bool     verbose_log;
  };

//+------------------------------------------------------------------+
//| ELASTIK GRID BACAGI                                              |
//+------------------------------------------------------------------+
struct SGridLevel
  {
   int      level;      // 0 = merkez, +n = ust, -n = alt
   int      side;       // +1 BUY bacagi, -1 SELL bacagi
   int      state;      // E_APEX_LEG_STATE
   double   price;      // planlanan / tetiklenen fiyat
   double   lot;
   double   sl;
   double   tp;
   ulong    order_ticket;
   ulong    pos_ticket;
   datetime stamp;
  };

//+------------------------------------------------------------------+
//| POZISYON DEFTERI KAYDI (self-healing mutabakat icin)             |
//+------------------------------------------------------------------+
struct SBookEntry
  {
   ulong    ticket;
   int      role;       // E_APEX_ROLE
   int      side;       // +1 / -1
   int      level;
   double   lot;
   double   entry;
   double   sl;
   double   tp;
   double   profit;
   double   swap;
   datetime time;
  };

//+------------------------------------------------------------------+
//| Skaler yardimcilar                                               |
//+------------------------------------------------------------------+
double ApexClamp(const double v, const double lo, const double hi)
  {
   if(v < lo) return lo;
   if(v > hi) return hi;
   return v;
  }

double ApexSaturate(const double v)
  {
   return ApexClamp(v, 0.0, 1.0);
  }

int ApexSign(const double v)
  {
   if(v > 0.0) return 1;
   if(v < 0.0) return -1;
   return 0;
  }

double ApexSafeDiv(const double a, const double b, const double fallback)
  {
   if(b == 0.0 || !MathIsValidNumber(b))
      return fallback;
   double r = a / b;
   if(!MathIsValidNumber(r))
      return fallback;
   return r;
  }

double ApexZScore(const double v, const double mean, const double std)
  {
   if(std <= 1.0e-12)
      return 0.0;
   return (v - mean) / std;
  }

// 0..1 arasina lineer esleme (min-max normalizasyonu)
double ApexNormRange(const double v, const double lo, const double hi)
  {
   if(hi - lo <= 1.0e-12)
      return 0.0;
   return ApexSaturate((v - lo) / (hi - lo));
  }

//+------------------------------------------------------------------+
//| Rol / yon etiketleri                                             |
//+------------------------------------------------------------------+
string ApexRegimeName(const int regime)
  {
   switch((E_APEX_REGIME)regime)
     {
      case REGIME_BOOT:            return "BOOT (isinma)";
      case REGIME_ACCUMULATION:    return "STATE_ACCUMULATION";
      case REGIME_BREAKOUT_ATTACK: return "STATE_BREAKOUT_ATTACK";
      case REGIME_MEAN_REVERSION:  return "STATE_MEAN_REVERSION_GRID";
      case REGIME_VOLATILITY_TRAP: return "STATE_VOLATILITY_TRAP";
      case REGIME_DEFENSE_LOCK:    return "STATE_DEFENSE_LOCK";
     }
   return "BILINMIYOR";
  }

string ApexRegimeShort(const int regime)
  {
   switch((E_APEX_REGIME)regime)
     {
      case REGIME_BOOT:            return "BOOT";
      case REGIME_ACCUMULATION:    return "ACC ";
      case REGIME_BREAKOUT_ATTACK: return "ATCK";
      case REGIME_MEAN_REVERSION:  return "MRG ";
      case REGIME_VOLATILITY_TRAP: return "TRAP";
      case REGIME_DEFENSE_LOCK:    return "LOCK";
     }
   return "????";
  }

string ApexPostureName(const int posture)
  {
   switch((E_APEX_POSTURE)posture)
     {
      case POSTURE_PEACE:    return "BARIŞ";
      case POSTURE_SKIRMISH: return "ÇATIŞMA";
      case POSTURE_ATTACK:   return "TAARRUZ";
      case POSTURE_SHIELD:   return "KALKAN";
      case POSTURE_RETREAT:  return "GERİ ÇEKİLME";
     }
   return "-";
  }

string ApexGridModeName(const int mode)
  {
   switch((E_APEX_GRID_MODE)mode)
     {
      case GRID_MODE_STEALTH:     return "STEALTH (gizli)";
      case GRID_MODE_TREND_RIDER: return "TREND RIDER (mizrak)";
      case GRID_MODE_HEDGED:      return "HEDGED GRID (çift yön)";
      case GRID_MODE_FORTRESS:    return "FORTRESS (tuzak avı)";
      case GRID_MODE_FROZEN:      return "FROZEN (kilitli)";
     }
   return "-";
  }

string ApexVolBandName(const int band)
  {
   switch((E_APEX_VOLBAND)band)
     {
      case VOLBAND_CRUSH:     return "EZİLME";
      case VOLBAND_NORMAL:    return "NORMAL";
      case VOLBAND_EXPANSION: return "GENİŞLEME";
      case VOLBAND_EXPLOSIVE: return "PATLAYICI";
     }
   return "-";
  }

string ApexRoleName(const int role)
  {
   switch((E_APEX_ROLE)role)
     {
      case ROLE_CORE:     return "ÇEKİRDEK";
      case ROLE_GRID:     return "GRİD";
      case ROLE_SCALP:    return "SCALP";
      case ROLE_HEDGE:    return "HEDGE";
      case ROLE_UNKNOWN:  return "BİLİNMEYEN";
     }
   return "-";
  }

string ApexSideName(const int side)
  {
   if(side > 0) return "BUY";
   if(side < 0) return "SELL";
   return "-";
  }

string ApexTierName(const int tier)
  {
   switch((E_APEX_RISK_TIER)tier)
     {
      case TIER_GREEN: return "GREEN";
      case TIER_AMBER: return "AMBER";
      case TIER_RED:   return "RED (kilit)";
      case TIER_BLACK: return "BLACK (geri çekilme)";
     }
   return "-";
  }

//+------------------------------------------------------------------+
//| Bilet etiketi: broker yorumu 27 karakterle sinirli oldugu icin   |
//| sabit uzunlukta kompakt kod kullanilir.                          |
//|   "APX" + rol(C/G/S/H) + yon(B/S) + seviye(+00..+99)             |
//| Bu etiket sayesinde EA kapatilip acilsa bile her pozisyonun      |
//| rolu, yonu ve grid seviyesi yeniden ayiklanabilir (self-healing).|
//+------------------------------------------------------------------+
string ApexEncodeTag(const int role, const int side, const int level)
  {
   string r = "U";
   if(role == ROLE_CORE)        r = "C";
   else if(role == ROLE_GRID)   r = "G";
   else if(role == ROLE_SCALP)  r = "S";
   else if(role == ROLE_HEDGE)  r = "H";

   string s = (side > 0 ? "B" : "S");

   int    a   = (int)MathAbs(level);
   string num = IntegerToString(a);
   if(a < 10)
      num = "0" + num;
   string lvl = (level >= 0 ? "+" : "-") + num;
   if(StringLen(lvl) > 3)
      lvl = (level >= 0 ? "+99" : "-99");

   return "APX" + r + s + lvl;
  }

bool ApexDecodeTag(const string tag, int &role, int &side, int &level)
  {
   role  = (int)ROLE_UNKNOWN;
   side  = 0;
   level = 0;
   if(StringLen(tag) < 8)
      return false;
   if(StringSubstr(tag, 0, 3) != "APX")
      return false;

   string rc = StringSubstr(tag, 3, 1);
   if(rc == "C")      role = (int)ROLE_CORE;
   else if(rc == "G") role = (int)ROLE_GRID;
   else if(rc == "S") role = (int)ROLE_SCALP;
   else if(rc == "H") role = (int)ROLE_HEDGE;
   else               role = (int)ROLE_UNKNOWN;

   string sc = StringSubstr(tag, 4, 1);
   if(sc == "B")      side = 1;
   else if(sc == "S") side = -1;
   else               side = 0;

   level = (int)StringToInteger(StringSubstr(tag, 5, 3));
   return true;
  }

//+------------------------------------------------------------------+
//| Global state icin kalici degisken adi (sembol + magic bazli)     |
//| EA yeniden baslatildiginda zirve equity / kilit sayaçlari        |
//| buradan geri yuklenir.                                           |
//+------------------------------------------------------------------+
string ApexGVName(const string symbol, const ulong magic, const string key)
  {
   return StringFormat("APEX_%I64u_%s_%s", magic, symbol, key);
  }

#endif
//+------------------------------------------------------------------+

//==============================================================================
//| MODUL: ApexTrade.mqh
//==============================================================================
//+------------------------------------------------------------------+
//|                                                     ApexTrade.mqh |
//|  APEX COMBAT ENGINE - Katman 1: Yurutme (Execution) + Defter      |
//|                                                                  |
//|  Tum broker etkilesimi tek bir sinifta toplanir:                  |
//|   * fiyat/lot normalizasyonu ve stops-level guvenlik boslugu      |
//|   * spread / freeze / marjin on kontrolleri                       |
//|   * rol + seviye etiketli emir ve pozisyon defteri                |
//|   * hata sonrasi geri cekilmeli yeniden deneme (self-healing)     |
//|   * yeniden baslatmada defterin biletlerden yeniden insasi        |
//+------------------------------------------------------------------+
#ifndef __APEX_TRADE_MQH__
#define __APEX_TRADE_MQH__ 1

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Yurutme motoru                                                   |
//+------------------------------------------------------------------+
class CApexExecution
  {
private:
   CTrade            m_trade;
   string            m_symbol;
   ulong             m_magic;
   int               m_deviation;
   int               m_digits;
   double            m_point;
   double            m_tick;
   double            m_lot_min;
   double            m_lot_max;
   double            m_lot_step;
   double            m_point_value;
   long              m_stops_level;
   long              m_freeze_level;
   double            m_min_stop_dist;
   bool              m_ready;
   int               m_error_streak;
   datetime          m_last_error_time;
   SBookEntry        m_book[];
   string            m_last_error;

   // --- yardimcilar ---
   double            MinStopDistance()
     {
      return MathMax((double)m_stops_level, (double)m_freeze_level) * m_point + m_tick;
     }

   // Gecici (sunucu/fiyat kaynakli) hatalar: geri cekilmeli yeniden deneme
   bool              RetryableError(const uint code)
     {
      return (code == TRADE_RETCODE_REQUOTE         ||
              code == TRADE_RETCODE_PRICE_OFF       ||
              code == TRADE_RETCODE_TIMEOUT         ||
              code == TRADE_RETCODE_PRICE_CHANGED   ||
              code == TRADE_RETCODE_TOO_MANY_REQUESTS ||
              code == TRADE_RETCODE_CONNECTION);
     }

   void              NoteError(const string where, const bool ok)
     {
      if(ok)
        {
         m_error_streak = 0;
         m_last_error   = "";
         return;
        }
      m_error_streak++;
      m_last_error_time = TimeCurrent();
      m_last_error = StringFormat("%s | retcode=%u (%s)", where,
                                  m_trade.ResultRetcode(),
                                  m_trade.ResultRetcodeDescription());
      PrintFormat("[APEX:EXEC] HATA %s (seri=%d)", m_last_error, m_error_streak);
     }

public:
                     CApexExecution() { m_ready = false; m_error_streak = 0; m_last_error_time = 0; m_last_error = ""; }
                    ~CApexExecution() { }

   //+------------------------------------------------------------------+
   bool Init(const SApexConfig &cfg)
     {
      m_symbol   = cfg.symbol;
      m_magic    = cfg.magic;
      m_deviation= cfg.deviation;
      m_point    = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      m_digits   = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      m_tick     = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      m_lot_min  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      m_lot_max  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      m_lot_step = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      m_stops_level  = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
      m_freeze_level = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_FREEZE_LEVEL);

      double tick_value = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_size  = m_tick > 0.0 ? m_tick : m_point;
      m_point_value     = ApexSafeDiv(tick_value, tick_size, 0.0); // 1.0 fiyat birimi basina para/lot

      if(m_point <= 0.0)      m_point = 0.00001;
      if(m_tick  <= 0.0)      m_tick  = m_point;
      if(m_lot_step <= 0.0)   m_lot_step = 0.01;
      if(m_lot_min  <= 0.0)   m_lot_min  = m_lot_step;
      if(m_lot_max  <= 0.0)   m_lot_max  = 100.0;
      m_min_stop_dist = MinStopDistance();

      m_trade.SetExpertMagicNumber(m_magic);
      m_trade.SetDeviationInPoints(m_deviation);
      m_trade.SetAsyncMode(false);
      m_trade.SetTypeFillingBySymbol(m_symbol);

      m_ready = (m_point_value > 0.0);
      ArrayResize(m_book, 0);
      return m_ready;
     }

   string Symbol()      { return m_symbol;   }
   double Point()       { return m_point;    }
   double Tick()        { return m_tick;     }
   int    Digits()      { return m_digits;   }
   double PointValue()  { return m_point_value; }
   double LotMin()      { return m_lot_min;  }
   double LotStep()     { return m_lot_step; }
   double MinStopDist() { return m_min_stop_dist; }
   string LastError()   { return m_last_error; }
   int    ErrorStreak() { return m_error_streak; }

   //+------------------------------------------------------------------+
   //| Fiyat / lot normalizasyonu                                       |
   //+------------------------------------------------------------------+
   double NormPrice(const double price, const int round_dir)
     {
      if(price <= 0.0 || m_tick <= 0.0)
         return NormalizeDouble(price, m_digits);
      double units = price / m_tick;
      if(round_dir > 0)       units = MathCeil(units - 1.0e-10);
      else if(round_dir < 0)  units = MathFloor(units + 1.0e-10);
      else                    units = MathRound(units);
      return NormalizeDouble(units * m_tick, m_digits);
     }

   double NormVolume(const double requested)
     {
      if(m_lot_step <= 0.0)
         return 0.0;
      double v = requested;
      if(m_lot_max > 0.0 && v > m_lot_max)
         v = m_lot_max;
      v = MathFloor(v / m_lot_step + 1.0e-9) * m_lot_step;
      v = NormalizeDouble(v, 8);
      if(v < m_lot_min - 1.0e-10)
         return 0.0;
      return v;
     }

   // Stop seviyelerini broker kisitlarina gore iteleyerek guvenli hale getirir
   bool   SafeStops(const int side, const double entry, double &sl, double &tp)
     {
      double mind = m_min_stop_dist;
      if(sl > 0.0)
        {
         double need = (side > 0) ? (entry - sl) : (sl - entry);
         if(need < mind)
            sl = (side > 0) ? NormPrice(entry - mind, -1) : NormPrice(entry + mind, 1);
        }
      if(tp > 0.0)
        {
         double need = (side > 0) ? (tp - entry) : (entry - tp);
         if(need < mind)
            tp = (side > 0) ? NormPrice(entry + mind, 1) : NormPrice(entry - mind, -1);
        }
      return true;
     }

   //+------------------------------------------------------------------+
   //| Piyasa kosullari                                                 |
   //+------------------------------------------------------------------+
   double SpreadPoints()
     {
      MqlTick tk;
      if(!SymbolInfoTick(m_symbol, tk) || tk.ask <= 0.0)
         return 1.0e9;
      double sp = (tk.ask - tk.bid);
      if(sp <= 0.0)
         sp = (double)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD) * m_point;
      return sp / m_point;
     }

   bool   SpreadOK(const double max_points)
     {
      if(max_points <= 0)
         return true;
      return (SpreadPoints() <= max_points);
     }

   double Ask() { MqlTick tk; if(!SymbolInfoTick(m_symbol, tk)) return 0.0; return tk.ask; }
   double Bid() { MqlTick tk; if(!SymbolInfoTick(m_symbol, tk)) return 0.0; return tk.bid; }

   double MarginLevelPct()
     {
      double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
      double mar = AccountInfoDouble(ACCOUNT_MARGIN);
      if(mar <= 0.0)
         return 9999.0;
      return (eq / mar) * 100.0;
     }

   double FreeMarginPct()
     {
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      double fm = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(eq <= 0.0)
         return 0.0;
      return ApexClamp(fm / eq, 0.0, 1.0);
     }

   //+------------------------------------------------------------------+
   //| Emir gonderimi - rol etiketli, geri cekilmeli yeniden denemeli   |
   //+------------------------------------------------------------------+
   ulong OpenMarket(const int side, const double lot_in, const double sl_in,
                    const double tp_in, const int role, const int level)
     {
      if(!m_ready)
         return 0;
      double lot = NormVolume(lot_in);
      if(lot <= 0.0)
        {
         Print("[APEX:EXEC] Lot broker limitlerine uymuyor, emir iptal.");
         return 0;
        }

      double sl = sl_in, tp = tp_in;
      double px = (side > 0 ? Ask() : Bid());
      if(px <= 0.0)
         return 0;
      SafeStops(side, px, sl, tp);

      string tag = ApexEncodeTag(role, side, level);
      bool ok = false;
      for(int attempt = 0; attempt < 3; attempt++)
        {
         ResetLastError();
         if(side > 0) ok = m_trade.Buy(lot, m_symbol, 0.0, sl, tp, tag);
         else         ok = m_trade.Sell(lot, m_symbol, 0.0, sl, tp, tag);

         uint code = m_trade.ResultRetcode();
         bool good = (ok && (code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_DONE_PARTIAL ||
                             code == TRADE_RETCODE_PLACED || code == TRADE_RETCODE_NO_CHANGES));
         if(good)
           {
            m_error_streak = 0;
            ulong tk = m_trade.ResultDeal();
            PrintFormat("[APEX:EXEC] %s %.2f lot acildi | rol=%s lvl=%+d | deal=%I64u",
                        ApexSideName(side), lot, ApexRoleName(role), level, tk);
            return m_trade.ResultOrder();
           }
         // Self-healing: yeniden fiyatla, lotu bir adim kirp, tekrar dene
         if(RetryableError(code) && attempt < 2)
           {
            Sleep(120);
            px = (side > 0 ? Ask() : Bid());
            SafeStops(side, px, sl, tp);
            continue;
           }
         if(code == TRADE_RETCODE_INVALID_VOLUME || code == TRADE_RETCODE_NO_MONEY)
           {
            lot = NormVolume(lot - m_lot_step);
            if(lot < m_lot_min)
               break;
            continue;
           }
         NoteError("OpenMarket", false);
         return 0;
        }
      NoteError("OpenMarket", false);
      return 0;
     }

   ulong PlacePending(const int order_type, const double lot_in, const double price_in,
                      const double sl_in, const double tp_in, const int role, const int level)
     {
      if(!m_ready)
         return 0;
      double lot = NormVolume(lot_in);
      if(lot <= 0.0)
         return 0;
      if(price_in <= 0.0)
         return 0;

      double sl = sl_in, tp = tp_in;
      int side = (order_type == ORDER_TYPE_BUY_LIMIT || order_type == ORDER_TYPE_BUY_STOP) ? 1 : -1;
      SafeStops(side, price_in, sl, tp);

      string tag = ApexEncodeTag(role, side, level);
      bool ok = false;
      for(int attempt = 0; attempt < 2; attempt++)
        {
         ResetLastError();
         switch((ENUM_ORDER_TYPE)order_type)
           {
            case ORDER_TYPE_BUY_LIMIT:  ok = m_trade.BuyLimit (lot, price_in, m_symbol, sl, tp, ORDER_TIME_GTC, 0, tag); break;
            case ORDER_TYPE_SELL_LIMIT: ok = m_trade.SellLimit(lot, price_in, m_symbol, sl, tp, ORDER_TIME_GTC, 0, tag); break;
            case ORDER_TYPE_BUY_STOP:   ok = m_trade.BuyStop  (lot, price_in, m_symbol, sl, tp, ORDER_TIME_GTC, 0, tag); break;
            case ORDER_TYPE_SELL_STOP:  ok = m_trade.SellStop (lot, price_in, m_symbol, sl, tp, ORDER_TIME_GTC, 0, tag); break;
            default: return 0;
           }
         uint code = m_trade.ResultRetcode();
         if(ok && (code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_PLACED || code == TRADE_RETCODE_NO_CHANGES))
           {
            m_error_streak = 0;
            return m_trade.ResultOrder();
           }
         if(RetryableError(code) && attempt == 0)
           {
            Sleep(120);
            continue;
           }
         break;
        }
      NoteError("PlacePending", false);
      return 0;
     }

   bool CloseTicket(const ulong ticket, const string reason)
     {
      if(ticket == 0)
         return true;
      if(!PositionSelectByTicket(ticket))
         return true;
      for(int a = 0; a < 3; a++)
        {
         ResetLastError();
         bool ok = m_trade.PositionClose(ticket, m_deviation);
         uint code = m_trade.ResultRetcode();
         if(ok && (code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_DONE_PARTIAL ||
                   code == TRADE_RETCODE_PLACED || code == TRADE_RETCODE_NO_CHANGES))
           {
            m_error_streak = 0;
            PrintFormat("[APEX:EXEC] Kapatildi ticket=%I64u neden=%s", ticket, reason);
            return true;
           }
         if(RetryableError(code))
           {
            Sleep(120);
            continue;
           }
         break;
        }
      NoteError(StringFormat("CloseTicket(%I64u,%s)", ticket, reason), false);
      return false;
     }

   bool ModifyStops(const ulong ticket, const double sl, const double tp)
     {
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         return false;
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      int    type  = (int)PositionGetInteger(POSITION_TYPE);
      int    side  = (type == POSITION_TYPE_BUY) ? 1 : -1;
      double nsl = sl, ntp = tp;
      SafeStops(side, entry, nsl, ntp);
      ResetLastError();
      bool ok = m_trade.PositionModify(ticket, nsl, ntp);
      uint code = m_trade.ResultRetcode();
      if(ok && (code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_NO_CHANGES))
         return true;
      return false;
     }

   bool DeleteOrder(const ulong ticket)
     {
      if(ticket == 0)
         return true;
      if(!OrderSelect(ticket))
         return true;
      ResetLastError();
      bool ok = m_trade.OrderDelete(ticket);
      uint code = m_trade.ResultRetcode();
      if(ok && (code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_PLACED || code == TRADE_RETCODE_NO_CHANGES))
         return true;
      return false;
     }

   //+------------------------------------------------------------------+
   //| Defter: biletlerden yeniden insa (self-healing mutabakat)        |
   //+------------------------------------------------------------------+
   bool IsOurTicket(const ulong ticket)
     {
      if(!PositionSelectByTicket(ticket))
         return false;
      if(PositionGetString(POSITION_SYMBOL) != m_symbol)
         return false;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
         return false;
      return true;
     }

   int RebuildBook()
     {
      ArrayResize(m_book, 0);
      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
        {
         ulong tk = PositionGetTicket(i);
         if(tk == 0 || !IsOurTicket(tk))
            continue;

         SBookEntry e;
         e.ticket = tk;
         string comment = PositionGetString(POSITION_COMMENT);
         int role = 0, side = 0, level = 0;
         if(!ApexDecodeTag(comment, role, side, level))
           {
            // Etiket okunamadiysa (broker yorumu kirpti / elle acilan islem)
            // pozisyon yetim kalmasin: tipinden yonu, magic'den aidiyeti al.
            long type = PositionGetInteger(POSITION_TYPE);
            side = (type == POSITION_TYPE_BUY) ? 1 : -1;
            role = (int)ROLE_CORE;
            level = 0;
           }
         e.role    = role;
         e.side    = side;
         e.level   = level;
         e.lot     = PositionGetDouble(POSITION_VOLUME);
         e.entry   = PositionGetDouble(POSITION_PRICE_OPEN);
         e.sl      = PositionGetDouble(POSITION_SL);
         e.tp      = PositionGetDouble(POSITION_TP);
         e.profit  = PositionGetDouble(POSITION_PROFIT);
         e.swap    = PositionGetDouble(POSITION_SWAP);
         e.time    = (datetime)PositionGetInteger(POSITION_TIME);

         int n = ArraySize(m_book);
         ArrayResize(m_book, n + 1);
         m_book[n] = e;
        }
      return ArraySize(m_book);
     }

   int      BookSize()          { return ArraySize(m_book); }

   // Defter kaydi referans ile dondurulur: MQL5'te string/dinamik dizi
   // iceren yapisalarin deger ile kopyalanmasi derleyiciye bagli olarak
   // kisitlanabildigi icin her yer referans kullanir.
   bool     BookAt(const int i, SBookEntry &e)
     {
      if(i < 0 || i >= ArraySize(m_book))
         return false;
      e = m_book[i];
      return true;
     }

   int CountPos(const int role_filter, const int side_filter)
     {
      int c = 0;
      for(int i = 0; i < ArraySize(m_book); i++)
        {
         if(role_filter >= 0 && m_book[i].role != role_filter) continue;
         if(side_filter != 0 && m_book[i].side != side_filter) continue;
         c++;
        }
      return c;
     }

   int CountOrders(const int role_filter)
     {
      int c = 0;
      int total = OrdersTotal();
      for(int i = 0; i < total; i++)
        {
         ulong tk = OrderGetTicket(i);
         if(tk == 0) continue;
         if(!OrderSelect(tk)) continue;
         if(OrderGetString(ORDER_SYMBOL) != m_symbol) continue;
         if((ulong)OrderGetInteger(ORDER_MAGIC) != m_magic) continue;
         if(role_filter >= 0)
           {
            int role = 0, side = 0, level = 0;
            if(ApexDecodeTag(OrderGetString(ORDER_COMMENT), role, side, level))
              {
               if(role != role_filter) continue;
              }
            else if(role_filter != (int)ROLE_CORE)
               continue;
           }
         c++;
        }
      return c;
     }

   double BasketProfit(const int role_filter, const int side_filter)
     {
      double p = 0.0;
      for(int i = 0; i < ArraySize(m_book); i++)
        {
         if(role_filter >= 0 && m_book[i].role != role_filter) continue;
         if(side_filter != 0 && m_book[i].side != side_filter) continue;
         p += m_book[i].profit + m_book[i].swap;
        }
      return p;
     }

   double NetLots(const int role_filter)
     {
      double n = 0.0;
      for(int i = 0; i < ArraySize(m_book); i++)
        {
         if(role_filter >= 0 && m_book[i].role != role_filter) continue;
         n += m_book[i].side * m_book[i].lot;
        }
      return n;
     }

   double GrossLots(const int role_filter)
     {
      double n = 0.0;
      for(int i = 0; i < ArraySize(m_book); i++)
        {
         if(role_filter >= 0 && m_book[i].role != role_filter) continue;
         n += m_book[i].lot;
        }
      return n;
     }

   // Agirlikli ortalama giris fiyati (delta hesabinin referansi)
   double BasketVWAP(const int role_filter, const int side_filter)
     {
      double num = 0.0, den = 0.0;
      for(int i = 0; i < ArraySize(m_book); i++)
        {
         if(role_filter >= 0 && m_book[i].role != role_filter) continue;
         if(side_filter != 0 && m_book[i].side != side_filter) continue;
         num += m_book[i].entry * m_book[i].lot;
         den += m_book[i].lot;
        }
      if(den <= 0.0)
         return 0.0;
      return num / den;
     }

   // Para birimi cinsinden net delta (0 = tam notr)
   double NetDeltaMoney(const int role_filter)
     {
      double px = Bid();
      if(px <= 0.0)
         return 0.0;
      double d = 0.0;
      for(int i = 0; i < ArraySize(m_book); i++)
        {
         if(role_filter >= 0 && m_book[i].role != role_filter) continue;
         d += m_book[i].side * m_book[i].lot * (px - m_book[i].entry) * m_point_value;
        }
      return d;
     }

   // Kritik marjin testi: yeni lot acildiktan sonra marjin seviyesi tabaninin
   // uzerinde kaliyor mu? (hesap para biriminde yaklasik marjin ihtiyaci)
   bool CanAfford(const double lot, const double min_level_pct)
     {
      double margin_req = 0.0;
      if(!OrderCalcMargin(ORDER_TYPE_BUY, m_symbol, lot, Ask(), margin_req))
         return true;
      double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
      double mar = AccountInfoDouble(ACCOUNT_MARGIN);
      double new_margin = mar + margin_req;
      if(new_margin <= 0.0)
         return true;
      return ((eq / new_margin) * 100.0) >= min_level_pct;
     }

   void CloseRole(const int role_filter, const string reason)
     {
      for(int i = ArraySize(m_book) - 1; i >= 0; i--)
        {
         if(role_filter >= 0 && m_book[i].role != role_filter)
            continue;
         CloseTicket(m_book[i].ticket, reason);
        }
     }

   void DeleteOrdersRole(const int role_filter)
     {
      int total = OrdersTotal();
      for(int i = total - 1; i >= 0; i--)
        {
         ulong tk = OrderGetTicket(i);
         if(tk == 0 || !OrderSelect(tk))
            continue;
         if(OrderGetString(ORDER_SYMBOL) != m_symbol)
            continue;
         if((ulong)OrderGetInteger(ORDER_MAGIC) != m_magic)
            continue;
         if(role_filter >= 0)
           {
            int role = 0, side = 0, level = 0;
            if(ApexDecodeTag(OrderGetString(ORDER_COMMENT), role, side, level))
              {
               if(role != role_filter)
                  continue;
              }
            else if(role_filter != (int)ROLE_CORE)
               continue;
           }
         DeleteOrder(tk);
        }
     }
  };

// Modul singleton'lari: baska moduller bunlari referans alir (pointer riski yok)
CApexExecution g_exec;

#endif
//+------------------------------------------------------------------+

//==============================================================================
//| MODUL: ApexSqueezeCore.mqh
//==============================================================================
//+------------------------------------------------------------------+
//|                                               ApexSqueezeCore.mqh |
//|  APEX COMBAT ENGINE - Katman 1: Squeeze Momentum [LazyBear]       |
//|                                                                  |
//|  ORIJINAL MANTIK KORUNARAK TASINDI:                               |
//|   val = linreg( close - avg(avg(highest(high,KC),lowest(low,KC)), |
//|                               sma(close,KC)), KC, 0 )             |
//|   bcolor = val>0 ? (val>val[1] ? lime : green)                    |
//|                  : (val<val[1] ? red  : maroon)                   |
//|   SELL sinyali = lime  -> green   (pozitif momentum zayifliyor)   |
//|   BUY  sinyali = red   -> maroon  (negatif momentum toparlaniyor) |
//|                                                                  |
//|  Ek olarak cekirdek, Apex Combat Engine'in ihtiyac duydugu        |
//|  mikro-pivot (momentum ic tepeleri) ve hiz/ivme turevlerini de    |
//|  ayni seriden uretir. Orijinal sinyal tanimi DEGISTIRILMEDI.      |
//+------------------------------------------------------------------+
#ifndef __APEX_SQUEEZE_CORE_MQH__
#define __APEX_SQUEEZE_CORE_MQH__ 1


enum ENUM_APEX_SQZ_COLOR
  {
   APX_SQZ_NONE   = 0,
   APX_SQZ_LIME   = 1, // val > 0 ve yukseliyor
   APX_SQZ_GREEN  = 2, // val > 0 ve dusuyor
   APX_SQZ_RED    = 3, // val < 0 ve dusuyor
   APX_SQZ_MAROON = 4  // val < 0 ve yukseliyor
  };

// DİKKAT: MQL5'te enum uyeleri global isim uzayinda yasar; bu yuzden
// ENUM_APEX_SQZ_COLOR icindeki APX_SQZ_NONE ile CARPISMAMASI icin
// durum enumu uyeleri APX_SQZST_ on ekiyle adlandirildi.
enum ENUM_APEX_SQZ_STATE
  {
   APX_SQZST_UNKNOWN = 0,
   APX_SQZST_ON      = 1, // sqzOn  : BB Keltner icinde -> sikisma
   APX_SQZST_OFF     = 2, // sqzOff : BB Keltner disinda -> salinim
   APX_SQZST_NONE    = 3  // noSqz  : ikisi de degil
  };

class CApexSqueeze
  {
private:
   string            m_symbol;
   ENUM_TIMEFRAMES   m_tf;
   int               m_bb_len;
   double            m_bb_mult;
   int               m_kc_len;
   double            m_kc_mult;
   bool              m_use_tr;
   int               m_history;
   bool              m_ready;
   datetime          m_last_bar;
   int               m_sqz_calc_depth;

   double            APX_LinRegEnd(const double &series[], const int end_index, const int period)
     {
      int start = end_index - period + 1;
      if(start < 0 || period < 2)
         return 0.0;
      double sum_x  = period * (period - 1) / 2.0;
      double sum_x2 = (double)(period - 1) * period * (2 * period - 1) / 6.0;
      double sum_y  = 0.0;
      double sum_xy = 0.0;
      for(int k = 0; k < period; k++)
        {
         double y = series[start + k];
         sum_y  += y;
         sum_xy += k * y;
        }
      double denom = period * sum_x2 - sum_x * sum_x;
      if(MathAbs(denom) < 1.0e-12)
         return sum_y / period;
      double slope     = (period * sum_xy - sum_x * sum_y) / denom;
      double intercept = (sum_y - slope * sum_x) / period;
      return intercept + slope * (period - 1);   // linreg(..., 0): son mumdaki deger
     }

   ENUM_APEX_SQZ_COLOR APX_BarColor(const double value, const double prev)
     {
      if(value > 0.0)
         return (value > prev) ? APX_SQZ_LIME : APX_SQZ_GREEN;
      return (value < prev) ? APX_SQZ_RED : APX_SQZ_MAROON;
     }

   ENUM_APEX_SQZ_STATE APX_SqueezeStateAt(const MqlRates &rates[], const int index)
     {
      int needed = (int)MathMax(m_bb_len, m_kc_len);
      if(index < needed - 1)
         return APX_SQZST_UNKNOWN;

      double basis = 0.0;
      for(int j = index - m_bb_len + 1; j <= index; j++)
         basis += rates[j].close;
      basis /= m_bb_len;

      double var = 0.0;
      for(int j = index - m_bb_len + 1; j <= index; j++)
        {
         double d = rates[j].close - basis;
         var += d * d;
        }
      double dev = m_bb_mult * MathSqrt(var / m_bb_len);

      double ma = 0.0, range_sum = 0.0;
      for(int j = index - m_kc_len + 1; j <= index; j++)
        {
         ma += rates[j].close;
         double range = rates[j].high - rates[j].low;
         if(m_use_tr && j > 0)
           {
            double pc = rates[j - 1].close;
            range = MathMax(range, MathMax(MathAbs(rates[j].high - pc), MathAbs(rates[j].low - pc)));
           }
         range_sum += range;
        }
      ma /= m_kc_len;
      double range_ma = range_sum / m_kc_len;

      double upper_bb = basis + dev;
      double lower_bb = basis - dev;
      double upper_kc = ma + range_ma * m_kc_mult;
      double lower_kc = ma - range_ma * m_kc_mult;

      if((lower_bb > lower_kc) && (upper_bb < upper_kc)) return APX_SQZST_ON;
      if((lower_bb < lower_kc) && (upper_bb > upper_kc)) return APX_SQZST_OFF;
      return APX_SQZST_NONE;
     }

public:
   MqlRates              m_rates[];   // 0 = en eski
   double                m_mom[];     // momentum (linreg cikisi)
   int                   m_colors[];  // ENUM_APEX_SQZ_COLOR
   bool                  m_valid[];
   int                   m_sqz[];     // ENUM_APEX_SQZ_STATE

                     CApexSqueeze()
     {
      m_ready = false;
      m_last_bar = 0;
      m_sqz_calc_depth = 400;
      ArrayResize(m_rates, 0);
      ArrayResize(m_mom, 0);
      ArrayResize(m_colors, 0);
      ArrayResize(m_valid, 0);
      ArrayResize(m_sqz, 0);
     }
                    ~CApexSqueeze() { }

   bool Init(const SApexConfig &cfg, const ENUM_TIMEFRAMES tf, const int depth)
     {
      m_symbol = cfg.symbol;
      m_tf     = tf;
      m_bb_len = cfg.bb_len;
      m_bb_mult= cfg.bb_mult;
      m_kc_len = cfg.kc_len;
      m_kc_mult= cfg.kc_mult;
      m_use_tr = cfg.use_true_range;
      m_history= cfg.history_bars;
      m_sqz_calc_depth = depth;
      ArrayResize(m_rates, 0);
      ArrayResize(m_mom, 0);
      ArrayResize(m_colors, 0);
      ArrayResize(m_valid, 0);
      ArrayResize(m_sqz, 0);
      return Refresh(depth);
     }

   //+------------------------------------------------------------------+
   //| Seriyi hesaplar (orijinal algoritma)                             |
   //+------------------------------------------------------------------+
   bool Refresh(const int depth)
     {
      int need = (int)MathMax(m_history, (m_kc_len * 4) + 64);
      ArraySetAsSeries(m_rates, false);
      int copied = CopyRates(m_symbol, m_tf, 0, need, m_rates);
      if(copied <= 0)
         return false;
      ArrayResize(m_rates, copied);

      int total = copied;
      if(ArrayResize(m_mom, total)    < total) return false;
      if(ArrayResize(m_colors, total) < total) return false;
      if(ArrayResize(m_valid, total)  < total) return false;
      if(ArrayResize(m_sqz, total)    < total) return false;

      ArrayInitialize(m_mom, 0.0);
      for(int i = 0; i < total; i++)
        {
         m_colors[i] = (int)APX_SQZ_NONE;
         m_valid[i]  = false;
         m_sqz[i]    = (int)APX_SQZST_UNKNOWN;
        }

      // 1) Detrend serisi
      double detrend[];
      bool   dvalid[];
      if(ArrayResize(detrend, total) < total) return false;
      if(ArrayResize(dvalid, total)  < total) return false;
      ArrayInitialize(detrend, 0.0);
      for(int i = 0; i < total; i++)
         dvalid[i] = false;

      for(int i = m_kc_len - 1; i < total; i++)
        {
         double highest = m_rates[i].high;
         double lowest  = m_rates[i].low;
         double sum_c   = 0.0;
         for(int j = i - m_kc_len + 1; j <= i; j++)
           {
            highest = MathMax(highest, m_rates[j].high);
            lowest  = MathMin(lowest,  m_rates[j].low);
            sum_c  += m_rates[j].close;
           }
         double sma_close = sum_c / m_kc_len;
         double mid = ((highest + lowest) * 0.5 + sma_close) * 0.5;
         detrend[i] = m_rates[i].close - mid;
         dvalid[i]  = true;
        }

      // 2) val = linreg(detrend, KC, 0)
      for(int i = 2 * m_kc_len - 2; i < total; i++)
        {
         bool ready = true;
         for(int j = i - m_kc_len + 1; j <= i; j++)
           {
            if(!dvalid[j]) { ready = false; break; }
           }
         if(!ready)
            continue;
         m_mom[i]   = APX_LinRegEnd(detrend, i, m_kc_len);
         m_valid[i] = true;
        }

      // 3) Renkler
      for(int i = 0; i < total; i++)
        {
         if(!m_valid[i])
            continue;
         double prev = (i > 0 && m_valid[i - 1]) ? m_mom[i - 1] : 0.0;
         m_colors[i] = (int)APX_BarColor(m_mom[i], prev);
        }

      // 4) Sikisma durumu - maliyetli oldugu icin son N bara sinirli
      int from = (int)MathMax(0, total - depth);
      for(int i = from; i < total; i++)
         m_sqz[i] = (int)APX_SqueezeStateAt(m_rates, i);

      m_ready = true;
      return true;
     }

   bool     Ready()              { return m_ready; }
   int      Bars()               { return ArraySize(m_rates); }
   int      LastClosed()         { int n = ArraySize(m_rates); return (n >= 2 ? n - 2 : -1); }
   datetime LastBarTime()        { int n = ArraySize(m_rates); return (n > 0 ? m_rates[n - 1].time : 0); }
   double   Mom(const int shift) { int n = ArraySize(m_mom); return (shift >= 0 && shift < n) ? m_mom[shift] : 0.0; }
   int      Color(const int shift){ int n = ArraySize(m_colors); return (shift >= 0 && shift < n) ? m_colors[shift] : 0; }
   bool     Valid(const int shift){ int n = ArraySize(m_valid); return (shift >= 0 && shift < n) ? m_valid[shift] : false; }
   int      Sqz(const int shift) { int n = ArraySize(m_sqz); return (shift >= 0 && shift < n) ? m_sqz[shift] : 0; }
   double   High(const int shift){ int n = ArraySize(m_rates); return (shift >= 0 && shift < n) ? m_rates[shift].high : 0.0; }
   double   Low(const int shift) { int n = ArraySize(m_rates); return (shift >= 0 && shift < n) ? m_rates[shift].low : 0.0; }
   double   Close(const int shift){ int n = ArraySize(m_rates); return (shift >= 0 && shift < n) ? m_rates[shift].close : 0.0; }
   double   Open(const int shift){ int n = ArraySize(m_rates); return (shift >= 0 && shift < n) ? m_rates[shift].open : 0.0; }
   datetime Time(const int shift){ int n = ArraySize(m_rates); return (shift >= 0 && shift < n) ? m_rates[shift].time : 0; }

   //+------------------------------------------------------------------+
   //| ORIJINAL SINYAL TANIMI (degistirilmedi)                          |
   //|   +1 = BUY  (red -> maroon)                                      |
   //|   -1 = SELL (lime -> green)                                      |
   //+------------------------------------------------------------------+
   int      SignalAt(const int shift)
     {
      if(shift < 1)
         return 0;
      int p = Color(shift - 1);
      int c = Color(shift);
      if(p == (int)APX_SQZ_LIME && c == (int)APX_SQZ_GREEN)  return -1;
      if(p == (int)APX_SQZ_RED  && c == (int)APX_SQZ_MAROON) return  1;
      return 0;
     }

   //+------------------------------------------------------------------+
   //| Momentum turevleri (D5 boyutu ve akilli cikis icin)              |
   //+------------------------------------------------------------------+
   double   StdDev(const int shift, const int lookback)
     {
      int n = ArraySize(m_mom);
      if(shift < 0 || shift >= n || lookback < 2)
         return 0.0;
      int from = (int)MathMax(0, shift - lookback + 1);
      int cnt = shift - from + 1;
      if(cnt < 2)
         return 0.0;
      double mean = 0.0;
      for(int i = from; i <= shift; i++) mean += m_mom[i];
      mean /= cnt;
      double var = 0.0;
      for(int i = from; i <= shift; i++)
        {
         double d = m_mom[i] - mean;
         var += d * d;
        }
      return MathSqrt(var / cnt);
     }

   // 1. turev (hiz): son k bardaki ortalama degisim
   double   Velocity(const int shift, const int k)
     {
      if(shift - k < 0)
         return 0.0;
      if(!Valid(shift) || !Valid(shift - k))
         return 0.0;
      return (m_mom[shift] - m_mom[shift - k]) / (double)k;
     }

   // 2. turev (ivme): hizin degisimi
   double   Acceleration(const int shift, const int k)
     {
      return Velocity(shift, k) - Velocity(shift - k, k);
     }

   // Momentum isaret degisim sikligi (0..1) - whipsaw olcer
   double   FlipRate(const int shift, const int lookback)
     {
      if(lookback < 3)
         return 0.0;
      int flips = 0, cnt = 0;
      int last_sign = 0;
      int from = (int)MathMax(1, shift - lookback + 1);
      for(int i = from; i <= shift; i++)
        {
         if(!Valid(i))
            continue;
         int s = ApexSign(m_mom[i]);
         if(last_sign != 0 && s != 0 && s != last_sign)
            flips++;
         if(s != 0)
            last_sign = s;
         cnt++;
        }
      if(cnt < 3)
         return 0.0;
      return (double)flips / (double)cnt;
     }

   //+------------------------------------------------------------------+
   //| MIKRO-PIVOT: momentum histograminin kendi icindeki minik         |
   //| tepe/dip donusleri. Mikro-scalp motorunun tetikleyicisidir.      |
   //|   +1 = dip (momentum asagi yonlu tukenmis, yukari donebilir)     |
   //|   -1 = tepe (momentum yukari yonlu tukenmis)                     |
   //+------------------------------------------------------------------+
   int      MicroPivot(const int shift, const int span, const double min_amplitude)
     {
      if(span < 1 || shift - span < 0)
         return 0;
      int n = ArraySize(m_mom);
      if(shift + span >= n)
         return 0;
      if(!Valid(shift))
         return 0;

      double c = m_mom[shift];
      bool is_max = true, is_min = true;
      for(int k = 1; k <= span; k++)
        {
         if(!Valid(shift - k) || !Valid(shift + k))
            return 0;
         if(m_mom[shift - k] > c || m_mom[shift + k] > c) is_max = false;
         if(m_mom[shift - k] < c || m_mom[shift + k] < c) is_min = false;
        }
      double sd = StdDev(shift, 60);
      if(sd <= 0.0)
         return 0;

      if(is_min && m_mom[shift] < -min_amplitude * sd)
         return 1;   // dip -> long scalpi
      if(is_max && m_mom[shift] > min_amplitude * sd)
         return -1;  // tepe -> short scalpi
      return 0;
     }
  };

// Uc ayri zaman dilimi icin ayri cekirdek ornekleri:
//   g_sqz_main   : ana sinyal/grid zaman dilimi
//   g_sqz_ctx    : ust zaman dilimi baglam/filtre
//   g_sqz_scalp  : mikro-scalp (alt zaman dilimi, tick hizinda yoklanir)
CApexSqueeze g_sqz_main;
CApexSqueeze g_sqz_ctx;
CApexSqueeze g_sqz_scalp;

#endif
//+------------------------------------------------------------------+

//==============================================================================
//| MODUL: ApexAnalytics.mqh
//==============================================================================
//+------------------------------------------------------------------+
//|                                                ApexAnalytics.mqh |
//|  APEX COMBAT ENGINE - Katman 2: 5 Boyutlu Rejim Analizi           |
//|                                                                  |
//|   D1 SQUEEZE BASINCI  : sikisma suresi, salinim yonu, titreme     |
//|   D2 HURST USTELI     : trend kaliciligi (varyans-temelli H)      |
//|   D3 ATR VOL BANDI    : normalize volatilite z-skoru              |
//|   D4 HACIM PROFILI    : POC / VAH / VAL, denge, emilim, CVD       |
//|   D5 MOMENTUM TUREVI  : hiz (1. turev), ivme (2. turev), yorgunluk|
//|                                                                  |
//|  Bilesik: agirlikli oy + histerezis + guven skoru -> rejim        |
//+------------------------------------------------------------------+
#ifndef __APEX_ANALYTICS_MQH__
#define __APEX_ANALYTICS_MQH__ 1


#define APX_RELEASE_WINDOW 6   // salinimdan sonraki kac bar "atak" sayilir
#define APX_FLICKER_WINDOW 40  // sikisma titreme sayaci penceresi

void ApexResetSnapshot(SRegimeSnapshot &s)
  {
   s.regime      = (int)REGIME_BOOT;
   s.prev_regime = (int)REGIME_BOOT;
   s.posture     = (int)POSTURE_PEACE;
   s.bars_in_regime = 0;
   s.confidence  = 0.0;
   s.trend_dir   = 0;
   s.stamp       = 0;
   s.valid       = 0;
   for(int i = 0; i < 6; i++)
      s.score[i] = 0.0;

   s.sqz_state = 0; s.sqz_compress_bars = 0; s.bars_since_release = -1;
   s.release_dir = 0; s.sqz_energy = 0.0; s.sqz_flicker = 0;

   s.hurst = 0.5; s.persistence = (int)PERSIST_RANDOM;

   s.atr = 0.0; s.atr_pct = 0.0; s.atr_mean = 0.0; s.atr_std = 0.0;
   s.atr_z = 0.0; s.vol_band = (int)VOLBAND_NORMAL;

   s.poc = 0.0; s.vah = 0.0; s.val = 0.0; s.vp_pos = (int)VP_IN_VALUE;
   s.balance = 0.0; s.absorption = 0.0; s.cvd_slope = 0.0; s.vp_skew = 0.0;

   s.mom = 0.0; s.mom_z = 0.0; s.vel = 0.0; s.vel_z = 0.0;
   s.accel = 0.0; s.accel_z = 0.0; s.flip_rate = 0.0;
   s.fatigue = 0; s.vel_zero_cross = 0; s.mom_dir = 0;

   s.elasticity = 1.0; s.composite_heat = 0.0;
  }

class CApexAnalytics
  {
private:
   SApexConfig       m_cfg;
   double            m_atr_series[];
   double            m_vp_buckets[];
   int               m_regime;
   int               m_regime_bars;
   int               m_bars_seen;
   bool              m_ready;

   //------------------------------------------------------------------+
   double TrueRangeAt(const MqlRates &r[], const int i)
     {
      if(i < 1)
         return r[i].high - r[i].low;
      double tr1 = r[i].high - r[i].low;
      double tr2 = MathAbs(r[i].high - r[i - 1].close);
      double tr3 = MathAbs(r[i].low  - r[i - 1].close);
      return MathMax(tr1, MathMax(tr2, tr3));
     }

   void   LinFit(const double &x[], const double &y[], const int n, double &slope, double &intercept)
     {
      slope = 0.0;
      intercept = 0.0;
      if(n < 3)
         return;
      double sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0;
      for(int i = 0; i < n; i++)
        {
         sx  += x[i];
         sy  += y[i];
         sxx += x[i] * x[i];
         sxy += x[i] * y[i];
        }
      double den = n * sxx - sx * sx;
      if(MathAbs(den) < 1.0e-12)
        {
         slope = 0.0;
         intercept = (n > 0 ? sy / n : 0.0);
         return;
        }
      slope     = (n * sxy - sx * sy) / den;
      intercept = (sy - slope * sx) / n;
     }

   //------------------------------------------------------------------+
   //| D2: Varyans-temelli Hurst usteli                                 |
   //|   Var(log P(t+L) - log P(t)) ~ L^(2H)                            |
   //|   log Var  =  2H * log L  + c   ->  egim = 2H                    |
   //+------------------------------------------------------------------+
   double ComputeHurst(const MqlRates &r[], const int end_index, const int window, const int max_lag)
     {
      int start = end_index - window + 1;
      if(start < 1 || window < max_lag * 3 || window < 30)
         return 0.5;

      double lp[];
      if(ArrayResize(lp, window + 1) < window + 1)
         return 0.5;
      for(int i = 0; i <= window; i++)
        {
         double c = r[start + i].close;
         if(c <= 0.0)
            return 0.5;
         lp[i] = MathLog(c);
        }

      double xs[], ys[];
      if(ArrayResize(xs, max_lag) < max_lag) return 0.5;
      if(ArrayResize(ys, max_lag) < max_lag) return 0.5;

      int idx = 0;
      for(int lag = 2; lag <= max_lag; lag++)
        {
         double sum = 0.0;
         int    cnt = 0;
         for(int i = 0; i + lag <= window; i++)
           {
            double d = lp[i + lag] - lp[i];
            sum += d * d;
            cnt++;
           }
         if(cnt < 5)
            continue;
         double v = sum / cnt;
         if(v <= 0.0)
            continue;
         xs[idx] = MathLog((double)lag);
         ys[idx] = MathLog(v);
         idx++;
        }
      if(idx < 3)
         return 0.5;

      double slope = 0.0, icpt = 0.0;
      LinFit(xs, ys, idx, slope, icpt);
      double H = slope * 0.5;
      if(!MathIsValidNumber(H))
         return 0.5;
      return ApexClamp(H, 0.05, 0.95);
     }

   //------------------------------------------------------------------+
   //| D3: ATR serisi, ortalama/std ve z-skoru                          |
   //+------------------------------------------------------------------+
   void ComputeATR(const MqlRates &r[], const int end_index, SRegimeSnapshot &s)
     {
      int len = m_cfg.atr_band_len + m_cfg.atr_period + 2;
      int start = end_index - len + 1;
      if(start < 1)
        {
         s.atr = 0.0;
         return;
        }
      if(ArrayResize(m_atr_series, len) < len)
         return;

      for(int k = 0; k < len; k++)
        {
         int i = start + k;
         double sum = 0.0;
         int cnt = 0;
         for(int j = i - m_cfg.atr_period + 1; j <= i; j++)
           {
            if(j < 1)
               continue;
            sum += TrueRangeAt(r, j);
            cnt++;
           }
         m_atr_series[k] = (cnt > 0 ? sum / cnt : 0.0);
        }

      double mean = 0.0;
      for(int k = 0; k < len; k++)
         mean += m_atr_series[k];
      mean /= len;

      double var = 0.0;
      for(int k = 0; k < len; k++)
        {
         double d = m_atr_series[k] - mean;
         var += d * d;
        }
      double std = MathSqrt(var / len);

      s.atr      = m_atr_series[len - 1];
      s.atr_mean = mean;
      s.atr_std  = std;
      s.atr_z    = ApexZScore(s.atr, mean, std);

      double px = r[end_index].close;
      s.atr_pct = (px > 0.0 ? s.atr / px : 0.0);

      if(s.atr_z >= m_cfg.atr_z_explosive)     s.vol_band = (int)VOLBAND_EXPLOSIVE;
      else if(s.atr_z >= m_cfg.atr_z_expansion) s.vol_band = (int)VOLBAND_EXPANSION;
      else if(s.atr_z <= -0.75)                 s.vol_band = (int)VOLBAND_CRUSH;
      else                                      s.vol_band = (int)VOLBAND_NORMAL;
     }

   //------------------------------------------------------------------+
   //| D4: Hacim profili (POC / VAH / VAL) + likidite dagilimi          |
   //+------------------------------------------------------------------+
   void ComputeVolumeProfile(const MqlRates &r[], const int end_index, SRegimeSnapshot &s)
     {
      int look = m_cfg.vp_lookback;
      int start = end_index - look + 1;
      if(start < 0)
         start = 0;
      int cnt = end_index - start + 1;
      if(cnt < 10)
         return;

      double lo = r[start].low, hi = r[start].high;
      for(int i = start; i <= end_index; i++)
        {
         lo = MathMin(lo, r[i].low);
         hi = MathMax(hi, r[i].high);
        }
      double span = hi - lo;
      if(span <= 0.0)
         return;

      int    nb   = m_cfg.vp_buckets;
      double step = span / nb;
      if(ArrayResize(m_vp_buckets, nb) < nb)
         return;
      ArrayInitialize(m_vp_buckets, 0.0);

      double total_vol = 0.0;
      for(int i = start; i <= end_index; i++)
        {
         double v = (r[i].real_volume > 0 ? (double)r[i].real_volume : (double)r[i].tick_volume);
         if(v <= 0.0)
            v = 1.0; // hacimsiz semboller (bazi CFD'ler) icin esit agirlik
         total_vol += v;

         int b0 = (int)MathFloor((r[i].low - lo) / step);
         int b1 = (int)MathFloor((r[i].high - lo) / step);
         if(b0 < 0) b0 = 0;
         if(b1 >= nb) b1 = nb - 1;
         if(b1 < b0) b1 = b0;
         double share = v / (double)(b1 - b0 + 1);
         for(int b = b0; b <= b1; b++)
            m_vp_buckets[b] += share;
        }
      if(total_vol <= 0.0)
         return;

      // POC
      int poc_idx = 0;
      double best = -1.0;
      for(int b = 0; b < nb; b++)
        {
         if(m_vp_buckets[b] > best)
           {
            best = m_vp_buckets[b];
            poc_idx = b;
           }
        }

      // Deger alani: POC'tan disa dogru %va_pct hacim toplanana kadar
      double target = total_vol * m_cfg.va_pct;
      double acc = m_vp_buckets[poc_idx];
      int lo_idx = poc_idx, hi_idx = poc_idx;
      while(acc < target && (lo_idx > 0 || hi_idx < nb - 1))
        {
         double below = (lo_idx > 0 ? m_vp_buckets[lo_idx - 1] : -1.0);
         double above = (hi_idx < nb - 1 ? m_vp_buckets[hi_idx + 1] : -1.0);
         if(above >= below && hi_idx < nb - 1)
           {
            hi_idx++;
            acc += m_vp_buckets[hi_idx];
           }
         else if(lo_idx > 0)
           {
            lo_idx--;
            acc += m_vp_buckets[lo_idx];
           }
         else
            break;
        }

      s.poc = lo + (poc_idx + 0.5) * step;
      s.vah = lo + (hi_idx + 1.0) * step;
      s.val = lo + lo_idx * step;

      double px = r[end_index].close;
      if(px > s.vah)      s.vp_pos = (int)VP_ABOVE_VALUE;
      else if(px < s.val) s.vp_pos = (int)VP_BELOW_VALUE;
      else                s.vp_pos = (int)VP_IN_VALUE;

      // Denge: hacmin merkezdeki ucte birlik kisimda yogunlasmasi
      int third = (int)MathMax(1, nb / 3);
      int c0 = nb / 2 - third / 2;
      int c1 = c0 + third;
      if(c0 < 0) c0 = 0;
      if(c1 >= nb) c1 = nb - 1;
      double centre = 0.0;
      for(int b = c0; b <= c1; b++)
         centre += m_vp_buckets[b];
      s.balance = ApexSaturate(centre / total_vol);

      // Asimetri: POC ustu / alti hacim dengesi
      double above_v = 0.0, below_v = 0.0;
      for(int b = 0; b < nb; b++)
        {
         if(b > poc_idx) above_v += m_vp_buckets[b];
         if(b < poc_idx) below_v += m_vp_buckets[b];
        }
      s.vp_skew = ApexClamp((above_v - below_v) / total_vol, -1.0, 1.0);

      // Emilim (akilli para): dusuk menzil + yuksek hacim + uc kapanis
      int ab = 0, ab_cnt = 0;
      double atr_now = (s.atr > 0.0 ? s.atr : span / (double)cnt);
      for(int i = end_index - 9; i <= end_index; i++)
        {
         if(i < 1)
            continue;
         double v   = (r[i].real_volume > 0 ? (double)r[i].real_volume : (double)r[i].tick_volume);
         double avg = total_vol / (double)cnt;
         double rng = r[i].high - r[i].low;
         if(avg <= 0.0)
            continue;
         bool  tight  = (rng < 0.6 * atr_now);
         bool  heavy  = (v > 1.4 * avg);
         bool  at_edge= (r[i].close > r[i].low + 0.75 * rng) || (r[i].close < r[i].low + 0.25 * rng);
         ab_cnt++;
         if(tight && heavy && at_edge)
            ab++;
        }
      s.absorption = (ab_cnt > 0 ? ApexSaturate((double)ab / (double)ab_cnt) : 0.0);

      // CVD egimi: kumulatif hacim dengesi (yukari/down bar hacimleri)
      double up_v = 0.0, dn_v = 0.0;
      for(int i = start; i <= end_index; i++)
        {
         double v = (r[i].real_volume > 0 ? (double)r[i].real_volume : (double)r[i].tick_volume);
         if(v <= 0.0) v = 1.0;
         if(r[i].close > r[i].open) up_v += v;
         else if(r[i].close < r[i].open) dn_v += v;
        }
      s.cvd_slope = ApexClamp((up_v - dn_v) / (up_v + dn_v + 1.0e-12), -1.0, 1.0);
     }

   //------------------------------------------------------------------+
   //| D1: Squeeze basinci (sikisma / salinim / titreme)                |
   //+------------------------------------------------------------------+
   void ComputeSqueezeDim(SRegimeSnapshot &s)
     {
      int last = g_sqz_main.LastClosed();
      if(last < 1)
         return;

      s.sqz_state = g_sqz_main.Sqz(last);

      // Geriye dogru kesintisiz sikisma suresi
      int bars = 0;
      for(int i = last; i >= 1; i--)
        {
         if(g_sqz_main.Sqz(i) == (int)APX_SQZST_ON)
            bars++;
         else
            break;
        }
      s.sqz_compress_bars = bars;
      s.sqz_energy = ApexSaturate((double)bars / 12.0);

      // Son ON -> OFF salinimi
      s.bars_since_release = -1;
      s.release_dir = 0;
      for(int i = last; i >= 1; i--)
        {
         int cur = g_sqz_main.Sqz(i);
         int prv = g_sqz_main.Sqz(i - 1);
         if(cur != (int)APX_SQZ_ON && prv == (int)APX_SQZST_ON)
           {
            s.bars_since_release = last - i;
            // Salinim anindaki momentum yonu
            double m1 = g_sqz_main.Mom(i);
            double m2 = g_sqz_main.Mom(i - 1);
            double m  = (MathAbs(m1) >= MathAbs(m2) ? m1 : m2);
            double sd = g_sqz_main.StdDev(i, 80);
            s.release_dir = (MathAbs(m) > 0.35 * sd ? ApexSign(m) : 0);
            break;
           }
        }

      // Titreme (ON/OFF salinimi) - tuzak gostergesi
      int flick = 0;
      int from = (int)MathMax(1, last - APX_FLICKER_WINDOW);
      for(int i = from + 1; i <= last; i++)
        {
         int cur = g_sqz_main.Sqz(i);
         int prv = g_sqz_main.Sqz(i - 1);
         if(cur == (int)APX_SQZST_UNKNOWN || prv == (int)APX_SQZST_UNKNOWN)
            continue;
         bool cur_on = (cur == (int)APX_SQZST_ON);
         bool prv_on = (prv == (int)APX_SQZST_ON);
         if(cur_on != prv_on)
            flick++;
        }
      s.sqz_flicker = flick;
     }

   //------------------------------------------------------------------+
   //| D5: Momentum turevleri                                           |
   //+------------------------------------------------------------------+
   void ComputeMomentumDim(SRegimeSnapshot &s)
     {
      int last = g_sqz_main.LastClosed();
      if(last < m_cfg.deriv_len + 2 || !g_sqz_main.Valid(last))
         return;

      int k = m_cfg.deriv_len;
      s.mom     = g_sqz_main.Mom(last);
      double sd = g_sqz_main.StdDev(last, 80);
      s.mom_z   = ApexSafeDiv(s.mom, sd, 0.0);
      s.mom_dir = (MathAbs(s.mom) > 0.3 * sd ? ApexSign(s.mom) : 0);

      s.vel   = g_sqz_main.Velocity(last, k);
      s.accel = g_sqz_main.Acceleration(last, k);

      // Hiz/ivme icin olcek: momentum std / k
      double vscale = ApexSafeDiv(sd, (double)k, 0.0);
      s.vel_z   = ApexSafeDiv(s.vel, vscale, 0.0);
      s.accel_z = ApexSafeDiv(s.accel, (vscale > 0.0 ? vscale * 0.5 : 0.0), 0.0);
      s.flip_rate = g_sqz_main.FlipRate(last, 30);

      double v_prev = g_sqz_main.Velocity(last - 1, k);
      s.vel_zero_cross = (ApexSign(s.vel) != 0 && ApexSign(v_prev) != 0 &&
                          ApexSign(s.vel) != ApexSign(v_prev)) ? 1 : 0;

      // Yorgunluk: momentum hala buyuk ama hiz yon degistirmis / dumduz
      double vel_max = 0.0;
      for(int i = 1; i <= 8; i++)
         vel_max = MathMax(vel_max, MathAbs(g_sqz_main.Velocity(last - i, k)));
      bool exhausted = (MathAbs(s.mom_z) > 0.9) && (MathAbs(s.vel) < 0.35 * vel_max);
      bool opposed   = (ApexSign(s.vel) != 0 && ApexSign(s.mom) != 0 && ApexSign(s.vel) != ApexSign(s.mom));
      s.fatigue = (exhausted || opposed || s.vel_zero_cross == 1) ? 1 : 0;
     }

   //------------------------------------------------------------------+
   //| Oylama: 5 boyutun rejim uyelikleri agirlikli olarak toplanir     |
   //+------------------------------------------------------------------+
   void ScoreRegimes(SRegimeSnapshot &s)
     {
      double m_compress = s.sqz_energy;
      double m_release  = (s.bars_since_release >= 0 && s.bars_since_release <= APX_RELEASE_WINDOW)
                          ? (1.0 - (double)s.bars_since_release / (double)APX_RELEASE_WINDOW) : 0.0;
      double m_trend_p  = ApexNormRange(s.hurst, m_cfg.hurst_mr, m_cfg.hurst_trend);
      double m_mr_p     = 1.0 - m_trend_p;
      double m_vol_exp  = ApexNormRange(s.atr_z, -0.25, m_cfg.atr_z_explosive);
      double m_vol_calm = 1.0 - m_vol_exp;
      double m_out_val  = (s.vp_pos == (int)VP_IN_VALUE) ? 0.0 : 1.0;
      double m_in_val   = 1.0 - m_out_val;
      double m_mom_str  = ApexNormRange(MathAbs(s.mom_z), 0.4, 2.0);
      double m_mom_weak = 1.0 - m_mom_str;
      double m_flip     = ApexNormRange(s.flip_rate, 0.22, 0.60);
      double m_flick    = ApexNormRange((double)s.sqz_flicker, 2.0, 9.0);

      // Yon hizasi: salinim yonu, momentum yonu, deger alani tarafi, CVD
      int votes = 0, agree = 0;
      int ref = s.release_dir;
      if(ref == 0) ref = s.mom_dir;
      if(ref != 0)
        {
         votes++; if(s.mom_dir == ref) agree++;
         votes++; if(s.vp_pos == ref)  agree++;
         votes++; if(ApexSign(s.cvd_slope) == ref) agree++;
         votes++; if(ApexSign(s.vp_skew) == ref)  agree++;
        }
      double m_align = (votes > 0 ? (double)agree / (double)votes : 0.0);

      double s_acc =
         34.0 * m_compress
       + 16.0 * m_vol_calm
       + 14.0 * m_in_val
       + 18.0 * s.absorption
       + 12.0 * m_mom_weak
       +  8.0 * s.balance
       - 25.0 * m_release
       - 18.0 * m_vol_exp;

      double s_brk =
         40.0 * m_release
       + 22.0 * m_vol_exp
       + 20.0 * m_out_val
       + 22.0 * m_trend_p
       + 18.0 * m_mom_str
       + 20.0 * m_align
       - 20.0 * m_mom_weak
       - 12.0 * m_flip;

      double s_mr =
         30.0 * m_mr_p
       + 18.0 * m_in_val
       + 20.0 * s.balance
       + 14.0 * m_mom_weak
       + 16.0 * m_flip
       + 12.0 * m_vol_calm
       - 22.0 * m_release
       - 15.0 * m_vol_exp
       - 10.0 * m_mom_str;

      double s_trap =
         38.0 * m_vol_exp
       + 26.0 * m_flip
       + 14.0 * (1.0 - m_align)
       + 12.0 * m_out_val
       + 10.0 * m_flick
       - 25.0 * m_vol_calm
       - 10.0 * m_trend_p;

      s.score[(int)REGIME_ACCUMULATION]    = MathMax(0.0, s_acc);
      s.score[(int)REGIME_BREAKOUT_ATTACK] = MathMax(0.0, s_brk);
      s.score[(int)REGIME_MEAN_REVERSION]  = MathMax(0.0, s_mr);
      s.score[(int)REGIME_VOLATILITY_TRAP] = MathMax(0.0, s_trap);
      s.score[(int)REGIME_DEFENSE_LOCK]    = 0.0; // yalnizca sert tetikle acilir

      double total = s.score[(int)REGIME_ACCUMULATION] + s.score[(int)REGIME_BREAKOUT_ATTACK]
                   + s.score[(int)REGIME_MEAN_REVERSION] + s.score[(int)REGIME_VOLATILITY_TRAP];
      if(total > 1.0)
        {
         double best = 0.0, second = 0.0;
         for(int i = 1; i <= 4; i++)
           {
            if(s.score[i] > best) { second = best; best = s.score[i]; }
            else if(s.score[i] > second) { second = s.score[i]; }
           }
         s.confidence = ApexSaturate((best - second) / MathMax(best, 1.0));
        }
      else
         s.confidence = 0.0;

      s.composite_heat = ApexSaturate(0.35 * m_vol_exp + 0.30 * m_flip +
                                      0.20 * (1.0 - m_align) + 0.15 * m_flick);
     }

   //------------------------------------------------------------------+
   int ArgBest(SRegimeSnapshot &s)
     {
      int best_i = (int)REGIME_MEAN_REVERSION;
      double best_v = -1.0e18;
      for(int i = 1; i <= 4; i++)
        {
         if(s.score[i] > best_v)
           {
            best_v = s.score[i];
            best_i = i;
           }
        }
      return best_i;
     }

   void ApplyHysteresis(SRegimeSnapshot &s)
     {
      int best = ArgBest(s);

      if(m_bars_seen < m_cfg.boot_bars)
        {
         m_regime = (int)REGIME_BOOT;
         m_regime_bars++;
         s.regime = m_regime;
         s.bars_in_regime = m_regime_bars;
         return;
        }

      if(best == m_regime)
        {
         m_regime_bars++;
        }
      else
        {
         double cur_score = s.score[m_regime];
         double new_score = s.score[best];
         // Histerezis: yeni rejim, mevcut rejimi belirgin farkla yenmeli
         if(new_score >= cur_score + (double)m_cfg.regime_margin &&
            m_regime_bars >= m_cfg.regime_persistence)
           {
            m_regime = best;
            m_regime_bars = 0;
            PrintFormat("[APEX:REGIME] GECIS -> %s (skor yeni=%.1f eski=%.1f guven=%.2f)",
                        ApexRegimeName(m_regime), new_score, cur_score, s.confidence);
           }
         else
           {
            m_regime_bars++;
           }
        }
      s.regime = m_regime;
      s.bars_in_regime = m_regime_bars;
     }

public:
                     CApexAnalytics()
     {
      m_regime      = (int)REGIME_BOOT;
      m_regime_bars = 0;
      m_bars_seen   = 0;
      m_ready       = false;
      ArrayResize(m_atr_series, 0);
      ArrayResize(m_vp_buckets, 0);
     }
                    ~CApexAnalytics() { }

   void Init(const SApexConfig &cfg)
     {
      m_cfg = cfg;
      m_regime = (int)REGIME_BOOT;
      m_regime_bars = 0;
      m_bars_seen = 0;
      ArrayResize(m_atr_series, 0);
      ArrayResize(m_vp_buckets, 0);
      m_ready = true;
     }

   void ForceRegime(const int regime)
     {
      if(m_regime == regime)
         return;
      m_regime = regime;
      m_regime_bars = 0;
     }

   int  CurrentRegime() { return m_regime; }
   int  RegimeBars()    { return m_regime_bars; }
   void CountBar()      { m_bars_seen++; }

   //+------------------------------------------------------------------+
   //| ANA GIRIS: 5 boyutlu rejim tespiti                               |
   //+------------------------------------------------------------------+
   bool DetectAdvancedMarketRegime(SRegimeSnapshot &s)
     {
      ApexResetSnapshot(s);
      if(!m_ready || !g_sqz_main.Ready())
         return false;

      int last = g_sqz_main.LastClosed();
      if(last < 60)
         return false;

      // --- D1 ---
      ComputeSqueezeDim(s);

      // --- D2 --- Hurst (ana TF'in ustune baglam TF'i de eklenir)
      double h_main = ComputeHurst(g_sqz_main.m_rates, last, m_cfg.hurst_window, m_cfg.hurst_max_lag);
      double h_ctx  = h_main;
      int  c_last = g_sqz_ctx.LastClosed();
      if(c_last >= m_cfg.hurst_window)
         h_ctx = ComputeHurst(g_sqz_ctx.m_rates, c_last, m_cfg.hurst_window, m_cfg.hurst_max_lag);
      s.hurst = ApexClamp(0.65 * h_main + 0.35 * h_ctx, 0.05, 0.95);
      if(s.hurst >= m_cfg.hurst_trend)      s.persistence = (int)PERSIST_TREND;
      else if(s.hurst <= m_cfg.hurst_mr)    s.persistence = (int)PERSIST_MEAN_REVERT;
      else                                  s.persistence = (int)PERSIST_RANDOM;

      // --- D3 ---
      ComputeATR(g_sqz_main.m_rates, last, s);

      // --- D4 ---
      ComputeVolumeProfile(g_sqz_main.m_rates, last, s);

      // --- D5 ---
      ComputeMomentumDim(s);

      // --- Bilesik ---
      s.elasticity = ApexClamp(ApexSafeDiv(s.atr, s.atr_mean, 1.0), 0.5, 2.5);

      ScoreRegimes(s);
      ApplyHysteresis(s);

      // --- Trend yonu ve durus ---
      int dir = 0;
      if(s.regime == (int)REGIME_BREAKOUT_ATTACK)
        {
         if(s.release_dir != 0)      dir = s.release_dir;
         else if(s.mom_dir != 0)     dir = s.mom_dir;
         else if(s.vp_pos != 0)      dir = s.vp_pos;
         else                        dir = ApexSign(s.cvd_slope);
        }
      s.trend_dir = dir;

      switch((E_APEX_REGIME)s.regime)
        {
         case REGIME_BOOT:            s.posture = (int)POSTURE_PEACE;    break;
         case REGIME_ACCUMULATION:    s.posture = (int)POSTURE_SKIRMISH; break;
         case REGIME_BREAKOUT_ATTACK: s.posture = (int)POSTURE_ATTACK;   break;
         case REGIME_MEAN_REVERSION:  s.posture = (int)POSTURE_SKIRMISH; break;
         case REGIME_VOLATILITY_TRAP: s.posture = (int)POSTURE_SKIRMISH; break;
         case REGIME_DEFENSE_LOCK:    s.posture = (int)POSTURE_SHIELD;   break;
        }

      s.stamp = TimeCurrent();
      s.valid = 1;
      return true;
     }
  };

CApexAnalytics g_analytics;

#endif
//+------------------------------------------------------------------+

//==============================================================================
//| MODUL: ApexRisk.mqh
//==============================================================================
//+------------------------------------------------------------------+
//|                                                     ApexRisk.mqh  |
//|  APEX COMBAT ENGINE - Katman 2: Sermaye Koruma Guvenlik Duvari    |
//|                                                                  |
//|  Katmanli savunma (defense in depth):                             |
//|   [1] Sembol/oturum/spread hijyeni  (islem oncesi filtre)         |
//|   [2] Pozisyon boyutu: risk% + volatilite + marjin + exposure     |
//|   [3] Rejim bazli risk carpanlari   (dinamik ihtiyat)             |
//|   [4] Drawdown kademeleri           (GREEN/AMBER/RED/BLACK)       |
//|   [5] Delta-notr kilit ve kontrollu geri cekilme (kill-switch)    |
//|                                                                  |
//|  Kendini onarma: drawdown geriledikce risk kapasitesi kademeli    |
//|  olarak geri kazanilir (asiri tepki yok), toksisite skoru zamanla |
//|  sogur, gunluk realize verisi tarihceden yeniden okunur (restart  |
//|  sonrasi bile sistem gunluk limitleri bilir).                     |
//+------------------------------------------------------------------+
#ifndef __APEX_RISK_MQH__
#define __APEX_RISK_MQH__ 1


class CApexRisk
  {
private:
   SApexConfig m_cfg;
   double      m_peak_equity;
   double      m_equity;
   double      m_balance;
   double      m_dd_pct;
   double      m_day_realized;
   double      m_day_start_balance;
   int         m_day_stamp;
   int         m_tier;
   double      m_size_mult;      // hedefe dogru yumusak gecis yapan carpan
   double      m_toxicity;       // 0..1 piyasa + sistem zehirlenme skoru
   int         m_consec_loss;
   bool        m_halted;
   int         m_halt_day;
   double      m_war_chest;      // mikro-scalp kâr havuzu
   datetime    m_last_refresh;
   string      m_gv_peak;
   string      m_gv_halt;
   string      m_status;

   int TodayStamp()
     {
      MqlDateTime dt;
      TimeCurrent(dt);
      return dt.year * 10000 + dt.mon * 100 + dt.day;
     }

   void LoadState()
     {
      m_gv_peak = ApexGVName(m_cfg.symbol, m_cfg.magic, "peak");
      m_gv_halt = ApexGVName(m_cfg.symbol, m_cfg.magic, "halt");
      if(GlobalVariableCheck(m_gv_peak))
         m_peak_equity = GlobalVariableGet(m_gv_peak);
      else
         m_peak_equity = AccountInfoDouble(ACCOUNT_BALANCE);
      if(m_peak_equity <= 0.0)
         m_peak_equity = AccountInfoDouble(ACCOUNT_EQUITY);

      if(GlobalVariableCheck(m_gv_halt))
        {
         double hd = GlobalVariableGet(m_gv_halt);
         m_halt_day = (int)hd;
         m_halted   = (m_halt_day == TodayStamp());
        }
     }

   void SavePeak()
     {
      GlobalVariableSet(m_gv_peak, m_peak_equity);
     }

   // Gunluk realize + ardisik kayip: tarihceden yeniden okunur (stateless)
   void RefreshHistoryStats()
     {
      MqlDateTime dt;
      TimeCurrent(dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      datetime from = StructToTime(dt);
      datetime to   = TimeCurrent() + 60;

      m_day_realized = 0.0;
      if(!HistorySelect(from, to))
         return;

      int total = HistoryDealsTotal();
      double realized = 0.0;
      int loss_streak = 0;
      int scanned = 0;

      for(int i = total - 1; i >= 0 && scanned < 200; i--)
        {
         ulong tk = HistoryDealGetTicket(i);
         if(tk == 0)
            continue;
         if(HistoryDealGetString(tk, DEAL_SYMBOL) != m_cfg.symbol)
            continue;
         if((ulong)HistoryDealGetInteger(tk, DEAL_MAGIC) != m_cfg.magic)
            continue;
         scanned++;

         double profit = HistoryDealGetDouble(tk, DEAL_PROFIT)
                       + HistoryDealGetDouble(tk, DEAL_SWAP)
                       + HistoryDealGetDouble(tk, DEAL_COMMISSION);
         realized += profit;

         long entry = HistoryDealGetInteger(tk, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_IN || entry == DEAL_ENTRY_INOUT)
            continue;
         if(profit < 0.0)
            loss_streak++;
         else
            break;   // kârla biten ilk islemde seri kirilir
        }

      m_day_realized = realized;
      m_consec_loss  = loss_streak;
     }

public:
                     CApexRisk()
     {
      m_peak_equity       = 0.0;
      m_equity            = 0.0;
      m_balance           = 0.0;
      m_dd_pct            = 0.0;
      m_day_realized      = 0.0;
      m_day_start_balance = 0.0;
      m_day_stamp         = 0;
      m_tier              = (int)TIER_GREEN;
      m_size_mult         = 1.0;
      m_toxicity          = 0.0;
      m_consec_loss       = 0;
      m_halted            = false;
      m_halt_day          = 0;
      m_war_chest         = 0.0;
      m_last_refresh      = 0;
      m_status            = "";
     }
                    ~CApexRisk() { }

   void Init(const SApexConfig &cfg)
     {
      m_cfg = cfg;
      m_day_stamp = TodayStamp();
      m_day_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      LoadState();
      Update(true);
     }

   //+------------------------------------------------------------------+
   //| Ana guncelleme: equity, zirve, drawdown, kademe, toksisite       |
   //+------------------------------------------------------------------+
   void Update(const bool force)
     {
      datetime now = TimeCurrent();
      if(!force && (now - m_last_refresh) < 2)
         return;
      m_last_refresh = now;

      m_equity  = AccountInfoDouble(ACCOUNT_EQUITY);
      m_balance = AccountInfoDouble(ACCOUNT_BALANCE);

      int ts = TodayStamp();
      if(ts != m_day_stamp)
        {
         m_day_stamp = ts;
         m_day_start_balance = m_balance;
         m_war_chest = 0.0;
         if(m_halted && m_halt_day != ts)
           {
            m_halted = false;
            GlobalVariableDel(m_gv_halt);
            Print("[APEX:RISK] Yeni gun: kill-switch sifirlandi.");
           }
        }

      if(m_equity > m_peak_equity)
        {
         m_peak_equity = m_equity;
         SavePeak();
        }
      m_dd_pct = (m_peak_equity > 0.0 ? ((m_peak_equity - m_equity) / m_peak_equity) * 100.0 : 0.0);

      RefreshHistoryStats();

      // --- Kademe belirleme ---
      int tier = (int)TIER_GREEN;
      if(m_dd_pct >= m_cfg.dd_kill)
         tier = (int)TIER_BLACK;
      else if(m_dd_pct >= m_cfg.dd_defense)
         tier = (int)TIER_RED;
      else if(m_dd_pct >= m_cfg.dd_warn)
         tier = (int)TIER_AMBER;

      bool daily_breach = (m_cfg.daily_loss_limit > 0.0 && m_day_realized <= -m_cfg.daily_loss_limit);
      if(daily_breach && tier < (int)TIER_RED)
         tier = (int)TIER_RED;
      if(g_exec.MarginLevelPct() < 250.0 && tier < (int)TIER_RED)
         tier = (int)TIER_RED;

      if(tier != m_tier)
        {
         PrintFormat("[APEX:RISK] KADEME %s -> %s (DD=%.2f%% gunluk=%.2f streak=%d)",
                     ApexTierName(m_tier), ApexTierName(tier), m_dd_pct, m_day_realized, m_consec_loss);
         m_tier = tier;
        }

      if(tier == (int)TIER_BLACK && !m_halted)
        {
         m_halted = true;
         m_halt_day = TodayStamp();
         GlobalVariableSet(m_gv_halt, (double)m_halt_day);
         PrintFormat("[APEX:RISK] KILL-SWITCH: DD %.2f%% >= %.2f%%. Gun sonuna kadar islem durdu.",
                     m_dd_pct, m_cfg.dd_kill);
        }

      // --- Kendini onaran risk kapasitesi ---
      double target = 1.0;
      switch((E_APEX_RISK_TIER)m_tier)
        {
         case TIER_GREEN: target = 1.00; break;
         case TIER_AMBER: target = 0.55; break;
         case TIER_RED:   target = 0.20; break;
         case TIER_BLACK: target = 0.00; break;
        }
      target *= (1.0 - 0.5 * m_toxicity);
      if(m_halted)
         target = 0.0;

      double rate = ApexClamp(m_cfg.heal_rate, 0.01, 1.0);
      if(m_size_mult < target)
         m_size_mult = MathMin(target, m_size_mult + rate);     // iyilesme yavas
      else
         m_size_mult = MathMax(target, m_size_mult - rate * 1.5); // kisitlama hizli

      // --- Toksisite sönümlenmesi ---
      m_toxicity = MathMax(0.0, m_toxicity - m_cfg.toxicity_decay);
      double streak_penalty = ApexNormRange((double)m_consec_loss, 1.0, (double)MathMax(2, m_cfg.max_consec_loss));
      m_toxicity = ApexSaturate(MathMax(m_toxicity, streak_penalty));

      m_status = StringFormat("%s | DD %.2f%% | gunluk %.2f | seri kayip %d | carpan %.2f | toks %.2f",
                              ApexTierName(m_tier), m_dd_pct, m_day_realized,
                              m_consec_loss, m_size_mult, m_toxicity);
     }

   //+------------------------------------------------------------------+
   //| Sorgular                                                         |
   //+------------------------------------------------------------------+
   int      Tier()          { return m_tier; }
   double   DrawdownPct()   { return m_dd_pct; }
   double   DayRealized()   { return m_day_realized; }
   double   PeakEquity()    { return m_peak_equity; }
   double   Equity()        { return m_equity; }
   double   SizeMultiplier(){ return m_size_mult; }
   double   Toxicity()      { return m_toxicity; }
   int      ConsecLoss()    { return m_consec_loss; }
   bool     Halted()        { return m_halted; }
   string   Status()        { return m_status; }
   double   WarChest()      { return m_war_chest; }

   void     AddWarChest(const double v) { m_war_chest += v; }
   void     SpendWarChest(const double v){ m_war_chest = MathMax(0.0, m_war_chest - v); }
   void     AddToxicity(const double v) { m_toxicity = ApexSaturate(m_toxicity + v); }

   void     ResetPeak()
     {
      m_peak_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      SavePeak();
     }

   void     ClearHalt()
     {
      m_halted = false;
      GlobalVariableDel(m_gv_halt);
     }

   bool     LockRequired()
     {
      return (m_tier >= (int)TIER_RED);
     }

   bool     LiquidationRequired()
     {
      return (m_tier >= (int)TIER_BLACK);
     }

   //+------------------------------------------------------------------+
   //| Islem oncesi izin: rol bazli                                     |
   //+------------------------------------------------------------------+
   bool AllowNew(const int role, const int regime)
     {
      if(m_halted)
         return false;
      if(m_tier >= (int)TIER_BLACK)
         return false;
      if(m_tier >= (int)TIER_RED)
         return false;                       // kilitte yalnizca hedge/çikis
      if(m_cfg.daily_profit_target > 0.0 && m_day_realized >= m_cfg.daily_profit_target)
         return false;                       // gunluk hedefe ulasildi -> risk alma
      if(regime == (int)REGIME_DEFENSE_LOCK && role != (int)ROLE_HEDGE)
         return false;
      if(role == (int)ROLE_SCALP && regime == (int)REGIME_VOLATILITY_TRAP)
         return false;
      if(role == (int)ROLE_GRID && regime == (int)REGIME_DEFENSE_LOCK)
         return false;
      if(!SessionOK())
         return false;
      if(!SpreadOK())
         return false;
      return true;
     }

   bool SessionOK()
     {
      if(!m_cfg.use_session)
         return true;
      MqlDateTime dt;
      TimeCurrent(dt);
      if(dt.day_of_week == 5 && dt.hour >= m_cfg.friday_close_hour)
         return false;                       // hafta kapanisi
      if(dt.day_of_week == 6 || dt.day_of_week == 0)
         return false;
      if(dt.hour < m_cfg.session_start_hour || dt.hour >= m_cfg.session_end_hour)
         return false;
      return true;
     }

   bool SpreadOK()
     {
      double sp = g_exec.SpreadPoints();
      if(m_cfg.max_spread_points > 0 && sp > m_cfg.max_spread_points)
         return false;
      return true;
     }

   //+------------------------------------------------------------------+
   //| Pozisyon boyutlandirma: risk% + volatilite + marjin + exposure   |
   //+------------------------------------------------------------------+
   // Tavan kurali: risk modeli lotu YALNIZCA KUCULTEBILIR.
   // Hard_cap (taban lot x rejim/rol carpani) asla asilmaz - boylece
   // risk% ayari grid/scalp boyutunu beklenmedik bicimde sisirmez.
   double RiskLotCapped(const double sl_distance_price, const double base_lot,
                        const double size_mult, const double hard_cap)
     {
      double lot = RiskLot(sl_distance_price, base_lot, size_mult);
      if(hard_cap > 0.0 && lot > hard_cap)
         lot = hard_cap;
      return g_exec.NormVolume(lot);
     }

   double RiskLot(const double sl_distance_price, const double base_lot, const double size_mult)
     {
      double lot = base_lot;
      if(m_cfg.risk_per_trade_pct > 0.0 && sl_distance_price > 0.0 && g_exec.PointValue() > 0.0)
        {
         double risk_money = m_equity * (m_cfg.risk_per_trade_pct / 100.0);
         double per_lot    = sl_distance_price * g_exec.PointValue();
         double risk_lot   = ApexSafeDiv(risk_money, per_lot, base_lot);
         // Risk tabanli lot; taban lotun cok altina inmez, cok ustune de cikmaz
         lot = ApexClamp(risk_lot, base_lot * 0.25, base_lot * 10.0);
        }
      lot = lot * ApexClamp(size_mult, 0.0, 1.0);
      if(m_cfg.max_lot > 0.0)
         lot = MathMin(lot, m_cfg.max_lot);
      return g_exec.NormVolume(lot);
     }

   // Kalan marjin ve toplam exposure limitine gore lot tavani
   double ExposureCap(const double lot_requested, const double max_gross_lots)
     {
      double lot = lot_requested;
      if(max_gross_lots > 0.0)
        {
         double used = g_exec.GrossLots(-1);
         double room = max_gross_lots - used;
         if(room <= 0.0)
            return 0.0;
         lot = MathMin(lot, room);
        }
      // Marjin tabani: islem sonrasi marjin seviyesi en az %400 kalmali
      while(lot > 0.0 && !g_exec.CanAfford(lot, 400.0))
         lot = g_exec.NormVolume(lot - g_exec.LotStep());
      return g_exec.NormVolume(lot);
     }

   //+------------------------------------------------------------------+
   //| Rejim bazli ihtiyat: onay sayisi ve lot carpanlari               |
   //+------------------------------------------------------------------+
   int ConfirmationsRequired(const int regime)
     {
      int need = 1;
      switch((E_APEX_REGIME)regime)
        {
         case REGIME_VOLATILITY_TRAP: need = 3; break;
         case REGIME_ACCUMULATION:    need = 2; break;
         case REGIME_MEAN_REVERSION:  need = 1; break;
         case REGIME_BREAKOUT_ATTACK: need = 1; break;
         default:                     need = 2; break;
        }
      if(m_tier >= (int)TIER_AMBER) need++;
      if(m_toxicity > 0.5)          need++;
      return need;
     }

   //+------------------------------------------------------------------+
   //| Kapanis bildirimi: toksisite ve savas sandigi guncellemesi       |
   //+------------------------------------------------------------------+
   void NoteClose(const double profit, const int role)
     {
      if(profit < 0.0)
         m_toxicity = ApexSaturate(m_toxicity + 0.08);
      else
         m_toxicity = MathMax(0.0, m_toxicity - 0.05);
      if(role == (int)ROLE_SCALP && profit > 0.0)
         m_war_chest += profit;
      Update(true);
     }
  };

CApexRisk g_risk;

#endif
//+------------------------------------------------------------------+

//==============================================================================
//| MODUL: ApexGrid.mqh
//==============================================================================
//+------------------------------------------------------------------+
//|                                                     ApexGrid.mqh  |
//|  APEX COMBAT ENGINE - Katman 3: Adatif Bukalemun Grid + Matris    |
//|                                                                  |
//|  SABIT GRID VE KLASIK MARTINGAL YOKTUR.                           |
//|   * Aralik = ATR x elastik carpan  -> "Elastomer Grid"            |
//|   * Lot egimi sinirlidir (anti-martingal), tavan sabittir         |
//|   * Rejim degisince grid modu degisir, ters yonlu bacaklar        |
//|     aninda kesilir (Cut Loss) ve tek yonlu trend binicisine       |
//|     evrilir                                                       |
//|   * Her plan yeniden kuruldugunda piyasadaki emirlerle            |
//|     mutabakat yapilir (kendi kendini onarma)                      |
//+------------------------------------------------------------------+
#ifndef __APEX_GRID_MQH__
#define __APEX_GRID_MQH__ 1


class CApexGrid
  {
private:
   SApexConfig  m_cfg;
   SGridLevel   m_levels[];
   double       m_anchor;
   double       m_step;
   int          m_mode;
   int          m_prev_mode;
   int          m_last_regime;
   int          m_trend_dir;
   int          m_cooldown_bars;
   int          m_cycle_id;
   double       m_basket_peak;
   double       m_basket_target;
   datetime     m_last_recenter;
   string       m_action;
   string       m_gv_anchor;
   string       m_prefix;

   //------------------------------------------------------------------+
   int    ModeFromRegime(const int regime)
     {
      switch((E_APEX_REGIME)regime)
        {
         case REGIME_ACCUMULATION:    return (int)GRID_MODE_STEALTH;
         case REGIME_BREAKOUT_ATTACK: return (int)GRID_MODE_TREND_RIDER;
         case REGIME_MEAN_REVERSION:  return (int)GRID_MODE_HEDGED;
         case REGIME_VOLATILITY_TRAP: return (int)GRID_MODE_FORTRESS;
         case REGIME_DEFENSE_LOCK:    return (int)GRID_MODE_FROZEN;
         default:                     return (int)GRID_MODE_FROZEN;
        }
     }

   int    MaxLevelsForMode(const int mode, const SRegimeSnapshot &s)
     {
      int n = m_cfg.grid_max_levels;
      switch((E_APEX_GRID_MODE)mode)
        {
         case GRID_MODE_STEALTH:     n = (int)MathMin(n, 2); break;
         case GRID_MODE_FORTRESS:    n = (int)MathMin(n, 2); break;
         case GRID_MODE_TREND_RIDER: n = (int)MathMin(n, 4); break;
         case GRID_MODE_HEDGED:      n = n; break;
         default:                    n = 0; break;
        }
      // Yuksek isida seviye sayisi kirpilir (isinin icine merdiven kurulmaz)
      if(s.composite_heat > 0.6)
         n = (int)MathMax(1, n - 1);
      if(g_risk.Tier() >= (int)TIER_AMBER)
         n = (int)MathMax(1, n - 1);
      return n;
     }

   double AdaptiveAnchor(const SRegimeSnapshot &s, const double price)
     {
      if(m_mode == (int)GRID_MODE_TREND_RIDER)
         return price;                                  // trendde merkez = piyasa
      if(s.poc > 0.0 && s.val > 0.0 && s.vah > 0.0)
         return (s.val + s.vah) * 0.5;                  // dengede merkez = deger alani
      return price;
     }

   double LotForLevel(const int i, const int mode)
     {
      double base = m_cfg.base_lot;
      double lot  = base;
      switch((E_APEX_GRID_MODE)mode)
        {
         case GRID_MODE_HEDGED:
            lot = base * (1.0 + m_cfg.grid_lot_slope * (double)(i - 1));
            lot = MathMin(lot, base * m_cfg.grid_lot_max_mult);
            break;
         case GRID_MODE_STEALTH:
            lot = base * 0.5;
            break;
         case GRID_MODE_FORTRESS:
            lot = base * 0.4;
            break;
         case GRID_MODE_TREND_RIDER:
            // Piramit: ilk ekleme en buyuk, sonrakiler kuculur
            lot = base * MathMax(0.45, 1.15 - 0.15 * (double)(i - 1));
            break;
         default:
            lot = base;
            break;
        }
      return lot;
     }

   int    OrderTypeFor(const int mode, const int side)
     {
      if(mode == (int)GRID_MODE_TREND_RIDER)
         return (side > 0 ? (int)ORDER_TYPE_BUY_STOP : (int)ORDER_TYPE_SELL_STOP);
      return (side > 0 ? (int)ORDER_TYPE_BUY_LIMIT : (int)ORDER_TYPE_SELL_LIMIT);
     }

   bool   PendingPriceLegal(const int type, const double price, const double bid, const double ask)
     {
      double mind = g_exec.MinStopDist();
      switch((ENUM_ORDER_TYPE)type)
        {
         case ORDER_TYPE_BUY_LIMIT:  return (price <= bid - mind);
         case ORDER_TYPE_SELL_LIMIT: return (price >= ask + mind);
         case ORDER_TYPE_BUY_STOP:   return (price >= ask + mind);
         case ORDER_TYPE_SELL_STOP:  return (price <= bid - mind);
        }
      return false;
     }

   //------------------------------------------------------------------+
   //| Elastik adim: volatilite buyudukce aralik genisler              |
   //+------------------------------------------------------------------+
   void ComputeElasticStep(const SRegimeSnapshot &s)
     {
      double atr = s.atr;
      double base_step = (atr > 0.0 ? atr * m_cfg.grid_step_atr_mult : g_exec.Point() * 200.0);

      double elasticity = ApexClamp(s.elasticity, m_cfg.grid_step_min_mult, m_cfg.grid_step_max_mult);
      double mode_mult = 1.0;
      switch((E_APEX_GRID_MODE)m_mode)
        {
         case GRID_MODE_STEALTH:     mode_mult = 1.70; break;
         case GRID_MODE_FORTRESS:    mode_mult = 2.20; break;
         case GRID_MODE_HEDGED:      mode_mult = 1.00; break;
         case GRID_MODE_TREND_RIDER: mode_mult = 0.85; break;
         default:                    mode_mult = 1.00; break;
        }
      // Rejim guveni dusukse aralik genisletilir (belirsizlikte seyrek ag)
      double conf_mult = 1.0 + (1.0 - s.confidence) * 0.35;

      m_step = base_step * elasticity * mode_mult * conf_mult;
      double spread = g_exec.SpreadPoints() * g_exec.Point();
      m_step = MathMax(m_step, g_exec.MinStopDist() * 2.0);
      m_step = MathMax(m_step, spread * 4.0);
      m_step = MathMax(m_step, g_exec.Point() * 10.0);
     }

   //------------------------------------------------------------------+
   //| Plan insasi                                                     |
   //+------------------------------------------------------------------+
   void BuildLevels(const SRegimeSnapshot &s, const double price)
     {
      int n = MaxLevelsForMode(m_mode, s);
      int need = 0;
      switch((E_APEX_GRID_MODE)m_mode)
        {
         case GRID_MODE_HEDGED:
         case GRID_MODE_STEALTH:
         case GRID_MODE_FORTRESS:
            need = n * 2;
            break;
         case GRID_MODE_TREND_RIDER:
            need = n;
            break;
         default:
            need = 0;
            break;
        }
      if(ArrayResize(m_levels, need) < need)
         return;

      int idx = 0;
      double sl_dist = (s.atr > 0.0 ? s.atr * m_cfg.grid_sl_atr : m_step * 6.0);
      double tp_dist = (s.atr > 0.0 ? s.atr * m_cfg.grid_tp_atr : m_step * 2.0);

      if(m_mode == (int)GRID_MODE_TREND_RIDER)
        {
         int d = (m_trend_dir != 0 ? m_trend_dir : (s.trend_dir != 0 ? s.trend_dir : 1));
         for(int i = 1; i <= n; i++)
           {
            SGridLevel L;
            L.level  = d * i;
            L.side   = d;
            L.state  = (int)LEG_PLANNED;
            L.price  = g_exec.NormPrice(m_anchor + d * m_step * (double)i, d);
            L.lot    = LotForLevel(i, m_mode);
            L.sl     = g_exec.NormPrice(L.price - d * sl_dist, -d);
            L.tp     = 0.0;   // trendde hedef: sepet + izleyen stop
            L.order_ticket = 0;
            L.pos_ticket   = 0;
            L.stamp        = 0;
            m_levels[idx] = L;
            idx++;
           }
        }
      else
        {
         for(int i = n; i >= 1; i--)   // once uzak seviyeler, sonra yakinlar
           {
            // UST taraf: SELL (yukselen fiyati sat)
            SGridLevel U;
            U.level  = i;
            U.side   = -1;
            U.state  = (int)LEG_PLANNED;
            U.price  = g_exec.NormPrice(m_anchor + m_step * (double)i, 1);
            U.lot    = LotForLevel(i, m_mode);
            U.sl     = g_exec.NormPrice(U.price + sl_dist, 1);
            U.tp     = g_exec.NormPrice(U.price - tp_dist, -1);
            U.order_ticket = 0;
            U.pos_ticket   = 0;
            U.stamp        = 0;
            m_levels[idx] = U;
            idx++;
           }
         for(int i = n; i >= 1; i--)
           {
            // ALT taraf: BUY (dusen fiyati al)
            SGridLevel D;
            D.level  = -i;
            D.side   = 1;
            D.state  = (int)LEG_PLANNED;
            D.price  = g_exec.NormPrice(m_anchor - m_step * (double)i, -1);
            D.lot    = LotForLevel(i, m_mode);
            D.sl     = g_exec.NormPrice(D.price - sl_dist, -1);
            D.tp     = g_exec.NormPrice(D.price + tp_dist, 1);
            D.order_ticket = 0;
            D.pos_ticket   = 0;
            D.stamp        = 0;
            m_levels[idx] = D;
            idx++;
           }
        }
     }

   //------------------------------------------------------------------+
   //| Piyasa ile mutabakat: emir/pozisyon -> plan hucreleri           |
   //+------------------------------------------------------------------+
   void SyncWithMarket(const SRegimeSnapshot &s, const double bid, const double ask)
     {
      // --- 1) Mevcut GRID emirlerini topla ---
      int    o_level[];
      ulong  o_ticket[];
      double o_price[];
      int    o_type[];
      int    o_cnt = 0;
      int    ototal = OrdersTotal();
      for(int i = ototal - 1; i >= 0; i--)
        {
         ulong tk = OrderGetTicket(i);
         if(tk == 0 || !OrderSelect(tk))
            continue;
         if(OrderGetString(ORDER_SYMBOL) != m_cfg.symbol)
            continue;
         if((ulong)OrderGetInteger(ORDER_MAGIC) != m_cfg.magic)
            continue;
         int role = 0, side = 0, level = 0;
         if(!ApexDecodeTag(OrderGetString(ORDER_COMMENT), role, side, level))
            continue;
         if(role != (int)ROLE_GRID)
            continue;
         int c = o_cnt;
         if(ArrayResize(o_level, c + 1)  < c + 1) break;
         if(ArrayResize(o_ticket, c + 1) < c + 1) break;
         if(ArrayResize(o_price, c + 1)  < c + 1) break;
         if(ArrayResize(o_type, c + 1)   < c + 1) break;
         o_level[c]  = level;
         o_ticket[c] = tk;
         o_price[c]  = OrderGetDouble(ORDER_PRICE_OPEN);
         o_type[c]   = (int)OrderGetInteger(ORDER_TYPE);
         o_cnt++;
        }

      // --- 2) Mevcut GRID pozisyonlarini topla ---
      g_exec.RebuildBook();
      int p_level[];
      ulong p_ticket[];
      int p_cnt = 0;
      for(int i = 0; i < g_exec.BookSize(); i++)
        {
         SBookEntry e;
         if(!g_exec.BookAt(i, e))
            continue;
         if(e.role != (int)ROLE_GRID)
            continue;
         int c = p_cnt;
         if(ArrayResize(p_level, c + 1)  < c + 1) break;
         if(ArrayResize(p_ticket, c + 1) < c + 1) break;
         p_level[c]  = e.level;
         p_ticket[c] = e.ticket;
         p_cnt++;
        }

      // --- 3) Plan hucrelerini isaretle + fazlaliklari temizle ---
      for(int i = 0; i < ArraySize(m_levels); i++)
        {
         m_levels[i].order_ticket = 0;
         m_levels[i].pos_ticket   = 0;
         m_levels[i].state        = (int)LEG_PLANNED;

         for(int k = 0; k < p_cnt; k++)
           {
            if(p_level[k] == m_levels[i].level)
              {
               m_levels[i].state      = (int)LEG_FILLED;
               m_levels[i].pos_ticket = p_ticket[k];
               break;
              }
           }
         if(m_levels[i].state == (int)LEG_FILLED)
            continue;

         for(int k = 0; k < o_cnt; k++)
           {
            if(o_level[k] != m_levels[i].level)
               continue;
            double drift = MathAbs(o_price[k] - m_levels[i].price);
            if(drift > m_step * 0.35)
              {
               // Elastik adim degisti: eski emri iptal et, yeni fiyattan kur
               g_exec.DeleteOrder(o_ticket[k]);
               m_levels[i].state = (int)LEG_PLANNED;
              }
            else
              {
               m_levels[i].state        = (int)LEG_ARMED;
               m_levels[i].order_ticket = o_ticket[k];
              }
            break;
           }
        }

      // --- 4) Planda olmayan emirleri sil (mod degisimi / recenter) ---
      for(int k = 0; k < o_cnt; k++)
        {
         bool found = false;
         for(int i = 0; i < ArraySize(m_levels); i++)
           {
            if(m_levels[i].level == o_level[k]) { found = true; break; }
           }
         if(!found)
            g_exec.DeleteOrder(o_ticket[k]);
        }

      // --- 5) Eksik bacaklari kur ---
      int filled_legs = p_cnt;
      int armed_legs  = 0;
      for(int i = 0; i < ArraySize(m_levels); i++)
         if(m_levels[i].state == (int)LEG_ARMED)
            armed_legs++;

      for(int i = 0; i < ArraySize(m_levels); i++)
        {
         if(m_levels[i].state != (int)LEG_PLANNED)
            continue;
         if((filled_legs + armed_legs) >= MathMin(m_cfg.grid_max_legs_total, ArraySize(m_levels)))
            break;
         if(!g_risk.AllowNew((int)ROLE_GRID, s.regime))
            break;

         int type = OrderTypeFor(m_mode, m_levels[i].side);
         if(!PendingPriceLegal(type, m_levels[i].price, bid, ask))
            continue;

         double lot = m_levels[i].lot;
         double sl_dist = (m_levels[i].sl > 0.0 ? MathAbs(m_levels[i].price - m_levels[i].sl) : m_step * 4.0);
         // Tavan: anti-martingal lot egimi. Risk modeli yalnizca kucultur.
         double cap = m_cfg.base_lot * m_cfg.grid_lot_max_mult;
         lot = g_risk.RiskLotCapped(sl_dist, lot, g_risk.SizeMultiplier(), MathMin(cap, lot));
         lot = g_risk.ExposureCap(lot, m_cfg.max_total_lots);
         if(lot <= 0.0)
            continue;

         ulong tk = g_exec.PlacePending(type, lot, m_levels[i].price, m_levels[i].sl,
                                        m_levels[i].tp, (int)ROLE_GRID, m_levels[i].level);
         if(tk != 0)
           {
            m_levels[i].state        = (int)LEG_ARMED;
            m_levels[i].order_ticket = tk;
            armed_legs++;
            if(m_cfg.verbose_log)
               PrintFormat("[APEX:GRID] Bacak kuruldu lvl=%+d %s lot=%.2f @ %.*f (mod=%s adim=%.1f pt)",
                           m_levels[i].level, ApexSideName(m_levels[i].side), lot,
                           g_exec.Digits(), m_levels[i].price, ApexGridModeName(m_mode),
                           m_step / g_exec.Point());
           }
        }
     }

   //------------------------------------------------------------------+
   //| Mod gecisi: rejim degistiginde gridin evrimi                    |
   //+------------------------------------------------------------------+
   void ApplyModeTransition(const int new_mode, const SRegimeSnapshot &s, const double price)
     {
      m_prev_mode = m_mode;
      m_mode      = new_mode;
      m_trend_dir = (s.trend_dir != 0 ? s.trend_dir : s.mom_dir);

      // Tum bekleyen emirler iptal: yeni mod yeni geometri demektir
      g_exec.DeleteOrdersRole((int)ROLE_GRID);

      if(new_mode == (int)GRID_MODE_TREND_RIDER)
        {
         m_anchor = price;
         // Ters yondeki tum bacaklar aninda kesilir (Cut Loss)
         CutCounterTrendLegs(m_trend_dir);
         m_action = StringFormat("MOD: TREND RIDER (%s) - ters bacaklar kesildi", ApexSideName(m_trend_dir));
         PrintFormat("[APEX:GRID] TAAARRUZ: mod=TREND_RIDER yon=%s ters bacaklar kesildi.",
                     ApexSideName(m_trend_dir));
        }
      else if(new_mode == (int)GRID_MODE_HEDGED)
        {
         m_anchor = AdaptiveAnchor(s, price);
         m_action = "MOD: HEDGED GRID - cift yonlu elastik ag";
         PrintFormat("[APEX:GRID] DENGE: mod=HEDGED_GRID merkez=%.5f (deger alani)", m_anchor);
        }
      else if(new_mode == (int)GRID_MODE_STEALTH)
        {
         m_anchor = AdaptiveAnchor(s, price);
         m_action = "MOD: STEALTH - gizli toplanma, genis aralik";
         Print("[APEX:GRID] GIZLI TOPLANMA: mod=STEALTH");
        }
      else if(new_mode == (int)GRID_MODE_FORTRESS)
        {
         m_anchor = AdaptiveAnchor(s, price);
         m_action = "MOD: FORTRESS - tuzak avi, seyrek ve kucuk";
         Print("[APEX:GRID] VOLATILITE TUZAGI: mod=FORTRESS");
        }
      else
        {
         m_action = "MOD: FROZEN - savunma kilidi";
         Print("[APEX:GRID] SIPER: mod=FROZEN (grid donduruldu)");
        }
      SaveAnchor();
     }

   // Ters yonlu bacaklari kapat (en zararli once)
   void CutCounterTrendLegs(const int dir)
     {
      if(dir == 0)
         return;
      g_exec.RebuildBook();
      ulong worst[];
      double worst_pl[];
      int cnt = 0;

      for(int pass = 0; pass < 2; pass++)
        {
         for(int i = 0; i < g_exec.BookSize(); i++)
           {
            SBookEntry e;
         if(!g_exec.BookAt(i, e))
            continue;
            if(e.role != (int)ROLE_GRID)
               continue;
            if(e.side == dir)
               continue;
            if(pass == 0 && e.profit > 0.0)
               continue;      // once zararli olanlar
            if(pass == 1 && e.profit <= 0.0)
               continue;
            int c = cnt;
            if(ArrayResize(worst, c + 1) < c + 1) break;
            if(ArrayResize(worst_pl, c + 1) < c + 1) break;
            worst[c]    = e.ticket;
            worst_pl[c] = e.profit;
            cnt++;
           }
        }

      int cut = (int)MathCeil(cnt * ApexClamp(m_cfg.grid_cut_ratio, 0.1, 1.0));
      for(int i = 0; i < cut && i < cnt; i++)
         g_exec.CloseTicket(worst[i], "REAKSIYON: ters yon bacağı kesildi");
     }

   //------------------------------------------------------------------+
   //| Sepet (basket) yonetimi - Akilli Cikis Matrisi'nin grid ayagi   |
   //+------------------------------------------------------------------+
   void ManageBasket(const SRegimeSnapshot &s, const double price)
     {
      g_exec.RebuildBook();
      double grid_profit  = g_exec.BasketProfit((int)ROLE_GRID, 0);
      double core_profit  = g_exec.BasketProfit((int)ROLE_CORE, 0);
      double gross        = g_exec.GrossLots((int)ROLE_GRID);
      double basket       = grid_profit + core_profit;
      if(basket > m_basket_peak)
         m_basket_peak = basket;

      if(gross <= 0.0)
         return;

      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double atr_money = (s.atr > 0.0 ? s.atr * gross * g_exec.PointValue() : 0.0);
      double target = MathMax(m_cfg.grid_basket_atr * atr_money,
                              m_cfg.grid_basket_equity * 0.01 * equity);
      // Mikro-scalp savas sandigi hedefi dusurur: kâr katlamasi burada
      target = MathMax(atr_money * 0.15, target - g_risk.WarChest());
      m_basket_target = target;
      double stop = -1.6 * MathMax(target, atr_money * 0.25);

      // 1) Hedefe ulasildi -> sepeti bosalt, donguyu sifirla
      if(target > 0.0 && basket >= target)
        {
         CloseCycle(StringFormat("SEPET HEDEFINE ULASILDI (%.2f >= %.2f)", basket, target));
         return;
        }

      // 2) Momentum yorgunlugu -> sinyal sayisini beklemeden AKILLI KÂR SWEEP
      if(s.fatigue == 1 && basket > 0.0 && basket > 0.25 * target)
        {
         CloseCycle(StringFormat("SMART PROFIT SWEEP: momentum turevi sifirlandi (sepet %.2f)", basket));
         g_risk.SpendWarChest(g_risk.WarChest());
         return;
        }

      // 3) Momentum yorgunlugu ama sepet zararda -> sadece kârli bacaklari bosalt
      if(s.fatigue == 1 && basket <= 0.0)
        {
         int closed = 0;
         for(int i = 0; i < g_exec.BookSize(); i++)
           {
            SBookEntry e;
         if(!g_exec.BookAt(i, e))
            continue;
            if(e.role != (int)ROLE_GRID)
               continue;
            if(e.profit > 0.0)
              {
               g_exec.CloseTicket(e.ticket, "KISMI SWEEP: momentum yorgun, kârli bacak realizasyonu");
               closed++;
              }
           }
         if(closed > 0)
            m_action = StringFormat("Kismi sweep: %d kârli bacak kapatildi", closed);
        }

      // 4) Sepet stopu -> savunmaya devir (risk kademesi zaten kilit acacak)
      if(stop < 0.0 && basket <= stop)
        {
         if(g_risk.Tier() >= (int)TIER_RED)
            CloseCycle(StringFormat("SEPET STOP + KIRMIZI KADEME (%.2f <= %.2f)", basket, stop));
         else
           {
            // Kontrollu azaltma: en zararli iki bacak kapatilir
            CutWorstLegs(2, "SEPET STOP: kontrollu azaltma");
           }
        }

      // 5) Trend binicisinde izleyen stop (chandelier)
      if(m_mode == (int)GRID_MODE_TREND_RIDER && s.atr > 0.0)
        {
         double trail = s.atr * 1.2;
         for(int i = 0; i < g_exec.BookSize(); i++)
           {
            SBookEntry e;
         if(!g_exec.BookAt(i, e))
            continue;
            if(e.role != (int)ROLE_GRID || e.side != m_trend_dir)
               continue;
            double new_sl = g_exec.NormPrice(price - e.side * trail, -e.side);
            bool better = false;
            if(e.side > 0)
               better = (new_sl > e.sl + g_exec.Point()) && (new_sl > e.entry);
            else
               better = (e.sl <= 0.0 || new_sl < e.sl - g_exec.Point()) && (new_sl < e.entry);
            if(better)
               g_exec.ModifyStops(e.ticket, new_sl, 0.0);
           }
        }
     }

   void CutWorstLegs(const int count, const string reason)
     {
      g_exec.RebuildBook();
      ulong tk[];
      double pl[];
      int cnt = 0;
      for(int i = 0; i < g_exec.BookSize(); i++)
        {
         SBookEntry e;
         if(!g_exec.BookAt(i, e))
            continue;
         if(e.role != (int)ROLE_GRID)
            continue;
         int c = cnt;
         if(ArrayResize(tk, c + 1) < c + 1) break;
         if(ArrayResize(pl, c + 1) < c + 1) break;
         tk[c] = e.ticket;
         pl[c] = e.profit;
         cnt++;
        }
      // En zararlidan basa: basit secmeli siralama
      for(int a = 0; a < cnt - 1; a++)
         for(int b = a + 1; b < cnt; b++)
            if(pl[b] < pl[a])
              {
               double tp = pl[a]; pl[a] = pl[b]; pl[b] = tp;
               ulong   tt = tk[a]; tk[a] = tk[b]; tk[b] = tt;
              }
      int n = (int)MathMin(count, cnt);
      for(int i = 0; i < n; i++)
         g_exec.CloseTicket(tk[i], reason);
     }

   void CloseCycle(const string reason)
     {
      PrintFormat("[APEX:GRID] DONGU KAPANDI: %s", reason);
      g_exec.CloseRole((int)ROLE_GRID, reason);
      g_exec.CloseRole((int)ROLE_CORE, reason);
      g_exec.DeleteOrdersRole((int)ROLE_GRID);
      m_anchor = 0.0;
      m_basket_peak = 0.0;
      m_cooldown_bars = 2;      // yeni dongu icin kisa nefes
      m_cycle_id++;
      m_action = "DONGU KAPANDI: " + reason;
      SaveAnchor();
     }

   void SaveAnchor()
     {
      if(m_gv_anchor != "")
         GlobalVariableSet(m_gv_anchor, m_anchor);
     }

   void LoadAnchor()
     {
      if(m_gv_anchor != "" && GlobalVariableCheck(m_gv_anchor))
         m_anchor = GlobalVariableGet(m_gv_anchor);
     }

public:
                     CApexGrid()
     {
      m_anchor        = 0.0;
      m_step          = 0.0;
      m_mode          = (int)GRID_MODE_FROZEN;
      m_prev_mode     = (int)GRID_MODE_FROZEN;
      m_last_regime   = (int)REGIME_BOOT;
      m_trend_dir     = 0;
      m_cooldown_bars = 0;
      m_cycle_id      = 0;
      m_basket_peak   = 0.0;
      m_basket_target = 0.0;
      m_last_recenter = 0;
      m_action        = "";
      m_gv_anchor     = "";
      m_prefix        = "";
      ArrayResize(m_levels, 0);
     }
                    ~CApexGrid() { }

   void Init(const SApexConfig &cfg)
     {
      m_cfg = cfg;
      m_gv_anchor = ApexGVName(cfg.symbol, cfg.magic, "anchor");
      m_prefix    = StringFormat("APXGRID_%I64u_%s_", cfg.magic, cfg.symbol);
      ArrayResize(m_levels, 0);
      LoadAnchor();
     }

   int    Mode()          { return m_mode; }
   double Anchor()        { return m_anchor; }
   double Step()          { return m_step; }
   double BasketTarget()  { return m_basket_target; }
   int    CycleId()       { return m_cycle_id; }
   int    LevelCount()    { return ArraySize(m_levels); }
   string Action()        { return m_action; }
   int    TrendDir()      { return m_trend_dir; }

   void   Reset()
     {
      m_anchor = 0.0;
      m_basket_peak = 0.0;
      ArrayResize(m_levels, 0);
      SaveAnchor();
     }

   //+------------------------------------------------------------------+
   //| ANA GIRIS: Adaptif elastik grid ve yon degistirme mekanizmasi    |
   //+------------------------------------------------------------------+
   void ManageAdaptiveElasticGrid(SRegimeSnapshot &s, const double bid, const double ask)
     {
      if(!m_cfg.grid_enabled)
         return;
      if(bid <= 0.0 || ask <= 0.0)
         return;

      double price = (bid + ask) * 0.5;

      // --- Mod gecisi (rejim -> grid modu) ---
      int want_mode = ModeFromRegime(s.regime);
      if(want_mode != m_mode)
         ApplyModeTransition(want_mode, s, price);
      else if(m_mode == (int)GRID_MODE_TREND_RIDER && s.trend_dir != 0 && s.trend_dir != m_trend_dir)
        {
         // Trend yonu tersine dondu: eski yonun bacaklari kesilir
         m_trend_dir = s.trend_dir;
         CutCounterTrendLegs(m_trend_dir);
         g_exec.DeleteOrdersRole((int)ROLE_GRID);
         m_anchor = price;
         m_action = StringFormat("TREND YON DEGISTI -> %s", ApexSideName(m_trend_dir));
        }

      // --- Elastik adim ---
      ComputeElasticStep(s);

      // --- Dondurulmus mod: yalnizca mevcutlari izle ---
      if(m_mode == (int)GRID_MODE_FROZEN)
        {
         g_exec.DeleteOrdersRole((int)ROLE_GRID);
         if(m_action == "")
            m_action = "FROZEN: yeni bacak yok";
         return;
        }

      // --- Bekleme suresi ---
      if(m_cooldown_bars > 0)
        {
         m_cooldown_bars--;
         m_action = StringFormat("Dongu nefesi (%d bar)", m_cooldown_bars);
         return;
        }

      // --- Merkez yeniden konumlandirma (recenter) ---
      if(m_anchor <= 0.0)
        {
         m_anchor = AdaptiveAnchor(s, price);
         SaveAnchor();
        }
      else if(s.atr > 0.0 && MathAbs(price - m_anchor) > m_cfg.grid_recenter_atr * s.atr)
        {
         m_anchor = AdaptiveAnchor(s, price);
         m_last_recenter = TimeCurrent();
         g_exec.DeleteOrdersRole((int)ROLE_GRID);
         m_action = "MERKEZ YENIDEN KONUMLANDI";
         if(m_cfg.verbose_log)
            PrintFormat("[APEX:GRID] Recenter -> %.5f (fiyat %.5f)", m_anchor, price);
        }

      // --- Plan + mutabakat ---
      BuildLevels(s, price);
      SyncWithMarket(s, bid, ask);

      // --- Sepet / akilli cikis ---
      ManageBasket(s, price);

      m_last_regime = s.regime;
     }
  };

CApexGrid g_grid;

#endif
//+------------------------------------------------------------------+

//==============================================================================
//| MODUL: ApexScalp.mqh
//==============================================================================
//+------------------------------------------------------------------+
//|                                                    ApexScalp.mqh  |
//|  APEX COMBAT ENGINE - Katman 3: Hibrit Scalp + Savunma Kalkani    |
//|                                                                  |
//|  IKI AYRI SAVAS KATMANI TEK CATP ALTINDA:                         |
//|   A) MICRO-SCALP ENGINE: squeeze momentum alt dalgalanmalarinda   |
//|      (histogramin kendi icindeki mikro tepe/dip donusleri) hizli  |
//|      mikro pozisyonlar acip kapatarak ana grid kârini katlar.     |
//|   B) DEFENSE SHIELD: drawdown kritik esige ulasinca veya rejim    |
//|      STATE_DEFENSE_LOCK olunca tum riskli bacaklar sentetik       |
//|      olarak kilitlenir (delta notr), zarar dondurulur.            |
//+------------------------------------------------------------------+
#ifndef __APEX_SCALP_MQH__
#define __APEX_SCALP_MQH__ 1


struct SScalpTrack
  {
   ulong    ticket;
   int      side;
   double   lot;
   double   tp;
   double   sl;
   double   entry;
   datetime open_time;
   double   mfe;
  };

class CApexScalp
  {
private:
   SApexConfig   m_cfg;
   SScalpTrack   m_track[];
   datetime      m_last_scalp_bar;
   datetime      m_last_scalp_entry;
   int           m_scalp_bar_count;
   bool          m_locked;
   datetime      m_lock_time;
   int           m_lock_bar;
   double        m_lock_dd;
   double        m_lock_equity;
   int           m_lock_reason;
   double        m_lock_net_lots;
   double        m_hedge_pnl;
   int           m_lock_bars;
   string        m_action;
   bool          m_hedging_account;

   //------------------------------------------------------------------+
   //| Mikro-scalp yonu: rejime gore ruzgarla veya kenarlardan doner   |
   //+------------------------------------------------------------------+
   int    ScalpBias(const SRegimeSnapshot &s, const double price, const int pivot_dir)
     {
      switch((E_APEX_REGIME)s.regime)
        {
         case REGIME_BREAKOUT_ATTACK:
            // Sadece trend yonunde: ruzgar arkadan
            if(s.trend_dir != 0 && pivot_dir == s.trend_dir)
               return s.trend_dir;
            return 0;

         case REGIME_MEAN_REVERSION:
            // Deger alani kenarlarindan fade (donus avi)
            if(s.vah > 0.0 && price >= s.vah - 0.15 * s.atr && pivot_dir < 0)
               return -1;
            if(s.val > 0.0 && price <= s.val + 0.15 * s.atr && pivot_dir > 0)
               return 1;
            return 0;

         case REGIME_ACCUMULATION:
            // Gizli toplanma: sadece momentum yonuyle, yarim boyut
            if(pivot_dir == s.mom_dir && s.mom_dir != 0)
               return s.mom_dir;
            return 0;

         default:
            return 0;   // tuzak / kilit / boot: scalp yok
        }
     }

   double ScalpLot(const SRegimeSnapshot &s, const double sl_dist)
     {
      double lot = m_cfg.base_lot * m_cfg.scalp_lot_mult;
      if(s.regime == (int)REGIME_ACCUMULATION)
         lot *= 0.5;
      if(s.composite_heat > 0.6)
         lot *= 0.5;
      double cap = m_cfg.base_lot * m_cfg.scalp_lot_mult;
      lot = g_risk.RiskLotCapped(sl_dist, lot, g_risk.SizeMultiplier(), MathMin(cap, lot));
      lot = g_risk.ExposureCap(lot, m_cfg.max_total_lots);
      return g_exec.NormVolume(lot);
     }

   //------------------------------------------------------------------+
   //| Acik mikro pozisyonlarin tick bazli yonetimi                    |
   //+------------------------------------------------------------------+
   void ManageOpenScalps(const SRegimeSnapshot &s, const double bid, const double ask)
     {
      g_exec.RebuildBook();

      // Deftere gore izleme listesini yenile (self-healing)
      int n = 0;
      SScalpTrack keep[];
      for(int i = 0; i < g_exec.BookSize(); i++)
        {
         SBookEntry e;
         if(!g_exec.BookAt(i, e))
            continue;
         if(e.role != (int)ROLE_SCALP)
            continue;
         SScalpTrack t;
         t.ticket    = e.ticket;
         t.side      = e.side;
         t.lot       = e.lot;
         t.entry     = e.entry;
         t.sl        = e.sl;
         t.tp        = e.tp;
         t.open_time = e.time;
         t.mfe       = 0.0;

         // Onceki kayitta MFE varsa tasi
         for(int k = 0; k < ArraySize(m_track); k++)
            if(m_track[k].ticket == t.ticket)
              {
               t.mfe = m_track[k].mfe;
               break;
              }
         double cur = (e.side > 0 ? bid : ask);
         double pl  = (cur - e.entry) * e.side;
         if(pl > t.mfe)
            t.mfe = pl;

         if(ArrayResize(keep, n + 1) >= n + 1)
            keep[n] = t;
         n++;
        }
      ArrayResize(m_track, n);
      for(int i = 0; i < n; i++)
         m_track[i] = keep[i];

      int span = (int)MathMax(2, m_cfg.scalp_pivot);
      int s_last = g_sqz_scalp.LastClosed();
      double vel_now = (s_last > span ? g_sqz_scalp.Velocity(s_last, span) : 0.0);
      double vel_prev= (s_last > span + 1 ? g_sqz_scalp.Velocity(s_last - 1, span) : 0.0);
      bool   vel_flip = (ApexSign(vel_now) != 0 && ApexSign(vel_prev) != 0 &&
                         ApexSign(vel_now) != ApexSign(vel_prev));

      int bars_held = 0;
      for(int i = 0; i < ArraySize(m_track); i++)
        {
         SScalpTrack t = m_track[i];
         double cur = (t.side > 0 ? bid : ask);
         double pl  = (cur - t.entry) * t.side;
         double target = MathAbs(t.tp - t.entry);
         if(target <= 0.0)
            target = g_exec.Point() * 50.0;

         bool close_it = false;
         string why = "";

         // 1) Momentum hizi tersine dondu -> mikro is derhal kapanir
         if(vel_flip && ApexSign(vel_now) != t.side)
           {
            close_it = true;
            why = "mikro momentum hizi ters dondu";
           }
         // 2) Zaman stopu: scalp TF'inde cok uzun sure tutuldu
         if(!close_it && m_cfg.scalp_max_bars > 0)
           {
            bars_held = BarsElapsed(m_cfg.tf_scalp, t.open_time);
            if(bars_held > m_cfg.scalp_max_bars)
              {
               close_it = true;
               why = StringFormat("zaman stopu (%d bar)", bars_held);
              }
           }
         // 3) Kârdan geri verme: MFE'nin %60'i geri verildiyse cik
         if(!close_it && t.mfe > g_exec.Point() * 20.0 && pl < 0.4 * t.mfe)
           {
            close_it = true;
            why = "MFE geri verildi";
           }
         // 4) Rejim savunmaya gectiyse tum mikro isler kapanir
         if(!close_it && (s.regime == (int)REGIME_DEFENSE_LOCK || g_risk.LockRequired()))
           {
            close_it = true;
            why = "savunma kilidi";
           }

         if(close_it)
           {
            double pnl_money = pl * t.lot * g_exec.PointValue();
            if(g_exec.CloseTicket(t.ticket, "SCALP: " + why))
              {
               g_risk.NoteClose(pnl_money, (int)ROLE_SCALP);
               m_action = StringFormat("Mikro-scalp kapandi: %s", why);
              }
            continue;
           }

         // 5) Izleyen stop: hedefin yarisindan sonra basa-bas + kilit
         if(pl > 0.5 * target && target > 0.0)
           {
            double be = g_exec.NormPrice(t.entry + t.side * g_exec.Point() * 2.0, t.side);
            bool improve = (t.side > 0) ? (be > t.sl) : (t.sl <= 0.0 || be < t.sl);
            if(improve)
               g_exec.ModifyStops(t.ticket, be, t.tp);
           }
        }
     }

   int BarsElapsed(const ENUM_TIMEFRAMES tf, const datetime from)
     {
      if(from <= 0)
         return 0;
      int sec = PeriodSeconds(tf);
      if(sec <= 0)
         return 0;
      return (int)((TimeCurrent() - from) / sec);
     }

   //------------------------------------------------------------------+
   //| Yeni mikro islem arama                                          |
   //+------------------------------------------------------------------+
   void TryOpenScalp(const SRegimeSnapshot &s, const double bid, const double ask)
     {
      if(!m_cfg.scalp_enabled)
         return;
      if(!g_sqz_scalp.Ready())
         return;

      int span = (int)MathMax(2, m_cfg.scalp_pivot);
      int s_last = g_sqz_scalp.LastClosed();
      int pivot_at = s_last - span;
      if(pivot_at < span + 2)
         return;

      int pivot = g_sqz_scalp.MicroPivot(pivot_at, span, 0.45);
      if(pivot == 0)
         return;

      double price = (pivot > 0 ? ask : bid);
      int dir = ScalpBias(s, price, pivot);
      if(dir == 0)
         return;

      int open_now = 0;
      for(int i = 0; i < ArraySize(m_track); i++)
         if(m_track[i].side == dir)
            open_now++;
      if(open_now >= m_cfg.scalp_max_open)
         return;

      // Soguma suresi
      if(m_cfg.scalp_cooldown_sec > 0 &&
         (TimeCurrent() - m_last_scalp_entry) < m_cfg.scalp_cooldown_sec)
         return;

      if(!g_risk.AllowNew((int)ROLE_SCALP, s.regime))
         return;

      // Geri cekilme kontrolu: mikro giris icin fiyat son uc bar asiri
      // noktasindan cok uzaklasmamis olmali (kovalamaca yasak)
      double swing = 0.0;
      for(int i = s_last; i > s_last - 3 && i >= 0; i--)
        {
         if(dir > 0) swing = (swing == 0.0 ? g_sqz_scalp.Low(i) : MathMin(swing, g_sqz_scalp.Low(i)));
         else        swing = (swing == 0.0 ? g_sqz_scalp.High(i) : MathMax(swing, g_sqz_scalp.High(i)));
        }
      double pullback = (s.atr > 0.0 ? s.atr * m_cfg.scalp_pullback_atr : g_exec.Point() * 100.0);
      if(swing > 0.0 && MathAbs(price - swing) > pullback)
         return;

      // Hedef / stop mesafeleri
      double tp_dist = (m_cfg.scalp_tp_points > 0 ? m_cfg.scalp_tp_points * g_exec.Point()
                                                  : (s.atr > 0.0 ? s.atr * 0.45 : g_exec.Point() * 100.0));
      double sl_dist = (m_cfg.scalp_sl_points > 0 ? m_cfg.scalp_sl_points * g_exec.Point()
                                                  : (s.atr > 0.0 ? s.atr * 0.35 : g_exec.Point() * 80.0));
      tp_dist = MathMax(tp_dist, g_exec.MinStopDist());
      sl_dist = MathMax(sl_dist, g_exec.MinStopDist());
      tp_dist = MathMax(tp_dist, g_exec.SpreadPoints() * g_exec.Point() * 3.0);

      double lot = ScalpLot(s, sl_dist);
      if(lot <= 0.0)
         return;

      double entry = (dir > 0 ? ask : bid);
      double sl = g_exec.NormPrice(entry - dir * sl_dist, -dir);
      double tp = g_exec.NormPrice(entry + dir * tp_dist, dir);

      ulong tk = g_exec.OpenMarket(dir, lot, sl, tp, (int)ROLE_SCALP, 0);
      if(tk != 0)
        {
         m_last_scalp_entry = TimeCurrent();
         m_action = StringFormat("Mikro-scalp %s lot=%.2f (tp=%.0fpt sl=%.0fpt)",
                                 ApexSideName(dir), lot, tp_dist / g_exec.Point(), sl_dist / g_exec.Point());
         if(m_cfg.verbose_log)
            PrintFormat("[APEX:SCALP] %s mikro islem acildi lot=%.2f | rejim=%s | pivot=%+d",
                        ApexSideName(dir), lot, ApexRegimeShort(s.regime), pivot);
        }
     }

   //------------------------------------------------------------------+
   //| SAVUNMA KALKANI (Delta-Notr Kilitleme)                          |
   //+------------------------------------------------------------------+
   double ExposureNetLots()
     {
      g_exec.RebuildBook();
      double net = 0.0;
      for(int i = 0; i < g_exec.BookSize(); i++)
        {
         SBookEntry e;
         if(!g_exec.BookAt(i, e))
            continue;
         if(e.role == (int)ROLE_HEDGE)
            continue;
         net += e.side * e.lot;
        }
      return net;
     }

   void EngageLock(const SRegimeSnapshot &s, const int reason)
     {
      if(m_locked)
         return;

      // 1) Tum bekleyen emirler iptal: yeni risk alinmayacak
      g_exec.DeleteOrdersRole((int)ROLE_GRID);

      // 2) Mikro isler kapatilir (kilitte sadece kalkan yasar)
      g_exec.CloseRole((int)ROLE_SCALP, "SAVUNMA KILIDI");

      // 3) Sentetik kilit: net pozisyonun karsisina kalkan
      double net = ExposureNetLots();
      double lots = MathAbs(net) * ApexClamp(m_cfg.hedge_ratio, 0.0, 1.0);
      lots = g_exec.NormVolume(lots);

      if(m_hedging_account && lots >= g_exec.LotMin() && MathAbs(net) >= g_exec.LotMin())
        {
         int side = (net > 0 ? -1 : 1);
         if(g_exec.CanAfford(lots, 300.0))
           {
            ulong tk = g_exec.OpenMarket(side, lots, 0.0, 0.0, (int)ROLE_HEDGE, 0);
            if(tk != 0)
               PrintFormat("[APEX:SHIELD] KALKAN KURULDU: net=%.2f lot -> karsisina %.2f lot %s",
                           net, lots, ApexSideName(side));
           }
         else
            Print("[APEX:SHIELD] UYARI: marjin yetersiz, kalkan kurulamadi - sadece dondurma modu.");
        }
      else if(!m_hedging_account && MathAbs(net) >= g_exec.LotMin())
        {
         // Netting hesap: karsit pozisyon acilamaz -> zararli bacaklar kapatilir
         Print("[APEX:SHIELD] Netting hesap: sentetik kilit yerine marjin azaltma uygulaniyor.");
         ReduceExposure(s);
        }

      m_locked       = true;
      m_lock_time    = TimeCurrent();
      m_lock_bar     = 0;
      m_lock_dd      = g_risk.DrawdownPct();
      m_lock_equity  = AccountInfoDouble(ACCOUNT_EQUITY);
      m_lock_reason  = reason;
      m_lock_net_lots= net;
      m_lock_bars    = 0;
      m_action       = "SAVUNMA KILIDI: delta notr kalkan devrede";
     }

   void DisengageLock(const string why)
     {
      if(!m_locked)
         return;
      g_exec.CloseRole((int)ROLE_HEDGE, "KILIT ACILDI: " + why);
      m_locked = false;
      m_lock_bars = 0;
      m_action = "KILIT ACILDI: " + why;
      PrintFormat("[APEX:SHIELD] Kilit acildi (%s). Normal operasyona donuluyor.", why);
     }

   // Marjin seviyesi duserken en kârli bacaklari kapatarak nefes aldirir
   void ReduceExposure(const SRegimeSnapshot &s)
     {
      g_exec.RebuildBook();
      ulong tk[];
      double pl[];
      int cnt = 0;
      for(int i = 0; i < g_exec.BookSize(); i++)
        {
         SBookEntry e;
         if(!g_exec.BookAt(i, e))
            continue;
         if(e.role == (int)ROLE_HEDGE)
            continue;
         int c = cnt;
         if(ArrayResize(tk, c + 1) < c + 1) break;
         if(ArrayResize(pl, c + 1) < c + 1) break;
         tk[c] = e.ticket;
         pl[c] = e.profit;
         cnt++;
        }
      for(int a = 0; a < cnt - 1; a++)
         for(int b = a + 1; b < cnt; b++)
            if(pl[b] > pl[a])
              {
               double tp = pl[a]; pl[a] = pl[b]; pl[b] = tp;
               ulong   tt = tk[a]; tk[a] = tk[b]; tk[b] = tt;
              }
      int closed = 0;
      for(int i = 0; i < cnt && g_exec.MarginLevelPct() < 500.0; i++)
        {
         g_exec.CloseTicket(tk[i], "MARJIN RAHATLATMA");
         closed++;
        }
      if(closed > 0)
         m_action = StringFormat("Marjin rahatlatma: %d bacak kapatildi", closed);
     }

   void ManageLock(const SRegimeSnapshot &s)
     {
      m_lock_bars++;

      // --- Kalkan bakiyesi ---
      m_hedge_pnl = g_exec.BasketProfit((int)ROLE_HEDGE, 0);

      // --- Marjin nefes borusu ---
      if(g_exec.MarginLevelPct() < 350.0)
         ReduceExposure(s);

      // --- BLACK kademe: kontrollu geri cekilme ---
      if(g_risk.LiquidationRequired() && m_cfg.allow_full_liquidation)
        {
         PrintFormat("[APEX:SHIELD] KONTROLLU GERI CEKILME: DD=%.2f%% - tum pozisyonlar kapatiliyor.",
                     g_risk.DrawdownPct());
         g_exec.DeleteOrdersRole(-1);
         g_exec.CloseRole(-1, "KILL-SWITCH: kontrollu geri cekilme");
         DisengageLock("kill-switch sonrasi tasfiye");
         return;
        }

      // --- Kalkan zarari tavan asarsa: ters bacaklar kapatilarak notrluk korunur
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_cfg.hedge_max_loss_pct > 0.0 && eq > 0.0 &&
         MathAbs(m_hedge_pnl) > m_cfg.hedge_max_loss_pct * 0.01 * eq)
        {
         PrintFormat("[APEX:SHIELD] Kalkan zarari tavan asildi (%.2f). Kademeli tasfiye.", m_hedge_pnl);
         ReduceExposure(s);
        }

      // --- Kilit acma kosullari (hepsi birlikte) ---
      bool dd_ok   = (g_risk.DrawdownPct() <= MathMax(0.0, m_lock_dd - m_cfg.unlock_recovery));
      bool cool_ok = (m_lock_bars >= m_cfg.lock_cooldown_bars);
      bool vol_ok  = (s.atr_z <= m_cfg.atr_z_expansion);
      bool tier_ok = !g_risk.LockRequired();
      bool reg_ok  = (s.regime != (int)REGIME_DEFENSE_LOCK);

      if(cool_ok && tier_ok && reg_ok && vol_ok && (dd_ok || m_lock_bars > m_cfg.lock_cooldown_bars * 3))
         DisengageLock(StringFormat("DD %.2f%% -> %.2f%%, ATRz=%.2f, %d bar soguma",
                                    m_lock_dd, g_risk.DrawdownPct(), s.atr_z, m_lock_bars));
     }

public:
                     CApexScalp()
     {
      m_last_scalp_bar   = 0;
      m_last_scalp_entry = 0;
      m_scalp_bar_count  = 0;
      m_locked           = false;
      m_lock_time        = 0;
      m_lock_bar         = 0;
      m_lock_dd          = 0.0;
      m_lock_equity      = 0.0;
      m_lock_reason      = 0;
      m_lock_net_lots    = 0.0;
      m_hedge_pnl        = 0.0;
      m_lock_bars        = 0;
      m_hedging_account  = true;
      m_action           = "";
      ArrayResize(m_track, 0);
     }
                    ~CApexScalp() { }

   void Init(const SApexConfig &cfg)
     {
      m_cfg = cfg;
      m_hedging_account = (AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
      ArrayResize(m_track, 0);
      m_locked = false;
     }

   bool   Locked()        { return m_locked; }
   int    LockBars()      { return m_lock_bars; }
   double HedgePnL()      { return m_hedge_pnl; }
   double LockedNetLots() { return m_lock_net_lots; }
   string Action()        { return m_action; }
   int    ScalpCount()    { return ArraySize(m_track); }

   //+------------------------------------------------------------------+
   //| ANA GIRIS: Mikro-scalp + hedge kalkani                           |
   //| Tick hizinda cagrilir; zaman dilimli gorev mimarisi icinde       |
   //| "yuksek frekansli motor" gorevini gorur.                         |
   //+------------------------------------------------------------------+
   void ExecuteHybridScalpAndDefense(SRegimeSnapshot &s, const double bid, const double ask)
     {
      if(bid <= 0.0 || ask <= 0.0)
         return;

      // ---------------- SAVUNMA KATMANI (oncelik her zaman burada) ----
      bool need_lock = (s.regime == (int)REGIME_DEFENSE_LOCK) || g_risk.LockRequired();
      if(need_lock && !m_locked)
         EngageLock(s, (s.regime == (int)REGIME_DEFENSE_LOCK) ? 1 : 2);

      if(m_locked)
        {
         ManageLock(s);
         // Kilitteyken yalnizca kalkan yasar; grid zaten FROZEN modunda
         return;
        }

      // ---------------- MIKRO-SCALP KATMANI ---------------------------
      if(!m_cfg.scalp_enabled)
         return;

      // Alt zaman dilimi serisini yeni mumda tazele
      datetime sb = g_sqz_scalp.LastBarTime();
      if(sb != m_last_scalp_bar)
        {
         m_last_scalp_bar = sb;
         m_scalp_bar_count++;
         g_sqz_scalp.Refresh(120);
        }
      if(m_scalp_bar_count < 30)   // istatistik isinmasi
         return;

      ManageOpenScalps(s, bid, ask);
      TryOpenScalp(s, bid, ask);
     }
  };

CApexScalp g_scalp;

#endif
//+------------------------------------------------------------------+

//==============================================================================
//| ANA EA GOVDE (ApexCombatEngine.mq5)
//==============================================================================
//+------------------------------------------------------------------+
//| 0) TEMEL / OPERASYON                                              |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 1) SQUEEZE MOMENTUM [LazyBear]                                    |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 2) CEKIRDEK SINYAL (orijinal EA mantigi - korundu)                |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 3) 5 BOYUTLU REJIM ANALIZI                                        |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 4) ELASTIK BUKALEMUN GRID                                         |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 5) MIKRO-SCALP MOTORU                                             |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 6) SAVUNMA / HEDGE KALKANI                                        |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 7) SERMAYE KORUMA GUVENLIK DUVARI                                 |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| 8) OTURUM VE ZAMANLAMA                                            |
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//| Global durum                                                      |
//+------------------------------------------------------------------+
SApexConfig     g_cfg;
SRegimeSnapshot g_snap;

bool            g_ready         = false;
datetime        g_last_bar_time = 0;
datetime        g_last_reconcile= 0;
datetime        g_last_panel    = 0;
ulong           g_last_tick_ms  = 0;
int             g_last_raw_signal = 0;
datetime        g_last_signal_time = 0;
double          g_last_signal_price = 0.0;
string          g_last_action   = "Baslatiliyor";
string          g_object_prefix = "";
bool            g_need_reconcile= false;
int             g_core_opened   = 0;
int             g_core_closed   = 0;
datetime        g_start_time    = 0;

//+------------------------------------------------------------------+
//| Konfigurasyon insasi (input -> SApexConfig)                       |
//+------------------------------------------------------------------+
void BuildConfig()
  {
   g_cfg.symbol            = _Symbol;
   g_cfg.magic             = InpMagicNumber;
   g_cfg.deviation         = InpDeviationPoints;
   g_cfg.tf_signal         = (InpTimeframe == PERIOD_CURRENT) ? (ENUM_TIMEFRAMES)Period() : InpTimeframe;
   g_cfg.tf_context        = InpContextTimeframe;
   g_cfg.tf_scalp          = InpScalpTimeframe;
   g_cfg.tf_signal_name    = EnumToString(g_cfg.tf_signal);
   g_cfg.tf_context_name   = EnumToString(g_cfg.tf_context);
   g_cfg.tf_scalp_name     = EnumToString(g_cfg.tf_scalp);

   g_cfg.bb_len            = InpBBLength;
   g_cfg.bb_mult           = InpBBMultFactor;
   g_cfg.kc_len            = InpKCLength;
   g_cfg.kc_mult           = InpKCMultFactor;
   g_cfg.use_true_range    = InpUseTrueRange;
   g_cfg.history_bars      = InpHistoryBars;

   g_cfg.reverse           = InpReverseTrading;
   g_cfg.open_buy          = InpOpenOnBuySignal;
   g_cfg.open_sell         = InpOpenOnSellSignal;
   g_cfg.allow_long        = InpAllowLongTrades;
   g_cfg.allow_short       = InpAllowShortTrades;
   g_cfg.tp_sig_count      = InpTPSignalCount;
   g_cfg.sl_sig_count      = InpSLSignalCount;
   g_cfg.fixed_tp_points   = InpFixedTPPoints;
   g_cfg.fixed_sl_points   = InpFixedSLPoints;
   g_cfg.base_lot          = InpBaseLot;
   g_cfg.max_positions     = InpMaxCorePositions;
   g_cfg.max_spread_points = InpMaxSpreadPoints;

   g_cfg.hurst_window      = InpHurstWindow;
   g_cfg.hurst_max_lag     = InpHurstMaxLag;
   g_cfg.hurst_trend       = InpHurstTrend;
   g_cfg.hurst_mr          = InpHurstMeanRevert;
   g_cfg.atr_period        = InpATRPeriod;
   g_cfg.atr_band_len      = InpATRBandLen;
   g_cfg.atr_z_expansion   = InpATRzExpansion;
   g_cfg.atr_z_explosive   = InpATRzExplosive;
   g_cfg.vp_lookback       = InpVPLookback;
   g_cfg.vp_buckets        = InpVPBuckets;
   g_cfg.va_pct            = InpValueAreaPct;
   g_cfg.deriv_len         = InpDerivLen;
   g_cfg.regime_margin     = InpRegimeMargin;
   g_cfg.regime_persistence= InpRegimePersistence;
   g_cfg.boot_bars         = InpBootBars;

   g_cfg.grid_enabled      = InpGridEnabled;
   g_cfg.grid_max_levels   = InpGridMaxLevels;
   g_cfg.grid_step_atr_mult= InpGridStepATRMult;
   g_cfg.grid_step_min_mult= InpGridMinMult;
   g_cfg.grid_step_max_mult= InpGridMaxMult;
   g_cfg.grid_lot_slope    = InpGridLotSlope;
   g_cfg.grid_lot_max_mult = InpGridLotMaxMult;
   g_cfg.grid_recenter_atr = InpGridRecenterATR;
   g_cfg.grid_basket_atr   = InpGridBasketATR;
   g_cfg.grid_basket_equity= InpGridBasketEqPct;
   g_cfg.grid_max_legs_total = InpGridMaxLegs;
   g_cfg.grid_cut_ratio    = InpGridCutRatio;
   g_cfg.grid_tp_atr       = InpGridTPATR;
   g_cfg.grid_sl_atr       = InpGridSLATR;

   g_cfg.scalp_enabled     = InpScalpEnabled;
   g_cfg.scalp_lot_mult    = InpScalpLotMult;
   g_cfg.scalp_tp_points   = InpScalpTPPoints;
   g_cfg.scalp_sl_points   = InpScalpSLPoints;
   g_cfg.scalp_max_open    = InpScalpMaxOpen;
   g_cfg.scalp_cooldown_sec= InpScalpCooldownSec;
   g_cfg.scalp_pivot       = InpScalpPivot;
   g_cfg.scalp_pullback_atr= InpScalpPullbackATR;
   g_cfg.scalp_max_bars    = InpScalpMaxBars;

   g_cfg.hedge_ratio       = InpHedgeRatio;
   g_cfg.lock_cooldown_bars= InpLockCooldownBars;
   g_cfg.unlock_recovery   = InpUnlockRecovery;
   g_cfg.hedge_max_loss_pct= InpHedgeMaxLossPct;
   g_cfg.allow_full_liquidation = InpAllowFullLiquidation;

   g_cfg.risk_per_trade_pct= InpRiskPerTrade;
   g_cfg.max_lot           = InpMaxLot;
   g_cfg.max_total_lots    = InpMaxTotalLots;
   g_cfg.dd_warn           = InpDDWarn;
   g_cfg.dd_defense        = InpDDDefense;
   g_cfg.dd_kill           = InpDDKill;
   g_cfg.daily_loss_limit  = InpDailyLossLimit;
   g_cfg.daily_profit_target = InpDailyProfitTarget;
   g_cfg.max_consec_loss   = 4;
   g_cfg.heal_rate         = InpHealRate;
   g_cfg.toxicity_decay    = InpToxicityDecay;

   g_cfg.use_session       = InpUseSession;
   g_cfg.session_start_hour= InpSessionStartHour;
   g_cfg.session_end_hour  = InpSessionEndHour;
   g_cfg.friday_close_hour = InpFridayCloseHour;
   g_cfg.tick_throttle_ms  = InpTickThrottleMs;
   g_cfg.reconcile_sec     = InpReconcileSec;
   g_cfg.show_panel        = InpShowPanel;
   g_cfg.draw_objects      = InpDrawArrows;
   g_cfg.verbose_log       = InpVerboseLog;
  }

//+------------------------------------------------------------------+
//| Dogrulama                                                         |
//+------------------------------------------------------------------+
bool ValidateInputs()
  {
   if(InpBBLength < 2 || InpKCLength < 2 || InpBBMultFactor <= 0.0 || InpKCMultFactor <= 0.0)
     { Print("Hata: BB/KC ayarlari gecersiz."); return false; }
   if(InpBaseLot <= 0.0 || InpMaxLot < InpBaseLot)
     { Print("Hata: lot ayarlari gecersiz."); return false; }
   if(InpDDWarn >= InpDDDefense || InpDDDefense >= InpDDKill)
     { Print("Hata: DD kademeleri siralanmamis (warn < defense < kill)."); return false; }
   if(InpGridCutRatio <= 0.0 || InpGridCutRatio > 1.0)
     { Print("Hata: grid kesme orani 0..1 araliginda olmali."); return false; }
   if(InpHurstMeanRevert >= InpHurstTrend)
     { Print("Hata: Hurst esikleri gecersiz (mr < trend)."); return false; }
   if(InpTPSignalCount < 0 || InpSLSignalCount < 0)
     { Print("Hata: sinyal sayimlari negatif olamaz."); return false; }
   if(InpTPSignalCount == 0 && InpSLSignalCount == 0 &&
      InpFixedTPPoints == 0 && InpFixedSLPoints == 0 && !InpGridEnabled && !InpScalpEnabled)
      Print("UYARI: Tum cikislar kapali; pozisyonlar yalnizca elle kapatilabilir.");
   return true;
  }

//+------------------------------------------------------------------+
//| Cekirdek sinyal: grafik oklari                                    |
//+------------------------------------------------------------------+
void DrawSignalArrow(const datetime bar_time, const double high, const double low, const int raw_signal)
  {
   if(!InpDrawArrows)
      return;
   string name = g_object_prefix + "sig" + IntegerToString((long)bar_time);
   if(ObjectFind(0, name) >= 0)
      return;
   double offset = MathMax((high - low) * 0.25, SymbolInfoDouble(_Symbol, SYMBOL_POINT) * 20.0);
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
//| ORIJINAL CIKIS MANTIGI: sinyal sayimi                             |
//| Pozisyon acildiktan SONRA gelen sinyaller sayilir. Pozisyon       |
//| yonuyle ayni yonde ve girisi gecen sinyaller TP, ters yonde       |
//| olanlar SL sayacini artirir. (Orijinal EA'dan birebir tasindi)   |
//+------------------------------------------------------------------+
int EvaluateCoreExit(const ulong ticket, string &reason, int &tp_count, int &sl_count)
  {
   reason   = "";
   tp_count = 0;
   sl_count = 0;

   if(!g_exec.IsOurTicket(ticket))
      return 0;

   long   type = PositionGetInteger(POSITION_TYPE);
   int    side = (type == POSITION_TYPE_BUY) ? 1 : -1;
   double entry = PositionGetDouble(POSITION_PRICE_OPEN);
   datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
   if(side == 0 || entry <= 0.0)
      return 0;

   int last_closed = g_sqz_main.LastClosed();
   if(last_closed < 1)
      return 0;
   int period_seconds = PeriodSeconds(g_cfg.tf_signal);
   if(period_seconds <= 0)
      period_seconds = 60;

   // Tarama baslangici: pozisyon acilisina denk gelen bara kadar geri git
   int start = 1;
   int back_limit = (int)MathMax(0, last_closed - 4000);
   for(int i = last_closed; i > back_limit; i--)
     {
      if(g_sqz_main.Time(i) < open_time)
        {
         start = i;
         break;
        }
     }

   for(int i = start; i <= last_closed; i++)
     {
      int signal = g_sqz_main.SignalAt(i);
      if(signal == 0)
         continue;
      datetime signal_close_time = g_sqz_main.Time(i) + period_seconds;
      if(signal_close_time <= open_time)
         continue;

      double signal_price = g_sqz_main.Close(i);
      bool is_tp = false, is_sl = false;
      if(side > 0)
        {
         is_tp = (signal > 0 && signal_price > entry);
         is_sl = (signal < 0 && signal_price < entry);
        }
      else
        {
         is_tp = (signal < 0 && signal_price < entry);
         is_sl = (signal > 0 && signal_price > entry);
        }

      if(is_tp)
        {
         tp_count++;
         if(InpTPSignalCount > 0 && tp_count >= InpTPSignalCount)
           {
            reason = StringFormat("TP (sinyal sayimi): %d. uygun %s sinyali, giris=%.*f sinyal=%.*f",
                                  tp_count, ApexSideName(signal), g_exec.Digits(), entry,
                                  g_exec.Digits(), signal_price);
            return 1;
           }
        }
      if(is_sl)
        {
         sl_count++;
         if(InpSLSignalCount > 0 && sl_count >= InpSLSignalCount)
           {
            reason = StringFormat("SL (sinyal sayimi): %d. uygun %s sinyali, giris=%.*f sinyal=%.*f",
                                  sl_count, ApexSideName(signal), g_exec.Digits(), entry,
                                  g_exec.Digits(), signal_price);
            return -1;
           }
        }
     }
   return 0;
  }

void ManageCoreSignalExits()
  {
   if(InpTPSignalCount <= 0 && InpSLSignalCount <= 0)
      return;

   g_exec.RebuildBook();
   for(int i = 0; i < g_exec.BookSize(); i++)
     {
      SBookEntry e;
      if(!g_exec.BookAt(i, e))
         continue;
      if(e.role != (int)ROLE_CORE)
         continue;
      string reason = "";
      int tp_c = 0, sl_c = 0;
      int res = EvaluateCoreExit(e.ticket, reason, tp_c, sl_c);
      if(res != 0)
        {
         if(g_exec.CloseTicket(e.ticket, reason))
            g_core_closed++;
        }
     }
  }

//+------------------------------------------------------------------+
//| AKILLI CIKIS MATRISI (Core pozisyonlar)                           |
//|  1) Sinyal sayimi (orijinal)                                      |
//|  2) Dinamik risk-odul: kâr >= RR x risk birimi -> sweep           |
//|  3) Momentum turevi sifirlandi -> sinyal beklemeden kâr realiz.   |
//|  4) Rejim evrimi: pozisyon yonu yeni rejimle celisiyorsa kapat    |
//|  5) Sure/volatilite tabanli izleyen stop                          |
//+------------------------------------------------------------------+
void ManageSmartExitMatrix(SRegimeSnapshot &s)
  {
   g_exec.RebuildBook();
   double atr = (s.atr > 0.0 ? s.atr : g_exec.Point() * 200.0);

   // Dinamik risk-odul carpanlari (rejim + kalicilik + guven)
   double rr = 1.5;
   if(s.persistence == (int)PERSIST_TREND)      rr *= 1.30;
   if(s.persistence == (int)PERSIST_MEAN_REVERT) rr *= 0.75;
   rr *= (0.75 + 0.45 * s.confidence);
   if(s.regime == (int)REGIME_VOLATILITY_TRAP)  rr *= 0.60;   // tuzakta cabuk al
   if(g_risk.Tier() >= (int)TIER_AMBER)         rr *= 0.70;   // ihtiyatli mod

   for(int i = 0; i < g_exec.BookSize(); i++)
     {
      SBookEntry e;
      if(!g_exec.BookAt(i, e))
         continue;
      if(e.role != (int)ROLE_CORE)
         continue;

      double risk_unit = atr * e.lot * g_exec.PointValue();   // 1 ATR = 1 risk birimi
      if(risk_unit <= 0.0)
         risk_unit = 1.0;

      // (3) Momentum yorgunlugu -> akilli kâr realizasyonu
      //     (gurultu cikisi olmamasi icin risk biriminin %15'i kadar kâr sarti)
      if(s.fatigue == 1 && e.profit > 0.15 * risk_unit)
        {
         if(g_exec.CloseTicket(e.ticket, "SMART PROFIT SWEEP: momentum turevi sifirlandi"))
            g_core_closed++;
         continue;
        }

      // (2) Dinamik risk-odul hedefi
      if(e.profit >= rr * risk_unit && e.profit > 0.0)
        {
         if(g_exec.CloseTicket(e.ticket, StringFormat("DINAMIK R:R %.2fx hedefe ulasildi", rr)))
            g_core_closed++;
         continue;
        }

      // (4) Rejim evrimi: BREAKOUT yonuyle celisen cekirdek pozisyon kapatilir
      if(s.regime == (int)REGIME_BREAKOUT_ATTACK && s.trend_dir != 0 &&
         e.side != s.trend_dir && s.confidence > 0.35)
        {
         if(g_exec.CloseTicket(e.ticket, "REAKSIYON: rejim tek yonlu ataga evrildi"))
            g_core_closed++;
         continue;
        }

      // (5) Izleyen stop: 1 ATR kârdan sonra basa-bas + 0.6 ATR trail
      if(e.profit > risk_unit)
        {
         double trail = atr * 0.60;
         double px = (e.side > 0 ? g_exec.Bid() : g_exec.Ask());
         double new_sl = g_exec.NormPrice(px - e.side * trail, -e.side);
         bool valid = (e.side > 0) ? (new_sl > e.sl && new_sl > e.entry)
                                   : ((e.sl <= 0.0 || new_sl < e.sl) && new_sl < e.entry);
         if(valid)
            g_exec.ModifyStops(e.ticket, new_sl, e.tp);
        }
     }
  }

//+------------------------------------------------------------------+
//| Cekirdek giris: orijinal sinyal kurallari (degistirilmedi)       |
//+------------------------------------------------------------------+
void ProcessCoreSignal(SRegimeSnapshot &s)
  {
   int last = g_sqz_main.LastClosed();
   if(last < 1)
      return;

   int raw = g_sqz_main.SignalAt(last);
   if(raw == 0)
      return;

   g_last_raw_signal   = raw;
   g_last_signal_time  = g_sqz_main.Time(last);
   g_last_signal_price = g_sqz_main.Close(last);

   DrawSignalArrow(g_sqz_main.Time(last), g_sqz_main.High(last), g_sqz_main.Low(last), raw);

   if(raw > 0 && !InpOpenOnBuySignal)
      return;
   if(raw < 0 && !InpOpenOnSellSignal)
      return;

   int side = InpReverseTrading ? -raw : raw;
   if(side > 0 && !InpAllowLongTrades)
      return;
   if(side < 0 && !InpAllowShortTrades)
      return;

   // Rejim uyumu: tuzak rejiminde cekirdek giris sayisi azaltilir
   if(s.regime == (int)REGIME_VOLATILITY_TRAP && s.confidence > 0.4)
      return;
   if(!g_risk.AllowNew((int)ROLE_CORE, s.regime))
      return;
   if(InpMaxCorePositions > 0 && g_exec.CountPos((int)ROLE_CORE, 0) >= InpMaxCorePositions)
      return;
   if(InpMaxSpreadPoints > 0 && g_exec.SpreadPoints() > InpMaxSpreadPoints)
      return;

   double bid = g_exec.Bid();
   double ask = g_exec.Ask();
   if(bid <= 0.0 || ask <= 0.0)
      return;
   double entry = (side > 0 ? ask : bid);

   double sl = 0.0, tp = 0.0;
   double atr = (s.atr > 0.0 ? s.atr : g_exec.Point() * 200.0);
   if(InpFixedSLPoints > 0)
      sl = g_exec.NormPrice(entry - side * InpFixedSLPoints * g_exec.Point(), -side);
   if(InpFixedTPPoints > 0)
      tp = g_exec.NormPrice(entry + side * InpFixedTPPoints * g_exec.Point(), side);
   if(InpFixedSLPoints <= 0)
      sl = g_exec.NormPrice(entry - side * atr * 2.0, -side);   // guvenlik agi

   double lot = g_cfg.base_lot;
   double sl_dist = MathAbs(entry - sl);
   // Tavan: cekirdek islemde risk modeli taban lotun 4 katini asamaz
   double cap = g_cfg.base_lot * 4.0;
   lot = g_risk.RiskLotCapped(sl_dist, lot, g_risk.SizeMultiplier(), cap);
   lot = g_risk.ExposureCap(lot, g_cfg.max_total_lots);
   if(lot <= 0.0)
      return;

   ulong tk = g_exec.OpenMarket(side, lot, sl, tp, (int)ROLE_CORE, 0);
   if(tk != 0)
     {
      g_core_opened++;
      g_last_action = StringFormat("Cekirdek %s acildi (sinyal %s, rejim %s)",
                                   ApexSideName(side), ApexSideName(raw), ApexRegimeShort(s.regime));
     }
  }

//+------------------------------------------------------------------+
//| GOREV G1: Yeni mum (bar bazli agir isler)                         |
//+------------------------------------------------------------------+
void OnNewSignalBar()
  {
   // 1) Serileri tazele
   g_sqz_main.Refresh(400);
   g_sqz_ctx.Refresh(200);

   // 2) Risk guncelle + 5 boyutlu rejim tespiti
   g_risk.Update(true);
   g_analytics.CountBar();
   if(!g_analytics.DetectAdvancedMarketRegime(g_snap))
     {
      g_last_action = "Rejim verisi olgunlasiyor";
      return;
     }

   // 3) Sermaye koruma override: kademe RED ise rejim dogrudan savunmaya cekilir
   if(g_risk.LockRequired() && g_snap.regime != (int)REGIME_DEFENSE_LOCK)
     {
      g_snap.prev_regime = g_snap.regime;
      g_snap.regime      = (int)REGIME_DEFENSE_LOCK;
      g_snap.posture     = (int)POSTURE_SHIELD;
      g_analytics.ForceRegime((int)REGIME_DEFENSE_LOCK);
     }
   else if(!g_risk.LockRequired() && g_snap.regime == (int)REGIME_DEFENSE_LOCK)
     {
      g_analytics.ForceRegime((int)REGIME_MEAN_REVERSION);   // skor motoru devralir
     }

   // 4) Cekirdek cikislar (sinyal sayimi) -> akilli cikis matrisi -> yeni giris
   ManageCoreSignalExits();
   ManageSmartExitMatrix(g_snap);
   ProcessCoreSignal(g_snap);

   // 5) Elastik grid (mod evrimi + sepet yonetimi)
   double bid = g_exec.Bid();
   double ask = g_exec.Ask();
   g_grid.ManageAdaptiveElasticGrid(g_snap, bid, ask);

   if(InpVerboseLog)
      PrintFormat("[APEX:BAR] %s | %s | H=%.2f ATRz=%.2f momZ=%.2f vel=%.4f flip=%.2f POC=%.*f",
                  TimeToString(TimeCurrent(), TIME_DATE | TIME_SECONDS),
                  ApexRegimeShort(g_snap.regime), g_snap.hurst, g_snap.atr_z,
                  g_snap.mom_z, g_snap.vel, g_snap.flip_rate, g_exec.Digits(), g_snap.poc);
  }

void CheckNewBar()
  {
   datetime t = iTime(_Symbol, g_cfg.tf_signal, 0);
   if(t <= 0)
      return;
   if(g_last_bar_time == 0)
     {
      g_last_bar_time = t;
      return;
     }
   if(t == g_last_bar_time)
      return;
   g_last_bar_time = t;
   OnNewSignalBar();
  }

//+------------------------------------------------------------------+
//| GOREV G0: Tick bazli yuksek frekansli motor                       |
//+------------------------------------------------------------------+
void FastLoop()
  {
   ulong now = GetTickCount();
   if(g_cfg.tick_throttle_ms > 0 && (now - g_last_tick_ms) < (ulong)g_cfg.tick_throttle_ms)
      return;
   g_last_tick_ms = now;

   double bid = g_exec.Bid();
   double ask = g_exec.Ask();
   if(bid <= 0.0 || ask <= 0.0)
      return;

   g_risk.Update(false);
   g_scalp.ExecuteHybridScalpAndDefense(g_snap, bid, ask);
  }

//+------------------------------------------------------------------+
//| GOREV G2: Defter mutabakati (kendi kendini onarma)                |
//+------------------------------------------------------------------+
void ReconcileTask()
  {
   if(g_cfg.reconcile_sec <= 0)
      return;
   if((TimeCurrent() - g_last_reconcile) < g_cfg.reconcile_sec && !g_need_reconcile)
      return;
   g_last_reconcile = TimeCurrent();
   g_need_reconcile = false;

   int before = g_exec.BookSize();
   g_exec.RebuildBook();
   int after = g_exec.BookSize();
   if(after != before && InpVerboseLog)
      PrintFormat("[APEX:BOOK] Mutabakat: %d -> %d pozisyon", before, after);

   // Yetim emir temizligi: savunma kilitli degilse ve grid dondurulmussa
   if(g_scalp.Locked() || g_grid.Mode() == (int)GRID_MODE_FROZEN)
      g_exec.DeleteOrdersRole((int)ROLE_GRID);
  }

//+------------------------------------------------------------------+
//| Bilgi paneli                                                      |
//+------------------------------------------------------------------+
void UpdatePanel()
  {
   if(!InpShowPanel)
     {
      Comment("");
      return;
     }
   ulong now = GetTickCount();
   if((now - g_last_panel) < 400)
      return;   // paneli her tikta yeniden cizme
   g_last_panel = (datetime)now;

   string dims = StringFormat(
      "D1 Squeeze : %s | sikisma %d bar | salinim %d bar once | enerji %.2f | titreme %d\n"
      "D2 Hurst   : %.3f  (%s)\n"
      "D3 ATR     : %.*f | fiyatin yuzde %.3f | z=%+.2f | band=%s\n"
      "D4 Hacim   : POC %.*f  VAL %.*f  VAH %.*f | konum=%s denge=%.2f emilim=%.2f CVD=%+.2f\n"
      "D5 Mom.Tur : mom=%+.4f (z=%+.2f) hiz=%+.4f ivme=%+.4f flip=%.2f %s%s\n",
      (g_snap.sqz_state == (int)APX_SQZST_ON ? "SIKISMA" : (g_snap.sqz_state == (int)APX_SQZST_OFF ? "SALINIM" : "notr")),
      g_snap.sqz_compress_bars, g_snap.bars_since_release, g_snap.sqz_energy, g_snap.sqz_flicker,
      g_snap.hurst, (g_snap.persistence == (int)PERSIST_TREND ? "trend kalici" :
                     (g_snap.persistence == (int)PERSIST_MEAN_REVERT ? "ortalamaya donus" : "rastgele")),
      g_exec.Digits(), g_snap.atr, g_snap.atr_pct * 100.0, g_snap.atr_z, ApexVolBandName(g_snap.vol_band),
      g_exec.Digits(), g_snap.poc, g_exec.Digits(), g_snap.val, g_exec.Digits(), g_snap.vah,
      (g_snap.vp_pos > 0 ? "PREMIUM(VAH ustu)" : (g_snap.vp_pos < 0 ? "ISKONTO(VAL alti)" : "DENGE(VA icinde)")),
      g_snap.balance, g_snap.absorption, g_snap.cvd_slope,
      g_snap.mom, g_snap.mom_z, g_snap.vel, g_snap.accel, g_snap.flip_rate,
      (g_snap.fatigue == 1 ? "[YORGUN]" : ""), (g_snap.vel_zero_cross == 1 ? "[HIZ-SIFIR]" : ""));

   string scores = StringFormat("Skorlar: ACC %.0f | ATK %.0f | MRG %.0f | TRAP %.0f | guven %.2f\n",
                                g_snap.score[(int)REGIME_ACCUMULATION],
                                g_snap.score[(int)REGIME_BREAKOUT_ATTACK],
                                g_snap.score[(int)REGIME_MEAN_REVERSION],
                                g_snap.score[(int)REGIME_VOLATILITY_TRAP],
                                g_snap.confidence);

   string grid = StringFormat(
      "GRID: %s | merkez %.*f | adim %.1f pt (%.2f ATR) | bacak %d/%d | sepet hedef %.2f\n",
      ApexGridModeName(g_grid.Mode()), g_exec.Digits(), g_grid.Anchor(),
      (g_exec.Point() > 0.0 ? g_grid.Step() / g_exec.Point() : 0.0),
      (g_snap.atr > 0.0 ? g_grid.Step() / g_snap.atr : 0.0),
      g_exec.CountPos((int)ROLE_GRID, 0) + g_exec.CountOrders((int)ROLE_GRID),
      g_cfg.grid_max_legs_total, g_grid.BasketTarget());

   string shield = StringFormat(
      "KALKAN: %s | net delta %.2f | hedge PnL %.2f | kilit suresi %d bar\n",
      (g_scalp.Locked() ? "DEVREDE (delta notr)" : "kapali"),
      g_exec.NetDeltaMoney(-1), g_scalp.HedgePnL(), g_scalp.LockBars());

   Comment(
      "=== APEX COMBAT ENGINE v2.00 ===\n",
      _Symbol, " | TF ", g_cfg.tf_signal_name, " / baglam ", g_cfg.tf_context_name,
      " / scalp ", g_cfg.tf_scalp_name, "\n",
      "REJIM: ", ApexRegimeName(g_snap.regime), " (", IntegerToString(g_snap.bars_in_regime), " bar) | ",
      "DURUS: ", ApexPostureName(g_snap.posture), " | yon ", ApexSideName(g_snap.trend_dir), "\n",
      dims, scores, grid, shield,
      "RISK: ", g_risk.Status(), "\n",
      "Pozisyon: CORE ", IntegerToString(g_exec.CountPos((int)ROLE_CORE, 0)),
      " | GRID ", IntegerToString(g_exec.CountPos((int)ROLE_GRID, 0)),
      " | SCALP ", IntegerToString(g_exec.CountPos((int)ROLE_SCALP, 0)),
      " | HEDGE ", IntegerToString(g_exec.CountPos((int)ROLE_HEDGE, 0)),
      " | emir ", IntegerToString(g_exec.CountOrders(-1)), "\n",
      "Sepet PnL: ", DoubleToString(g_exec.BasketProfit(-1, 0), 2),
      " | spread ", DoubleToString(g_exec.SpreadPoints(), 1), " pt",
      " | marjin sev. ", DoubleToString(g_exec.MarginLevelPct(), 0), "%\n",
      "Grid: ", g_grid.Action(), "\n",
      "Scalp/Def: ", g_scalp.Action(), "\n",
      "Durum: ", g_last_action);
  }

//+------------------------------------------------------------------+
//| Standart olaylar                                                  |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_start_time = TimeCurrent();
   if(!ValidateInputs())
      return INIT_PARAMETERS_INCORRECT;

   if(InpRequireHedging &&
      AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      Print("Apex Combat Engine: elastik grid ve delta-notr kilit hedging hesap gerektirir. "
            "Netting hesapta InpRequireHedging=false yapilabilir (kilit yerine marjin azaltma uygulanir).");
      return INIT_FAILED;
     }
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("UYARI: Netting hesap. Sentetik kilit yerine marjin azaltma modu kullanilacak.");

   if(!SymbolSelect(_Symbol, true))
     {
      Print("Sembol secilemedi.");
      return INIT_FAILED;
     }

   BuildConfig();

   if(!g_exec.Init(g_cfg))
     {
      Print("Yurutme katmani baslatilamadi (tick value/lot bilgisi yok).");
      return INIT_FAILED;
     }

   if(!g_sqz_main.Init(g_cfg, g_cfg.tf_signal, 400))
     { Print("Ana squeeze serisi yuklenemedi."); return INIT_FAILED; }
   g_sqz_ctx.Init(g_cfg, g_cfg.tf_context, 200);
   g_sqz_scalp.Init(g_cfg, g_cfg.tf_scalp, 120);

   g_analytics.Init(g_cfg);
   g_risk.Init(g_cfg);
   g_grid.Init(g_cfg);
   g_scalp.Init(g_cfg);

   ApexResetSnapshot(g_snap);
   g_analytics.DetectAdvancedMarketRegime(g_snap);

   g_object_prefix = StringFormat("APX_%I64u_%s_%s_", InpMagicNumber, _Symbol, g_cfg.tf_signal_name);
   g_last_bar_time = iTime(_Symbol, g_cfg.tf_signal, 0);
   g_ready = true;

   EventSetTimer(1);
   PrintFormat("APEX COMBAT ENGINE HAZIR | %s | TF=%s | magic=%I64u | lot=%.2f | grid=%s scalp=%s",
               _Symbol, g_cfg.tf_signal_name, InpMagicNumber, InpBaseLot,
               (InpGridEnabled ? "ACIK" : "KAPALI"), (InpScalpEnabled ? "ACIK" : "KAPALI"));
   Print("Rejim motoru isinma asamasinda; ilk barlarda grid/agresif mod devre disidir.");
   UpdatePanel();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(InpDeleteArrowsOnExit)
      DeleteOwnObjects();
   Comment("");
   PrintFormat("APEX durduruldu. Cekirdek islem: %d acildi / %d kapandi. Sure: %d sn",
               g_core_opened, g_core_closed, (int)(TimeCurrent() - g_start_time));
  }

void OnTick()
  {
   if(!g_ready)
      return;
   CheckNewBar();
   FastLoop();
   ReconcileTask();
   UpdatePanel();
  }

void OnTimer()
  {
   if(!g_ready)
      return;
   // Ticksiz zaman dilimlerinde de motor yasamaya devam eder
   CheckNewBar();
   FastLoop();
   ReconcileTask();
   UpdatePanel();
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(!g_ready)
      return;
   // Dolum/iptal sonrasi defter yeniden insa edilir (self-healing tetikleyici)
   if(trans.type == TRADE_TRANSACTION_DEAL_ADD ||
      trans.type == TRADE_TRANSACTION_ORDER_ADD ||
      trans.type == TRADE_TRANSACTION_ORDER_DELETE ||
      trans.type == TRADE_TRANSACTION_POSITION)
      g_need_reconcile = true;
  }

double OnTester()
  {
   // Optimizasyon hedefi: risk ayarli bilesik skor
   double profit   = TesterStatistics(STAT_PROFIT);
   double dd_rel   = TesterStatistics(STAT_EQUITY_DDREL_PERCENT);
   double recovery = TesterStatistics(STAT_RECOVERY_FACTOR);
   double sharpe   = TesterStatistics(STAT_SHARPE_RATIO);
   double score    = profit;
   if(dd_rel > 0.0)
      score = profit / (1.0 + dd_rel * 0.05);
   score *= (1.0 + ApexClamp(recovery, 0.0, 10.0) * 0.05);
   score *= (1.0 + ApexClamp(sharpe, -2.0, 5.0) * 0.05);
   return score;
  }
//+------------------------------------------------------------------+
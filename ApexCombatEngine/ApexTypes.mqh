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

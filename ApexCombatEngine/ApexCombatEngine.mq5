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

#include "ApexTypes.mqh"
#include "ApexTrade.mqh"
#include "ApexSqueezeCore.mqh"
#include "ApexAnalytics.mqh"
#include "ApexRisk.mqh"
#include "ApexGrid.mqh"
#include "ApexScalp.mqh"

//+------------------------------------------------------------------+
//| 0) TEMEL / OPERASYON                                              |
//+------------------------------------------------------------------+
input group "0) Temel ayarlar"
input ulong  InpMagicNumber        = 20261107;  // Magic Number
input int    InpDeviationPoints    = 20;        // Maksimum sapma (point)
input bool   InpRequireHedging     = true;      // Hedging hesap zorunlu (grid + kilit icin)
input bool   InpShowPanel          = true;      // Grafikte bilgi paneli
input bool   InpDrawArrows         = true;      // Sinyal oklari
input bool   InpDeleteArrowsOnExit = true;      // Cikista oklari sil
input bool   InpVerboseLog         = false;     // Ayrintili log

//+------------------------------------------------------------------+
//| 1) SQUEEZE MOMENTUM [LazyBear]                                    |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| 2) CEKIRDEK SINYAL (orijinal EA mantigi - korundu)                |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| 3) 5 BOYUTLU REJIM ANALIZI                                        |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| 4) ELASTIK BUKALEMUN GRID                                         |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| 5) MIKRO-SCALP MOTORU                                             |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| 6) SAVUNMA / HEDGE KALKANI                                        |
//+------------------------------------------------------------------+
input group "6) Savunma kilidi ve hedge kalkani"
input double InpHedgeRatio         = 1.00;  // Net pozisyonun kacina kalkan (1 = tam notr)
input int    InpLockCooldownBars   = 20;    // Kilit minimum sure (bar)
input double InpUnlockRecovery     = 0.35;  // Kilit acmak icin DD iyilesmesi (yuzde puan)
input double InpHedgeMaxLossPct    = 1.50;  // Kalkan zarar tavani (equity %)
input bool   InpAllowFullLiquidation = true;// Kill-switch'te tam tasfiye

//+------------------------------------------------------------------+
//| 7) SERMAYE KORUMA GUVENLIK DUVARI                                 |
//+------------------------------------------------------------------+
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

//+------------------------------------------------------------------+
//| 8) OTURUM VE ZAMANLAMA                                            |
//+------------------------------------------------------------------+
input group "8) Oturum ve gorev zamanlamasi"
input bool   InpUseSession         = false; // Oturum filtresi
input int    InpSessionStartHour   = 8;     // Baslangic saati (sunucu)
input int    InpSessionEndHour     = 20;    // Bitis saati (sunucu)
input int    InpFridayCloseHour    = 19;    // Cuma kapanis saati
input int    InpTickThrottleMs     = 250;   // Tick motoru ertelemesi (ms)
input int    InpReconcileSec       = 20;    // Defter mutabakat araligi (sn)

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
   g_last_panel = now;

   string dims = StringFormat(
      "D1 Squeeze : %s | sikisma %d bar | salinim %d bar once | enerji %.2f | titreme %d\n"
      "D2 Hurst   : %.3f  (%s)\n"
      "D3 ATR     : %.*f | fiyatin yuzde %.3f | z=%+.2f | band=%s\n"
      "D4 Hacim   : POC %.*f  VAL %.*f  VAH %.*f | konum=%s denge=%.2f emilim=%.2f CVD=%+.2f\n"
      "D5 Mom.Tur : mom=%+.4f (z=%+.2f) hiz=%+.4f ivme=%+.4f flip=%.2f %s%s\n",
      (g_snap.sqz_state == (int)APX_SQZ_ON ? "SIKISMA" : (g_snap.sqz_state == (int)APX_SQZ_OFF ? "SALINIM" : "notr")),
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

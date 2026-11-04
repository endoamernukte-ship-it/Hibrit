//+------------------------------------------------------------------+
//|                                       ScalperProGoldEA.mq5       |
//|                                                                    |
//|  Scalper Pro Gold EA v2                                           |
//|  - Sinyal motoru: "Nadaraya-Watson Regression Liquidity Sweeps     |
//|    [AlgoAlpha]" Pine Script® v6 göstergesi ile BİREBİR             |
//|  - Pine'daki 12 sinyalin tamamı + klasik pivot kırılım sinyalleri  |
//|    gruplanmış, MT5 ayarlarından tek tek/seçerek/HEPSİ seçilebilir  |
//|  - ScalperProGold mevcut özellikleri korunur:                      |
//|      otomatik/sinyal modu, lot modları, ters işlem modu,           |
//|      zıt sinyal çıkışı, TP/SL garantisi (klasik sinyallerde),      |
//|      bakiye trailing stop, hedge/netting, bildirimler, panel        |
//|                                                                    |
//|  Giriş kuralları:                                                  |
//|   - NW sinyalleri: SL/TP KULLANILMAZ (kullanıcı seçimi) -          |
//|     pozisyon YALNIZCA zıt sinyal sayacıyla kapanır                  |
//|   - Klasik sinyaller: SL = son pivot, TP = risk × çarpan           |
//+------------------------------------------------------------------+
#property copyright "ScalperProGoldEA v2 - NW Liquidity + klasik sinyaller"
#property version   "2.00"
#property description "Nadaraya-Watson Liquidity sinyalleri + klasik pivot kirilimi"
#property description "Sinyaller gruplu/secilebilir; tum mevcut ozellikler korunur"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Girdi tipleri                                                      |
//+------------------------------------------------------------------+
enum ENUM_SP_TRADE_MODE
  {
   SP_TRADE_OFF = 0,     // Sadece sinyal / çizim
   SP_TRADE_ON  = 1      // Otomatik pozisyon aç
  };

enum ENUM_SP_LOT_MODE
  {
   SP_LOT_FIXED = 0,     // Sabit lot
   SP_LOT_RISK  = 1      // Risk yüzdesi
  };

enum ENUM_SIG_DIR
  {
   SIG_OFF    = 0,       // Kullanma (kapalı)
   SIG_LONG   = 1,       // LONG aç
   SIG_SHORT  = 2        // SHORT aç
  };

//+------------------------------------------------------------------+
//| Girdiler                                                           |
//+------------------------------------------------------------------+
input group              "═══ NW Sinyal Motoru (Pine birebir) ═══"
input int                InpNWNormLen     = 100;   // Normalization Length (stdev penceresi)
input int                InpNWBandwidth   = 30;    // Nadaraya-Watson Bandwidth
input int                InpNWLookback    = 140;   // Nadaraya-Watson Lookback
input int                InpNWOscSmooth   = 21;    // Oscillator Smoothing Length (WMA)
input int                InpNWSigLen      = 14;    // Signal Length (EMA)
input int                InpNWATRLen      = 14;    // ATR Length
input int                InpNWVolSmooth   = 21;    // Volatility Smoothing Length
input bool               InpNWUseTip      = true;  // Use Swing Points (likidite seviyesi çapası)
input bool               InpNWDrawLevels  = true;  // Likidite seviyesi çizgilerini çiz
input bool               InpNWDrawMarkers = true;  // Momentum/rebound işaretlerini çiz
input color              InpNWBullColor   = C'0,255,187';  // Boğa rengi (yeşil)
input color              InpNWBearColor   = C'255,17,0';   // Ayı rengi (kırmızı)

input group              "═══ Sinyaller: Momentum Zayıflama ═══"
input ENUM_SIG_DIR       InpSigWeakenBull = SIG_SHORT; // Weakening Bullish Momentum
input ENUM_SIG_DIR       InpSigWeakenBear = SIG_LONG;  // Weakening Bearish Momentum

input group              "═══ Sinyaller: Sinyal Kesişimi ═══"
input ENUM_SIG_DIR       InpSigBullCross  = SIG_LONG;  // Bullish Signal Cross (osc ↑ signal)
input ENUM_SIG_DIR       InpSigBearCross  = SIG_SHORT; // Bearish Signal Cross (osc ↓ signal)

input group              "═══ Sinyaller: Sıfır Kesişimi ═══"
input ENUM_SIG_DIR       InpSigBullZero   = SIG_LONG;  // Bullish Zero Cross (osc ↑ 0)
input ENUM_SIG_DIR       InpSigBearZero   = SIG_SHORT; // Bearish Zero Cross (osc ↓ 0)

input group              "═══ Sinyaller: Likidite Seviyeleri ═══"
input ENUM_SIG_DIR       InpSigNewUpper   = SIG_SHORT; // New Upper Liquidity Level
input ENUM_SIG_DIR       InpSigNewLower   = SIG_LONG;  // New Lower Liquidity Level
input ENUM_SIG_DIR       InpSigUpperSwept = SIG_SHORT; // Upper Liquidity Level Swept
input ENUM_SIG_DIR       InpSigLowerSwept = SIG_LONG;  // Lower Liquidity Level Swept

input group              "═══ Sinyaller: Rebound ═══"
input ENUM_SIG_DIR       InpSigBullRebound = SIG_LONG; // Bullish Rebound (▲)
input ENUM_SIG_DIR       InpSigBearRebound = SIG_SHORT;// Bearish Rebound (▼)

input group              "═══ Sinyaller: Klasik ScalperPro ═══"
input ENUM_SIG_DIR       InpSigClassicBull = SIG_LONG; // Klasik LONG pivot kırılımı
input ENUM_SIG_DIR       InpSigClassicBear = SIG_SHORT;// Klasik SHORT pivot kırılımı

input group              "═══ Strategy (Klasik - SL/TP) ═══"
input double             InpTargetMult      = 2.0;   // Target Multiplier (Risk:Reward)
input int                InpBoxLength       = 5;     // Drawing Box Length (Bars)
input int                InpPivotLength     = 3;     // Structure Pivot Length

input group              "═══ Consolidation Filter (Sıkışma) ═══"
input bool               InpUseConsolidation = true; // Require Consolidation Before Breakout
input int                InpConsLength      = 10;    // Consolidation Length (Bars)
input double             InpAtrMult         = 3.0;   // Max Range (ATR Multiplier)

input group              "═══ Cooldown Filter ═══"
input bool               InpUseCooldown     = true;  // Enable Cooldown Between Trades
input int                InpCooldownBars    = 30;    // Cooldown Length (Bars)

input group              "═══ Trade (İşlem) ═══"
input ENUM_SP_TRADE_MODE InpTradeMode       = SP_TRADE_ON; // İşlem modu
input bool               InpReverseMode     = false; // Ters İşlem Modu (sinyal yönü ters açılır)
input bool               InpUseOppExit      = false; // Zıt Sinyal Çıkışı (KLASİK işlemler için; NW her zaman sayacı kullanır)
input int                InpOppExitCount    = 3;     // Kaç zıt sinyalde kapansın
input ENUM_SP_LOT_MODE   InpLotMode         = SP_LOT_FIXED; // Lot modu
input double             InpFixedLot        = 0.1;   // Sabit lot
input double             InpRiskPercent     = 1.0;   // Risk % (bakiye)
input int                InpMaxBarsInTrade  = 0;     // Ekstra: kaç bar sonra kapat (0 = kapalı, klasik)
input bool               InpAllowMultiple   = true;  // Eş zamanlı çoklu pozisyona izin ver
input long               InpMagic           = 20261031; // Magic number
input ulong              InpDeviation       = 30;    // Slippage (points)

input group              "═══ Appearance (Görsel) ═══"
input bool               InpDrawSetups      = true;  // Klasik kutu/etiket/çizgileri çiz
input int                InpDrawHistoryBars = 500;   // Geçmişte çizim yapılan bar sayısı
input color              InpEntryColor      = C'0,0,255';    // ENTRY rengi (mavi)
input color              InpStopColor       = C'255,0,0';    // STOP LOSS rengi (kırmızı)
input color              InpTargetColor     = C'0,128,128';  // TARGET rengi (teal)

input group              "═══ Notifications (Bildirim) ═══"
input bool               InpAlertsOn        = false; // Terminal Alert()
input bool               InpPushOn          = false; // Push bildirimi

input group              "═══ Advanced (Gelişmiş) ═══"
input int                InpMaxHistoryBars  = 20000; // İşlenecek maks. geçmiş bar (0 = tümü)

input group              "═══ Bakiye Trailing Stop ═══"
input bool               InpEquityTrailOn   = true;   // Bakiye (varlık) trailing stop aktif
input double             InpEquityGivebackPct = 50.0; // Kârın %'si geri verilince TÜM pozisyonları kapat
input bool               InpEquityOnlyMagic = false;  // Yalnız kendi (magic) pozisyonlarını kapat
input double             InpEquityTrailMinProfit = 1.0; // Devreye girme: kâr eşiği (hesap parası; 0 = hemen)
input int                InpEquityTrailDelayMin  = 0;   // Devreye girme: başlangıçtan sonra dk (0 = hemen)

//+------------------------------------------------------------------+
//| Sabitler                                                           |
//+------------------------------------------------------------------+
#define ATR_LENGTH                14
#define MAX_SETUPS_ON_CHART       160
#define NO_BAR                    (-1)
#define NA_DOUBLE                 EMPTY_VALUE
#define MAX_EVENTS                16

//+------------------------------------------------------------------+
//| İşlem kaydı                                                       |
//+------------------------------------------------------------------+
struct SPTradeRec
  {
   ulong  ticket;
   int    dir;         // +1 long, -1 short (işlem yönü)
   int    sigDir;      // sinyalin HAM yönü (enum) - zıt sinyal sayacı için
   int    oppCount;    // sayılan zıt sinyal sayısı
   bool   noSLTP;      // true = NW işlemi (SL/TP yok; yalnız sinyal sayacı kapatır)
   long   signalBar;
   double entryPrice;
   double stopPrice;   // noSLTP ise 0
   double targetPrice; // noSLTP ise 0
  };

//+------------------------------------------------------------------+
//| Global durum                                                       |
//+------------------------------------------------------------------+
double   g_tickSize;
int      g_digits;
bool     g_isHedge;
long     g_barIndex;
datetime g_lastBarTime;
bool     g_historyDone;
int      g_atrHandle;

// klasik yapı takibi
double   g_lastPivotHigh;
double   g_lastPivotLow;
long     g_lastTradeBar;

string   g_setupNames[];
SPTradeRec g_trades[];
long     g_tradeIdSeq;

// sinyal anındaki kurulum (çekirdek -> OnTick aktarımı)
int      g_sigDir;
int      g_sigRawDir;
bool     g_sigNoSLTP;
string   g_sigName;
double   g_sigEntry, g_sigStop, g_sigTarget;
long     g_sigBar;

int      g_totalSignals;
int      g_totalTrades;

//+------------------------------------------------------------------+
//| NW motoru durumu (Pine birebir)                                    |
//+------------------------------------------------------------------+
double   g_nwW[];          // Gauss çekirdek ağırlıkları
double   g_nwWDen;
double   g_slopeArr[];     // nw_slope[bi]
double   g_oscArr[];       // osc_ (normalize eğim, WMA öncesi) [bi]
double   g_sigArr[];       // signal (EMA) [bi]
double   g_atrArr[];       // ATR (Wilder) [bi]
double   g_nwEmaVal;  bool g_nwEmaInit;
double   g_nwEmaSeed[];    int g_nwEmaFill;
double   g_nwAtrVal;  bool g_nwAtrInit;
double   g_nwAtrSeed[];    int g_nwAtrFill;

// Pine "var" durumları
double   g_aboveTipPrice, g_belowTipPrice;
long     g_aboveTipBar, g_belowTipBar;
bool     g_aboveTipValid, g_belowTipValid;
bool     g_abovePrev, g_belowPrev;
int      g_nwLineType;     // 0 / 1 (üst) / -1 (alt)
double   g_nwLinePrice;
long     g_nwLineBar;
string   g_nwLineName;
long     g_nwSeq;

// son bar hesapları (panel/log)
double   g_nwVal, g_nwOsc, g_nwSig, g_nwVol;
bool     g_nwReady;

// olay listesi (bir bar için)
int      g_evtCount;
int      g_evtKind[MAX_EVENTS];   // 0 = NW, 1 = klasik bull, 2 = klasik bear
int      g_evtDir[MAX_EVENTS];    // enum yönü (+1/-1)
string   g_evtName[MAX_EVENTS];
double   g_evtEntry[MAX_EVENTS], g_evtStop[MAX_EVENTS], g_evtTarget[MAX_EVENTS];

//+------------------------------------------------------------------+
//| Renk / grafik yardımcıları                                         |
//+------------------------------------------------------------------+
color BlendColors(color a, color b, double t)
  {
   t = MathMax(0.0, MathMin(1.0, t));
   uint ua = (uint)a, ub = (uint)b;
   int r  = (int)MathRound((ua & 0xFF) * (1.0 - t) + (ub & 0xFF) * t);
   int g  = (int)MathRound(((ua >> 8) & 0xFF) * (1.0 - t) + ((ub >> 8) & 0xFF) * t);
   int bl = (int)MathRound(((ua >> 16) & 0xFF) * (1.0 - t) + ((ub >> 16) & 0xFF) * t);
   return (color)(r | (g << 8) | (bl << 16));
  }

color WithTransparency(color c, int transp)
  {
   color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   return BlendColors(c, bg, transp / 100.0);
  }

datetime TimeOfBar(long barIdx)
  {
   long shift = g_barIndex - barIdx;
   if(shift < 0)
      return iTime(_Symbol, _Period, 0) + (datetime)(-shift * PeriodSeconds());
   return iTime(_Symbol, _Period, (int)shift);
  }

//+------------------------------------------------------------------+
//| Lot yardımcıları                                                   |
//+------------------------------------------------------------------+
double NormalizeLots(double lots)
  {
   double step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   double mn   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double mx   = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   if(step <= 0.0) step = 0.01;
   lots = MathFloor(lots / step + 1e-9) * step;
   if(lots < mn) lots = mn;
   if(lots > mx) lots = mx;
   return NormalizeDouble(lots, 2);
  }

double CalcLots(double riskDistance)
  {
   if(InpLotMode == SP_LOT_FIXED)
      return NormalizeLots(InpFixedLot);
   double balance   = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * InpRiskPercent / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickValue <= 0.0 || g_tickSize <= 0.0 || riskDistance <= 0.0)
      return NormalizeLots(InpFixedLot);
   double lots = riskMoney / ((riskDistance / g_tickSize) * tickValue);
   return NormalizeLots(lots);
  }

double NormPrice(double price)
  {
   if(g_tickSize <= 0.0)
      return NormalizeDouble(price, g_digits);
   return NormalizeDouble(MathRound(price / g_tickSize) * g_tickSize, g_digits);
  }

//+------------------------------------------------------------------+
//| Pivot tespiti (Pine ta.pivothigh / ta.pivotlow; strict)            |
//+------------------------------------------------------------------+
double PivotHighValue(int shift, long barIdx)
  {
   int p = InpPivotLength;
   if(barIdx < 2 * p)
      return NA_DOUBLE;
   int candShift = shift + p;
   double cand = iHigh(_Symbol, _Period, candShift);
   for(int k = shift; k <= shift + 2 * p; k++)
     {
      if(k == candShift)
         continue;
      if(iHigh(_Symbol, _Period, k) >= cand)
         return NA_DOUBLE;
     }
   return cand;
  }

double PivotLowValue(int shift, long barIdx)
  {
   int p = InpPivotLength;
   if(barIdx < 2 * p)
      return NA_DOUBLE;
   int candShift = shift + p;
   double cand = iLow(_Symbol, _Period, candShift);
   for(int k = shift; k <= shift + 2 * p; k++)
     {
      if(k == candShift)
         continue;
      if(iLow(_Symbol, _Period, k) <= cand)
         return NA_DOUBLE;
     }
   return cand;
  }

double AtrAt(int shift, long barIdx)
  {
   if(barIdx < ATR_LENGTH)
      return NA_DOUBLE;
   double buf[1];
   if(g_atrHandle == INVALID_HANDLE)
      return NA_DOUBLE;
   if(CopyBuffer(g_atrHandle, 0, shift, 1, buf) != 1)
      return NA_DOUBLE;
   return buf[0];
  }

//+------------------------------------------------------------------+
//| NW motoru - çekirdek hesaplar (Pine nw() birebir)                  |
//+------------------------------------------------------------------+
void NwInit()
  {
   ArrayResize(g_nwW, InpNWLookback);
   double h2 = 2.0 * InpNWBandwidth * InpNWBandwidth;
   g_nwWDen = 0.0;
   for(int i = 0; i < InpNWLookback; i++)
     {
      double w = MathExp(-(double)(i * i) / h2);
      g_nwW[i] = w;
      g_nwWDen += w;
     }
   ArrayResize(g_slopeArr, 0);
   ArrayResize(g_oscArr, 0);
   ArrayResize(g_sigArr, 0);
   ArrayResize(g_atrArr, 0);
   ArrayResize(g_nwEmaSeed, 0);
   ArrayResize(g_nwAtrSeed, 0);
   g_nwEmaFill = 0;
   g_nwAtrFill = 0;
   g_nwEmaInit = false;
   g_nwAtrInit = false;
   g_nwVal = g_nwOsc = g_nwSig = g_nwVol = NA_DOUBLE;
   g_nwReady = false;
   g_aboveTipPrice = g_belowTipPrice = NA_DOUBLE;
   g_aboveTipBar = g_belowTipBar = NO_BAR;
   g_aboveTipValid = g_belowTipValid = false;
   g_abovePrev = g_belowPrev = false;
   g_nwLineType = 0;
   g_nwLinePrice = 0.0;
   g_nwLineBar = NO_BAR;
   g_nwLineName = "";
   g_nwSeq = 0;
  }

// nw(): lookback barın Gauss ağırlıklı ortalaması
double NwValueAt(int shift)
  {
   if(g_nwWDen == 0.0)
      return NA_DOUBLE;
   if(shift + InpNWLookback > iBars(_Symbol, _Period))
      return NA_DOUBLE;
   double num = 0.0;
   for(int i = 0; i < InpNWLookback; i++)
      num += iClose(_Symbol, _Period, shift + i) * g_nwW[i];
   return num / g_nwWDen;
  }

// nw_slope = nw_val - nw_val[1]
double RawSlopeAt(int shift)
  {
   double v0 = NwValueAt(shift);
   double v1 = NwValueAt(shift + 1);
   if(v0 == NA_DOUBLE || v1 == NA_DOUBLE)
      return NA_DOUBLE;
   return v0 - v1;
  }

// ta.stdev(nw_slope, norm_len) - Pine biased (payda = n)
double StdOfSlopes(long bi, int shift)
  {
   int n = InpNWNormLen;
   double sum = 0.0;
   for(int k = 0; k < n; k++)
     {
      long bj = bi - k;
      double s = NA_DOUBLE;
      if(bj >= 0 && bj < ArraySize(g_slopeArr))
         s = g_slopeArr[bj];
      if(s == NA_DOUBLE)
         s = RawSlopeAt(shift + k);
      if(s == NA_DOUBLE)
         return NA_DOUBLE;
      sum += s;
     }
   double mean = sum / n;
   double var = 0.0;
   for(int k = 0; k < n; k++)
     {
      long bj = bi - k;
      double s = NA_DOUBLE;
      if(bj >= 0 && bj < ArraySize(g_slopeArr))
         s = g_slopeArr[bj];
      if(s == NA_DOUBLE)
         s = RawSlopeAt(shift + k);
      double dv = s - mean;
      var += dv * dv;
     }
   return MathSqrt(var / n);
  }

// osc_ = nw_slope / slope_std
double RawOscAt(long bi, int shift)
  {
   double slope = RawSlopeAt(shift);
   double std = StdOfSlopes(bi, shift);
   if(slope == NA_DOUBLE || std == NA_DOUBLE || std <= 0.0)
      return NA_DOUBLE;
   return slope / std;
  }

//+------------------------------------------------------------------+
//| NW motoru - bar adımı (Pine bar mantığı birebir)                   |
//| Girdi: bi = Pine bar_index, shift = barın uzaklığı                 |
//| Çıktılar g_nw* global ve olay listesinde                          |
//+------------------------------------------------------------------+
void NwStep(long bi, int shift, double o, double c, double h, double l, double c1)
  {
   // dizileri büyüt
   long need = bi + 1;
   if(ArraySize(g_slopeArr) < need)
     {
      ArrayResize(g_slopeArr, (int)need);
      ArrayResize(g_oscArr, (int)need);
      ArrayResize(g_sigArr, (int)need);
      ArrayResize(g_atrArr, (int)need);
     }
   g_slopeArr[bi] = NA_DOUBLE;
   g_oscArr[bi]   = NA_DOUBLE;
   g_sigArr[bi]   = NA_DOUBLE;
   g_atrArr[bi]   = NA_DOUBLE;

   //--- nw_val / nw_slope / osc_ / osc (WMA) / signal (EMA)
   double nwVal = NwValueAt(shift);
   double slope = NA_DOUBLE;
   if(nwVal != NA_DOUBLE)
     {
      double nwPrev = NwValueAt(shift + 1);
      if(nwPrev != NA_DOUBLE)
         slope = nwVal - nwPrev;
     }
   g_slopeArr[bi] = slope;

   double osc = NA_DOUBLE;
   if(slope != NA_DOUBLE)
     {
      double std = StdOfSlopes(bi, shift);
      if(std != NA_DOUBLE && std > 0.0)
        {
         double osc_ = slope / std;
         g_oscArr[bi] = osc_;
         // ta.wma(osc_, osc_smooth_len): ağırlıklar en yeniye en yüksek
         int m = InpNWOscSmooth;
         double wsum = 0.0, wtot = 0.0;
         bool ok = true;
         for(int k = 0; k < m; k++)
           {
            long bj = bi - k;
            double v = NA_DOUBLE;
            if(bj >= 0 && bj < ArraySize(g_oscArr))
               v = g_oscArr[bj];
            if(v == NA_DOUBLE)
               v = RawOscAt(bj, shift + k);
            if(v == NA_DOUBLE)
              {
               ok = false;
               break;
              }
            double w = (double)(m - k);
            wsum += v * w;
            wtot += w;
           }
         if(ok && wtot > 0.0)
            osc = wsum / wtot;
        }
     }

   //--- signal = ta.ema(osc, signal_len); ilk len değerin SMA'sı ile tohumlanır
   double sig = NA_DOUBLE;
   if(osc != NA_DOUBLE)
     {
      if(!g_nwEmaInit)
        {
         int n1 = g_nwEmaFill;
         ArrayResize(g_nwEmaSeed, n1 + 1);
         g_nwEmaSeed[n1] = osc;
         g_nwEmaFill = n1 + 1;
         if(g_nwEmaFill == InpNWSigLen)
           {
            double ssum = 0.0;
            for(int i = 0; i < InpNWSigLen; i++)
               ssum += g_nwEmaSeed[i];
            g_nwEmaVal = ssum / InpNWSigLen;
            g_nwEmaInit = true;
            sig = g_nwEmaVal;
           }
        }
      else
        {
         double alpha = 2.0 / (InpNWSigLen + 1);
         g_nwEmaVal = alpha * osc + (1.0 - alpha) * g_nwEmaVal;
         sig = g_nwEmaVal;
        }
     }
   g_sigArr[bi] = sig;
   g_nwVal = nwVal;
   g_nwOsc = osc;
   g_nwSig = sig;

   //--- ATR (Pine ta.atr = ta.rma(tr, len) - Wilder) + volatility = SMA(atr, vol_smooth)
   double tr;
   if(c1 == NA_DOUBLE)
      tr = h - l;
   else
      tr = MathMax(h - l, MathMax(MathAbs(h - c1), MathAbs(l - c1)));
   double atrVal = NA_DOUBLE;
   if(!g_nwAtrInit)
     {
      int n2 = g_nwAtrFill;
      ArrayResize(g_nwAtrSeed, n2 + 1);
      g_nwAtrSeed[n2] = tr;
      g_nwAtrFill = n2 + 1;
      if(g_nwAtrFill == InpNWATRLen)
        {
         double asum = 0.0;
         for(int i = 0; i < InpNWATRLen; i++)
            asum += g_nwAtrSeed[i];
         g_nwAtrVal = asum / InpNWATRLen;
         g_nwAtrInit = true;
         atrVal = g_nwAtrVal;
        }
     }
   else
     {
      g_nwAtrVal = (g_nwAtrVal * (InpNWATRLen - 1) + tr) / InpNWATRLen;
      atrVal = g_nwAtrVal;
     }
   g_atrArr[bi] = atrVal;

   double vol = NA_DOUBLE;
   if(atrVal != NA_DOUBLE && bi >= InpNWVolSmooth - 1)
     {
      double vsum = 0.0;
      bool vok = true;
      for(int k = 0; k < InpNWVolSmooth; k++)
        {
         double v = g_atrArr[bi - k];
         if(v == NA_DOUBLE)
           {
            vok = false;
            break;
           }
         vsum += v;
        }
      if(vok)
         vol = vsum / InpNWVolSmooth;
     }
   g_nwVol = vol;

   //--- hazırlık kontrolü (Pine na dönemi)
   bool chartReady = (iBars(_Symbol, _Period) - 1 - shift) >=
                     (InpNWLookback + InpNWNormLen + InpNWOscSmooth + InpNWSigLen);
   g_nwReady = chartReady && (osc != NA_DOUBLE) && (sig != NA_DOUBLE) && (vol != NA_DOUBLE);

   if(!g_nwReady)
      return;

   double oscPrev = (bi > 0) ? g_oscArr[bi - 1] : NA_DOUBLE;
   double sigPrev = (bi > 0) ? g_sigArr[bi - 1] : NA_DOUBLE;
   if(oscPrev == NA_DOUBLE || sigPrev == NA_DOUBLE)
      return;

   //--- Pine koşulları
   bool con1 = (oscPrev > sigPrev) && (osc < sig);        // crossunder(osc, signal)
   bool con2 = (oscPrev < sigPrev) && (osc > sig);        // crossover(osc, signal)
   bool above_signal = (osc > sig);
   bool below_signal = (osc < sig);

   //--- swing tip takibi (use_tip çapası)
   if(above_signal)
     {
      if(!g_abovePrev)
        {
         g_aboveTipPrice = h;
         g_aboveTipBar = bi;
         g_aboveTipValid = true;
        }
      else if(!g_aboveTipValid || h > g_aboveTipPrice)
        {
         g_aboveTipPrice = h;
         g_aboveTipBar = bi;
         g_aboveTipValid = true;
        }
     }
   if(below_signal)
     {
      if(!g_belowPrev)
        {
         g_belowTipPrice = l;
         g_belowTipBar = bi;
         g_belowTipValid = true;
        }
      else if(!g_belowTipValid || l < g_belowTipPrice)
        {
         g_belowTipPrice = l;
         g_belowTipBar = bi;
         g_belowTipValid = true;
        }
     }
   g_abovePrev = above_signal;
   g_belowPrev = below_signal;

   //--- sinyaller
   bool weakening_bull = (osc > 0 && con1);
   bool weakening_bear = (osc < 0 && con2);
   bool bull_zero = (oscPrev < 0 && osc > 0);
   bool bear_zero = (oscPrev > 0 && osc < 0);
   bool bull_cross = con2;
   bool bear_cross = con1;

   bool draw_upper = weakening_bull;    // Pine: draw_upper_line = osc>0 and con1
   bool draw_lower = weakening_bear;    // Pine: draw_lower_line = osc<0 and con2
   bool draw_new = draw_upper || draw_lower;

   bool upper_swept = (g_nwLineType == 1  && c > g_nwLinePrice);
   bool lower_swept = (g_nwLineType == -1 && c < g_nwLinePrice);

   bool bull_rebound = (osc > 0 && c1 != NA_DOUBLE && c1 < nwVal && c > nwVal);
   bool bear_rebound = (osc < 0 && c1 != NA_DOUBLE && c1 > nwVal && c < nwVal);

   //--- çizim penceresi
   bool drawWindow = (bi >= g_barIndex - InpDrawHistoryBars);

   //--- durum makinesi (Pine SIRASI: önce swept, sonra emekli et, sonra yeni çizgi)
   if(g_nwLineType != 0)
     {
      // Pine: line.set_x2 (aktif çizgiyi sağa uzat)
      if(InpNWDrawLevels && drawWindow && g_nwLineName != "")
         ObjectMove(0, g_nwLineName, 1, TimeOfBar(bi), g_nwLinePrice);
      bool line_crossed = (g_nwLineType == 1) ? (c > g_nwLinePrice) : (c < g_nwLinePrice);
      if(line_crossed || draw_new)
         g_nwLineType = 0;
     }

   if(draw_upper)
     {
      double levelPrice = (InpNWUseTip && g_aboveTipValid) ? g_aboveTipPrice : h;
      long levelBar = (InpNWUseTip && g_aboveTipBar != NO_BAR) ? g_aboveTipBar : bi;
      NwCreateLine(+1, levelPrice, levelBar, bi, drawWindow);
     }
   if(draw_lower)
     {
      double levelPrice = (InpNWUseTip && g_belowTipValid) ? g_belowTipPrice : l;
      long levelBar = (InpNWUseTip && g_belowTipBar != NO_BAR) ? g_belowTipBar : bi;
      NwCreateLine(-1, levelPrice, levelBar, bi, drawWindow);
     }

   //--- işaretler (Pine plotchar)
   if(InpNWDrawMarkers && drawWindow)
     {
      if(weakening_bull)
         NwMarker("DOT", bi, h, 159, InpNWBullColor, ANCHOR_LOWER);
      if(weakening_bear)
         NwMarker("DOT", bi, l, 159, InpNWBearColor, ANCHOR_UPPER);
      if(bull_rebound)
         NwMarker("RBD", bi, nwVal - vol * 1.5, 233, InpNWBullColor, ANCHOR_CENTER);
      if(bear_rebound)
         NwMarker("RBD", bi, nwVal + vol * 1.5, 234, InpNWBearColor, ANCHOR_CENTER);
     }

   //--- olay kaydı (sabit öncelik sırası)
   if(weakening_bull) AddEvent(0, InpSigWeakenBull, "Weakening Bullish Momentum", bi, c);
   if(weakening_bear) AddEvent(0, InpSigWeakenBear, "Weakening Bearish Momentum", bi, c);
   if(bull_cross)     AddEvent(0, InpSigBullCross,  "Bullish Signal Cross", bi, c);
   if(bear_cross)     AddEvent(0, InpSigBearCross,  "Bearish Signal Cross", bi, c);
   if(bull_zero)      AddEvent(0, InpSigBullZero,   "Bullish Zero Cross", bi, c);
   if(bear_zero)      AddEvent(0, InpSigBearZero,   "Bearish Zero Cross", bi, c);
   if(draw_upper)     AddEvent(0, InpSigNewUpper,   "New Upper Liquidity Level", bi, c);
   if(draw_lower)     AddEvent(0, InpSigNewLower,   "New Lower Liquidity Level", bi, c);
   if(upper_swept)    AddEvent(0, InpSigUpperSwept, "Upper Liquidity Level Swept", bi, c);
   if(lower_swept)    AddEvent(0, InpSigLowerSwept, "Lower Liquidity Level Swept", bi, c);
   if(bull_rebound)   AddEvent(0, InpSigBullRebound,"Bullish Rebound", bi, c);
   if(bear_rebound)   AddEvent(0, InpSigBearRebound,"Bearish Rebound", bi, c);
  }

//+------------------------------------------------------------------+
//| NW çizim yardımcıları                                              |
//+------------------------------------------------------------------+
void NwCreateLine(int type, double price, long levelBar, long bi, bool drawWindow)
  {
   if(InpNWDrawLevels && drawWindow)
     {
      string name = "SP_NWL_" + IntegerToString(++g_nwSeq);
      datetime t0 = TimeOfBar(levelBar);
      datetime t1 = TimeOfBar(bi);
      if(ObjectCreate(0, name, OBJ_TREND, 0, t0, price, t1, price))
        {
         ObjectSetInteger(0, name, OBJPROP_RAY, false);
         ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_SOLID);
         ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
         ObjectSetInteger(0, name, OBJPROP_COLOR, (type == 1) ? InpNWBearColor : InpNWBullColor);
         ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
         g_nwLineName = name;
         PushSetupName(name);
        }
     }
   g_nwLineType = type;
   g_nwLinePrice = price;
   g_nwLineBar = levelBar;
  }

void NwMarker(string tag, long bi, double price, int code, color col, ENUM_ANCHOR_POINT anchor)
  {
   string name = "SP_NWM_" + tag + "_" + IntegerToString(++g_nwSeq);
   if(!ObjectCreate(0, name, OBJ_ARROW, 0, TimeOfBar(bi), price))
      return;
   ObjectSetInteger(0, name, OBJPROP_ARROWCODE, code);
   ObjectSetInteger(0, name, OBJPROP_COLOR, col);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   PushSetupName(name);
  }

//+------------------------------------------------------------------+
//| Olay listesi                                                       |
//+------------------------------------------------------------------+
void AddEvent(int kind, ENUM_SIG_DIR sel, string name, long bi, double price)
  {
   if(sel == SIG_OFF)
      return;
   if(g_evtCount >= MAX_EVENTS)
      return;
   int d = (sel == SIG_LONG) ? 1 : -1;
   g_evtKind[g_evtCount] = kind;
   g_evtDir[g_evtCount] = d;
   g_evtName[g_evtCount] = name;
   g_evtEntry[g_evtCount] = price;
   g_evtStop[g_evtCount] = 0.0;
   g_evtTarget[g_evtCount] = 0.0;
   g_evtCount++;
   g_totalSignals++;
  }

//+------------------------------------------------------------------+
//| Çubuk işleme çekirdeği                                             |
//| Çıktı: g_sig* (giriş hazırlandıysa return 1)                       |
//+------------------------------------------------------------------+
int ProcessConfirmedBar(int shift, long barIdx)
  {
   g_sigDir = 0;
   g_sigName = "";
   g_evtCount = 0;

   double o = iOpen(_Symbol, _Period, shift);
   double c = iClose(_Symbol, _Period, shift);
   double h = iHigh(_Symbol, _Period, shift);
   double l = iLow(_Symbol, _Period, shift);
   double c1 = (barIdx >= 1) ? iClose(_Symbol, _Period, shift + 1) : NA_DOUBLE;

   //---- 1) Yapı takibi (klasik - SL/TP ve klasik sinyaller için)
   double prevLPH = g_lastPivotHigh;
   double prevLPL = g_lastPivotLow;
   double ph = PivotHighValue(shift, barIdx);
   double pl = PivotLowValue(shift, barIdx);
   if(ph != NA_DOUBLE)
      g_lastPivotHigh = ph;
   if(pl != NA_DOUBLE)
      g_lastPivotLow = pl;

   //---- 2) Konsolidasyon filtresi (klasik)
   bool zoneValid = (barIdx >= InpConsLength);
   double pastHigh = NA_DOUBLE, pastLow = NA_DOUBLE;
   if(zoneValid)
     {
      int hs = iHighest(_Symbol, _Period, MODE_HIGH, InpConsLength, shift + 1);
      int ls = iLowest(_Symbol, _Period, MODE_LOW, InpConsLength, shift + 1);
      pastHigh = iHigh(_Symbol, _Period, hs);
      pastLow  = iLow(_Symbol, _Period, ls);
     }
   double zoneRange = (zoneValid) ? pastHigh - pastLow : NA_DOUBLE;
   double currentAtr = AtrAt(shift, barIdx);
   bool isConsolidating = true;
   if(InpUseConsolidation)
      isConsolidating = (zoneValid && currentAtr != NA_DOUBLE &&
                         zoneRange <= currentAtr * InpAtrMult);

   //---- 3) Cooldown (tüm girişler için ortak)
   bool canEnter = InpUseCooldown ? (g_lastTradeBar == NO_BAR ||
                                     barIdx - g_lastTradeBar >= InpCooldownBars) : true;

   //---- 4) NW motoru (Pine birebir) -> olay listesine ekler
   NwStep(barIdx, shift, o, c, h, l, c1);

   //---- 5) Klasik kırılım olayları (eski ScalperPro mantığı - korunur)
   if(InpSigClassicBull != SIG_OFF || InpSigClassicBear != SIG_OFF)
     {
      bool crossUp = (barIdx >= 1 && prevLPH != NA_DOUBLE && c1 < prevLPH) &&
                     (g_lastPivotHigh != NA_DOUBLE && c > g_lastPivotHigh);
      bool crossDn = (barIdx >= 1 && prevLPL != NA_DOUBLE && c1 > prevLPL) &&
                     (g_lastPivotLow != NA_DOUBLE && c < g_lastPivotLow);
      bool bullCandle = (c > o);
      bool bearCandle = (c < o);

      if(InpSigClassicBull != SIG_OFF)
        {
         bool bullishBreakout = bullCandle && crossUp &&
                                (g_lastPivotLow != NA_DOUBLE && l > g_lastPivotLow) &&
                                isConsolidating;
         if(bullishBreakout && g_lastPivotLow != NA_DOUBLE)
           {
            double risk = c - g_lastPivotLow;
            if(risk > 0)
              {
               int idx = g_evtCount;
               AddEvent(1, InpSigClassicBull, "Klasik LONG Breakout", barIdx, c);
               if(g_evtCount > idx)
                 {
                  g_evtStop[idx] = g_lastPivotLow;
                  g_evtTarget[idx] = NormPrice(c + risk * InpTargetMult);
                 }
              }
           }
        }
      if(InpSigClassicBear != SIG_OFF)
        {
         bool bearishBreakout = bearCandle && crossDn &&
                                (g_lastPivotHigh != NA_DOUBLE && h < g_lastPivotHigh) &&
                                isConsolidating;
         if(bearishBreakout && g_lastPivotHigh != NA_DOUBLE)
           {
            double risk = g_lastPivotHigh - c;
            if(risk > 0)
              {
               int idx = g_evtCount;
               AddEvent(2, InpSigClassicBear, "Klasik SHORT Breakout", barIdx, c);
               if(g_evtCount > idx)
                 {
                  g_evtStop[idx] = g_lastPivotHigh;
                  g_evtTarget[idx] = NormPrice(c - risk * InpTargetMult);
                 }
              }
           }
        }
     }

   //---- 6) Olaylar: zıt sinyal sayacı + bildirim + GİRİŞ (ilk uygun olay)
   for(int e = 0; e < g_evtCount; e++)
     {
      // zıt sinyal sayacı (açık NW işlemlerini HER ZAMAN, klasikleri
      // InpUseOppExit açıkken sayar)
      OnSignalEvent(g_evtDir[e]);

      if(barIdx >= g_barIndex - 1 && (InpAlertsOn || InpPushOn))
         Notify("ScalperProGold: " + g_evtName[e],
                StringFormat("%s %s @ %s", _Symbol,
                             (g_evtDir[e] > 0) ? "LONG" : "SHORT",
                             DoubleToString(g_evtEntry[e], g_digits)));
     }

   if(g_evtCount > 0 && canEnter)
     {
      int e = 0;   // sabit öncelik: ilk olay
      g_lastTradeBar = barIdx;
      g_sigRawDir = g_evtDir[e];
      g_sigName = g_evtName[e];
      g_sigBar = barIdx;
      g_sigEntry = g_evtEntry[e];

      if(g_evtKind[e] == 0)
        {
         // NW işlemi: SL/TP KULLANILMAZ (kullanıcı seçimi)
         g_sigNoSLTP = true;
         g_sigDir = InpReverseMode ? -g_sigRawDir : g_sigRawDir;
         g_sigStop = 0.0;
         g_sigTarget = 0.0;
         if(InpDrawSetups && barIdx >= g_barIndex - InpDrawHistoryBars)
            DrawNwEntry(barIdx, g_sigDir, g_sigEntry, g_sigName);
        }
      else
        {
         // klasik işlem: SL = pivot, TP = risk × mult (özellikler korunur)
         g_sigNoSLTP = false;
         int natDir = (g_evtKind[e] == 1) ? 1 : -1;
         g_sigDir = natDir;
         g_sigStop = g_evtStop[e];
         g_sigTarget = g_evtTarget[e];
         // enum ters seçimse seviyeleri takas et (ters mod mantığı)
         if(g_sigRawDir != natDir)
           {
            double tmp = g_sigStop;
            g_sigStop = g_sigTarget;
            g_sigTarget = tmp;
            g_sigDir = -g_sigDir;
           }
         // Ters İşlem Modu
         if(InpReverseMode)
           {
            double tmp = g_sigStop;
            g_sigStop = g_sigTarget;
            g_sigTarget = tmp;
            g_sigDir = -g_sigDir;
           }
         if(InpDrawSetups && barIdx >= g_barIndex - InpDrawHistoryBars)
            DrawSetup(barIdx, g_sigDir, g_sigEntry, g_sigStop, g_sigTarget);
        }
      return 1;
     }

   return 0;
  }

//+------------------------------------------------------------------+
//| NW giriş işareti (SL/TP yok - yalnız giriş çizgisi + etiket)       |
//+------------------------------------------------------------------+
void DrawNwEntry(long barIdx, int dir, double entryPrice, string sigName)
  {
   datetime t0 = TimeOfBar(barIdx);
   datetime t1 = TimeOfBar(barIdx + InpBoxLength);
   string tag = StringFormat("SP_NWE_%I64d", barIdx * 8 + (dir > 0 ? 1 : 2));
   color col = (dir > 0) ? InpNWBullColor : InpNWBearColor;
   MakeLine(tag + "_lnEntry", t0, t1, entryPrice, InpEntryColor, STYLE_DOT);
   MakeLabel(tag + "_lbEntry", t1, entryPrice, sigName, col, ANCHOR_LEFT);
  }

//+------------------------------------------------------------------+
//| Kurulum çizimleri (klasik - Pine box/label/line)                    |
//+------------------------------------------------------------------+
void PushSetupName(const string name)
  {
   int n = ArraySize(g_setupNames);
   ArrayResize(g_setupNames, n + 1);
   g_setupNames[n] = name;
   int maxObjs = MAX_SETUPS_ON_CHART * 8;
   while(ArraySize(g_setupNames) > maxObjs)
     {
      ObjectDelete(0, g_setupNames[0]);
      ArrayRemove(g_setupNames, 0, 1);
     }
  }

void MakeRect(const string name, datetime t0, datetime t1, double top, double bottom, color base, int transp)
  {
   if(!ObjectCreate(0, name, OBJ_RECTANGLE, 0, t0, top, t1, bottom))
      return;
   color c = WithTransparency(base, transp);
   ObjectSetInteger(0, name, OBJPROP_COLOR, c);
   ObjectSetInteger(0, name, OBJPROP_BGCOLOR, c);
   ObjectSetInteger(0, name, OBJPROP_FILL, true);
   ObjectSetInteger(0, name, OBJPROP_BACK, false);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   PushSetupName(name);
  }

void MakeLine(const string name, datetime t0, datetime t1, double price, color base, ENUM_LINE_STYLE style)
  {
   if(!ObjectCreate(0, name, OBJ_TREND, 0, t0, price, t1, price))
      return;
   ObjectSetInteger(0, name, OBJPROP_RAY, false);
   ObjectSetInteger(0, name, OBJPROP_STYLE, style);
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 1);
   ObjectSetInteger(0, name, OBJPROP_COLOR, base);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   PushSetupName(name);
  }

void MakeLabel(const string name, datetime t, double price, string text, color base, ENUM_ANCHOR_POINT anchor)
  {
   if(!ObjectCreate(0, name, OBJ_TEXT, 0, t, price))
      return;
   ObjectSetString(0, name, OBJPROP_TEXT, text);
   ObjectSetString(0, name, OBJPROP_FONT, "Arial");
   ObjectSetInteger(0, name, OBJPROP_FONTSIZE, 9);
   ObjectSetInteger(0, name, OBJPROP_COLOR, WithTransparency(base, 20));
   ObjectSetInteger(0, name, OBJPROP_ANCHOR, anchor);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
   PushSetupName(name);
  }

void DrawSetup(long barIdx, int dir, double entryPrice, double stopPrice, double targetPrice)
  {
   datetime t0 = TimeOfBar(barIdx);
   datetime t1 = TimeOfBar(barIdx + InpBoxLength);
   string tag = StringFormat("SP_%I64d", barIdx * 8 + (dir > 0 ? 1 : 2));

   if(dir > 0)
     {
      MakeRect(tag + "_stopbox", t0, t1, entryPrice, stopPrice, InpStopColor, 80);
      MakeRect(tag + "_tgtbox", t0, t1, targetPrice, entryPrice, InpTargetColor, 80);
     }
   else
     {
      MakeRect(tag + "_stopbox", t0, t1, stopPrice, entryPrice, InpStopColor, 80);
      MakeRect(tag + "_tgtbox", t0, t1, entryPrice, targetPrice, InpTargetColor, 80);
     }

   datetime tl = t1;
   MakeLabel(tag + "_lbEntry", tl, entryPrice, "ENTRY", InpEntryColor, ANCHOR_LEFT);
   if(dir > 0)
     {
      MakeLabel(tag + "_lbStop", tl, stopPrice, "STOP LOSS", InpStopColor, ANCHOR_UPPER);
      MakeLabel(tag + "_lbTgt", tl, targetPrice, "TARGET", InpTargetColor, ANCHOR_LOWER);
     }
   else
     {
      MakeLabel(tag + "_lbStop", tl, stopPrice, "STOP LOSS", InpStopColor, ANCHOR_LOWER);
      MakeLabel(tag + "_lbTgt", tl, targetPrice, "TARGET", InpTargetColor, ANCHOR_UPPER);
     }

   MakeLine(tag + "_lnEntry", t0, t1, entryPrice, InpEntryColor, STYLE_DOT);
   MakeLine(tag + "_lnStop", t0, t1, stopPrice, InpStopColor, STYLE_SOLID);
   MakeLine(tag + "_lnTgt", t0, t1, targetPrice, InpTargetColor, STYLE_SOLID);
  }

//+------------------------------------------------------------------+
//| Bildirim                                                           |
//+------------------------------------------------------------------+
void Notify(const string title, const string text)
  {
   if(InpAlertsOn)
      Alert(title, ": ", text);
   if(InpPushOn)
      SendNotification(title + ": " + text);
  }

//+------------------------------------------------------------------+
//| İşlem yönetimi                                                     |
//+------------------------------------------------------------------+
bool HedgeAllowsNewTrade()
  {
   if(InpAllowMultiple && g_isHedge)
      return true;
   for(int i = 0; i < ArraySize(g_trades); i++)
      if(g_trades[i].ticket != 0)
         return false;
   return true;
  }

void OpenTrade(int dir, int rawSigDir, bool noSLTP, string sigName,
               double entryRef, double stopPrice, double targetPrice, long signalBar)
  {
   if(InpTradeMode != SP_TRADE_ON)
      return;
   if(!HedgeAllowsNewTrade())
     {
      Print("SP: mevcut pozisyon nedeniyle yeni emir açılmadı (netting veya çoklu kapalı).");
      return;
     }

   double entry = NormPrice(entryRef);
   double sl = NormPrice(stopPrice);
   double tp = NormPrice(targetPrice);

   double risk = 0.0;
   double sendSL = 0.0, sendTP = 0.0;

   if(noSLTP)
     {
      // NW işlemi: SL/TP YOK - kapanış yalnız zıt sinyal sayacıyla
      // lot risk mesafesi = NW volatilitesi (ATR-smoothed); yoksa sabit lot
      risk = (g_nwVol != NA_DOUBLE && g_nwVol > 0.0) ? g_nwVol : 0.0;
     }
   else
     {
      risk = MathAbs(entry - sl);
      if(risk <= g_tickSize)
        {
         Print("SP: risk mesafesi 1 tick'ten küçük, emir açılmadı.");
         return;
        }
      sendSL = InpUseOppExit ? 0.0 : sl;
      sendTP = InpUseOppExit ? 0.0 : tp;
      if(!InpUseOppExit)
        {
         double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
         long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
         double minDist = stopsLevel * point;
         if(minDist > 0.0 && (MathAbs(entry - sl) < minDist || MathAbs(tp - entry) < minDist))
           {
            Print("SP: broker min. stop mesafesi (", DoubleToString(minDist, g_digits),
                  ") sağlanamıyor - emir atlandı. SL=", DoubleToString(sl, g_digits),
                  " TP=", DoubleToString(tp, g_digits));
            return;
           }
        }
     }

   double lots = CalcLots(risk);
   CTrade trade;
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviation);
   trade.SetTypeFillingBySymbol(_Symbol);

   bool ok = false;
   if(dir > 0)
      ok = trade.Buy(lots, _Symbol, 0.0, sendSL, sendTP, "SP " + sigName);
   else
      ok = trade.Sell(lots, _Symbol, 0.0, sendSL, sendTP, "SP " + sigName);

   if(ok && trade.ResultRetcode() == TRADE_RETCODE_DONE)
     {
      ulong deal = trade.ResultDeal();
      ulong posId = 0;
      if(deal > 0)
         posId = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      if(posId == 0)
         posId = trade.ResultOrder();

      // dolum sonrası SL/TP doğrulaması (yalnız klasik + SL/TP'li modda)
      if(!noSLTP && !InpUseOppExit && posId != 0 && PositionSelectByTicket(posId))
        {
         double curSL = PositionGetDouble(POSITION_SL);
         double curTP = PositionGetDouble(POSITION_TP);
         if(MathAbs(curSL - sl) > g_tickSize * 0.5 || MathAbs(curTP - tp) > g_tickSize * 0.5)
           {
            CTrade mod;
            mod.SetDeviationInPoints(InpDeviation);
            if(mod.PositionModify(posId, sl, tp))
               Print("SP: SL/TP pozisyona eklendi -> SL=", DoubleToString(sl, g_digits),
                     " TP=", DoubleToString(tp, g_digits));
            else
               Print("SP: SL/TP değiştirilemedi, retcode=", mod.ResultRetcode(),
                     " comment=", mod.ResultComment());
           }
        }

      int n = ArraySize(g_trades);
      ArrayResize(g_trades, n + 1);
      g_trades[n].ticket = posId;
      g_trades[n].dir = dir;
      g_trades[n].sigDir = rawSigDir;
      g_trades[n].oppCount = 0;
      g_trades[n].noSLTP = noSLTP;
      g_trades[n].signalBar = signalBar;
      g_trades[n].entryPrice = entry;
      g_trades[n].stopPrice = noSLTP ? 0.0 : sl;
      g_trades[n].targetPrice = noSLTP ? 0.0 : tp;
      g_totalTrades++;
      if(noSLTP)
         Print("SP: [", sigName, "] pozisyon açıldı #", posId,
               " [NW: SL/TP yok - ", IntegerToString(InpOppExitCount),
               " zıt sinyalde kapanır] lot=", DoubleToString(lots, 2));
      else if(InpUseOppExit)
         Print("SP: [", sigName, "] pozisyon açıldı #", posId,
               " [ZIT SİNYAL ÇIKIŞI] lot=", DoubleToString(lots, 2));
      else
         Print("SP: [", sigName, "] pozisyon açıldı #", posId,
               " SL=", DoubleToString(sl, g_digits), " TP=", DoubleToString(tp, g_digits),
               " lot=", DoubleToString(lots, 2));
     }
   else
      Print("SP: emir gönderilemedi, retcode=", trade.ResultRetcode(),
            " comment=", trade.ResultComment());
  }

//+------------------------------------------------------------------+
//| Zıt sinyal sayacı                                                  |
//| - NW işlemleri (noSLTP): HER ZAMAN sayılır (tek kapanış yolu)     |
//| - Klasik işlemler: yalnız InpUseOppExit açıkken                   |
//+------------------------------------------------------------------+
void OnSignalEvent(int rawDir)
  {
   if(InpOppExitCount < 1)
      return;
   for(int i = ArraySize(g_trades) - 1; i >= 0; i--)
     {
      if(g_trades[i].sigDir != -rawDir)
         continue;
      if(!(g_trades[i].noSLTP || InpUseOppExit))
         continue;
      g_trades[i].oppCount++;
      if(g_trades[i].oppCount >= InpOppExitCount)
        {
         if(g_trades[i].ticket != 0 && PositionSelectByTicket(g_trades[i].ticket))
           {
            CTrade trade;
            trade.SetDeviationInPoints(InpDeviation);
            if(trade.PositionClose(g_trades[i].ticket, InpDeviation))
               Print("SP: ZIT SİNYAL ÇIKIŞI (", IntegerToString(InpOppExitCount),
                     ". zıt sinyal) - pozisyon kapatıldı #", g_trades[i].ticket);
            else
               Print("SP: zıt sinyal çıkışı - kapatma başarısız, retcode=", trade.ResultRetcode());
           }
         RemoveTradeAt(i);
        }
     }
  }

// Her tick: kapanan pozisyonları temizle
// NW işlemlerinde süre sonu KULLANILMAZ (yalnız zıt sinyal sayacı kapatır)
void ManageTradesTick()
  {
   for(int i = ArraySize(g_trades) - 1; i >= 0; i--)
     {
      if(g_trades[i].ticket == 0 || !PositionSelectByTicket(g_trades[i].ticket))
        {
         RemoveTradeAt(i);
         continue;
        }
      if(!g_trades[i].noSLTP && !InpUseOppExit && InpMaxBarsInTrade > 0 &&
         g_barIndex - g_trades[i].signalBar > InpMaxBarsInTrade)
        {
         CTrade trade;
         trade.SetDeviationInPoints(InpDeviation);
         trade.PositionClose(g_trades[i].ticket, InpDeviation);
         RemoveTradeAt(i);
        }
     }
  }

void RemoveTradeAt(int i)
  {
   int n = ArraySize(g_trades);
   for(int k = i; k < n - 1; k++)
      g_trades[k] = g_trades[k + 1];
   ArrayResize(g_trades, n - 1);
  }

// EA yeniden başlatıldığında açık pozisyonları sahiplen
void AdoptExistingPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;

      int dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      datetime openTime = (datetime)PositionGetInteger(POSITION_TIME);
      int shift = iBarShift(_Symbol, _Period, openTime, false);
      if(shift < 0)
         continue;
      long signalBar = g_barIndex - shift;

      double posSL = PositionGetDouble(POSITION_SL);
      double posTP = PositionGetDouble(POSITION_TP);

      int n = ArraySize(g_trades);
      ArrayResize(g_trades, n + 1);
      g_trades[n].ticket = ticket;
      g_trades[n].dir = dir;
      g_trades[n].sigDir = InpReverseMode ? -dir : dir;
      g_trades[n].oppCount = 0;
      g_trades[n].noSLTP = (posSL == 0.0 && posTP == 0.0);
      g_trades[n].signalBar = signalBar;
      g_trades[n].entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      g_trades[n].stopPrice = posSL;
      g_trades[n].targetPrice = posTP;
      Print("SP: mevcut pozisyon sahiplendi, ticket=", ticket);
     }
  }

//+------------------------------------------------------------------+
//| Geçmiş yürüyüşü                                                    |
//+------------------------------------------------------------------+
void ProcessHistory()
  {
   int barsAvail = iBars(_Symbol, _Period);
   if(barsAvail < 2)
     {
      g_barIndex = 0;
      return;
     }
   int startShift = barsAvail - 1;
   if(InpMaxHistoryBars > 0 && startShift > InpMaxHistoryBars)
      startShift = InpMaxHistoryBars;

   g_barIndex = startShift;

   for(int s = startShift; s >= 1; s--)
     {
      long bi = startShift - s;
      ProcessConfirmedBar(s, bi);
     }
  }

//+------------------------------------------------------------------+
//| OnInit                                                             |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpPivotLength < 1 || InpBoxLength < 1 || InpConsLength < 1)
     {
      Print("SP: uzunluk parametreleri >= 1 olmalı");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpTargetMult <= 0.0)
     {
      Print("SP: Target Multiplier > 0 olmalı");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpNWNormLen < 2 || InpNWBandwidth < 1 || InpNWLookback < 2 ||
      InpNWOscSmooth < 1 || InpNWSigLen < 1 || InpNWATRLen < 1 || InpNWVolSmooth < 1)
     {
      Print("SP: NW parametreleri geçersiz (hepsi >= 1, norm_len >= 2 olmalı)");
      return INIT_PARAMETERS_INCORRECT;
     }

   g_tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(g_tickSize <= 0.0)
      g_tickSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   ENUM_ACCOUNT_MARGIN_MODE mode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   g_isHedge = (mode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);

   g_atrHandle = iATR(_Symbol, _Period, ATR_LENGTH);
   NwInit();

   g_lastPivotHigh = NA_DOUBLE;
   g_lastPivotLow = NA_DOUBLE;
   g_lastTradeBar = NO_BAR;
   g_barIndex = 0;
   g_lastBarTime = 0;
   g_historyDone = false;
   g_tradeIdSeq = 0;
   g_totalSignals = 0;
   g_totalTrades = 0;
   g_sigDir = 0;
   g_sigNoSLTP = true;

   Print("SP: başlatıldı (v2 NW sinyal motoru). Hedge=", g_isHedge ? "EVET" : "HAYIR",
         " tickSize=", DoubleToString(g_tickSize, g_digits));
   g_eqBaseline = AccountInfoDouble(ACCOUNT_EQUITY);
   g_eqPeak = g_eqBaseline;
   g_eqStartTime = TimeCurrent();
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                           |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ObjectsDeleteAll(0, "SP_");
   Comment("");
   if(g_atrHandle != INVALID_HANDLE)
      IndicatorRelease(g_atrHandle);
  }

//+------------------------------------------------------------------+
//| Bakiye (Varlık) Trailing Stop - kâr koruması                      |
//+------------------------------------------------------------------+
double g_eqBaseline = 0.0;
double g_eqPeak     = 0.0;
datetime g_eqStartTime = 0;

void EquityTrailCheck()
  {
   if(!InpEquityTrailOn)
      return;
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > g_eqPeak)
      g_eqPeak = eq;
   double gain = g_eqPeak - g_eqBaseline;
   if(gain <= 0.0)
      return;
   if(gain < InpEquityTrailMinProfit)
      return;
   if(InpEquityTrailDelayMin > 0 && TimeCurrent() - g_eqStartTime < InpEquityTrailDelayMin * 60)
      return;
   double trigger = g_eqPeak - gain * InpEquityGivebackPct / 100.0;
   if(eq > trigger)
      return;

   Print("EQ: BAKİYE TRAILING STOP tetiklendi - zirve=", DoubleToString(g_eqPeak, 2),
         " varlık=", DoubleToString(eq, 2), " (", DoubleToString(InpEquityGivebackPct, 1),
         "% geri çekilme) - pozisyonlar kapatılıyor.");
   int closed = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(InpEquityOnlyMagic && PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      CTrade trade;
      trade.SetDeviationInPoints(InpDeviation);
      if(trade.PositionClose(ticket, InpDeviation))
         closed++;
      else
         Print("EQ: kapatma başarısız, ticket=", ticket, " retcode=", trade.ResultRetcode());
     }
   g_eqBaseline = AccountInfoDouble(ACCOUNT_EQUITY);
   g_eqPeak = g_eqBaseline;
   Print("EQ: ", closed, " pozisyon kapatıldı, yeni başlangıç=", DoubleToString(g_eqBaseline, 2));
   Notify("Bakiye Trailing Stop",
          IntegerToString(closed) + " pozisyon kapatıldı, yeni başlangıç: " + DoubleToString(g_eqBaseline, 2));
  }

//+------------------------------------------------------------------+
//| OnTick                                                             |
//+------------------------------------------------------------------+
void OnTick()
  {
   EquityTrailCheck();
   datetime curBarTime = iTime(_Symbol, _Period, 0);

   if(!g_historyDone)
     {
      ProcessHistory();
      g_historyDone = true;
      g_lastBarTime = curBarTime;
      AdoptExistingPositions();
      UpdateStatusPanel();
      ChartRedraw(0);
     }

   bool newBar = (curBarTime != g_lastBarTime);
   if(newBar)
     {
      int lastShift = iBarShift(_Symbol, _Period, g_lastBarTime, false);
      if(lastShift < 1)
         lastShift = 1;
      g_lastBarTime = curBarTime;
      g_barIndex += lastShift;

      for(int s = lastShift; s >= 1; s--)
        {
         long bi = g_barIndex - s;
         int mask = ProcessConfirmedBar(s, bi);
         // sinyal kapanan barın kapanışında onaylanır -> piyasa emri
         // yalnız en son kapanan bardaki sinyal emre çevrilir
         if(mask != 0)
           {
            if(s == 1)
               OpenTrade(g_sigDir, g_sigRawDir, g_sigNoSLTP, g_sigName,
                         g_sigEntry, g_sigStop, g_sigTarget, g_sigBar);
            else
               Print("SP: atlanan bar nedeniyle eski sinyal emre çevrilmedi (sadece çizildi): ",
                     g_sigName);
           }
        }

      UpdateStatusPanel();
      ChartRedraw(0);
     }

   ManageTradesTick();
  }

//+------------------------------------------------------------------+
//| Durum paneli                                                       |
//+------------------------------------------------------------------+
void UpdateStatusPanel()
  {
   string txt = "";
   txt += "═══ Scalper Pro Gold EA v2 (NW Liquidity) ═══\n";
   txt += StringFormat("Sembol: %s  Zaman Dilimi: %s\n", _Symbol, EnumToString(_Period));
   txt += StringFormat("Bar indeksi: %I64d | Açık işlem: %d | Toplam sinyal/işlem: %d/%d\n",
                       g_barIndex, ArraySize(g_trades), g_totalSignals, g_totalTrades);
   txt += StringFormat("NW: osc=%s sig=%s vol=%s | Likidite: %s\n",
                       (g_nwOsc == NA_DOUBLE) ? "-" : DoubleToString(g_nwOsc, 3),
                       (g_nwSig == NA_DOUBLE) ? "-" : DoubleToString(g_nwSig, 3),
                       (g_nwVol == NA_DOUBLE) ? "-" : DoubleToString(g_nwVol, g_digits),
                       (g_nwLineType == 1) ? StringFormat("ÜST %s", DoubleToString(g_nwLinePrice, g_digits)) :
                       (g_nwLineType == -1) ? StringFormat("ALT %s", DoubleToString(g_nwLinePrice, g_digits)) : "YOK");
   txt += StringFormat("Aktif sinyal: %d/14 | Son sinyal: %s\n",
                       EnabledSignalCount(), (g_sigName == "") ? "-" : g_sigName);
   txt += StringFormat("Mod: %s%s | Lot: %s | Klasik TP Çarpanı: %.1f",
                       (InpTradeMode == SP_TRADE_ON) ? "OTOMATİK İŞLEM" : "SİNYAL",
                       InpReverseMode ? " + TERS İŞLEM" : "",
                       (InpLotMode == SP_LOT_FIXED) ? "sabit" : "risk %",
                       InpTargetMult);
   double eqGain = g_eqPeak - g_eqBaseline;
   bool eqArmed = (eqGain >= InpEquityTrailMinProfit) &&
                  (InpEquityTrailDelayMin <= 0 || TimeCurrent() - g_eqStartTime >= InpEquityTrailDelayMin * 60);
   txt += StringFormat("\nZirve: %.2f | Taban: %.2f | Tetik: %.2f (%.0f%%) | Eşik: %.2f %s",
                       g_eqPeak, g_eqBaseline,
                       (g_eqPeak > g_eqBaseline) ? g_eqPeak - eqGain * InpEquityGivebackPct / 100.0 : 0.0,
                       InpEquityGivebackPct, InpEquityTrailMinProfit,
                       (InpEquityTrailOn ? (eqArmed ? "[AKTİF]" : "[BEKLİYOR]") : "[KAPALI]"));
   Comment(txt);
  }

int EnabledSignalCount()
  {
   int cnt = 0;
   if(InpSigWeakenBull  != SIG_OFF) cnt++;
   if(InpSigWeakenBear  != SIG_OFF) cnt++;
   if(InpSigBullCross   != SIG_OFF) cnt++;
   if(InpSigBearCross   != SIG_OFF) cnt++;
   if(InpSigBullZero    != SIG_OFF) cnt++;
   if(InpSigBearZero    != SIG_OFF) cnt++;
   if(InpSigNewUpper    != SIG_OFF) cnt++;
   if(InpSigNewLower    != SIG_OFF) cnt++;
   if(InpSigUpperSwept  != SIG_OFF) cnt++;
   if(InpSigLowerSwept  != SIG_OFF) cnt++;
   if(InpSigBullRebound != SIG_OFF) cnt++;
   if(InpSigBearRebound != SIG_OFF) cnt++;
   if(InpSigClassicBull != SIG_OFF) cnt++;
   if(InpSigClassicBear != SIG_OFF) cnt++;
   return cnt;
  }
//+------------------------------------------------------------------+

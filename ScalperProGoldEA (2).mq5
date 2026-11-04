//+------------------------------------------------------------------+
//|                                       ScalperProGoldEA.mq5       |
//|                                                                    |
//|  TradingView "Scalper Pro 3 Min Gold" Pine Script® v5 göstergesinin|
//|  MetaTrader 5 Expert Advisor (robot) portu                         |
//|                                                                    |
//|  Strateji özeti:                                                   |
//|   - Pivot High/Low (yapı) takibi                                  |
//|   - Konsolidasyon filtresi (ATR'ye göre sıkışma)                  |
//|   - Cooldown filtresi                                             |
//|   - Pivot kırılımı (breakout) sinyalleri:                         |
//|       LONG : kapanış son pivot high'ın üzerine, dip > son pivot low|
//|       SHORT: kapanış son pivot low'un altına, tepe < son pivot high|
//|   - Giriş = sinyal barı kapanışı, SL = pivot, TP = risk × mult    |
//+------------------------------------------------------------------+
#property copyright "Pine portu - orijinal: Scalper Pro 3 Min Gold"
#property version   "1.00"
#property description "Scalper Pro Gold - MT5 EA (Pine v5 birebir port)"
#property description "Pivot kirilimi, konsolidasyon ve cooldown filtreli scalper robotu"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Giriş tipleri                                                      |
//+------------------------------------------------------------------+
enum ENUM_SP_TRADE_MODE
  {
   SP_TRADE_OFF = 0,     // Sadece sinyal / çizim
   SP_TRADE_ON  = 1      // Otomatik pozisyon aç
  };

enum ENUM_SP_LOT_MODE
  {
   SP_LOT_FIXED = 0,     // Sabit lot
   SP_LOT_RISK  = 1      // Risk yüzdesi (SL mesafesine göre)
  };

//+------------------------------------------------------------------+
//| Girdiler - Pine input karşılıkları                                 |
//+------------------------------------------------------------------+
input group              "═══ Strategy (Strateji) ═══"
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
input bool               InpReverseMode     = false; // Ters İşlem Modu (sinyalin tersi yön + SL/TP takas)
input bool               InpUseOppExit      = false; // Zıt Sinyal Çıkışı (TP/SL yerine sinyal sayacı)
input int                InpOppExitCount    = 3;     // Kaç zıt sinyalde kapansın
input ENUM_SP_LOT_MODE   InpLotMode         = SP_LOT_FIXED; // Lot modu
input double             InpFixedLot        = 0.1;   // Sabit lot
input double             InpRiskPercent     = 1.0;   // Risk % (bakiye)
input int                InpMaxBarsInTrade  = 0;     // Ekstra: kaç bar sonra kapat (0 = kapalı)
input bool               InpAllowMultiple   = true;  // Eş zamanlı çoklu pozisyona izin ver
input long               InpMagic           = 20261031; // Magic number
input ulong              InpDeviation       = 30;    // Slippage (points)

input group              "═══ Appearance (Görsel) ═══"
input bool               InpDrawSetups      = true;  // Kutu/etiket/çizgileri çiz
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

//+------------------------------------------------------------------+
//| Sabitler                                                           |
//+------------------------------------------------------------------+
#define ATR_LENGTH                14
#define MAX_SETUPS_ON_CHART       160    // Pine box/label/line limitleri (~500) ile uyumlu
#define NO_BAR                    (-1)
#define NA_DOUBLE                 EMPTY_VALUE

//+------------------------------------------------------------------+
//| İşlem kaydı (yalnız canlı pozisyonlar)                             |
//+------------------------------------------------------------------+
struct SPTradeRec
  {
   ulong  ticket;      // pozisyon bileti
   int    dir;         // +1 long, -1 short (işlem yönü)
   int    sigDir;      // sinyalin HAM yönü (+1 bull / -1 bear) - sayaç için
   int    oppCount;    // sayılan zıt sinyal sayısı
   long   signalBar;   // sinyal barı (Pine bar_index)
   double entryPrice;  // sinyal barı kapanışı (referans giriş)
   double stopPrice;
   double targetPrice;
  };

//+------------------------------------------------------------------+
//| Global durum                                                       |
//+------------------------------------------------------------------+
double   g_tickSize;
int      g_digits;
bool     g_isHedge;
long     g_barIndex;        // Pine bar_index karşılığı (şekillenen bar)
datetime g_lastBarTime;
bool     g_historyDone;
int      g_atrHandle;

// yapı takibi (Pine var lastPivotHigh / lastPivotLow)
double   g_lastPivotHigh;
double   g_lastPivotLow;
long     g_lastTradeBar;    // Pine var lastTradeBar (NO_BAR = na)

// çizim nesneleri (FIFO)
string   g_setupNames[];
SPTradeRec g_trades[];
long     g_tradeIdSeq;

// sinyal anındaki kurulum bilgisi (core -> OnTick aktarımı)
int      g_sigDir;
double   g_sigEntry, g_sigStop, g_sigTarget;
long     g_sigBar;

int      g_totalSignals;
int      g_totalTrades;

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

// Pine color.new(c, transp) -> grafik arka planına doğru harmanlama
color WithTransparency(color c, int transp)
  {
   color bg = (color)ChartGetInteger(0, CHART_COLOR_BACKGROUND);
   return BlendColors(c, bg, transp / 100.0);
  }

//+------------------------------------------------------------------+
//| Zaman / fiyat yardımcıları                                         |
//+------------------------------------------------------------------+
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

// Fiyatı tick ızgarasına yuvarla (broker SL/TP doğrulaması için zorunlu)
double NormPrice(double price)
  {
   if(g_tickSize <= 0.0)
      return NormalizeDouble(price, g_digits);
   return NormalizeDouble(MathRound(price / g_tickSize) * g_tickSize, g_digits);
  }

//+------------------------------------------------------------------+
//| Pivot tespiti (Pine ta.pivothigh / ta.pivotlow)                    |
//| Sağ onay = pivotLength bar sonra; komşular kesinlikle düşük olmalı |
//+------------------------------------------------------------------+
double PivotHighValue(int shift, long barIdx)
  {
   int p = InpPivotLength;
   if(barIdx < 2 * p)          // Pine warmup: left+right bar gerekli
      return NA_DOUBLE;
   int candShift = shift + p;  // aday pivot barı
   double cand = iHigh(_Symbol, _Period, candShift);
   for(int k = shift; k <= shift + 2 * p; k++)
     {
      if(k == candShift)
         continue;
      if(iHigh(_Symbol, _Period, k) >= cand)   // eşit/daha yüksek komşu -> pivot değil
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
      if(iLow(_Symbol, _Period, k) <= cand)    // eşit/daha düşük komşu -> pivot değil
         return NA_DOUBLE;
     }
   return cand;
  }

//+------------------------------------------------------------------+
//| ATR (Pine ta.atr(14))                                              |
//+------------------------------------------------------------------+
double AtrAt(int shift, long barIdx)
  {
   if(barIdx < ATR_LENGTH)     // Pine warmup: ilk 14 barda na
      return NA_DOUBLE;
   double buf[1];
   if(g_atrHandle == INVALID_HANDLE)
      return NA_DOUBLE;
   if(CopyBuffer(g_atrHandle, 0, shift, 1, buf) != 1)
      return NA_DOUBLE;
   return buf[0];
  }

//+------------------------------------------------------------------+
//| Çubuk işleme çekirdeği (Pine bar hesabı)                           |
//| Çıktı: g_sigDir (0/1/-1) + g_sigEntry/Stop/Target                 |
//+------------------------------------------------------------------+
int ProcessConfirmedBar(int shift, long barIdx)
  {
   g_sigDir = 0;
   double o = iOpen(_Symbol, _Period, shift);
   double c = iClose(_Symbol, _Period, shift);
   double h = iHigh(_Symbol, _Period, shift);
   double l = iLow(_Symbol, _Period, shift);
   double c1 = (barIdx >= 1) ? iClose(_Symbol, _Period, shift + 1) : NA_DOUBLE;

   //---- 1) Yapı takibi (Pine: ph/pl -> lastPivotHigh/Low)
   // crossover için bir önceki barın değerleri gerekir (y[1])
   double prevLPH = g_lastPivotHigh;
   double prevLPL = g_lastPivotLow;

   double ph = PivotHighValue(shift, barIdx);
   double pl = PivotLowValue(shift, barIdx);
   if(ph != NA_DOUBLE)
      g_lastPivotHigh = ph;
   if(pl != NA_DOUBLE)
      g_lastPivotLow = pl;

   //---- 2) Konsolidasyon filtresi
   // Pine: pastHigh = ta.highest(high[1], consLength)
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

   //---- 3) Cooldown filtresi
   bool canEnter = InpUseCooldown ? (g_lastTradeBar == NO_BAR ||
                                     barIdx - g_lastTradeBar >= InpCooldownBars) : true;

   //---- 4) Kırılım mantığı
   // Pine ta.crossover(close, lastPivotHigh): close[1] < lastPivotHigh[1] and close > lastPivotHigh
   // (y[1] = bir önceki barın son pivot değeri -> prevLPH)
   bool crossUp = (barIdx >= 1 && prevLPH != NA_DOUBLE && c1 < prevLPH) &&
                  (g_lastPivotHigh != NA_DOUBLE && c > g_lastPivotHigh);
   bool crossDn = (barIdx >= 1 && prevLPL != NA_DOUBLE && c1 > prevLPL) &&
                  (g_lastPivotLow != NA_DOUBLE && c < g_lastPivotLow);

   bool bullCandle = (c > o);
   bool bearCandle = (c < o);

   bool bullishBreakout = bullCandle && crossUp &&
                          (g_lastPivotLow != NA_DOUBLE && l > g_lastPivotLow) &&
                          isConsolidating && canEnter;

   bool bearishBreakout = bearCandle && crossDn &&
                          (g_lastPivotHigh != NA_DOUBLE && h < g_lastPivotHigh) &&
                          isConsolidating && canEnter;

   //---- 5) Kurulum (Pine: risk > 0 kontrolü; risk<=0 ise hiçbir şey olmaz)
   int mask = 0;
   if(bullishBreakout)
     {
      double entryPrice = c;
      double stopPrice  = g_lastPivotLow;
      double risk = entryPrice - stopPrice;
      if(risk > 0)
        {
         g_lastTradeBar = barIdx;
         g_sigDir = 1;
         g_sigEntry = entryPrice;
         g_sigStop = stopPrice;
         g_sigTarget = NormPrice(entryPrice + risk * InpTargetMult);
         g_sigBar = barIdx;
         mask = 1;
         g_totalSignals++;
        }
     }
   else if(bearishBreakout)
     {
      double entryPrice = c;
      double stopPrice  = g_lastPivotHigh;
      double risk = stopPrice - entryPrice;
      if(risk > 0)
        {
         g_lastTradeBar = barIdx;
         g_sigDir = -1;
         g_sigEntry = entryPrice;
         g_sigStop = stopPrice;
         g_sigTarget = NormPrice(entryPrice - risk * InpTargetMult);
         g_sigBar = barIdx;
         mask = 2;
         g_totalSignals++;
        }
     }

   //---- 5b) Ters İşlem Modu: sinyalin tersi yön açılır,
   // normal TP seviyesi SL, normal SL seviyesi TP olur.
   // Çizimler daha sonra yapıldığı için grafik GERÇEK işlemi gösterir.
   if(mask != 0 && InpReverseMode)
     {
      double tmp = g_sigStop;
      g_sigStop = g_sigTarget;     // ters: SL = normal TARGET seviyesi
      g_sigTarget = tmp;           // ters: TP = normal STOP LOSS seviyesi
      g_sigDir = -g_sigDir;        // ters yön
     }

   //---- 6) Kurulum çizimleri (Pine box/label/line blokları)
   if(mask != 0 && InpDrawSetups && barIdx >= g_barIndex - InpDrawHistoryBars)
      DrawSetup(barIdx, g_sigDir, g_sigEntry, g_sigStop, g_sigTarget);

   //---- 7) Bildirimler (yalnız canlı bar)
   if(mask != 0 && barIdx >= g_barIndex - 1 && (InpAlertsOn || InpPushOn))
     {
      if(mask == 1)
         Notify("Scalper Pro: LONG Breakout",
                StringFormat("ENTRY=%.5f SL=%.5f TP=%.5f", g_sigEntry, g_sigStop, g_sigTarget));
      else
         Notify("Scalper Pro: SHORT Breakout",
                StringFormat("ENTRY=%.5f SL=%.5f TP=%.5f", g_sigEntry, g_sigStop, g_sigTarget));
     }

   return mask;
  }

//+------------------------------------------------------------------+
//| Kurulum çizimleri (Pine: 2 box + 3 label + 3 line)                 |
//+------------------------------------------------------------------+
void PushSetupName(const string name)
  {
   int n = ArraySize(g_setupNames);
   ArrayResize(g_setupNames, n + 1);
   g_setupNames[n] = name;
   // Pine max_boxes/labels/lines = 500 -> en eskileri sil (FIFO)
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
   datetime t1 = TimeOfBar(barIdx + InpBoxLength);   // Pine: right = bar_index + boxLength
   string tag = StringFormat("SP_%I64d", barIdx * 8 + (dir > 0 ? 1 : 2));

   if(dir > 0)
     {
      // LONG: kırmızı kutu (entry..stop), teal kutu (target..entry)
      MakeRect(tag + "_stopbox", t0, t1, entryPrice, stopPrice, InpStopColor, 80);
      MakeRect(tag + "_tgtbox", t0, t1, targetPrice, entryPrice, InpTargetColor, 80);
     }
   else
     {
      // SHORT: kırmızı kutu (stop..entry), teal kutu (entry..target)
      MakeRect(tag + "_stopbox", t0, t1, stopPrice, entryPrice, InpStopColor, 80);
      MakeRect(tag + "_tgtbox", t0, t1, entryPrice, targetPrice, InpTargetColor, 80);
     }

   // etiketler (Pine: x = bar_index + boxLength)
   datetime tl = t1;
   MakeLabel(tag + "_lbEntry", tl, entryPrice, "ENTRY", InpEntryColor, ANCHOR_LEFT);
   if(dir > 0)
     {
      MakeLabel(tag + "_lbStop", tl, stopPrice, "STOP LOSS", InpStopColor, ANCHOR_UPPER);   // label_lower_left
      MakeLabel(tag + "_lbTgt", tl, targetPrice, "TARGET", InpTargetColor, ANCHOR_LOWER);    // label_upper_left
     }
   else
     {
      MakeLabel(tag + "_lbStop", tl, stopPrice, "STOP LOSS", InpStopColor, ANCHOR_LOWER);    // label_upper_left
      MakeLabel(tag + "_lbTgt", tl, targetPrice, "TARGET", InpTargetColor, ANCHOR_UPPER);    // label_lower_left
     }

   // çizgiler
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

void OpenTrade(int dir, int rawSigDir, double entryRef, double stopPrice, double targetPrice, long signalBar)
  {
   if(InpTradeMode != SP_TRADE_ON)
      return;
   if(!HedgeAllowsNewTrade())
     {
      Print("SP: mevcut pozisyon/limit nedeniyle yeni emir açılmadı (netting veya çoklu kapalı).");
      return;
     }

   // Grafikte işaretlenen KESİN seviyeler (tick ızgarasına yuvarlanmış)
   double sl = NormPrice(stopPrice);       // STOP LOSS kutusunun seviyesi
   double tp = NormPrice(targetPrice);     // TARGET kutusunun seviyesi
   double entry = NormPrice(entryRef);     // ENTRY (sinyal barı kapanışı)

   double risk = MathAbs(entry - sl);
   if(risk <= g_tickSize)
     {
      Print("SP: risk mesafesi 1 tick'ten küçük, emir açılmadı.");
      return;
     }

   // Zıt Sinyal Çıkışı modunda TP/SL KULLANILMAZ (yalnız referans seviyelerdir)
   double sendSL = InpUseOppExit ? 0.0 : sl;
   double sendTP = InpUseOppExit ? 0.0 : tp;

   if(!InpUseOppExit)
     {
      // Broker minimum SL/TP mesafesi (SYMBOL_TRADE_STOPS_LEVEL) kontrolü
      double point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
      long stopsLevel = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
      double minDist = stopsLevel * point;
      if(minDist > 0.0 && (MathAbs(entry - sl) < minDist || MathAbs(tp - entry) < minDist))
        {
         Print("SP: broker min. stop mesafesi (", DoubleToString(minDist, g_digits),
               ") sağlanamıyor - seviyeler korunarak emir atlandı. SL=", DoubleToString(sl, g_digits),
               " TP=", DoubleToString(tp, g_digits));
         return;
        }
     }

   double lots = CalcLots(risk);
   CTrade trade;
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviation);
   trade.SetTypeFillingBySymbol(_Symbol);

   // Piyasa emri (+ klasik modda otomatik SL/TP)
   bool ok = false;
   if(dir > 0)
      ok = trade.Buy(lots, _Symbol, 0.0, sendSL, sendTP, "SP LONG");
   else
      ok = trade.Sell(lots, _Symbol, 0.0, sendSL, sendTP, "SP SHORT");

   if(ok && trade.ResultRetcode() == TRADE_RETCODE_DONE)
     {
      ulong deal = trade.ResultDeal();
      ulong posId = 0;
      if(deal > 0)
         posId = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      if(posId == 0)
         posId = trade.ResultOrder();

      // Dolum sonrası SL/TP doğrulaması (yalnız klasik modda)
      if(!InpUseOppExit && posId != 0 && PositionSelectByTicket(posId))
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
      g_trades[n].signalBar = signalBar;
      g_trades[n].entryPrice = entry;
      g_trades[n].stopPrice = sl;
      g_trades[n].targetPrice = tp;
      g_totalTrades++;
      if(InpUseOppExit)
         Print("SP: pozisyon açıldı #", posId, " [ZIT SİNYAL ÇIKIŞI: ",
               IntegerToString(InpOppExitCount), " zıt sinyalde kapanır] lot=", DoubleToString(lots, 2));
      else
         Print("SP: pozisyon açıldı #", posId, " SL=", DoubleToString(sl, g_digits),
               " TP=", DoubleToString(tp, g_digits), " lot=", DoubleToString(lots, 2));
     }
   else
      Print("SP: emir gönderilemedi, retcode=", trade.ResultRetcode(),
            " comment=", trade.ResultComment());
  }

//+------------------------------------------------------------------+
//| Zıt sinyal sayacı: açık işlemleri, giriş sinyalinin TERSİ yöndeki  |
//| sinyallerle sayar; N'nci zıt sinyalde pozisyonu kapatır.           |
//| (Ters modda da geçerli: ters modda ▼=LONG sinyali olduğundan       |
//|  kural aynıdır - giriş sinyalinin tersi sayılır.)                  |
//+------------------------------------------------------------------+
void OnSignalEvent(int rawDir)
  {
   if(!InpUseOppExit || InpOppExitCount < 1)
      return;
   for(int i = ArraySize(g_trades) - 1; i >= 0; i--)
     {
      if(g_trades[i].sigDir != -rawDir)
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

// Her tick: kapanan pozisyonları temizle (zıt sinyal modunda süre sonu KULLANILMAZ)
void ManageTradesTick()
  {
   for(int i = ArraySize(g_trades) - 1; i >= 0; i--)
     {
      if(g_trades[i].ticket == 0 || !PositionSelectByTicket(g_trades[i].ticket))
        {
         // pozisyon manuel/kurumsal olarak kapanmış
         RemoveTradeAt(i);
         continue;
        }
      if(!InpUseOppExit && InpMaxBarsInTrade > 0 && g_barIndex - g_trades[i].signalBar > InpMaxBarsInTrade)
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

      int n = ArraySize(g_trades);
      ArrayResize(g_trades, n + 1);
      g_trades[n].ticket = ticket;
      g_trades[n].dir = dir;
      g_trades[n].sigDir = InpReverseMode ? -dir : dir; // ham sinyal yönü (yeniden inşa)
      g_trades[n].oppCount = 0;
      g_trades[n].signalBar = signalBar;
      g_trades[n].entryPrice = PositionGetDouble(POSITION_PRICE_OPEN);
      g_trades[n].stopPrice = PositionGetDouble(POSITION_SL);
      g_trades[n].targetPrice = PositionGetDouble(POSITION_TP);
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
      ProcessConfirmedBar(s, bi);   // sinyal -> çizim (yerinde), emir yok
     }
  }

//+------------------------------------------------------------------+
//| Custom expert initialization                                       |
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

   g_tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(g_tickSize <= 0.0)
      g_tickSize = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_digits = (int)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);

   ENUM_ACCOUNT_MARGIN_MODE mode = (ENUM_ACCOUNT_MARGIN_MODE)AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   g_isHedge = (mode == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);

   g_atrHandle = iATR(_Symbol, _Period, ATR_LENGTH);

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

   Print("SP: başlatıldı. Hedge=", g_isHedge ? "EVET" : "HAYIR",
         " tickSize=", DoubleToString(g_tickSize, g_digits));
   g_eqBaseline = AccountInfoDouble(ACCOUNT_EQUITY);
   g_eqPeak = g_eqBaseline;
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| Custom expert deinitialization                                     |
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
//| - Zirve: EA çalıştığından beri görülen en yüksek CANLI VARLIK     |
//|   (equity; açık pozisyonlarla birlikte hesabın anlık toplamı)     |
//| - Tetik: zirveden, kazanılan kârın %InpEquityGivebackPct kadarı   |
//|   geri verildiğinde (ör. 100→104→102 = kârın %50'si geri verildi) |
//| - Tetikte TÜM pozisyonlar kapanır; yeni başlangıç = kapanıştaki   |
//|   varlık (ör. 102; sonra 102→110→106'da yeniden kapanır)          |
//+------------------------------------------------------------------+
double g_eqBaseline = 0.0;
double g_eqPeak     = 0.0;

void EquityTrailCheck()
  {
   if(!InpEquityTrailOn)
      return;
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq > g_eqPeak)
      g_eqPeak = eq;
   double gain = g_eqPeak - g_eqBaseline;
   if(gain <= 0.0)
      return;   // korunacak kâr yok (zirve henüz tabanın üstünde değil)
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
   g_eqBaseline = AccountInfoDouble(ACCOUNT_EQUITY);   // yeni başlangıç
   g_eqPeak = g_eqBaseline;
   Print("EQ: ", closed, " pozisyon kapatıldı, yeni başlangıç=", DoubleToString(g_eqBaseline, 2));
   Notify("Bakiye Trailing Stop",
          IntegerToString(closed) + " pozisyon kapatıldı, yeni başlangıç: " + DoubleToString(g_eqBaseline, 2));
  }

//+------------------------------------------------------------------+
//| Custom expert tick function                                        |
//+------------------------------------------------------------------+
void OnTick()
  {
   EquityTrailCheck();   // bakiye trailing stop: zirveden %X düşüşte TÜMÜNÜ kapat
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
      // kaç bar atlandıysa o kadar barı sırayla işle
      int lastShift = iBarShift(_Symbol, _Period, g_lastBarTime, false);
      if(lastShift < 1)
         lastShift = 1;
      g_lastBarTime = curBarTime;
      g_barIndex += lastShift;

      for(int s = lastShift; s >= 1; s--)
        {
         long bi = g_barIndex - s;
         int mask = ProcessConfirmedBar(s, bi);
         // sinyal, kapanan barın kapanışında onaylanır -> piyasa emri
         // (dolum ≈ sinyal barı kapanışı; Pine'daki ENTRY fiyatı = close)
         // yalnız en son kapanan bardaki sinyal emre çevrilir; atlanan
         // bar(lar)daki sinyaller yalnız çizilir (eski fiyattan emir açılmaz)
         if(mask != 0)
           {
            int rawDir = (mask & 1) ? 1 : -1;   // sinyalin HAM yönü
            OnSignalEvent(rawDir);              // açık işlemleri zıt sinyal sayacıyla say
            if(s == 1)
               OpenTrade(g_sigDir, rawDir, g_sigEntry, g_sigStop, g_sigTarget, g_sigBar);
            else
               Print("SP: atlanan bar nedeniyle eski sinyal emre çevrilmedi (sadece çizildi).");
           }
        }

      UpdateStatusPanel();
      ChartRedraw(0);
     }

   // pozisyon takibi (kapanma / opsiyonel süre sonu)
   ManageTradesTick();
  }

//+------------------------------------------------------------------+
//| Durum paneli                                                       |
//+------------------------------------------------------------------+
void UpdateStatusPanel()
  {
   string txt = "";
   txt += "═══ Scalper Pro Gold EA ═══\n";
   txt += StringFormat("Sembol: %s  Zaman Dilimi: %s\n", _Symbol, EnumToString(_Period));
   txt += StringFormat("Bar indeksi: %I64d\n", g_barIndex);
   txt += StringFormat("Son Pivot High: %s | Son Pivot Low: %s\n",
                       (g_lastPivotHigh == NA_DOUBLE) ? "-" : DoubleToString(g_lastPivotHigh, g_digits),
                       (g_lastPivotLow == NA_DOUBLE) ? "-" : DoubleToString(g_lastPivotLow, g_digits));
   txt += StringFormat("Son sinyal barı: %s | Açık işlem: %d\n",
                       (g_lastTradeBar == NO_BAR) ? "-" : IntegerToString((int)g_lastTradeBar),
                       ArraySize(g_trades));
   txt += StringFormat("Toplam sinyal: %d | Toplam işlem: %d\n", g_totalSignals, g_totalTrades);
   txt += StringFormat("Mod: %s%s%s | Lot: %s | TP Çarpanı: %.1f",
                       (InpTradeMode == SP_TRADE_ON) ? "OTOMATİK İŞLEM" : "SİNYAL",
                       InpReverseMode ? " + TERS İŞLEM" : "",
                       InpUseOppExit ? StringFormat(" + ZIT SİNYAL ÇIKIŞI(%d)", InpOppExitCount) : "",
                       (InpLotMode == SP_LOT_FIXED) ? "sabit" : "risk %",
                       InpTargetMult);
   txt += StringFormat("Zirve: %.2f | Taban: %.2f | Tetik: %.2f (%.0f%% geri çekilme)\n",
                       g_eqPeak, g_eqBaseline,
                       (g_eqPeak > g_eqBaseline) ? g_eqPeak - (g_eqPeak - g_eqBaseline) * InpEquityGivebackPct / 100.0 : 0.0,
                       InpEquityGivebackPct);
   Comment(txt);
  }
//+------------------------------------------------------------------+

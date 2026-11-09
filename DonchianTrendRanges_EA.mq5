//+------------------------------------------------------------------+
//|  DonchianTrendRanges_EA.mq5                                      |
//|     "Donchian Trend Ranges [AlgoAlpha]" - MT5 ROBOT (EA)         |
//|                                                                  |
//|  Bu bir UZMAN DANIŞMAN (robot) dosyasıdır; gösterge değildir.    |
//|  Grafiğe eklenir, sinyal geldiğinde emir açar ve kapatır.        |
//|                                                                  |
//|  ÖZET:                                                           |
//|   * Pine kodu MQL5'e BIREBIR çevrildi (aşağıdaki matematik).     |
//|   * LONG giriş / SHORT giriş / LONG TP / LONG SL / SHORT TP /    |
//|     SHORT SL sinyalleri AÇILIR MENÜLERDEN seçilir.               |
//|     Örnek: LONG giriş = "Strong Short TP" seçilirse, o olay      |
//|     oluşan kapalı mumda LONG işlem açılır.                       |
//|   * TP/SL sayımı: sinyal, pozisyon açıldıktan SONRA kapanan      |
//|     mumlarda sayılır (N. sinyalde kapat). Sayım geçmişten        |
//|     yeniden hesaplanır; EA yeniden başlasa da bozulmaz.          |
//|   * Sinyaller YALNIZCA KAPANMIŞ mumlarda değerlendirilir.        |
//|   * Ek güvenlik: sabit TP/SL (point), para bazlı TP/SL, maksimum |
//|     pozisyon süresi, spread filtresi, otomatik sıfırlama.        |
//|                                                                  |
//|  PINE MATEMATİĞİ (birebir):                                      |
//|   l = ta.lowest(length)      u = ta.highest(length)              |
//|   basis = math.avg(u, l)                                         |
//|   fbasis := basis == basis[con] ? basis : fbasis[1]  (yapışkan)  |
//|   dev   = ta.stdev(close, length, false) * mult      (n-1 bölme) |
//|   vol   = ta.atr(14)                                  (RMA)      |
//|   rangge := fbasis != fbasis[1] ? dev : rangge[1]    (yapışkan)  |
//|   upper = fbasis + rangge , lower = fbasis - rangge              |
//|   uu = upper + vol , ul = upper - vol                            |
//|   lu = lower + vol , ll = lower - vol                            |
//|                                                                  |
//|  SİNYALLER (Pine plotchar koşullarıyla aynı):                    |
//|   Strong Long TP  = crossunder(close, uu)                        |
//|   Strong Short TP = crossover(close, ll)                         |
//|   Weak Long TP    = crossunder(close, ul) and not (close, uu)    |
//|   Weak Short TP   = crossover(close, lu)  and not (close, ll)    |
//|   Bullish Shift   = crossover(close, fbasis)                     |
//|   Bearish Shift   = crossunder(close, fbasis)                    |
//|                                                                  |
//|  Pine'daki na davranışı korunur: na içeren karşılaştırma false   |
//|  kabul edilir; seviyeler fbasis sabitlenince oluşur, grafikte    |
//|  ilk mumlarda sinyal görülmez (Pine'da da aynıdır).              |
//|                                                                  |
//|  NOT: Yoğun öneriler - önce Strategy Tester'da test edin.        |
//|  HEDGING hesap önerilir (aynı anda long+short açılabilir).       |
//+------------------------------------------------------------------+
#property copyright "Donchian Trend Ranges [AlgoAlpha] - MT5 Robot"
#property version   "1.00"
#property strict
#property description "Donchian Trend Ranges [AlgoAlpha] birebir Pine çevirisi ile işlem açar"
#property description "LONG/SHORT giriş ve TP/SL sinyalleri açılır menüden seçilir"
#property description "Sinyaller yalnızca kapanmış mumlarda değerlendirilir"
#property description "Sabit TP/SL, para bazlı çıkış, süre sınırı ve otomatik sıfırlama"

#include <Trade/Trade.mqh>

CTrade trade;

//+------------------------------------------------------------------+
//| Tipler                                                           |
//+------------------------------------------------------------------+
// Açılır menülerde seçilebilen sinyaller (Pine olayları)
enum ENUM_DON_EVENT
  {
   DON_EVENT_NONE   = 0, // (yok / kapalı)
   DON_BULL_SHIFT   = 1, // Bullish Trend Shift (close, fbasis'i yukarı keser)
   DON_BEAR_SHIFT   = 2, // Bearish Trend Shift (close, fbasis'i aşağı keser)
   DON_STRONG_LONG  = 3, // Strong Long TP  (close, uu altına iner)
   DON_WEAK_LONG    = 4, // Weak Long TP    (close, ul altına iner; uu hariç)
   DON_STRONG_SHORT = 5, // Strong Short TP (close, ll üstüne çıkar)
   DON_WEAK_SHORT   = 6  // Weak Short TP   (close, lu üstüne çıkar; ll hariç)
  };

// Otomatik sıfırlama modu (referans = başlangıç / son sıfırlama bakiyesi)
enum ENUM_DON_RESET_MODE
  {
   DON_RESET_PROFIT = 0, // Kâr hedefi: referans +X olunca kapat
   DON_RESET_LOSS   = 1, // Zarar eşiği: referans -X olunca kapat
   DON_RESET_BOTH   = 2  // Her iki yön: ±X olunca kapat
  };

//+------------------------------------------------------------------+
//| Girdiler                                                         |
//+------------------------------------------------------------------+
input group "1) Donchian Trend Ranges [AlgoAlpha] - birebir Pine ayarları"
input int    InpLength      = 50;    // Length (ta.lowest / ta.highest penceresi)
input double InpMult        = 3.0;   // Range Multiplier
input int    InpCon         = 1;     // con (Pine: basis == basis[con])
input int    InpAtrLength   = 14;    // vol = ta.atr(length)
input int    InpHistoryBars = 3000;  // Taranacak maksimum mum sayısı

input group "2) Sinyal seçimi (açılır menülerden)"
input ENUM_DON_EVENT InpLongEntry  = DON_STRONG_SHORT; // LONG giriş sinyali
input ENUM_DON_EVENT InpShortEntry = DON_STRONG_LONG;  // SHORT giriş sinyali
input ENUM_DON_EVENT InpLongTp     = DON_STRONG_LONG;  // LONG TP sinyali
input ENUM_DON_EVENT InpLongSl     = DON_BEAR_SHIFT;   // LONG SL sinyali
input ENUM_DON_EVENT InpShortTp    = DON_STRONG_SHORT; // SHORT TP sinyali
input ENUM_DON_EVENT InpShortSl    = DON_BULL_SHIFT;   // SHORT SL sinyali
input int  InpTpSignalCount   = 1;      // TP için gereken sinyal sayısı (0 = kapalı)
input int  InpSlSignalCount   = 1;      // SL için gereken sinyal sayısı (0 = kapalı)
input bool InpTpOnlyInProfit  = false;  // TP sinyali yalnızca pozisyon kârdayken uygulanır
input bool InpSlOnlyInLoss    = false;  // SL sinyali yalnızca pozisyon zarardayken uygulanır
input bool InpCloseOppositeOnEntry = false; // Giriş sinyali gelince ters yöndeki pozisyonları kapat

input group "3) Pozisyon ve emir"
input double InpLotSize          = 0.01;      // Lot
input ulong  InpMagicNumber      = 20261109;  // Magic Number
input int    InpDeviationPoints  = 20;        // Maksimum sapma (point)
input int    InpMaxSpreadPoints  = 0;         // Maksimum spread (point) - 0 = kapalı
input int    InpMaxOpenPositions = 0;         // Aynı anda maks. pozisyon - 0 = sınırsız
input bool   InpRequireHedging   = true;      // Hedging hesap zorunlu olsun mu?
input bool   InpAllowLongs       = true;      // LONG pozisyon açılsın
input bool   InpAllowShorts      = true;      // SHORT pozisyon açılsın
input bool   InpReverseTrading   = false;     // TERS İŞLEM: sinyalin tersine işlem aç

input group "4) Sabit güvenlik TP/SL (point, 0 = kapalı)"
input int InpFixedTpPoints = 0; // Sabit TP (point)
input int InpFixedSlPoints = 0; // Sabit SL (point)

input group "5) Para bazlı ve süre bazlı çıkışlar"
input double InpMoneyTakeProfit   = 0.0; // Para TP (hesap birimi, 0 = kapalı)
input double InpMoneyStopLoss     = 0.0; // Para SL (hesap birimi, 0 = kapalı)
input int    InpMaxPositionMinutes = 0;  // Maksimum pozisyon süresi (dakika, 0 = kapalı)

input group "6) Otomatik sıfırlama (hedefe ulaşınca kapat, yeni döngü başlat)"
input bool                 InpAutoResetEnabled = true;             // Otomatik sıfırlama açık
input ENUM_DON_RESET_MODE  InpAutoResetMode    = DON_RESET_PROFIT; // Sıfırlama modu
input double               InpAutoResetLevel   = 3.0;              // Eşik tutarı (0 = kapalı)

input group "7) Görsel ve günlük"
input bool InpDrawArrows     = true;  // Sinyal okları çiz
input bool InpShowPanel      = true;  // Grafikte bilgi paneli göster
input bool InpDeleteOnExit   = true;  // EA kapanırken kendi nesnelerini sil
input bool InpLogSignals     = false; // Her yeni mumda sinyal/seviye logla

//+------------------------------------------------------------------+
//| Global durum                                                     |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES g_tf              = PERIOD_CURRENT;
datetime        g_last_bar_time   = 0;
double          g_don_fbasis      = 0.0;
double          g_don_uu          = 0.0;
double          g_don_ul          = 0.0;
double          g_don_lu          = 0.0;
double          g_don_ll          = 0.0;
bool            g_don_ready       = false;
int             g_last_events     = 0;
datetime        g_last_event_time = 0;
string          g_last_action     = "Başlatılıyor";
string          g_object_prefix   = "";
double          g_reset_reference = 0.0;
bool            g_reset_hold      = false;
int             g_reset_count     = 0;
datetime        g_reset_last_try  = 0;
int             g_signal_count    = 0;
int             g_skip_count      = 0;

//+------------------------------------------------------------------+
//| Yardımcılar                                                      |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES WorkingTimeframe()
  {
   if(g_tf == PERIOD_CURRENT)
      return (ENUM_TIMEFRAMES)Period();
   return g_tf;
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
   // round_direction: +1 yukarı, -1 aşağı, 0 en yakına
   double tick = TickSize();
   if(price <= 0.0 || tick <= 0.0)
      return NormalizeDouble(price, _Digits);
   double units = price / tick;
   if(round_direction > 0)
      units = MathCeil(units - 1.0e-10);
   else
      if(round_direction < 0)
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
      PrintFormat("Lot atlandı: istenen %.8f, broker minimumu %.8f.", requested, min_volume);
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

string EventName(const ENUM_DON_EVENT ev)
  {
   switch(ev)
     {
      case DON_BULL_SHIFT:   return "Bullish Trend Shift";
      case DON_BEAR_SHIFT:   return "Bearish Trend Shift";
      case DON_STRONG_LONG:  return "Strong Long TP";
      case DON_WEAK_LONG:    return "Weak Long TP";
      case DON_STRONG_SHORT: return "Strong Short TP";
      case DON_WEAK_SHORT:   return "Weak Short TP";
      default:               return "yok";
     }
  }

int EventBit(const ENUM_DON_EVENT ev)
  {
   if(ev == DON_EVENT_NONE)
      return 0;
   return (1 << ((int)ev - 1));
  }

bool HasEvent(const int flags, const ENUM_DON_EVENT ev)
  {
   if(ev == DON_EVENT_NONE)
      return false;
   return ((flags & EventBit(ev)) != 0);
  }

string EventFlagsText(const int flags)
  {
   string text = "";
   if(HasEvent(flags, DON_BULL_SHIFT))   text += "BullShift ";
   if(HasEvent(flags, DON_BEAR_SHIFT))   text += "BearShift ";
   if(HasEvent(flags, DON_STRONG_LONG))  text += "StrongLongTP ";
   if(HasEvent(flags, DON_WEAK_LONG))    text += "WeakLongTP ";
   if(HasEvent(flags, DON_STRONG_SHORT)) text += "StrongShortTP ";
   if(HasEvent(flags, DON_WEAK_SHORT))   text += "WeakShortTP ";
   if(text == "")
      text = "yok";
   return text;
  }

//+------------------------------------------------------------------+
//| Donchian Trend Ranges [AlgoAlpha] - Pine birebir hesaplama       |
//|                                                                  |
//| rates kronolojik sıradadır (0 = en eski). events[] her mum için  |
//| olay bit maskesini taşır.                                        |
//+------------------------------------------------------------------+
bool ComputeEvents(const MqlRates &rates[],
                   int &events[],
                   double &last_fbasis,
                   double &last_uu,
                   double &last_ul,
                   double &last_lu,
                   double &last_ll,
                   bool &last_ok)
  {
   last_fbasis = 0.0;
   last_uu     = 0.0;
   last_ul     = 0.0;
   last_lu     = 0.0;
   last_ll     = 0.0;
   last_ok     = false;

   int total = ArraySize(rates);
   if(total < 3)
      return false;
   if(ArrayResize(events, total) < total)
      return false;
   for(int i = 0; i < total; i++)
      events[i] = 0;

   int length  = (int)MathMax(InpLength, 2);
   int atr_len = (int)MathMax(InpAtrLength, 1);
   int con     = (int)MathMax(InpCon, 0);
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
      basis[i] = 0.0;    basis_ok[i]  = false;
      dev[i] = 0.0;      dev_ok[i]    = false;
      tr[i] = 0.0;       vol[i] = 0.0; vol_ok[i] = false;
      fbasis[i] = 0.0;   fbasis_ok[i] = false;
      rangge[i] = 0.0;   rangge_ok[i] = false;
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

   // 2) dev = mult * stdev(close, length, biased=false) -> n-1
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
      dev[i]    = InpMult * MathSqrt(var);
      dev_ok[i] = true;
     }

   // 3) vol = atr(atr_len) -> RMA; ilk değer SMA
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

   // 4) fbasis ve rangge (yapışkan / sticky) - Pine ile birebir
   double fb_value = 0.0;
   bool   fb_valid = false;
   double rg_value = 0.0;
   bool   rg_valid = false;
   for(int i = 0; i < total; i++)
     {
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

   // 6) Olaylar: crossover / crossunder
   for(int i = 1; i < total; i++)
     {
      if(!level_ok[i] || !level_ok[i - 1])
         continue;

      double c  = rates[i].close;
      double cp = rates[i - 1].close;

      bool cross_under_uu = (c < uu[i] && cp >= uu[i - 1]);
      bool cross_over_ll  = (c > ll[i] && cp <= ll[i - 1]);
      bool cross_under_ul = (c < ul[i] && cp >= ul[i - 1]);
      bool cross_over_lu  = (c > lu[i] && cp <= lu[i - 1]);
      bool cross_over_fb  = (c > fbasis[i] && cp <= fbasis[i - 1]);
      bool cross_under_fb = (c < fbasis[i] && cp >= fbasis[i - 1]);

      int flags = 0;
      if(cross_over_fb)
         flags |= EventBit(DON_BULL_SHIFT);
      if(cross_under_fb)
         flags |= EventBit(DON_BEAR_SHIFT);
      if(cross_under_uu)
         flags |= EventBit(DON_STRONG_LONG);
      if(cross_over_ll)
         flags |= EventBit(DON_STRONG_SHORT);
      if(cross_under_ul && !cross_under_uu)
         flags |= EventBit(DON_WEAK_LONG);
      if(cross_over_lu && !cross_over_ll)
         flags |= EventBit(DON_WEAK_SHORT);

      events[i] = flags;
     }

   int panel_index = total - 2; // son kapanmış mum
   if(panel_index >= 0 && level_ok[panel_index])
     {
      last_fbasis = fbasis[panel_index];
      last_uu     = uu[panel_index];
      last_ul     = ul[panel_index];
      last_lu     = lu[panel_index];
      last_ll     = ll[panel_index];
      last_ok     = true;
     }
   return true;
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
      return true; // zaten kapalı
   int side = SideFromPositionType(PositionGetInteger(POSITION_TYPE));
   bool sent = trade.PositionClose(ticket, InpDeviationPoints);
   if(!TradeRetcodeOK(sent))
     {
      PrintFormat("Kapatma başarısız: ticket=%I64u neden=%s retcode=%u (%s)",
                  ticket, reason, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      return false;
     }
   PrintFormat("Pozisyon kapandı: ticket=%I64u side=%s neden=%s",
               ticket, SideName(side), reason);
   g_last_action = StringFormat("%s pozisyon kapatıldı (%s)", SideName(side), reason);
   return true;
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
      if(ArrayResize(tickets, n + 1) == n + 1)
         tickets[n] = ticket;
     }
   for(int i = 0; i < ArraySize(tickets); i++)
      CloseOurPosition(tickets[i], reason);
  }

//+------------------------------------------------------------------+
//| Seçilen sinyallere göre TP / SL sayımı                           |
//+------------------------------------------------------------------+
int EvaluatePositionExit(const ulong ticket,
                         const MqlRates &rates[],
                         const int &events[],
                         string &reason,
                         int &tp_count_out,
                         int &sl_count_out)
  {
   reason       = "";
   tp_count_out = 0;
   sl_count_out = 0;
   if(InpTpSignalCount <= 0 && InpSlSignalCount <= 0)
      return 0;
   if(!SelectOurPosition(ticket))
      return 0;

   int side = SideFromPositionType(PositionGetInteger(POSITION_TYPE));
   if(side == 0)
      return 0;
   datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
   double   profit    = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

   ENUM_DON_EVENT tp_event = (side > 0 ? InpLongTp : InpShortTp);
   ENUM_DON_EVENT sl_event = (side > 0 ? InpLongSl : InpShortSl);

   int period_seconds = PeriodSeconds(g_tf);
   if(period_seconds <= 0)
      period_seconds = 60;

   int total       = ArraySize(rates);
   int event_total = ArraySize(events);
   int last_closed = total - 2; // son index oluşan (canlı) mumdur
   if(last_closed < 1)
      return 0;
   if(event_total < total)
      last_closed = event_total - 2;

   for(int i = 1; i <= last_closed; i++)
     {
      datetime signal_close_time = rates[i].time + period_seconds;
      if(signal_close_time <= open_time)
         continue; // pozisyon açılmadan önce kapanan mumlar sayılmaz

      if(tp_event != DON_EVENT_NONE && HasEvent(events[i], tp_event))
        {
         tp_count_out++;
         if(InpTpSignalCount > 0 && tp_count_out >= InpTpSignalCount)
           {
            if(!InpTpOnlyInProfit || profit >= 0.0)
              {
               reason = StringFormat("TP (%s): %d. sinyal | %s",
                                     EventName(tp_event), tp_count_out,
                                     TimeToString(rates[i].time));
               return 1;
              }
           }
        }

      if(sl_event != DON_EVENT_NONE && HasEvent(events[i], sl_event))
        {
         sl_count_out++;
         if(InpSlSignalCount > 0 && sl_count_out >= InpSlSignalCount)
           {
            if(!InpSlOnlyInLoss || profit < 0.0)
              {
               reason = StringFormat("SL (%s): %d. sinyal | %s",
                                     EventName(sl_event), sl_count_out,
                                     TimeToString(rates[i].time));
               return -1;
              }
           }
        }
     }
   return 0;
  }

void ManageSignalExits(const MqlRates &rates[], const int &events[])
  {
   if(InpTpSignalCount <= 0 && InpSlSignalCount <= 0)
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
      string reason = "";
      int tp_count = 0;
      int sl_count = 0;
      int result = EvaluatePositionExit(tickets[i], rates, events, reason, tp_count, sl_count);
      if(result != 0)
         CloseOurPosition(tickets[i], reason);
     }
  }

//+------------------------------------------------------------------+
//| Para / süre bazlı güvenlik çıkışları (her tick)                  |
//+------------------------------------------------------------------+
void CheckMoneyExits()
  {
   if(InpMoneyTakeProfit <= 0.0 && InpMoneyStopLoss <= 0.0 && InpMaxPositionMinutes <= 0)
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
      datetime open_time    = (datetime)PositionGetInteger(POSITION_TIME);
      long     seconds_open = (long)(now - open_time);
      double   profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);

      if(InpMoneyTakeProfit > 0.0 && profit >= InpMoneyTakeProfit)
        {
         CloseOurPosition(ticket, StringFormat("para TP (%.2f)", profit));
         continue;
        }
      if(InpMoneyStopLoss > 0.0 && profit <= -InpMoneyStopLoss)
        {
         CloseOurPosition(ticket, StringFormat("para SL (%.2f)", profit));
         continue;
        }
      if(InpMaxPositionMinutes > 0 && seconds_open >= (long)InpMaxPositionMinutes * 60)
        {
         CloseOurPosition(ticket, StringFormat("süre sınırı (%d dk)", InpMaxPositionMinutes));
         continue;
        }
     }
  }

//+------------------------------------------------------------------+
//| Otomatik sıfırlama                                               |
//+------------------------------------------------------------------+
string ResetModeName()
  {
   if(InpAutoResetMode == DON_RESET_LOSS)
      return "zarar eşiği";
   if(InpAutoResetMode == DON_RESET_BOTH)
      return "her iki yön";
   return "kâr hedefi";
  }

double FlatReferenceBalance()
  {
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double equity  = AccountInfoDouble(ACCOUNT_EQUITY);
   return (equity > balance ? equity : balance);
  }

bool ResetCondition(const double equity)
  {
   double diff = equity - g_reset_reference;
   if(InpAutoResetMode == DON_RESET_LOSS)
      return (diff <= -InpAutoResetLevel);
   if(InpAutoResetMode == DON_RESET_BOTH)
      return (MathAbs(diff) >= InpAutoResetLevel);
   return (diff >= InpAutoResetLevel);
  }

void CheckAutoReset()
  {
   if(!InpAutoResetEnabled || InpAutoResetLevel <= 0.0)
      return;

   double equity     = AccountInfoDouble(ACCOUNT_EQUITY);
   int    open_count = CountOurPositions(0);

   if(open_count == 0 && !g_reset_hold)
     {
      g_reset_reference = FlatReferenceBalance();
      return;
     }

   if(!ResetCondition(equity))
     {
      if(g_reset_hold)
        {
         g_reset_hold = false;
         if(open_count == 0)
            g_reset_reference = FlatReferenceBalance();
         PrintFormat("Otomatik sıfırlama: hedef aralığa dönüldü. Varlık=%.2f", equity);
        }
      return;
     }

   if(!g_reset_hold)
     {
      g_reset_hold = true;
      g_reset_count++;
      PrintFormat("OTOMATİK SIFIRLAMA #%d: %s | eşik=%.2f referans=%.2f varlık=%.2f fark=%+.2f",
                  g_reset_count, ResetModeName(), InpAutoResetLevel,
                  g_reset_reference, equity, equity - g_reset_reference);
      g_last_action = "Otomatik sıfırlama: pozisyonlar kapatılıyor";
     }

   datetime now = TimeCurrent();
   if(g_reset_hold && g_reset_last_try > 0 && (now - g_reset_last_try) < 2)
      return;
   g_reset_last_try = now;

   CloseAllOurPositions("otomatik sıfırlama");

   if(CountOurPositions(0) == 0)
     {
      g_reset_reference = FlatReferenceBalance();
      g_reset_hold      = false;
      g_last_action = StringFormat("Otomatik sıfırlama #%d tamamlandı (referans %.2f)",
                                   g_reset_count, g_reset_reference);
     }
   else
      g_last_action = "Otomatik sıfırlama: bazı pozisyonlar kapatılamadı, tekrar denenecek";
  }

//+------------------------------------------------------------------+
//| Emir açma                                                        |
//+------------------------------------------------------------------+
void BuildFixedPrices(const int side, const double entry, double &sl, double &tp)
  {
   sl = 0.0;
   tp = 0.0;
   if(side == 0 || entry <= 0.0)
      return;

   long stops_level  = (long)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze_level = (long)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double min_distance = MathMax((double)stops_level, (double)freeze_level) * _Point;

   if(InpFixedTpPoints > 0)
     {
      double distance = MathMax(InpFixedTpPoints * _Point, min_distance + TickSize());
      tp = NormalizePriceToTick(entry + side * distance, (side > 0 ? 1 : -1));
     }
   if(InpFixedSlPoints > 0)
     {
      double distance = MathMax(InpFixedSlPoints * _Point, min_distance + TickSize());
      sl = NormalizePriceToTick(entry - side * distance, (side > 0 ? -1 : 1));
     }
  }

bool OpenTrade(const int side, const datetime signal_time, const string signal_text)
  {
   if(InpMaxOpenPositions > 0 && CountOurPositions(0) >= InpMaxOpenPositions)
     {
      g_skip_count++;
      g_last_action = "Maksimum pozisyon sayısına ulaşıldı";
      return false;
     }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick) || tick.ask <= 0.0 || tick.bid <= 0.0)
      return false;

   double spread_points = (tick.ask - tick.bid) / _Point;
   if(InpMaxSpreadPoints > 0 && spread_points > InpMaxSpreadPoints)
     {
      g_skip_count++;
      g_last_action = StringFormat("Spread yüksek: %.1f point", spread_points);
      return false;
     }

   double volume = NormalizeVolume(InpLotSize);
   if(volume <= 0.0)
     {
      g_last_action = "Lot hacmi broker sınırlarına uymuyor";
      return false;
     }

   double expected_entry = (side > 0 ? tick.ask : tick.bid);
   double fixed_sl = 0.0;
   double fixed_tp = 0.0;
   BuildFixedPrices(side, expected_entry, fixed_sl, fixed_tp);

   string comment = (side > 0 ? "DON BUY" : "DON SELL");
   bool sent = false;
   if(side > 0)
      sent = trade.Buy(volume, _Symbol, 0.0, fixed_sl, fixed_tp, comment);
   else
      sent = trade.Sell(volume, _Symbol, 0.0, fixed_sl, fixed_tp, comment);

   if(!TradeRetcodeOK(sent))
     {
      PrintFormat("Giriş başarısız: %s | yön=%s lot=%.8f retcode=%u (%s)",
                  signal_text, SideName(side), volume,
                  trade.ResultRetcode(), trade.ResultRetcodeDescription());
      g_last_action = "Emir broker tarafından reddedildi";
      return false;
     }

   g_signal_count++;
   PrintFormat("GİRİŞ: %s | yön=%s | sinyal mumu=%s | lot=%.8f | fiyat=%.*f",
               signal_text, SideName(side), TimeToString(signal_time),
               volume, _Digits, expected_entry);
   g_last_action = StringFormat("%s işlem açıldı (%s)", SideName(side), signal_text);
   return true;
  }

//+------------------------------------------------------------------+
//| Grafik nesneleri                                                 |
//+------------------------------------------------------------------+
void DrawSignalArrow(const datetime bar_time, const double high, const double low, const int side)
  {
   if(!InpDrawArrows)
      return;
   string name = g_object_prefix + IntegerToString((long)bar_time);
   if(ObjectFind(0, name) >= 0)
      return;
   double offset = MathMax((high - low) * 0.25, _Point * 20.0);
   if(side > 0)
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
//| Bilgi paneli                                                     |
//+------------------------------------------------------------------+
void UpdatePanel()
  {
   if(!InpShowPanel)
     {
      Comment("");
      return;
     }

   string level_text = (g_don_ready
                        ? StringFormat("fbasis=%s | uu=%s | ul=%s | lu=%s | ll=%s",
                                       DoubleToString(g_don_fbasis, _Digits + 1),
                                       DoubleToString(g_don_uu, _Digits + 1),
                                       DoubleToString(g_don_ul, _Digits + 1),
                                       DoubleToString(g_don_lu, _Digits + 1),
                                       DoubleToString(g_don_ll, _Digits + 1))
                        : "hesaplanıyor (yeterli mum bekleniyor)");

   string reset_text;
   if(!InpAutoResetEnabled || InpAutoResetLevel <= 0.0)
      reset_text = "kapalı";
   else
      reset_text = StringFormat("%s | eşik %.2f | referans %.2f | fark %+.2f | toplam %d",
                                ResetModeName(), InpAutoResetLevel, g_reset_reference,
                                AccountInfoDouble(ACCOUNT_EQUITY) - g_reset_reference,
                                g_reset_count);

   Comment("Donchian Trend Ranges [AlgoAlpha] ROBOT v1.00\n",
           "Sembol: ", _Symbol, " | TF: ", EnumToString(g_tf),
           " | spread: ", DoubleToString((SymbolInfoDouble(_Symbol, SYMBOL_ASK) -
                                          SymbolInfoDouble(_Symbol, SYMBOL_BID)) / _Point, 0), " point\n",
           "Seviyeler: ", level_text, "\n",
           "Son mum olayları: ", EventFlagsText(g_last_events),
           (g_last_event_time > 0 ? " | " + TimeToString(g_last_event_time, TIME_DATE | TIME_MINUTES) : ""), "\n",
           "Giriş: LONG=", EventName(InpLongEntry), " | SHORT=", EventName(InpShortEntry), "\n",
           "LONG  TP=", EventName(InpLongTp), "  SL=", EventName(InpLongSl),
           " (", IntegerToString(InpTpSignalCount), "/", IntegerToString(InpSlSignalCount), " sinyal)\n",
           "SHORT TP=", EventName(InpShortTp), "  SL=", EventName(InpShortSl),
           " (", IntegerToString(InpTpSignalCount), "/", IntegerToString(InpSlSignalCount), " sinyal)\n",
           "Açık pozisyon BUY/SELL: ", IntegerToString(CountOurPositions(1)), " / ",
           IntegerToString(CountOurPositions(-1)),
           " | toplam sinyal: ", IntegerToString(g_signal_count),
           " | atlanan: ", IntegerToString(g_skip_count), "\n",
           "Otomatik sıfırlama: ", reset_text, "\n",
           "Durum: ", g_last_action);
  }

//+------------------------------------------------------------------+
//| Kapanmış mum işleme                                              |
//+------------------------------------------------------------------+
void ProcessClosedBar()
  {
   MqlRates rates[];
   ArraySetAsSeries(rates, false);
   int needed = (int)MathMax(InpHistoryBars, InpLength + (int)MathMax(InpCon, 0) + 20);
   int copied = CopyRates(_Symbol, g_tf, 0, needed, rates);
   if(copied > 0)
      ArrayResize(rates, copied);

   int min_bars = (int)MathMax(InpLength + (int)MathMax(InpCon, 0) + 5, InpAtrLength + 5);
   if(copied < min_bars)
     {
      g_last_action = StringFormat("Yetersiz mum verisi: %d/%d", copied, min_bars);
      return;
     }

   int last_closed = copied - 2; // son index oluşan (canlı) mumdur
   if(last_closed < 1)
     {
      g_last_action = "Yeterli kapalı mum yok";
      return;
     }

   int events[];
   double fb = 0.0, uu = 0.0, ul = 0.0, lu = 0.0, ll = 0.0;
   bool   ok = false;
   if(!ComputeEvents(rates, events, fb, uu, ul, lu, ll, ok) || !ok)
     {
      g_last_action = "Donchian seviyeleri için yeterli veri yok";
      return;
     }
   if(last_closed >= ArraySize(events))
     {
      g_last_action = "Olay dizisi tutarsız";
      return;
     }

   g_don_fbasis = fb;
   g_don_uu     = uu;
   g_don_ul     = ul;
   g_don_lu     = lu;
   g_don_ll     = ll;
   g_don_ready  = true;

   int bar_events = events[last_closed];
   g_last_events     = bar_events;
   g_last_event_time = rates[last_closed].time;

   if(InpLogSignals)
      PrintFormat("Donchian[%s] fbasis=%.*f uu=%.*f ul=%.*f lu=%.*f ll=%.*f | olaylar: %s",
                  TimeToString(rates[last_closed].time, TIME_DATE | TIME_MINUTES),
                  _Digits + 1, fb, _Digits + 1, uu, _Digits + 1, ul,
                  _Digits + 1, lu, _Digits + 1, ll, EventFlagsText(bar_events));

   // 1) Önce mevcut pozisyonların seçili sinyallere göre çıkışları
   ManageSignalExits(rates, events);

   // 2) Bu mumun giriş sinyalleri
   int raw = 0;
   if(HasEvent(bar_events, InpLongEntry))
      raw = 1;
   else
      if(HasEvent(bar_events, InpShortEntry))
         raw = -1;

   if(raw == 0)
     {
      if(!InpLogSignals)
         g_last_action = "Yeni giriş sinyali yok";
      return;
     }

   int signal_side = (InpReverseTrading ? -raw : raw);
   if(signal_side > 0 && !InpAllowLongs)
     {
      g_last_action = "LONG giriş ayarlardan kapalı";
      return;
     }
   if(signal_side < 0 && !InpAllowShorts)
     {
      g_last_action = "SHORT giriş ayarlardan kapalı";
      return;
     }

   string signal_text = (raw > 0 ? EventName(InpLongEntry) + " -> LONG"
                                 : EventName(InpShortEntry) + " -> SHORT");
   if(InpReverseTrading)
      signal_text = signal_text + " (ters)";

   DrawSignalArrow(rates[last_closed].time, rates[last_closed].high,
                   rates[last_closed].low, signal_side);

   // 3) Opsiyonel: ters yöndeki pozisyonları kapat
   if(InpCloseOppositeOnEntry)
     {
      int opposite = -signal_side;
      ulong to_close[];
      ArrayResize(to_close, 0);
      for(int i = PositionsTotal() - 1; i >= 0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !SelectOurPosition(ticket))
            continue;
         if(SideFromPositionType(PositionGetInteger(POSITION_TYPE)) != opposite)
            continue;
         int n = ArraySize(to_close);
         if(ArrayResize(to_close, n + 1) == n + 1)
            to_close[n] = ticket;
        }
      for(int i = 0; i < ArraySize(to_close); i++)
         CloseOurPosition(to_close[i], "ters giriş sinyali");
     }

   OpenTrade(signal_side, rates[last_closed].time, signal_text);
  }

void CheckNewBar()
  {
   datetime current_bar_time = iTime(_Symbol, g_tf, 0);
   if(current_bar_time <= 0)
      return;
   if(g_last_bar_time == 0)
     {
      // EA açıldığında geçmiş sinyalden geriye dönük işlem açılmaz.
      g_last_bar_time = current_bar_time;
      return;
     }
   if(current_bar_time == g_last_bar_time)
      return;
   g_last_bar_time = current_bar_time;
   ProcessClosedBar();
  }

//+------------------------------------------------------------------+
//| Standart olaylar                                                 |
//+------------------------------------------------------------------+
int OnInit()
  {
   g_tf = WorkingTimeframe();
   if(PeriodSeconds(g_tf) <= 0)
     {
      Print("EA başlatılamadı: geçersiz zaman dilimi.");
      return INIT_FAILED;
     }
   if(InpLength < 2 || InpAtrLength < 1 || InpCon < 0 ||
      InpMult <= 0.0 || !MathIsValidNumber(InpMult))
     {
      Print("Hatalı girdiler: Length >= 2, ATR Length >= 1, con >= 0, Range Multiplier > 0 olmalı.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpHistoryBars < 100 || InpLotSize <= 0.0 || !MathIsValidNumber(InpLotSize))
     {
      Print("Hatalı girdiler: geçmiş mum sayısı en az 100, lot > 0 olmalı.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpTpSignalCount < 0 || InpSlSignalCount < 0 ||
      InpFixedTpPoints < 0 || InpFixedSlPoints < 0 ||
      InpDeviationPoints < 0 || InpMaxSpreadPoints < 0 ||
      InpMaxOpenPositions < 0 || InpMaxPositionMinutes < 0)
     {
      Print("Hatalı girdiler: sinyal sayıları ve emir ayarları negatif olamaz.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpMoneyTakeProfit < 0.0 || InpMoneyStopLoss < 0.0 ||
      InpAutoResetLevel < 0.0 || !MathIsValidNumber(InpMoneyTakeProfit) ||
      !MathIsValidNumber(InpMoneyStopLoss) || !MathIsValidNumber(InpAutoResetLevel))
     {
      Print("Hatalı girdiler: para bazlı çıkış ve sıfırlama eşikleri negatif olamaz (0 = kapalı).");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpLongEntry == DON_EVENT_NONE && InpShortEntry == DON_EVENT_NONE)
     {
      Print("Hatalı girdiler: en az bir giriş sinyali (LONG veya SHORT) seçilmeli.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpLongEntry != DON_EVENT_NONE && InpLongEntry == InpShortEntry)
      Print("BİLGİ: LONG ve SHORT giriş sinyali aynı seçilmiş. Aynı mumda iki olay oluşursa LONG önceliklidir.");
   if(InpLongTp != DON_EVENT_NONE && InpLongTp == InpLongSl)
      Print("UYARI: LONG TP ve LONG SL sinyali aynı; aynı mumda TP öncelikli olur.");
   if(InpShortTp != DON_EVENT_NONE && InpShortTp == InpShortSl)
      Print("UYARI: SHORT TP ve SHORT SL sinyali aynı; aynı mumda TP öncelikli olur.");
   if(InpTpSignalCount <= 0 && InpSlSignalCount <= 0 &&
      InpFixedTpPoints <= 0 && InpFixedSlPoints <= 0 &&
      InpMoneyTakeProfit <= 0.0 && InpMoneyStopLoss <= 0.0 &&
      InpMaxPositionMinutes <= 0)
      Print("UYARI: hiçbir çıkış kuralı tanımlı değil; pozisyonlar yalnızca elle kapatılabilir.");

   if(InpRequireHedging &&
      AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      Print("EA başlatılamadı: her pozisyon için ayrı TP/SL sayımı gerekir; hedging hesap gerekli. ",
            "Netting hesapta kullanmak isterseniz InpRequireHedging=false yapın.");
      return INIT_FAILED;
     }
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("UYARI: Hesap hedging değil. Aynı sembolde pozisyonlar netleşebilir; ",
            "sayım tek net pozisyon üzerinden yapılır.");

   if(!SymbolSelect(_Symbol, true))
     {
      Print("EA başlatılamadı: sembol seçilemiyor.");
      return INIT_FAILED;
     }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetAsyncMode(false);
   trade.SetTypeFillingBySymbol(_Symbol);

   g_object_prefix = StringFormat("DON_%I64u_%s_%s_",
                                  InpMagicNumber, _Symbol, EnumToString(g_tf));
   g_last_bar_time   = iTime(_Symbol, g_tf, 0);
   g_reset_reference = FlatReferenceBalance();
   g_reset_hold      = false;

   EventSetTimer(1);

   PrintFormat("Donchian ROBOT hazır: %s TF=%s | length=%d mult=%.2f con=%d atr=%d | lot=%.2f | magic=%I64u",
               _Symbol, EnumToString(g_tf), InpLength, InpMult, InpCon, InpAtrLength,
               InpLotSize, InpMagicNumber);
   PrintFormat("Eşleme: LONG giriş=%s | SHORT giriş=%s | LONG TP=%s / SL=%s | SHORT TP=%s / SL=%s | TP %d / SL %d sinyal",
               EventName(InpLongEntry), EventName(InpShortEntry),
               EventName(InpLongTp), EventName(InpLongSl),
               EventName(InpShortTp), EventName(InpShortSl),
               InpTpSignalCount, InpSlSignalCount);
   Print("Sinyaller yalnızca KAPANMIŞ mumlarda değerlendirilir. Açılışta geçmişe dönük işlem açılmaz.");

   UpdatePanel();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(InpDeleteOnExit)
      DeleteOwnObjects();
   Comment("");
  }

void OnTick()
  {
   CheckAutoReset();
   CheckNewBar();
   CheckMoneyExits();
   UpdatePanel();
  }

void OnTimer()
  {
   CheckAutoReset();
   CheckNewBar();
   CheckMoneyExits();
   UpdatePanel();
  }

double OnTester()
  {
   // Strategy Tester optimizasyonunda net kârı sırala.
   return TesterStatistics(STAT_PROFIT);
  }
//+------------------------------------------------------------------+

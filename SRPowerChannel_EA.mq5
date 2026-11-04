//+------------------------------------------------------------------+
//|  SRPowerChannel_EA.mq5                                           |
//|  Support and Resistance Power Channel [ChartPrime] -> MT5 EA     |
//|                                                                  |
//|  GÖSTERGE MATEMATİĞİ (Pine koduyla BİREBİR):                     |
//|   max  = highest(high, length)        (son length mum)           |
//|   min  = lowest(low, length)          (son length mum)           |
//|   mid  = (max + min) / 2                                         |
//|   atr  = ta.atr(200) * 0.5            (RMA tabanlı ATR)          |
//|   top  = min + atr   -> d.sup_area.get_top()                     |
//|   bot  = max - atr   -> d.res_area.get_bottom()                  |
//|                                                                  |
//|  SİNYAL KURALLARI (yalnızca KAPANMIŞ mumlar):                    |
//|   * BUY  : low[i]  > top  ve  low[i+1]  <= top                   |
//|            (fiyat destek bandının üstüne geri döndü)             |
//|   * SELL : high[i] < bot  ve  high[i+1] >= bot                   |
//|            (fiyat direnç bandının altına indi)                   |
//|   * low_1/high_1 = mum i (yeni), low_2/high_2 = i+1 (eski)       |
//|   * Pine aynı mumda iki işaret de çizebilir;                     |
//|     işlemde BUY önceliklidir.                                    |
//|   * Pine işaretleri son mumda tarar. EA sinyali mum              |
//|     kapanışında üretir (repaint yok, gecikme yok).               |
//|                                                                  |
//|  ÇIKIŞ KURALLARI (pozisyon yönüne göre sayılır):                 |
//|   * BUY  : TP = girişten YUKARIDA gelen 2. BUY sinyali           |
//|            SL = girişten AŞAĞIDA gelen 2. SELL sinyali           |
//|   * SELL : TP = girişten AŞAĞIDA gelen 2. SELL sinyali           |
//|            SL = girişten YUKARIDA gelen 2. BUY sinyali           |
//|     (Sayılar ayarlardan değiştirilebilir; 0 = kapalı.)           |
//|                                                                  |
//|  TERS İŞLEM (InpReverseTrading = true):                          |
//|   * BUY sinyali -> SELL pozisyon, SELL sinyali -> BUY.           |
//|                                                                  |
//|  OTOMATİK SIFIRLAMA:                                             |
//|   * Referans = robotun başladığı andaki bakiye. Varlık           |
//|     referans + eşik olunca tüm pozisyonlar kapatılır ve          |
//|     YENİ döngü başlar (işlemeye hemen devam eder).               |
//|   * Mod: sadece kâr (+), sadece zarar (-) veya iki yön.          |
//|   * Eşik tutarı ve mod girdilerden değiştirilebilir.             |
//|                                                                  |
//|  POZİSYON DENGELEME (long/short farkı):                          |
//|   * İki yöndeki pozisyon farkı en fazla "maksimum fark"          |
//|     (varsayılan 2) olabilir.                                     |
//|   * Sinyal geride kalan yöndeyse, farkı kapatacak kadar          |
//|     çok pozisyon açılır (7L/5S + SHORT = 2 short).               |
//|   * Sinyal öndeki yöndeyse ve fark limitteyse açılmaz.           |
//|                                                                  |
//|  NOT: TP/SL sinyal sayımıyla çalıştığı için bunlar sabit         |
//|  fiyat emri olarak brokera gönderilmez; sayım dolunca EA         |
//|  pozisyonu piyasadan kapatır. EA açık kalmalı.                   |
//+------------------------------------------------------------------+
#property copyright "S&R Power Channel [ChartPrime] - MT5 EA"
#property version   "1.00"
#property strict
#property description "Support and Resistance Power Channel [ChartPrime] ile otomatik al/sat"
#property description "Kanal matematiği Pine koduyla birebir: highest/lowest(length) + ta.atr(200)*0.5"
#property description "Otomatik sıfırlama: kâr/zarar hedefine ulaşınca kapatıp yeni döngü başlatır"
#property description "Pozisyon dengeleme: long/short farkını istenen aralıkta tutar"
#property description "Çıkışlar: girişe göre uygun yöndeki 2. sinyal TP, ters yöndeki 2. sinyal SL"

#include <Trade/Trade.mqh>

CTrade trade;

//+------------------------------------------------------------------+
//| Tipler                                                           |
//+------------------------------------------------------------------+
// Otomatik sıfırlama tetikleme modu (referans = başlangıç/son sıfırlama bakiyesi)
enum ENUM_SRC_RESET_MODE
  {
   SRC_RESET_PROFIT = 0, // Kâr hedefi: referans +X kâr olunca (+3$)
   SRC_RESET_LOSS   = 1, // Zarar eşiği: referans -X zarar olunca (-3$)
   SRC_RESET_BOTH   = 2  // Her iki yön: ±X olunca
  };

//+------------------------------------------------------------------+
//| Giriş parametreleri                                              |
//+------------------------------------------------------------------+
input group "1) S&R Power Channel ayarları (Pine ile birebir)"
input ENUM_TIMEFRAMES InpTimeframe       = PERIOD_CURRENT; // İşlem zaman dilimi (PERIOD_CURRENT = grafik TF)
input int             InpLength          = 130;            // length: max/min penceresi (mum)
input int             InpAtrLength       = 200;            // ta.atr uzunluğu (Pine kodunda sabit 200)
input double          InpAtrMultiplier   = 0.5;            // ta.atr çarpanı (Pine kodunda sabit 0.5)
input int             InpExtend          = 30;             // extend: kanalın sağa uzatılması (sadece görsel)
input int             InpHistoryBars     = 5000;           // Taranacak maksimum mum sayısı (sinyal + çıkış sayımı)
input bool            InpLogIndicator    = false;          // Her yeni mumda kanal seviyelerini logla

input group "2) Sinyal ve ters işlem"
input bool            InpReverseTrading     = false; // TERS İŞLEM: true = BUY sinyali SELL, SELL sinyali BUY açar
input bool            InpOpenOnBuySignal    = true;  // BUY sinyalinde işlem aç
input bool            InpOpenOnSellSignal   = true;  // SELL sinyalinde işlem aç
input bool            InpAllowLongTrades    = true;  // BUY pozisyon açmaya izin ver
input bool            InpAllowShortTrades   = true;  // SELL pozisyon açmaya izin ver
input bool            InpDrawSignalArrows   = true;  // Grafikte sinyal okları çiz
input bool            InpShowChartInfo      = true;  // Grafikte bilgi paneli göster

input group "3) Çıkışlar - sinyal sayımı (0 = o çıkış kapalı)"
input int             InpTakeProfitSignalCount = 2;  // TP: girişle aynı yöndeki kaçıncı sinyalde kapat?
input int             InpStopLossSignalCount   = 2;  // SL: girişle ters yöndeki kaçıncı sinyalde kapat?
input int             InpFixedTakeProfitPoints = 0;  // Ekstra sabit TP (point) - 0 = kapalı
input int             InpFixedStopLossPoints   = 0;  // Ekstra sabit SL (point) - 0 = kapalı

input group "4) Pozisyon ve emir"
input double          InpLotSize              = 0.01;      // Lot
input ulong           InpMagicNumber          = 20261021;  // Magic Number
input int             InpDeviationPoints      = 20;        // Maksimum sapma (point)
input int             InpMaxSpreadPoints      = 0;         // Maksimum spread (point) - 0 = kapalı
input int             InpMaxOpenPositions     = 0;         // Aynı anda maks. pozisyon - 0 = sınırsız
input bool            InpRequireHedgingAccount = true;     // Hedging hesap zorunlu olsun mu?
input bool            InpDeleteArrowsOnExit   = true;      // EA kapanırken çizimleri sil

input group "5) Otomatik sıfırlama (kâr hedefinde kapat, yeni döngü başlat)"
input bool                InpAutoResetEnabled = true;             // Otomatik sıfırlama açık
input ENUM_SRC_RESET_MODE InpAutoResetMode    = SRC_RESET_PROFIT; // Sıfırlama modu (referans = başlangıç bakiyesi)
input double              InpAutoResetLevel   = 3.0;              // Eşik tutarı (hesap para birimi, örn. 3 = 3$) - 0 = kapalı

input group "6) Pozisyon dengeleme (long/short farkı)"
input bool            InpBalanceEnabled  = true;                 // Dengeleme açık (kapalıysa her sinyal 1 pozisyon)
input int             InpBalanceMaxGap   = 2;                    // İki yöndeki maksimum pozisyon farkı (min 1)
input int             InpBalanceMaxBatch = 0;                    // Tek sinyalde en fazla kaç telafi pozisyonu - 0 = sınırsız

input group "7) Görsel ayarlar (Pine ile aynı görünüm)"
input bool            InpDrawChannel    = true;        // Kanal çizgilerini ve bantlarını çiz
input bool            InpDrawLabels     = true;        // max / min / orta etiketlerini çiz
input color           InpTopColor       = clrFuchsia;  // Top (direnç bandı) rengi
input color           InpBottomColor    = clrLime;     // Bottom (destek bandı) rengi

//+------------------------------------------------------------------+
//| Global durum                                                     |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES g_timeframe           = PERIOD_CURRENT;
datetime        g_last_bar_time       = 0;
int             g_last_raw_signal     = 0;      // +1 BUY sinyali, -1 SELL sinyali
datetime        g_last_signal_time    = 0;
double          g_last_signal_price   = 0.0;
double          g_chan_max            = 0.0;    // highest(high, length)
double          g_chan_min            = 0.0;    // lowest(low, length)
double          g_chan_mid            = 0.0;    // (max + min) / 2
double          g_atr_half            = 0.0;    // ta.atr(200) * 0.5
double          g_chan_top            = 0.0;    // min + atr_half  (destek bandı üst kenarı)
double          g_chan_bot            = 0.0;    // max - atr_half  (direnç bandı alt kenarı)
int             g_buy_power           = 0;      // son length mumda close > open sayısı
int             g_sell_power          = 0;      // son length mumda close < open sayısı
string          g_last_action         = "Başlatılıyor";
string          g_object_prefix       = "";
double          g_reset_start_balance = 0.0; // Referans bakiye (robot başlangıcı / son sıfırlama)
bool            g_reset_hold          = false; // Sıfırlama işlemi sürüyor (tekrar tetikleme koruması)
int             g_reset_count         = 0;     // Toplam otomatik sıfırlama sayısı
int             g_balance_fill_count  = 0;     // Dengeleme ile açılan ek pozisyon sayısı
int             g_balance_skip_count  = 0;     // Fark limiti nedeniyle atlanan sinyal sayısı
datetime        g_reset_last_try      = 0;     // Son kapatma denemesi (log spam'i önlenir)

//+------------------------------------------------------------------+
//| Kanal hesaplamaları (Pine ile birebir)                           |
//+------------------------------------------------------------------+
// Pine: ta.atr(length) = ta.rma(ta.tr(true), length)
//   tr  = max(high-low, |high-close[1]|, |low-close[1]|)
//   rma = SMA ile tohumlanır, sonra rma[i] = rma[i-1] + (tr-rma[i-1])/len
bool ComputeAtrSeries(const MqlRates &rates[], const int period, double &atr[])
  {
   int total = ArraySize(rates);
   if(total <= 0 || period < 1)
      return false;
   if(ArrayResize(atr, total) < total)
      return false;

   double tr[];
   if(ArrayResize(tr, total) < total)
      return false;

   for(int i = 0; i < total; i++)
     {
      double hl = rates[i].high - rates[i].low;
      if(i == 0)
        {
         tr[i] = hl; // Pine: ilk mumda tr = high - low
         continue;
        }
      double prev_close = rates[i - 1].close;
      tr[i] = MathMax(hl, MathMax(MathAbs(rates[i].high - prev_close),
                                  MathAbs(rates[i].low  - prev_close)));
     }

   int seed_end = period - 1;
   for(int i = 0; i < total; i++)
     {
      if(i < seed_end)
        {
         atr[i] = 0.0; // yetersiz veri
         continue;
        }
      if(i == seed_end)
        {
         double sum = 0.0;
         for(int j = 0; j <= seed_end; j++)
            sum += tr[j];
         atr[i] = sum / period;
         continue;
        }
      atr[i] = atr[i - 1] + (tr[i] - atr[i - 1]) / period;
     }
   return true;
  }

// Pine max_min(): highest high / lowest low, son "length" mum.
// Pine bantları:
//   d.res_area = box(top = max+atr, bottom = max-atr)  -> bot = max-atr
//   d.sup_area = box(top = min+atr, bottom = min-atr)  -> top = min+atr
bool BuildChannel(const MqlRates &rates[], const double &atr[],
                  double &chan_high[], double &chan_low[],
                  double &chan_top[], double &chan_bot[],
                  bool &chan_ready[])
  {
   int total = ArraySize(rates);
   if(total <= 0 || ArraySize(atr) < total)
      return false;
   if(ArrayResize(chan_high, total) < total ||
      ArrayResize(chan_low,  total) < total ||
      ArrayResize(chan_top,  total) < total ||
      ArrayResize(chan_bot,  total) < total ||
      ArrayResize(chan_ready, total) < total)
      return false;

   for(int i = 0; i < total; i++)
     {
      chan_high[i]  = 0.0;
      chan_low[i]   = 0.0;
      chan_top[i]   = 0.0;
      chan_bot[i]   = 0.0;
      chan_ready[i] = false;
     }

   for(int i = InpLength - 1; i < total; i++)
     {
      double mx = rates[i].high;
      double mn = rates[i].low;
      for(int j = i - InpLength + 1; j <= i; j++)
        {
         if(rates[j].high > mx)
            mx = rates[j].high;
         if(rates[j].low < mn)
            mn = rates[j].low;
        }
      double half = InpAtrMultiplier * atr[i];
      chan_high[i]  = mx;
      chan_low[i]   = mn;
      chan_top[i]   = mn + half;
      chan_bot[i]   = mx - half;
      chan_ready[i] = (atr[i] > 0.0);
     }
   return true;
  }

// Pine signals():
//   low_1 = low[i],  low_2 = low[i+1]   (i = yeni mum)
//   if low_1 > top and low_2 <= top  -> BUY
//   if high_1 < bot and high_2 >= bot -> SELL
// Aynı mumda iki koşul da oluşabilir; işlemde BUY önceliklidir.
int ChannelSignalAt(const MqlRates &rates[], const double &chan_top[],
                    const double &chan_bot[], const bool &chan_ready[],
                    const int index)
  {
   int total = ArraySize(rates);
   if(index < 1 || index >= total)
      return 0;
   if(index >= ArraySize(chan_top) || index >= ArraySize(chan_bot) ||
      index >= ArraySize(chan_ready))
      return 0;
   if(!chan_ready[index] || chan_top[index] <= 0.0 || chan_bot[index] <= 0.0)
      return 0;

   double low_1  = rates[index].low;
   double low_2  = rates[index - 1].low;
   double high_1 = rates[index].high;
   double high_2 = rates[index - 1].high;

   if(low_1 > chan_top[index] && low_2 <= chan_top[index])
      return 1;  // BUY
   if(high_1 < chan_bot[index] && high_2 >= chan_bot[index])
      return -1; // SELL
   return 0;
  }

// Pine power(): son "length" mumda close>open ve close<open sayıları.
void ComputePower(const MqlRates &rates[], const int index, int &buy_power, int &sell_power)
  {
   buy_power  = 0;
   sell_power = 0;
   if(index < InpLength - 1)
      return;
   for(int j = index - InpLength + 1; j <= index; j++)
     {
      if(rates[j].close > rates[j].open)
         buy_power++;
      else if(rates[j].close < rates[j].open)
         sell_power++;
     }
  }

string SignalName(const int signal)
  {
   if(signal > 0)
      return "BUY sinyali (destek bandı üstüne dönüş)";
   if(signal < 0)
      return "SELL sinyali (direnç bandı altına iniş)";
   return "sinyal yok";
  }

//+------------------------------------------------------------------+
//| Kanal çizimi (Pine görünümü)                                     |
//+------------------------------------------------------------------+
void DrawChannel(const MqlRates &rates[], const int index)
  {
   string p = g_object_prefix + "CH_";
   ObjectDelete(0, p + "top_line");
   ObjectDelete(0, p + "bot_line");
   ObjectDelete(0, p + "res_box");
   ObjectDelete(0, p + "sup_box");
   ObjectDelete(0, p + "lbl_max");
   ObjectDelete(0, p + "lbl_min");
   ObjectDelete(0, p + "lbl_mid");
   if(!InpDrawChannel)
      return;

   int left_index = index - InpLength + 1;
   if(left_index < 0)
      left_index = 0;
   datetime t_left = rates[left_index].time;
   int period_seconds = PeriodSeconds(g_timeframe);
   if(period_seconds <= 0)
      period_seconds = 60;
   datetime t_right  = rates[index].time + (long)InpExtend * period_seconds;
   datetime t_far    = rates[index].time + (long)(InpExtend + 30) * period_seconds;

   double upper_line = g_chan_max + g_atr_half; // Pine: line ... max+atr (t_col)
   double lower_line = g_chan_min - g_atr_half; // Pine: line ... min-atr (b_col)

   if(ObjectCreate(0, p + "top_line", OBJ_TREND, 0, t_left, upper_line, t_far, upper_line))
     {
      ObjectSetInteger(0, p + "top_line", OBJPROP_COLOR, InpTopColor);
      ObjectSetInteger(0, p + "top_line", OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, p + "top_line", OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, p + "top_line", OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, p + "top_line", OBJPROP_HIDDEN, true);
     }
   if(ObjectCreate(0, p + "bot_line", OBJ_TREND, 0, t_left, lower_line, t_far, lower_line))
     {
      ObjectSetInteger(0, p + "bot_line", OBJPROP_COLOR, InpBottomColor);
      ObjectSetInteger(0, p + "bot_line", OBJPROP_WIDTH, 1);
      ObjectSetInteger(0, p + "bot_line", OBJPROP_RAY_RIGHT, false);
      ObjectSetInteger(0, p + "bot_line", OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, p + "bot_line", OBJPROP_HIDDEN, true);
     }

   // Direnç bandı: max ± atr
   if(ObjectCreate(0, p + "res_box", OBJ_RECTANGLE, 0,
                   t_left, g_chan_max + g_atr_half, t_right, g_chan_max - g_atr_half))
     {
      ObjectSetInteger(0, p + "res_box", OBJPROP_COLOR, InpTopColor);
      ObjectSetInteger(0, p + "res_box", OBJPROP_BGCOLOR, ColorToARGB(InpTopColor, 46));
      ObjectSetInteger(0, p + "res_box", OBJPROP_FILL, true);
      ObjectSetInteger(0, p + "res_box", OBJPROP_BACK, true);
      ObjectSetInteger(0, p + "res_box", OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, p + "res_box", OBJPROP_HIDDEN, true);
     }
   // Destek bandı: min ± atr
   if(ObjectCreate(0, p + "sup_box", OBJ_RECTANGLE, 0,
                   t_left, g_chan_min + g_atr_half, t_right, g_chan_min - g_atr_half))
     {
      ObjectSetInteger(0, p + "sup_box", OBJPROP_COLOR, InpBottomColor);
      ObjectSetInteger(0, p + "sup_box", OBJPROP_BGCOLOR, ColorToARGB(InpBottomColor, 46));
      ObjectSetInteger(0, p + "sup_box", OBJPROP_FILL, true);
      ObjectSetInteger(0, p + "sup_box", OBJPROP_BACK, true);
      ObjectSetInteger(0, p + "sup_box", OBJPROP_SELECTABLE, false);
      ObjectSetInteger(0, p + "sup_box", OBJPROP_HIDDEN, true);
     }

   if(InpDrawLabels)
     {
      if(ObjectCreate(0, p + "lbl_max", OBJ_TEXT, 0, t_right, g_chan_max))
        {
         ObjectSetString(0, p + "lbl_max", OBJPROP_TEXT, StringFormat("MAX %.2f", g_chan_max));
         ObjectSetInteger(0, p + "lbl_max", OBJPROP_COLOR, InpTopColor);
         ObjectSetInteger(0, p + "lbl_max", OBJPROP_ANCHOR, ANCHOR_LEFT);
         ObjectSetInteger(0, p + "lbl_max", OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, p + "lbl_max", OBJPROP_HIDDEN, true);
        }
      if(ObjectCreate(0, p + "lbl_min", OBJ_TEXT, 0, t_right, g_chan_min))
        {
         ObjectSetString(0, p + "lbl_min", OBJPROP_TEXT, StringFormat("MIN %.2f", g_chan_min));
         ObjectSetInteger(0, p + "lbl_min", OBJPROP_COLOR, InpBottomColor);
         ObjectSetInteger(0, p + "lbl_min", OBJPROP_ANCHOR, ANCHOR_LEFT);
         ObjectSetInteger(0, p + "lbl_min", OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, p + "lbl_min", OBJPROP_HIDDEN, true);
        }
      if(ObjectCreate(0, p + "lbl_mid", OBJ_TEXT, 0, t_right, g_chan_mid))
        {
         ObjectSetString(0, p + "lbl_mid", OBJPROP_TEXT, StringFormat("MID %.2f", g_chan_mid));
         ObjectSetInteger(0, p + "lbl_mid", OBJPROP_COLOR, clrGray);
         ObjectSetInteger(0, p + "lbl_mid", OBJPROP_ANCHOR, ANCHOR_LEFT);
         ObjectSetInteger(0, p + "lbl_mid", OBJPROP_SELECTABLE, false);
         ObjectSetInteger(0, p + "lbl_mid", OBJPROP_HIDDEN, true);
        }
     }
   ChartRedraw();
  }

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

int LoadRates(MqlRates &rates[])
  {
   int needed = (int)MathMax(InpHistoryBars, ((int)MathMax(InpAtrLength, InpLength) * 4) + 10);
   ArraySetAsSeries(rates, false); // 0 = en eski mum
   int copied = CopyRates(_Symbol, g_timeframe, 0, needed, rates);
   if(copied > 0)
      ArrayResize(rates, copied);
   return copied;
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
string ResetModeName(const ENUM_SRC_RESET_MODE mode)
  {
   if(mode == SRC_RESET_LOSS)
      return "zarar eşiği";
   if(mode == SRC_RESET_BOTH)
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
   if(InpAutoResetMode == SRC_RESET_LOSS)
      return (diff <= -InpAutoResetLevel);
   if(InpAutoResetMode == SRC_RESET_BOTH)
      return (MathAbs(diff) >= InpAutoResetLevel);
   return (diff >= InpAutoResetLevel); // SRC_RESET_PROFIT
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
//| Sinyalde pozisyon açma                                           |
//+------------------------------------------------------------------+
bool BuildFixedExits(const int side, const double entry, double &sl, double &tp)
  {
   sl = 0.0;
   tp = 0.0;
   long stops_level  = (long)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze_level = (long)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double min_distance = MathMax(stops_level, freeze_level) * _Point;

   if(InpFixedTakeProfitPoints > 0)
     {
      double distance = MathMax(InpFixedTakeProfitPoints * _Point, min_distance + TickSize());
      tp = NormalizePriceToTick(entry + side * distance, (side > 0 ? 1 : -1));
     }
   if(InpFixedStopLossPoints > 0)
     {
      double distance = MathMax(InpFixedStopLossPoints * _Point, min_distance + TickSize());
      sl = NormalizePriceToTick(entry - side * distance, (side > 0 ? -1 : 1));
     }
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
                  const double signal_price, const int index, const int total)
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

   double volume = NormalizeVolume(InpLotSize);
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

   string comment = (trade_side > 0 ? "SRPC BUY" : "SRPC SELL");
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

   PrintFormat("Giriş: %s | işlem=%s%s | sinyal mumu=%s sinyal fiyatı=%.*f | lot=%.8f",
               SignalName(raw_signal), SideName(trade_side),
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

   // Dengeleme: bu sinyalde kaç pozisyon açılacağı (0 = atla).
   string note = "";
   int count = PositionsToOpen(trade_side, note);
   if(count <= 0)
     {
      g_balance_skip_count++;
      PrintFormat("Sinyal atlandı (dengeleme): %s | %s", SignalName(raw_signal), note);
      g_last_action = StringFormat("%s sinyali atlandı: %s",
                                   SideName(trade_side), (note == "" ? "fark limiti" : note));
      return false;
     }

   int opened = 0;
   for(int i = 1; i <= count; i++)
     {
      if(!OpenOneTrade(trade_side, raw_signal, signal_bar_time, signal_price, i, count))
         break;
      opened++;
     }

   if(opened > 0 && count > 1)
     {
      g_balance_fill_count += (opened - 1);
      PrintFormat("Dengeleme: %s | tek sinyalde %d pozisyon açıldı", note, opened);
      g_last_action = StringFormat("Dengeleme: %s -> %d %s pozisyon açıldı",
                                   note, opened, SideName(trade_side));
     }
   return (opened > 0);
  }

//+------------------------------------------------------------------+
//| Sinyal sayımına dayalı çıkış kontrolü                            |
//|                                                                  |
//| Pozisyon açıldıktan SONRA gelen sinyaller kronolojik sırayla     |
//| taranır. Pozisyon yönüyle aynı yönlü ve giriş fiyatını geçen     |
//| sinyaller TP sayacını, ters yönlü ve giriş fiyatını geçen        |
//| sinyaller SL sayacını artırır. Sayacı önce dolduran çıkış        |
//| gerçekleşir. Böylece EA yeniden başlatılsa bile sayım, pozisyon  |
//| açılış zamanına göre geçmiş mumlardan tekrar hesaplanabilir.     |
//+------------------------------------------------------------------+
int EvaluatePositionExit(const ulong ticket,
                         const MqlRates &rates[],
                         const double &chan_top[],
                         const double &chan_bot[],
                         const bool &chan_ready[],
                         string &reason,
                         int &tp_count_out,
                         int &sl_count_out)
  {
   reason       = "";
   tp_count_out = 0;
   sl_count_out = 0;
   if(!SelectOurPosition(ticket))
      return 0;

   int      side       = SideFromPositionType(PositionGetInteger(POSITION_TYPE));
   double   entry      = PositionGetDouble(POSITION_PRICE_OPEN);
   datetime open_time  = (datetime)PositionGetInteger(POSITION_TIME);
   if(side == 0 || entry <= 0.0)
      return 0;

   int last_closed = ArraySize(rates) - 2; // Son index oluşan mumdur
   int period_seconds = PeriodSeconds(g_timeframe);
   if(period_seconds <= 0)
      period_seconds = 60;

   for(int i = 1; i <= last_closed; i++)
     {
      if(!chan_ready[i])
         continue;
      int signal = ChannelSignalAt(rates, chan_top, chan_bot, chan_ready, i);
      if(signal == 0)
         continue;

      // Sinyal, mum kapandığında oluşur. Pozisyonu açan sinyalin kendisi
      // sayılmaz; sadece açılıştan sonra kapanan mumların sinyalleri sayılır.
      datetime signal_close_time = rates[i].time + period_seconds;
      if(signal_close_time <= open_time)
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
         if(InpTakeProfitSignalCount > 0 && tp_count_out >= InpTakeProfitSignalCount)
           {
            reason = StringFormat("TP (sinyal sayımı): %d. uygun %s sinyali, giriş=%.*f sinyal fiyatı=%.*f",
                                  tp_count_out, SideName(signal), _Digits, entry, _Digits, signal_price);
            return 1;
           }
        }
      if(is_sl_signal)
        {
         sl_count_out++;
         if(InpStopLossSignalCount > 0 && sl_count_out >= InpStopLossSignalCount)
           {
            reason = StringFormat("SL (sinyal sayımı): %d. uygun %s sinyali, giriş=%.*f sinyal fiyatı=%.*f",
                                  sl_count_out, SideName(signal), _Digits, entry, _Digits, signal_price);
            return -1;
           }
        }
     }
   return 0;
  }

void ManageSignalExits(const MqlRates &rates[],
                       const double &chan_top[],
                       const double &chan_bot[],
                       const bool &chan_ready[])
  {
   if(InpTakeProfitSignalCount <= 0 && InpStopLossSignalCount <= 0)
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
      string reason = "";
      int tp_count = 0;
      int sl_count = 0;
      int result = EvaluatePositionExit(tickets[i], rates, chan_top, chan_bot, chan_ready,
                                        reason, tp_count, sl_count);
      if(result != 0)
         CloseOurPosition(tickets[i], reason);
     }
  }

//+------------------------------------------------------------------+
//| Kapanmış mum işleme                                              |
//+------------------------------------------------------------------+
void ProcessClosedBar()
  {
   MqlRates rates[];
   int copied = LoadRates(rates);
   int min_bars = (int)MathMax(InpLength + 2, InpAtrLength + 2);
   if(copied < min_bars)
     {
      g_last_action = StringFormat("Yetersiz mum verisi: %d/%d", copied, min_bars);
      return;
     }

   double atr[];
   if(!ComputeAtrSeries(rates, InpAtrLength, atr))
     {
      g_last_action = "ATR hesaplanamadı";
      return;
     }

   double chan_high[], chan_low[], chan_top[], chan_bot[];
   bool   chan_ready[];
   if(!BuildChannel(rates, atr, chan_high, chan_low, chan_top, chan_bot, chan_ready))
     {
      g_last_action = "Kanal hesaplanamadı";
      return;
     }

   int last_closed = copied - 2; // Son index oluşan (canlı) mumdur
   if(last_closed < 1 || !chan_ready[last_closed])
     {
      g_last_action = "Kanal için yeterli kapalı mum yok";
      return;
     }

   g_chan_max = chan_high[last_closed];
   g_chan_min = chan_low[last_closed];
   g_chan_mid = (g_chan_max + g_chan_min) * 0.5;
   g_atr_half = InpAtrMultiplier * atr[last_closed];
   g_chan_top = chan_top[last_closed];
   g_chan_bot = chan_bot[last_closed];
   ComputePower(rates, last_closed, g_buy_power, g_sell_power);

   if(InpLogIndicator)
     {
      PrintFormat("Kanal[%s] max=%.*f min=%.*f mid=%.*f atr/2=%.*f | top(min+atr)=%.*f bot(max-atr)=%.*f | BuyPower=%d SellPower=%d",
                  TimeToString(rates[last_closed].time, TIME_DATE | TIME_MINUTES),
                  _Digits, g_chan_max, _Digits, g_chan_min, _Digits, g_chan_mid,
                  _Digits, g_atr_half, _Digits, g_chan_top, _Digits, g_chan_bot,
                  g_buy_power, g_sell_power);
     }

   DrawChannel(rates, last_closed);

   // Önce mevcut pozisyonların sinyal sayımlı çıkışları kontrol edilir;
   // böylece bu mumda oluşan sinyal önce eski pozisyonlara işletilir,
   // ardından aynı sinyal yeni pozisyon açabilir.
   ManageSignalExits(rates, chan_top, chan_bot, chan_ready);

   int raw_signal = ChannelSignalAt(rates, chan_top, chan_bot, chan_ready, last_closed);
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

//+------------------------------------------------------------------+
//| Bilgi paneli                                                     |
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

   string channel_text;
   if(g_chan_max <= 0.0)
      channel_text = "henüz hesaplanmadı (ilk mum bekleniyor)";
   else
      channel_text = StringFormat("max %.*f | min %.*f | orta %.*f | atr/2 %.*f",
                                  _Digits, g_chan_max, _Digits, g_chan_min,
                                  _Digits, g_chan_mid, _Digits, g_atr_half);

   string levels_text = "-";
   if(g_chan_top > 0.0)
      levels_text = StringFormat("BUY eşiği (min+atr) %.*f | SELL eşiği (max-atr) %.*f",
                                 _Digits, g_chan_top, _Digits, g_chan_bot);

   double price = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   string zone_text = "-";
   if(g_atr_half > 0.0 && price > 0.0)
     {
      if(price >= g_chan_max - g_atr_half)
         zone_text = "direnç bandında / üzerinde";
      else if(price <= g_chan_min + g_atr_half)
         zone_text = "destek bandında / altında";
      else
         zone_text = "bantlar arasında";
     }

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

   Comment("S&R Power Channel [ChartPrime] EA v1.00\n",
           "Sembol: ", _Symbol, " | TF: ", EnumToString(g_timeframe),
           " | length: ", IntegerToString(InpLength), " | ATR: ",
           IntegerToString(InpAtrLength), " x ", DoubleToString(InpAtrMultiplier, 2), "\n",
           "Kanal: ", channel_text, "\n",
           "Sinyal seviyeleri: ", levels_text, "\n",
           "Fiyat bölgesi: ", zone_text, "\n",
           "Buy Power / Sell Power (son ", IntegerToString(InpLength), " mum): ",
           IntegerToString(g_buy_power), " / ", IntegerToString(g_sell_power), "\n",
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
           "Durum: ", g_last_action);
  }

//+------------------------------------------------------------------+
//| Standart olaylar                                                 |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpLength < 2 || InpAtrLength < 1 ||
      InpAtrMultiplier <= 0.0 || InpExtend < 0 ||
      InpHistoryBars < 100 || InpLotSize <= 0.0 ||
      InpTakeProfitSignalCount < 0 || InpStopLossSignalCount < 0 ||
      InpFixedTakeProfitPoints < 0 || InpFixedStopLossPoints < 0 ||
      InpDeviationPoints < 0 || InpMaxSpreadPoints < 0 ||
      InpMaxOpenPositions < 0 ||
      !MathIsValidNumber(InpAtrMultiplier) || !MathIsValidNumber(InpLotSize))
     {
      Print("Hatalı girdiler: length, ATR uzunluğu/çarpanı, lot, sinyal sayıları ve emir ayarlarını kontrol edin.");
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

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetAsyncMode(false);
   trade.SetTypeFillingBySymbol(_Symbol);

   g_object_prefix = StringFormat("SRPC_%I64u_%s_%s_",
                                  InpMagicNumber, _Symbol, EnumToString(g_timeframe));
   g_last_bar_time = iTime(_Symbol, g_timeframe, 0);

   // Otomatik sıfırlama referansı: robotun başladığı andaki bakiye
   g_reset_start_balance = FlatReferenceBalance();
   g_reset_hold          = false;

   EventSetTimer(1);
   PrintFormat("EA hazır: %s TF=%s | length=%d | ta.atr(%d)*%.2f | TP=%d sinyal SL=%d sinyal | ters işlem=%s",
               _Symbol, EnumToString(g_timeframe), InpLength,
               InpAtrLength, InpAtrMultiplier,
               InpTakeProfitSignalCount, InpStopLossSignalCount,
               (InpReverseTrading ? "true" : "false"));
   Print("Kanal bantları Pine ile birebir: direnç bandı max±atr, destek bandı min±atr | "
         "BUY: low>min+atr, SELL: high<max-atr");
   if(InpHistoryBars < InpAtrLength * 3)
      PrintFormat("UYARI: InpHistoryBars (%d) ATR(%d) için düşük. RMA yakınsaması tamamlanmayabilir; "
                  "TradingView ile küçük farklar görülebilir.", InpHistoryBars, InpAtrLength);
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
   Print("Sinyaller yalnızca kapanmış mumlarda değerlendirilir. Açılışta geçmişe dönük sinyal işlenmez.");
   UpdateChartInfo();
   return INIT_SUCCEEDED;
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
   UpdateChartInfo();
  }

void OnTimer()
  {
   CheckAutoReset();
   CheckNewBar();
   UpdateChartInfo();
  }

double OnTester()
  {
   // Strategy Tester optimizasyonunda net kârı sırala.
   return TesterStatistics(STAT_PROFIT);
  }

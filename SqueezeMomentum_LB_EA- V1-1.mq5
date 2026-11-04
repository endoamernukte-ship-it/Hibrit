//+------------------------------------------------------------------+
//|                                           SqueezeMomentum_LB_EA.mq5 |
//|        Squeeze Momentum Indicator [LazyBear] -> MT5 Expert Advisor  |
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
//|  NOT: TP/SL sinyal sayımıyla çalıştığı için bunlar sabit fiyat   |
//|  emri olarak brokera gönderilmez; sayım dolunca EA pozisyonu     |
//|  piyasadan kapatır. Bu yüzden EA'nın açık kalması gerekir.       |
//|  İsterseniz ek güvenlik için sabit TP/SL (point) de tanımlanabilir.  |
//+------------------------------------------------------------------+
#property copyright "Squeeze Momentum [LazyBear] - MT5 EA"
#property version   "1.10"
#property strict
#property description "Squeeze Momentum [LazyBear] renk değişimi sinyalleriyle işlem açar"
#property description "Sinyal renk geçişleri (BUY/SELL) girdilerden ayrı ayrı seçilebilir"
#property description "Çıkışlar: girişe göre uygun yöndeki 3. sinyal TP, ters yöndeki 3. sinyal SL (ayarlanabilir)"
#property description "Ters işlem ayarı: BUY sinyali SELL, SELL sinyali BUY açar (açık/kapalı seçilebilir)"

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

//+------------------------------------------------------------------+
//| Giriş parametreleri                                              |
//+------------------------------------------------------------------+
input group "1) Squeeze Momentum [LazyBear] ayarları"
input ENUM_TIMEFRAMES InpTimeframe          = PERIOD_CURRENT; // İşlem zaman dilimi (PERIOD_CURRENT = grafik TF)
input int             InpBBLength           = 20;             // BB Length
input double          InpBBMultFactor       = 2.0;            // BB MultFactor
input int             InpKCLength           = 20;             // KC Length
input double          InpKCMultFactor       = 1.5;            // KC MultFactor
input bool            InpUseTrueRange       = true;           // Use TrueRange (KC)
input int             InpHistoryBars        = 5000;           // Taranacak maksimum mum sayısı (sinyal + çıkış sayımı)

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

   // Bollinger: basis = sma(close, BB), dev = BB_Mult * stdev(close, BB)
   // NOT: Gönderilen kodda dev satırında multKC yazıyordu; orijinal
   // LazyBear kodunda BB sapması BB MultFactor ile hesaplanır. Bu
   // fark sadece sıkışma durumunu etkiler, momentum çubuklarını ve
   // dolayısıyla sinyalleri etkilemez.
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
   double dev = InpBBMultFactor * MathSqrt(variance / InpBBLength);
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

int LoadRates(MqlRates &rates[])
  {
   int needed = (int)MathMax(InpHistoryBars, (InpKCLength * 4) + 10);
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
                         const ENUM_SQZ_BAR_COLOR &colors[],
                         const bool &valid[],
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
      if(!valid[i] || !valid[i - 1])
         continue;
      int signal = SignalFromTransition(colors[i - 1], colors[i]);
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
                       const ENUM_SQZ_BAR_COLOR &colors[],
                       const bool &valid[])
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
      int result = EvaluatePositionExit(tickets[i], rates, colors, valid, reason, tp_count, sl_count);
      if(result != 0)
         CloseOurPosition(tickets[i], reason);
     }
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

   string comment = (trade_side > 0 ? "SQZLB BUY" : "SQZLB SELL");
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

//+------------------------------------------------------------------+
//| Kapanmış mum işleme                                              |
//+------------------------------------------------------------------+
void ProcessClosedBar()
  {
   MqlRates rates[];
   int copied = LoadRates(rates);
   int min_bars = (2 * InpKCLength) + 5;
   if(copied < min_bars)
     {
      g_last_action = StringFormat("Yetersiz mum verisi: %d/%d", copied, min_bars);
      return;
     }

   double values[];
   ENUM_SQZ_BAR_COLOR colors[];
   bool valid[];
   if(!ComputeMomentum(rates, values, colors, valid))
     {
      g_last_action = "Momentum hesaplanamadı";
      return;
     }

   int last_closed = copied - 2; // Son index oluşan (canlı) mumdur
   if(last_closed < 1 || !valid[last_closed] || !valid[last_closed - 1])
     {
      g_last_action = "Momentum için yeterli kapalı mum yok";
      return;
     }

   g_last_momentum  = values[last_closed];
   g_last_bar_color = colors[last_closed];
   g_prev_bar_color = colors[last_closed - 1];
   g_last_sqz_state = ComputeSqueezeState(rates, last_closed);

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

   Comment("Squeeze Momentum [LazyBear] EA v1.10\n",
           "Sembol: ", _Symbol, " | TF: ", EnumToString(g_timeframe), "\n",
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

   g_object_prefix = StringFormat("SQZLB_%I64u_%s_%s_",
                                  InpMagicNumber, _Symbol, EnumToString(g_timeframe));
   g_last_bar_time = iTime(_Symbol, g_timeframe, 0);

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
   CheckNewBar();
   UpdateChartInfo();
  }

void OnTimer()
  {
   CheckNewBar();
   UpdateChartInfo();
  }

double OnTester()
  {
   // Strategy Tester optimizasyonunda net kârı sırala.
   return TesterStatistics(STAT_PROFIT);
  }
//+------------------------------------------------------------------+

//+------------------------------------------------------------------+
//|                                           SqueezeMomentum_LB_EA_Lab.mq5 |
//|        Squeeze Momentum Indicator [LazyBear] -> MT5 Expert Advisor  |
//|                                                                  |
//|  SİNYAL KURALLARI (sadece KAPANMIŞ mumlar kullanılır):           |
//|   * Açık yeşil (lime)  -> Koyu yeşil (green) geçişi : SELL sinyali|
//|   * Kırmızı (red)      -> Bordo (maroon)     geçişi : BUY  sinyali|
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
#property version   "2.00"
#property strict
#property description "Squeeze Momentum [LazyBear] renk değişimi sinyalleriyle işlem açar"
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

// Experimental entry policies. Original raw signals continue to drive exits.
enum ENUM_LAB_ENTRY_MODE
  {
   LAB_CLASSIC=0,           // Original colour-transition signal
   LAB_SQUEEZE_REVERSAL=1,  // Raw signal on first squeeze release
   LAB_SQUEEZE_TREND=2      // Release in the momentum direction
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

input group "2) Sinyal ve ters işlem"
input bool            InpReverseTrading     = false; // TERS İŞLEM: true = BUY sinyali SELL, SELL sinyali BUY açar
input bool            InpOpenOnBuySignal    = true;  // BUY sinyalinde işlem aç
input bool            InpOpenOnSellSignal   = true;  // SELL sinyalinde işlem aç
input bool            InpAllowLongTrades    = true;  // BUY pozisyon açmaya izin ver
input bool            InpAllowShortTrades   = true;  // SELL pozisyon açmaya izin ver
input bool            InpDrawSignalArrows   = true;  // Grafikte sinyal okları çiz
input bool            InpShowChartInfo      = true;  // Grafikte bilgi paneli göster

input group "3) Çıkışlar - sinyal sayımı (0 = o çıkış kapalı)"
input int             InpTakeProfitSignalCount = 3;  // TP: girişle aynı yöndeki kaçıncı sinyalde kapat?
input int             InpStopLossSignalCount   = 3;  // SL: girişle ters yöndeki kaçıncı sinyalde kapat?
input int             InpFixedTakeProfitPoints = 0;  // Ekstra sabit TP (point) - 0 = kapalı
input int             InpFixedStopLossPoints   = 0;  // Ekstra sabit SL (point) - 0 = kapalı

input group "4) Pozisyon ve emir"
input double          InpLotSize              = 0.01;      // Lot
input ulong           InpMagicNumber          = 20261107;  // Magic Number
input int             InpDeviationPoints      = 20;        // Maksimum sapma (point)
input int             InpMaxSpreadPoints      = 0;         // Maksimum spread (point) - 0 = kapalı
input int             InpMaxOpenPositions     = 0;         // Aynı anda maks. pozisyon - 0 = sınırsız
input bool            InpRequireHedgingAccount = true;     // Hedging hesap zorunlu olsun mu?
input bool            InpDeleteArrowsOnExit   = true;      // EA kapanırken sinyal oklarını sil

input group "5) Lab - agirlikli sinyal cikisi"
input bool            InpWeightedSignals      = false; // ATR ile normalize edilen sinyal agirligi
input int             InpLabATRPeriod         = 14;    // Lab ATR: kapanmis mum TR basit ortalamasi
input double          InpWeightReference      = 0.10;  // delta momentum / ATR = bu degerse agirlik 1
input double          InpWeightMinimum        = 0.25;  // Asgari sinyal agirligi
input double          InpWeightMaximum        = 2.00;  // Azami sinyal agirligi

input group "6) Lab - sikisma ve maliyet"
input ENUM_LAB_ENTRY_MODE InpLabEntryMode      = LAB_CLASSIC; // Giris modu
input int             InpSqueezeLookback      = 10;    // Birakilmadan onceki sikisma arama mumlari
input double          InpMaxSpreadATRPercent  = 0.0;   // Spread / ATR yuzdesi, 0 kapali

input group "7) Lab - pozisyon yasi ve risk butcesi"
input int             InpStaleBlockBars       = 0;     // Bu yasta pozisyon varsa yeni giris yok, 0 kapali
input int             InpMaxHoldingBars       = 0;     // Pozisyon bu kadar mum sonra kapanir, 0 kapali
input double          InpRiskBudgetPercent    = 0.0;   // Hesap genelinde tahmini SL riski / equity %, 0 kapali

input group "8) Lab - sepet guvenligi"
input double          InpBasketLossLimit      = 0.0;   // Sembol+magic sepet zarar limiti (hesap parasi), 0 kapali
input double          InpMaxGrossLots         = 0.0;   // Sembol+magic toplam BUY+SELL lot limiti, 0 kapali

input group "9) Lab - sinyal gunlugu"
input bool            InpSignalJournal        = false; // CSV dosyasina kaydet
input int             InpOutcomeBars          = 10;    // Ham sinyalden sonraki N kapali mum performansi

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
bool            g_basket_locked       = false; // Remains locked until EA is reinitialised.
datetime        g_last_basket_attempt = 0;

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

string SignalName(const int signal)
  {
   if(signal > 0)
      return "BUY sinyali (kırmızı -> bordo)";
   if(signal < 0)
      return "SELL sinyali (açık yeşil -> koyu yeşil)";
   return "sinyal yok";
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

   double sum_x  = (double)period * (period - 1) / 2.0;
   double sum_x2 = (double)(period - 1) * period * (2.0 * period - 1) / 6.0;
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
//   +1 = BUY sinyali, -1 = SELL sinyali, 0 = sinyal yok
int SignalFromTransition(const ENUM_SQZ_BAR_COLOR previous_color,
                         const ENUM_SQZ_BAR_COLOR current_color)
  {
   // Açık yeşil (lime) -> Koyu yeşil (green): momentum pozitifken zayıflıyor
   if(previous_color == SQZ_COLOR_LIME && current_color == SQZ_COLOR_GREEN)
      return -1;
   // Kırmızı (red) -> Bordo (maroon): momentum negatifken toparlanıyor
   if(previous_color == SQZ_COLOR_RED && current_color == SQZ_COLOR_MAROON)
      return 1;
   return 0;
  }

// BB/KC sıkışma durumu. Klasik modda panel bilgisidir; Lab squeeze modları girişte kullanır.
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

// ATR here means the SMA of true range, computed only on closed bars.
double LabATR(const MqlRates &rates[], const int index)
  {
   if(index<InpLabATRPeriod) return 0.0;
   double sum=0.0;
   for(int j=index-InpLabATRPeriod+1;j<=index;j++)
      sum+=MathMax(rates[j].high-rates[j].low,
                   MathMax(MathAbs(rates[j].high-rates[j-1].close),MathAbs(rates[j].low-rates[j-1].close)));
   return sum/InpLabATRPeriod;
  }

double LabSignalWeight(const MqlRates &rates[], const double &values[], const int index)
  {
   if(!InpWeightedSignals) return 1.0;
   double atr=LabATR(rates,index);
   if(index<1 || atr<=0.0) return -1.0; // cannot reconstruct the counter safely
   return MathMax(InpWeightMinimum,MathMin(InpWeightMaximum,
                  MathAbs(values[index]-values[index-1])/atr/InpWeightReference));
  }

// The release is the first sqzOff after a non-off bar, with an sqzOn in
// the preceding lookback; intermediate noSqz bars are permitted.
int LabEntrySignal(const MqlRates &rates[], const double &values[],
                   const ENUM_SQZ_BAR_COLOR &colors[], const bool &valid[], const int index)
  {
   if(index<1 || !valid[index] || !valid[index-1]) return 0;
   int raw=SignalFromTransition(colors[index-1],colors[index]);
   if(InpLabEntryMode==LAB_CLASSIC) return raw;
   if(ComputeSqueezeState(rates,index)!=SQZ_STATE_OFF ||
      ComputeSqueezeState(rates,index-1)==SQZ_STATE_OFF) return 0;
   bool found=false;
   for(int j=index-1;j>=0 && j>=index-InpSqueezeLookback;j--)
      if(ComputeSqueezeState(rates,j)==SQZ_STATE_ON) { found=true; break; }
   if(!found) return 0;
   if(InpLabEntryMode==LAB_SQUEEZE_REVERSAL) return raw;
   if(values[index]>0.0) return 1;
   if(values[index]<0.0) return -1;
   return 0;
  }

int LoadRates(MqlRates &rates[])
  {
   int needed = (int)MathMax(InpHistoryBars, MathMax((InpKCLength * 4) + 10, MathMax(InpBBLength + InpSqueezeLookback + 5, InpLabATRPeriod + 5)));
   if(InpSignalJournal) needed=(int)MathMax(needed,2*InpKCLength+InpOutcomeBars+5);
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
// Return -2 if the history/weight is incomplete; never silently undercount.
int EvaluatePositionExit(const ulong ticket, const MqlRates &rates[], const double &values[],
                         const ENUM_SQZ_BAR_COLOR &colors[], const bool &valid[],
                         string &reason, double &tp_count, double &sl_count)
  {
   reason=""; tp_count=0.0; sl_count=0.0;
   if(!SelectOurPosition(ticket)) return 0;
   int side=SideFromPositionType(PositionGetInteger(POSITION_TYPE));
   double entry=PositionGetDouble(POSITION_PRICE_OPEN);
   datetime opened=(datetime)PositionGetInteger(POSITION_TIME);
   int n=ArraySize(rates);
   int warmup=(int)MathMax(2*InpKCLength-1,InpWeightedSignals ? InpLabATRPeriod : 0);
   if(side==0 || entry<=0 || opened<=0 || warmup>=n-1 || rates[warmup].time>opened)
     { reason="Pozisyon acilisina uzanan hesaplanabilir gecmis yetersiz"; return -2; }
   for(int i=1;i<n-1;i++)
     {
      if(!valid[i] || !valid[i-1] || rates[i+1].time<=opened) continue;
      int signal=SignalFromTransition(colors[i-1],colors[i]);
      if(signal==0) continue;
      double change=side*(rates[i].close-entry);
      if(!((signal==side && change>0.0) || (signal==-side && change<0.0))) continue;
      double weight=LabSignalWeight(rates,values,i);
      if(weight<0.0) { reason="ATR hesaplanamadi; sinyal sayimi durduruldu"; return -2; }
      if(signal==side) tp_count+=weight; else sl_count+=weight;
      if(InpTakeProfitSignalCount>0 && tp_count>=InpTakeProfitSignalCount)
        { reason=StringFormat("TP sinyal agirligi %.3f",tp_count); return 1; }
      if(InpStopLossSignalCount>0 && sl_count>=InpStopLossSignalCount)
        { reason=StringFormat("SL sinyal agirligi %.3f",sl_count); return -1; }
     }
   return 0;
  }

bool ManageSignalExits(const MqlRates &rates[], const double &values[],
                       const ENUM_SQZ_BAR_COLOR &colors[], const bool &valid[])
  {
   if(InpTakeProfitSignalCount<=0 && InpStopLossSignalCount<=0) return true;
   bool ok=true;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !SelectOurPosition(ticket)) continue;
      string reason=""; double tp=0.0,sl=0.0;
      int result=EvaluatePositionExit(ticket,rates,values,colors,valid,reason,tp,sl);
      if(result==-2)
        { PrintFormat("LAB ticket=%I64u: %s; yeni giris engellendi",ticket,reason); g_last_action=reason; ok=false; }
      else if(result!=0 && !CloseOurPosition(ticket,reason)) ok=false;
     }
   return ok;
  }

//+------------------------------------------------------------------+
//| Sinyalde pozisyon açma                                           |
//+------------------------------------------------------------------+
bool BuildFixedExits(const int side, const double entry, const MqlTick &tick, double &sl, double &tp)
  {
   sl = 0.0;
   tp = 0.0;
   long stops_level  = (long)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze_level = (long)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double min_distance = MathMax(stops_level, freeze_level) * _Point;

   if(InpFixedTakeProfitPoints > 0)
     {
      double distance = InpFixedTakeProfitPoints * _Point;
      tp = NormalizePriceToTick(entry + side * distance, (side > 0 ? 1 : -1));
     }
   if(InpFixedStopLossPoints > 0)
     {
      double distance = InpFixedStopLossPoints * _Point;
      sl = NormalizePriceToTick(entry - side * distance, (side > 0 ? -1 : 1));
     }
   double exit_price=(side>0 ? tick.bid : tick.ask);
   if(InpFixedTakeProfitPoints>0 && (tp<=0.0 || side*(tp-exit_price)<=0.0 || side*(tp-exit_price)<min_distance)) return false;
   if(InpFixedStopLossPoints>0 && (sl<=0.0 || side*(exit_price-sl)<=0.0 || side*(exit_price-sl)<min_distance)) return false;
   return true;
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

double LabGrossLots()
  {
   double lots=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     { ulong t=PositionGetTicket(i); if(t!=0 && SelectOurPosition(t)) lots+=PositionGetDouble(POSITION_VOLUME); }
   return lots;
  }

bool LabStalePositionExists()
  {
   if(InpStaleBlockBars<=0) return false;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong t=PositionGetTicket(i);
      if(t==0 || !SelectOurPosition(t)) continue;
      int age=iBarShift(_Symbol,g_timeframe,(datetime)PositionGetInteger(POSITION_TIME),false);
      if(age<0 || age>=InpStaleBlockBars) return true; // unavailable history: fail closed
     }
   return false;
  }

bool LabManageAge()
  {
   if(InpMaxHoldingBars<=0) return true;
   bool ok=true;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong t=PositionGetTicket(i);
      if(t==0 || !SelectOurPosition(t)) continue;
      int age=iBarShift(_Symbol,g_timeframe,(datetime)PositionGetInteger(POSITION_TIME),false);
      if(age<0) { g_last_action="Pozisyon yasi hesaplanamadi"; ok=false; }
      else if(age>=InpMaxHoldingBars && !CloseOurPosition(t,"Maksimum pozisyon yasi")) ok=false;
     }
   return ok;
  }

// Conservative account-wide estimate: all existing positions must have an SL;
// pending orders are blocked because their future risk cannot be inferred here.
bool LabRiskBudgetOK(const int side,const double volume,const double entry,const double sl)
  {
   if(InpRiskBudgetPercent<=0.0) return true;
   if(sl<=0.0 || OrdersTotal()>0) { g_last_action="Risk butcesi: SL gerekli; bekleyen emir olmamali"; return false; }
   double risk=0.0, profit=0.0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong t=PositionGetTicket(i);
      if(t==0 || !PositionSelectByTicket(t)) { g_last_action="Risk butcesi: pozisyon okunamadi"; return false; }
      string symbol=PositionGetString(POSITION_SYMBOL);
      double old_sl=PositionGetDouble(POSITION_SL);
      double old_volume=PositionGetDouble(POSITION_VOLUME);
      ENUM_ORDER_TYPE type=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
      MqlTick quote;
      if(old_sl<=0.0 || !SymbolInfoTick(symbol,quote) || quote.bid<=0.0 || quote.ask<quote.bid)
        { g_last_action="Risk butcesi: hesap pozisyonunda SL/fiyat yok"; return false; }
      double liquidation=(type==ORDER_TYPE_BUY ? quote.bid : quote.ask);
      if((type==ORDER_TYPE_BUY && old_sl>=liquidation) || (type==ORDER_TYPE_SELL && old_sl<=liquidation) ||
         !OrderCalcProfit(type,symbol,old_volume,liquidation,old_sl,profit))
        { g_last_action="Risk butcesi: hesap pozisyonu riski hesaplanamadi"; return false; }
      risk+=MathMax(0.0,-profit);
     }
   if(!OrderCalcProfit(side>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL,_Symbol,volume,entry,sl,profit))
     { g_last_action="Risk butcesi: yeni emir riski hesaplanamadi"; return false; }
   risk+=MathMax(0.0,-profit);
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity<=0.0 || risk>equity*InpRiskBudgetPercent/100.0)
     { g_last_action=StringFormat("Risk butcesi asildi: %.2f",risk); return false; }
   return true;
  }

// Equity estimate uses POSITION_PROFIT+SWAP, excludes commissions. Once hit,
// lock new entries until reinitialisation and retry failed closes once/second.
void LabManageBasket()
  {
   if(InpBasketLossLimit<=0.0) return;
   double pnl=0.0; int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong t=PositionGetTicket(i);
      if(t==0 || !SelectOurPosition(t)) continue;
      pnl+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP); count++;
     }
   if(count>0 && pnl<=-InpBasketLossLimit && !g_basket_locked)
     { g_basket_locked=true; PrintFormat("LAB sepet zarar kilidi: %.2f",pnl); }
   if(!g_basket_locked) return;
   g_last_action="Sepet zarar kilidi: yeni giris kapali";
   datetime now=TimeCurrent();
   if(now==g_last_basket_attempt) return;
   g_last_basket_attempt=now;
   // A pending order might otherwise fill after all positions are closed.
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong t=OrderGetTicket(i);
      if(t==0 || OrderGetString(ORDER_SYMBOL)!=_Symbol || (ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagicNumber) continue;
      if(!TradeRetcodeOK(trade.OrderDelete(t)) || OrderSelect(t))
         PrintFormat("LAB sepet kilidi: bekleyen emir iptal edilemedi ticket=%I64u retcode=%u",t,trade.ResultRetcode());
     }
   for(int i=PositionsTotal()-1;i>=0;i--)
     { ulong t=PositionGetTicket(i); if(t!=0 && SelectOurPosition(t)) CloseOurPosition(t,"Sepet zarar limiti"); }
  }

bool LabPendingOrderExists()
  {
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong ticket=OrderGetTicket(i);
      if(ticket!=0 && OrderGetString(ORDER_SYMBOL)==_Symbol &&
         (ulong)OrderGetInteger(ORDER_MAGIC)==InpMagicNumber) return true;
     }
   return false;
  }

bool OpenPositionBySignal(const int raw_signal, const datetime signal_bar_time, const double signal_price, const double atr)
  {
   if(LabPendingOrderExists()) { g_last_action="Onceki emir bekliyor; yeni giris engellendi"; return false; }
   if(g_basket_locked) { g_last_action="Sepet zarar kilidi aktif"; return false; }
   if(LabStalePositionExists()) { g_last_action="Eski pozisyon nedeniyle yeni giris engellendi"; return false; }
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

   if(tick.ask<tick.bid) { g_last_action="Gecersiz fiyat"; return false; }
   double spread_points = (tick.ask - tick.bid) / _Point;
   if(InpMaxSpreadPoints > 0 && spread_points > InpMaxSpreadPoints)
     {
      g_last_action = StringFormat("Spread yüksek: %.1f point", spread_points);
      return false;
     }

   if(InpMaxSpreadATRPercent>0.0 && (atr<=0.0 || (tick.ask-tick.bid)/atr*100.0>InpMaxSpreadATRPercent))
     { g_last_action="Spread / ATR limiti veya ATR verisi"; return false; }

   double volume = NormalizeVolume(InpLotSize);
   if(volume <= 0.0)
     {
      g_last_action = "Lot hacmi broker sınırlarına uymuyor";
      return false;
     }

   if(InpMaxGrossLots>0.0 && LabGrossLots()+volume>InpMaxGrossLots+1e-9)
     { g_last_action="Sepet toplam lot limiti"; return false; }
   // Do not let netting orders modify another strategy's/manual position.
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING && PositionSelect(_Symbol) &&
      (ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber)
     { g_last_action="Netting sembolunde baska pozisyon var"; return false; }
   double expected_entry = (trade_side > 0 ? tick.ask : tick.bid);
   double fixed_sl = 0.0;
   double fixed_tp = 0.0;
   if(!BuildFixedExits(trade_side, expected_entry, tick, fixed_sl, fixed_tp))
     {
      g_last_action = "Sabit TP/SL broker veya spread mesafesine uymuyor";
      return false;
     }

   if(!LabRiskBudgetOK(trade_side,volume,expected_entry,fixed_sl)) return false;
   string comment = (trade_side > 0 ? "SQZLAB BUY" : "SQZLAB SELL");
   bool sent = false;
   if(trade_side > 0)
      sent = trade.Buy(volume, _Symbol, 0.0, fixed_sl, fixed_tp, comment);
   else
      sent = trade.Sell(volume, _Symbol, 0.0, fixed_sl, fixed_tp, comment);

   if(!TradeRetcodeOK(sent))
     {
      PrintFormat("Giriş başarısız: sinyal=%s işlem yönü=%s lot=%.8f retcode=%u (%s)",
                  SideName(raw_signal), SideName(trade_side), volume,
                  trade.ResultRetcode(), trade.ResultRetcodeDescription());
      g_last_action = "Emir broker tarafından reddedildi";
      return false;
     }

   PrintFormat("Giriş: %s | işlem=%s%s | sinyal mumu=%s sinyal fiyatı=%.*f | lot=%.8f",
               SideName(raw_signal), SideName(trade_side),
               (InpReverseTrading ? " (ters işlem)" : ""),
               TimeToString(signal_bar_time), _Digits, signal_price, volume);
   if(trade.ResultRetcode()==TRADE_RETCODE_PLACED)
      g_last_action="Emir kabul edildi, gerceklesme bekleniyor";
   else if(trade.ResultRetcode()==TRADE_RETCODE_DONE_PARTIAL)
      g_last_action="Emir kismen gerceklesti; pozisyonu kontrol edin";
   else
      g_last_action = StringFormat("Yeni %s pozisyon acildi (%s%s)",
                                   SideName(trade_side), SideName(raw_signal),
                                   (InpReverseTrading ? ", ters islem" : ""));
   return true;
  }

//+------------------------------------------------------------------+
//| Kapanmış mum işleme                                              |
//+------------------------------------------------------------------+
// Logs observable facts only. OUTCOME records use the raw signal from N bars
// ago and the current closed price. They are not available to the trading logic.
void LabJournal(const string kind, const datetime signal_time, const datetime observed_time,
                const int raw, const int entry_signal, const double signal_close,
                const double observed_close, const double momentum, const double atr,
                const ENUM_SQZ_STATE state, const string action)
  {
   if(!InpSignalJournal) return;
   string symbol=_Symbol;
   StringReplace(symbol,"/","_"); StringReplace(symbol,"\\","_");
   StringReplace(symbol,":","_"); StringReplace(symbol,"*","_"); StringReplace(symbol,"?","_");
   StringReplace(symbol,"\"","_"); StringReplace(symbol,"<","_"); StringReplace(symbol,">","_"); StringReplace(symbol,"|","_");
   string file=StringFormat("SQZLab_%s_%s_%I64u.csv",symbol,EnumToString(g_timeframe),InpMagicNumber);
   int h=FileOpen(file,FILE_READ|FILE_WRITE|FILE_CSV|FILE_ANSI|FILE_SHARE_READ,',');
   if(h==INVALID_HANDLE) { PrintFormat("LAB CSV acilamadi: %s hata=%d",file,GetLastError()); return; }
   if(FileSize(h)==0)
      FileWrite(h,"kind","signal_time","observed_time","raw","entry_signal","signal_close","observed_close","move_points","momentum","atr","squeeze","spread_points","buy_count","sell_count","action");
   FileSeek(h,0,SEEK_END);
   MqlTick tick; double spread=-1.0;
   if(SymbolInfoTick(_Symbol,tick) && tick.ask>=tick.bid && tick.bid>0) spread=(tick.ask-tick.bid)/_Point;
   FileWrite(h,kind,TimeToString(signal_time,TIME_DATE|TIME_SECONDS),TimeToString(observed_time,TIME_DATE|TIME_SECONDS),
             raw,entry_signal,DoubleToString(signal_close,_Digits),DoubleToString(observed_close,_Digits),
             DoubleToString((observed_close-signal_close)/_Point,1),DoubleToString(momentum,_Digits+2),
             DoubleToString(atr,_Digits+2),SqueezeStateName(state),DoubleToString(spread,1),
             CountOurPositions(1),CountOurPositions(-1),action);
   FileClose(h);
  }

bool ProcessClosedBar(const datetime current_bar_time)
  {
   MqlRates rates[];
   int copied=LoadRates(rates);
   int min_bars=(int)MathMax((2*InpKCLength)+5,InpLabATRPeriod+2);
   if(copied<min_bars || rates[copied-1].time!=current_bar_time)
     { g_last_action=StringFormat("Yetersiz veya guncel olmayan mum verisi: %d/%d",copied,min_bars); return false; }
   double values[]; ENUM_SQZ_BAR_COLOR colors[]; bool valid[];
   if(!ComputeMomentum(rates,values,colors,valid)) { g_last_action="Momentum hesaplanamadi"; return false; }
   int last=copied-2;
   if(last<1 || !valid[last] || !valid[last-1]) { g_last_action="Momentum icin yeterli mum yok"; return false; }
   g_last_momentum=values[last]; g_last_bar_color=colors[last]; g_prev_bar_color=colors[last-1];
   g_last_sqz_state=ComputeSqueezeState(rates,last);
   bool age_ok=LabManageAge();
   bool exit_ok=ManageSignalExits(rates,values,colors,valid);
   int raw=SignalFromTransition(colors[last-1],colors[last]);
   int entry=LabEntrySignal(rates,values,colors,valid,last);
   double atr=LabATR(rates,last);
   if(raw!=0)
     {
      g_last_raw_signal=raw; g_last_signal_time=rates[last].time; g_last_signal_price=rates[last].close;
      DrawSignalArrow(rates[last].time,rates[last].high,rates[last].low,raw);
     }
   if(!age_ok || !exit_ok) g_last_action="Cikis/hesaplama hatasi; yeni giris engellendi";
   else if(entry!=0) OpenPositionBySignal(entry,rates[last].time,rates[last].close,atr);
   else g_last_action=(raw!=0 ? "Ham sinyal giris filtresinden gecmedi" : "Yeni sinyal yok");
   if(raw!=0 || entry!=0)
      LabJournal("SIGNAL",rates[last].time,rates[last].time,raw,entry,rates[last].close,rates[last].close,values[last],atr,g_last_sqz_state,g_last_action);
   int target=last-InpOutcomeBars;
   if(InpSignalJournal && target>=1 && valid[target] && valid[target-1])
     {
      int oldraw=SignalFromTransition(colors[target-1],colors[target]);
      int oldentry=LabEntrySignal(rates,values,colors,valid,target);
      if(oldraw!=0 || oldentry!=0)
         LabJournal("OUTCOME",rates[target].time,rates[last].time,oldraw,oldentry,rates[target].close,rates[last].close,
                    values[target],LabATR(rates,target),ComputeSqueezeState(rates,target),"sinyal N mum sonrasi fiyat degisimi");
     }
   return true;
  }

void CheckNewBar()
  {
   datetime current=iTime(_Symbol,g_timeframe,0);
   if(current<=0) return;
   if(g_last_bar_time==0) { g_last_bar_time=current; return; }
   if(current==g_last_bar_time) return;
   if(ProcessClosedBar(current)) g_last_bar_time=current;
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

   Comment("Squeeze Momentum [LazyBear] LAB v2.00\n",
           "Sembol: ", _Symbol, " | TF: ", EnumToString(g_timeframe), "\n",
           "Son kapalı mum momentum: ", DoubleToString(g_last_momentum, _Digits + 2), "\n",
           "Renk geçişi: ", ColorName(g_prev_bar_color), " -> ", ColorName(g_last_bar_color), "\n",
           "Squeeze durumu: ", SqueezeStateName(g_last_sqz_state), " | Mod: ", EnumToString(InpLabEntryMode), "\n",
           "Sepet: ", DoubleToString(LabGrossLots(),2), " lot | Kilit: ", (g_basket_locked ? "AKTIF" : "kapali"), "\n",
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
   if(InpBBLength < 2 || InpBBLength > 5000 || InpKCLength < 2 || InpKCLength > 5000 ||
      InpBBMultFactor <= 0.0 || InpKCMultFactor <= 0.0 ||
      InpHistoryBars < 100 || InpHistoryBars > 1000000 || InpLotSize <= 0.0 ||
      InpTakeProfitSignalCount < 0 || InpStopLossSignalCount < 0 ||
      InpFixedTakeProfitPoints < 0 || InpFixedStopLossPoints < 0 ||
      InpDeviationPoints < 0 || InpMaxSpreadPoints < 0 ||
      InpMaxOpenPositions < 0 || InpLabATRPeriod<1 || InpLabATRPeriod>5000 ||
      InpSqueezeLookback<1 || InpSqueezeLookback>5000 || InpOutcomeBars<1 || InpOutcomeBars>5000 ||
      InpStaleBlockBars<0 || InpMaxHoldingBars<0 || InpRiskBudgetPercent<0 ||
      InpMaxSpreadATRPercent<0 || InpBasketLossLimit<0 || InpMaxGrossLots<0 ||
      InpWeightReference<=0 || InpWeightMinimum<=0 || InpWeightMaximum<InpWeightMinimum ||
      !MathIsValidNumber(InpRiskBudgetPercent) || !MathIsValidNumber(InpMaxSpreadATRPercent) ||
      !MathIsValidNumber(InpBasketLossLimit) || !MathIsValidNumber(InpMaxGrossLots) ||
      !MathIsValidNumber(InpWeightReference) || !MathIsValidNumber(InpWeightMinimum) || !MathIsValidNumber(InpWeightMaximum) ||
      !MathIsValidNumber(InpBBMultFactor) || !MathIsValidNumber(InpKCMultFactor) ||
      !MathIsValidNumber(InpLotSize))
     {
      Print("Hatalı girdiler: BB/KC uzunluk ve çarpımları, lot, sinyal sayıları ve emir ayarlarını kontrol edin.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpRiskBudgetPercent>0.0 && InpFixedStopLossPoints==0)
      Print("UYARI: Risk butcesi acik ancak yeni emirler icin sabit SL kapali; girisler engellenir.");
   if(InpMaxOpenPositions==0 && InpMaxGrossLots==0.0)
      Print("UYARI: Maksimum pozisyon ve toplam lot limiti kapali.");
   if(InpTakeProfitSignalCount == 0 && InpStopLossSignalCount == 0 &&
      InpFixedTakeProfitPoints == 0 && InpFixedStopLossPoints == 0 &&
      InpMaxHoldingBars==0 && InpBasketLossLimit==0.0)
      Print("UYARI: Tum robot cikislari kapali; pozisyonlari kontrol edin.");

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

   g_object_prefix = StringFormat("SQZLAB_%I64u_%s_%s_",
                                  InpMagicNumber, _Symbol, EnumToString(g_timeframe));
   g_last_bar_time = iTime(_Symbol, g_timeframe, 0);

   EventSetTimer(1);
   PrintFormat("EA hazır: %s TF=%s BB=%d/%.2f KC=%d/%.2f TrueRange=%s | TP=%d sinyal SL=%d sinyal | ters işlem=%s",
               _Symbol, EnumToString(g_timeframe),
               InpBBLength, InpBBMultFactor, InpKCLength, InpKCMultFactor,
               (InpUseTrueRange ? "true" : "false"),
               InpTakeProfitSignalCount, InpStopLossSignalCount,
               (InpReverseTrading ? "true" : "false"));
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
   LabManageBasket();
   CheckNewBar();
   UpdateChartInfo();
  }

void OnTimer()
  {
   LabManageBasket();
   CheckNewBar();
   UpdateChartInfo();
  }

double OnTester()
  {
   // Strategy Tester optimizasyonunda net kârı sırala.
   return TesterStatistics(STAT_PROFIT);
  }
//+------------------------------------------------------------------+

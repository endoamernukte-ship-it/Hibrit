//+------------------------------------------------------------------+
//|  DonchianTrendRanges.mq5                                         |
//|     "Donchian Trend Ranges [AlgoAlpha]" - Pine v5 -> MQL5        |
//|                                                                  |
//|  Bu gösterge, TradingView'deki Pine koduyla BIREBIR aynı          |
//|  matematiği kullanır. Amacı: EA'nın (SqueezeMomentum_LB_EA dosya) |
//|  Donchian motorunun sinyallerini grafikte gözle doğrulamak.       |
//|                                                                  |
//|  Pine karşılığı:                                                 |
//|   length = 50 , mult = 3 , con = 1                               |
//|   l   = ta.lowest(length)      // en düşük DÜŞÜK                 |
//|   u   = ta.highest(length)     // en yüksek YÜKSEK               |
//|   basis = math.avg(u, l)                                          |
//|   fbasis := basis == basis[con] ? basis : fbasis[1]              |
//|   dev   = ta.stdev(close, length, false) * mult   // n-1 bölme   |
//|   vol   = ta.atr(14)                              // RMA         |
//|   rangge := fbasis != fbasis[1] ? dev : rangge[1]                |
//|   upper = fbasis + rangge , lower = fbasis - rangge              |
//|   uu = upper + vol , ul = upper - vol                            |
//|   lu = lower + vol , ll = lower - vol                            |
//|                                                                  |
//|  Sinyaller (Pine plotchar ile aynı koşullar):                    |
//|   Strong Long TP  = crossunder(close, uu)          -> X üstte    |
//|   Strong Short TP = crossover(close, ll)           -> X altta    |
//|   Weak Long TP    = crossunder(close, ul) && !(close,uu) -> ◆    |
//|   Weak Short TP   = crossover(close, lu)  && !(close,ll) -> ◆    |
//|   Bullish Shift   = crossover(close, fbasis)                    |
//|   Bearish Shift   = crossunder(close, fbasis)                   |
//|                                                                  |
//|  NOT: Pine'daki gibi değerler her tick'te yeniden hesaplanır.     |
//|  Pine'daki barcolor() MQL5 göstergesinde doğrudan yapılamaz;      |
//|  onun yerine basis çizgisi yukarı/aşağı rengiyle boyanır.         |
//+------------------------------------------------------------------+
#property copyright "Donchian Trend Ranges [AlgoAlpha] - Pine v5 uyarlaması"
#property version   "1.00"
#property description "Donchian Trend Ranges [AlgoAlpha] birebir Pine çevirisi"
#property description "Strong/Weak Long ve Short TP seviyeleri + trend shift sinyalleri"
#property indicator_chart_window
#property indicator_buffers 14
#property indicator_plots   10

//--- 1) Basis (fbasis) - yukarı/aşağı renkli çizgi
#property indicator_label1  "Basis"
#property indicator_type1   DRAW_COLOR_LINE
#property indicator_color1  C'0,255,187',C'255,17,0'
#property indicator_style1  STYLE_SOLID
#property indicator_width1  2

//--- 2) Üst bulut (uu ile ul arası)
#property indicator_label2  "Upper Cloud"
#property indicator_type2   DRAW_FILLING
#property indicator_color2  C'60,0,0',C'60,0,0'

//--- 3) Alt bulut (ll ile lu arası)
#property indicator_label3  "Lower Cloud"
#property indicator_type3   DRAW_FILLING
#property indicator_color3  C'0,45,35',C'0,45,35'

//--- 4) Basis bulutu (fu ile fl arası)
#property indicator_label4  "Basis Cloud"
#property indicator_type4   DRAW_FILLING
#property indicator_color4  C'35,35,35',C'35,35,35'

//--- 5) Üst ara bölge çizgisi: avg(fu, ul)
#property indicator_label5  "Upper Inter Range"
#property indicator_type5   DRAW_LINE
#property indicator_color5  C'110,110,110'
#property indicator_style5  STYLE_DOT
#property indicator_width5  1

//--- 6) Alt ara bölge çizgisi: avg(fl, lu)
#property indicator_label6  "Lower Inter Range"
#property indicator_type6   DRAW_LINE
#property indicator_color6  C'110,110,110'
#property indicator_style6  STYLE_DOT
#property indicator_width6  1

//--- 7..10) Sinyal işaretleri
#property indicator_label7  "Strong Long TP"
#property indicator_type7   DRAW_ARROW
#property indicator_color7  C'255,17,0'

#property indicator_label8  "Strong Short TP"
#property indicator_type8   DRAW_ARROW
#property indicator_color8  C'0,255,187'

#property indicator_label9  "Weak Long TP"
#property indicator_type9   DRAW_ARROW
#property indicator_color9  C'255,120,90'

#property indicator_label10 "Weak Short TP"
#property indicator_type10  DRAW_ARROW
#property indicator_color10 C'120,255,210'

//+------------------------------------------------------------------+
//| Girdiler                                                         |
//+------------------------------------------------------------------+
input int    InpLength     = 50;                    // Length
input double InpMult       = 3.0;                   // Range Multiplier
input int    InpCon        = 1;                     // con (basis == basis[con])
input int    InpAtrLength  = 14;                    // vol = ta.atr(length)
input color  InpColorUp    = C'0,255,187';          // Up Color (Pine #00ffbb)
input color  InpColorDown  = C'255,17,0';           // Down Color (Pine #ff1100)
input bool   InpShowClouds = true;                  // Bulutları (fill) göster
input bool   InpAlerts     = false;                 // Yeni mumda sinyal alerti ver

//+------------------------------------------------------------------+
//| Tamponlar                                                        |
//+------------------------------------------------------------------+
double BasisBuf[], BasisColorBuf[];
double UpperCloudHi[], UpperCloudLo[];
double LowerCloudHi[], LowerCloudLo[];
double BasisCloudHi[], BasisCloudLo[];
double MidUpperBuf[], MidLowerBuf[];
double StrongLongBuf[], StrongShortBuf[], WeakLongBuf[], WeakShortBuf[];

//+------------------------------------------------------------------+
//| Yardımcı: çizgi renklerini girdilerden uygula                    |
//+------------------------------------------------------------------+
void ApplyColors()
  {
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 0, InpColorUp);
   PlotIndexSetInteger(0, PLOT_LINE_COLOR, 1, InpColorDown);
   PlotIndexSetInteger(6, PLOT_LINE_COLOR, 0, InpColorDown);
   PlotIndexSetInteger(7, PLOT_LINE_COLOR, 0, InpColorUp);
   PlotIndexSetInteger(8, PLOT_LINE_COLOR, 0, InpColorDown);
   PlotIndexSetInteger(9, PLOT_LINE_COLOR, 0, InpColorUp);
  }

//+------------------------------------------------------------------+
//| OnInit                                                           |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpLength < 2 || InpAtrLength < 1 || InpCon < 0 || InpMult <= 0.0)
     {
      Print("Hatalı girdiler: Length >= 2, ATR >= 1, con >= 0, Range Multiplier > 0 olmalı.");
      return INIT_PARAMETERS_INCORRECT;
     }

   SetIndexBuffer(0,  BasisBuf,       INDICATOR_DATA);
   SetIndexBuffer(1,  BasisColorBuf,  INDICATOR_COLOR_INDEX);
   SetIndexBuffer(2,  UpperCloudHi,   INDICATOR_DATA);
   SetIndexBuffer(3,  UpperCloudLo,   INDICATOR_DATA);
   SetIndexBuffer(4,  LowerCloudHi,   INDICATOR_DATA);
   SetIndexBuffer(5,  LowerCloudLo,   INDICATOR_DATA);
   SetIndexBuffer(6,  BasisCloudHi,   INDICATOR_DATA);
   SetIndexBuffer(7,  BasisCloudLo,   INDICATOR_DATA);
   SetIndexBuffer(8,  MidUpperBuf,    INDICATOR_DATA);
   SetIndexBuffer(9,  MidLowerBuf,    INDICATOR_DATA);
   SetIndexBuffer(10, StrongLongBuf,  INDICATOR_DATA);
   SetIndexBuffer(11, StrongShortBuf, INDICATOR_DATA);
   SetIndexBuffer(12, WeakLongBuf,    INDICATOR_DATA);
   SetIndexBuffer(13, WeakShortBuf,   INDICATOR_DATA);

   PlotIndexSetInteger(0, PLOT_COLOR_INDEXES, 2);
   PlotIndexSetInteger(0, PLOT_DRAW_BEGIN, InpLength);

   // Bulut görünürlüğü
   if(!InpShowClouds)
     {
      PlotIndexSetInteger(1, PLOT_SHOW_DATA, false);
      PlotIndexSetInteger(2, PLOT_SHOW_DATA, false);
      PlotIndexSetInteger(3, PLOT_SHOW_DATA, false);
     }

   // Sinyal işaretleri (Wingdings kodları)
   PlotIndexSetInteger(6, PLOT_ARROW, 251);
   PlotIndexSetInteger(7, PLOT_ARROW, 251);
   PlotIndexSetInteger(8, PLOT_ARROW, 108);
   PlotIndexSetInteger(9, PLOT_ARROW, 108);
   PlotIndexSetInteger(6, PLOT_ARROW_SHIFT, -12);
   PlotIndexSetInteger(7, PLOT_ARROW_SHIFT,  12);
   PlotIndexSetInteger(8, PLOT_ARROW_SHIFT, -12);
   PlotIndexSetInteger(9, PLOT_ARROW_SHIFT,  12);

   for(int i = 4; i < 10; i++)
      PlotIndexSetDouble(i, PLOT_EMPTY_VALUE, EMPTY_VALUE);

   ArrayInitialize(BasisBuf, EMPTY_VALUE);
   ArrayInitialize(BasisColorBuf, 0.0);
   ArrayInitialize(UpperCloudHi, EMPTY_VALUE);
   ArrayInitialize(UpperCloudLo, EMPTY_VALUE);
   ArrayInitialize(LowerCloudHi, EMPTY_VALUE);
   ArrayInitialize(LowerCloudLo, EMPTY_VALUE);
   ArrayInitialize(BasisCloudHi, EMPTY_VALUE);
   ArrayInitialize(BasisCloudLo, EMPTY_VALUE);
   ArrayInitialize(MidUpperBuf, EMPTY_VALUE);
   ArrayInitialize(MidLowerBuf, EMPTY_VALUE);
   ArrayInitialize(StrongLongBuf, EMPTY_VALUE);
   ArrayInitialize(StrongShortBuf, EMPTY_VALUE);
   ArrayInitialize(WeakLongBuf, EMPTY_VALUE);
   ArrayInitialize(WeakShortBuf, EMPTY_VALUE);

   ApplyColors();
   IndicatorSetString(INDICATOR_SHORTNAME,
                      StringFormat("Donchian Trend Ranges (%d, %.1f)", InpLength, InpMult));
   IndicatorSetInteger(INDICATOR_DIGITS, _Digits);
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| OnCalculate                                                      |
//+------------------------------------------------------------------+
int OnCalculate(const int rates_total,
                const int prev_calculated,
                const datetime &time[],
                const double &open[],
                const double &high[],
                const double &low[],
                const double &close[],
                const long &tick_volume[],
                const long &volume[],
                const int &spread[])
  {
   if(rates_total < InpLength + InpCon + 5)
      return 0;

   int length  = (int)MathMax(InpLength, 2);
   int atr_len = (int)MathMax(InpAtrLength, 1);
   int con     = (int)MathMax(InpCon, 0);
   int total   = rates_total;

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
      return 0;

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

   // 1) basis = avg(highest(high,length), lowest(low,length))
   for(int i = length - 1; i < total; i++)
     {
      double hi = high[i];
      double lo = low[i];
      for(int j = i - length + 1; j <= i; j++)
        {
         hi = MathMax(hi, high[j]);
         lo = MathMin(lo, low[j]);
        }
      basis[i]    = (hi + lo) * 0.5;
      basis_ok[i] = true;
     }

   // 2) dev = mult * ta.stdev(close, length, biased = false)
   for(int i = length - 1; i < total; i++)
     {
      double sum = 0.0;
      for(int j = i - length + 1; j <= i; j++)
         sum += close[j];
      double mean = sum / length;
      double var  = 0.0;
      for(int j = i - length + 1; j <= i; j++)
        {
         double d = close[j] - mean;
         var += d * d;
        }
      var /= (double)(length - 1);
      dev[i]    = InpMult * MathSqrt(var);
      dev_ok[i] = true;
     }

   // 3) vol = ta.atr(atr_len) -> RMA; ilk değer SMA
   for(int i = 0; i < total; i++)
     {
      double tr_value = high[i] - low[i];
      if(i > 0)
        {
         double prev_close = close[i - 1];
         tr_value = MathMax(tr_value, MathMax(MathAbs(high[i] - prev_close),
                                              MathAbs(low[i]  - prev_close)));
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

   // 4) fbasis / rangge (yapışkan, Pine ile birebir)
   double fb_value = 0.0;
   bool   fb_valid = false;
   double rg_value = 0.0;
   bool   rg_valid = false;
   for(int i = 0; i < total; i++)
     {
      if(basis_ok[i] && i - con >= 0 && basis_ok[i - con])
        {
         if(basis[i] == basis[i - con])
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

   // 6) Çizimler + sinyaller
   for(int i = 0; i < total; i++)
     {
      BasisBuf[i]      = EMPTY_VALUE;
      UpperCloudHi[i]  = EMPTY_VALUE;
      UpperCloudLo[i]  = EMPTY_VALUE;
      LowerCloudHi[i]  = EMPTY_VALUE;
      LowerCloudLo[i]  = EMPTY_VALUE;
      BasisCloudHi[i]  = EMPTY_VALUE;
      BasisCloudLo[i]  = EMPTY_VALUE;
      MidUpperBuf[i]   = EMPTY_VALUE;
      MidLowerBuf[i]   = EMPTY_VALUE;
      StrongLongBuf[i] = EMPTY_VALUE;
      StrongShortBuf[i] = EMPTY_VALUE;
      WeakLongBuf[i]   = EMPTY_VALUE;
      WeakShortBuf[i]  = EMPTY_VALUE;

      if(!level_ok[i])
         continue;

      double fu = fbasis[i] + vol[i];
      double fl = fbasis[i] - vol[i];

      BasisBuf[i]     = fbasis[i];
      BasisColorBuf[i] = (close[i] > fbasis[i] ? 0.0 : 1.0);

      if(InpShowClouds)
        {
         UpperCloudHi[i] = uu[i];
         UpperCloudLo[i] = ul[i];
         LowerCloudHi[i] = ll[i];
         LowerCloudLo[i] = lu[i];
         BasisCloudHi[i] = fu;
         BasisCloudLo[i] = fl;
        }

      MidUpperBuf[i] = (fu + ul[i]) * 0.5;
      MidLowerBuf[i] = (fl + lu[i]) * 0.5;

     }

   // 7) crossover / crossunder olayları (i >= 1, iki bar da geçerli olmalı)
   for(int i = 1; i < total; i++)
     {
      if(!level_ok[i] || !level_ok[i - 1])
         continue;

      double c  = close[i];
      double cp = close[i - 1];

      bool cross_under_uu = (c < uu[i] && cp >= uu[i - 1]);
      bool cross_over_ll  = (c > ll[i] && cp <= ll[i - 1]);
      bool cross_under_ul = (c < ul[i] && cp >= ul[i - 1]);
      bool cross_over_lu  = (c > lu[i] && cp <= lu[i - 1]);

      if(cross_under_uu)
         StrongLongBuf[i] = high[i];
      if(cross_over_ll)
         StrongShortBuf[i] = low[i];
      if(cross_under_ul && !cross_under_uu)
         WeakLongBuf[i] = high[i];
      if(cross_over_lu && !cross_over_ll)
         WeakShortBuf[i] = low[i];
     }

   // 8) Yeni mumda alert (Pine alertcondition karşılığı)
   static datetime last_alert_bar = 0;
   if(InpAlerts && total >= 2 && !MQLInfoInteger(MQL_TESTER))
     {
      datetime closed_bar = time[total - 2];
      if(closed_bar != last_alert_bar)
        {
         last_alert_bar = closed_bar;
         int i = total - 2;
         if(i >= 1 && level_ok[i] && level_ok[i - 1])
           {
            double c  = close[i];
            double cp = close[i - 1];
            double fb = fbasis[i];
            string text = "";
            if(c > fb && cp <= fbasis[i - 1])
               text += "Bullish Trend Shift; ";
            if(c < fb && cp >= fbasis[i - 1])
               text += "Bearish Trend Shift; ";
            if(c < uu[i] && cp >= uu[i - 1])
               text += "Strong Long TP; ";
            if(c > ll[i] && cp <= ll[i - 1])
               text += "Strong Short TP; ";
            if(c < ul[i] && cp >= ul[i - 1] && !(c < uu[i] && cp >= uu[i - 1]))
               text += "Weak Long TP; ";
            if(c > lu[i] && cp <= lu[i - 1] && !(c > ll[i] && cp <= ll[i - 1]))
               text += "Weak Short TP; ";
            if(text != "")
               Alert(_Symbol, " ", EnumToString((ENUM_TIMEFRAMES)Period()), " | ", text,
                     TimeToString(closed_bar));
           }
        }
     }

   return rates_total;
  }
//+------------------------------------------------------------------+

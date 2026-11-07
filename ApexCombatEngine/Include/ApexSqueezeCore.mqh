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

#include "ApexTypes.mqh"

enum ENUM_APEX_SQZ_COLOR
  {
   APX_SQZ_NONE   = 0,
   APX_SQZ_LIME   = 1, // val > 0 ve yukseliyor
   APX_SQZ_GREEN  = 2, // val > 0 ve dusuyor
   APX_SQZ_RED    = 3, // val < 0 ve dusuyor
   APX_SQZ_MAROON = 4  // val < 0 ve yukseliyor
  };

enum ENUM_APEX_SQZ_STATE
  {
   APX_SQZ_UNKNOWN = 0,
   APX_SQZ_ON      = 1, // sqzOn  : BB Keltner icinde -> sikisma
   APX_SQZ_OFF     = 2, // sqzOff : BB Keltner disinda -> salinim
   APX_SQZ_NONE    = 3
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
         return APX_SQZ_UNKNOWN;

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

      if((lower_bb > lower_kc) && (upper_bb < upper_kc)) return APX_SQZ_ON;
      if((lower_bb < lower_kc) && (upper_bb > upper_kc)) return APX_SQZ_OFF;
      return APX_SQZ_NONE;
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
         m_sqz[i]    = (int)APX_SQZ_UNKNOWN;
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

//+------------------------------------------------------------------+
//|                                                ApexAnalytics.mqh |
//|  APEX COMBAT ENGINE - Katman 2: 5 Boyutlu Rejim Analizi           |
//|                                                                  |
//|   D1 SQUEEZE BASINCI  : sikisma suresi, salinim yonu, titreme     |
//|   D2 HURST USTELI     : trend kaliciligi (varyans-temelli H)      |
//|   D3 ATR VOL BANDI    : normalize volatilite z-skoru              |
//|   D4 HACIM PROFILI    : POC / VAH / VAL, denge, emilim, CVD       |
//|   D5 MOMENTUM TUREVI  : hiz (1. turev), ivme (2. turev), yorgunluk|
//|                                                                  |
//|  Bilesik: agirlikli oy + histerezis + guven skoru -> rejim        |
//+------------------------------------------------------------------+
#ifndef __APEX_ANALYTICS_MQH__
#define __APEX_ANALYTICS_MQH__ 1

#include "ApexTypes.mqh"
#include "ApexSqueezeCore.mqh"

#define APX_RELEASE_WINDOW 6   // salinimdan sonraki kac bar "atak" sayilir
#define APX_FLICKER_WINDOW 40  // sikisma titreme sayaci penceresi

void ApexResetSnapshot(SRegimeSnapshot &s)
  {
   s.regime      = (int)REGIME_BOOT;
   s.prev_regime = (int)REGIME_BOOT;
   s.posture     = (int)POSTURE_PEACE;
   s.bars_in_regime = 0;
   s.confidence  = 0.0;
   s.trend_dir   = 0;
   s.stamp       = 0;
   s.valid       = 0;
   for(int i = 0; i < 6; i++)
      s.score[i] = 0.0;

   s.sqz_state = 0; s.sqz_compress_bars = 0; s.bars_since_release = -1;
   s.release_dir = 0; s.sqz_energy = 0.0; s.sqz_flicker = 0;

   s.hurst = 0.5; s.persistence = (int)PERSIST_RANDOM;

   s.atr = 0.0; s.atr_pct = 0.0; s.atr_mean = 0.0; s.atr_std = 0.0;
   s.atr_z = 0.0; s.vol_band = (int)VOLBAND_NORMAL;

   s.poc = 0.0; s.vah = 0.0; s.val = 0.0; s.vp_pos = (int)VP_IN_VALUE;
   s.balance = 0.0; s.absorption = 0.0; s.cvd_slope = 0.0; s.vp_skew = 0.0;

   s.mom = 0.0; s.mom_z = 0.0; s.vel = 0.0; s.vel_z = 0.0;
   s.accel = 0.0; s.accel_z = 0.0; s.flip_rate = 0.0;
   s.fatigue = 0; s.vel_zero_cross = 0; s.mom_dir = 0;

   s.elasticity = 1.0; s.composite_heat = 0.0;
  }

class CApexAnalytics
  {
private:
   SApexConfig       m_cfg;
   double            m_atr_series[];
   double            m_vp_buckets[];
   int               m_regime;
   int               m_regime_bars;
   int               m_bars_seen;
   bool              m_ready;

   //------------------------------------------------------------------+
   double TrueRangeAt(const MqlRates &r[], const int i)
     {
      if(i < 1)
         return r[i].high - r[i].low;
      double tr1 = r[i].high - r[i].low;
      double tr2 = MathAbs(r[i].high - r[i - 1].close);
      double tr3 = MathAbs(r[i].low  - r[i - 1].close);
      return MathMax(tr1, MathMax(tr2, tr3));
     }

   void   LinFit(const double &x[], const double &y[], const int n, double &slope, double &intercept)
     {
      slope = 0.0;
      intercept = 0.0;
      if(n < 3)
         return;
      double sx = 0.0, sy = 0.0, sxx = 0.0, sxy = 0.0;
      for(int i = 0; i < n; i++)
        {
         sx  += x[i];
         sy  += y[i];
         sxx += x[i] * x[i];
         sxy += x[i] * y[i];
        }
      double den = n * sxx - sx * sx;
      if(MathAbs(den) < 1.0e-12)
        {
         slope = 0.0;
         intercept = (n > 0 ? sy / n : 0.0);
         return;
        }
      slope     = (n * sxy - sx * sy) / den;
      intercept = (sy - slope * sx) / n;
     }

   //------------------------------------------------------------------+
   //| D2: Varyans-temelli Hurst usteli                                 |
   //|   Var(log P(t+L) - log P(t)) ~ L^(2H)                            |
   //|   log Var  =  2H * log L  + c   ->  egim = 2H                    |
   //+------------------------------------------------------------------+
   double ComputeHurst(const MqlRates &r[], const int end_index, const int window, const int max_lag)
     {
      int start = end_index - window + 1;
      if(start < 1 || window < max_lag * 3 || window < 30)
         return 0.5;

      double lp[];
      if(ArrayResize(lp, window + 1) < window + 1)
         return 0.5;
      for(int i = 0; i <= window; i++)
        {
         double c = r[start + i].close;
         if(c <= 0.0)
            return 0.5;
         lp[i] = MathLog(c);
        }

      double xs[], ys[];
      if(ArrayResize(xs, max_lag) < max_lag) return 0.5;
      if(ArrayResize(ys, max_lag) < max_lag) return 0.5;

      int idx = 0;
      for(int lag = 2; lag <= max_lag; lag++)
        {
         double sum = 0.0;
         int    cnt = 0;
         for(int i = 0; i + lag <= window; i++)
           {
            double d = lp[i + lag] - lp[i];
            sum += d * d;
            cnt++;
           }
         if(cnt < 5)
            continue;
         double v = sum / cnt;
         if(v <= 0.0)
            continue;
         xs[idx] = MathLog((double)lag);
         ys[idx] = MathLog(v);
         idx++;
        }
      if(idx < 3)
         return 0.5;

      double slope = 0.0, icpt = 0.0;
      LinFit(xs, ys, idx, slope, icpt);
      double H = slope * 0.5;
      if(!MathIsValidNumber(H))
         return 0.5;
      return ApexClamp(H, 0.05, 0.95);
     }

   //------------------------------------------------------------------+
   //| D3: ATR serisi, ortalama/std ve z-skoru                          |
   //+------------------------------------------------------------------+
   void ComputeATR(const MqlRates &r[], const int end_index, SRegimeSnapshot &s)
     {
      int len = m_cfg.atr_band_len + m_cfg.atr_period + 2;
      int start = end_index - len + 1;
      if(start < 1)
        {
         s.atr = 0.0;
         return;
        }
      if(ArrayResize(m_atr_series, len) < len)
         return;

      for(int k = 0; k < len; k++)
        {
         int i = start + k;
         double sum = 0.0;
         int cnt = 0;
         for(int j = i - m_cfg.atr_period + 1; j <= i; j++)
           {
            if(j < 1)
               continue;
            sum += TrueRangeAt(r, j);
            cnt++;
           }
         m_atr_series[k] = (cnt > 0 ? sum / cnt : 0.0);
        }

      double mean = 0.0;
      for(int k = 0; k < len; k++)
         mean += m_atr_series[k];
      mean /= len;

      double var = 0.0;
      for(int k = 0; k < len; k++)
        {
         double d = m_atr_series[k] - mean;
         var += d * d;
        }
      double std = MathSqrt(var / len);

      s.atr      = m_atr_series[len - 1];
      s.atr_mean = mean;
      s.atr_std  = std;
      s.atr_z    = ApexZScore(s.atr, mean, std);

      double px = r[end_index].close;
      s.atr_pct = (px > 0.0 ? s.atr / px : 0.0);

      if(s.atr_z >= m_cfg.atr_z_explosive)     s.vol_band = (int)VOLBAND_EXPLOSIVE;
      else if(s.atr_z >= m_cfg.atr_z_expansion) s.vol_band = (int)VOLBAND_EXPANSION;
      else if(s.atr_z <= -0.75)                 s.vol_band = (int)VOLBAND_CRUSH;
      else                                      s.vol_band = (int)VOLBAND_NORMAL;
     }

   //------------------------------------------------------------------+
   //| D4: Hacim profili (POC / VAH / VAL) + likidite dagilimi          |
   //+------------------------------------------------------------------+
   void ComputeVolumeProfile(const MqlRates &r[], const int end_index, SRegimeSnapshot &s)
     {
      int look = m_cfg.vp_lookback;
      int start = end_index - look + 1;
      if(start < 0)
         start = 0;
      int cnt = end_index - start + 1;
      if(cnt < 10)
         return;

      double lo = r[start].low, hi = r[start].high;
      for(int i = start; i <= end_index; i++)
        {
         lo = MathMin(lo, r[i].low);
         hi = MathMax(hi, r[i].high);
        }
      double span = hi - lo;
      if(span <= 0.0)
         return;

      int    nb   = m_cfg.vp_buckets;
      double step = span / nb;
      if(ArrayResize(m_vp_buckets, nb) < nb)
         return;
      ArrayInitialize(m_vp_buckets, 0.0);

      double total_vol = 0.0;
      for(int i = start; i <= end_index; i++)
        {
         double v = (r[i].real_volume > 0 ? (double)r[i].real_volume : (double)r[i].tick_volume);
         if(v <= 0.0)
            v = 1.0; // hacimsiz semboller (bazi CFD'ler) icin esit agirlik
         total_vol += v;

         int b0 = (int)MathFloor((r[i].low - lo) / step);
         int b1 = (int)MathFloor((r[i].high - lo) / step);
         if(b0 < 0) b0 = 0;
         if(b1 >= nb) b1 = nb - 1;
         if(b1 < b0) b1 = b0;
         double share = v / (double)(b1 - b0 + 1);
         for(int b = b0; b <= b1; b++)
            m_vp_buckets[b] += share;
        }
      if(total_vol <= 0.0)
         return;

      // POC
      int poc_idx = 0;
      double best = -1.0;
      for(int b = 0; b < nb; b++)
        {
         if(m_vp_buckets[b] > best)
           {
            best = m_vp_buckets[b];
            poc_idx = b;
           }
        }

      // Deger alani: POC'tan disa dogru %va_pct hacim toplanana kadar
      double target = total_vol * m_cfg.va_pct;
      double acc = m_vp_buckets[poc_idx];
      int lo_idx = poc_idx, hi_idx = poc_idx;
      while(acc < target && (lo_idx > 0 || hi_idx < nb - 1))
        {
         double below = (lo_idx > 0 ? m_vp_buckets[lo_idx - 1] : -1.0);
         double above = (hi_idx < nb - 1 ? m_vp_buckets[hi_idx + 1] : -1.0);
         if(above >= below && hi_idx < nb - 1)
           {
            hi_idx++;
            acc += m_vp_buckets[hi_idx];
           }
         else if(lo_idx > 0)
           {
            lo_idx--;
            acc += m_vp_buckets[lo_idx];
           }
         else
            break;
        }

      s.poc = lo + (poc_idx + 0.5) * step;
      s.vah = lo + (hi_idx + 1.0) * step;
      s.val = lo + lo_idx * step;

      double px = r[end_index].close;
      if(px > s.vah)      s.vp_pos = (int)VP_ABOVE_VALUE;
      else if(px < s.val) s.vp_pos = (int)VP_BELOW_VALUE;
      else                s.vp_pos = (int)VP_IN_VALUE;

      // Denge: hacmin merkezdeki ucte birlik kisimda yogunlasmasi
      int third = (int)MathMax(1, nb / 3);
      int c0 = nb / 2 - third / 2;
      int c1 = c0 + third;
      if(c0 < 0) c0 = 0;
      if(c1 >= nb) c1 = nb - 1;
      double centre = 0.0;
      for(int b = c0; b <= c1; b++)
         centre += m_vp_buckets[b];
      s.balance = ApexSaturate(centre / total_vol);

      // Asimetri: POC ustu / alti hacim dengesi
      double above_v = 0.0, below_v = 0.0;
      for(int b = 0; b < nb; b++)
        {
         if(b > poc_idx) above_v += m_vp_buckets[b];
         if(b < poc_idx) below_v += m_vp_buckets[b];
        }
      s.vp_skew = ApexClamp((above_v - below_v) / total_vol, -1.0, 1.0);

      // Emilim (akilli para): dusuk menzil + yuksek hacim + uc kapanis
      int ab = 0, ab_cnt = 0;
      double atr_now = (s.atr > 0.0 ? s.atr : span / (double)cnt);
      for(int i = end_index - 9; i <= end_index; i++)
        {
         if(i < 1)
            continue;
         double v   = (r[i].real_volume > 0 ? (double)r[i].real_volume : (double)r[i].tick_volume);
         double avg = total_vol / (double)cnt;
         double rng = r[i].high - r[i].low;
         if(avg <= 0.0)
            continue;
         bool  tight  = (rng < 0.6 * atr_now);
         bool  heavy  = (v > 1.4 * avg);
         bool  at_edge= (r[i].close > r[i].low + 0.75 * rng) || (r[i].close < r[i].low + 0.25 * rng);
         ab_cnt++;
         if(tight && heavy && at_edge)
            ab++;
        }
      s.absorption = (ab_cnt > 0 ? ApexSaturate((double)ab / (double)ab_cnt) : 0.0);

      // CVD egimi: kumulatif hacim dengesi (yukari/down bar hacimleri)
      double up_v = 0.0, dn_v = 0.0;
      for(int i = start; i <= end_index; i++)
        {
         double v = (r[i].real_volume > 0 ? (double)r[i].real_volume : (double)r[i].tick_volume);
         if(v <= 0.0) v = 1.0;
         if(r[i].close > r[i].open) up_v += v;
         else if(r[i].close < r[i].open) dn_v += v;
        }
      s.cvd_slope = ApexClamp((up_v - dn_v) / (up_v + dn_v + 1.0e-12), -1.0, 1.0);
     }

   //------------------------------------------------------------------+
   //| D1: Squeeze basinci (sikisma / salinim / titreme)                |
   //+------------------------------------------------------------------+
   void ComputeSqueezeDim(SRegimeSnapshot &s)
     {
      int last = g_sqz_main.LastClosed();
      if(last < 1)
         return;

      s.sqz_state = g_sqz_main.Sqz(last);

      // Geriye dogru kesintisiz sikisma suresi
      int bars = 0;
      for(int i = last; i >= 1; i--)
        {
         if(g_sqz_main.Sqz(i) == (int)APX_SQZST_ON)
            bars++;
         else
            break;
        }
      s.sqz_compress_bars = bars;
      s.sqz_energy = ApexSaturate((double)bars / 12.0);

      // Son ON -> OFF salinimi
      s.bars_since_release = -1;
      s.release_dir = 0;
      for(int i = last; i >= 1; i--)
        {
         int cur = g_sqz_main.Sqz(i);
         int prv = g_sqz_main.Sqz(i - 1);
         if(cur != (int)APX_SQZST_ON && prv == (int)APX_SQZST_ON)
           {
            s.bars_since_release = last - i;
            // Salinim anindaki momentum yonu
            double m1 = g_sqz_main.Mom(i);
            double m2 = g_sqz_main.Mom(i - 1);
            double m  = (MathAbs(m1) >= MathAbs(m2) ? m1 : m2);
            double sd = g_sqz_main.StdDev(i, 80);
            s.release_dir = (MathAbs(m) > 0.35 * sd ? ApexSign(m) : 0);
            break;
           }
        }

      // Titreme (ON/OFF salinimi) - tuzak gostergesi
      int flick = 0;
      int from = (int)MathMax(1, last - APX_FLICKER_WINDOW);
      for(int i = from + 1; i <= last; i++)
        {
         int cur = g_sqz_main.Sqz(i);
         int prv = g_sqz_main.Sqz(i - 1);
         if(cur == (int)APX_SQZST_UNKNOWN || prv == (int)APX_SQZST_UNKNOWN)
            continue;
         bool cur_on = (cur == (int)APX_SQZST_ON);
         bool prv_on = (prv == (int)APX_SQZST_ON);
         if(cur_on != prv_on)
            flick++;
        }
      s.sqz_flicker = flick;
     }

   //------------------------------------------------------------------+
   //| D5: Momentum turevleri                                           |
   //+------------------------------------------------------------------+
   void ComputeMomentumDim(SRegimeSnapshot &s)
     {
      int last = g_sqz_main.LastClosed();
      if(last < m_cfg.deriv_len + 2 || !g_sqz_main.Valid(last))
         return;

      int k = m_cfg.deriv_len;
      s.mom     = g_sqz_main.Mom(last);
      double sd = g_sqz_main.StdDev(last, 80);
      s.mom_z   = ApexSafeDiv(s.mom, sd, 0.0);
      s.mom_dir = (MathAbs(s.mom) > 0.3 * sd ? ApexSign(s.mom) : 0);

      s.vel   = g_sqz_main.Velocity(last, k);
      s.accel = g_sqz_main.Acceleration(last, k);

      // Hiz/ivme icin olcek: momentum std / k
      double vscale = ApexSafeDiv(sd, (double)k, 0.0);
      s.vel_z   = ApexSafeDiv(s.vel, vscale, 0.0);
      s.accel_z = ApexSafeDiv(s.accel, (vscale > 0.0 ? vscale * 0.5 : 0.0), 0.0);
      s.flip_rate = g_sqz_main.FlipRate(last, 30);

      double v_prev = g_sqz_main.Velocity(last - 1, k);
      s.vel_zero_cross = (ApexSign(s.vel) != 0 && ApexSign(v_prev) != 0 &&
                          ApexSign(s.vel) != ApexSign(v_prev)) ? 1 : 0;

      // Yorgunluk: momentum hala buyuk ama hiz yon degistirmis / dumduz
      double vel_max = 0.0;
      for(int i = 1; i <= 8; i++)
         vel_max = MathMax(vel_max, MathAbs(g_sqz_main.Velocity(last - i, k)));
      bool exhausted = (MathAbs(s.mom_z) > 0.9) && (MathAbs(s.vel) < 0.35 * vel_max);
      bool opposed   = (ApexSign(s.vel) != 0 && ApexSign(s.mom) != 0 && ApexSign(s.vel) != ApexSign(s.mom));
      s.fatigue = (exhausted || opposed || s.vel_zero_cross == 1) ? 1 : 0;
     }

   //------------------------------------------------------------------+
   //| Oylama: 5 boyutun rejim uyelikleri agirlikli olarak toplanir     |
   //+------------------------------------------------------------------+
   void ScoreRegimes(SRegimeSnapshot &s)
     {
      double m_compress = s.sqz_energy;
      double m_release  = (s.bars_since_release >= 0 && s.bars_since_release <= APX_RELEASE_WINDOW)
                          ? (1.0 - (double)s.bars_since_release / (double)APX_RELEASE_WINDOW) : 0.0;
      double m_trend_p  = ApexNormRange(s.hurst, m_cfg.hurst_mr, m_cfg.hurst_trend);
      double m_mr_p     = 1.0 - m_trend_p;
      double m_vol_exp  = ApexNormRange(s.atr_z, -0.25, m_cfg.atr_z_explosive);
      double m_vol_calm = 1.0 - m_vol_exp;
      double m_out_val  = (s.vp_pos == (int)VP_IN_VALUE) ? 0.0 : 1.0;
      double m_in_val   = 1.0 - m_out_val;
      double m_mom_str  = ApexNormRange(MathAbs(s.mom_z), 0.4, 2.0);
      double m_mom_weak = 1.0 - m_mom_str;
      double m_flip     = ApexNormRange(s.flip_rate, 0.22, 0.60);
      double m_flick    = ApexNormRange((double)s.sqz_flicker, 2.0, 9.0);

      // Yon hizasi: salinim yonu, momentum yonu, deger alani tarafi, CVD
      int votes = 0, agree = 0;
      int ref = s.release_dir;
      if(ref == 0) ref = s.mom_dir;
      if(ref != 0)
        {
         votes++; if(s.mom_dir == ref) agree++;
         votes++; if(s.vp_pos == ref)  agree++;
         votes++; if(ApexSign(s.cvd_slope) == ref) agree++;
         votes++; if(ApexSign(s.vp_skew) == ref)  agree++;
        }
      double m_align = (votes > 0 ? (double)agree / (double)votes : 0.0);

      double s_acc =
         34.0 * m_compress
       + 16.0 * m_vol_calm
       + 14.0 * m_in_val
       + 18.0 * s.absorption
       + 12.0 * m_mom_weak
       +  8.0 * s.balance
       - 25.0 * m_release
       - 18.0 * m_vol_exp;

      double s_brk =
         40.0 * m_release
       + 22.0 * m_vol_exp
       + 20.0 * m_out_val
       + 22.0 * m_trend_p
       + 18.0 * m_mom_str
       + 20.0 * m_align
       - 20.0 * m_mom_weak
       - 12.0 * m_flip;

      double s_mr =
         30.0 * m_mr_p
       + 18.0 * m_in_val
       + 20.0 * s.balance
       + 14.0 * m_mom_weak
       + 16.0 * m_flip
       + 12.0 * m_vol_calm
       - 22.0 * m_release
       - 15.0 * m_vol_exp
       - 10.0 * m_mom_str;

      double s_trap =
         38.0 * m_vol_exp
       + 26.0 * m_flip
       + 14.0 * (1.0 - m_align)
       + 12.0 * m_out_val
       + 10.0 * m_flick
       - 25.0 * m_vol_calm
       - 10.0 * m_trend_p;

      s.score[(int)REGIME_ACCUMULATION]    = MathMax(0.0, s_acc);
      s.score[(int)REGIME_BREAKOUT_ATTACK] = MathMax(0.0, s_brk);
      s.score[(int)REGIME_MEAN_REVERSION]  = MathMax(0.0, s_mr);
      s.score[(int)REGIME_VOLATILITY_TRAP] = MathMax(0.0, s_trap);
      s.score[(int)REGIME_DEFENSE_LOCK]    = 0.0; // yalnizca sert tetikle acilir

      double total = s.score[(int)REGIME_ACCUMULATION] + s.score[(int)REGIME_BREAKOUT_ATTACK]
                   + s.score[(int)REGIME_MEAN_REVERSION] + s.score[(int)REGIME_VOLATILITY_TRAP];
      if(total > 1.0)
        {
         double best = 0.0, second = 0.0;
         for(int i = 1; i <= 4; i++)
           {
            if(s.score[i] > best) { second = best; best = s.score[i]; }
            else if(s.score[i] > second) { second = s.score[i]; }
           }
         s.confidence = ApexSaturate((best - second) / MathMax(best, 1.0));
        }
      else
         s.confidence = 0.0;

      s.composite_heat = ApexSaturate(0.35 * m_vol_exp + 0.30 * m_flip +
                                      0.20 * (1.0 - m_align) + 0.15 * m_flick);
     }

   //------------------------------------------------------------------+
   int ArgBest(SRegimeSnapshot &s)
     {
      int best_i = (int)REGIME_MEAN_REVERSION;
      double best_v = -1.0e18;
      for(int i = 1; i <= 4; i++)
        {
         if(s.score[i] > best_v)
           {
            best_v = s.score[i];
            best_i = i;
           }
        }
      return best_i;
     }

   void ApplyHysteresis(SRegimeSnapshot &s)
     {
      int best = ArgBest(s);

      if(m_bars_seen < m_cfg.boot_bars)
        {
         m_regime = (int)REGIME_BOOT;
         m_regime_bars++;
         s.regime = m_regime;
         s.bars_in_regime = m_regime_bars;
         return;
        }

      if(best == m_regime)
        {
         m_regime_bars++;
        }
      else
        {
         double cur_score = s.score[m_regime];
         double new_score = s.score[best];
         // Histerezis: yeni rejim, mevcut rejimi belirgin farkla yenmeli
         if(new_score >= cur_score + (double)m_cfg.regime_margin &&
            m_regime_bars >= m_cfg.regime_persistence)
           {
            m_regime = best;
            m_regime_bars = 0;
            PrintFormat("[APEX:REGIME] GECIS -> %s (skor yeni=%.1f eski=%.1f guven=%.2f)",
                        ApexRegimeName(m_regime), new_score, cur_score, s.confidence);
           }
         else
           {
            m_regime_bars++;
           }
        }
      s.regime = m_regime;
      s.bars_in_regime = m_regime_bars;
     }

public:
                     CApexAnalytics()
     {
      m_regime      = (int)REGIME_BOOT;
      m_regime_bars = 0;
      m_bars_seen   = 0;
      m_ready       = false;
      ArrayResize(m_atr_series, 0);
      ArrayResize(m_vp_buckets, 0);
     }
                    ~CApexAnalytics() { }

   void Init(const SApexConfig &cfg)
     {
      m_cfg = cfg;
      m_regime = (int)REGIME_BOOT;
      m_regime_bars = 0;
      m_bars_seen = 0;
      ArrayResize(m_atr_series, 0);
      ArrayResize(m_vp_buckets, 0);
      m_ready = true;
     }

   void ForceRegime(const int regime)
     {
      if(m_regime == regime)
         return;
      m_regime = regime;
      m_regime_bars = 0;
     }

   int  CurrentRegime() { return m_regime; }
   int  RegimeBars()    { return m_regime_bars; }
   void CountBar()      { m_bars_seen++; }

   //+------------------------------------------------------------------+
   //| ANA GIRIS: 5 boyutlu rejim tespiti                               |
   //+------------------------------------------------------------------+
   bool DetectAdvancedMarketRegime(SRegimeSnapshot &s)
     {
      ApexResetSnapshot(s);
      if(!m_ready || !g_sqz_main.Ready())
         return false;

      int last = g_sqz_main.LastClosed();
      if(last < 60)
         return false;

      // --- D1 ---
      ComputeSqueezeDim(s);

      // --- D2 --- Hurst (ana TF'in ustune baglam TF'i de eklenir)
      double h_main = ComputeHurst(g_sqz_main.m_rates, last, m_cfg.hurst_window, m_cfg.hurst_max_lag);
      double h_ctx  = h_main;
      int  c_last = g_sqz_ctx.LastClosed();
      if(c_last >= m_cfg.hurst_window)
         h_ctx = ComputeHurst(g_sqz_ctx.m_rates, c_last, m_cfg.hurst_window, m_cfg.hurst_max_lag);
      s.hurst = ApexClamp(0.65 * h_main + 0.35 * h_ctx, 0.05, 0.95);
      if(s.hurst >= m_cfg.hurst_trend)      s.persistence = (int)PERSIST_TREND;
      else if(s.hurst <= m_cfg.hurst_mr)    s.persistence = (int)PERSIST_MEAN_REVERT;
      else                                  s.persistence = (int)PERSIST_RANDOM;

      // --- D3 ---
      ComputeATR(g_sqz_main.m_rates, last, s);

      // --- D4 ---
      ComputeVolumeProfile(g_sqz_main.m_rates, last, s);

      // --- D5 ---
      ComputeMomentumDim(s);

      // --- Bilesik ---
      s.elasticity = ApexClamp(ApexSafeDiv(s.atr, s.atr_mean, 1.0), 0.5, 2.5);

      ScoreRegimes(s);
      ApplyHysteresis(s);

      // --- Trend yonu ve durus ---
      int dir = 0;
      if(s.regime == (int)REGIME_BREAKOUT_ATTACK)
        {
         if(s.release_dir != 0)      dir = s.release_dir;
         else if(s.mom_dir != 0)     dir = s.mom_dir;
         else if(s.vp_pos != 0)      dir = s.vp_pos;
         else                        dir = ApexSign(s.cvd_slope);
        }
      s.trend_dir = dir;

      switch((E_APEX_REGIME)s.regime)
        {
         case REGIME_BOOT:            s.posture = (int)POSTURE_PEACE;    break;
         case REGIME_ACCUMULATION:    s.posture = (int)POSTURE_SKIRMISH; break;
         case REGIME_BREAKOUT_ATTACK: s.posture = (int)POSTURE_ATTACK;   break;
         case REGIME_MEAN_REVERSION:  s.posture = (int)POSTURE_SKIRMISH; break;
         case REGIME_VOLATILITY_TRAP: s.posture = (int)POSTURE_SKIRMISH; break;
         case REGIME_DEFENSE_LOCK:    s.posture = (int)POSTURE_SHIELD;   break;
        }

      s.stamp = TimeCurrent();
      s.valid = 1;
      return true;
     }
  };

CApexAnalytics g_analytics;

#endif
//+------------------------------------------------------------------+

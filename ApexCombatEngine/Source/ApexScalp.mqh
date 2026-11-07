//+------------------------------------------------------------------+
//|                                                    ApexScalp.mqh  |
//|  APEX COMBAT ENGINE - Katman 3: Hibrit Scalp + Savunma Kalkani    |
//|                                                                  |
//|  IKI AYRI SAVAS KATMANI TEK CATP ALTINDA:                         |
//|   A) MICRO-SCALP ENGINE: squeeze momentum alt dalgalanmalarinda   |
//|      (histogramin kendi icindeki mikro tepe/dip donusleri) hizli  |
//|      mikro pozisyonlar acip kapatarak ana grid kârini katlar.     |
//|   B) DEFENSE SHIELD: drawdown kritik esige ulasinca veya rejim    |
//|      STATE_DEFENSE_LOCK olunca tum riskli bacaklar sentetik       |
//|      olarak kilitlenir (delta notr), zarar dondurulur.            |
//+------------------------------------------------------------------+
#ifndef __APEX_SCALP_MQH__
#define __APEX_SCALP_MQH__ 1

#include "ApexTypes.mqh"
#include "ApexTrade.mqh"
#include "ApexAnalytics.mqh"
#include "ApexRisk.mqh"

struct SScalpTrack
  {
   ulong    ticket;
   int      side;
   double   lot;
   double   tp;
   double   sl;
   double   entry;
   datetime open_time;
   double   mfe;
  };

class CApexScalp
  {
private:
   SApexConfig   m_cfg;
   SScalpTrack   m_track[];
   datetime      m_last_scalp_bar;
   datetime      m_last_scalp_entry;
   int           m_scalp_bar_count;
   bool          m_locked;
   datetime      m_lock_time;
   int           m_lock_bar;
   double        m_lock_dd;
   double        m_lock_equity;
   int           m_lock_reason;
   double        m_lock_net_lots;
   double        m_hedge_pnl;
   int           m_lock_bars;
   string        m_action;
   bool          m_hedging_account;

   //------------------------------------------------------------------+
   //| Mikro-scalp yonu: rejime gore ruzgarla veya kenarlardan doner   |
   //+------------------------------------------------------------------+
   int    ScalpBias(const SRegimeSnapshot &s, const double price, const int pivot_dir)
     {
      switch((E_APEX_REGIME)s.regime)
        {
         case REGIME_BREAKOUT_ATTACK:
            // Sadece trend yonunde: ruzgar arkadan
            if(s.trend_dir != 0 && pivot_dir == s.trend_dir)
               return s.trend_dir;
            return 0;

         case REGIME_MEAN_REVERSION:
            // Deger alani kenarlarindan fade (donus avi)
            if(s.vah > 0.0 && price >= s.vah - 0.15 * s.atr && pivot_dir < 0)
               return -1;
            if(s.val > 0.0 && price <= s.val + 0.15 * s.atr && pivot_dir > 0)
               return 1;
            return 0;

         case REGIME_ACCUMULATION:
            // Gizli toplanma: sadece momentum yonuyle, yarim boyut
            if(pivot_dir == s.mom_dir && s.mom_dir != 0)
               return s.mom_dir;
            return 0;

         default:
            return 0;   // tuzak / kilit / boot: scalp yok
        }
     }

   double ScalpLot(const SRegimeSnapshot &s, const double sl_dist)
     {
      double lot = m_cfg.base_lot * m_cfg.scalp_lot_mult;
      if(s.regime == (int)REGIME_ACCUMULATION)
         lot *= 0.5;
      if(s.composite_heat > 0.6)
         lot *= 0.5;
      double cap = m_cfg.base_lot * m_cfg.scalp_lot_mult;
      lot = g_risk.RiskLotCapped(sl_dist, lot, g_risk.SizeMultiplier(), MathMin(cap, lot));
      lot = g_risk.ExposureCap(lot, m_cfg.max_total_lots);
      return g_exec.NormVolume(lot);
     }

   //------------------------------------------------------------------+
   //| Acik mikro pozisyonlarin tick bazli yonetimi                    |
   //+------------------------------------------------------------------+
   void ManageOpenScalps(const SRegimeSnapshot &s, const double bid, const double ask)
     {
      g_exec.RebuildBook();

      // Deftere gore izleme listesini yenile (self-healing)
      int n = 0;
      SScalpTrack keep[];
      for(int i = 0; i < g_exec.BookSize(); i++)
        {
         SBookEntry e;
         if(!g_exec.BookAt(i, e))
            continue;
         if(e.role != (int)ROLE_SCALP)
            continue;
         SScalpTrack t;
         t.ticket    = e.ticket;
         t.side      = e.side;
         t.lot       = e.lot;
         t.entry     = e.entry;
         t.sl        = e.sl;
         t.tp        = e.tp;
         t.open_time = e.time;
         t.mfe       = 0.0;

         // Onceki kayitta MFE varsa tasi
         for(int k = 0; k < ArraySize(m_track); k++)
            if(m_track[k].ticket == t.ticket)
              {
               t.mfe = m_track[k].mfe;
               break;
              }
         double cur = (e.side > 0 ? bid : ask);
         double pl  = (cur - e.entry) * e.side;
         if(pl > t.mfe)
            t.mfe = pl;

         if(ArrayResize(keep, n + 1) >= n + 1)
            keep[n] = t;
         n++;
        }
      ArrayResize(m_track, n);
      for(int i = 0; i < n; i++)
         m_track[i] = keep[i];

      int span = (int)MathMax(2, m_cfg.scalp_pivot);
      int s_last = g_sqz_scalp.LastClosed();
      double vel_now = (s_last > span ? g_sqz_scalp.Velocity(s_last, span) : 0.0);
      double vel_prev= (s_last > span + 1 ? g_sqz_scalp.Velocity(s_last - 1, span) : 0.0);
      bool   vel_flip = (ApexSign(vel_now) != 0 && ApexSign(vel_prev) != 0 &&
                         ApexSign(vel_now) != ApexSign(vel_prev));

      int bars_held = 0;
      for(int i = 0; i < ArraySize(m_track); i++)
        {
         SScalpTrack t = m_track[i];
         double cur = (t.side > 0 ? bid : ask);
         double pl  = (cur - t.entry) * t.side;
         double target = MathAbs(t.tp - t.entry);
         if(target <= 0.0)
            target = g_exec.Point() * 50.0;

         bool close_it = false;
         string why = "";

         // 1) Momentum hizi tersine dondu -> mikro is derhal kapanir
         if(vel_flip && ApexSign(vel_now) != t.side)
           {
            close_it = true;
            why = "mikro momentum hizi ters dondu";
           }
         // 2) Zaman stopu: scalp TF'inde cok uzun sure tutuldu
         if(!close_it && m_cfg.scalp_max_bars > 0)
           {
            bars_held = BarsElapsed(m_cfg.tf_scalp, t.open_time);
            if(bars_held > m_cfg.scalp_max_bars)
              {
               close_it = true;
               why = StringFormat("zaman stopu (%d bar)", bars_held);
              }
           }
         // 3) Kârdan geri verme: MFE'nin %60'i geri verildiyse cik
         if(!close_it && t.mfe > g_exec.Point() * 20.0 && pl < 0.4 * t.mfe)
           {
            close_it = true;
            why = "MFE geri verildi";
           }
         // 4) Rejim savunmaya gectiyse tum mikro isler kapanir
         if(!close_it && (s.regime == (int)REGIME_DEFENSE_LOCK || g_risk.LockRequired()))
           {
            close_it = true;
            why = "savunma kilidi";
           }

         if(close_it)
           {
            double pnl_money = pl * t.lot * g_exec.PointValue();
            if(g_exec.CloseTicket(t.ticket, "SCALP: " + why))
              {
               g_risk.NoteClose(pnl_money, (int)ROLE_SCALP);
               m_action = StringFormat("Mikro-scalp kapandi: %s", why);
              }
            continue;
           }

         // 5) Izleyen stop: hedefin yarisindan sonra basa-bas + kilit
         if(pl > 0.5 * target && target > 0.0)
           {
            double be = g_exec.NormPrice(t.entry + t.side * g_exec.Point() * 2.0, t.side);
            bool improve = (t.side > 0) ? (be > t.sl) : (t.sl <= 0.0 || be < t.sl);
            if(improve)
               g_exec.ModifyStops(t.ticket, be, t.tp);
           }
        }
     }

   int BarsElapsed(const ENUM_TIMEFRAMES tf, const datetime from)
     {
      if(from <= 0)
         return 0;
      int sec = PeriodSeconds(tf);
      if(sec <= 0)
         return 0;
      return (int)((TimeCurrent() - from) / sec);
     }

   //------------------------------------------------------------------+
   //| Yeni mikro islem arama                                          |
   //+------------------------------------------------------------------+
   void TryOpenScalp(const SRegimeSnapshot &s, const double bid, const double ask)
     {
      if(!m_cfg.scalp_enabled)
         return;
      if(!g_sqz_scalp.Ready())
         return;

      int span = (int)MathMax(2, m_cfg.scalp_pivot);
      int s_last = g_sqz_scalp.LastClosed();
      int pivot_at = s_last - span;
      if(pivot_at < span + 2)
         return;

      int pivot = g_sqz_scalp.MicroPivot(pivot_at, span, 0.45);
      if(pivot == 0)
         return;

      double price = (pivot > 0 ? ask : bid);
      int dir = ScalpBias(s, price, pivot);
      if(dir == 0)
         return;

      int open_now = 0;
      for(int i = 0; i < ArraySize(m_track); i++)
         if(m_track[i].side == dir)
            open_now++;
      if(open_now >= m_cfg.scalp_max_open)
         return;

      // Soguma suresi
      if(m_cfg.scalp_cooldown_sec > 0 &&
         (TimeCurrent() - m_last_scalp_entry) < m_cfg.scalp_cooldown_sec)
         return;

      if(!g_risk.AllowNew((int)ROLE_SCALP, s.regime))
         return;

      // Geri cekilme kontrolu: mikro giris icin fiyat son uc bar asiri
      // noktasindan cok uzaklasmamis olmali (kovalamaca yasak)
      double swing = 0.0;
      for(int i = s_last; i > s_last - 3 && i >= 0; i--)
        {
         if(dir > 0) swing = (swing == 0.0 ? g_sqz_scalp.Low(i) : MathMin(swing, g_sqz_scalp.Low(i)));
         else        swing = (swing == 0.0 ? g_sqz_scalp.High(i) : MathMax(swing, g_sqz_scalp.High(i)));
        }
      double pullback = (s.atr > 0.0 ? s.atr * m_cfg.scalp_pullback_atr : g_exec.Point() * 100.0);
      if(swing > 0.0 && MathAbs(price - swing) > pullback)
         return;

      // Hedef / stop mesafeleri
      double tp_dist = (m_cfg.scalp_tp_points > 0 ? m_cfg.scalp_tp_points * g_exec.Point()
                                                  : (s.atr > 0.0 ? s.atr * 0.45 : g_exec.Point() * 100.0));
      double sl_dist = (m_cfg.scalp_sl_points > 0 ? m_cfg.scalp_sl_points * g_exec.Point()
                                                  : (s.atr > 0.0 ? s.atr * 0.35 : g_exec.Point() * 80.0));
      tp_dist = MathMax(tp_dist, g_exec.MinStopDist());
      sl_dist = MathMax(sl_dist, g_exec.MinStopDist());
      tp_dist = MathMax(tp_dist, g_exec.SpreadPoints() * g_exec.Point() * 3.0);

      double lot = ScalpLot(s, sl_dist);
      if(lot <= 0.0)
         return;

      double entry = (dir > 0 ? ask : bid);
      double sl = g_exec.NormPrice(entry - dir * sl_dist, -dir);
      double tp = g_exec.NormPrice(entry + dir * tp_dist, dir);

      ulong tk = g_exec.OpenMarket(dir, lot, sl, tp, (int)ROLE_SCALP, 0);
      if(tk != 0)
        {
         m_last_scalp_entry = TimeCurrent();
         m_action = StringFormat("Mikro-scalp %s lot=%.2f (tp=%.0fpt sl=%.0fpt)",
                                 ApexSideName(dir), lot, tp_dist / g_exec.Point(), sl_dist / g_exec.Point());
         if(m_cfg.verbose_log)
            PrintFormat("[APEX:SCALP] %s mikro islem acildi lot=%.2f | rejim=%s | pivot=%+d",
                        ApexSideName(dir), lot, ApexRegimeShort(s.regime), pivot);
        }
     }

   //------------------------------------------------------------------+
   //| SAVUNMA KALKANI (Delta-Notr Kilitleme)                          |
   //+------------------------------------------------------------------+
   double ExposureNetLots()
     {
      g_exec.RebuildBook();
      double net = 0.0;
      for(int i = 0; i < g_exec.BookSize(); i++)
        {
         SBookEntry e;
         if(!g_exec.BookAt(i, e))
            continue;
         if(e.role == (int)ROLE_HEDGE)
            continue;
         net += e.side * e.lot;
        }
      return net;
     }

   void EngageLock(const SRegimeSnapshot &s, const int reason)
     {
      if(m_locked)
         return;

      // 1) Tum bekleyen emirler iptal: yeni risk alinmayacak
      g_exec.DeleteOrdersRole((int)ROLE_GRID);

      // 2) Mikro isler kapatilir (kilitte sadece kalkan yasar)
      g_exec.CloseRole((int)ROLE_SCALP, "SAVUNMA KILIDI");

      // 3) Sentetik kilit: net pozisyonun karsisina kalkan
      double net = ExposureNetLots();
      double lots = MathAbs(net) * ApexClamp(m_cfg.hedge_ratio, 0.0, 1.0);
      lots = g_exec.NormVolume(lots);

      if(m_hedging_account && lots >= g_exec.LotMin() && MathAbs(net) >= g_exec.LotMin())
        {
         int side = (net > 0 ? -1 : 1);
         if(g_exec.CanAfford(lots, 300.0))
           {
            ulong tk = g_exec.OpenMarket(side, lots, 0.0, 0.0, (int)ROLE_HEDGE, 0);
            if(tk != 0)
               PrintFormat("[APEX:SHIELD] KALKAN KURULDU: net=%.2f lot -> karsisina %.2f lot %s",
                           net, lots, ApexSideName(side));
           }
         else
            Print("[APEX:SHIELD] UYARI: marjin yetersiz, kalkan kurulamadi - sadece dondurma modu.");
        }
      else if(!m_hedging_account && MathAbs(net) >= g_exec.LotMin())
        {
         // Netting hesap: karsit pozisyon acilamaz -> zararli bacaklar kapatilir
         Print("[APEX:SHIELD] Netting hesap: sentetik kilit yerine marjin azaltma uygulaniyor.");
         ReduceExposure(s);
        }

      m_locked       = true;
      m_lock_time    = TimeCurrent();
      m_lock_bar     = 0;
      m_lock_dd      = g_risk.DrawdownPct();
      m_lock_equity  = AccountInfoDouble(ACCOUNT_EQUITY);
      m_lock_reason  = reason;
      m_lock_net_lots= net;
      m_lock_bars    = 0;
      m_action       = "SAVUNMA KILIDI: delta notr kalkan devrede";
     }

   void DisengageLock(const string why)
     {
      if(!m_locked)
         return;
      g_exec.CloseRole((int)ROLE_HEDGE, "KILIT ACILDI: " + why);
      m_locked = false;
      m_lock_bars = 0;
      m_action = "KILIT ACILDI: " + why;
      PrintFormat("[APEX:SHIELD] Kilit acildi (%s). Normal operasyona donuluyor.", why);
     }

   // Marjin seviyesi duserken en kârli bacaklari kapatarak nefes aldirir
   void ReduceExposure(const SRegimeSnapshot &s)
     {
      g_exec.RebuildBook();
      ulong tk[];
      double pl[];
      int cnt = 0;
      for(int i = 0; i < g_exec.BookSize(); i++)
        {
         SBookEntry e;
         if(!g_exec.BookAt(i, e))
            continue;
         if(e.role == (int)ROLE_HEDGE)
            continue;
         int c = cnt;
         if(ArrayResize(tk, c + 1) < c + 1) break;
         if(ArrayResize(pl, c + 1) < c + 1) break;
         tk[c] = e.ticket;
         pl[c] = e.profit;
         cnt++;
        }
      for(int a = 0; a < cnt - 1; a++)
         for(int b = a + 1; b < cnt; b++)
            if(pl[b] > pl[a])
              {
               double tp = pl[a]; pl[a] = pl[b]; pl[b] = tp;
               ulong   tt = tk[a]; tk[a] = tk[b]; tk[b] = tt;
              }
      int closed = 0;
      for(int i = 0; i < cnt && g_exec.MarginLevelPct() < 500.0; i++)
        {
         g_exec.CloseTicket(tk[i], "MARJIN RAHATLATMA");
         closed++;
        }
      if(closed > 0)
         m_action = StringFormat("Marjin rahatlatma: %d bacak kapatildi", closed);
     }

   void ManageLock(const SRegimeSnapshot &s)
     {
      m_lock_bars++;

      // --- Kalkan bakiyesi ---
      m_hedge_pnl = g_exec.BasketProfit((int)ROLE_HEDGE, 0);

      // --- Marjin nefes borusu ---
      if(g_exec.MarginLevelPct() < 350.0)
         ReduceExposure(s);

      // --- BLACK kademe: kontrollu geri cekilme ---
      if(g_risk.LiquidationRequired() && m_cfg.allow_full_liquidation)
        {
         PrintFormat("[APEX:SHIELD] KONTROLLU GERI CEKILME: DD=%.2f%% - tum pozisyonlar kapatiliyor.",
                     g_risk.DrawdownPct());
         g_exec.DeleteOrdersRole(-1);
         g_exec.CloseRole(-1, "KILL-SWITCH: kontrollu geri cekilme");
         DisengageLock("kill-switch sonrasi tasfiye");
         return;
        }

      // --- Kalkan zarari tavan asarsa: ters bacaklar kapatilarak notrluk korunur
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_cfg.hedge_max_loss_pct > 0.0 && eq > 0.0 &&
         MathAbs(m_hedge_pnl) > m_cfg.hedge_max_loss_pct * 0.01 * eq)
        {
         PrintFormat("[APEX:SHIELD] Kalkan zarari tavan asildi (%.2f). Kademeli tasfiye.", m_hedge_pnl);
         ReduceExposure(s);
        }

      // --- Kilit acma kosullari (hepsi birlikte) ---
      bool dd_ok   = (g_risk.DrawdownPct() <= MathMax(0.0, m_lock_dd - m_cfg.unlock_recovery));
      bool cool_ok = (m_lock_bars >= m_cfg.lock_cooldown_bars);
      bool vol_ok  = (s.atr_z <= m_cfg.atr_z_expansion);
      bool tier_ok = !g_risk.LockRequired();
      bool reg_ok  = (s.regime != (int)REGIME_DEFENSE_LOCK);

      if(cool_ok && tier_ok && reg_ok && vol_ok && (dd_ok || m_lock_bars > m_cfg.lock_cooldown_bars * 3))
         DisengageLock(StringFormat("DD %.2f%% -> %.2f%%, ATRz=%.2f, %d bar soguma",
                                    m_lock_dd, g_risk.DrawdownPct(), s.atr_z, m_lock_bars));
     }

public:
                     CApexScalp()
     {
      m_last_scalp_bar   = 0;
      m_last_scalp_entry = 0;
      m_scalp_bar_count  = 0;
      m_locked           = false;
      m_lock_time        = 0;
      m_lock_bar         = 0;
      m_lock_dd          = 0.0;
      m_lock_equity      = 0.0;
      m_lock_reason      = 0;
      m_lock_net_lots    = 0.0;
      m_hedge_pnl        = 0.0;
      m_lock_bars        = 0;
      m_hedging_account  = true;
      m_action           = "";
      ArrayResize(m_track, 0);
     }
                    ~CApexScalp() { }

   void Init(const SApexConfig &cfg)
     {
      m_cfg = cfg;
      m_hedging_account = (AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
      ArrayResize(m_track, 0);
      m_locked = false;
     }

   bool   Locked()        { return m_locked; }
   int    LockBars()      { return m_lock_bars; }
   double HedgePnL()      { return m_hedge_pnl; }
   double LockedNetLots() { return m_lock_net_lots; }
   string Action()        { return m_action; }
   int    ScalpCount()    { return ArraySize(m_track); }

   //+------------------------------------------------------------------+
   //| ANA GIRIS: Mikro-scalp + hedge kalkani                           |
   //| Tick hizinda cagrilir; zaman dilimli gorev mimarisi icinde       |
   //| "yuksek frekansli motor" gorevini gorur.                         |
   //+------------------------------------------------------------------+
   void ExecuteHybridScalpAndDefense(SRegimeSnapshot &s, const double bid, const double ask)
     {
      if(bid <= 0.0 || ask <= 0.0)
         return;

      // ---------------- SAVUNMA KATMANI (oncelik her zaman burada) ----
      bool need_lock = (s.regime == (int)REGIME_DEFENSE_LOCK) || g_risk.LockRequired();
      if(need_lock && !m_locked)
         EngageLock(s, (s.regime == (int)REGIME_DEFENSE_LOCK) ? 1 : 2);

      if(m_locked)
        {
         ManageLock(s);
         // Kilitteyken yalnizca kalkan yasar; grid zaten FROZEN modunda
         return;
        }

      // ---------------- MIKRO-SCALP KATMANI ---------------------------
      if(!m_cfg.scalp_enabled)
         return;

      // Alt zaman dilimi serisini yeni mumda tazele
      datetime sb = g_sqz_scalp.LastBarTime();
      if(sb != m_last_scalp_bar)
        {
         m_last_scalp_bar = sb;
         m_scalp_bar_count++;
         g_sqz_scalp.Refresh(120);
        }
      if(m_scalp_bar_count < 30)   // istatistik isinmasi
         return;

      ManageOpenScalps(s, bid, ask);
      TryOpenScalp(s, bid, ask);
     }
  };

CApexScalp g_scalp;

#endif
//+------------------------------------------------------------------+

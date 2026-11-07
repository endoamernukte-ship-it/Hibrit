//+------------------------------------------------------------------+
//|                                                     ApexGrid.mqh  |
//|  APEX COMBAT ENGINE - Katman 3: Adatif Bukalemun Grid + Matris    |
//|                                                                  |
//|  SABIT GRID VE KLASIK MARTINGAL YOKTUR.                           |
//|   * Aralik = ATR x elastik carpan  -> "Elastomer Grid"            |
//|   * Lot egimi sinirlidir (anti-martingal), tavan sabittir         |
//|   * Rejim degisince grid modu degisir, ters yonlu bacaklar        |
//|     aninda kesilir (Cut Loss) ve tek yonlu trend binicisine       |
//|     evrilir                                                       |
//|   * Her plan yeniden kuruldugunda piyasadaki emirlerle            |
//|     mutabakat yapilir (kendi kendini onarma)                      |
//+------------------------------------------------------------------+
#ifndef __APEX_GRID_MQH__
#define __APEX_GRID_MQH__ 1

#include "ApexTypes.mqh"
#include "ApexTrade.mqh"
#include "ApexAnalytics.mqh"
#include "ApexRisk.mqh"

class CApexGrid
  {
private:
   SApexConfig  m_cfg;
   SGridLevel   m_levels[];
   double       m_anchor;
   double       m_step;
   int          m_mode;
   int          m_prev_mode;
   int          m_last_regime;
   int          m_trend_dir;
   int          m_cooldown_bars;
   int          m_cycle_id;
   double       m_basket_peak;
   double       m_basket_target;
   datetime     m_last_recenter;
   string       m_action;
   string       m_gv_anchor;
   string       m_prefix;

   //------------------------------------------------------------------+
   int    ModeFromRegime(const int regime)
     {
      switch((E_APEX_REGIME)regime)
        {
         case REGIME_ACCUMULATION:    return (int)GRID_MODE_STEALTH;
         case REGIME_BREAKOUT_ATTACK: return (int)GRID_MODE_TREND_RIDER;
         case REGIME_MEAN_REVERSION:  return (int)GRID_MODE_HEDGED;
         case REGIME_VOLATILITY_TRAP: return (int)GRID_MODE_FORTRESS;
         case REGIME_DEFENSE_LOCK:    return (int)GRID_MODE_FROZEN;
         default:                     return (int)GRID_MODE_FROZEN;
        }
     }

   int    MaxLevelsForMode(const int mode, const SRegimeSnapshot &s)
     {
      int n = m_cfg.grid_max_levels;
      switch((E_APEX_GRID_MODE)mode)
        {
         case GRID_MODE_STEALTH:     n = (int)MathMin(n, 2); break;
         case GRID_MODE_FORTRESS:    n = (int)MathMin(n, 2); break;
         case GRID_MODE_TREND_RIDER: n = (int)MathMin(n, 4); break;
         case GRID_MODE_HEDGED:      n = n; break;
         default:                    n = 0; break;
        }
      // Yuksek isida seviye sayisi kirpilir (isinin icine merdiven kurulmaz)
      if(s.composite_heat > 0.6)
         n = (int)MathMax(1, n - 1);
      if(g_risk.Tier() >= (int)TIER_AMBER)
         n = (int)MathMax(1, n - 1);
      return n;
     }

   double AdaptiveAnchor(const SRegimeSnapshot &s, const double price)
     {
      if(m_mode == (int)GRID_MODE_TREND_RIDER)
         return price;                                  // trendde merkez = piyasa
      if(s.poc > 0.0 && s.val > 0.0 && s.vah > 0.0)
         return (s.val + s.vah) * 0.5;                  // dengede merkez = deger alani
      return price;
     }

   double LotForLevel(const int i, const int mode)
     {
      double base = m_cfg.base_lot;
      double lot  = base;
      switch((E_APEX_GRID_MODE)mode)
        {
         case GRID_MODE_HEDGED:
            lot = base * (1.0 + m_cfg.grid_lot_slope * (double)(i - 1));
            lot = MathMin(lot, base * m_cfg.grid_lot_max_mult);
            break;
         case GRID_MODE_STEALTH:
            lot = base * 0.5;
            break;
         case GRID_MODE_FORTRESS:
            lot = base * 0.4;
            break;
         case GRID_MODE_TREND_RIDER:
            // Piramit: ilk ekleme en buyuk, sonrakiler kuculur
            lot = base * MathMax(0.45, 1.15 - 0.15 * (double)(i - 1));
            break;
         default:
            lot = base;
            break;
        }
      return lot;
     }

   int    OrderTypeFor(const int mode, const int side)
     {
      if(mode == (int)GRID_MODE_TREND_RIDER)
         return (side > 0 ? (int)ORDER_TYPE_BUY_STOP : (int)ORDER_TYPE_SELL_STOP);
      return (side > 0 ? (int)ORDER_TYPE_BUY_LIMIT : (int)ORDER_TYPE_SELL_LIMIT);
     }

   bool   PendingPriceLegal(const int type, const double price, const double bid, const double ask)
     {
      double mind = g_exec.MinStopDist();
      switch((ENUM_ORDER_TYPE)type)
        {
         case ORDER_TYPE_BUY_LIMIT:  return (price <= bid - mind);
         case ORDER_TYPE_SELL_LIMIT: return (price >= ask + mind);
         case ORDER_TYPE_BUY_STOP:   return (price >= ask + mind);
         case ORDER_TYPE_SELL_STOP:  return (price <= bid - mind);
        }
      return false;
     }

   //------------------------------------------------------------------+
   //| Elastik adim: volatilite buyudukce aralik genisler              |
   //+------------------------------------------------------------------+
   void ComputeElasticStep(const SRegimeSnapshot &s)
     {
      double atr = s.atr;
      double base_step = (atr > 0.0 ? atr * m_cfg.grid_step_atr_mult : g_exec.Point() * 200.0);

      double elasticity = ApexClamp(s.elasticity, m_cfg.grid_step_min_mult, m_cfg.grid_step_max_mult);
      double mode_mult = 1.0;
      switch((E_APEX_GRID_MODE)m_mode)
        {
         case GRID_MODE_STEALTH:     mode_mult = 1.70; break;
         case GRID_MODE_FORTRESS:    mode_mult = 2.20; break;
         case GRID_MODE_HEDGED:      mode_mult = 1.00; break;
         case GRID_MODE_TREND_RIDER: mode_mult = 0.85; break;
         default:                    mode_mult = 1.00; break;
        }
      // Rejim guveni dusukse aralik genisletilir (belirsizlikte seyrek ag)
      double conf_mult = 1.0 + (1.0 - s.confidence) * 0.35;

      m_step = base_step * elasticity * mode_mult * conf_mult;
      double spread = g_exec.SpreadPoints() * g_exec.Point();
      m_step = MathMax(m_step, g_exec.MinStopDist() * 2.0);
      m_step = MathMax(m_step, spread * 4.0);
      m_step = MathMax(m_step, g_exec.Point() * 10.0);
     }

   //------------------------------------------------------------------+
   //| Plan insasi                                                     |
   //+------------------------------------------------------------------+
   void BuildLevels(const SRegimeSnapshot &s, const double price)
     {
      int n = MaxLevelsForMode(m_mode, s);
      int need = 0;
      switch((E_APEX_GRID_MODE)m_mode)
        {
         case GRID_MODE_HEDGED:
         case GRID_MODE_STEALTH:
         case GRID_MODE_FORTRESS:
            need = n * 2;
            break;
         case GRID_MODE_TREND_RIDER:
            need = n;
            break;
         default:
            need = 0;
            break;
        }
      if(ArrayResize(m_levels, need) < need)
         return;

      int idx = 0;
      double sl_dist = (s.atr > 0.0 ? s.atr * m_cfg.grid_sl_atr : m_step * 6.0);
      double tp_dist = (s.atr > 0.0 ? s.atr * m_cfg.grid_tp_atr : m_step * 2.0);

      if(m_mode == (int)GRID_MODE_TREND_RIDER)
        {
         int d = (m_trend_dir != 0 ? m_trend_dir : (s.trend_dir != 0 ? s.trend_dir : 1));
         for(int i = 1; i <= n; i++)
           {
            SGridLevel L;
            L.level  = d * i;
            L.side   = d;
            L.state  = (int)LEG_PLANNED;
            L.price  = g_exec.NormPrice(m_anchor + d * m_step * (double)i, d);
            L.lot    = LotForLevel(i, m_mode);
            L.sl     = g_exec.NormPrice(L.price - d * sl_dist, -d);
            L.tp     = 0.0;   // trendde hedef: sepet + izleyen stop
            L.order_ticket = 0;
            L.pos_ticket   = 0;
            L.stamp        = 0;
            m_levels[idx] = L;
            idx++;
           }
        }
      else
        {
         for(int i = n; i >= 1; i--)   // once uzak seviyeler, sonra yakinlar
           {
            // UST taraf: SELL (yukselen fiyati sat)
            SGridLevel U;
            U.level  = i;
            U.side   = -1;
            U.state  = (int)LEG_PLANNED;
            U.price  = g_exec.NormPrice(m_anchor + m_step * (double)i, 1);
            U.lot    = LotForLevel(i, m_mode);
            U.sl     = g_exec.NormPrice(U.price + sl_dist, 1);
            U.tp     = g_exec.NormPrice(U.price - tp_dist, -1);
            U.order_ticket = 0;
            U.pos_ticket   = 0;
            U.stamp        = 0;
            m_levels[idx] = U;
            idx++;
           }
         for(int i = n; i >= 1; i--)
           {
            // ALT taraf: BUY (dusen fiyati al)
            SGridLevel D;
            D.level  = -i;
            D.side   = 1;
            D.state  = (int)LEG_PLANNED;
            D.price  = g_exec.NormPrice(m_anchor - m_step * (double)i, -1);
            D.lot    = LotForLevel(i, m_mode);
            D.sl     = g_exec.NormPrice(D.price - sl_dist, -1);
            D.tp     = g_exec.NormPrice(D.price + tp_dist, 1);
            D.order_ticket = 0;
            D.pos_ticket   = 0;
            D.stamp        = 0;
            m_levels[idx] = D;
            idx++;
           }
        }
     }

   //------------------------------------------------------------------+
   //| Piyasa ile mutabakat: emir/pozisyon -> plan hucreleri           |
   //+------------------------------------------------------------------+
   void SyncWithMarket(const SRegimeSnapshot &s, const double bid, const double ask)
     {
      // --- 1) Mevcut GRID emirlerini topla ---
      int    o_level[];
      ulong  o_ticket[];
      double o_price[];
      int    o_type[];
      int    o_cnt = 0;
      int    ototal = OrdersTotal();
      for(int i = ototal - 1; i >= 0; i--)
        {
         ulong tk = OrderGetTicket(i);
         if(tk == 0 || !OrderSelect(tk))
            continue;
         if(OrderGetString(ORDER_SYMBOL) != m_cfg.symbol)
            continue;
         if((ulong)OrderGetInteger(ORDER_MAGIC) != m_cfg.magic)
            continue;
         int role = 0, side = 0, level = 0;
         if(!ApexDecodeTag(OrderGetString(ORDER_COMMENT), role, side, level))
            continue;
         if(role != (int)ROLE_GRID)
            continue;
         int c = o_cnt;
         if(ArrayResize(o_level, c + 1)  < c + 1) break;
         if(ArrayResize(o_ticket, c + 1) < c + 1) break;
         if(ArrayResize(o_price, c + 1)  < c + 1) break;
         if(ArrayResize(o_type, c + 1)   < c + 1) break;
         o_level[c]  = level;
         o_ticket[c] = tk;
         o_price[c]  = OrderGetDouble(ORDER_PRICE_OPEN);
         o_type[c]   = (int)OrderGetInteger(ORDER_TYPE);
         o_cnt++;
        }

      // --- 2) Mevcut GRID pozisyonlarini topla ---
      g_exec.RebuildBook();
      int p_level[];
      ulong p_ticket[];
      int p_cnt = 0;
      for(int i = 0; i < g_exec.BookSize(); i++)
        {
         SBookEntry e;
         if(!g_exec.BookAt(i, e))
            continue;
         if(e.role != (int)ROLE_GRID)
            continue;
         int c = p_cnt;
         if(ArrayResize(p_level, c + 1)  < c + 1) break;
         if(ArrayResize(p_ticket, c + 1) < c + 1) break;
         p_level[c]  = e.level;
         p_ticket[c] = e.ticket;
         p_cnt++;
        }

      // --- 3) Plan hucrelerini isaretle + fazlaliklari temizle ---
      for(int i = 0; i < ArraySize(m_levels); i++)
        {
         m_levels[i].order_ticket = 0;
         m_levels[i].pos_ticket   = 0;
         m_levels[i].state        = (int)LEG_PLANNED;

         for(int k = 0; k < p_cnt; k++)
           {
            if(p_level[k] == m_levels[i].level)
              {
               m_levels[i].state      = (int)LEG_FILLED;
               m_levels[i].pos_ticket = p_ticket[k];
               break;
              }
           }
         if(m_levels[i].state == (int)LEG_FILLED)
            continue;

         for(int k = 0; k < o_cnt; k++)
           {
            if(o_level[k] != m_levels[i].level)
               continue;
            double drift = MathAbs(o_price[k] - m_levels[i].price);
            if(drift > m_step * 0.35)
              {
               // Elastik adim degisti: eski emri iptal et, yeni fiyattan kur
               g_exec.DeleteOrder(o_ticket[k]);
               m_levels[i].state = (int)LEG_PLANNED;
              }
            else
              {
               m_levels[i].state        = (int)LEG_ARMED;
               m_levels[i].order_ticket = o_ticket[k];
              }
            break;
           }
        }

      // --- 4) Planda olmayan emirleri sil (mod degisimi / recenter) ---
      for(int k = 0; k < o_cnt; k++)
        {
         bool found = false;
         for(int i = 0; i < ArraySize(m_levels); i++)
           {
            if(m_levels[i].level == o_level[k]) { found = true; break; }
           }
         if(!found)
            g_exec.DeleteOrder(o_ticket[k]);
        }

      // --- 5) Eksik bacaklari kur ---
      int filled_legs = p_cnt;
      int armed_legs  = 0;
      for(int i = 0; i < ArraySize(m_levels); i++)
         if(m_levels[i].state == (int)LEG_ARMED)
            armed_legs++;

      for(int i = 0; i < ArraySize(m_levels); i++)
        {
         if(m_levels[i].state != (int)LEG_PLANNED)
            continue;
         if((filled_legs + armed_legs) >= MathMin(m_cfg.grid_max_legs_total, ArraySize(m_levels)))
            break;
         if(!g_risk.AllowNew((int)ROLE_GRID, s.regime))
            break;

         int type = OrderTypeFor(m_mode, m_levels[i].side);
         if(!PendingPriceLegal(type, m_levels[i].price, bid, ask))
            continue;

         double lot = m_levels[i].lot;
         double sl_dist = (m_levels[i].sl > 0.0 ? MathAbs(m_levels[i].price - m_levels[i].sl) : m_step * 4.0);
         // Tavan: anti-martingal lot egimi. Risk modeli yalnizca kucultur.
         double cap = m_cfg.base_lot * m_cfg.grid_lot_max_mult;
         lot = g_risk.RiskLotCapped(sl_dist, lot, g_risk.SizeMultiplier(), MathMin(cap, lot));
         lot = g_risk.ExposureCap(lot, m_cfg.max_total_lots);
         if(lot <= 0.0)
            continue;

         ulong tk = g_exec.PlacePending(type, lot, m_levels[i].price, m_levels[i].sl,
                                        m_levels[i].tp, (int)ROLE_GRID, m_levels[i].level);
         if(tk != 0)
           {
            m_levels[i].state        = (int)LEG_ARMED;
            m_levels[i].order_ticket = tk;
            armed_legs++;
            if(m_cfg.verbose_log)
               PrintFormat("[APEX:GRID] Bacak kuruldu lvl=%+d %s lot=%.2f @ %.*f (mod=%s adim=%.1f pt)",
                           m_levels[i].level, ApexSideName(m_levels[i].side), lot,
                           g_exec.Digits(), m_levels[i].price, ApexGridModeName(m_mode),
                           m_step / g_exec.Point());
           }
        }
     }

   //------------------------------------------------------------------+
   //| Mod gecisi: rejim degistiginde gridin evrimi                    |
   //+------------------------------------------------------------------+
   void ApplyModeTransition(const int new_mode, const SRegimeSnapshot &s, const double price)
     {
      m_prev_mode = m_mode;
      m_mode      = new_mode;
      m_trend_dir = (s.trend_dir != 0 ? s.trend_dir : s.mom_dir);

      // Tum bekleyen emirler iptal: yeni mod yeni geometri demektir
      g_exec.DeleteOrdersRole((int)ROLE_GRID);

      if(new_mode == (int)GRID_MODE_TREND_RIDER)
        {
         m_anchor = price;
         // Ters yondeki tum bacaklar aninda kesilir (Cut Loss)
         CutCounterTrendLegs(m_trend_dir);
         m_action = StringFormat("MOD: TREND RIDER (%s) - ters bacaklar kesildi", ApexSideName(m_trend_dir));
         PrintFormat("[APEX:GRID] TAAARRUZ: mod=TREND_RIDER yon=%s ters bacaklar kesildi.",
                     ApexSideName(m_trend_dir));
        }
      else if(new_mode == (int)GRID_MODE_HEDGED)
        {
         m_anchor = AdaptiveAnchor(s, price);
         m_action = "MOD: HEDGED GRID - cift yonlu elastik ag";
         PrintFormat("[APEX:GRID] DENGE: mod=HEDGED_GRID merkez=%.5f (deger alani)", m_anchor);
        }
      else if(new_mode == (int)GRID_MODE_STEALTH)
        {
         m_anchor = AdaptiveAnchor(s, price);
         m_action = "MOD: STEALTH - gizli toplanma, genis aralik";
         Print("[APEX:GRID] GIZLI TOPLANMA: mod=STEALTH");
        }
      else if(new_mode == (int)GRID_MODE_FORTRESS)
        {
         m_anchor = AdaptiveAnchor(s, price);
         m_action = "MOD: FORTRESS - tuzak avi, seyrek ve kucuk";
         Print("[APEX:GRID] VOLATILITE TUZAGI: mod=FORTRESS");
        }
      else
        {
         m_action = "MOD: FROZEN - savunma kilidi";
         Print("[APEX:GRID] SIPER: mod=FROZEN (grid donduruldu)");
        }
      SaveAnchor();
     }

   // Ters yonlu bacaklari kapat (en zararli once)
   void CutCounterTrendLegs(const int dir)
     {
      if(dir == 0)
         return;
      g_exec.RebuildBook();
      ulong worst[];
      double worst_pl[];
      int cnt = 0;

      for(int pass = 0; pass < 2; pass++)
        {
         for(int i = 0; i < g_exec.BookSize(); i++)
           {
            SBookEntry e;
         if(!g_exec.BookAt(i, e))
            continue;
            if(e.role != (int)ROLE_GRID)
               continue;
            if(e.side == dir)
               continue;
            if(pass == 0 && e.profit > 0.0)
               continue;      // once zararli olanlar
            if(pass == 1 && e.profit <= 0.0)
               continue;
            int c = cnt;
            if(ArrayResize(worst, c + 1) < c + 1) break;
            if(ArrayResize(worst_pl, c + 1) < c + 1) break;
            worst[c]    = e.ticket;
            worst_pl[c] = e.profit;
            cnt++;
           }
        }

      int cut = (int)MathCeil(cnt * ApexClamp(m_cfg.grid_cut_ratio, 0.1, 1.0));
      for(int i = 0; i < cut && i < cnt; i++)
         g_exec.CloseTicket(worst[i], "REAKSIYON: ters yon bacağı kesildi");
     }

   //------------------------------------------------------------------+
   //| Sepet (basket) yonetimi - Akilli Cikis Matrisi'nin grid ayagi   |
   //+------------------------------------------------------------------+
   void ManageBasket(const SRegimeSnapshot &s, const double price)
     {
      g_exec.RebuildBook();
      double grid_profit  = g_exec.BasketProfit((int)ROLE_GRID, 0);
      double core_profit  = g_exec.BasketProfit((int)ROLE_CORE, 0);
      double gross        = g_exec.GrossLots((int)ROLE_GRID);
      double basket       = grid_profit + core_profit;
      if(basket > m_basket_peak)
         m_basket_peak = basket;

      if(gross <= 0.0)
         return;

      double equity = AccountInfoDouble(ACCOUNT_EQUITY);
      double atr_money = (s.atr > 0.0 ? s.atr * gross * g_exec.PointValue() : 0.0);
      double target = MathMax(m_cfg.grid_basket_atr * atr_money,
                              m_cfg.grid_basket_equity * 0.01 * equity);
      // Mikro-scalp savas sandigi hedefi dusurur: kâr katlamasi burada
      target = MathMax(atr_money * 0.15, target - g_risk.WarChest());
      m_basket_target = target;
      double stop = -1.6 * MathMax(target, atr_money * 0.25);

      // 1) Hedefe ulasildi -> sepeti bosalt, donguyu sifirla
      if(target > 0.0 && basket >= target)
        {
         CloseCycle(StringFormat("SEPET HEDEFINE ULASILDI (%.2f >= %.2f)", basket, target));
         return;
        }

      // 2) Momentum yorgunlugu -> sinyal sayisini beklemeden AKILLI KÂR SWEEP
      if(s.fatigue == 1 && basket > 0.0 && basket > 0.25 * target)
        {
         CloseCycle(StringFormat("SMART PROFIT SWEEP: momentum turevi sifirlandi (sepet %.2f)", basket));
         g_risk.SpendWarChest(g_risk.WarChest());
         return;
        }

      // 3) Momentum yorgunlugu ama sepet zararda -> sadece kârli bacaklari bosalt
      if(s.fatigue == 1 && basket <= 0.0)
        {
         int closed = 0;
         for(int i = 0; i < g_exec.BookSize(); i++)
           {
            SBookEntry e;
         if(!g_exec.BookAt(i, e))
            continue;
            if(e.role != (int)ROLE_GRID)
               continue;
            if(e.profit > 0.0)
              {
               g_exec.CloseTicket(e.ticket, "KISMI SWEEP: momentum yorgun, kârli bacak realizasyonu");
               closed++;
              }
           }
         if(closed > 0)
            m_action = StringFormat("Kismi sweep: %d kârli bacak kapatildi", closed);
        }

      // 4) Sepet stopu -> savunmaya devir (risk kademesi zaten kilit acacak)
      if(stop < 0.0 && basket <= stop)
        {
         if(g_risk.Tier() >= (int)TIER_RED)
            CloseCycle(StringFormat("SEPET STOP + KIRMIZI KADEME (%.2f <= %.2f)", basket, stop));
         else
           {
            // Kontrollu azaltma: en zararli iki bacak kapatilir
            CutWorstLegs(2, "SEPET STOP: kontrollu azaltma");
           }
        }

      // 5) Trend binicisinde izleyen stop (chandelier)
      if(m_mode == (int)GRID_MODE_TREND_RIDER && s.atr > 0.0)
        {
         double trail = s.atr * 1.2;
         for(int i = 0; i < g_exec.BookSize(); i++)
           {
            SBookEntry e;
         if(!g_exec.BookAt(i, e))
            continue;
            if(e.role != (int)ROLE_GRID || e.side != m_trend_dir)
               continue;
            double new_sl = g_exec.NormPrice(price - e.side * trail, -e.side);
            bool better = false;
            if(e.side > 0)
               better = (new_sl > e.sl + g_exec.Point()) && (new_sl > e.entry);
            else
               better = (e.sl <= 0.0 || new_sl < e.sl - g_exec.Point()) && (new_sl < e.entry);
            if(better)
               g_exec.ModifyStops(e.ticket, new_sl, 0.0);
           }
        }
     }

   void CutWorstLegs(const int count, const string reason)
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
         if(e.role != (int)ROLE_GRID)
            continue;
         int c = cnt;
         if(ArrayResize(tk, c + 1) < c + 1) break;
         if(ArrayResize(pl, c + 1) < c + 1) break;
         tk[c] = e.ticket;
         pl[c] = e.profit;
         cnt++;
        }
      // En zararlidan basa: basit secmeli siralama
      for(int a = 0; a < cnt - 1; a++)
         for(int b = a + 1; b < cnt; b++)
            if(pl[b] < pl[a])
              {
               double tp = pl[a]; pl[a] = pl[b]; pl[b] = tp;
               ulong   tt = tk[a]; tk[a] = tk[b]; tk[b] = tt;
              }
      int n = (int)MathMin(count, cnt);
      for(int i = 0; i < n; i++)
         g_exec.CloseTicket(tk[i], reason);
     }

   void CloseCycle(const string reason)
     {
      PrintFormat("[APEX:GRID] DONGU KAPANDI: %s", reason);
      g_exec.CloseRole((int)ROLE_GRID, reason);
      g_exec.CloseRole((int)ROLE_CORE, reason);
      g_exec.DeleteOrdersRole((int)ROLE_GRID);
      m_anchor = 0.0;
      m_basket_peak = 0.0;
      m_cooldown_bars = 2;      // yeni dongu icin kisa nefes
      m_cycle_id++;
      m_action = "DONGU KAPANDI: " + reason;
      SaveAnchor();
     }

   void SaveAnchor()
     {
      if(m_gv_anchor != "")
         GlobalVariableSet(m_gv_anchor, m_anchor);
     }

   void LoadAnchor()
     {
      if(m_gv_anchor != "" && GlobalVariableCheck(m_gv_anchor))
         m_anchor = GlobalVariableGet(m_gv_anchor);
     }

public:
                     CApexGrid()
     {
      m_anchor        = 0.0;
      m_step          = 0.0;
      m_mode          = (int)GRID_MODE_FROZEN;
      m_prev_mode     = (int)GRID_MODE_FROZEN;
      m_last_regime   = (int)REGIME_BOOT;
      m_trend_dir     = 0;
      m_cooldown_bars = 0;
      m_cycle_id      = 0;
      m_basket_peak   = 0.0;
      m_basket_target = 0.0;
      m_last_recenter = 0;
      m_action        = "";
      m_gv_anchor     = "";
      m_prefix        = "";
      ArrayResize(m_levels, 0);
     }
                    ~CApexGrid() { }

   void Init(const SApexConfig &cfg)
     {
      m_cfg = cfg;
      m_gv_anchor = ApexGVName(cfg.symbol, cfg.magic, "anchor");
      m_prefix    = StringFormat("APXGRID_%I64u_%s_", cfg.magic, cfg.symbol);
      ArrayResize(m_levels, 0);
      LoadAnchor();
     }

   int    Mode()          { return m_mode; }
   double Anchor()        { return m_anchor; }
   double Step()          { return m_step; }
   double BasketTarget()  { return m_basket_target; }
   int    CycleId()       { return m_cycle_id; }
   int    LevelCount()    { return ArraySize(m_levels); }
   string Action()        { return m_action; }
   int    TrendDir()      { return m_trend_dir; }

   void   Reset()
     {
      m_anchor = 0.0;
      m_basket_peak = 0.0;
      ArrayResize(m_levels, 0);
      SaveAnchor();
     }

   //+------------------------------------------------------------------+
   //| ANA GIRIS: Adaptif elastik grid ve yon degistirme mekanizmasi    |
   //+------------------------------------------------------------------+
   void ManageAdaptiveElasticGrid(SRegimeSnapshot &s, const double bid, const double ask)
     {
      if(!m_cfg.grid_enabled)
         return;
      if(bid <= 0.0 || ask <= 0.0)
         return;

      double price = (bid + ask) * 0.5;

      // --- Mod gecisi (rejim -> grid modu) ---
      int want_mode = ModeFromRegime(s.regime);
      if(want_mode != m_mode)
         ApplyModeTransition(want_mode, s, price);
      else if(m_mode == (int)GRID_MODE_TREND_RIDER && s.trend_dir != 0 && s.trend_dir != m_trend_dir)
        {
         // Trend yonu tersine dondu: eski yonun bacaklari kesilir
         m_trend_dir = s.trend_dir;
         CutCounterTrendLegs(m_trend_dir);
         g_exec.DeleteOrdersRole((int)ROLE_GRID);
         m_anchor = price;
         m_action = StringFormat("TREND YON DEGISTI -> %s", ApexSideName(m_trend_dir));
        }

      // --- Elastik adim ---
      ComputeElasticStep(s);

      // --- Dondurulmus mod: yalnizca mevcutlari izle ---
      if(m_mode == (int)GRID_MODE_FROZEN)
        {
         g_exec.DeleteOrdersRole((int)ROLE_GRID);
         if(m_action == "")
            m_action = "FROZEN: yeni bacak yok";
         return;
        }

      // --- Bekleme suresi ---
      if(m_cooldown_bars > 0)
        {
         m_cooldown_bars--;
         m_action = StringFormat("Dongu nefesi (%d bar)", m_cooldown_bars);
         return;
        }

      // --- Merkez yeniden konumlandirma (recenter) ---
      if(m_anchor <= 0.0)
        {
         m_anchor = AdaptiveAnchor(s, price);
         SaveAnchor();
        }
      else if(s.atr > 0.0 && MathAbs(price - m_anchor) > m_cfg.grid_recenter_atr * s.atr)
        {
         m_anchor = AdaptiveAnchor(s, price);
         m_last_recenter = TimeCurrent();
         g_exec.DeleteOrdersRole((int)ROLE_GRID);
         m_action = "MERKEZ YENIDEN KONUMLANDI";
         if(m_cfg.verbose_log)
            PrintFormat("[APEX:GRID] Recenter -> %.5f (fiyat %.5f)", m_anchor, price);
        }

      // --- Plan + mutabakat ---
      BuildLevels(s, price);
      SyncWithMarket(s, bid, ask);

      // --- Sepet / akilli cikis ---
      ManageBasket(s, price);

      m_last_regime = s.regime;
     }
  };

CApexGrid g_grid;

#endif
//+------------------------------------------------------------------+

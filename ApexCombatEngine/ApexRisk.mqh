//+------------------------------------------------------------------+
//|                                                     ApexRisk.mqh  |
//|  APEX COMBAT ENGINE - Katman 2: Sermaye Koruma Guvenlik Duvari    |
//|                                                                  |
//|  Katmanli savunma (defense in depth):                             |
//|   [1] Sembol/oturum/spread hijyeni  (islem oncesi filtre)         |
//|   [2] Pozisyon boyutu: risk% + volatilite + marjin + exposure     |
//|   [3] Rejim bazli risk carpanlari   (dinamik ihtiyat)             |
//|   [4] Drawdown kademeleri           (GREEN/AMBER/RED/BLACK)       |
//|   [5] Delta-notr kilit ve kontrollu geri cekilme (kill-switch)    |
//|                                                                  |
//|  Kendini onarma: drawdown geriledikce risk kapasitesi kademeli    |
//|  olarak geri kazanilir (asiri tepki yok), toksisite skoru zamanla |
//|  sogur, gunluk realize verisi tarihceden yeniden okunur (restart  |
//|  sonrasi bile sistem gunluk limitleri bilir).                     |
//+------------------------------------------------------------------+
#ifndef __APEX_RISK_MQH__
#define __APEX_RISK_MQH__ 1

#include "ApexTypes.mqh"
#include "ApexTrade.mqh"

class CApexRisk
  {
private:
   SApexConfig m_cfg;
   double      m_peak_equity;
   double      m_equity;
   double      m_balance;
   double      m_dd_pct;
   double      m_day_realized;
   double      m_day_start_balance;
   int         m_day_stamp;
   int         m_tier;
   double      m_size_mult;      // hedefe dogru yumusak gecis yapan carpan
   double      m_toxicity;       // 0..1 piyasa + sistem zehirlenme skoru
   int         m_consec_loss;
   bool        m_halted;
   int         m_halt_day;
   double      m_war_chest;      // mikro-scalp kâr havuzu
   datetime    m_last_refresh;
   string      m_gv_peak;
   string      m_gv_halt;
   string      m_status;

   int TodayStamp()
     {
      MqlDateTime dt;
      TimeCurrent(dt);
      return dt.year * 10000 + dt.mon * 100 + dt.day;
     }

   void LoadState()
     {
      m_gv_peak = ApexGVName(m_cfg.symbol, m_cfg.magic, "peak");
      m_gv_halt = ApexGVName(m_cfg.symbol, m_cfg.magic, "halt");
      if(GlobalVariableCheck(m_gv_peak))
         m_peak_equity = GlobalVariableGet(m_gv_peak);
      else
         m_peak_equity = AccountInfoDouble(ACCOUNT_BALANCE);
      if(m_peak_equity <= 0.0)
         m_peak_equity = AccountInfoDouble(ACCOUNT_EQUITY);

      if(GlobalVariableCheck(m_gv_halt))
        {
         double hd = GlobalVariableGet(m_gv_halt);
         m_halt_day = (int)hd;
         m_halted   = (m_halt_day == TodayStamp());
        }
     }

   void SavePeak()
     {
      GlobalVariableSet(m_gv_peak, m_peak_equity);
     }

   // Gunluk realize + ardisik kayip: tarihceden yeniden okunur (stateless)
   void RefreshHistoryStats()
     {
      MqlDateTime dt;
      TimeCurrent(dt);
      dt.hour = 0; dt.min = 0; dt.sec = 0;
      datetime from = StructToTime(dt);
      datetime to   = TimeCurrent() + 60;

      m_day_realized = 0.0;
      if(!HistorySelect(from, to))
         return;

      int total = HistoryDealsTotal();
      double realized = 0.0;
      int loss_streak = 0;
      int scanned = 0;

      for(int i = total - 1; i >= 0 && scanned < 200; i--)
        {
         ulong tk = HistoryDealGetTicket(i);
         if(tk == 0)
            continue;
         if(HistoryDealGetString(tk, DEAL_SYMBOL) != m_cfg.symbol)
            continue;
         if((ulong)HistoryDealGetInteger(tk, DEAL_MAGIC) != m_cfg.magic)
            continue;
         scanned++;

         double profit = HistoryDealGetDouble(tk, DEAL_PROFIT)
                       + HistoryDealGetDouble(tk, DEAL_SWAP)
                       + HistoryDealGetDouble(tk, DEAL_COMMISSION);
         realized += profit;

         long entry = HistoryDealGetInteger(tk, DEAL_ENTRY);
         if(entry == DEAL_ENTRY_IN || entry == DEAL_ENTRY_INOUT)
            continue;
         if(profit < 0.0)
            loss_streak++;
         else
            break;   // kârla biten ilk islemde seri kirilir
        }

      m_day_realized = realized;
      m_consec_loss  = loss_streak;
     }

public:
                     CApexRisk()
     {
      m_peak_equity       = 0.0;
      m_equity            = 0.0;
      m_balance           = 0.0;
      m_dd_pct            = 0.0;
      m_day_realized      = 0.0;
      m_day_start_balance = 0.0;
      m_day_stamp         = 0;
      m_tier              = (int)TIER_GREEN;
      m_size_mult         = 1.0;
      m_toxicity          = 0.0;
      m_consec_loss       = 0;
      m_halted            = false;
      m_halt_day          = 0;
      m_war_chest         = 0.0;
      m_last_refresh      = 0;
      m_status            = "";
     }
                    ~CApexRisk() { }

   void Init(const SApexConfig &cfg)
     {
      m_cfg = cfg;
      m_day_stamp = TodayStamp();
      m_day_start_balance = AccountInfoDouble(ACCOUNT_BALANCE);
      LoadState();
      Update(true);
     }

   //+------------------------------------------------------------------+
   //| Ana guncelleme: equity, zirve, drawdown, kademe, toksisite       |
   //+------------------------------------------------------------------+
   void Update(const bool force)
     {
      datetime now = TimeCurrent();
      if(!force && (now - m_last_refresh) < 2)
         return;
      m_last_refresh = now;

      m_equity  = AccountInfoDouble(ACCOUNT_EQUITY);
      m_balance = AccountInfoDouble(ACCOUNT_BALANCE);

      int ts = TodayStamp();
      if(ts != m_day_stamp)
        {
         m_day_stamp = ts;
         m_day_start_balance = m_balance;
         m_war_chest = 0.0;
         if(m_halted && m_halt_day != ts)
           {
            m_halted = false;
            GlobalVariableDel(m_gv_halt);
            Print("[APEX:RISK] Yeni gun: kill-switch sifirlandi.");
           }
        }

      if(m_equity > m_peak_equity)
        {
         m_peak_equity = m_equity;
         SavePeak();
        }
      m_dd_pct = (m_peak_equity > 0.0 ? ((m_peak_equity - m_equity) / m_peak_equity) * 100.0 : 0.0);

      RefreshHistoryStats();

      // --- Kademe belirleme ---
      int tier = (int)TIER_GREEN;
      if(m_dd_pct >= m_cfg.dd_kill)
         tier = (int)TIER_BLACK;
      else if(m_dd_pct >= m_cfg.dd_defense)
         tier = (int)TIER_RED;
      else if(m_dd_pct >= m_cfg.dd_warn)
         tier = (int)TIER_AMBER;

      bool daily_breach = (m_cfg.daily_loss_limit > 0.0 && m_day_realized <= -m_cfg.daily_loss_limit);
      if(daily_breach && tier < (int)TIER_RED)
         tier = (int)TIER_RED;
      if(g_exec.MarginLevelPct() < 250.0 && tier < (int)TIER_RED)
         tier = (int)TIER_RED;

      if(tier != m_tier)
        {
         PrintFormat("[APEX:RISK] KADEME %s -> %s (DD=%.2f%% gunluk=%.2f streak=%d)",
                     ApexTierName(m_tier), ApexTierName(tier), m_dd_pct, m_day_realized, m_consec_loss);
         m_tier = tier;
        }

      if(tier == (int)TIER_BLACK && !m_halted)
        {
         m_halted = true;
         m_halt_day = TodayStamp();
         GlobalVariableSet(m_gv_halt, (double)m_halt_day);
         PrintFormat("[APEX:RISK] KILL-SWITCH: DD %.2f%% >= %.2f%%. Gun sonuna kadar islem durdu.",
                     m_dd_pct, m_cfg.dd_kill);
        }

      // --- Kendini onaran risk kapasitesi ---
      double target = 1.0;
      switch((E_APEX_RISK_TIER)m_tier)
        {
         case TIER_GREEN: target = 1.00; break;
         case TIER_AMBER: target = 0.55; break;
         case TIER_RED:   target = 0.20; break;
         case TIER_BLACK: target = 0.00; break;
        }
      target *= (1.0 - 0.5 * m_toxicity);
      if(m_halted)
         target = 0.0;

      double rate = ApexClamp(m_cfg.heal_rate, 0.01, 1.0);
      if(m_size_mult < target)
         m_size_mult = MathMin(target, m_size_mult + rate);     // iyilesme yavas
      else
         m_size_mult = MathMax(target, m_size_mult - rate * 1.5); // kisitlama hizli

      // --- Toksisite sönümlenmesi ---
      m_toxicity = MathMax(0.0, m_toxicity - m_cfg.toxicity_decay);
      double streak_penalty = ApexNormRange((double)m_consec_loss, 1.0, (double)MathMax(2, m_cfg.max_consec_loss));
      m_toxicity = ApexSaturate(MathMax(m_toxicity, streak_penalty));

      m_status = StringFormat("%s | DD %.2f%% | gunluk %.2f | seri kayip %d | carpan %.2f | toks %.2f",
                              ApexTierName(m_tier), m_dd_pct, m_day_realized,
                              m_consec_loss, m_size_mult, m_toxicity);
     }

   //+------------------------------------------------------------------+
   //| Sorgular                                                         |
   //+------------------------------------------------------------------+
   int      Tier()          { return m_tier; }
   double   DrawdownPct()   { return m_dd_pct; }
   double   DayRealized()   { return m_day_realized; }
   double   PeakEquity()    { return m_peak_equity; }
   double   Equity()        { return m_equity; }
   double   SizeMultiplier(){ return m_size_mult; }
   double   Toxicity()      { return m_toxicity; }
   int      ConsecLoss()    { return m_consec_loss; }
   bool     Halted()        { return m_halted; }
   string   Status()        { return m_status; }
   double   WarChest()      { return m_war_chest; }

   void     AddWarChest(const double v) { m_war_chest += v; }
   void     SpendWarChest(const double v){ m_war_chest = MathMax(0.0, m_war_chest - v); }
   void     AddToxicity(const double v) { m_toxicity = ApexSaturate(m_toxicity + v); }

   void     ResetPeak()
     {
      m_peak_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      SavePeak();
     }

   void     ClearHalt()
     {
      m_halted = false;
      GlobalVariableDel(m_gv_halt);
     }

   bool     LockRequired()
     {
      return (m_tier >= (int)TIER_RED);
     }

   bool     LiquidationRequired()
     {
      return (m_tier >= (int)TIER_BLACK);
     }

   //+------------------------------------------------------------------+
   //| Islem oncesi izin: rol bazli                                     |
   //+------------------------------------------------------------------+
   bool AllowNew(const int role, const int regime)
     {
      if(m_halted)
         return false;
      if(m_tier >= (int)TIER_BLACK)
         return false;
      if(m_tier >= (int)TIER_RED)
         return false;                       // kilitte yalnizca hedge/çikis
      if(m_cfg.daily_profit_target > 0.0 && m_day_realized >= m_cfg.daily_profit_target)
         return false;                       // gunluk hedefe ulasildi -> risk alma
      if(regime == (int)REGIME_DEFENSE_LOCK && role != (int)ROLE_HEDGE)
         return false;
      if(role == (int)ROLE_SCALP && regime == (int)REGIME_VOLATILITY_TRAP)
         return false;
      if(role == (int)ROLE_GRID && regime == (int)REGIME_DEFENSE_LOCK)
         return false;
      if(!SessionOK())
         return false;
      if(!SpreadOK())
         return false;
      return true;
     }

   bool SessionOK()
     {
      if(!m_cfg.use_session)
         return true;
      MqlDateTime dt;
      TimeCurrent(dt);
      if(dt.day_of_week == 5 && dt.hour >= m_cfg.friday_close_hour)
         return false;                       // hafta kapanisi
      if(dt.day_of_week == 6 || dt.day_of_week == 0)
         return false;
      if(dt.hour < m_cfg.session_start_hour || dt.hour >= m_cfg.session_end_hour)
         return false;
      return true;
     }

   bool SpreadOK()
     {
      double sp = g_exec.SpreadPoints();
      if(m_cfg.max_spread_points > 0 && sp > m_cfg.max_spread_points)
         return false;
      return true;
     }

   //+------------------------------------------------------------------+
   //| Pozisyon boyutlandirma: risk% + volatilite + marjin + exposure   |
   //+------------------------------------------------------------------+
   // Tavan kurali: risk modeli lotu YALNIZCA KUCULTEBILIR.
   // Hard_cap (taban lot x rejim/rol carpani) asla asilmaz - boylece
   // risk% ayari grid/scalp boyutunu beklenmedik bicimde sisirmez.
   double RiskLotCapped(const double sl_distance_price, const double base_lot,
                        const double size_mult, const double hard_cap)
     {
      double lot = RiskLot(sl_distance_price, base_lot, size_mult);
      if(hard_cap > 0.0 && lot > hard_cap)
         lot = hard_cap;
      return g_exec.NormVolume(lot);
     }

   double RiskLot(const double sl_distance_price, const double base_lot, const double size_mult)
     {
      double lot = base_lot;
      if(m_cfg.risk_per_trade_pct > 0.0 && sl_distance_price > 0.0 && g_exec.PointValue() > 0.0)
        {
         double risk_money = m_equity * (m_cfg.risk_per_trade_pct / 100.0);
         double per_lot    = sl_distance_price * g_exec.PointValue();
         double risk_lot   = ApexSafeDiv(risk_money, per_lot, base_lot);
         // Risk tabanli lot; taban lotun cok altina inmez, cok ustune de cikmaz
         lot = ApexClamp(risk_lot, base_lot * 0.25, base_lot * 10.0);
        }
      lot = lot * ApexClamp(size_mult, 0.0, 1.0);
      if(m_cfg.max_lot > 0.0)
         lot = MathMin(lot, m_cfg.max_lot);
      return g_exec.NormVolume(lot);
     }

   // Kalan marjin ve toplam exposure limitine gore lot tavani
   double ExposureCap(const double lot_requested, const double max_gross_lots)
     {
      double lot = lot_requested;
      if(max_gross_lots > 0.0)
        {
         double used = g_exec.GrossLots(-1);
         double room = max_gross_lots - used;
         if(room <= 0.0)
            return 0.0;
         lot = MathMin(lot, room);
        }
      // Marjin tabani: islem sonrasi marjin seviyesi en az %400 kalmali
      while(lot > 0.0 && !g_exec.CanAfford(lot, 400.0))
         lot = g_exec.NormVolume(lot - g_exec.LotStep());
      return g_exec.NormVolume(lot);
     }

   //+------------------------------------------------------------------+
   //| Rejim bazli ihtiyat: onay sayisi ve lot carpanlari               |
   //+------------------------------------------------------------------+
   int ConfirmationsRequired(const int regime)
     {
      int need = 1;
      switch((E_APEX_REGIME)regime)
        {
         case REGIME_VOLATILITY_TRAP: need = 3; break;
         case REGIME_ACCUMULATION:    need = 2; break;
         case REGIME_MEAN_REVERSION:  need = 1; break;
         case REGIME_BREAKOUT_ATTACK: need = 1; break;
         default:                     need = 2; break;
        }
      if(m_tier >= (int)TIER_AMBER) need++;
      if(m_toxicity > 0.5)          need++;
      return need;
     }

   //+------------------------------------------------------------------+
   //| Kapanis bildirimi: toksisite ve savas sandigi guncellemesi       |
   //+------------------------------------------------------------------+
   void NoteClose(const double profit, const int role)
     {
      if(profit < 0.0)
         m_toxicity = ApexSaturate(m_toxicity + 0.08);
      else
         m_toxicity = MathMax(0.0, m_toxicity - 0.05);
      if(role == (int)ROLE_SCALP && profit > 0.0)
         m_war_chest += profit;
      Update(true);
     }
  };

CApexRisk g_risk;

#endif
//+------------------------------------------------------------------+

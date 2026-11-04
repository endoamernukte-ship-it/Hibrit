//+------------------------------------------------------------------+
//|                                            BTC_Alpha_Engine.mq5  |
//| BTCUSD icin uyarlanabilir trend kirilimi + opsiyonel range motoru|
//| Risk-oncelikli: ATR stop, R-bazli cikis, gunluk DD kill-switch.  |
//+------------------------------------------------------------------+
#property copyright   "MTFROBOT1"
#property link        "https://github.com/Ertoraman/MTFROBOT1"
#property version     "1.00"
#property description "BTCUSD trend breakout engine with H4 regime filter, ATR risk sizing and trailing exit."
#property description "Optional mean-reversion (range) engine is gated by low ADX / low ATR percentile."
#property description "Daily loss limit, max drawdown kill-switch, loss-streak pause, spread and session filters."
#property description "IMPORTANT: backtest with real ticks, optimise walk-forward, demo-test before live."

#include <Trade/Trade.mqh>

//+------------------------------------------------------------------+
//| Enumerations                                                     |
//+------------------------------------------------------------------+
enum ENUM_ENGINE
  {
   ENGINE_NONE  = 0,
   ENGINE_TREND = 1,
   ENGINE_RANGE = 2
  };

//+------------------------------------------------------------------+
//| Inputs                                                           |
//+------------------------------------------------------------------+
input group "=== 1) Genel / General ==="
input ulong               InpMagicBase            = 20261018; // Magic base (trend=base, range=base+1)
input ENUM_TIMEFRAMES     InpSignalTimeframe      = PERIOD_H1; // Sinyal zaman dilimi
input ENUM_TIMEFRAMES     InpRegimeTimeframe      = PERIOD_H4; // Rejim zaman dilimi
input int                 InpDeviationPoints      = 300;      // Izin verilen kayma (point)
input bool                InpVerboseLog           = true;     // Ayrintili log
input bool                InpShowDashboard        = true;     // Grafikte durum paneli

input group "=== 2) Motor secimi / Engines ==="
input bool                InpEnableTrend          = true;     // Trend kirilim motoru
input bool                InpEnableRange          = false;    // Range mean-reversion motoru
input bool                InpAllowHedge           = false;    // Ayni anda ters yonlu pozisyona izin ver
input int                 InpMaxPositions         = 1;        // Toplam maksimum pozisyon (bu EA)
input double              InpMaxLots              = 5.0;      // Islem basina maksimum lot (0 = sinirsiz)

input group "=== 3) Trend motoru / Trend engine ==="
input int                 InpDonchianBars         = 24;       // Donchian kanal uzunlugu (bar)
input bool                InpRequireFreshBreakout = true;     // Sadece ilk kirilimda gir
input int                 InpFastEma              = 50;       // Hizli EMA
input int                 InpSlowEma              = 200;      // Yavas EMA
input int                 InpTrendMinAdx          = 0;        // Min ADX (0 = kapali)
input double              InpTrendSlAtr           = 2.0;      // Baslangic SL (x ATR)
input double              InpTrendTrailAtr        = 3.0;      // Chandelier trail (x ATR, 0 = kapali)
input double              InpTrendTpR             = 0.0;      // Sabit TP (R cinsinden, 0 = sadece trail)
input int                 InpTrendMaxBars         = 72;       // Zaman stopu (bar)
input bool                InpExitTrendOnRegimeFlip= true;     // H4 rejimi bozulunca cik

input group "=== 4) Range motoru / Range engine ==="
input int                 InpRangeBbPeriod        = 20;       // Bollinger periyodu
input double              InpRangeBbDev           = 2.0;      // Bollinger sapmasi
input int                 InpRangeRsiPeriod       = 14;       // RSI periyodu
input double              InpRangeRsiBuy          = 30.0;     // Asiri satim RSI
input double              InpRangeRsiSell         = 70.0;     // Asiri alim RSI
input double              InpRangeMaxAdx          = 18.0;     // Range icin maksimum ADX
input double              InpRangeMaxH4SlopePct   = 0.25;     // H4 EMA egim esigi (yuzde)
input int                 InpRangeMaxAtrPctile    = 60;       // Range icin maksimum ATR yuzdeligi
input double              InpRangeSlAtr           = 1.5;      // Range SL (x ATR)
input double              InpRangeTpR             = 1.5;      // Range TP (R cinsinden)
input double              InpRangeRiskScale       = 0.50;     // Range risk carpani
input int                 InpRangeMaxBars         = 24;       // Range zaman stopu (bar)

input group "=== 5) Rejim / volatilite filtreleri ==="
input bool                InpUseH4Regime          = true;     // H4 EMA rejim filtresi
input int                 InpH4EmaPeriod          = 200;      // H4 EMA periyodu
input int                 InpH4SlopeBars          = 10;       // H4 egim olcum bar sayisi
input int                 InpAtrPeriod            = 14;       // ATR periyodu
input double              InpMinAtrPct            = 0.15;     // Min ATR / fiyat (%)
input double              InpMaxAtrPct            = 3.00;     // Max ATR / fiyat (%)
input bool                InpUseAtrPercentile     = true;     // ATR yuzdelik filtresi
input int                 InpAtrPctileLookback    = 500;      // ATR yuzdelik geriye bakis
input double              InpAtrPctileMin         = 10.0;     // Min ATR yuzdeligi
input double              InpAtrPctileMax         = 97.0;     // Max ATR yuzdeligi

input group "=== 6) Spread / seans / gun ==="
input bool                InpUseSpreadFilter      = true;     // Spread filtresi
input double              InpMaxSpreadPct         = 0.05;     // Maks spread / fiyat (%)
input double              InpSpreadMedianMult     = 2.5;      // Spread <= medyan x bu
input bool                InpUseSessionFilter     = false;    // Seans filtresi
input int                 InpSessionStartHour     = 0;        // Baslangic saati (server)
input int                 InpSessionEndHour       = 24;       // Bitis saati (server, 24 = tum gun)
input int                 InpDayRolloverHour      = 0;        // Gun donum saati (server)

input group "=== 7) Risk yonetimi / Risk ==="
input double              InpRiskPerTradePct      = 0.50;     // Islem basina risk (% equity)
input double              InpMaxRiskPerTradePct   = 1.00;     // Islem basina sert risk tavani (%)
input double              InpMaxPortfolioRiskPct  = 3.00;     // Acik pozisyonlar toplam risk tavani (%)
input bool                InpUseVolTarget         = true;     // Volatilite hedefli risk olcekleme
input int                 InpVolTargetLookback    = 200;      // Vol hedef geriye bakis
input double              InpVolTargetMin         = 0.50;     // Vol olcek alt sinir
input double              InpVolTargetMax         = 1.50;     // Vol olcek ust sinir
input double              InpMaxDailyLossPct      = 2.00;     // Gunluk zarar limiti (%)
input bool                InpCloseAllOnDailyLoss  = true;     // Limitte tum pozisyonlari kapat
input double              InpMaxTotalDrawdownPct  = 15.0;     // Toplam DD kill-switch (% 0=kapali)
input int                 InpMaxConsecutiveLosses = 3;        // Ardisik zarar sonrasi duraklat
input int                 InpLossStreakPauseHours = 12;       // Duraklatma suresi (saat)
input double              InpMaxMarginUsagePct    = 30.0;     // Maks marjin / equity (%)
input bool                InpResetRiskLocksOnInit = false;    // Kilidi elle sifirla (dikkat)

input group "=== 8) Cikis yonetimi / Exit management ==="
input double              InpBreakevenAtR         = 1.0;      // Breakeven tetigi (R)
input double              InpBreakevenOffsetR     = 0.10;     // Breakeven tamponu (R)
input double              InpTrendPartialAtR      = 1.5;      // Trend kismi kapatma (R)
input double              InpRangePartialAtR      = 1.0;      // Range kismi kapatma (R)
input double              InpPartialClosePct      = 50.0;     // Kismi kapatma orani (%)
input double              InpTrailMinStepAtr      = 0.15;     // Trail guncelleme esigi (x ATR)
input double              InpTimeStopMinR         = 0.75;     // Zaman stopunda kabul edilen min R

input group "=== 9) Test / optimizasyon ==="
input bool                InpUseRiskAdjustedScore = true;     // OnTester: risk ayarli skor
input int                 InpOptimizationMinTrades= 40;       // Optimizasyon min islem sayisi

//+------------------------------------------------------------------+
//| Global state                                                     |
//+------------------------------------------------------------------+
CTrade   trade;

int      g_trend_magic = 0;
int      g_range_magic = 0;
bool     g_is_netting  = false;
bool     g_allow_partial = true;

int      h_atr      = INVALID_HANDLE;
int      h_ema_fast = INVALID_HANDLE;
int      h_ema_slow = INVALID_HANDLE;
int      h_h4_ema   = INVALID_HANDLE;
int      h_adx      = INVALID_HANDLE;
int      h_rsi      = INVALID_HANDLE;
int      h_bb       = INVALID_HANDLE;

bool     g_data_ok          = false;
double   g_atr              = 0.0;
double   g_atr_pct          = 0.0;
double   g_atr_pctile       = 50.0;
double   g_vol_scale        = 1.0;
double   g_ema_fast         = 0.0;
double   g_ema_slow         = 0.0;
double   g_adx              = 0.0;
double   g_rsi              = 0.0;
double   g_bb_up            = 0.0;
double   g_bb_mid           = 0.0;
double   g_bb_low           = 0.0;
double   g_h4_slope_pct     = 0.0;
bool     g_h4_bull          = false;
bool     g_h4_bear          = false;
bool     g_h4_flat          = true;
bool     g_h4_ok            = false;
double   g_last_close       = 0.0;

datetime g_last_bar_time    = 0;
datetime g_last_manage_time = 0;
bool     g_bar_evaluated    = false;
datetime g_last_state_retry = 0;

// Spread ring buffer (median filter)
double   g_spread_ring[256];
int      g_spread_pos   = 0;
int      g_spread_count = 0;
double   g_spread_median= 0.0;

// Risk / equity guards
datetime g_day_start        = 0;
double   g_day_equity       = 0.0;
double   g_peak_equity      = 0.0;
bool     g_daily_halted     = false;
bool     g_dd_halted        = false;
bool     g_liquidate_all    = false;
string   g_halt_reason      = "";
int      g_consecutive_losses = 0;
datetime g_last_loss_time   = 0;
datetime g_pause_until      = 0;
datetime g_last_risk_save   = 0;
datetime g_last_riskstats   = 0;

// Position state
struct SPosState
  {
   ulong    ticket;
   ulong    position_id;
   double   entry;
   double   init_risk;
   double   init_atr;
   datetime open_time;
   bool     partial_done;
   int      engine;
  };

SPosState g_states[];

datetime ComputeDayStart(const datetime now);

// Diagnostics
string   g_last_block    = "";
string   g_last_action   = "Baslatiliyor";

//+------------------------------------------------------------------+
//| Small utilities                                                  |
//+------------------------------------------------------------------+
uint HashText(const string text)
  {
   uint hash = 2166136261;
   for(int i=0; i<StringLen(text); i++)
     {
      hash ^= (uint)StringGetCharacter(text,i);
      hash *= 16777619;
     }
   return hash;
  }

string EngineName(const int engine)
  {
   if(engine == ENGINE_TREND)
      return "TREND";
   if(engine == ENGINE_RANGE)
      return "RANGE";
   return "NONE";
  }

int EngineFromMagic(const long magic)
  {
   if(magic == (long)g_trend_magic)
      return ENGINE_TREND;
   if(magic == (long)g_range_magic)
      return ENGINE_RANGE;
   return ENGINE_NONE;
  }

ulong MagicForEngine(const int engine)
  {
   if(engine == ENGINE_RANGE)
      return (ulong)g_range_magic;
   return (ulong)g_trend_magic;
  }

string SideName(const int side)
  {
   if(side > 0)
      return "LONG";
   if(side < 0)
      return "SHORT";
   return "FLAT";
  }

void LogMsg(const string message)
  {
   if(!InpVerboseLog)
      return;
   PrintFormat("%s | %s",TimeToString(TimeCurrent(),TIME_DATE|TIME_SECONDS),message);
  }

double Equity()
  {
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq <= 0.0)
      eq = AccountInfoDouble(ACCOUNT_BALANCE);
   return eq;
  }

double CurrentSpread()
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return 0.0;
   if(tick.ask <= 0.0 || tick.bid <= 0.0)
      return 0.0;
   return MathMax(0.0,tick.ask - tick.bid);
  }

double TickSize()
  {
   double size = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(size <= 0.0)
      size = _Point;
   if(size <= 0.0)
      size = 0.00001;
   return size;
  }

double NormalizePrice(const double price)
  {
   double tick = TickSize();
   if(price <= 0.0 || tick <= 0.0)
      return NormalizeDouble(price,_Digits);
   double units = MathRound(price / tick);
   return NormalizeDouble(units * tick,_Digits);
  }

double MinStopDistance()
  {
   long stops  = (long)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freeze = (long)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   long levels = stops;
   if(freeze > levels)
      levels = freeze;
   double distance = (double)levels * _Point;
   distance = MathMax(distance,CurrentSpread() * 1.5);
   distance = MathMax(distance,TickSize());
   return distance;
  }

void VolumeLimits(double &vmin,double &vmax,double &vstep)
  {
   vmin  = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   vmax  = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   vstep = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(vmin <= 0.0)
      vmin = 0.01;
   if(vmax <= 0.0)
      vmax = 1000.0;
   if(vstep <= 0.0)
      vstep = 0.01;
  }

double PartialVolume(const double position_volume,const double percent)
  {
   if(position_volume <= 0.0 || percent <= 0.0)
      return 0.0;
   double vmin,vmax,vstep;
   VolumeLimits(vmin,vmax,vstep);
   double raw  = position_volume * percent / 100.0;
   double part = MathFloor(raw / vstep + 1.0e-9) * vstep;
   part = NormalizeDouble(part,8);
   if(part < vmin)
      return 0.0;
   if(position_volume - part < vmin - 1.0e-12)
      return 0.0;
   if(part >= position_volume)
      return 0.0;
   return part;
  }

//+------------------------------------------------------------------+
//| Persistence keys                                                 |
//+------------------------------------------------------------------+
uint g_instance_tag = 0;

uint InstanceHash()
  {
   if(g_instance_tag == 0)
     {
      string seed = StringFormat("%s_%I64d_%I64u",
                                 _Symbol,(long)AccountInfoInteger(ACCOUNT_LOGIN),(ulong)InpMagicBase);
      g_instance_tag = HashText(seed);
      if(g_instance_tag == 0)
         g_instance_tag = 1;
     }
   return g_instance_tag;
  }

// MT5 global variable names are limited to 63 characters: keep them short.
string RiskKey(const string field)
  {
   return StringFormat("BAA_%08X_%s",InstanceHash(),field);
  }

string PosKey(const ulong ticket,const string field)
  {
   uint ticket_hash = HashText(StringFormat("%I64u",ticket));
   return StringFormat("BAA_%08X_%08X_%s",InstanceHash(),ticket_hash,field);
  }

void SaveRiskState()
  {
   if(MQLInfoInteger(MQL_TESTER))
      return;
   if(g_peak_equity <= 0.0 || g_day_equity <= 0.0)
      return; // do not overwrite saved risk state if initialization failed early
   GlobalVariableSet(RiskKey("DAYT"),(double)g_day_start);
   GlobalVariableSet(RiskKey("DAYEQ"),g_day_equity);
   GlobalVariableSet(RiskKey("PEAK"),g_peak_equity);
   GlobalVariableSet(RiskKey("DDH"),(g_dd_halted ? 1.0 : 0.0));
   GlobalVariablesFlush();
   g_last_risk_save = TimeCurrent();
  }

void LoadRiskState()
  {
   double eq = Equity();
   g_day_start   = 0;
   g_day_equity  = eq;
   g_peak_equity = eq;
   g_dd_halted   = false;
   g_daily_halted= false;

   if(MQLInfoInteger(MQL_TESTER))
      return;

   if(InpResetRiskLocksOnInit)
     {
      GlobalVariableDel(RiskKey("DAYT"));
      GlobalVariableDel(RiskKey("DAYEQ"));
      GlobalVariableDel(RiskKey("PEAK"));
      GlobalVariableDel(RiskKey("DDH"));
      LogMsg("Risk kilitleri elle sifirlandi.");
      return;
     }

   if(GlobalVariableCheck(RiskKey("PEAK")))
     {
      double saved_peak = GlobalVariableGet(RiskKey("PEAK"));
      if(saved_peak > g_peak_equity)
         g_peak_equity = saved_peak;
     }

   datetime today = ComputeDayStart(TimeCurrent());
   if(GlobalVariableCheck(RiskKey("DAYT")) && GlobalVariableCheck(RiskKey("DAYEQ")))
     {
      datetime saved_day = (datetime)GlobalVariableGet(RiskKey("DAYT"));
      double saved_eq    = GlobalVariableGet(RiskKey("DAYEQ"));
      if(saved_day == (datetime)today && saved_eq > 0.0)
        {
         g_day_start  = saved_day;
         g_day_equity = saved_eq;
        }
     }

   if(GlobalVariableCheck(RiskKey("DDH")) && GlobalVariableGet(RiskKey("DDH")) > 0.5)
     {
      g_dd_halted  = true;
      g_halt_reason= "Maksimum toplam DD kilidi (onceki oturum)";
     }
  }

void PersistState(const SPosState &st)
  {
   if(MQLInfoInteger(MQL_TESTER))
      return;
   GlobalVariableSet(PosKey(st.ticket,"E"),st.entry);
   GlobalVariableSet(PosKey(st.ticket,"R"),st.init_risk);
   GlobalVariableSet(PosKey(st.ticket,"A"),st.init_atr);
   GlobalVariableSet(PosKey(st.ticket,"P"),(st.partial_done ? 1.0 : 0.0));
   GlobalVariablesFlush();
  }

void DeleteStateGV(const ulong ticket)
  {
   if(MQLInfoInteger(MQL_TESTER))
      return;
   GlobalVariableDel(PosKey(ticket,"E"));
   GlobalVariableDel(PosKey(ticket,"R"));
   GlobalVariableDel(PosKey(ticket,"A"));
   GlobalVariableDel(PosKey(ticket,"P"));
  }

void LoadStateGV(SPosState &st)
  {
   if(MQLInfoInteger(MQL_TESTER))
      return;
   if(GlobalVariableCheck(PosKey(st.ticket,"R")))
     {
      double saved_risk = GlobalVariableGet(PosKey(st.ticket,"R"));
      if(saved_risk > 0.0)
         st.init_risk = saved_risk;
     }
   if(GlobalVariableCheck(PosKey(st.ticket,"A")))
     {
      double saved_atr = GlobalVariableGet(PosKey(st.ticket,"A"));
      if(saved_atr > 0.0)
         st.init_atr = saved_atr;
     }
   if(GlobalVariableCheck(PosKey(st.ticket,"P")))
      st.partial_done = (GlobalVariableGet(PosKey(st.ticket,"P")) > 0.5);
  }

//+------------------------------------------------------------------+
//| Position state map                                               |
//+------------------------------------------------------------------+
int FindState(const ulong ticket)
  {
   for(int i=ArraySize(g_states)-1; i>=0; i--)
      if(g_states[i].ticket == ticket)
         return i;
   return -1;
  }

void AddState(const SPosState &st)
  {
   int idx = FindState(st.ticket);
   if(idx >= 0)
     {
      g_states[idx] = st;
      return;
     }
   int n = ArraySize(g_states);
   if(ArrayResize(g_states,n + 1) >= n + 1)
      g_states[n] = st;
  }

void RemoveStateAt(const int idx)
  {
   int n = ArraySize(g_states);
   if(idx < 0 || idx >= n)
      return;
   DeleteStateGV(g_states[idx].ticket);
   for(int i=idx; i<n-1; i++)
      g_states[i] = g_states[i + 1];
   ArrayResize(g_states,n - 1);
  }

bool SelectOurPosition(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket))
      return false;
   if(PositionGetString(POSITION_SYMBOL) != _Symbol)
      return false;
   long magic = PositionGetInteger(POSITION_MAGIC);
   return (EngineFromMagic(magic) != ENGINE_NONE);
  }

bool EnsureState(const ulong ticket,SPosState &st)
  {
   int idx = FindState(ticket);
   if(idx >= 0)
     {
      st = g_states[idx];
      return true;
     }

   if(!SelectOurPosition(ticket))
      return false;

   st.ticket      = ticket;
   st.position_id = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   st.entry       = PositionGetDouble(POSITION_PRICE_OPEN);
   st.open_time   = (datetime)PositionGetInteger(POSITION_TIME);
   st.partial_done= false;
   st.engine      = EngineFromMagic(PositionGetInteger(POSITION_MAGIC));
   st.init_atr    = g_atr;

   double sl = PositionGetDouble(POSITION_SL);
   if(sl > 0.0)
      st.init_risk = MathAbs(st.entry - sl);
   else
     {
      double atr_mult = (st.engine == ENGINE_RANGE ? InpRangeSlAtr : InpTrendSlAtr);
      st.init_risk = (g_atr > 0.0 ? g_atr * atr_mult : 0.0);
     }

   LoadStateGV(st);
   if(st.init_risk <= 0.0)
      st.init_risk = MathMax(TickSize(),MinStopDistance());

   AddState(st);
   return true;
  }

void PruneStates()
  {
   for(int i=ArraySize(g_states)-1; i>=0; i--)
     {
      if(!PositionSelectByTicket(g_states[i].ticket))
         RemoveStateAt(i);
     }
  }

int CountOurPositions(const int side_filter,const int engine_filter)
  {
   int count = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      int side = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1);
      int engine = EngineFromMagic(PositionGetInteger(POSITION_MAGIC));
      if(side_filter != 0 && side != side_filter)
         continue;
      if(engine_filter != ENGINE_NONE && engine != engine_filter)
         continue;
      count++;
     }
   return count;
  }

bool HasOppositeSide(const int side)
  {
   return (CountOurPositions(-side,ENGINE_NONE) > 0);
  }

bool PositionOpenByID(const ulong position_id)
  {
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if((ulong)PositionGetInteger(POSITION_IDENTIFIER) == position_id)
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Indicator and market-state refresh                               |
//+------------------------------------------------------------------+
double BufferValue(const int handle,const int buffer,const int shift)
  {
   if(handle == INVALID_HANDLE)
      return EMPTY_VALUE;
   double values[];
   if(CopyBuffer(handle,buffer,shift,1,values) < 1)
      return EMPTY_VALUE;
   return values[0];
  }

void UpdateSpreadMedian()
  {
   if(g_spread_count < 20)
     {
      g_spread_median = 0.0;
      return;
     }
   double values[];
   if(ArrayResize(values,g_spread_count) < g_spread_count)
      return;
   for(int i=0; i<g_spread_count; i++)
      values[i] = g_spread_ring[i];
   ArraySort(values);
   g_spread_median = values[g_spread_count / 2];
  }

void SampleSpread(const double spread)
  {
   if(spread <= 0.0)
      return;
   g_spread_ring[g_spread_pos] = spread;
   g_spread_pos = (g_spread_pos + 1) % 256;
   if(g_spread_count < 256)
      g_spread_count++;
  }

void UpdateMarketState()
  {
   g_data_ok = false;
   double atr = BufferValue(h_atr,0,1);
   double c1  = iClose(_Symbol,InpSignalTimeframe,1);
   double ema_fast = BufferValue(h_ema_fast,0,1);
   double ema_slow = BufferValue(h_ema_slow,0,1);

   if(atr == EMPTY_VALUE || atr <= 0.0 || c1 <= 0.0 ||
      ema_fast == EMPTY_VALUE || ema_slow == EMPTY_VALUE)
     {
      g_last_block = "Indikator verisi hazir degil";
      return;
     }

   g_atr        = atr;
   g_last_close = c1;
   g_atr_pct    = atr / c1 * 100.0;
   g_ema_fast   = ema_fast;
   g_ema_slow   = ema_slow;

   // ATR percentile and volatility targeting from the same window.
   g_atr_pctile = 50.0;
   g_vol_scale  = 1.0;
   int pct_bars = (int)MathMax(50.0,(double)InpAtrPctileLookback);
   int vol_bars = (int)MathMax(50.0,(double)InpVolTargetLookback);
   int lookback = (int)MathMax((double)pct_bars,(double)vol_bars);
   double atr_hist[];
   double close_hist[];
   int na = CopyBuffer(h_atr,0,1,lookback,atr_hist);
   int nc = CopyClose(_Symbol,InpSignalTimeframe,1,lookback,close_hist);
   int n  = (int)MathMin((double)na,(double)nc);
   if(n >= 20)
     {
      int pct_n = (int)MathMin((double)n,(double)pct_bars);
      int below = 0;
      double ratio_sum = 0.0;
      int ratio_n = 0;
      for(int i=0; i<pct_n; i++)
        {
         if(atr_hist[i] > 0.0 && close_hist[i] > 0.0 && atr_hist[i] < g_atr)
            below++;
        }
      int vol_n = (int)MathMin((double)n,(double)vol_bars);
      for(int i=0; i<vol_n; i++)
        {
         if(atr_hist[i] > 0.0 && close_hist[i] > 0.0)
           {
            ratio_sum += atr_hist[i] / close_hist[i];
            ratio_n++;
           }
        }
      if(pct_n > 0)
         g_atr_pctile = 100.0 * (double)below / (double)pct_n;
      if(InpUseVolTarget && ratio_n > 10)
        {
         double avg_ratio = ratio_sum / (double)ratio_n;
         double cur_ratio = g_atr / c1;
         if(cur_ratio > 1.0e-9)
           {
            g_vol_scale = avg_ratio / cur_ratio;
            g_vol_scale = MathMax(InpVolTargetMin,MathMin(InpVolTargetMax,g_vol_scale));
           }
        }
     }

   // ADX / RSI / Bollinger
   double adx = BufferValue(h_adx,0,1);
   double rsi = BufferValue(h_rsi,0,1);
   double bb_up  = BufferValue(h_bb,1,1);
   double bb_mid = BufferValue(h_bb,0,1);
   double bb_low = BufferValue(h_bb,2,1);
   g_adx    = (adx == EMPTY_VALUE ? 0.0 : adx);
   g_rsi    = (rsi == EMPTY_VALUE ? 50.0 : rsi);
   g_bb_up  = (bb_up == EMPTY_VALUE ? 0.0 : bb_up);
   g_bb_mid = (bb_mid == EMPTY_VALUE ? 0.0 : bb_mid);
   g_bb_low = (bb_low == EMPTY_VALUE ? 0.0 : bb_low);

   // H4 regime
   g_h4_bull = false;
   g_h4_bear = false;
   g_h4_flat = true;
   g_h4_ok   = false;
   g_h4_slope_pct = 0.0;
   double h4_ema_now  = BufferValue(h_h4_ema,0,1);
   double h4_ema_past = BufferValue(h_h4_ema,0,1 + InpH4SlopeBars);
   double h4_close    = iClose(_Symbol,InpRegimeTimeframe,1);
   if(h4_ema_now != EMPTY_VALUE && h4_ema_past != EMPTY_VALUE &&
      h4_ema_now > 0.0 && h4_close > 0.0)
     {
      g_h4_slope_pct = (h4_ema_now - h4_ema_past) / h4_ema_now * 100.0;
      g_h4_bull = (h4_close > h4_ema_now && g_h4_slope_pct > 0.0);
      g_h4_bear = (h4_close < h4_ema_now && g_h4_slope_pct < 0.0);
      g_h4_flat = (MathAbs(g_h4_slope_pct) <= InpRangeMaxH4SlopePct);
      g_h4_ok   = true;
     }
   else
     {
      g_last_block = "H4 rejim verisi hazir degil";
     }

   g_data_ok = (MathAbs(g_atr) > 0.0 && MathIsValidNumber(g_atr));
  }

//+------------------------------------------------------------------+
//| Signal logic (closed bars only)                                  |
//+------------------------------------------------------------------+
bool FreshBreakout(const int side,const int bars)
  {
   double highs[];
   double lows[];
   int count = (int)MathMax((double)bars,2.0);
   if(side > 0)
     {
      if(CopyHigh(_Symbol,InpSignalTimeframe,3,count,highs) < count)
         return false;
      double upper = highs[ArrayMaximum(highs,0,count)];
      double prev_close = iClose(_Symbol,InpSignalTimeframe,2);
      return (prev_close > 0.0 && prev_close <= upper);
     }
   if(CopyLow(_Symbol,InpSignalTimeframe,3,count,lows) < count)
      return false;
   double lower = lows[ArrayMinimum(lows,0,count)];
   double prev_close = iClose(_Symbol,InpSignalTimeframe,2);
   return (prev_close > 0.0 && prev_close >= lower);
  }

bool TrendSignal(int &side_out)
  {
   side_out = 0;
   if(!g_data_ok)
      return false;
   if(InpUseH4Regime && !g_h4_ok)
      return false;
   if(InpUseH4Regime && !g_h4_bull && !g_h4_bear)
      return false;
   if(InpTrendMinAdx > 0.0 && g_adx < InpTrendMinAdx)
      return false;

   double close1 = iClose(_Symbol,InpSignalTimeframe,1);
   if(close1 <= 0.0)
      return false;

   int bars = (int)MathMax((double)InpDonchianBars,2.0);
   double highs[];
   double lows[];
   if(CopyHigh(_Symbol,InpSignalTimeframe,2,bars,highs) < bars)
      return false;
   if(CopyLow(_Symbol,InpSignalTimeframe,2,bars,lows) < bars)
      return false;
   double upper = highs[ArrayMaximum(highs,0,bars)];
   double lower = lows[ArrayMinimum(lows,0,bars)];

   bool long_ok = ((!InpUseH4Regime || g_h4_bull) &&
                   g_ema_fast > g_ema_slow &&
                   close1 > g_ema_fast &&
                   close1 > upper);
   bool short_ok = ((!InpUseH4Regime || g_h4_bear) &&
                    g_ema_fast < g_ema_slow &&
                    close1 < g_ema_fast &&
                    close1 < lower);

   if(InpRequireFreshBreakout)
     {
      if(long_ok && !FreshBreakout(1,bars))
         long_ok = false;
      if(short_ok && !FreshBreakout(-1,bars))
         short_ok = false;
     }

   if(long_ok && !short_ok)
     {
      side_out = 1;
      return true;
     }
   if(short_ok && !long_ok)
     {
      side_out = -1;
      return true;
     }
   return false;
  }

bool RangeSignal(int &side_out)
  {
   side_out = 0;
   if(!g_data_ok)
      return false;
   if(InpUseH4Regime && (!g_h4_ok || !g_h4_flat))
      return false;
   if(g_adx >= InpRangeMaxAdx)
      return false;
   if(InpUseAtrPercentile && g_atr_pctile > (double)InpRangeMaxAtrPctile)
      return false;
   double close1 = iClose(_Symbol,InpSignalTimeframe,1);
   if(close1 <= 0.0 || g_bb_low <= 0.0 || g_bb_up <= 0.0)
      return false;

   if(close1 < g_bb_low && g_rsi < InpRangeRsiBuy)
     {
      side_out = 1;
      return true;
     }
   if(close1 > g_bb_up && g_rsi > InpRangeRsiSell)
     {
      side_out = -1;
      return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Day anchor, loss streak and equity guards                        |
//+------------------------------------------------------------------+
datetime ComputeDayStart(const datetime now)
  {
   MqlDateTime parts;
   TimeToStruct(now,parts);
   parts.hour = 0;
   parts.min  = 0;
   parts.sec  = 0;
   datetime midnight = StructToTime(parts);
   datetime start = (datetime)((long)midnight + (long)InpDayRolloverHour * 3600);
   if(now < start)
      start = (datetime)((long)start - 86400);
   return start;
  }

void RefreshDailyAnchor()
  {
   datetime day_start = ComputeDayStart(TimeCurrent());
   if(g_day_start == 0)
     {
      g_day_start  = day_start;
      g_day_equity = Equity();
      SaveRiskState();
      return;
     }
   if(day_start != g_day_start)
     {
      g_day_start    = day_start;
      g_day_equity   = Equity();
      g_daily_halted = false;
      if(!g_dd_halted && !g_liquidate_all)
         g_halt_reason = "";
      SaveRiskState();
      LogMsg(StringFormat("Yeni islem gunu. Baslangic equity=%.2f %s",
                          g_day_equity,AccountInfoString(ACCOUNT_CURRENCY)));
     }
  }

struct SClosedPos
  {
   ulong    pid;
   double   net;
   datetime close_time;
  };

int FindClosedIndex(SClosedPos &list[],const ulong pid)
  {
   for(int i=ArraySize(list)-1; i>=0; i--)
      if(list[i].pid == pid)
         return i;
   return -1;
  }

int CountConsecutiveLosses(datetime &last_loss_time)
  {
   last_loss_time = 0;
   datetime from = TimeCurrent() - 60 * 86400;
   if(!HistorySelect(from,TimeCurrent() + 300))
      return 0;

   int total_deals = HistoryDealsTotal();
   SClosedPos raw[];
   for(int i=0; i<total_deals; i++)
     {
      ulong deal = HistoryDealGetTicket(i);
      if(deal == 0)
         continue;
      if(HistoryDealGetString(deal,DEAL_SYMBOL) != _Symbol)
         continue;
      long magic = HistoryDealGetInteger(deal,DEAL_MAGIC);
      if(EngineFromMagic(magic) == ENGINE_NONE)
         continue;
      long deal_type = HistoryDealGetInteger(deal,DEAL_TYPE);
      if(deal_type != DEAL_TYPE_BUY && deal_type != DEAL_TYPE_SELL)
         continue;
      ulong pid = (ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
      if(pid == 0)
         continue;
      int idx = FindClosedIndex(raw,pid);
      if(idx < 0)
        {
         idx = ArraySize(raw);
         if(ArrayResize(raw,idx + 1) < idx + 1)
            continue;
         raw[idx].pid        = pid;
         raw[idx].net        = 0.0;
         raw[idx].close_time = 0;
        }
      raw[idx].net += HistoryDealGetDouble(deal,DEAL_PROFIT)
                    + HistoryDealGetDouble(deal,DEAL_SWAP)
                    + HistoryDealGetDouble(deal,DEAL_COMMISSION);
      long entry_kind = HistoryDealGetInteger(deal,DEAL_ENTRY);
      if(entry_kind == DEAL_ENTRY_OUT || entry_kind == DEAL_ENTRY_OUT_BY ||
         entry_kind == DEAL_ENTRY_INOUT)
        {
         datetime t = (datetime)HistoryDealGetInteger(deal,DEAL_TIME);
         if(t > raw[idx].close_time)
            raw[idx].close_time = t;
        }
     }

   SClosedPos closed[];
   for(int i=0; i<ArraySize(raw); i++)
     {
      if(raw[i].close_time <= 0)
         continue;
      if(PositionOpenByID(raw[i].pid))
         continue;
      int n = ArraySize(closed);
      if(ArrayResize(closed,n + 1) < n + 1)
         continue;
      closed[n] = raw[i];
     }

   // Newest first.
   for(int i=1; i<ArraySize(closed); i++)
     {
      SClosedPos key = closed[i];
      int j = i - 1;
      while(j >= 0 && closed[j].close_time < key.close_time)
        {
         closed[j + 1] = closed[j];
         j--;
        }
      closed[j + 1] = key;
     }

   int count = 0;
   for(int i=0; i<ArraySize(closed); i++)
     {
      if(closed[i].net < 0.0)
        {
         if(count == 0)
            last_loss_time = closed[i].close_time;
         count++;
        }
      else
         break;
     }
   return count;
  }

void UpdateRiskStats()
  {
   datetime last_loss = 0;
   g_consecutive_losses = CountConsecutiveLosses(last_loss);
   g_last_loss_time = last_loss;
   if(g_consecutive_losses >= InpMaxConsecutiveLosses &&
      InpMaxConsecutiveLosses > 0 && InpLossStreakPauseHours > 0 && last_loss > 0)
      g_pause_until = (datetime)((long)last_loss + (long)InpLossStreakPauseHours * 3600);
   else
      g_pause_until = 0;
  }

bool LossStreakPauseActive()
  {
   if(g_pause_until > 0 && TimeCurrent() < g_pause_until)
      return true;
   return false;
  }

bool SessionOK()
  {
   if(!InpUseSessionFilter)
      return true;
   int start = InpSessionStartHour;
   int end   = InpSessionEndHour;
   if(start == end || (start == 0 && end >= 24))
      return true;
   MqlDateTime parts;
   TimeToStruct(TimeCurrent(),parts);
   int hour = parts.hour;
   if(start < end)
      return (hour >= start && hour < end);
   return (hour >= start || hour < end);
  }

bool SpreadOK()
  {
   double spread = CurrentSpread();
   if(spread <= 0.0)
      return true; // zero-spread quote or missing data: nothing to filter
   if(!InpUseSpreadFilter)
      return true;
   MqlTick tick;
   if(SymbolInfoTick(_Symbol,tick) && tick.bid > 0.0 && InpMaxSpreadPct > 0.0)
     {
      double cap = tick.bid * InpMaxSpreadPct / 100.0;
      if(spread > cap)
        {
         g_last_block = StringFormat("Spread mutlak limit: %.*f > %.*f",_Digits,spread,_Digits,cap);
         return false;
        }
     }
   if(g_spread_median > 0.0 && spread > g_spread_median * InpSpreadMedianMult)
     {
      g_last_block = StringFormat("Spread medyanin %.1fx uzerinde: %.*f / med %.*f",
                                  InpSpreadMedianMult,_Digits,spread,_Digits,g_spread_median);
      return false;
     }
   return true;
  }

void CloseAllPositions(const string reason)
  {
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      if(trade.PositionClose(ticket,(ulong)InpDeviationPoints))
         LogMsg(StringFormat("Pozisyon kapatildi #%I64u: %s",ticket,reason));
      else
         LogMsg(StringFormat("Pozisyon kapatma basarisiz #%I64u rc=%u (%s)",
                             ticket,trade.ResultRetcode(),trade.ResultRetcodeDescription()));
     }
  }

void SetDailyHalt(const string reason,bool close_all)
  {
   if(g_daily_halted)
      return;
   g_daily_halted = true;
   g_halt_reason  = reason;
   if(close_all)
      g_liquidate_all = true;
   LogMsg("GUNLUK RISK KILIDI: " + reason);
   SaveRiskState();
  }

void SetDrawdownHalt(const string reason)
  {
   if(g_dd_halted)
      return;
   g_dd_halted     = true;
   g_liquidate_all = true;
   g_halt_reason   = reason;
   LogMsg("TOPLAM DD KILIDI: " + reason);
   SaveRiskState();
  }

void UpdateEquityGuards()
  {
   double eq = Equity();
   if(eq <= 0.0)
      return;

   if(eq > g_peak_equity)
      g_peak_equity = eq;

   if(InpMaxTotalDrawdownPct > 0.0 && g_peak_equity > 0.0)
     {
      double dd_pct = (1.0 - eq / g_peak_equity) * 100.0;
      if(dd_pct >= InpMaxTotalDrawdownPct)
         SetDrawdownHalt(StringFormat("Toplam DD %.2f%% >= %.2f%%",dd_pct,InpMaxTotalDrawdownPct));
     }

   if(InpMaxDailyLossPct > 0.0 && g_day_equity > 0.0)
     {
      double day_pct = (1.0 - eq / g_day_equity) * 100.0;
      if(day_pct >= InpMaxDailyLossPct)
         SetDailyHalt(StringFormat("Gunluk zarar %.2f%% >= %.2f%%",day_pct,InpMaxDailyLossPct),
                      InpCloseAllOnDailyLoss);
     }

   if(g_liquidate_all)
     {
      CloseAllPositions(g_halt_reason);
      if(CountOurPositions(0,ENGINE_NONE) == 0)
         g_liquidate_all = false;
     }
  }

bool TradingEnabled()
  {
   if(g_dd_halted || g_daily_halted)
      return false;
   if(!TerminalInfoInteger(TERMINAL_TRADE_ALLOWED))
     {
      g_last_block = "Terminal ticareti kapali";
      return false;
     }
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED))
     {
      g_last_block = "EA ticareti kapali";
      return false;
     }
   if(!AccountInfoInteger(ACCOUNT_TRADE_ALLOWED))
     {
      g_last_block = "Hesap ticareti kapali";
      return false;
     }
   if(!AccountInfoInteger(ACCOUNT_TRADE_EXPERT))
     {
      g_last_block = "Hesapta EA izni kapali";
      return false;
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Risk sizing and order execution                                  |
//+------------------------------------------------------------------+
double CurrentOpenRisk()
  {
   double total = 0.0;
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      long type  = PositionGetInteger(POSITION_TYPE);
      double vol = PositionGetDouble(POSITION_VOLUME);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sl  = PositionGetDouble(POSITION_SL);
      if(vol <= 0.0 || entry <= 0.0)
         continue;
      if(sl <= 0.0)
        {
         int engine = EngineFromMagic(PositionGetInteger(POSITION_MAGIC));
         double mult = (engine == ENGINE_RANGE ? InpRangeSlAtr : InpTrendSlAtr);
         if(g_atr <= 0.0)
            continue;
         sl = (type == POSITION_TYPE_BUY ? entry - g_atr * mult : entry + g_atr * mult);
        }
      double profit = 0.0;
      ENUM_ORDER_TYPE ot = (type == POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
      if(OrderCalcProfit(ot,_Symbol,vol,entry,sl,profit))
         total += MathAbs(profit);
     }
   return total;
  }

double BaseRiskMoney(const int engine)
  {
   double eq = Equity();
   if(eq <= 0.0)
      return 0.0;
   double pct = InpRiskPerTradePct;
   if(engine == ENGINE_RANGE)
      pct *= InpRangeRiskScale;
   double risk = eq * pct / 100.0;
   if(InpUseVolTarget)
      risk *= g_vol_scale;
   double cap = eq * InpMaxRiskPerTradePct / 100.0;
   if(risk > cap)
      risk = cap;

   double open_risk = CurrentOpenRisk();
   double budget = eq * InpMaxPortfolioRiskPct / 100.0 - open_risk;
   if(risk > budget)
      risk = budget;

   double min_relevant = eq * InpRiskPerTradePct / 100.0 * 0.20;
   if(risk < min_relevant)
      return 0.0;
   return risk;
  }

double CalcLots(const ENUM_ORDER_TYPE type,const double entry,const double sl,
                const double risk_money,double &actual_risk)
  {
   actual_risk = 0.0;
   if(risk_money <= 0.0 || entry <= 0.0 || sl <= 0.0)
      return 0.0;

   double loss_per_lot = 0.0;
   double profit = 0.0;
   if(OrderCalcProfit(type,_Symbol,1.0,entry,sl,profit) && profit < 0.0)
      loss_per_lot = -profit;

   if(loss_per_lot <= 1.0e-9)
     {
      double tick = TickSize();
      double tick_value = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
      if(tick_value <= 0.0)
         tick_value = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE_LOSS);
      if(tick > 0.0 && tick_value > 0.0)
         loss_per_lot = MathAbs(entry - sl) / tick * tick_value;
     }
   if(loss_per_lot <= 1.0e-9)
     {
      g_last_block = "Lot degeri hesaplanamadi (tick value)";
      return 0.0;
     }

   double lots = risk_money / loss_per_lot;
   if(InpMaxLots > 0.0 && lots > InpMaxLots)
      lots = InpMaxLots;

   double vmin,vmax,vstep;
   VolumeLimits(vmin,vmax,vstep);
   lots = MathFloor(lots / vstep + 1.0e-9) * vstep;
   if(lots > vmax)
      lots = MathFloor(vmax / vstep) * vstep;
   if(lots < vmin)
      lots = vmin;
   lots = NormalizeDouble(lots,8);
   if(lots <= 0.0)
      return 0.0;

   actual_risk = lots * loss_per_lot;
   double eq = Equity();
   if(eq > 0.0 && actual_risk > eq * InpMaxRiskPerTradePct / 100.0 * 1.000001)
     {
      g_last_block = StringFormat("Min lot bile risk tavanini asiyor: risk=%.2f %s > %.2f%% equity",
                                  actual_risk,AccountInfoString(ACCOUNT_CURRENCY),InpMaxRiskPerTradePct);
      return 0.0;
     }

   double margin = 0.0;
   if(OrderCalcMargin(type,_Symbol,lots,entry,margin) && margin > 0.0)
     {
      double free_margin = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      double used_margin = AccountInfoDouble(ACCOUNT_MARGIN);
      if(margin > free_margin * 0.90)
        {
         g_last_block = "Serbest marjin yetersiz";
         return 0.0;
        }
      if(eq > 0.0 && (used_margin + margin) / eq * 100.0 > InpMaxMarginUsagePct)
        {
         g_last_block = "Marjin kullanim limiti asiliyor";
         return 0.0;
        }
     }
   return lots;
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

bool RetryableRetcode(const uint code)
  {
   return (code == TRADE_RETCODE_REQUOTE ||
           code == TRADE_RETCODE_PRICE_CHANGED ||
           code == TRADE_RETCODE_PRICE_OFF ||
           code == TRADE_RETCODE_TIMEOUT ||
           code == TRADE_RETCODE_CONNECTION);
  }

ulong FindPositionTicket(const ulong deal,const int engine,const int side)
  {
   if(deal > 0 && HistoryDealSelect(deal))
     {
      ulong pid = (ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
      if(pid > 0)
        {
         for(int i=PositionsTotal()-1; i>=0; i--)
           {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket))
               continue;
            if(PositionGetString(POSITION_SYMBOL) != _Symbol)
               continue;
            if(EngineFromMagic(PositionGetInteger(POSITION_MAGIC)) != engine)
               continue;
            if((ulong)PositionGetInteger(POSITION_IDENTIFIER) == pid)
               return ticket;
           }
        }
     }

   // Fallback: newest position of this engine on the expected side.
   ulong best = 0;
   long best_time = 0;
   long now = (long)TimeCurrent();
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(EngineFromMagic(PositionGetInteger(POSITION_MAGIC)) != engine)
         continue;
      int pos_side = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1);
      if(pos_side != side)
         continue;
      long t = (long)PositionGetInteger(POSITION_TIME);
      if(t + 15 < now)
         continue;
      if(t >= best_time)
        {
         best_time = t;
         best = ticket;
        }
     }
   return best;
  }

void RegisterPosition(const ulong ticket,const int engine,const double atr,const double planned_sl)
  {
   if(ticket == 0 || !PositionSelectByTicket(ticket))
      return;
   SPosState st;
   st.ticket       = ticket;
   st.position_id  = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   st.entry        = PositionGetDouble(POSITION_PRICE_OPEN);
   st.open_time    = (datetime)PositionGetInteger(POSITION_TIME);
   st.partial_done = false;
   st.engine       = engine;
   st.init_atr     = atr;
   double sl = PositionGetDouble(POSITION_SL);
   if(sl <= 0.0)
      sl = planned_sl;
   st.init_risk = MathAbs(st.entry - sl);
   if(st.init_risk <= 0.0)
      st.init_risk = MathMax(TickSize(),MinStopDistance());
   AddState(st);
   PersistState(st);
  }

bool NettingSymbolBusy()
  {
   if(!g_is_netting)
      return false;
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) == _Symbol)
         return true;
     }
   return false;
  }

bool OpenPosition(const int engine,const int side)
  {
   if(side == 0)
      return false;
   if(NettingSymbolBusy())
     {
      g_last_block = "Netting hesapta sembolde acik pozisyon var (manuel islem dahil)";
      return false;
     }
   if(!InpAllowHedge && HasOppositeSide(side))
     {
      g_last_block = "Ters yonde acik pozisyon var (hedge kapali)";
      return false;
     }
   if(g_is_netting && CountOurPositions(0,ENGINE_NONE) > 0)
     {
      g_last_block = "Netting hesapta tek pozisyon kurali";
      return false;
     }

   double risk_money = BaseRiskMoney(engine);
   if(risk_money <= 0.0)
     {
      if(g_last_block == "")
         g_last_block = "Risk butcesi yetersiz (portfoy risk limiti)";
      return false;
     }
   if(g_atr <= 0.0)
     {
      g_last_block = "ATR hazir degil";
      return false;
     }

   double atr_mult = (engine == ENGINE_RANGE ? InpRangeSlAtr : InpTrendSlAtr);
   if(atr_mult <= 0.0)
      return false;
   double tp_r = (engine == ENGINE_RANGE ? InpRangeTpR : InpTrendTpR);
   string comment = (engine == ENGINE_RANGE ? "BAA-R" : "BAA-T");

   for(int attempt=0; attempt<3; attempt++)
     {
      MqlTick tick;
      if(!SymbolInfoTick(_Symbol,tick) || tick.ask <= 0.0 || tick.bid <= 0.0)
         return false;

      double entry = (side > 0 ? tick.ask : tick.bid);
      double sl_dist = g_atr * atr_mult;
      double min_dist = MinStopDistance();
      if(sl_dist < min_dist * 1.10)
         sl_dist = min_dist * 1.10;
      double sl = (side > 0 ? entry - sl_dist : entry + sl_dist);
      double tp = 0.0;
      if(tp_r > 0.0)
         tp = (side > 0 ? entry + tp_r * sl_dist : entry - tp_r * sl_dist);

      sl = NormalizePrice(sl);
      tp = NormalizePrice(tp);

      double actual_risk = 0.0;
      ENUM_ORDER_TYPE order_type = (side > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
      double lots = CalcLots(order_type,entry,sl,risk_money,actual_risk);
      if(lots <= 0.0)
         return false;

      trade.SetExpertMagicNumber(MagicForEngine(engine));
      bool sent = (side > 0
                   ? trade.Buy(lots,_Symbol,0.0,sl,tp,comment)
                   : trade.Sell(lots,_Symbol,0.0,sl,tp,comment));
      uint code = trade.ResultRetcode();

      if(TradeRetcodeOK(sent))
        {
         ulong ticket = FindPositionTicket(trade.ResultDeal(),engine,side);
         if(ticket > 0)
            RegisterPosition(ticket,engine,g_atr,sl);
         g_last_block = "";
         g_last_action = StringFormat("%s %s acildi | lot=%.2f risk=%.2f %s",
                                      EngineName(engine),SideName(side),lots,
                                      actual_risk,AccountInfoString(ACCOUNT_CURRENCY));
         LogMsg(StringFormat("%s | entry~%.*f SL=%.*f TP=%.*f lot=%.4f planRisk=%.2f %s ATR=%.*f",
                             g_last_action,_Digits,entry,_Digits,sl,_Digits,tp,lots,
                             actual_risk,AccountInfoString(ACCOUNT_CURRENCY),
                             _Digits,g_atr));
         return true;
        }

      PrintFormat("Emir reddedildi: engine=%s side=%s lot=%.4f retcode=%u (%s) attempt=%d",
                  EngineName(engine),SideName(side),lots,code,
                  trade.ResultRetcodeDescription(),attempt + 1);
      if(!RetryableRetcode(code))
         return false;
      if(!MQLInfoInteger(MQL_TESTER))
         Sleep(250);
     }
   g_last_block = "Emir 3 denemede gerceklesmedi";
   return false;
  }

void EvaluateEntries()
  {
   if(!TradingEnabled())
      return;
   if(g_liquidate_all)
      return;
   if(!g_data_ok)
      return;
   if(!SessionOK())
     {
      g_last_block = "Seans disi";
      return;
     }
   if(!SpreadOK())
      return;
   if(g_atr_pct < InpMinAtrPct || g_atr_pct > InpMaxAtrPct)
     {
      g_last_block = StringFormat("ATR%% filtre disi: %.2f%%",g_atr_pct);
      return;
     }
   if(InpUseAtrPercentile &&
      (g_atr_pctile < InpAtrPctileMin || g_atr_pctile > InpAtrPctileMax))
     {
      g_last_block = StringFormat("ATR yuzdeligi filtre disi: %.1f",g_atr_pctile);
      return;
     }
   if(LossStreakPauseActive())
     {
      g_last_block = StringFormat("Ardisik zarar molasi: %s",TimeToString(g_pause_until,TIME_DATE|TIME_MINUTES));
      return;
     }

   int total = CountOurPositions(0,ENGINE_NONE);
   if(total >= InpMaxPositions)
      return;

   if(InpEnableTrend && CountOurPositions(0,ENGINE_TREND) == 0)
     {
      int side = 0;
      if(TrendSignal(side))
        {
         if(OpenPosition(ENGINE_TREND,side))
            return;
        }
     }

   if(InpEnableRange && CountOurPositions(0,ENGINE_RANGE) == 0 &&
      CountOurPositions(0,ENGINE_NONE) < InpMaxPositions)
     {
      int side = 0;
      if(RangeSignal(side))
         OpenPosition(ENGINE_RANGE,side);
     }
  }

//+------------------------------------------------------------------+
//| Position management                                              |
//+------------------------------------------------------------------+
bool ModifyPositionSL(const ulong ticket,const int side,const double new_sl_raw)
  {
   if(!PositionSelectByTicket(ticket))
      return false;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return false;
   double new_sl = NormalizePrice(new_sl_raw);
   double min_dist = MinStopDistance();
   if(side > 0 && new_sl > tick.bid - min_dist)
      return false;
   if(side < 0 && new_sl < tick.ask + min_dist)
      return false;
   double tp = PositionGetDouble(POSITION_TP);
   if(!trade.PositionModify(ticket,new_sl,tp))
      return false;
   return true;
  }

double HighestHighSince(const datetime from_time,const int max_bars)
  {
   // Include the current (forming) bar: its high is real information, not a look-ahead.
   int bars = iBarShift(_Symbol,InpSignalTimeframe,from_time,false);
   if(bars < 0)
      bars = 0;
   if(max_bars > 0 && bars >= max_bars)
      bars = max_bars - 1;
   double highs[];
   int copied = CopyHigh(_Symbol,InpSignalTimeframe,0,bars + 1,highs);
   if(copied <= 0)
      return 0.0;
   return highs[ArrayMaximum(highs,0,copied)];
  }

double LowestLowSince(const datetime from_time,const int max_bars)
  {
   int bars = iBarShift(_Symbol,InpSignalTimeframe,from_time,false);
   if(bars < 0)
      bars = 0;
   if(max_bars > 0 && bars >= max_bars)
      bars = max_bars - 1;
   double lows[];
   int copied = CopyLow(_Symbol,InpSignalTimeframe,0,bars + 1,lows);
   if(copied <= 0)
      return 0.0;
   return lows[ArrayMinimum(lows,0,copied)];
  }

void ManageOpenPositions(const MqlTick &tick)
  {
   ulong tickets[];
   int count = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      if(ArrayResize(tickets,count + 1) < count + 1)
         continue;
      tickets[count] = ticket;
      count++;
     }

   for(int k=0; k<count; k++)
     {
      ulong ticket = tickets[k];
      if(!SelectOurPosition(ticket))
         continue;

      SPosState st;
      if(!EnsureState(ticket,st))
         continue;

      long pos_type = PositionGetInteger(POSITION_TYPE);
      int side = (pos_type == POSITION_TYPE_BUY ? 1 : -1);
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double volume = PositionGetDouble(POSITION_VOLUME);
      double sl = PositionGetDouble(POSITION_SL);
      double close_price = (side > 0 ? tick.bid : tick.ask);
      if(close_price <= 0.0)
         continue;

      if(st.init_risk <= 0.0)
        {
         double mult = (st.engine == ENGINE_RANGE ? InpRangeSlAtr : InpTrendSlAtr);
         st.init_risk = MathMax(TickSize(),g_atr * mult);
        }
      if(st.init_risk <= 0.0)
         continue;

      double r_multiple = (side > 0
                           ? (close_price - entry) / st.init_risk
                           : (entry - close_price) / st.init_risk);

      // Repair missing protection.
      if(sl <= 0.0)
        {
         double mult = (st.engine == ENGINE_RANGE ? InpRangeSlAtr : InpTrendSlAtr);
         double repair = (side > 0 ? entry - g_atr * mult : entry + g_atr * mult);
         if(ModifyPositionSL(ticket,side,repair))
            LogMsg(StringFormat("#%I64u koruma SL'si eklendi",ticket));
        }

      // Partial profit.
      double partial_r = (st.engine == ENGINE_RANGE ? InpRangePartialAtR : InpTrendPartialAtR);
      if(g_allow_partial && !st.partial_done && InpPartialClosePct > 0.0 &&
         partial_r > 0.0 && r_multiple >= partial_r && volume > 0.0)
        {
         double part = PartialVolume(volume,InpPartialClosePct);
         if(part > 0.0)
           {
            if(trade.PositionClosePartial(ticket,part,(ulong)InpDeviationPoints))
              {
               st.partial_done = true;
               PersistState(st);
               int idx = FindState(ticket);
               if(idx >= 0)
                  g_states[idx] = st;
               LogMsg(StringFormat("#%I64u kismi kar: lot=%.4f R=%.2f",ticket,part,r_multiple));
              }
            else
               LogMsg(StringFormat("#%I64u kismi kapatma basarisiz rc=%u",ticket,trade.ResultRetcode()));
           }
         else
           {
            st.partial_done = true;
            PersistState(st);
            int idx = FindState(ticket);
            if(idx >= 0)
               g_states[idx] = st;
           }
         if(!PositionSelectByTicket(ticket))
           {
            int idx = FindState(ticket);
            if(idx >= 0)
               RemoveStateAt(idx);
            continue;
           }
         volume = PositionGetDouble(POSITION_VOLUME);
         sl = PositionGetDouble(POSITION_SL);
        }

      // Breakeven / trailing.
      double new_sl = sl;
      if(InpBreakevenAtR > 0.0 && r_multiple >= InpBreakevenAtR)
        {
         double be = entry + (side > 0 ? 1.0 : -1.0) * st.init_risk * InpBreakevenOffsetR;
         if(side > 0 && (new_sl <= 0.0 || be > new_sl))
            new_sl = be;
         if(side < 0 && (new_sl <= 0.0 || be < new_sl))
            new_sl = be;
        }

      if(st.engine == ENGINE_TREND && InpTrendTrailAtr > 0.0 && g_atr > 0.0)
        {
         int max_bars = 4000;
         if(side > 0)
           {
            double highest = HighestHighSince(st.open_time,max_bars);
            if(highest > 0.0)
              {
               double trail = highest - InpTrendTrailAtr * g_atr;
               if(trail > new_sl)
                  new_sl = trail;
              }
           }
         else
           {
            double lowest = LowestLowSince(st.open_time,max_bars);
            if(lowest > 0.0)
              {
               double trail = lowest + InpTrendTrailAtr * g_atr;
               if(new_sl <= 0.0 || trail < new_sl)
                  new_sl = trail;
              }
           }
        }

      if(new_sl > 0.0)
        {
         bool has_sl = (sl > 0.0);
         double min_step = MathMax(TickSize(),InpTrailMinStepAtr * g_atr);
         bool better = (!has_sl);
         if(has_sl && side > 0 && new_sl > sl + min_step)
            better = true;
         if(has_sl && side < 0 && new_sl < sl - min_step)
            better = true;
         if(better && ModifyPositionSL(ticket,side,new_sl))
            LogMsg(StringFormat("#%I64u SL guncellendi -> %.*f (R=%.2f)",ticket,_Digits,new_sl,r_multiple));
        }

      // Time stop.
      int max_bars = (st.engine == ENGINE_RANGE ? InpRangeMaxBars : InpTrendMaxBars);
      if(max_bars > 0 && r_multiple < InpTimeStopMinR)
        {
         int bars_open = iBarShift(_Symbol,InpSignalTimeframe,st.open_time,false);
         if(bars_open >= max_bars)
           {
            if(trade.PositionClose(ticket,(ulong)InpDeviationPoints))
              {
               LogMsg(StringFormat("#%I64u zaman stopu: %d bar, R=%.2f",ticket,bars_open,r_multiple));
               int idx = FindState(ticket);
               if(idx >= 0)
                  RemoveStateAt(idx);
               continue;
              }
           }
        }

      // Regime flip exit for trend positions.
      if(st.engine == ENGINE_TREND && InpUseH4Regime && InpExitTrendOnRegimeFlip && g_h4_ok)
        {
         bool regime_against = (side > 0 ? !g_h4_bull : !g_h4_bear);
         if(regime_against)
           {
            if(trade.PositionClose(ticket,(ulong)InpDeviationPoints))
              {
               LogMsg(StringFormat("#%I64u H4 rejim cikisi (R=%.2f)",ticket,r_multiple));
               int idx = FindState(ticket);
               if(idx >= 0)
                  RemoveStateAt(idx);
               continue;
              }
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Dashboard                                                        |
//+------------------------------------------------------------------+
void UpdateDashboard()
  {
   if(!InpShowDashboard)
      return;
   if(MQLInfoInteger(MQL_TESTER))
      return;
   static datetime last_update = 0;
   datetime now = TimeCurrent();
   if(last_update > 0 && now - last_update < 2)
      return;
   last_update = now;

   string regime = "NOTR";
   if(g_h4_bull)
      regime = "BOGA";
   else if(g_h4_bear)
      regime = "AYI";

   string pos_text = "yok";
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      int side = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY ? 1 : -1);
      int engine = EngineFromMagic(PositionGetInteger(POSITION_MAGIC));
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double vol = PositionGetDouble(POSITION_VOLUME);
      double risk = 0.0;
      int idx = FindState(ticket);
      if(idx >= 0)
         risk = g_states[idx].init_risk;
      double price = (side > 0 ? SymbolInfoDouble(_Symbol,SYMBOL_BID) : SymbolInfoDouble(_Symbol,SYMBOL_ASK));
      double r = (risk > 0.0 ? (side > 0 ? (price - entry) / risk : (entry - price) / risk) : 0.0);
      pos_text = StringFormat("%s %s %.3f lot | R=%+.2f",EngineName(engine),SideName(side),vol,r);
      break;
     }

   double eq = Equity();
   double day_pct = (g_day_equity > 0.0 ? (eq / g_day_equity - 1.0) * 100.0 : 0.0);
   double dd_pct  = (g_peak_equity > 0.0 ? (1.0 - eq / g_peak_equity) * 100.0 : 0.0);
   string halt = "AKTIF";
   if(g_dd_halted)
      halt = "DD KILIDI";
   else if(g_daily_halted)
      halt = "GUNLUK KILIT";
   else if(LossStreakPauseActive())
      halt = "ZARAR MOLASI";

   string engines = "";
   if(InpEnableTrend)
      engines += "TREND";
   if(InpEnableRange)
      engines += (engines == "" ? "RANGE" : "+RANGE");
   if(engines == "")
      engines = "KAPALI";

   Comment("BTC Alpha Engine v1.00  |  ",_Symbol,"  |  ",
           EnumToString(InpSignalTimeframe)," / ",EnumToString(InpRegimeTimeframe),"\n",
           "Motor: ",engines,"   Rejim: ",regime," (egim ",DoubleToString(g_h4_slope_pct,2),"%)   Durum: ",halt,"\n",
           "ATR",IntegerToString(InpAtrPeriod),": ",DoubleToString(g_atr,_Digits),
           " (",DoubleToString(g_atr_pct,2),"% | yuzdelik ",DoubleToString(g_atr_pctile,0),")",
           "   ADX: ",DoubleToString(g_adx,1),
           "   VolOlcek: ",DoubleToString(g_vol_scale,2),"\n",
           "Spread: ",DoubleToString(CurrentSpread(),_Digits),
           " (med ",DoubleToString(g_spread_median,_Digits),")",
           "   Pozisyon: ",pos_text,"\n",
           "Gun: ",DoubleToString(day_pct,2),"% (limit -",DoubleToString(InpMaxDailyLossPct,1),"%)",
           "   Tepe DD: ",DoubleToString(dd_pct,2),"% (limit ",DoubleToString(InpMaxTotalDrawdownPct,1),"%)",
           "   Ardisik zarar: ",IntegerToString(g_consecutive_losses),"\n",
           "Son islem: ",g_last_action,
           (g_last_block != "" ? "\nSon blok: " + g_last_block : ""));
  }

//+------------------------------------------------------------------+
//| OnInit / OnTick / OnDeinit / OnTester                            |
//+------------------------------------------------------------------+
bool ValidateInputs()
  {
   if(InpMagicBase == 0 || InpMagicBase > 2000000000)
      return false;
   if(!InpEnableTrend && !InpEnableRange)
      return false;
   if(InpSignalTimeframe == PERIOD_CURRENT || InpRegimeTimeframe == PERIOD_CURRENT)
      return false;
   if(InpSignalTimeframe >= InpRegimeTimeframe)
      return false;
   if(InpDeviationPoints < 0 || InpMaxPositions < 1)
      return false;
   if(InpMaxLots < 0.0 || InpDonchianBars < 2 || InpFastEma < 2 || InpSlowEma < 3)
      return false;
   if(InpTrendSlAtr <= 0.0 || InpTrendTrailAtr < 0.0 || InpTrendTpR < 0.0 ||
      InpTrendMaxBars < 0 || InpTrendMinAdx < 0.0)
      return false;
   if(InpRangeBbPeriod < 5 || InpRangeBbDev <= 0.0 || InpRangeRsiPeriod < 2 ||
      InpRangeRsiBuy <= 0.0 || InpRangeRsiSell >= 100.0 ||
      InpRangeRsiBuy >= InpRangeRsiSell || InpRangeMaxAdx <= 0.0 ||
      InpRangeMaxH4SlopePct < 0.0 || InpRangeSlAtr <= 0.0 ||
      InpRangeTpR <= 0.0 || InpRangeRiskScale <= 0.0 || InpRangeMaxBars < 0)
      return false;
   if(InpH4EmaPeriod < 20 || InpH4SlopeBars < 1 || InpAtrPeriod < 2)
      return false;
   if(InpMinAtrPct < 0.0 || InpMaxAtrPct <= InpMinAtrPct)
      return false;
   if(InpAtrPctileLookback < 50 || InpAtrPctileMin < 0.0 ||
      InpAtrPctileMax > 100.0 || InpAtrPctileMin >= InpAtrPctileMax)
      return false;
   if(InpMaxSpreadPct < 0.0 || InpSpreadMedianMult < 1.0 ||
      InpSessionStartHour < 0 || InpSessionStartHour > 24 ||
      InpSessionEndHour < 0 || InpSessionEndHour > 24 ||
      InpDayRolloverHour < 0 || InpDayRolloverHour > 23)
      return false;
   if(InpRiskPerTradePct <= 0.0 || InpMaxRiskPerTradePct < InpRiskPerTradePct ||
      InpMaxRiskPerTradePct > 100.0 || InpMaxPortfolioRiskPct < InpMaxRiskPerTradePct)
      return false;
   if(InpVolTargetLookback < 50 || InpVolTargetMin <= 0.0 ||
      InpVolTargetMin > InpVolTargetMax)
      return false;
   if(InpMaxDailyLossPct < 0.0 || InpMaxDailyLossPct > 100.0 ||
      InpMaxTotalDrawdownPct < 0.0 || InpMaxTotalDrawdownPct > 100.0)
      return false;
   if(InpMaxConsecutiveLosses < 0 || InpLossStreakPauseHours < 0 ||
      InpMaxMarginUsagePct <= 0.0 || InpMaxMarginUsagePct > 100.0)
      return false;
   if(InpBreakevenAtR < 0.0 || InpBreakevenOffsetR < 0.0 ||
      InpTrendPartialAtR < 0.0 || InpRangePartialAtR < 0.0 ||
      InpPartialClosePct < 0.0 || InpPartialClosePct >= 100.0 ||
      InpTrailMinStepAtr < 0.0 || InpTimeStopMinR < 0.0)
      return false;
   if(InpOptimizationMinTrades < 0)
      return false;
   return true;
  }

int OnInit()
  {
   if(!ValidateInputs())
     {
      Print("Hatali girdiler: lutfen pozitif degerleri, TF sirasini ve risk limitlerini kontrol edin.");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpSignalTimeframe >= InpRegimeTimeframe)
     {
      Print("Sinyal TF, rejim TF'den kucuk olmali (or: H1 sinyal / H4 rejim).");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpEnableRange && !InpUseH4Regime)
      Print("Uyari: Range motoru H4 rejim filtresi kapaliyken trendli piyasada calisabilir.");

   g_trend_magic = (int)InpMagicBase;
   g_range_magic = (int)(InpMagicBase + 1);
   g_is_netting  = (AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_NETTING);
   if(g_is_netting)
      Print("Netting hesap: tek pozisyon, kismi kapatma devre disi (hedging onerilir).");
   if(g_is_netting && InpEnableRange)
     {
      Print("Netting hesapta iki motor (trend+range) desteklenmez: InpEnableRange=false yapin.");
      return INIT_PARAMETERS_INCORRECT;
     }
   g_allow_partial = !g_is_netting; // CTrade::PositionClosePartial is hedging-only

   long trade_mode = (long)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_MODE);
   if(trade_mode != SYMBOL_TRADE_MODE_FULL)
     {
      Print("Sembolde tam islem izni yok (SYMBOL_TRADE_MODE).");
      return INIT_FAILED;
     }
   if(SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP) <= 0.0 ||
      SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE) <= 0.0)
     {
      Print("Sembol hacim/tick bilgisi gecersiz.");
      return INIT_FAILED;
     }

   int min_signal_bars = (int)MathMax((double)(InpSlowEma + 5),(double)(int)MathMax((double)(InpDonchianBars + 10),120.0));
   if(Bars(_Symbol,InpSignalTimeframe) < min_signal_bars)
     {
      PrintFormat("Yetersiz %s gecmisi: %d bar var, en az %d gerekli.",
                  EnumToString(InpSignalTimeframe),Bars(_Symbol,InpSignalTimeframe),min_signal_bars);
      return INIT_FAILED;
     }
   int min_regime_bars = InpH4EmaPeriod + InpH4SlopeBars + 5;
   if(InpUseH4Regime && Bars(_Symbol,InpRegimeTimeframe) < min_regime_bars)
     {
      PrintFormat("Yetersiz %s gecmisi: %d bar var, en az %d gerekli.",
                  EnumToString(InpRegimeTimeframe),Bars(_Symbol,InpRegimeTimeframe),min_regime_bars);
      return INIT_FAILED;
     }

   h_atr      = iATR(_Symbol,InpSignalTimeframe,InpAtrPeriod);
   h_ema_fast = iMA(_Symbol,InpSignalTimeframe,InpFastEma,0,MODE_EMA,PRICE_CLOSE);
   h_ema_slow = iMA(_Symbol,InpSignalTimeframe,InpSlowEma,0,MODE_EMA,PRICE_CLOSE);
   h_h4_ema   = iMA(_Symbol,InpRegimeTimeframe,InpH4EmaPeriod,0,MODE_EMA,PRICE_CLOSE);
   h_adx      = iADX(_Symbol,InpSignalTimeframe,InpAtrPeriod);
   h_rsi      = iRSI(_Symbol,InpSignalTimeframe,InpRangeRsiPeriod,PRICE_CLOSE);
   h_bb       = iBands(_Symbol,InpSignalTimeframe,InpRangeBbPeriod,0,InpRangeBbDev,PRICE_CLOSE);

   if(h_atr == INVALID_HANDLE || h_ema_fast == INVALID_HANDLE ||
      h_ema_slow == INVALID_HANDLE || h_h4_ema == INVALID_HANDLE ||
      h_adx == INVALID_HANDLE || h_rsi == INVALID_HANDLE || h_bb == INVALID_HANDLE)
     {
      Print("Indikator handle olusturulamadi.");
      return INIT_FAILED;
     }

   trade.SetExpertMagicNumber(MagicForEngine(ENGINE_TREND));
   trade.SetDeviationInPoints((ulong)InpDeviationPoints);
   trade.SetAsyncMode(false);
   trade.SetTypeFillingBySymbol(_Symbol);

   LoadRiskState();
   g_day_start = ComputeDayStart(TimeCurrent());
   if(g_day_equity <= 0.0)
      g_day_equity = Equity();
   if(g_peak_equity <= 0.0)
      g_peak_equity = Equity();
   g_peak_equity = MathMax(g_peak_equity,Equity());
   SaveRiskState();

   UpdateMarketState();
   UpdateSpreadMedian();
   UpdateRiskStats();
   g_last_riskstats = TimeCurrent();
   g_last_bar_time  = iTime(_Symbol,InpSignalTimeframe,0);
   g_bar_evaluated  = true; // do not enter on a stale signal at startup

   PrintFormat("BTC Alpha Engine v1.00 basladi | %s | sinyal=%s rejim=%s | hesap modu=%s netting=%s",
               _Symbol,EnumToString(InpSignalTimeframe),EnumToString(InpRegimeTimeframe),
               (g_is_netting ? "netting" : "hedging"),
               (g_is_netting ? "evet" : "hayir"));
   PrintFormat("Risk: islem %.2f%% (tavan %.2f%%), portfoy %.2f%%, gunluk limit %.2f%%, toplam DD %.2f%%",
               InpRiskPerTradePct,InpMaxRiskPerTradePct,InpMaxPortfolioRiskPct,
               InpMaxDailyLossPct,InpMaxTotalDrawdownPct);
   PrintFormat("Motorlar: trend=%s range=%s | Donchian=%d EMA=%d/%d ATR=%d | SL=%.1f ATR trail=%.1f ATR",
               (InpEnableTrend ? "acik" : "kapali"),(InpEnableRange ? "acik" : "kapali"),
               InpDonchianBars,InpFastEma,InpSlowEma,InpAtrPeriod,
               InpTrendSlAtr,InpTrendTrailAtr);
   if(g_dd_halted)
      Print("DIKKAT: Onceki oturumdan toplam DD kilidi aktif. InpResetRiskLocksOnInit=true ile sifirlayin.");
   if(g_pause_until > 0)
      PrintFormat("Ardisik zarar molasi: %s",TimeToString(g_pause_until,TIME_DATE|TIME_MINUTES));
   UpdateDashboard();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   SaveRiskState();
   Comment("");
   if(h_atr != INVALID_HANDLE)
      IndicatorRelease(h_atr);
   if(h_ema_fast != INVALID_HANDLE)
      IndicatorRelease(h_ema_fast);
   if(h_ema_slow != INVALID_HANDLE)
      IndicatorRelease(h_ema_slow);
   if(h_h4_ema != INVALID_HANDLE)
      IndicatorRelease(h_h4_ema);
   if(h_adx != INVALID_HANDLE)
      IndicatorRelease(h_adx);
   if(h_rsi != INVALID_HANDLE)
      IndicatorRelease(h_rsi);
   if(h_bb != INVALID_HANDLE)
      IndicatorRelease(h_bb);
  }

void OnTick()
  {
   if(IsStopped())
      return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick) || tick.bid <= 0.0 || tick.ask <= 0.0)
      return;

   SampleSpread(MathMax(0.0,tick.ask - tick.bid));
   RefreshDailyAnchor();
   UpdateEquityGuards();

   datetime bar_time = iTime(_Symbol,InpSignalTimeframe,0);
   bool new_bar = (bar_time > 0 && bar_time != g_last_bar_time);
   if(new_bar)
     {
      g_last_bar_time  = bar_time;
      g_bar_evaluated  = false;
      UpdateMarketState();
      UpdateSpreadMedian();
      if(g_last_riskstats == 0 || TimeCurrent() - g_last_riskstats >= 60)
        {
         UpdateRiskStats();
         g_last_riskstats = TimeCurrent();
        }
      PruneStates();
      RefreshDailyAnchor();
      UpdateEquityGuards();
     }

   if(g_last_manage_time == 0 || TimeCurrent() - g_last_manage_time >= 2)
     {
      ManageOpenPositions(tick);
      g_last_manage_time = TimeCurrent();
     }

   if(!g_bar_evaluated && !g_liquidate_all)
     {
      // Retry for a few ticks if indicator buffers were not ready on the first
      // tick of the new bar; this avoids silently missing a valid H1 signal.
      if(!g_data_ok && (g_last_state_retry == 0 || TimeCurrent() - g_last_state_retry >= 2))
        {
         UpdateMarketState();
         g_last_state_retry = TimeCurrent();
        }
      if(g_data_ok)
        {
         EvaluateEntries();
         g_bar_evaluated = true;
        }
     }

   if(new_bar && (!MQLInfoInteger(MQL_TESTER) || TimeCurrent() - g_last_risk_save > 300))
      SaveRiskState();

   UpdateDashboard();
  }

double OnTester()
  {
   double profit  = TesterStatistics(STAT_PROFIT);
   double dd      = TesterStatistics(STAT_EQUITY_DD);
   double initial = TesterStatistics(STAT_INITIAL_DEPOSIT);
   double trades  = TesterStatistics(STAT_TRADES);
   if(InpOptimizationMinTrades > 0 && trades < InpOptimizationMinTrades)
      return -1000000.0 + trades;
   if(!InpUseRiskAdjustedScore)
      return profit;
   double floor_dd = MathMax(initial * 0.01,0.01);
   double recovery = profit / MathMax(dd,floor_dd);
   double confidence = MathMin(1.0,MathSqrt(trades / MathMax(1.0,(double)InpOptimizationMinTrades * 2.0)));
   double score = recovery * confidence;
   PrintFormat("Tester skoru=%.4f net=%.2f DD=%.2f trades=%.0f PF=%.2f",
               score,profit,dd,trades,TesterStatistics(STAT_PROFIT_FACTOR));
   return score;
  }
//+------------------------------------------------------------------+

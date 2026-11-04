#property strict
#property version   "1.08"
#property description "M1 volatility-sized fixed-price grid with closed-candle Heiken Ashi direction"
#property description "Position-limit rotation: at the layer cap the oldest same-side position is replaced by the fresh level"
#property description "Equity target can also re-base to every new equity low and close on the rebound"
#property description "Bounded strategy-only live optimization on the last closed hour; lot/position caps remain manual"

#include <Trade/Trade.mqh>

CTrade trade;

enum ENUM_SIGNAL_CANDLE_MODE
  {
   SIGNAL_HEIKEN_ASHI = 0,
   SIGNAL_STANDARD_CANDLE = 1
  };

input group "Sinyal ve işlem yönü (M1 kapanmış mum)"
input ENUM_TIMEFRAMES       InpSignalTimeframe          = PERIOD_M1;
input ENUM_SIGNAL_CANDLE_MODE InpSignalCandleMode       = SIGNAL_HEIKEN_ASHI;
input int                   InpSignalHistoryBars        = 300;
input bool                  InpCloseOppositeOnColorChange      = false;  // true: renk değişince yeni işlem yönüne ters açık pozisyonları kapat
input bool                  InpReverseTradeDirection    = false;  // true: yeşil sinyalde SHORT, kırmızı sinyalde LONG aç; otomatik modun başlangıç/yedek seçimi

input group "Otomatik işlem yönü (her dakika son 1 saat)"
input bool                  InpAutoReverseTradeDirection = false; // true: son 60 dk tick testinde daha kârlı olan normal/ters yönü seç
input double                InpAutoDirectionCommissionPerLot = 0.0; // Her iki sanal testte 1 lot toplam komisyonu (hesap para birimi); 0 = hariç

input group "Otomatik strateji optimizasyonu (lot ve adet sabit)"
input bool                  InpAutoOptimizeSettings      = false; // Açıkken yön otomasyonuna göre önceliklidir
input int                   InpAutoOptimizeEveryMinutes  = 5;     // Sunucu zamanına hizalı test aralığı (1..1440 dk)
input int                   InpAutoOptimizeMaxCandidates = 128;   // Sınırlı aramada en fazla aday (64..512); tam tarama değildir
input int                   InpAutoOptimizeMinClosedTrades = 5;   // Aday için en az kapanmış sanal işlem
input double                InpAutoOptimizeMaxDrawdownPct = 5.0;  // Test özsermaye düşüşü üst sınırı; 0 = ek sınır yok
input double                InpAutoOptimizeDrawdownFloorPct = 0.01; // Puanda DD tabanı = en az sermayenin bu yüzdesi
input double                InpAutoOptimizeMinImprovementPct = 5.0; // Mevcut ayarın puanına göre gereken iyileşme
input int                   InpAutoOptimizeSliceMs        = 25;    // Her zamanlayıcı olayında CPU bütçesi (5..200 ms)
input int                   InpAutoOptimizeMaxSeconds     = 120;   // Tamamlanmayan tarama iptal edilir; kısmi kazanan uygulanmaz
input bool                  InpOptSearchBooleans         = true;  // Mum modu, yön ve tüm strateji bool seçenekleri

input group "Optimizasyon aday değerleri (virgülle ayrılmış; manuel değer de dahil)"
input string                InpOptSignalTimeframes       = "M1,M5,M15";
input string                InpOptSignalHistoryBars      = "50,150,300";
input string                InpOptGridLookbackBars       = "10,20,40";
input string                InpOptGridMultipliers        = "0.25,0.50,0.75,1.00";
input string                InpOptMinSpreadMultiples     = "1,2,3";
input string                InpOptInitialGridLevels      = "15,30,60";
input string                InpOptMaxGridLevels          = "100,500,1000";
input string                InpOptTPGrids                = "1,2,3,5";
input string                InpOptSLGrids                = "3,5,10,15";
input string                InpOptMaxSpreadPoints        = "0";
input string                InpOptMaxSpreadFractions     = "0.25,0.50,0.75";
input string                InpOptEquityTargets          = "0,1,2,5"; // Hesap para birimi; lot/pozisyon sınırları aranmaz

input group "Otomatik grid aralığı"
input int                   InpGridRangeLookbackBars    = 20;     // Son kapanmış M1 mumları
input double                InpGridStepMultiplier       = 0.50;   // Medyan (High-Low) x çarpan
input double                InpMinSpreadMultiple        = 2.00;   // Adım en az spread x bu değer
input int                   InpInitialGridLevels        = 30;     // Başlangıçta her yönde
input int                   InpMaxGridLevels            = 1000;   // Her yönde üst sınır
input bool                  InpResetGridOnInit          = false;  // true: bu başlatılışta yeni B/S hesapla
input bool                  InpDrawGridLevels           = true;
input bool                  InpEnterOnAnyCross          = true;   // false: LONG yalnız yukarı, SHORT yalnız aşağı geçişte

input group "Çıkışlar (her katman için)"
input int                   InpTakeProfitGrids          = 3;
input int                   InpStopLossGrids            = 10;

input group "Pozisyon ve lot sınırları"
input bool                  InpUseBrokerMinimumVolume   = false;  // true ise otomatik broker minimum hacmi
input double                InpFixedLots                = 0.01;   // Varsayılan; minimum lotun altındaysa işlem atlanır
input int                   InpMaxLayersPerSide         = 5;      // 0 = sınırsız
input int                   InpMaxTotalPositions        = 10;     // Bu sembol + Magic; 0 = sınırsız
input bool                  InpRotateOldestAtLimit      = true;   // true: sınır dolunca en eski aynı yönlü pozisyonu kapat, yeni seviyeden taze giriş aç
input bool                  InpOnePositionPerGridLine   = true;
input int                   InpMaxSpreadPoints          = 0;      // 0 = point bazlı ek filtre kapalı
input double                InpMaxSpreadGridFraction    = 0.50;   // Spread > grid adımının bu oranıysa yeni giriş yok

input group "İşlem"
input ulong                 InpMagicNumber              = 20261008;
input int                   InpDeviationPoints           = 20;
input bool                  InpShowChartStatus           = true;

input group "Özsermaye kâr hedefi"
input double                InpCloseAllAtEquityGain       = 0.0;   // 0 = kapalı; pozitif tutar hesap para biriminde
input bool                  InpEquityTargetRebaseOnLow    = false; // true: her yeni özsermaye dibinde hedef tabanı dibe çekilir; dipten +hedef gelince tüm pozisyonlar kapanır

input group "Strateji Sınayıcı optimizasyonu"
input bool                  InpUseRiskAdjustedTesterScore = true; // true: Custom max için kâr / özsermaye düşüşü
input int                   InpOptimizationMinTrades      = 30;   // Risk ayarlı puanda minimum işlem; 0 = filtre yok

// Grid coordinates and spacing stay fixed for this grid generation.
double g_grid_base = 0.0;
double g_grid_step = 0.0;
int    g_up_count = 0;
int    g_down_count = 0;
int    g_up_state[];       // -1 = current price below line; +1 = above; 0 = not armed
int    g_down_state[];

int      g_signal_side = 0; // +1 LONG, -1 SHORT, 0 no valid closed-bar signal
bool     g_active_reverse_trade_direction = false;
datetime g_auto_direction_window_end = 0;
datetime g_auto_direction_attempt_minute = 0;
datetime g_auto_direction_retry_after = 0;
double   g_auto_direction_normal_profit = 0.0;
double   g_auto_direction_reverse_profit = 0.0;
int      g_auto_direction_normal_entries = 0;
int      g_auto_direction_reverse_entries = 0;
string   g_auto_direction_status = "İlk test bekleniyor";
double   g_profit_target_start_equity = 0.0;
bool     g_profit_target_liquidating = false;
datetime g_last_signal_bar_time = 0;
datetime g_last_state_flush = 0;
datetime g_last_low_rebase_log = 0;
string   g_last_action = "Başlatılıyor";
string   g_grid_object_prefix = "";

// Strategy-only configuration: lot, position caps, Magic and execution/UI inputs
// deliberately do NOT belong here. The optimizer can never increase those limits.
struct StrategySettings
  {
   ENUM_TIMEFRAMES signal_timeframe;
   ENUM_SIGNAL_CANDLE_MODE candle_mode;
   int    signal_history;
   bool   close_opposite;
   bool   reverse;
   int    grid_lookback;
   double grid_multiplier;
   double min_spread_multiple;
   int    initial_levels;
   int    max_levels;
   bool   enter_any_cross;
   int    tp_grids;
   int    sl_grids;
   bool   rotate_oldest;
   bool   one_per_line;
   int    max_spread_points;
   double max_spread_fraction;
   double equity_target;
   bool   rebase_on_low;
   double grid_base;
   double grid_step;
  };

struct SavedGridPosition
  {
   ulong identifier;
   int line_code;
   double step;
   int tp;
   int sl;
   long generation;
  };
SavedGridPosition g_saved_grid_positions[];

StrategySettings g_optimized_settings;
bool   g_optimizer_settings_active = false;
long   g_grid_generation = 0;
double g_cycle_equity_target = 0.0;
bool   g_cycle_rebase_on_low = false;
bool   g_cycle_settings_initialized = false;

StrategySettings ManualStrategySettings()
  {
   StrategySettings p;
   p.signal_timeframe = (InpSignalTimeframe == PERIOD_CURRENT ? (ENUM_TIMEFRAMES)_Period : InpSignalTimeframe);
   p.candle_mode = InpSignalCandleMode;
   p.signal_history = (int)MathMax(50,MathMin(1500,InpSignalHistoryBars));
   p.close_opposite = InpCloseOppositeOnColorChange;
   p.reverse = InpReverseTradeDirection;
   p.grid_lookback = InpGridRangeLookbackBars;
   p.grid_multiplier = InpGridStepMultiplier;
   p.min_spread_multiple = InpMinSpreadMultiple;
   p.initial_levels = InpInitialGridLevels;
   p.max_levels = InpMaxGridLevels;
   p.enter_any_cross = InpEnterOnAnyCross;
   p.tp_grids = InpTakeProfitGrids;
   p.sl_grids = InpStopLossGrids;
   p.rotate_oldest = InpRotateOldestAtLimit;
   p.one_per_line = InpOnePositionPerGridLine;
   p.max_spread_points = InpMaxSpreadPoints;
   p.max_spread_fraction = InpMaxSpreadGridFraction;
   p.equity_target = InpCloseAllAtEquityGain;
   p.rebase_on_low = InpEquityTargetRebaseOnLow;
   p.grid_base = g_grid_base;
   p.grid_step = g_grid_step;
   return p;
  }

StrategySettings LiveStrategySettings()
  {
   if(InpAutoOptimizeSettings && g_optimizer_settings_active)
      return g_optimized_settings;
   return ManualStrategySettings();
  }

int ClampedSignalHistory(const int history)
  {
   return (int)MathMax(50,MathMin(1500,history));
  }

bool SameNumber(const double a,const double b)
  {
   return MathAbs(a - b) <= 1.0e-10 * MathMax(1.0,MathMax(MathAbs(a),MathAbs(b)));
  }

bool SameStrategySettings(const StrategySettings &a,const StrategySettings &b)
  {
   return (a.signal_timeframe == b.signal_timeframe && a.candle_mode == b.candle_mode &&
           a.signal_history == b.signal_history && a.close_opposite == b.close_opposite &&
           a.reverse == b.reverse && a.grid_lookback == b.grid_lookback &&
           SameNumber(a.grid_multiplier,b.grid_multiplier) && SameNumber(a.min_spread_multiple,b.min_spread_multiple) &&
           a.initial_levels == b.initial_levels && a.max_levels == b.max_levels &&
           a.enter_any_cross == b.enter_any_cross && a.tp_grids == b.tp_grids && a.sl_grids == b.sl_grids &&
           a.rotate_oldest == b.rotate_oldest && a.one_per_line == b.one_per_line &&
           a.max_spread_points == b.max_spread_points && SameNumber(a.max_spread_fraction,b.max_spread_fraction) &&
           SameNumber(a.equity_target,b.equity_target) && a.rebase_on_low == b.rebase_on_low &&
           SameNumber(a.grid_base,b.grid_base) && SameNumber(a.grid_step,b.grid_step));
  }

bool ValidStrategySettings(const StrategySettings &p)
  {
   return (PeriodSeconds(p.signal_timeframe) > 0 &&
           (p.candle_mode == SIGNAL_HEIKEN_ASHI || p.candle_mode == SIGNAL_STANDARD_CANDLE) &&
           p.signal_history >= 50 && p.signal_history <= 1500 && p.grid_lookback >= 5 && p.grid_lookback <= 10000 &&
           MathIsValidNumber(p.grid_multiplier) && p.grid_multiplier > 0.0 &&
           MathIsValidNumber(p.min_spread_multiple) && p.min_spread_multiple >= 0.0 &&
           p.initial_levels >= 1 && p.max_levels >= p.initial_levels && p.max_levels <= 100000 &&
           p.tp_grids >= 1 && p.sl_grids >= 1 && p.max_spread_points >= 0 &&
           MathIsValidNumber(p.max_spread_fraction) && p.max_spread_fraction >= 0.0 &&
           MathIsValidNumber(p.equity_target) && p.equity_target >= 0.0 &&
           MathIsValidNumber(p.grid_base) && p.grid_base > 0.0 &&
           MathIsValidNumber(p.grid_step) && p.grid_step > 0.0);
  }

//+------------------------------------------------------------------+
//| Basic market and numeric helpers                                 |
//+------------------------------------------------------------------+
string SideName(const int side)
  {
   if(side > 0)
      return "LONG";
   if(side < 0)
      return "SHORT";
   return "BEKLENİYOR";
  }

bool EffectiveReverseTradeDirection()
  {
   StrategySettings p = LiveStrategySettings();
   if(InpAutoOptimizeSettings)
      return p.reverse;
   return (InpAutoReverseTradeDirection ? g_active_reverse_trade_direction : p.reverse);
  }

int TradeSideForSignal(const int signal_side)
  {
   if(signal_side == 0)
      return 0;
   return (EffectiveReverseTradeDirection() ? -signal_side : signal_side);
  }

int SideFromPositionType(const long type)
  {
   if(type == POSITION_TYPE_BUY)
      return 1;
   if(type == POSITION_TYPE_SELL)
      return -1;
   return 0;
  }

double TickSize()
  {
   double size = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(size <= 0.0)
      size = _Point;
   return size;
  }

double PipSize()
  {
   if(_Digits == 3 || _Digits == 5)
      return _Point * 10.0;
   return _Point;
  }

double CrossTolerance()
  {
   return MathMax(TickSize() * 0.05,_Point * 0.01);
  }

double MidPrice(const MqlTick &tick)
  {
   if(tick.last > 0.0)
      return tick.last;
   if(tick.bid > 0.0 && tick.ask > 0.0)
      return (tick.bid + tick.ask) * 0.5;
   if(tick.bid > 0.0)
      return tick.bid;
   return tick.ask;
  }

bool UsableReplayTick(const MqlTick &tick)
  {
   return (MathIsValidNumber(tick.bid) && MathIsValidNumber(tick.ask) &&
           MathIsValidNumber(tick.last) && tick.bid > 0.0 && tick.ask >= tick.bid);
  }

double NormalizePriceToTick(const double price,const int round_direction)
  {
   // round_direction: +1 ceil, -1 floor, 0 nearest
   double tick = TickSize();
   if(price <= 0.0 || tick <= 0.0)
      return NormalizeDouble(price,_Digits);
   double units = price / tick;
   if(round_direction > 0)
      units = MathCeil(units - 1.0e-10);
   else if(round_direction < 0)
      units = MathFloor(units + 1.0e-10);
   else
      units = MathRound(units);
   return NormalizeDouble(units * tick,_Digits);
  }

int ComparePriceToLevel(const double price,const double level,const double cached_tolerance=-1.0)
  {
   double eps = (cached_tolerance >= 0.0 ? cached_tolerance : CrossTolerance());
   if(price > level + eps)
      return 1;
   if(price < level - eps)
      return -1;
   return 0;
  }

string RunModeTag()
  {
   return (MQLInfoInteger(MQL_TESTER) ? "T" : "L");
  }

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

uint HashSymbol(const string symbol)
  {
   return HashText(symbol);
  }

string InstanceStatePrefix()
  {
   string seed = StringFormat("%I64d_%I64u_%s_%s",
                              AccountInfoInteger(ACCOUNT_LOGIN),InpMagicNumber,_Symbol,RunModeTag());
   // Short key keeps position-state global variables under MT5's 63-character limit.
   return "M1G_" + StringFormat("%I64u",(ulong)HashText(seed));
  }

string GridStateKey(const string field)
  {
   return InstanceStatePrefix() + "_" + field;
  }

int CountOurPositions(const int side_filter=0);

double CycleEquityTarget()
  {
   if(g_cycle_settings_initialized)
      return g_cycle_equity_target;
   StrategySettings settings = LiveStrategySettings();
   return settings.equity_target;
  }

bool CycleRebaseOnLow()
  {
   if(g_cycle_settings_initialized)
      return g_cycle_rebase_on_low;
   StrategySettings settings = LiveStrategySettings();
   return settings.rebase_on_low;
  }

void SaveProfitTargetState()
  {
   if(MQLInfoInteger(MQL_TESTER))
      return; // Each tester pass starts from its own initial deposit/equity.
   GlobalVariableSet(GridStateKey("PTBASE"),g_profit_target_start_equity);
   GlobalVariableSet(GridStateKey("PTAMT"),CycleEquityTarget());
   GlobalVariableSet(GridStateKey("PTLIQ"),(g_profit_target_liquidating ? 1.0 : 0.0));
   GlobalVariableSet(GridStateKey("PTLOW"),(CycleRebaseOnLow() ? 1.0 : 0.0));
   GlobalVariablesFlush();
  }

void LoadProfitTargetState()
  {
   StrategySettings settings = LiveStrategySettings();
   g_cycle_equity_target = settings.equity_target;
   g_cycle_rebase_on_low = settings.rebase_on_low;
   g_cycle_settings_initialized = true;
   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(current_equity <= 0.0)
      current_equity = AccountInfoDouble(ACCOUNT_BALANCE);

   if(MQLInfoInteger(MQL_TESTER))
     {
      g_profit_target_start_equity = current_equity;
      g_profit_target_liquidating = false;
      return;
     }

   string base_key = GridStateKey("PTBASE");
   string amount_key = GridStateKey("PTAMT");
   string liquidating_key = GridStateKey("PTLIQ");
   string low_key = GridStateKey("PTLOW");
   bool state_exists = (GlobalVariableCheck(base_key) &&
                        GlobalVariableCheck(amount_key) &&
                        GlobalVariableCheck(liquidating_key) &&
                        GlobalVariableCheck(low_key));
   if(state_exists)
     {
      double saved_amount = GlobalVariableGet(amount_key);
      bool saved_low_mode = (GlobalVariableGet(low_key) > 0.5);
      double amount_tolerance = MathMax(1.0e-8,MathAbs(CycleEquityTarget()) * 1.0e-8);
      if(GlobalVariableGet(base_key) > 0.0 &&
         MathIsValidNumber(saved_amount) && saved_amount >= 0.0 &&
         ((MathAbs(saved_amount - CycleEquityTarget()) <= amount_tolerance && saved_low_mode == CycleRebaseOnLow()) ||
          CountOurPositions() > 0 || GlobalVariableGet(liquidating_key) > 0.5))
        {
         g_cycle_equity_target = saved_amount;
         g_cycle_rebase_on_low = saved_low_mode;
         g_profit_target_start_equity = GlobalVariableGet(base_key);
         g_profit_target_liquidating = (GlobalVariableGet(liquidating_key) > 0.5);
         return;
        }
     }

   // First run or changed target amount: start a fresh equity cycle.
   g_profit_target_start_equity = current_equity;
   g_profit_target_liquidating = false;
   SaveProfitTargetState();
  }

string PositionStateKey(const ulong position_id,const string field)
  {
   return InstanceStatePrefix() + "_" + StringFormat("%I64u",position_id) + "_" + field;
  }

string GridObjectName(const bool is_up,const int index)
  {
   return g_grid_object_prefix + (is_up ? "U_" : "D_") + IntegerToString(index);
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

//+------------------------------------------------------------------+
//| Automatic one-time M1 volatility sizing                          |
//+------------------------------------------------------------------+
// as_of is exclusive: size the historical grid only with completed M1 bars
// BEFORE the test window, not candles learned later during the tested hour.
bool GridMedianBefore(const MqlRates &rates[],const datetime as_of,const int lookback,double &median)
  {
   median = 0.0;
   int last = ArraySize(rates) - 1;
   while(last >= 0 && rates[last].time >= as_of) last--;
   if(lookback < 1 || last + 1 < lookback) return false;
   double ranges[];
   if(ArrayResize(ranges,lookback) < lookback) return false;
   for(int i=0; i<lookback; i++)
     {
      double range = rates[last - i].high - rates[last - i].low;
      if(!MathIsValidNumber(range) || range < 0.0) return false;
      ranges[i] = range;
     }
   if(!ArraySort(ranges)) return false;
   median = ((lookback % 2) == 1 ? ranges[lookback / 2]
             : (ranges[lookback / 2 - 1] + ranges[lookback / 2]) * 0.5);
   return true;
  }

bool GridStepFromMedian(const StrategySettings &settings,const double median_range,const double spread,
                        double &step_out,double &floor_out)
  {
   double tick_size = TickSize();
   double min_step = tick_size;
   if(spread > 0.0 && settings.min_spread_multiple > 0.0)
      min_step = MathMax(min_step,spread * settings.min_spread_multiple);
   long stop_level = SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freeze_level = SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   long broker_points = (stop_level > freeze_level ? stop_level : freeze_level);
   if(settings.tp_grids > 0 && broker_points > 0)
      min_step = MathMax(min_step,((double)broker_points * _Point + tick_size) / settings.tp_grids);
   if(settings.sl_grids > 0 && broker_points > 0)
      min_step = MathMax(min_step,((double)broker_points * _Point + tick_size + spread) / settings.sl_grids);
   step_out = MathMax(median_range * settings.grid_multiplier,min_step);
   step_out = NormalizeDouble(MathCeil(step_out / tick_size - 1.0e-10) * tick_size,_Digits);
   floor_out = min_step;
   return (step_out > 0.0 && MathIsValidNumber(step_out));
  }

bool GridStepForSettings(const StrategySettings &settings,const MqlRates &rates[],const datetime as_of,
                         const double spread,double &step_out,double &median_range_out,double &floor_out)
  {
   step_out = 0.0;
   floor_out = 0.0;
   if(!GridMedianBefore(rates,as_of,settings.grid_lookback,median_range_out)) return false;
   return GridStepFromMedian(settings,median_range_out,spread,step_out,floor_out);
  }

bool CalculateInitialGridStep(double &step_out,double &median_range_out,double &floor_out)
  {
   StrategySettings settings = LiveStrategySettings();
   MqlRates rates[];
   ArraySetAsSeries(rates,false);
   int copied = CopyRates(_Symbol,PERIOD_M1,0,settings.grid_lookback + 1,rates);
   if(copied < settings.grid_lookback + 1)
      return false;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return false;
   return GridStepForSettings(settings,rates,rates[copied - 1].time,MathMax(0.0,tick.ask - tick.bid),
                              step_out,median_range_out,floor_out);
  }

bool LoadOrCreateGrid(const double current_price)
  {
   string base_key = GridStateKey("BASE");
   string step_key = GridStateKey("STEP");
   bool auto_grid = (GlobalVariableCheck(GridStateKey("AUTOGRID")) && GlobalVariableGet(GridStateKey("AUTOGRID")) > 0.5);
   bool can_load = (!InpResetGridOnInit && !MQLInfoInteger(MQL_TESTER) && !auto_grid &&
                    GlobalVariableCheck(base_key) && GlobalVariableCheck(step_key));

   if(can_load)
     {
      g_grid_base = GlobalVariableGet(base_key);
      g_grid_step = GlobalVariableGet(step_key);
      if(g_grid_base > 0.0 && g_grid_step > 0.0)
        {
         g_grid_generation = (GlobalVariableCheck(GridStateKey("GEN")) ? (long)GlobalVariableGet(GridStateKey("GEN")) : 0);
         g_last_action = "Önceki grid geri yüklendi";
         PrintFormat("Saved grid restored: base=%.*f step=%.*f",_Digits,g_grid_base,_Digits,g_grid_step);
         return true;
        }
     }

   double median_range = 0.0;
   double min_step = 0.0;
   double calculated_step = 0.0;
   if(!CalculateInitialGridStep(calculated_step,median_range,min_step))
     {
      PrintFormat("Grid adımı hesaplanamadı: son %d kapanmış M1 mumunun terminalde yüklü olduğundan emin olun.",
                  InpGridRangeLookbackBars);
      return false;
     }
   if(calculated_step * InpStopLossGrids >= current_price * 0.90)
     {
      Print("Grid adımı mevcut fiyata göre aşırı büyük; güvenlik nedeniyle EA başlatılmadı.");
      return false;
     }

   g_grid_base = NormalizePriceToTick(current_price,0);
   g_grid_step = calculated_step;
   g_grid_generation = (GlobalVariableCheck(GridStateKey("GEN")) ? (long)GlobalVariableGet(GridStateKey("GEN")) + 1 : 0);
   GlobalVariableSet(GridStateKey("GEN"),(double)g_grid_generation);
   GlobalVariableSet(GridStateKey("AUTOGRID"),0.0);
   GlobalVariableSet(base_key,g_grid_base);
   GlobalVariableSet(step_key,g_grid_step);
   GlobalVariablesFlush();

   PrintFormat("Yeni grid oluşturuldu: base=%.*f medyan M1 aralığı=%.*f çarpan=%.2f alt sınır=%.*f adım=%.*f (%.1f point)",
               _Digits,g_grid_base,_Digits,median_range,InpGridStepMultiplier,
               _Digits,min_step,_Digits,g_grid_step,g_grid_step / _Point);
   g_last_action = "Başlangıç grid'i hesaplandı";
   return true;
  }

//+------------------------------------------------------------------+
//| Optional visible grid levels                                      |
//+------------------------------------------------------------------+
color CurrentGridColor()
  {
   if(g_signal_side > 0)
      return clrLimeGreen;
   if(g_signal_side < 0)
      return clrTomato;
   return clrDarkGray;
  }

void SetHorizontalLine(const string name,const double price,const color line_color,
                       const ENUM_LINE_STYLE style,const int width)
  {
   if(ObjectFind(0,name) < 0)
     {
      if(!ObjectCreate(0,name,OBJ_HLINE,0,0,price))
         return;
     }
   ObjectSetDouble(0,name,OBJPROP_PRICE,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,line_color);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
  }

void DrawGridLine(const bool is_up,const int index)
  {
   if(!InpDrawGridLevels || index < 1)
      return;
   double price = (is_up ? g_grid_base + g_grid_step * index : g_grid_base - g_grid_step * index);
   if(price <= 0.0)
      return;
   SetHorizontalLine(GridObjectName(is_up,index),price,CurrentGridColor(),STYLE_DOT,1);
  }

void DrawBaseLine()
  {
   if(!InpDrawGridLevels || g_grid_base <= 0.0)
      return;
   SetHorizontalLine(g_grid_object_prefix + "BASE",g_grid_base,clrSilver,STYLE_DASH,1);
  }

void RecolorGridLines()
  {
   if(!InpDrawGridLevels)
      return;
   DrawBaseLine();
   for(int i=1; i<=g_up_count; i++)
      DrawGridLine(true,i);
   for(int i=1; i<=g_down_count; i++)
      DrawGridLine(false,i);
   ChartRedraw(0);
  }

void DeleteOwnGridObjects()
  {
   if(g_grid_object_prefix == "")
      return;
   int total = ObjectsTotal(0,-1,-1);
   for(int i=total - 1; i>=0; i--)
     {
      string name = ObjectName(0,i,-1,-1);
      if(StringFind(name,g_grid_object_prefix) == 0)
         ObjectDelete(0,name);
     }
  }

//+------------------------------------------------------------------+
//| Fixed grid coordinates and crossing state                        |
//+------------------------------------------------------------------+
double GridLevelPrice(const bool is_up,const int index)
  {
   if(is_up)
      return g_grid_base + g_grid_step * index;
   return g_grid_base - g_grid_step * index;
  }

bool InitializeGridState(const double current_price)
  {
   StrategySettings settings = LiveStrategySettings();
   g_up_count = settings.initial_levels;
   g_down_count = settings.initial_levels;
   if(ArrayResize(g_up_state,g_up_count + 1) < g_up_count + 1 ||
      ArrayResize(g_down_state,g_down_count + 1) < g_down_count + 1)
      return false;
   ArrayInitialize(g_up_state,0);
   ArrayInitialize(g_down_state,0);

   // Seed existing levels relative to the current price to avoid false startup crosses.
   for(int i=1; i<=g_up_count; i++)
     {
      g_up_state[i] = ComparePriceToLevel(current_price,GridLevelPrice(true,i));
      DrawGridLine(true,i);
     }
   for(int i=1; i<=g_down_count; i++)
     {
      g_down_state[i] = ComparePriceToLevel(current_price,GridLevelPrice(false,i));
      DrawGridLine(false,i);
     }
   DrawBaseLine();
   return true;
  }

void ExpandGrid(const double price)
  {
   StrategySettings settings = LiveStrategySettings();
   if(g_grid_step <= 0.0)
      return;
   int guard = 0;
   double upper_limit = price + g_grid_step;
   while(g_up_count < settings.max_levels && guard < 10000)
     {
      guard++;
      int next_index = g_up_count + 1;
      if(GridLevelPrice(true,next_index) <= upper_limit)
        {
         if(ArrayResize(g_up_state,next_index + 1) < next_index + 1)
            break;
         g_up_count = next_index;
         g_up_state[next_index] = 0; // New line arms on this observation; it does not fire immediately.
         DrawGridLine(true,next_index);
        }
      else
         break;
     }

   guard = 0;
   double lower_limit = price - g_grid_step;
   while(g_down_count < settings.max_levels && guard < 10000)
     {
      guard++;
      int next_index = g_down_count + 1;
      if(GridLevelPrice(false,next_index) >= lower_limit)
        {
         if(ArrayResize(g_down_state,next_index + 1) < next_index + 1)
            break;
         g_down_count = next_index;
         g_down_state[next_index] = 0;
         DrawGridLine(false,next_index);
        }
      else
         break;
     }
  }

//+------------------------------------------------------------------+
//| Closed-candle direction                                           |
//+------------------------------------------------------------------+
int SignalHistoryBars()
  {
   StrategySettings settings = LiveStrategySettings();
   return ClampedSignalHistory(settings.signal_history);
  }

// Chronological (non-series) rates, shared by live trading and historical replay.
// Only bars BEFORE current_index may influence the signal; never read the live candle.
int CandleSignalForSettings(const MqlRates &rates[],const int current_index,const StrategySettings &settings)
  {
   if(current_index < 2 || current_index >= ArraySize(rates))
      return 0;
   int closed_index = current_index - 1;
   if(settings.candle_mode == SIGNAL_STANDARD_CANDLE)
      return (rates[closed_index].close >= rates[closed_index].open ? 1 : -1);

   int oldest_index = (int)MathMax(0,current_index - ClampedSignalHistory(settings.signal_history) + 1);
   double previous_ha_open = 0.0;
   double previous_ha_close = 0.0;
   int side = 0;
   for(int i=oldest_index; i<=closed_index; i++)
     {
      double ha_close = (rates[i].open + rates[i].high + rates[i].low + rates[i].close) / 4.0;
      double ha_open = (i == oldest_index
                        ? (rates[i].open + rates[i].close) / 2.0
                        : (previous_ha_open + previous_ha_close) / 2.0);
      side = (ha_close >= ha_open ? 1 : -1);
      previous_ha_open = ha_open;
      previous_ha_close = ha_close;
     }
   return side;
  }

int ClosedCandleSignalFromRates(const MqlRates &rates[],const int current_index)
  {
   StrategySettings settings = LiveStrategySettings();
   return CandleSignalForSettings(rates,current_index,settings);
  }

bool CalculateClosedCandleSignal(int &side_out,datetime &current_bar_time)
  {
   StrategySettings settings = LiveStrategySettings();
   side_out = 0;
   current_bar_time = 0;
   MqlRates rates[];
   ArraySetAsSeries(rates,false);
   int copied = CopyRates(_Symbol,settings.signal_timeframe,0,SignalHistoryBars(),rates);
   if(copied < 3)
      return false;
   current_bar_time = rates[copied - 1].time;
   side_out = ClosedCandleSignalFromRates(rates,copied - 1);
   return (side_out != 0);
  }

void RefreshClosedCandleSignal(const bool force)
  {
   StrategySettings settings = LiveStrategySettings();
   datetime chart_bar_time = iTime(_Symbol,settings.signal_timeframe,0);
   if(!force && chart_bar_time > 0 && chart_bar_time == g_last_signal_bar_time)
      return;

   int new_side = 0;
   datetime current_bar_time = 0;
   if(!CalculateClosedCandleSignal(new_side,current_bar_time))
      return;

   g_last_signal_bar_time = (current_bar_time > 0 ? current_bar_time : chart_bar_time);
   if(new_side == 0)
      return;

   int old_side = g_signal_side;
   g_signal_side = new_side;
   if(old_side != new_side)
     {
      g_last_action = StringFormat("M1 sinyali %s oldu",SideName(new_side));
      PrintFormat("Closed M1 signal changed: %s -> %s (%s)",SideName(old_side),SideName(new_side),
                  (settings.candle_mode == SIGNAL_HEIKEN_ASHI ? "Heiken Ashi" : "standard candle"));
      RecolorGridLines();
     }
  }

//+------------------------------------------------------------------+
//| Position state, discovery and risk sizing                        |
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

int ParseLineCode(const string comment)
  {
   int marker = StringFind(comment,"M1G:");
   if(marker < 0)
      return 0;
   string line = StringSubstr(comment,marker + 4);
   if(StringFind(line,"U") == 0)
      return (int)StringToInteger(StringSubstr(line,1));
   if(StringFind(line,"D") == 0)
      return -(int)MathAbs((double)StringToInteger(StringSubstr(line,1)));
   return 0;
  }

int PositionLineCode(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket))
      return 0;
   ulong identifier = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   for(int i=0; i<ArraySize(g_saved_grid_positions); i++)
      if(g_saved_grid_positions[i].identifier == identifier)
         return g_saved_grid_positions[i].line_code;
   if(MQLInfoInteger(MQL_TESTER))
      return ParseLineCode(PositionGetString(POSITION_COMMENT));
   string key = PositionStateKey(identifier,"LN");
   if(GlobalVariableCheck(key))
      return (int)MathRound(GlobalVariableGet(key));
   return ParseLineCode(PositionGetString(POSITION_COMMENT));
  }

int FindSavedGridPosition(const ulong identifier)
  {
   for(int i=0; i<ArraySize(g_saved_grid_positions); i++)
      if(g_saved_grid_positions[i].identifier == identifier)
         return i;
   return -1;
  }

bool CacheGridPosition(const ulong identifier,const int line_code,const double step,
                       const int tp,const int sl,const long generation)
  {
   int index = FindSavedGridPosition(identifier);
   if(index < 0)
     {
      index = ArraySize(g_saved_grid_positions);
      if(ArrayResize(g_saved_grid_positions,index + 1,64) < index + 1)
         return false;
     }
   g_saved_grid_positions[index].identifier = identifier;
   g_saved_grid_positions[index].line_code = line_code;
   g_saved_grid_positions[index].step = step;
   g_saved_grid_positions[index].tp = tp;
   g_saved_grid_positions[index].sl = sl;
   g_saved_grid_positions[index].generation = generation;
   return true;
  }

void StorePositionSettings(const ulong identifier,const int line_code,const double grid_step,
                           const int tp_grids,const int sl_grids)
  {
   // The in-memory record is essential in the Strategy Tester too: runtime
   // optimization must never overwrite an older layer's protection settings.
   CacheGridPosition(identifier,line_code,grid_step,tp_grids,sl_grids,g_grid_generation);
   if(MQLInfoInteger(MQL_TESTER))
      return;
   GlobalVariableSet(PositionStateKey(identifier,"LN"),(double)line_code);
   GlobalVariableSet(PositionStateKey(identifier,"GS"),grid_step);
   GlobalVariableSet(PositionStateKey(identifier,"TP"),(double)tp_grids);
   GlobalVariableSet(PositionStateKey(identifier,"SL"),(double)sl_grids);
   GlobalVariableSet(PositionStateKey(identifier,"GN"),(double)g_grid_generation);
   GlobalVariablesFlush();
  }

void DeletePositionSettings(const ulong identifier)
  {
   int index = FindSavedGridPosition(identifier);
   if(index >= 0)
     {
      int size = ArraySize(g_saved_grid_positions);
      for(int i=index; i<size - 1; i++)
         g_saved_grid_positions[i] = g_saved_grid_positions[i + 1];
      ArrayResize(g_saved_grid_positions,size - 1);
     }
   if(MQLInfoInteger(MQL_TESTER))
      return;
   GlobalVariableDel(PositionStateKey(identifier,"LN"));
   GlobalVariableDel(PositionStateKey(identifier,"GS"));
   GlobalVariableDel(PositionStateKey(identifier,"TP"));
   GlobalVariableDel(PositionStateKey(identifier,"SL"));
   GlobalVariableDel(PositionStateKey(identifier,"GN"));
   GlobalVariablesFlush();
  }

void GetPositionGridSettings(const ulong ticket,double &grid_step,int &tp_grids,int &sl_grids)
  {
   StrategySettings settings = LiveStrategySettings();
   grid_step = g_grid_step;
   tp_grids = settings.tp_grids;
   sl_grids = settings.sl_grids;
   if(!PositionSelectByTicket(ticket))
      return;
   ulong identifier = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   int index = FindSavedGridPosition(identifier);
   if(index >= 0)
     {
      grid_step = g_saved_grid_positions[index].step;
      tp_grids = g_saved_grid_positions[index].tp;
      sl_grids = g_saved_grid_positions[index].sl;
      return;
     }
   long generation = g_grid_generation;
   int line_code = PositionLineCode(ticket);
   if(!MQLInfoInteger(MQL_TESTER))
     {
      if(GlobalVariableCheck(PositionStateKey(identifier,"GS")))
        {
         double saved = GlobalVariableGet(PositionStateKey(identifier,"GS"));
         if(saved > 0.0) grid_step = saved;
        }
      if(GlobalVariableCheck(PositionStateKey(identifier,"TP")))
        {
         int saved = (int)MathRound(GlobalVariableGet(PositionStateKey(identifier,"TP")));
         if(saved > 0) tp_grids = saved;
        }
      if(GlobalVariableCheck(PositionStateKey(identifier,"SL")))
        {
         int saved = (int)MathRound(GlobalVariableGet(PositionStateKey(identifier,"SL")));
         if(saved > 0) sl_grids = saved;
        }
      if(GlobalVariableCheck(PositionStateKey(identifier,"GN")))
         generation = (long)GlobalVariableGet(PositionStateKey(identifier,"GN"));
      if(!GlobalVariableCheck(PositionStateKey(identifier,"GS")))
        {
         StorePositionSettings(identifier,line_code,grid_step,tp_grids,sl_grids);
         return;
        }
     }
   CacheGridPosition(identifier,line_code,grid_step,tp_grids,sl_grids,generation);
  }

long PositionGridGeneration(const ulong ticket)
  {
   double step;
   int tp,sl;
   GetPositionGridSettings(ticket,step,tp,sl);
   if(!PositionSelectByTicket(ticket))
      return -1;
   int index = FindSavedGridPosition((ulong)PositionGetInteger(POSITION_IDENTIFIER));
   return (index >= 0 ? g_saved_grid_positions[index].generation : -1);
  }

bool SnapshotOpenGridSettings()
  {
   for(int i=PositionsTotal() - 1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      double step;
      int tp,sl;
      GetPositionGridSettings(ticket,step,tp,sl);
      if(!PositionSelectByTicket(ticket))
         continue;
      if(FindSavedGridPosition((ulong)PositionGetInteger(POSITION_IDENTIFIER)) < 0)
         return false;
     }
   return true;
  }

int CountOurPositions(const int side_filter)
  {
   int count = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
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

bool HasPositionOnGridLine(const int side,const int line_code)
  {
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      if(SideFromPositionType(PositionGetInteger(POSITION_TYPE)) != side)
         continue;
      if(PositionLineCode(ticket) == line_code && PositionGridGeneration(ticket) == g_grid_generation)
         return true;
     }
   return false;
  }

bool CloseOurPosition(const ulong ticket,const string reason);

//+------------------------------------------------------------------+
//| Position-limit rotation                                          |
//| At the per-side or total position cap, close the oldest position |
//| on the same side so the incoming signal can open a fresh entry   |
//| on the new grid level. Returns true when a slot was freed.       |
//+------------------------------------------------------------------+
bool CloseOldestPositionOnSide(const int side,const int protected_line_code)
  {
   ulong    oldest_ticket = 0;
   datetime oldest_time = 0;
   long     oldest_time_msc = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      if(SideFromPositionType(PositionGetInteger(POSITION_TYPE)) != side)
         continue;
      // Never sacrifice a position just opened on the level that is firing now.
      if(protected_line_code != 0 && PositionLineCode(ticket) == protected_line_code &&
         PositionGridGeneration(ticket) == g_grid_generation)
         continue;

      datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
      long open_time_msc = PositionGetInteger(POSITION_TIME_MSC);
      bool is_older = (oldest_ticket == 0 ||
                       open_time < oldest_time ||
                       (open_time == oldest_time && open_time_msc < oldest_time_msc));
      if(is_older)
        {
         oldest_ticket = ticket;
         oldest_time = open_time;
         oldest_time_msc = open_time_msc;
        }
     }

   if(oldest_ticket == 0)
      return false; // Nothing on this side can be rotated out.

   string reason = StringFormat("Sınır rotasyonu: en eski %s pozisyon kapatıldı",SideName(side));
   g_last_action = reason;
   if(!CloseOurPosition(oldest_ticket,reason))
      return false;

   // In netting-style partial closures a small residual could stay behind; only
   // report success when the slot is genuinely free.
   return !SelectOurPosition(oldest_ticket);
  }

double OrderVolume()
  {
   double min_volume = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double max_volume = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double volume_step = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(min_volume <= 0.0 || volume_step <= 0.0)
      return 0.0;
   if(InpUseBrokerMinimumVolume)
      return min_volume;

   double requested = InpFixedLots;
   if(requested <= 0.0)
      return 0.0;
   if(max_volume > 0.0 && requested > max_volume)
      requested = max_volume;
   double result = MathFloor(requested / volume_step + 1.0e-10) * volume_step;
   result = NormalizeDouble(result,8);
   if(result + 1.0e-10 < min_volume)
     {
      PrintFormat("Hacim atlandı: istenen lot %.8f broker minimumu %.8f altında.",requested,min_volume);
      return 0.0;
     }
   return result;
  }

double PositionTakeProfit(const double entry,const int side,const double grid_step,const int grids)
  {
   double raw = entry + side * grid_step * grids;
   return NormalizePriceToTick(raw,(side > 0 ? 1 : -1));
  }

double PositionStopLoss(const double entry,const int side,const double grid_step,const int grids)
  {
   double raw = entry - side * grid_step * grids;
   return NormalizePriceToTick(raw,(side > 0 ? -1 : 1));
  }

bool ModifyPositionProtection(const ulong ticket,const int side,const double entry,
                              const double grid_step,const int tp_grids,const int sl_grids)
  {
   if(!PositionSelectByTicket(ticket))
      return false;
   double desired_tp = PositionTakeProfit(entry,side,grid_step,tp_grids);
   double desired_sl = PositionStopLoss(entry,side,grid_step,sl_grids);
   double current_tp = PositionGetDouble(POSITION_TP);
   double current_sl = PositionGetDouble(POSITION_SL);
   double tolerance = TickSize() * 0.5;
   if(MathAbs(current_tp - desired_tp) <= tolerance && MathAbs(current_sl - desired_sl) <= tolerance)
      return true;

   bool modified = trade.PositionModify(ticket,desired_sl,desired_tp);
   if(!TradeRetcodeOK(modified))
     {
      PrintFormat("Koruma emri güncellenemedi ticket=%I64u retcode=%u (%s). EA yerel fiyat kontrolünü sürdürecek.",
                  ticket,trade.ResultRetcode(),trade.ResultRetcodeDescription());
      return false;
     }
   return true;
  }

bool CloseOurPosition(const ulong ticket,const string reason)
  {
   if(!SelectOurPosition(ticket))
      return true; // Already closed by server-side TP/SL.
   ulong identifier = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   int side = SideFromPositionType(PositionGetInteger(POSITION_TYPE));
   bool sent = trade.PositionClose(ticket,InpDeviationPoints);
   if(!TradeRetcodeOK(sent))
     {
      PrintFormat("Kapatma başarısız ticket=%I64u neden=%s retcode=%u (%s)",
                  ticket,reason,trade.ResultRetcode(),trade.ResultRetcodeDescription());
      return false;
     }
   if(PositionSelectByTicket(ticket))
     {
      PrintFormat("Pozisyon tamamen kapanmadı ticket=%I64u kalan hacim=%.8f",ticket,
                  PositionGetDouble(POSITION_VOLUME));
      return false;
     }
   DeletePositionSettings(identifier);
   PrintFormat("Pozisyon kapandı: ticket=%I64u side=%s reason=%s",ticket,SideName(side),reason);
   g_last_action = reason;
   return true;
  }

void ReseedGridCrossState(const double current_price)
  {
   if(current_price <= 0.0)
      return;
   for(int i=1; i<=g_up_count; i++)
      g_up_state[i] = ComparePriceToLevel(current_price,GridLevelPrice(true,i));
   for(int i=1; i<=g_down_count; i++)
      g_down_state[i] = ComparePriceToLevel(current_price,GridLevelPrice(false,i));
  }

void SyncProfitCycleWhenFlat()
  {
   if(g_profit_target_liquidating)
      return;
   StrategySettings settings = LiveStrategySettings();
   if(g_cycle_settings_initialized && SameNumber(g_cycle_equity_target,settings.equity_target) &&
      g_cycle_rebase_on_low == settings.rebase_on_low)
      return;
   if(CountOurPositions() > 0)
      return;
   double equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(equity <= 0.0)
      equity = AccountInfoDouble(ACCOUNT_BALANCE);
   if(equity <= 0.0)
      return;
   g_cycle_equity_target = settings.equity_target;
   g_cycle_rebase_on_low = settings.rebase_on_low;
   g_cycle_settings_initialized = true;
   g_profit_target_start_equity = equity;
   SaveProfitTargetState();
  }

bool HandleEquityProfitTarget()
  {
   SyncProfitCycleWhenFlat();
   if(CycleEquityTarget() <= 0.0 || g_profit_target_start_equity <= 0.0)
      return false;

   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(current_equity <= 0.0)
      current_equity = AccountInfoDouble(ACCOUNT_BALANCE);

   // Optional two-sided target: every new equity low becomes the new base.
   // Example: start 100, target 2. A drop to 95 re-bases the target to 97;
   // the next rise to 97 closes every position and starts a fresh cycle.
   if(CycleRebaseOnLow() && !g_profit_target_liquidating &&
      current_equity > 0.0 && current_equity < g_profit_target_start_equity)
     {
      double previous_base = g_profit_target_start_equity;
      g_profit_target_start_equity = current_equity;
      if(!MQLInfoInteger(MQL_TESTER))
        {
         GlobalVariableSet(GridStateKey("PTBASE"),g_profit_target_start_equity);
         GlobalVariableSet(GridStateKey("PTLOW"),1.0);
        }
      datetime low_now = TimeCurrent();
      if(g_last_low_rebase_log == 0 || low_now - g_last_low_rebase_log >= 10)
        {
         g_last_low_rebase_log = low_now;
         PrintFormat("Yeni özsermaye dibi: taban %.2f -> %.2f; yeni kapanış hedefi %.2f %s",
                     previous_base,g_profit_target_start_equity,
                     g_profit_target_start_equity + CycleEquityTarget(),
                     AccountInfoString(ACCOUNT_CURRENCY));
        }
      g_last_action = StringFormat("Yeni özsermaye dibi %.2f; hedef tabanı güncellendi",
                                   g_profit_target_start_equity);
     }

   if(!g_profit_target_liquidating &&
      current_equity - g_profit_target_start_equity >= CycleEquityTarget())
     {
      g_profit_target_liquidating = true;
      SaveProfitTargetState();
      g_last_action = "Özsermaye hedefi ulaştı; EA pozisyonları kapatılıyor";
      PrintFormat("Özsermaye hedefi ulaştı: başlangıç=%.2f güncel=%.2f hedef=%.2f %s; bu EA'nın pozisyonları kapatılıyor.",
                  g_profit_target_start_equity,current_equity,CycleEquityTarget(),
                  AccountInfoString(ACCOUNT_CURRENCY));
     }

   if(!g_profit_target_liquidating)
      return false;

   ulong tickets[];
   ArrayResize(tickets,0);
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      int n = ArraySize(tickets);
      if(ArrayResize(tickets,n + 1) >= n + 1)
         tickets[n] = ticket;
     }
   for(int i=0; i<ArraySize(tickets); i++)
      CloseOurPosition(tickets[i],"Özsermaye kâr hedefi");

   int remaining = CountOurPositions(0);
   if(remaining > 0)
     {
      g_last_action = StringFormat("Kâr hedefi: %d EA pozisyonu daha kapatılacak",remaining);
      return true;
     }

   // Start the next profit cycle only after every position belonging to this EA is closed.
   double new_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(new_equity <= 0.0)
      new_equity = AccountInfoDouble(ACCOUNT_BALANCE);
   if(new_equity > 0.0)
     {
      g_profit_target_start_equity = new_equity;
      g_profit_target_liquidating = false;
      SyncProfitCycleWhenFlat();
      SaveProfitTargetState();
      MqlTick tick;
      if(SymbolInfoTick(_Symbol,tick))
         ReseedGridCrossState(MidPrice(tick));
      g_last_action = "Kâr hedefi tamamlandı; yeni hedef döngüsü başladı";
      PrintFormat("Yeni kâr hedefi döngüsü: başlangıç özsermayesi=%.2f %s hedef=%.2f",
                  g_profit_target_start_equity,AccountInfoString(ACCOUNT_CURRENCY),
                  CycleEquityTarget());
     }
   return true; // Do not open a replacement position on the same tick as target liquidation.
  }

void ClosePositionsOppositeToTradeSide(const int new_trade_side)
  {
   if(new_trade_side == 0)
      return;
   ulong tickets[];
   ArrayResize(tickets,0);
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      if(SideFromPositionType(PositionGetInteger(POSITION_TYPE)) == -new_trade_side)
        {
         int n = ArraySize(tickets);
         if(ArrayResize(tickets,n + 1) >= n + 1)
            tickets[n] = ticket;
        }
     }
   for(int i=0; i<ArraySize(tickets); i++)
      CloseOurPosition(tickets[i],"Çizgi rengi değişimi: ters pozisyon kapatıldı");
  }

//+------------------------------------------------------------------+
//| Grid entry                                                        |
//+------------------------------------------------------------------+
bool FindPositionFromDeal(const ulong deal,const int expected_side,const string expected_comment,
                          const long earliest_time_msc,ulong &ticket_out)
  {
   ticket_out = 0;
   if(deal > 0 && HistoryDealSelect(deal))
     {
      ulong position_id = (ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
      if(position_id > 0)
        {
         for(int i=PositionsTotal()-1; i>=0; i--)
           {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket))
               continue;
            if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
               (ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
               continue;
            if((ulong)PositionGetInteger(POSITION_IDENTIFIER) == position_id)
              {
               ticket_out = ticket;
               return true;
              }
           }
        }
     }

   // Fallback for brokers that do not return a position id immediately.
   long newest_time = -1;
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         (ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber ||
         SideFromPositionType(PositionGetInteger(POSITION_TYPE)) != expected_side)
         continue;
      long time_msc = PositionGetInteger(POSITION_TIME_MSC);
      string comment = PositionGetString(POSITION_COMMENT);
      if(time_msc + 1000 < earliest_time_msc)
         continue;
      if(expected_comment != "" && StringFind(comment,expected_comment) < 0)
         continue;
      if(time_msc >= newest_time)
        {
         newest_time = time_msc;
         ticket_out = ticket;
        }
     }
   return (ticket_out > 0);
  }

bool OpenGridPosition(const int side,const int line_code,const double signal_price)
  {
   StrategySettings settings = LiveStrategySettings();
   if(side == 0 || g_grid_step <= 0.0 || g_signal_side == 0)
      return false;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick) || tick.ask <= 0.0 || tick.bid <= 0.0)
      return false;

   double spread_price = MathMax(0.0,tick.ask - tick.bid);
   double spread_points = spread_price / _Point;
   if(settings.max_spread_points > 0 && spread_points > settings.max_spread_points)
     {
      g_last_action = StringFormat("Spread yüksek: %.1f point",spread_points);
      return false;
     }
   if(settings.max_spread_fraction > 0.0 && spread_price > g_grid_step * settings.max_spread_fraction)
     {
      g_last_action = StringFormat("Spread grid adımına göre yüksek: %.1f point",spread_points);
      return false;
     }

   if(settings.one_per_line && HasPositionOnGridLine(side,line_code))
     {
      g_last_action = "Bu grid çizgisinde aynı yönlü pozisyon açık";
      return false;
     }

   // Validate the new order fully before any rotation closes an existing position,
   // so a rejected/undersized entry never leaves the grid short of a layer.
   double volume = OrderVolume();
   if(volume <= 0.0)
     {
      g_last_action = "Lot hacmi broker sınırlarına uymuyor";
      return false;
     }

   double expected_entry = (side > 0 ? tick.ask : tick.bid);
   double expected_tp = PositionTakeProfit(expected_entry,side,g_grid_step,settings.tp_grids);
   double expected_sl = PositionStopLoss(expected_entry,side,g_grid_step,settings.sl_grids);
   if(expected_tp <= 0.0 || expected_sl <= 0.0)
     {
      g_last_action = "Pozitif olmayan TP/SL fiyatı nedeniyle giriş atlandı";
      return false;
     }

   double min_stop_distance = (double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL) * _Point;
   double protection_reference = (side > 0 ? tick.bid : tick.ask);
   double tp_distance = (side > 0 ? expected_tp - protection_reference : protection_reference - expected_tp);
   double sl_distance = (side > 0 ? protection_reference - expected_sl : expected_sl - protection_reference);
   if(min_stop_distance > 0.0 &&
      (tp_distance + CrossTolerance() < min_stop_distance || sl_distance + CrossTolerance() < min_stop_distance))
     {
      g_last_action = "Broker stop mesafesi nedeniyle giriş atlandı; rotasyon yapılmadı";
      return false;
     }

   int side_count = CountOurPositions(side);
   int total_count = CountOurPositions(0);
   bool total_full = (InpMaxTotalPositions > 0 && total_count >= InpMaxTotalPositions);
   bool side_full = (InpMaxLayersPerSide > 0 && side_count >= InpMaxLayersPerSide);
   if(total_full || side_full)
     {
      if(!settings.rotate_oldest)
        {
         g_last_action = (total_full
                          ? "Toplam pozisyon sınırı dolu"
                          : StringFormat("%s katman sınırı dolu",SideName(side)));
         return false;
        }

      // Position limit is reached: free exactly one slot by closing the oldest
      // position on this side, then open the fresh entry on the new level.
      // The side count therefore drops by one before returning to the cap.
      if(!CloseOldestPositionOnSide(side,line_code))
        {
         g_last_action = (total_full
                          ? "Toplam pozisyon sınırı dolu; rotasyon için uygun aynı yönlü pozisyon yok"
                          : StringFormat("%s katman sınırı dolu; rotasyon için uygun aynı yönlü pozisyon yok",SideName(side)));
         return false;
        }
      PrintFormat("Rotasyon: %s | en eski pozisyon kapatıldı, kalan yan=%d toplam=%d; yeni seviyeden giriş denenecek.",
                  SideName(side),CountOurPositions(side),CountOurPositions(0));
     }

   string line_text = (line_code > 0 ? "U" + IntegerToString(line_code) : "D" + IntegerToString(-line_code));
   string comment = "M1G:" + line_text;
   long request_time_msc = (long)tick.time_msc;

   bool sent = false;
   if(side > 0)
      sent = trade.Buy(volume,_Symbol,0.0,expected_sl,expected_tp,comment);
   else
      sent = trade.Sell(volume,_Symbol,0.0,expected_sl,expected_tp,comment);

   if(!TradeRetcodeOK(sent))
     {
      PrintFormat("Grid girişi başarısız side=%s line=%s lot=%.8f retcode=%u (%s)",
                  SideName(side),line_text,volume,trade.ResultRetcode(),trade.ResultRetcodeDescription());
      g_last_action = "Emir broker tarafından reddedildi";
      return false;
     }

   if(trade.ResultDeal() > 0 && HistoryDealSelect(trade.ResultDeal()))
     {
      ulong position_id = (ulong)HistoryDealGetInteger(trade.ResultDeal(),DEAL_POSITION_ID);
      if(position_id > 0)
         StorePositionSettings(position_id,line_code,g_grid_step,settings.tp_grids,settings.sl_grids);
     }
   ulong ticket = 0;
   FindPositionFromDeal(trade.ResultDeal(),side,comment,request_time_msc,ticket);
   if(ticket > 0 && PositionSelectByTicket(ticket))
     {
      ulong identifier = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      double fill_price = PositionGetDouble(POSITION_PRICE_OPEN);
      StorePositionSettings(identifier,line_code,g_grid_step,settings.tp_grids,settings.sl_grids);
      ModifyPositionProtection(ticket,side,fill_price,g_grid_step,settings.tp_grids,settings.sl_grids);
      PrintFormat("Grid giriş: %s line=%s signal=%.*f fill=%.*f lot=%.8f gridStep=%.*f TP=%.*f SL=%.*f",
                  SideName(side),line_text,_Digits,signal_price,_Digits,fill_price,
                  PositionGetDouble(POSITION_VOLUME),_Digits,g_grid_step,
                  _Digits,PositionTakeProfit(fill_price,side,g_grid_step,settings.tp_grids),
                  _Digits,PositionStopLoss(fill_price,side,g_grid_step,settings.sl_grids));
     }
   else
     {
      PrintFormat("Grid emri kabul edildi side=%s line=%s; pozisyon sonraki tikte bulunacak.",SideName(side),line_text);
     }

   g_last_action = StringFormat("Yeni %s giriş: %s",SideName(side),line_text);
   return true;
  }

void HandleGridCross(const bool is_up,const int index,const int cross_direction,
                     const double current_price)
  {
   StrategySettings settings = LiveStrategySettings();
   int trade_side = TradeSideForSignal(g_signal_side);
   if(trade_side == 0)
      return;
   if(!settings.enter_any_cross && cross_direction != trade_side)
      return;

   int line_code = (is_up ? index : -index);
   OpenGridPosition(trade_side,line_code,current_price);
  }

void ProcessGridCrosses(const double price)
  {
   if(g_grid_step <= 0.0 || g_grid_base <= 0.0)
      return;
   ExpandGrid(price);

   // Keep deterministic order if one tick crosses several existing grid levels.
   for(int i=1; i<=g_up_count; i++)
     {
      int now_side = ComparePriceToLevel(price,GridLevelPrice(true,i));
      if(now_side == 0)
         continue;
      int previous = g_up_state[i];
      g_up_state[i] = now_side;
      if(previous != 0 && now_side != previous)
         HandleGridCross(true,i,now_side,price);
     }

   for(int i=g_down_count; i>=1; i--)
     {
      int now_side = ComparePriceToLevel(price,GridLevelPrice(false,i));
      if(now_side == 0)
         continue;
      int previous = g_down_state[i];
      g_down_state[i] = now_side;
      if(previous != 0 && now_side != previous)
         HandleGridCross(false,i,now_side,price);
     }
  }

//+------------------------------------------------------------------+
//| Open position management                                         |
//+------------------------------------------------------------------+
void ManageOpenPositions(const MqlTick &tick)
  {
   StrategySettings settings = LiveStrategySettings();
   ulong tickets[];
   ArrayResize(tickets,0);
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      int n = ArraySize(tickets);
      if(ArrayResize(tickets,n + 1) >= n + 1)
         tickets[n] = ticket;
     }

   for(int i=0; i<ArraySize(tickets); i++)
     {
      ulong ticket = tickets[i];
      if(!SelectOurPosition(ticket))
         continue;

      int side = SideFromPositionType(PositionGetInteger(POSITION_TYPE));
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double step = g_grid_step;
      int tp_grids = settings.tp_grids;
      int sl_grids = settings.sl_grids;
      GetPositionGridSettings(ticket,step,tp_grids,sl_grids);
      if(step <= 0.0 || entry <= 0.0)
         continue;

      double target = PositionTakeProfit(entry,side,step,tp_grids);
      double stop = PositionStopLoss(entry,side,step,sl_grids);
      // Use executable close prices: Bid closes LONG; Ask closes SHORT.
      double close_price = (side > 0 ? tick.bid : tick.ask);
      bool tp_hit = (side > 0 ? close_price >= target : close_price <= target);
      bool sl_hit = (side > 0 ? close_price <= stop : close_price >= stop);

      if(tp_hit)
        {
         CloseOurPosition(ticket,StringFormat("TP (%d grid)",tp_grids));
         continue;
        }
      if(sl_hit)
        {
         CloseOurPosition(ticket,StringFormat("SL (%d grid)",sl_grids));
         continue;
        }

      ModifyPositionProtection(ticket,side,entry,step,tp_grids,sl_grids);
     }
  }

// Apply only after a COMPLETE search. Allocation and old-layer snapshots happen
// before changing live state; no trade is sent and no old TP/SL is rewritten here.
bool ApplyOptimizedStrategy(const StrategySettings &settings)
  {
   if(!ValidStrategySettings(settings) || g_profit_target_liquidating)
      return false;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick) || !UsableReplayTick(tick))
      return false;
   double price = MidPrice(tick);
   if(settings.grid_step * settings.sl_grids >= price * 0.90)
      return false;
   int up_state[];
   int down_state[];
   if(ArrayResize(up_state,settings.initial_levels + 1) < settings.initial_levels + 1 ||
      ArrayResize(down_state,settings.initial_levels + 1) < settings.initial_levels + 1 ||
      !SnapshotOpenGridSettings())
      return false;
   ArrayInitialize(up_state,0);
   ArrayInitialize(down_state,0);
   for(int i=1; i<=settings.initial_levels; i++)
     {
      up_state[i] = ComparePriceToLevel(price,settings.grid_base + settings.grid_step * i);
      down_state[i] = ComparePriceToLevel(price,settings.grid_base - settings.grid_step * i);
     }
   bool new_geometry = (!SameNumber(g_grid_step,settings.grid_step) || !SameNumber(g_grid_base,settings.grid_base));
   ArraySwap(g_up_state,up_state);
   ArraySwap(g_down_state,down_state);
   g_up_count = settings.initial_levels;
   g_down_count = settings.initial_levels;
   g_grid_base = settings.grid_base;
   g_grid_step = settings.grid_step;
   if(new_geometry)
      g_grid_generation++;
   g_optimized_settings = settings;
   g_optimizer_settings_active = true;
   GlobalVariableSet(GridStateKey("BASE"),g_grid_base);
   GlobalVariableSet(GridStateKey("STEP"),g_grid_step);
   GlobalVariableSet(GridStateKey("GEN"),(double)g_grid_generation);
   GlobalVariableSet(GridStateKey("AUTOGRID"),1.0);
   GlobalVariablesFlush();
   SyncProfitCycleWhenFlat(); // A changed equity target waits for the old cycle to become flat.
   DeleteOwnGridObjects();
   g_last_signal_bar_time = 0;
   RefreshClosedCandleSignal(true); // Settings changes themselves never trigger opposite-side closures.
   RecolorGridLines();
   g_last_action = "Son 60 dk optimizasyonunun kazanan strateji ayarları uygulandı";
   return true;
  }

//+------------------------------------------------------------------+
//| Last-hour direction replay: isolated virtual positions only       |
//| Both candidates start flat on the SAME fixed live grid.           |
//| No trade/position/global-variable writes are allowed in replay.   |
//+------------------------------------------------------------------+
struct AutoDirectionPosition
  {
   int    side;
   int    line_code;
   long   opened_msc;
   double entry;
   double take_profit;
   double stop_loss;
  };

class CAutoDirectionReplay
  {
private:
   AutoDirectionPosition m_positions[];
   int    m_up_state[];
   int    m_down_state[];
   int    m_up_count;
   int    m_down_count;
   StrategySettings m_settings;
   bool   m_track_drawdown;
   double m_peak_equity;
   double m_max_drawdown;
   int    m_closed_trades;
   double m_volume;
   double m_cross_tolerance;
   double m_min_stop_distance;
   double m_realized;
   double m_equity_base;
   int    m_entries;

   double LevelPrice(const bool is_up,const int index)
     {
      return m_settings.grid_base + (is_up ? 1.0 : -1.0) * m_settings.grid_step * index;
     }

   double CommissionPerSide()
     {
      return InpAutoDirectionCommissionPerLot * m_volume * 0.5;
     }

   bool PositionProfit(const int index,const MqlTick &tick,double &profit)
     {
      int side = m_positions[index].side;
      double close_price = (side > 0 ? tick.bid : tick.ask);
      ENUM_ORDER_TYPE order_type = (side > 0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
      return (OrderCalcProfit(order_type,_Symbol,m_volume,m_positions[index].entry,close_price,profit) &&
              MathIsValidNumber(profit));
     }

   bool Equity(const MqlTick &tick,const bool include_exit_commission,double &equity)
     {
      equity = m_realized;
      for(int i=0; i<ArraySize(m_positions); i++)
        {
         double profit = 0.0;
         if(!PositionProfit(i,tick,profit))
            return false;
         equity += profit;
         if(include_exit_commission)
            equity -= CommissionPerSide();
        }
      return MathIsValidNumber(equity);
     }

   bool RecordEquity(const MqlTick &tick)
     {
      if(!m_track_drawdown)
         return true;
      double equity = 0.0;
      if(!Equity(tick,true,equity))
         return false;
      m_peak_equity = MathMax(m_peak_equity,equity);
      m_max_drawdown = MathMax(m_max_drawdown,m_peak_equity - equity);
      return true;
     }

   bool ClosePosition(const int index,const MqlTick &tick)
     {
      double profit = 0.0;
      if(!PositionProfit(index,tick,profit))
         return false;
      m_realized += profit - CommissionPerSide();
      m_closed_trades++;
      int size = ArraySize(m_positions);
      for(int i=index; i<size - 1; i++)
         m_positions[i] = m_positions[i + 1];
      return (ArrayResize(m_positions,size - 1) == size - 1);
     }

   void Reseed(const double price)
     {
      for(int i=1; i<=m_up_count; i++)
         m_up_state[i] = ComparePriceToLevel(price,LevelPrice(true,i),m_cross_tolerance);
      for(int i=1; i<=m_down_count; i++)
         m_down_state[i] = ComparePriceToLevel(price,LevelPrice(false,i),m_cross_tolerance);
     }

   bool Expand(const double price)
     {
      int guard = 0;
      while(m_up_count < m_settings.max_levels && guard < 10000)
        {
         guard++;
         int next_index = m_up_count + 1;
         if(LevelPrice(true,next_index) > price + m_settings.grid_step)
            break;
         if(ArrayResize(m_up_state,next_index + 1,128) < next_index + 1)
            return false;
         m_up_count = next_index;
         m_up_state[next_index] = 0; // Arm newly added levels without a false cross.
        }
      guard = 0;
      while(m_down_count < m_settings.max_levels && guard < 10000)
        {
         guard++;
         int next_index = m_down_count + 1;
         if(LevelPrice(false,next_index) < price - m_settings.grid_step)
            break;
         if(ArrayResize(m_down_state,next_index + 1,128) < next_index + 1)
            return false;
         m_down_count = next_index;
         m_down_state[next_index] = 0;
        }
      return true;
     }

   bool TryOpen(const int side,const int line_code,const int cross_direction,const MqlTick &tick)
     {
      if(side == 0 || (!m_settings.enter_any_cross && cross_direction != side))
         return true;
      double spread = MathMax(0.0,tick.ask - tick.bid);
      if((m_settings.max_spread_points > 0 && spread / _Point > m_settings.max_spread_points) ||
         (m_settings.max_spread_fraction > 0.0 && spread > m_settings.grid_step * m_settings.max_spread_fraction))
         return true;

      int size = ArraySize(m_positions);
      int side_count = 0;
      for(int i=0; i<size; i++)
        {
         if(m_positions[i].side != side)
            continue;
         side_count++;
         if(m_settings.one_per_line && m_positions[i].line_code == line_code)
            return true;
        }
      double entry = (side > 0 ? tick.ask : tick.bid);
      double tp = PositionTakeProfit(entry,side,m_settings.grid_step,m_settings.tp_grids);
      double sl = PositionStopLoss(entry,side,m_settings.grid_step,m_settings.sl_grids);
      if(tp <= 0.0 || sl <= 0.0)
         return true;
      if(m_min_stop_distance > 0.0)
        {
         double reference = (side > 0 ? tick.bid : tick.ask);
         double tp_distance = (side > 0 ? tp - reference : reference - tp);
         double sl_distance = (side > 0 ? reference - sl : sl - reference);
         if(tp_distance + m_cross_tolerance < m_min_stop_distance || sl_distance + m_cross_tolerance < m_min_stop_distance)
            return true; // Do not score entries rejected by the current static stop-distance rule.
        }

      bool total_full = (InpMaxTotalPositions > 0 && size >= InpMaxTotalPositions);
      bool side_full = (InpMaxLayersPerSide > 0 && side_count >= InpMaxLayersPerSide);
      if(total_full || side_full)
        {
         if(!m_settings.rotate_oldest)
            return true;
         int oldest = -1;
         for(int i=size - 1; i>=0; i--)
           {
            if(m_positions[i].side != side || m_positions[i].line_code == line_code)
               continue;
            if(oldest < 0 || m_positions[i].opened_msc < m_positions[oldest].opened_msc)
               oldest = i;
           }
         if(oldest < 0)
            return true;
         if(!ClosePosition(oldest,tick))
            return false;
         size--;
        }

      if(ArrayResize(m_positions,size + 1,128) < size + 1)
         return false;
      m_positions[size].side = side;
      m_positions[size].line_code = line_code;
      m_positions[size].opened_msc = tick.time_msc;
      m_positions[size].entry = entry;
      m_positions[size].take_profit = tp;
      m_positions[size].stop_loss = sl;
      m_realized -= CommissionPerSide();
      m_entries++;
      return true;
     }

public:
   void Clear()
     {
      ArrayFree(m_positions);
      ArrayFree(m_up_state);
      ArrayFree(m_down_state);
     }

   bool Initialize(const bool reverse,const double volume,const double first_price)
     {
      StrategySettings settings = LiveStrategySettings();
      settings.reverse = reverse;
      settings.grid_base = g_grid_base;
      settings.grid_step = g_grid_step;
      return InitializeSettings(settings,volume,first_price,false);
     }

   bool InitializeSettings(const StrategySettings &settings,const double volume,const double first_price,
                           const bool track_drawdown=true)
     {
      if(!ValidStrategySettings(settings) || volume <= 0.0)
         return false;
      m_settings = settings;
      m_track_drawdown = track_drawdown;
      m_peak_equity = 0.0;
      m_max_drawdown = 0.0;
      m_closed_trades = 0;
      m_volume = volume;
      m_min_stop_distance = (double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL) * _Point;
      m_cross_tolerance = CrossTolerance(); // Avoid symbol-metadata calls on every historical line/tick.
      m_realized = 0.0;
      m_equity_base = 0.0;
      m_entries = 0;
      m_up_count = m_settings.initial_levels;
      m_down_count = m_settings.initial_levels;
      if(ArrayResize(m_positions,0) != 0 ||
         ArrayResize(m_up_state,m_up_count + 1) < m_up_count + 1 ||
         ArrayResize(m_down_state,m_down_count + 1) < m_down_count + 1)
         return false;
      Reseed(first_price);
      return true;
     }

   bool ProcessTick(const MqlTick &tick,const int signal_side,const bool color_changed)
     {
      int side = (m_settings.reverse ? -signal_side : signal_side);
      // Existing server-side protection executes on quotes before fresh entries.
      for(int i=ArraySize(m_positions) - 1; i>=0; i--)
        {
         int position_side = m_positions[i].side;
         double close_price = (position_side > 0 ? tick.bid : tick.ask);
         bool tp_hit = (position_side > 0 ? close_price >= m_positions[i].take_profit
                                         : close_price <= m_positions[i].take_profit);
         bool sl_hit = (position_side > 0 ? close_price <= m_positions[i].stop_loss
                                         : close_price >= m_positions[i].stop_loss);
         if((tp_hit || sl_hit) && !ClosePosition(i,tick))
            return false;
        }
      if(m_settings.close_opposite && color_changed && side != 0)
        {
         for(int i=ArraySize(m_positions) - 1; i>=0; i--)
            if(m_positions[i].side == -side && !ClosePosition(i,tick))
               return false;
        }

      if(!RecordEquity(tick))
         return false;
      double price = MidPrice(tick);
      if(m_settings.equity_target > 0.0)
        {
         double equity = 0.0;
         if(!Equity(tick,false,equity))
            return false;
         if(m_settings.rebase_on_low && equity < m_equity_base)
            m_equity_base = equity;
         if(equity - m_equity_base >= m_settings.equity_target)
           {
            for(int i=ArraySize(m_positions) - 1; i>=0; i--)
               if(!ClosePosition(i,tick))
                  return false;
            m_equity_base = m_realized;
            Reseed(price);
            return RecordEquity(tick); // No replacement entries on a liquidation tick.
           }
        }
      if(!Expand(price))
         return false;
      // Match the live EA's deterministic order, including multiple crosses in a gap.
      for(int i=1; i<=m_up_count; i++)
        {
         int now_side = ComparePriceToLevel(price,LevelPrice(true,i),m_cross_tolerance);
         if(now_side == 0)
            continue;
         int previous = m_up_state[i];
         m_up_state[i] = now_side;
         if(previous != 0 && previous != now_side && !TryOpen(side,i,now_side,tick))
            return false;
        }
      for(int i=m_down_count; i>=1; i--)
        {
         int now_side = ComparePriceToLevel(price,LevelPrice(false,i),m_cross_tolerance);
         if(now_side == 0)
            continue;
         int previous = m_down_state[i];
         m_down_state[i] = now_side;
         if(previous != 0 && previous != now_side && !TryOpen(side,-i,now_side,tick))
            return false;
        }
      return RecordEquity(tick);
     }

   bool Metrics(const MqlTick &last_tick,double &profit,double &drawdown,int &closed_trades,int &entries)
     {
      if(!RecordEquity(last_tick) || !Result(last_tick,profit,entries))
         return false;
      drawdown = m_max_drawdown;
      closed_trades = m_closed_trades;
      return true;
     }

   bool Result(const MqlTick &last_tick,double &profit,int &entries)
     {
      entries = m_entries;
      // Include liquidation P/L and the remaining close commission on open positions.
      // Otherwise a candidate could "win" just by keeping its losses unrealized.
      return Equity(last_tick,true,profit);
     }
  };

// Replay both fixed-direction candidates together so signals/ticks are identical.
bool TestAutoTradeDirections(const MqlTick &ticks[],const MqlRates &rates[],const double volume,
                             double &normal_profit,double &reverse_profit,
                             int &normal_entries,int &reverse_entries)
  {
   if(ArraySize(ticks) < 2 || ArraySize(rates) < 3 || volume <= 0.0 ||
      g_grid_step <= 0.0 || g_grid_base <= 0.0)
      return false;
   CAutoDirectionReplay normal;
   CAutoDirectionReplay reversed;
   int rate_index = 0;
   int signal_index = -1;
   int signal_side = 0;
   int previous_signal = 0;
   int valid_ticks = 0;
   MqlTick last_tick = {};
   for(int i=0; i<ArraySize(ticks); i++)
     {
      if((i % 1024) == 0 && IsStopped())
         return false;
      if(!UsableReplayTick(ticks[i]))
         continue;
      while(rate_index + 1 < ArraySize(rates) && rates[rate_index + 1].time <= ticks[i].time)
         rate_index++;
      if(signal_index != rate_index)
        {
         signal_side = ClosedCandleSignalFromRates(rates,rate_index);
         signal_index = rate_index;
        }
      if(signal_side == 0)
         return false;
      if(valid_ticks == 0 &&
         (!normal.Initialize(false,volume,MidPrice(ticks[i])) ||
          !reversed.Initialize(true,volume,MidPrice(ticks[i]))))
         return false;
      bool color_changed = (previous_signal != 0 && previous_signal != signal_side);
      if(!normal.ProcessTick(ticks[i],signal_side,color_changed) ||
         !reversed.ProcessTick(ticks[i],signal_side,color_changed))
         return false;
      previous_signal = signal_side;
      last_tick = ticks[i];
      valid_ticks++;
     }
   if(valid_ticks < 2)
      return false;
   return (normal.Result(last_tick,normal_profit,normal_entries) &&
           reversed.Result(last_tick,reverse_profit,reverse_entries));
  }

bool SelectAutoReverseDirection(const double normal_profit,const double reverse_profit,const bool current_reverse)
  {
   double tolerance = 1.0e-8 * MathMax(1.0,MathMax(MathAbs(normal_profit),MathAbs(reverse_profit)));
   if(reverse_profit > normal_profit + tolerance)
      return true;
   if(normal_profit > reverse_profit + tolerance)
      return false;
   return current_reverse; // Equal results/no entries: do not churn the direction.
  }

bool LoadSignalRates(const ENUM_TIMEFRAMES timeframe,const int history,const datetime start_time,
                     const datetime end_time,MqlRates &rates[],string &error)
  {
   // The interval is [start_time, end_time); the forming minute is NEVER tested.
   int first_shift = iBarShift(_Symbol,timeframe,start_time,false);
   int last_shift = iBarShift(_Symbol,timeframe,end_time - 1,false);
   if(first_shift < 0 || last_shift < 0 || first_shift < last_shift)
     {
      error = "Sinyal mum geçmişi henüz hazır değil";
      return false;
     }
   int needed = first_shift - last_shift + history;
   ArraySetAsSeries(rates,false);
   ResetLastError();
   // Anchor the copy to a timestamp, not a shifting bar offset: a new live bar
   // can arrive while the terminal is synchronizing the requested history.
   if(CopyRates(_Symbol,timeframe,(datetime)(end_time - 1),needed,rates) != needed || GetLastError() != 0)
     {
      error = "Sinyal mumları/Heiken Ashi ısınma geçmişi eksik";
      return false;
     }
   int first_index = ArraySize(rates) - 1;
   while(first_index >= 0 && rates[first_index].time > start_time)
      first_index--;
   if(first_index < history - 1)
     {
      error = "Pencere başında yeterli sinyal ısınma geçmişi yok";
      return false;
     }

   return true;
  }

bool LoadAutoDirectionHistory(const datetime start_time,const datetime end_time,
                              MqlTick &ticks[],MqlRates &rates[],string &error)
  {
   StrategySettings settings = LiveStrategySettings();
   if(!LoadSignalRates(settings.signal_timeframe,ClampedSignalHistory(settings.signal_history),start_time,end_time,rates,error))
      return false;

   ArraySetAsSeries(ticks,false);
   ResetLastError();
   int copied = CopyTicksRange(_Symbol,ticks,COPY_TICKS_ALL,
                              (ulong)start_time * 1000,(ulong)end_time * 1000 - 1);
   int tick_error = GetLastError();
   if(copied < 2 || tick_error != 0)
     {
      error = StringFormat("Son 60 dk tick geçmişi hazır değil (tick=%d, hata=%d)",copied,tick_error);
      return false; // Discard partial/timed-out copies; never select on an incomplete load.
     }

   // A copied tail alone must not be mistaken for a complete hour. Market-closed
   // gaps are allowed, but every existing M1 candle must have ticks in the replay.
   MqlRates coverage[];
   ArraySetAsSeries(coverage,false);
   ResetLastError();
   int bars = CopyRates(_Symbol,PERIOD_M1,start_time,(datetime)(end_time - 1),coverage);
   if(bars < 1 || GetLastError() != 0)
     {
      error = "Son 60 dk M1 kapsam kontrolü hazır değil";
      return false;
     }
   int tick_index = 0;
   for(int i=0; i<bars; i++)
     {
      while(tick_index < copied && (ticks[tick_index].time < coverage[i].time || !UsableReplayTick(ticks[tick_index])))
         tick_index++;
      if(tick_index >= copied || ticks[tick_index].time >= coverage[i].time + 60)
        {
         error = "Son 60 dk içindeki bazı M1 mumlarının tick geçmişi eksik";
         return false;
        }
     }
   return true;
  }

void RefreshAutoTradeDirection(const bool force)
  {
   if(!InpAutoReverseTradeDirection || InpAutoOptimizeSettings)
      return;
   datetime now = TimeCurrent(); // Broker/server time, not the PC's clock.
   datetime minute = (datetime)(((long)now / 60) * 60);
   if(minute < 3600 || (!force && g_auto_direction_window_end == minute))
      return;
   bool first_attempt = (g_auto_direction_attempt_minute != minute);
   if(!force && !first_attempt && now < g_auto_direction_retry_after)
      return;
   g_auto_direction_attempt_minute = minute;
   g_auto_direction_retry_after = now + 10;

   MqlTick ticks[];
   MqlRates rates[];
   string error = "";
   double normal_profit = 0.0;
   double reverse_profit = 0.0;
   int normal_entries = 0;
   int reverse_entries = 0;
   double volume = OrderVolume();
   bool ready = (volume > 0.0);
   if(!ready)
      error = "Geçerli test lotu yok; lot ayarını kontrol edin";
   if(ready)
      ready = LoadAutoDirectionHistory(minute - 3600,minute,ticks,rates,error);
   if(ready && !TestAutoTradeDirections(ticks,rates,volume,normal_profit,reverse_profit,normal_entries,reverse_entries))
     {
      ready = false;
      error = "Sanal test tamamlanamadı (fiyat/kâr hesabı/bellek/geçmiş)";
     }
   if(!ready)
     {
      g_auto_direction_status = "Seçim korundu; " + error;
      if(first_attempt || force)
         Print("Otomatik yön: ",g_auto_direction_status,". 10 saniye sonra yeniden denenecek.");
      return;
     }

   bool previous_reverse = g_active_reverse_trade_direction;
   g_active_reverse_trade_direction = SelectAutoReverseDirection(normal_profit,reverse_profit,previous_reverse);
   g_auto_direction_window_end = minute;
   g_auto_direction_normal_profit = normal_profit;
   g_auto_direction_reverse_profit = reverse_profit;
   g_auto_direction_normal_entries = normal_entries;
   g_auto_direction_reverse_entries = reverse_entries;
   g_auto_direction_status = "Test tamamlandı";
   PrintFormat("Otomatik yön testi [%s - %s): false=%.2f (%d giriş), true=%.2f (%d giriş) %s; seçim=%s%s",
               TimeToString(minute - 3600,TIME_DATE|TIME_MINUTES),TimeToString(minute,TIME_DATE|TIME_MINUTES),
               normal_profit,normal_entries,reverse_profit,reverse_entries,AccountInfoString(ACCOUNT_CURRENCY),
               (g_active_reverse_trade_direction ? "true (ters)" : "false (normal)"),
               (previous_reverse != g_active_reverse_trade_direction ? " [değişti]" : " [korundu]"));
   if(previous_reverse != g_active_reverse_trade_direction)
      g_last_action = StringFormat("Otomatik işlem yönü: %s",(g_active_reverse_trade_direction ? "ters (true)" : "normal (false)"));
  }

void RefreshTradingDirection(const bool force)
  {
   int previous_signal = g_signal_side;
   RefreshClosedCandleSignal(force);
   RefreshAutoTradeDirection(force);
   // History synchronization can cross a candle boundary; use the latest signal.
   if(InpAutoReverseTradeDirection)
      RefreshClosedCandleSignal(false);
   // Resolve the new signal AND the new direction before optional color-change
   // closures; never close against an intermediate/stale direction selection.
   StrategySettings settings = LiveStrategySettings();
   if(settings.close_opposite && previous_signal != 0 &&
      g_signal_side != 0 && previous_signal != g_signal_side)
      ClosePositionsOppositeToTradeSide(TradeSideForSignal(g_signal_side));
   // A direction-only switch affects new entries, not existing layers' TP/SL.
  }

//+------------------------------------------------------------------+
//| Bounded multi-parameter optimization; never exhaustive/global     |
//| Replay is sliced across OnTimer events so live ticks keep running.|
//+------------------------------------------------------------------+
enum ENUM_OPT_FIELD
  {
   OPT_TIMEFRAME=0, OPT_CANDLE_MODE, OPT_SIGNAL_HISTORY, OPT_CLOSE_OPPOSITE, OPT_REVERSE,
   OPT_GRID_LOOKBACK, OPT_GRID_MULTIPLIER, OPT_MIN_SPREAD, OPT_INITIAL_LEVELS, OPT_MAX_LEVELS,
   OPT_ENTER_ANY, OPT_TP, OPT_SL, OPT_ROTATE, OPT_ONE_PER_LINE, OPT_SPREAD_POINTS,
   OPT_SPREAD_FRACTION, OPT_EQUITY_TARGET, OPT_REBASE, OPT_FIELD_COUNT
  };

struct OptimizationChoices
  {
   double values[];
  };
struct OptimizationHistory
  {
   ENUM_TIMEFRAMES timeframe;
   MqlRates rates[];
  };

bool AddOptimizationChoice(OptimizationChoices &choices,const double value)
  {
   for(int i=0; i<ArraySize(choices.values); i++)
      if(SameNumber(choices.values[i],value))
         return true;
   int n = ArraySize(choices.values);
   if(ArrayResize(choices.values,n + 1) < n + 1)
      return false;
   choices.values[n] = value;
   return true;
  }

double StrategyChoiceValue(const StrategySettings &p,const int field)
  {
   switch(field)
     {
      case OPT_TIMEFRAME: return (double)p.signal_timeframe;
      case OPT_CANDLE_MODE: return (double)p.candle_mode;
      case OPT_SIGNAL_HISTORY: return p.signal_history;
      case OPT_CLOSE_OPPOSITE: return (p.close_opposite ? 1.0 : 0.0);
      case OPT_REVERSE: return (p.reverse ? 1.0 : 0.0);
      case OPT_GRID_LOOKBACK: return p.grid_lookback;
      case OPT_GRID_MULTIPLIER: return p.grid_multiplier;
      case OPT_MIN_SPREAD: return p.min_spread_multiple;
      case OPT_INITIAL_LEVELS: return p.initial_levels;
      case OPT_MAX_LEVELS: return p.max_levels;
      case OPT_ENTER_ANY: return (p.enter_any_cross ? 1.0 : 0.0);
      case OPT_TP: return p.tp_grids;
      case OPT_SL: return p.sl_grids;
      case OPT_ROTATE: return (p.rotate_oldest ? 1.0 : 0.0);
      case OPT_ONE_PER_LINE: return (p.one_per_line ? 1.0 : 0.0);
      case OPT_SPREAD_POINTS: return p.max_spread_points;
      case OPT_SPREAD_FRACTION: return p.max_spread_fraction;
      case OPT_EQUITY_TARGET: return p.equity_target;
      case OPT_REBASE: return (p.rebase_on_low ? 1.0 : 0.0);
     }
   return 0.0;
  }

void SetStrategyChoice(StrategySettings &p,const int field,const double value)
  {
   switch(field)
     {
      case OPT_TIMEFRAME: p.signal_timeframe = (ENUM_TIMEFRAMES)(int)value; break;
      case OPT_CANDLE_MODE: p.candle_mode = (ENUM_SIGNAL_CANDLE_MODE)(int)value; break;
      case OPT_SIGNAL_HISTORY: p.signal_history = (int)value; break;
      case OPT_CLOSE_OPPOSITE: p.close_opposite = (value > 0.5); break;
      case OPT_REVERSE: p.reverse = (value > 0.5); break;
      case OPT_GRID_LOOKBACK: p.grid_lookback = (int)value; break;
      case OPT_GRID_MULTIPLIER: p.grid_multiplier = value; break;
      case OPT_MIN_SPREAD: p.min_spread_multiple = value; break;
      case OPT_INITIAL_LEVELS: p.initial_levels = (int)value; break;
      case OPT_MAX_LEVELS: p.max_levels = (int)value; break;
      case OPT_ENTER_ANY: p.enter_any_cross = (value > 0.5); break;
      case OPT_TP: p.tp_grids = (int)value; break;
      case OPT_SL: p.sl_grids = (int)value; break;
      case OPT_ROTATE: p.rotate_oldest = (value > 0.5); break;
      case OPT_ONE_PER_LINE: p.one_per_line = (value > 0.5); break;
      case OPT_SPREAD_POINTS: p.max_spread_points = (int)value; break;
      case OPT_SPREAD_FRACTION: p.max_spread_fraction = value; break;
      case OPT_EQUITY_TARGET: p.equity_target = value; break;
      case OPT_REBASE: p.rebase_on_low = (value > 0.5); break;
     }
  }

bool ParseOptimizationTimeframe(string text,ENUM_TIMEFRAMES &timeframe)
  {
   StringToUpper(text);
   if(text == "M1") timeframe = PERIOD_M1;
   else if(text == "M2") timeframe = PERIOD_M2;
   else if(text == "M3") timeframe = PERIOD_M3;
   else if(text == "M4") timeframe = PERIOD_M4;
   else if(text == "M5") timeframe = PERIOD_M5;
   else if(text == "M6") timeframe = PERIOD_M6;
   else if(text == "M10") timeframe = PERIOD_M10;
   else if(text == "M12") timeframe = PERIOD_M12;
   else if(text == "M15") timeframe = PERIOD_M15;
   else if(text == "M20") timeframe = PERIOD_M20;
   else if(text == "M30") timeframe = PERIOD_M30;
   else if(text == "H1") timeframe = PERIOD_H1;
   else if(text == "H2") timeframe = PERIOD_H2;
   else if(text == "H3") timeframe = PERIOD_H3;
   else if(text == "H4") timeframe = PERIOD_H4;
   else if(text == "H6") timeframe = PERIOD_H6;
   else if(text == "H8") timeframe = PERIOD_H8;
   else if(text == "H12") timeframe = PERIOD_H12;
   else if(text == "D1") timeframe = PERIOD_D1;
   else if(text == "W1") timeframe = PERIOD_W1;
   else if(text == "MN1") timeframe = PERIOD_MN1;
   else return false;
   return true;
  }

bool ValidOptimizationValue(const int field,const double value)
  {
   if(!MathIsValidNumber(value) || value < 0.0)
      return false;
   if(field == OPT_GRID_MULTIPLIER)
      return (value > 0.0);
   if(field == OPT_MIN_SPREAD || field == OPT_SPREAD_FRACTION || field == OPT_EQUITY_TARGET)
      return true;
   if(value != MathFloor(value) || value > 2147483647.0)
      return false;
   if(field == OPT_TIMEFRAME)
      return (PeriodSeconds((ENUM_TIMEFRAMES)(int)value) > 0);
   if(field == OPT_SIGNAL_HISTORY)
      return (value >= 50.0 && value <= 1500.0);
   if(field == OPT_GRID_LOOKBACK)
      return (value >= 5.0 && value <= 10000.0);
   if(field == OPT_INITIAL_LEVELS || field == OPT_MAX_LEVELS)
      return (value >= 1.0 && value <= 100000.0);
   if(field == OPT_TP || field == OPT_SL)
      return (value >= 1.0 && value <= 10000.0);
   if(field == OPT_SPREAD_POINTS)
      return true;
   return (value == 0.0 || value == 1.0);
  }

// Deliberately reject malformed numbers instead of StringToDouble's silent zero.
// Non-negative plain decimals only; use '.' for decimals and ',' between values.
bool ParseOptimizationList(const string text,const int field,OptimizationChoices &choices,string &error)
  {
   string tokens[];
   int count = StringSplit(text,StringGetCharacter(",",0),tokens);
   if(count < 1 || count > 16)
     {
      error = "Her aday listesi 1..16 değer içermeli";
      return false;
     }
   for(int i=0; i<count; i++)
     {
      StringTrimLeft(tokens[i]);
      StringTrimRight(tokens[i]);
      double value = 0.0;
      if(field == OPT_TIMEFRAME)
        {
         ENUM_TIMEFRAMES timeframe;
         if(!ParseOptimizationTimeframe(tokens[i],timeframe))
           {
            error = "Geçersiz aday zaman dilimi: " + tokens[i];
            return false;
           }
         value = (double)timeframe;
        }
      else
        {
         bool digit = false;
         bool decimal = false;
         for(int j=0; j<StringLen(tokens[i]); j++)
           {
            ushort ch = StringGetCharacter(tokens[i],j);
            if(ch >= 48 && ch <= 57) digit = true;
            else if(ch == 46 && !decimal) decimal = true;
            else
              {
               error = "Geçersiz sayısal aday: " + tokens[i];
               return false;
              }
           }
         if(!digit)
           {
            error = "Boş/geçersiz sayısal aday";
            return false;
           }
         value = StringToDouble(tokens[i]);
        }
      if(!ValidOptimizationValue(field,value) || !AddOptimizationChoice(choices,value))
        {
         error = StringFormat("Aday sınır dışında veya bellek yetersiz (alan=%d)",field);
         return false;
        }
     }
   return true;
  }

bool BuildOptimizationChoices(const StrategySettings &current,OptimizationChoices &choices[],string &error)
  {
   if(ArrayResize(choices,OPT_FIELD_COUNT) < OPT_FIELD_COUNT)
      return false;
   StrategySettings manual = ManualStrategySettings();
   for(int field=0; field<OPT_FIELD_COUNT; field++)
     {
      ArrayResize(choices[field].values,0);
      if(!AddOptimizationChoice(choices[field],StrategyChoiceValue(current,field)) ||
         !AddOptimizationChoice(choices[field],StrategyChoiceValue(manual,field)))
         return false;
      string list = "";
      switch(field)
        {
         case OPT_TIMEFRAME: list = InpOptSignalTimeframes; break;
         case OPT_SIGNAL_HISTORY: list = InpOptSignalHistoryBars; break;
         case OPT_GRID_LOOKBACK: list = InpOptGridLookbackBars; break;
         case OPT_GRID_MULTIPLIER: list = InpOptGridMultipliers; break;
         case OPT_MIN_SPREAD: list = InpOptMinSpreadMultiples; break;
         case OPT_INITIAL_LEVELS: list = InpOptInitialGridLevels; break;
         case OPT_MAX_LEVELS: list = InpOptMaxGridLevels; break;
         case OPT_TP: list = InpOptTPGrids; break;
         case OPT_SL: list = InpOptSLGrids; break;
         case OPT_SPREAD_POINTS: list = InpOptMaxSpreadPoints; break;
         case OPT_SPREAD_FRACTION: list = InpOptMaxSpreadFractions; break;
         case OPT_EQUITY_TARGET: list = InpOptEquityTargets; break;
         default:
            if(InpOptSearchBooleans &&
               (!AddOptimizationChoice(choices[field],0.0) || !AddOptimizationChoice(choices[field],1.0)))
               return false;
            break;
        }
      if(list != "" && !ParseOptimizationList(list,field,choices[field],error))
         return false;
      if(list == "" && (field == OPT_TIMEFRAME || field == OPT_SIGNAL_HISTORY || field == OPT_GRID_LOOKBACK ||
                        field == OPT_GRID_MULTIPLIER || field == OPT_MIN_SPREAD || field == OPT_INITIAL_LEVELS ||
                        field == OPT_MAX_LEVELS || field == OPT_TP || field == OPT_SL || field == OPT_SPREAD_POINTS ||
                        field == OPT_SPREAD_FRACTION || field == OPT_EQUITY_TARGET))
        {
         error = "Sayısal/zaman dilimi aday listesi boş bırakılamaz";
         return false;
        }
     }
   return true;
  }

bool ValidateOptimizationInputs(string &error)
  {
   if(InpAutoOptimizeEveryMinutes < 1 || InpAutoOptimizeEveryMinutes > 1440 ||
      InpAutoOptimizeMaxCandidates < 64 || InpAutoOptimizeMaxCandidates > 512 ||
      InpAutoOptimizeMinClosedTrades < 1 || InpAutoOptimizeMinClosedTrades > 100000 ||
      InpAutoOptimizeSliceMs < 5 || InpAutoOptimizeSliceMs > 200 ||
      InpAutoOptimizeMaxSeconds < 1 || InpAutoOptimizeMaxSeconds > 3600 ||
      !MathIsValidNumber(InpAutoOptimizeMaxDrawdownPct) || InpAutoOptimizeMaxDrawdownPct < 0.0 || InpAutoOptimizeMaxDrawdownPct > 100.0 ||
      !MathIsValidNumber(InpAutoOptimizeDrawdownFloorPct) || InpAutoOptimizeDrawdownFloorPct < 0.0 || InpAutoOptimizeDrawdownFloorPct > 100.0 ||
      !MathIsValidNumber(InpAutoOptimizeMinImprovementPct) || InpAutoOptimizeMinImprovementPct < 0.0)
     {
      error = "Optimizasyon süre/adet/işlem/düşüş sınırlarını kontrol edin";
      return false;
     }
   StrategySettings manual = ManualStrategySettings();
   for(int field=0; field<OPT_FIELD_COUNT; field++)
      if(!ValidOptimizationValue(field,StrategyChoiceValue(manual,field)))
        {
         error = StringFormat("Manuel strateji değeri optimizasyon sınırları dışında (alan=%d)",field);
         return false;
        }
   OptimizationChoices choices[];
   return BuildOptimizationChoices(manual,choices,error);
  }

uint OptimizationHash(const int candidate,const int field)
  {
   uint value = (uint)candidate * 2654435761 + (uint)field * 2246822519 + 3266489917;
   value ^= value >> 16;
   value *= 2246822519;
   value ^= value >> 13;
   value *= 3266489917;
   return value ^ (value >> 16);
  }

datetime OptimizationSlot(const datetime now,const int minutes)
  {
   long seconds = (long)minutes * 60;
   if(seconds <= 0) return 0;
   return (datetime)(((long)now / seconds) * seconds);
  }

bool OptimizationScore(const double profit,const double drawdown,const int closed_trades,
                       const double initial_equity,double &score)
  {
   score = 0.0;
   if(!MathIsValidNumber(profit) || !MathIsValidNumber(drawdown) || profit <= 0.0 || drawdown < 0.0 ||
      !MathIsValidNumber(initial_equity) || initial_equity <= 0.0 || closed_trades < InpAutoOptimizeMinClosedTrades)
      return false;
   if(InpAutoOptimizeMaxDrawdownPct > 0.0 && drawdown / initial_equity * 100.0 > InpAutoOptimizeMaxDrawdownPct)
      return false;
   double floor = MathMax(0.01,initial_equity * InpAutoOptimizeDrawdownFloorPct / 100.0);
   score = profit / MathMax(drawdown,floor);
   return MathIsValidNumber(score);
  }

bool OptimizationImproves(const double score,const bool baseline_valid,const double baseline_score)
  {
   if(!baseline_valid) return true;
   double required = MathMax(1.0e-8,MathAbs(baseline_score) * InpAutoOptimizeMinImprovementPct / 100.0);
   return (score > baseline_score + required);
  }

string StrategySettingsSummary(const StrategySettings &p)
  {
   return StringFormat("TF=%s mum=%s geçmiş=%d reverse=%s renkKapat=%s; LB=%d çarpan=%.4f minSpread=%.2f seviye=%d/%d herGeçiş=%s; TP=%d SL=%d rotasyon=%s tekÇizgi=%s spreadPoint=%d spreadOran=%.3f hedef=%.2f dip=%s; base=%.*f adım=%.*f",
                       EnumToString(p.signal_timeframe),(p.candle_mode == SIGNAL_HEIKEN_ASHI ? "HA" : "normal"),
                       p.signal_history,(p.reverse ? "true" : "false"),(p.close_opposite ? "true" : "false"),
                       p.grid_lookback,p.grid_multiplier,p.min_spread_multiple,p.initial_levels,p.max_levels,
                       (p.enter_any_cross ? "true" : "false"),p.tp_grids,p.sl_grids,
                       (p.rotate_oldest ? "true" : "false"),(p.one_per_line ? "true" : "false"),
                       p.max_spread_points,p.max_spread_fraction,p.equity_target,(p.rebase_on_low ? "true" : "false"),
                       _Digits,p.grid_base,_Digits,p.grid_step);
  }

class CAutoSettingsOptimizer
  {
private:
   OptimizationChoices m_choices[];
   OptimizationHistory m_history[];
   StrategySettings m_candidates[];
   MqlTick m_ticks[];
   double m_grid_medians[];
   CAutoDirectionReplay m_replay;
   StrategySettings m_current;
   datetime m_slot;
   datetime m_window_end;
   datetime m_completed_slot;
   datetime m_attempt_slot;
   datetime m_retry_after;
   ulong m_started_ms;
   bool m_running;
   int m_candidate;
   int m_tick_index;
   int m_history_index;
   int m_rate_index;
   int m_signal_index;
   int m_signal_side;
   int m_previous_signal;
   int m_valid_ticks;
   MqlTick m_last_tick;
   double m_volume;
   double m_initial_equity;
   bool m_baseline_valid;
   double m_baseline_score;
   int m_best_index;
   double m_best_score;
   double m_best_profit;
   double m_best_drawdown;
   int m_best_closed;
   string m_status;
   string m_last_result;

   void ReleaseData()
     {
      m_replay.Clear();
      ArrayFree(m_ticks);
      ArrayFree(m_history);
      ArrayFree(m_choices);
      ArrayFree(m_grid_medians);
      ArrayFree(m_candidates);
     }

   int HistoryIndex(const ENUM_TIMEFRAMES timeframe)
     {
      for(int i=0; i<ArraySize(m_history); i++)
         if(m_history[i].timeframe == timeframe)
            return i;
      return -1;
     }

   bool AddHistory(const ENUM_TIMEFRAMES timeframe,const int warmup,string &error)
     {
      if(HistoryIndex(timeframe) >= 0) return true;
      if(Expired())
        {
         error = "Geçmiş yükleme süre bütçesi doldu";
         return false;
        }
      int n = ArraySize(m_history);
      if(ArrayResize(m_history,n + 1) < n + 1) return false;
      m_history[n].timeframe = timeframe;
      return LoadSignalRates(timeframe,warmup,m_window_end - 3600,m_window_end,m_history[n].rates,error);
     }

   bool AddCandidate(const StrategySettings &candidate,const bool keep_live_step)
     {
      // MQL5 requires structure parameters by reference. Size a local copy so
      // adding a candidate never changes the caller's settings or the incumbent.
      StrategySettings settings = candidate;
      if(!keep_live_step)
        {
         bool same_sizing = (settings.grid_lookback == m_current.grid_lookback &&
                             SameNumber(settings.grid_multiplier,m_current.grid_multiplier) &&
                             SameNumber(settings.min_spread_multiple,m_current.min_spread_multiple) &&
                             settings.tp_grids == m_current.tp_grids);
         if(!same_sizing)
           {
            int lookback_index = -1;
            for(int i=0; i<ArraySize(m_choices[OPT_GRID_LOOKBACK].values); i++)
               if((int)m_choices[OPT_GRID_LOOKBACK].values[i] == settings.grid_lookback) lookback_index = i;
            double floor,step;
            if(lookback_index < 0 || !GridStepFromMedian(settings,m_grid_medians[lookback_index],
                                                        MathMax(0.0,m_ticks[0].ask - m_ticks[0].bid),step,floor))
               return true; // Invalid candidate, not a partly evaluated winner.
            settings.grid_step = step;
           }
        }
      if(!ValidStrategySettings(settings) || settings.grid_step * settings.sl_grids >= MidPrice(m_ticks[0]) * 0.90)
         return true;
      for(int i=0; i<ArraySize(m_candidates); i++)
         if(SameStrategySettings(m_candidates[i],settings)) return true;
      int n = ArraySize(m_candidates);
      if(n >= InpAutoOptimizeMaxCandidates) return true;
      if(ArrayResize(m_candidates,n + 1,128) < n + 1) return false;
      m_candidates[n] = settings;
      return true;
     }

   bool BuildCandidates()
     {
      // Always score the incumbent first. Half the budget explores one-field
      // neighbors, the other half explores joint, deterministic mixed settings.
      if(!AddCandidate(m_current,true) || ArraySize(m_candidates) != 1) return false;
      StrategySettings manual = ManualStrategySettings();
      if(!AddCandidate(manual,false)) return false;
      int neighbor_limit = InpAutoOptimizeMaxCandidates / 2;
      for(int round=0; round<18 && ArraySize(m_candidates)<neighbor_limit; round++)
        {
         for(int field=0; field<OPT_FIELD_COUNT && ArraySize(m_candidates)<neighbor_limit; field++)
           {
            int alternative = 0;
            for(int i=0; i<ArraySize(m_choices[field].values); i++)
              {
               if(SameNumber(m_choices[field].values[i],StrategyChoiceValue(m_current,field))) continue;
               if(alternative++ != round) continue;
               StrategySettings settings = m_current;
               SetStrategyChoice(settings,field,m_choices[field].values[i]);
               if(!AddCandidate(settings,false)) return false;
               break;
              }
           }
        }
      for(int attempt=1; attempt<=InpAutoOptimizeMaxCandidates * 16 && ArraySize(m_candidates)<InpAutoOptimizeMaxCandidates; attempt++)
        {
         if((attempt % 32) == 0 && Expired()) return false;
         StrategySettings settings = m_current;
         for(int field=0; field<OPT_FIELD_COUNT; field++)
           {
            int size = ArraySize(m_choices[field].values);
            int index = (int)(OptimizationHash(attempt,field) % (uint)size);
            SetStrategyChoice(settings,field,m_choices[field].values[index]);
           }
         if(!AddCandidate(settings,false)) return false;
        }
      return true;
     }

   bool Start(const datetime slot,const datetime window_end,string &error)
     {
      ReleaseData();
      m_slot = slot;
      m_window_end = window_end;
      m_started_ms = GetTickCount64();
      m_current = LiveStrategySettings();
      m_current.grid_base = g_grid_base;
      m_current.grid_step = g_grid_step;
      m_volume = OrderVolume();
      m_initial_equity = AccountInfoDouble(ACCOUNT_EQUITY);
      if(m_initial_equity <= 0.0) m_initial_equity = AccountInfoDouble(ACCOUNT_BALANCE);
      if(m_volume <= 0.0 || !ValidStrategySettings(m_current) || m_initial_equity <= 0.0)
        {
         error = "Geçerli lot/sermaye/başlangıç stratejisi yok";
         return false;
        }
      if(!BuildOptimizationChoices(m_current,m_choices,error)) return false;
      int max_history = ClampedSignalHistory(m_current.signal_history);
      int max_lookback = m_current.grid_lookback;
      for(int i=0; i<ArraySize(m_choices[OPT_SIGNAL_HISTORY].values); i++)
         max_history = (int)MathMax(max_history,m_choices[OPT_SIGNAL_HISTORY].values[i]);
      for(int i=0; i<ArraySize(m_choices[OPT_GRID_LOOKBACK].values); i++)
         max_lookback = (int)MathMax(max_lookback,m_choices[OPT_GRID_LOOKBACK].values[i]);
      if(!AddHistory(PERIOD_M1,(int)MathMax(max_history,max_lookback + 1),error)) return false;
      for(int i=0; i<ArraySize(m_choices[OPT_TIMEFRAME].values); i++)
         if(!AddHistory((ENUM_TIMEFRAMES)(int)m_choices[OPT_TIMEFRAME].values[i],max_history,error)) return false;
      MqlRates unused_rates[];
      if(!LoadAutoDirectionHistory(window_end - 3600,window_end,m_ticks,unused_rates,error)) return false;
      // All candidates must start at the first usable executable quote.
      int first = 0;
      while(first < ArraySize(m_ticks) && !UsableReplayTick(m_ticks[first])) first++;
      if(first >= ArraySize(m_ticks) - 1)
        {
         error = "Yeterli geçerli tick yok";
         return false;
        }
      if(first > 0)
        {
         int size = ArraySize(m_ticks) - first;
         for(int i=0; i<size; i++) m_ticks[i] = m_ticks[i + first];
         ArrayResize(m_ticks,size);
        }
      int m1 = HistoryIndex(PERIOD_M1);
      int lookbacks = ArraySize(m_choices[OPT_GRID_LOOKBACK].values);
      if(ArrayResize(m_grid_medians,lookbacks) < lookbacks) return false;
      for(int i=0; i<lookbacks; i++)
         if(Expired() || !GridMedianBefore(m_history[m1].rates,window_end - 3600,
                                          (int)m_choices[OPT_GRID_LOOKBACK].values[i],m_grid_medians[i]))
           {
            error = "Grid ısınma verisi/süre bütçesi yetersiz";
            return false;
           }
      if(!BuildCandidates())
        {
         error = "Geçerli aday havuzu/bellek oluşturulamadı";
         return false;
        }
      m_candidate = 0;
      m_tick_index = 0;
      m_best_index = -1;
      m_best_score = 0.0;
      m_best_profit = 0.0;
      m_best_drawdown = 0.0;
      m_best_closed = 0;
      m_baseline_valid = false;
      m_baseline_score = 0.0;
      m_running = true;
      m_status = "Sanal strateji taraması çalışıyor";
      return true;
     }

   bool BeginCandidate()
     {
      m_history_index = HistoryIndex(m_candidates[m_candidate].signal_timeframe);
      if(m_history_index < 0) return false;
      m_rate_index = 0;
      m_signal_index = -1;
      m_signal_side = 0;
      m_previous_signal = 0;
      m_valid_ticks = 0;
      return m_replay.InitializeSettings(m_candidates[m_candidate],m_volume,MidPrice(m_ticks[0]),true);
     }

   bool ReplayOneTick()
     {
      MqlTick tick = m_ticks[m_tick_index++];
      if(!UsableReplayTick(tick)) return true;
      int size = ArraySize(m_history[m_history_index].rates);
      while(m_rate_index + 1 < size && m_history[m_history_index].rates[m_rate_index + 1].time <= tick.time)
         m_rate_index++;
      if(m_signal_index != m_rate_index)
        {
         m_signal_side = CandleSignalForSettings(m_history[m_history_index].rates,m_rate_index,m_candidates[m_candidate]);
         m_signal_index = m_rate_index;
        }
      if(m_signal_side == 0) return false;
      bool color_changed = (m_previous_signal != 0 && m_previous_signal != m_signal_side);
      if(!m_replay.ProcessTick(tick,m_signal_side,color_changed)) return false;
      m_previous_signal = m_signal_side;
      m_last_tick = tick;
      m_valid_ticks++;
      return true;
     }

   bool FinishCandidate()
     {
      double profit,drawdown,score;
      int closed,entries;
      if(m_valid_ticks < 2 || !m_replay.Metrics(m_last_tick,profit,drawdown,closed,entries)) return false;
      bool valid = OptimizationScore(profit,drawdown,closed,m_initial_equity,score);
      if(m_candidate == 0)
        {
         m_baseline_valid = valid;
         m_baseline_score = score;
        }
      if(valid && (m_best_index < 0 || score > m_best_score + 1.0e-8))
        {
         m_best_index = m_candidate;
         m_best_score = score;
         m_best_profit = profit;
         m_best_drawdown = drawdown;
         m_best_closed = closed;
        }
      m_candidate++;
      m_tick_index = 0;
      return true;
     }

   void FinishSearch()
     {
      m_running = false;
      m_completed_slot = m_slot;
      int tested = ArraySize(m_candidates);
      if(m_best_index < 0)
         m_status = "Uygun kârlı aday yok; mevcut ayarlar korundu";
      else if(m_best_index == 0 || !OptimizationImproves(m_best_score,m_baseline_valid,m_baseline_score))
         m_status = "Yeterli puan iyileşmesi yok; mevcut ayarlar korundu";
      else if(ApplyOptimizedStrategy(m_candidates[m_best_index]))
        {
         m_status = "Kazanan strateji uygulandı (lot/pozisyon limitleri sabit)";
         Print("Otomatik strateji seçimi: ",StrategySettingsSummary(m_candidates[m_best_index]));
        }
      else
         m_status = "Güvenli uygulama mümkün değil; mevcut ayarlar korundu";
      if(m_best_index < 0)
         m_last_result = StringFormat("[%s - %s) %d aday; uygun aday yok",
                                      TimeToString(m_window_end - 3600,TIME_DATE|TIME_MINUTES),
                                      TimeToString(m_window_end,TIME_DATE|TIME_MINUTES),tested);
      else
         m_last_result = StringFormat("[%s - %s) %d aday; en iyi puan=%.4f kâr=%.2f DD=%.2f (%d kapanış)",
                                   TimeToString(m_window_end - 3600,TIME_DATE|TIME_MINUTES),
                                   TimeToString(m_window_end,TIME_DATE|TIME_MINUTES),tested,
                                   m_best_score,m_best_profit,m_best_drawdown,m_best_closed);
      Print("Otomatik optimizasyon: ",m_status," | ",m_last_result);
      ReleaseData();
     }

   void Abort(const string reason)
     {
      m_running = false;
      m_completed_slot = m_slot;
      m_status = "Tarama iptal; ayarlar korundu: " + reason;
      Print("Otomatik optimizasyon: ",m_status);
      ReleaseData(); // A partial best is NEVER applied.
     }

   bool Expired()
     {
      return (IsStopped() || OptimizationSlot(TimeCurrent(),InpAutoOptimizeEveryMinutes) != m_slot ||
              GetTickCount64() - m_started_ms >= (ulong)InpAutoOptimizeMaxSeconds * 1000);
     }

   void Step()
     {
      ulong started = GetTickCount64();
      int work = 0;
      while(m_running && GetTickCount64() - started < (ulong)InpAutoOptimizeSliceMs)
        {
         if((work++ % 64) == 0 && Expired())
           {
            Abort("süre sınırı/yeni test aralığı/durdurma");
            return;
           }
         if(m_tick_index == 0 && !BeginCandidate())
           {
            Abort("aday başlatılamadı");
            return;
           }
         if(!ReplayOneTick())
           {
            Abort("sinyal veya kâr hesabı başarısız");
            return;
           }
         if(m_tick_index >= ArraySize(m_ticks))
           {
            if(!FinishCandidate())
              {
               Abort("aday sonucu hesaplanamadı");
               return;
              }
            if(m_candidate >= ArraySize(m_candidates))
              {
               if(Expired()) Abort("tamamlama anında test süresi doldu");
               else FinishSearch();
               return;
              }
           }
        }
     }

public:
   void Reset()
     {
      ReleaseData();
      m_running = false;
      m_slot = 0;
      m_completed_slot = 0;
      m_attempt_slot = 0;
      m_retry_after = 0;
      m_candidate = 0;
      m_status = "İlk strateji testi bekleniyor";
      m_last_result = "";
     }

   void Refresh(const bool force=false)
     {
      if(!InpAutoOptimizeSettings) return;
      if(m_running)
        {
         Step();
         return;
        }
      datetime now = TimeCurrent();
      datetime slot = OptimizationSlot(now,InpAutoOptimizeEveryMinutes);
      if(now < 3600 || (!force && m_completed_slot == slot)) return;
      bool first_attempt = (m_attempt_slot != slot);
      if(!force && !first_attempt && now < m_retry_after) return;
      m_attempt_slot = slot;
      m_retry_after = now + 10;
      string error = "";
      if(!Start(slot,OptimizationSlot(now,1),error))
        {
         if(Expired())
           {
            Abort("hazırlık süresi/yeni test aralığı/durdurma");
            return;
           }
         m_running = false;
         m_status = "Veri/aday bekleniyor; ayarlar korundu: " + error;
         if(first_attempt || force) Print("Otomatik optimizasyon: ",m_status);
         ReleaseData();
        }
     }

   bool Running() { return m_running; }
   string Status()
     {
      if(m_running)
         return StringFormat("%s (%d/%d aday, tick %d/%d)",m_status,m_candidate,ArraySize(m_candidates),m_tick_index,ArraySize(m_ticks));
      return m_status;
     }
   string LastResult() { return m_last_result; }
  };

CAutoSettingsOptimizer g_settings_optimizer;

//+------------------------------------------------------------------+
//| Status and standard MT5 events                                   |
//+------------------------------------------------------------------+
void UpdateChartStatus()
  {
   StrategySettings settings = LiveStrategySettings();
   if(!InpShowChartStatus)
     {
      Comment("");
      return;
     }

   MqlTick tick;
   double current_price = 0.0;
   if(SymbolInfoTick(_Symbol,tick))
      current_price = MidPrice(tick);
   int long_count = CountOurPositions(1);
   int short_count = CountOurPositions(-1);
   double step_points = (g_grid_step > 0.0 ? g_grid_step / _Point : 0.0);
   double step_pips = (g_grid_step > 0.0 ? g_grid_step / PipSize() : 0.0);
   string signal_type = (settings.candle_mode == SIGNAL_HEIKEN_ASHI ? "HA" : "normal");
   string target_status = "Özsermaye hedefi: kapalı";
   if(CycleEquityTarget() > 0.0)
     {
      double equity_gain = AccountInfoDouble(ACCOUNT_EQUITY) - g_profit_target_start_equity;
      string rebound_text = "";
      if(CycleRebaseOnLow())
         rebound_text = " | dip takibi açık";
      target_status = StringFormat("Özsermaye hedefi: %.2f / %.2f %s | taban %.2f%s%s",
                                   equity_gain,CycleEquityTarget(),
                                   AccountInfoString(ACCOUNT_CURRENCY),
                                   g_profit_target_start_equity,
                                   rebound_text,
                                   (g_profit_target_liquidating ? " (pozisyonlar kapatılıyor)" : ""));
     }

   string direction_status = "Otomatik yön: kapalı (manuel seçim)";
   if(InpAutoOptimizeSettings)
      direction_status = "Yön tam strateji optimizasyonuna bağlı (ayrı yön otomasyonu askıda)";
   else if(InpAutoReverseTradeDirection)
     {
      direction_status = "Otomatik yön: açık | seçim=" +
                         (EffectiveReverseTradeDirection() ? "true (ters)" : "false (normal)") +
                         " | " + g_auto_direction_status;
      if(g_auto_direction_window_end > 0)
         direction_status += StringFormat("\nSon 60 dk [%s - %s): false=%.2f (%d giriş) | true=%.2f (%d giriş) %s",
                                           TimeToString(g_auto_direction_window_end - 3600,TIME_MINUTES),
                                           TimeToString(g_auto_direction_window_end,TIME_MINUTES),
                                           g_auto_direction_normal_profit,g_auto_direction_normal_entries,
                                           g_auto_direction_reverse_profit,g_auto_direction_reverse_entries,
                                           AccountInfoString(ACCOUNT_CURRENCY));
     }

   string optimization_status = "Strateji optimizasyonu: kapalı";
   if(InpAutoOptimizeSettings)
     {
      optimization_status = StringFormat("Strateji optimizasyonu: açık | her %d dk | %s\n%s\nEtkin: %s",
                                          InpAutoOptimizeEveryMinutes,g_settings_optimizer.Status(),
                                          g_settings_optimizer.LastResult(),StrategySettingsSummary(settings));
      if(!SameNumber(CycleEquityTarget(),settings.equity_target) || CycleRebaseOnLow() != settings.rebase_on_low)
         optimization_status += "\nYeni özsermaye hedefi/dip modu mevcut pozisyon döngüsü bitince etkinleşecek";
     }

   string rotation_status = (settings.rotate_oldest ? "açık (en eski pozisyon yenilenir)" : "kapalı (sınırda giriş atlanır)");
   Comment("M1 Auto Grid HA v1.08\n",
           "Sembol: ",_Symbol," | Mum yönü: ",signal_type," ",EnumToString(settings.signal_timeframe)," ",SideName(g_signal_side),"\n",
           "İşlem yönü: ",SideName(TradeSideForSignal(g_signal_side)),
           (EffectiveReverseTradeDirection() ? " (ters yön açık)" : ""),"\n",
           direction_status,"\n",
           optimization_status,"\n",
           "Grid base: ",DoubleToString(g_grid_base,_Digits)," | anlık: ",DoubleToString(current_price,_Digits),"\n",
           "Sabit adım: ",DoubleToString(g_grid_step,_Digits)," (",DoubleToString(step_points,1)," point / ",
           DoubleToString(step_pips,2)," pip) | TP ",
           IntegerToString(settings.tp_grids)," grid / SL ",IntegerToString(settings.sl_grids)," grid\n",
           "Pozisyon LONG/SHORT: ",IntegerToString(long_count)," / ",IntegerToString(short_count),
           " | Sınır/yan: ",IntegerToString(InpMaxLayersPerSide),
           " | Toplam sınır: ",IntegerToString(InpMaxTotalPositions),"\n",
           "Sınır rotasyonu: ",rotation_status,"\n",
           target_status,"\n",
           "Durum: ",g_last_action);
  }

double OnTester()
  {
   StrategySettings settings = LiveStrategySettings();
   double profit = TesterStatistics(STAT_PROFIT);
   double equity_drawdown = TesterStatistics(STAT_EQUITY_DD);
   double initial_deposit = TesterStatistics(STAT_INITIAL_DEPOSIT);
   double trades = TesterStatistics(STAT_TRADES);
   double fitness = profit;

   if(InpUseRiskAdjustedTesterScore)
     {
      if(InpOptimizationMinTrades > 0 && trades < InpOptimizationMinTrades)
         fitness = -1000000.0 + trades; // Reject small samples so a few lucky trades do not win.
      else
        {
         double drawdown_floor = MathMax(initial_deposit * 0.005,0.01);
         fitness = profit / MathMax(equity_drawdown,drawdown_floor);
        }
     }

   // In optimization mode, use the Optimization Results table to rank passes.
   // Print one detailed line for a single backtest run (not once per optimizer pass).
   if(!MQLInfoInteger(MQL_OPTIMIZATION))
      PrintFormat("Tester fitness=%.6f netProfit=%.2f equityDD=%.2f trades=%.0f; gridMultiplier=%.2f TP=%d SL=%d reverse=%s autoReverse=%s",
                  fitness,profit,equity_drawdown,trades,settings.grid_multiplier,
                  settings.tp_grids,settings.sl_grids,
                  (EffectiveReverseTradeDirection() ? "true" : "false"),
                  (InpAutoReverseTradeDirection ? "true" : "false"));
   return fitness;
  }

int OnInit()
  {
   g_optimizer_settings_active = false;
   g_cycle_settings_initialized = false;
   g_signal_side = 0;
   g_last_signal_bar_time = 0;
   ArrayFree(g_saved_grid_positions);
   g_settings_optimizer.Reset();
   if(InpGridRangeLookbackBars < 5 || InpGridStepMultiplier <= 0.0 ||
      InpMinSpreadMultiple < 0.0 || InpInitialGridLevels < 1 ||
      InpMaxGridLevels < InpInitialGridLevels || InpTakeProfitGrids < 1 ||
      InpStopLossGrids < 1 || InpMaxLayersPerSide < 0 ||
      InpMaxTotalPositions < 0 || InpMaxSpreadPoints < 0 || InpMaxSpreadGridFraction < 0.0 || InpSignalHistoryBars < 2 ||
      InpDeviationPoints < 0 || InpOptimizationMinTrades < 0 || InpCloseAllAtEquityGain < 0.0 ||
      InpAutoDirectionCommissionPerLot < 0.0 || !MathIsValidNumber(InpAutoDirectionCommissionPerLot))
     {
      Print("Hatalı girdiler: grid/mum/TP/SL, sınır ve test komisyonu ayarlarını kontrol edin.");
      return INIT_PARAMETERS_INCORRECT;
     }

   string optimization_error = "";
   if(InpAutoOptimizeSettings && !ValidateOptimizationInputs(optimization_error))
     {
      Print("Geçersiz otomatik optimizasyon ayarı: ",optimization_error);
      return INIT_PARAMETERS_INCORRECT;
     }

   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      Print("EA başlatılamadı: ayrı katman TP/SL ve aynı anda LONG+SHORT için hedging hesap gerekir.");
      return INIT_FAILED;
     }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetAsyncMode(false);
   trade.SetTypeFillingBySymbol(_Symbol);

   string object_tag = StringFormat("M1AG_%I64u_%I64u_%s_",InpMagicNumber,(ulong)HashSymbol(_Symbol),RunModeTag());
   g_grid_object_prefix = object_tag;
   if(InpResetGridOnInit)
      DeleteOwnGridObjects();

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
     {
      Print("EA başlatılamadı: sembol için fiyat tiki alınamıyor.");
      return INIT_FAILED;
     }
   double startup_price = MidPrice(tick);
   if(startup_price <= 0.0)
     {
      Print("EA başlatılamadı: geçersiz başlangıç fiyatı.");
      return INIT_FAILED;
     }

   if(!LoadOrCreateGrid(startup_price))
      return INIT_FAILED;
   if(!InitializeGridState(startup_price))
     {
      Print("Grid hafızası oluşturulamadı.");
      return INIT_FAILED;
     }

   g_active_reverse_trade_direction = InpReverseTradeDirection;
   g_auto_direction_window_end = 0;
   g_auto_direction_attempt_minute = 0;
   g_auto_direction_retry_after = 0;
   g_auto_direction_normal_profit = 0.0;
   g_auto_direction_reverse_profit = 0.0;
   g_auto_direction_normal_entries = 0;
   g_auto_direction_reverse_entries = 0;
   g_auto_direction_status = "İlk test bekleniyor";
   LoadProfitTargetState();
   RefreshTradingDirection(true);
   bool timer_ok = (InpAutoOptimizeSettings ? EventSetMillisecondTimer(100) : EventSetTimer(1));
   if(!timer_ok)
     {
      Print("EA başlatılamadı: zamanlayıcı kurulamadı.");
      return INIT_FAILED;
     }

   PrintFormat("EA hazır: %s base=%.*f step=%.*f signal=%s %s trade=%s; TP=%d SL=%d hedging",
               _Symbol,_Digits,g_grid_base,_Digits,g_grid_step,
               (InpSignalCandleMode == SIGNAL_HEIKEN_ASHI ? "Heiken Ashi" : "normal mum"),
               SideName(g_signal_side),SideName(TradeSideForSignal(g_signal_side)),
               InpTakeProfitGrids,InpStopLossGrids);
   Print("Grid koordinatları ve hesaplanan adım sabit kalır. Çizgi rengi mum yönünü gösterir; etkin ters yön seçimi işlem yönünü tersine çevirir.");
   if(InpAutoOptimizeSettings)
      PrintFormat("Otomatik strateji optimizasyonu etkin: her %d dk son kapanmış 60 dk; en fazla %d aday, kâr/düşüş puanı, en az %d kapanış. Lot ve pozisyon sınırları sabit; ayrı yön otomasyonu askıda.",
                  InpAutoOptimizeEveryMinutes,InpAutoOptimizeMaxCandidates,InpAutoOptimizeMinClosedTrades);
   else if(InpAutoReverseTradeDirection)
      PrintFormat("Otomatik yön etkin: her sunucu dakikasında son kapanmış 60 dk tick testi; başlangıç/yedek reverse=%s, 1 lot toplam komisyon=%.2f %s. Yön değişimi yalnız yeni girişlere uygulanır.",
                  (InpReverseTradeDirection ? "true" : "false"),InpAutoDirectionCommissionPerLot,
                  AccountInfoString(ACCOUNT_CURRENCY));
   if(InpRotateOldestAtLimit)
      PrintFormat("Pozisyon sınırı rotasyonu etkin: yan sınırı=%d toplam sınırı=%d. Sınır dolduğunda aynı yöndeki en eski pozisyon kapatılıp yeni seviyeden taze giriş açılacak.",
                  InpMaxLayersPerSide,InpMaxTotalPositions);
   else
      Print("Pozisyon sınırı rotasyonu kapalı: sınır dolduğunda yeni giriş atlanır.");
   if(InpCloseAllAtEquityGain > 0.0)
      PrintFormat("Özsermaye kâr hedefi etkin: başlangıç=%.2f hedef=%.2f %s",
                  g_profit_target_start_equity,InpCloseAllAtEquityGain,
                  AccountInfoString(ACCOUNT_CURRENCY));
   if(InpEquityTargetRebaseOnLow)
      Print("Dip takibi etkin: her yeni özsermaye dibinde hedef tabanı dibe çekilir; dipten hedef tutarı kadar yükselişte tüm pozisyonlar kapanıp döngü sıfırdan başlar.");
   UpdateChartStatus();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   g_settings_optimizer.Reset();
   ArrayFree(g_saved_grid_positions);
   DeleteOwnGridObjects();
   Comment("");
  }

void OnTimer()
  {
   RefreshTradingDirection(false);
   HandleEquityProfitTarget();
   g_settings_optimizer.Refresh(false);
   UpdateChartStatus();
   // Touch saved grid globals while the EA is active so MT5 keeps them current.
   if(g_grid_base > 0.0 && g_grid_step > 0.0)
     {
      GlobalVariableSet(GridStateKey("BASE"),g_grid_base);
      GlobalVariableSet(GridStateKey("STEP"),g_grid_step);
      if(!MQLInfoInteger(MQL_TESTER) && g_profit_target_start_equity > 0.0)
        {
         GlobalVariableSet(GridStateKey("PTBASE"),g_profit_target_start_equity);
         GlobalVariableSet(GridStateKey("PTAMT"),CycleEquityTarget());
         GlobalVariableSet(GridStateKey("PTLIQ"),(g_profit_target_liquidating ? 1.0 : 0.0));
         GlobalVariableSet(GridStateKey("PTLOW"),(CycleRebaseOnLow() ? 1.0 : 0.0));
        }
      datetime now = TimeCurrent();
      if(g_last_state_flush == 0 || now - g_last_state_flush >= 30)
        {
         GlobalVariablesFlush();
         g_last_state_flush = now;
        }
     }
  }

void OnTick()
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick) || tick.bid <= 0.0 || tick.ask <= 0.0)
      return;

   RefreshTradingDirection(false);
   // Tick-history synchronization/replay can take time; never trade on the stale
   // quote captured before the test. Broker-side protection remains in place.
   if(!SymbolInfoTick(_Symbol,tick) || tick.bid <= 0.0 || tick.ask <= 0.0)
      return;
   if(HandleEquityProfitTarget())
     {
      UpdateChartStatus();
      return;
     }
   ManageOpenPositions(tick);
   double grid_price = MidPrice(tick);
   if(grid_price > 0.0)
      ProcessGridCrosses(grid_price);
   UpdateChartStatus();
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL) != _Symbol ||
      (ulong)HistoryDealGetInteger(trans.deal,DEAL_MAGIC) != InpMagicNumber)
      return;

   long entry_kind = HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   if(entry_kind != DEAL_ENTRY_OUT && entry_kind != DEAL_ENTRY_OUT_BY && entry_kind != DEAL_ENTRY_INOUT)
      return;

   ulong identifier = (ulong)HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID);
   bool still_open = false;
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket) &&
         (ulong)PositionGetInteger(POSITION_IDENTIFIER) == identifier)
        {
         still_open = true;
         break;
        }
     }
   if(!still_open && identifier > 0)
      DeletePositionSettings(identifier);
  }

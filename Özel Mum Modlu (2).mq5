#property strict
#property version   "1.05"
#property description "Adaptive HA grid with an isolated candle-count trading mode"

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
input bool                  InpReverseTradeDirection    = false;  // true: yeşil sinyalde SHORT, kırmızı sinyalde LONG aç

input group "Özel mum modu (açıksa grid ayarları devre dışı)"
input bool                  InpEnableCandleMode                = false;          // Mum modunu tek başına çalıştır
input ENUM_TIMEFRAMES       InpCandleModeTimeframe              = PERIOD_M1;
input ENUM_SIGNAL_CANDLE_MODE InpCandleModeCandleType           = SIGNAL_STANDARD_CANDLE;
input int                   InpCandleModeHACalculationBars      = 300;            // Heiken Ashi hesabı için geçmiş mum
input bool                  InpCandleModeReverseDirection      = false;          // true: yeşil mumda SELL, kırmızı mumda BUY
input int                   InpCandleModeTakeProfitCandles      = 3;              // BUY: girişten sonra 3 yeşil; SELL: 3 kırmızı, birikimli (ardışık değil)
input int                   InpCandleModeStopLossCandles        = 10;             // BUY: girişten sonra 10 kırmızı; SELL: 10 yeşil, birikimli
input double                InpCandleModeFixedLots              = 0.01;
input bool                  InpCandleModeUseBrokerMinimumVolume = false;
input int                   InpCandleModeMaxPositionsPerSide    = 0;              // 0 = sınırsız; her renkli kapanışta giriş için
input int                   InpCandleModeMaxTotalPositions      = 0;              // 0 = sınırsız; risk için istenirse sınır koy
input ulong                 InpCandleModeMagicNumber            = 20261009;       // Grid'den ayrı; açıkken değiştirmeyin
input int                   InpCandleModeDeviationPoints        = 20;
input bool                  InpCandleModeEnableTradingHours     = true;
input int                   InpCandleModeStartHour              = 8;
input int                   InpCandleModeStartMinute            = 0;
input int                   InpCandleModeEndHour                = 19;
input int                   InpCandleModeEndMinute              = 0;              // Bitiş saati hariçtir
input int                   InpCandleModeTesterUtcOffsetWinterHours = 2;          // Tipik EET broker kış UTC+2
input int                   InpCandleModeTesterUtcOffsetSummerHours = 3;          // Tipik EET broker yaz UTC+3
input bool                  InpCandleModeTesterUsesEuropeanDST  = true;
input bool                  InpCandleModeShowChartStatus        = true;

input group "İşlem saatleri (Türkiye saati)"
input bool                  InpEnableTradingHours        = true;
input int                   InpTradingStartHour          = 8;
input int                   InpTradingStartMinute        = 0;
input int                   InpTradingEndHour            = 19;
input int                   InpTradingEndMinute          = 0;     // Bitiş saati hariçtir; 19:00'da işlemler kapatılır

input group "Backtest Türkiye saati dönüşümü"
input int                   InpTesterServerUtcOffsetWinterHours = 2; // Tipik MT5 EET broker sunucusu: kışın UTC+2
input int                   InpTesterServerUtcOffsetSummerHours = 3; // Tipik MT5 EET broker sunucusu: yazın UTC+3
input bool                  InpTesterServerUsesEuropeanDST = true; // Broker farklıysa offsetleri/DST seçeneğini ayarlayın

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

input group "Grid çizgisi yorgunluğu ve kinetik filtre"
input bool                  InpEnableGridFatigue         = true;
input double                InpGridHeatPerCross           = 20.0;  // Her çizgi geçişinde eklenen ısı (0..100)
input double                InpGridHeatDecayPerM1         = 10.0;  // Her yeni M1 mumunda mevcut ısının azalan yüzdesi
input double                InpGridHeatReverseThreshold   = 50.0;  // Bu ısıda çizgi yerel ters-yön moduna geçer
input double                InpGridHeatToxicThreshold     = 100.0; // SL çizgiyi zehirler; soğuyana kadar giriş kapalı
input int                   InpFastTPMaxSeconds           = 60;    // Bu süreden hızlı TP çizgiyi verimli/soğuk yapar

input group "Çok katmanlı epoch ve bükülmüş grid"
input int                   InpGridEpochMinutes           = 15;
input double                InpGridEpochDeviation         = 0.50;  // Yeni medyan adımda gerekli göreli fark
input double                InpGridSpacingExponent        = 1.15;  // Merkezden uzaklaştıkça grid aralığını açar

input group "Sembiyotik pozisyon katmanlama"
input bool                  InpEnableSymbioticLayering    = true;
input double                InpSymbioticProfitGrids       = 1.50;  // Yeni pozisyon kârı bu grid'e ulaşınca çift çözülür
input double                InpSymbioticMaxCloseFraction  = 0.50;  // Eski zararlı pozisyonun en fazla bu kısmı kapatılır

input group "Pozisyon ve lot sınırları"
input bool                  InpUseBrokerMinimumVolume   = false;  // true ise otomatik broker minimum hacmi
input double                InpFixedLots                = 0.01;   // Varsayılan; minimum lotun altındaysa işlem atlanır
input int                   InpMaxLayersPerSide         = 5;      // 0 = sınırsız
input int                   InpMaxTotalPositions        = 10;     // Bu sembol + Magic; 0 = sınırsız
input bool                  InpOnePositionPerGridLine   = true;
input int                   InpMaxSpreadPoints          = 0;      // 0 = point bazlı ek filtre kapalı
input double                InpMaxSpreadGridFraction    = 0.50;   // Spread > grid adımının bu oranıysa yeni giriş yok

input group "İşlem"
input ulong                 InpMagicNumber              = 20261008;
input int                   InpDeviationPoints           = 20;
input bool                  InpShowChartStatus           = true;

input group "Özsermaye kâr hedefi"
input double                InpCloseAllAtEquityGain       = 0.0;   // 0 = kapalı; pozitif tutar hesap para biriminde

input group "Strateji Sınayıcı optimizasyonu"
input bool                  InpUseRiskAdjustedTesterScore = true; // true: Custom max için kâr / özsermaye düşüşü
input int                   InpOptimizationMinTrades      = 30;   // Risk ayarlı puanda minimum işlem; 0 = filtre yok
input double                InpTesterStressPenaltyStrength = 1.0; // Uzun açık kalma/zarar süresinin puan cezası

// Grid lines keep their own prices across epoch changes while a position uses them.
double g_grid_base = 0.0;
double g_grid_step = 0.0;
int    g_up_count = 0;
int    g_down_count = 0;
int    g_up_state[];       // -1 = below; +1 = above; 0 = not armed; 2 = ballistic spring armed
int    g_down_state[];
int    g_up_spring_side[]; // Side reached on the first ballistic crossing while in reverse mode
int    g_down_spring_side[];
double g_up_heat[];
double g_down_heat[];
int    g_up_poisoned[];
int    g_down_poisoned[];
int    g_up_fast_tp[];
int    g_down_fast_tp[];
double g_up_price[];
double g_down_price[];

struct PositionRuntimeSettings
  {
   ulong identifier;
   int line_code;
   double grid_step;
   int tp_grids;
   int sl_grids;
   long open_time_msc;
  };
PositionRuntimeSettings g_position_settings[];

struct PendingGridSettings
  {
   int side;
   int line_code;
   string comment;
   double grid_step;
   int tp_grids;
   int sl_grids;
   long request_time_msc;
  };
PendingGridSettings g_pending_settings[];

int      g_signal_side = 0; // +1 LONG, -1 SHORT, 0 no valid closed-bar signal
double   g_signal_score = 1.0; // 0..1 Heiken Ashi/candle morphology score
double   g_profit_target_start_equity = 0.0;
bool     g_profit_target_liquidating = false;
datetime g_last_signal_bar_time = 0;
datetime g_last_heat_bar_time = 0;
datetime g_last_epoch_recalculation = 0;
datetime g_last_state_flush = 0;
datetime g_last_hours_close_attempt = 0;
bool     g_was_outside_trading_hours = false;
bool     g_reseed_crosses_on_next_tick = false;
datetime g_candle_mode_last_processed_bar = 0;
datetime g_candle_mode_last_close_attempt = 0;
bool     g_candle_mode_was_outside_hours = false;
string   g_candle_mode_last_action = "Mum modu başlatılıyor";
string   g_last_action = "Başlatılıyor";
string   g_grid_object_prefix = "";

long   g_tick_time_history[5];
double g_tick_price_history[5];
int    g_tick_history_count = 0;
long   g_last_tick_time_msc = 0;
double g_last_tick_price = 0.0;

// Tester-only stress statistics (all values are accumulated in seconds/seconds^2).
double g_underwater_seconds_squared = 0.0;
double g_underwater_episode_seconds = 0.0;
long   g_last_stress_time_msc = 0;
double g_position_lifetime_seconds_squared = 0.0;

// Weighted TP-price POC for the current equity-target cycle.
double g_tp_price_volume_sum = 0.0;
double g_tp_volume_sum = 0.0;

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

bool GlobalReverseModeActive()
  {
   // A fatigued HA candle requests mean reversion even when the input switch is off.
   return (InpReverseTradeDirection || g_signal_score < 0.3);
  }

int TradeSideForSignal(const int signal_side)
  {
   if(signal_side == 0)
      return 0;
   return (GlobalReverseModeActive() ? -signal_side : signal_side);
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

int ComparePriceToLevel(const double price,const double level)
  {
   double eps = CrossTolerance();
   if(price > level + eps)
      return 1;
   if(price < level - eps)
      return -1;
   return 0;
  }

int LastSundayOfMonth(const int year,const int month)
  {
   for(int day=31; day>=28; day--)
     {
      MqlDateTime date;
      date.year = year;
      date.mon = month;
      date.day = day;
      date.hour = 12;
      date.min = 0;
      date.sec = 0;
      date.day_of_week = 0;
      date.day_of_year = 0;
      datetime date_time = StructToTime(date);
      MqlDateTime normalized;
      if(date_time > 0 && TimeToStruct(date_time,normalized) &&
         normalized.mon == month && normalized.day == day && normalized.day_of_week == 0)
         return day;
     }
   return 31;
  }

int TesterServerUtcOffsetHours(const datetime server_time,const int winter_offset,
                               const int summer_offset,const bool uses_european_dst)
  {
   if(!uses_european_dst)
      return winter_offset;

   MqlDateTime date;
   if(server_time <= 0 || !TimeToStruct(server_time,date))
      return winter_offset;
   int march_last_sunday = LastSundayOfMonth(date.year,3);
   int october_last_sunday = LastSundayOfMonth(date.year,10);
   bool summer_time = false;
   if(date.mon > 3 && date.mon < 10)
      summer_time = true;
   else if(date.mon == 3)
      summer_time = (date.day > march_last_sunday ||
                     (date.day == march_last_sunday && date.hour >= 3));
   else if(date.mon == 10)
      summer_time = (date.day < october_last_sunday ||
                     (date.day == october_last_sunday && date.hour < 4));
   return (summer_time ? summer_offset : winter_offset);
  }

datetime CurrentTurkeyTimeForOffsets(const int winter_offset,const int summer_offset,
                                     const bool uses_european_dst)
  {
   datetime utc_time = 0;
   if(MQLInfoInteger(MQL_TESTER))
     {
      datetime server_time = TimeCurrent();
      int server_utc_offset = TesterServerUtcOffsetHours(server_time,winter_offset,
                                                         summer_offset,uses_european_dst);
      utc_time = (datetime)((long)server_time - (long)server_utc_offset * 3600);
     }
   else
      utc_time = TimeGMT();

   if(utc_time <= 0)
      return 0;
   return utc_time + 3 * 3600; // Turkey is UTC+3 year-round.
  }

datetime CurrentTurkeyTime()
  {
   return CurrentTurkeyTimeForOffsets(InpTesterServerUtcOffsetWinterHours,
                                      InpTesterServerUtcOffsetSummerHours,
                                      InpTesterServerUsesEuropeanDST);
  }

datetime CurrentCandleModeTurkeyTime()
  {
   return CurrentTurkeyTimeForOffsets(InpCandleModeTesterUtcOffsetWinterHours,
                                      InpCandleModeTesterUtcOffsetSummerHours,
                                      InpCandleModeTesterUsesEuropeanDST);
  }

bool IsWithinTurkeyHours(const datetime turkey_time,const int start_hour,const int start_minute,
                         const int end_hour,const int end_minute)
  {
   if(turkey_time <= 0)
      return false;
   MqlDateTime date;
   if(!TimeToStruct(turkey_time,date))
      return false;
   int current_minute = date.hour * 60 + date.min;
   int start = start_hour * 60 + start_minute;
   int end = end_hour * 60 + end_minute;
   if(start == end)
      return true; // Equal endpoints explicitly mean a 24-hour window.
   if(start < end)
      return (current_minute >= start && current_minute < end);
   return (current_minute >= start || current_minute < end); // Overnight window.
  }

bool IsWithinTradingHours(const datetime turkey_time)
  {
   return IsWithinTurkeyHours(turkey_time,InpTradingStartHour,InpTradingStartMinute,
                              InpTradingEndHour,InpTradingEndMinute);
  }

bool IsWithinCandleModeTradingHours(const datetime turkey_time)
  {
   return IsWithinTurkeyHours(turkey_time,InpCandleModeStartHour,InpCandleModeStartMinute,
                              InpCandleModeEndHour,InpCandleModeEndMinute);
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

void SaveProfitTargetState()
  {
   if(MQLInfoInteger(MQL_TESTER))
      return; // Each tester pass starts from its own initial deposit/equity.
   GlobalVariableSet(GridStateKey("PTBASE"),g_profit_target_start_equity);
   GlobalVariableSet(GridStateKey("PTAMT"),InpCloseAllAtEquityGain);
   GlobalVariableSet(GridStateKey("PTLIQ"),(g_profit_target_liquidating ? 1.0 : 0.0));
   GlobalVariablesFlush();
  }

void LoadProfitTargetState()
  {
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
   bool state_exists = (GlobalVariableCheck(base_key) &&
                        GlobalVariableCheck(amount_key) &&
                        GlobalVariableCheck(liquidating_key));
   if(state_exists)
     {
      double saved_amount = GlobalVariableGet(amount_key);
      double amount_tolerance = MathMax(1.0e-8,MathAbs(InpCloseAllAtEquityGain) * 1.0e-8);
      if(GlobalVariableGet(base_key) > 0.0 &&
         MathAbs(saved_amount - InpCloseAllAtEquityGain) <= amount_tolerance)
        {
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

string GridLineStateKey(const bool is_up,const int index,const string field)
  {
   return GridStateKey((is_up ? "U" : "D") + IntegerToString(index) + "_" + field);
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
//| M1 volatility sizing for initial grid and later epochs            |
//+------------------------------------------------------------------+
bool CalculateInitialGridStep(double &step_out,double &median_range_out,double &floor_out)
  {
   step_out = 0.0;
   median_range_out = 0.0;
   floor_out = 0.0;

   int lookback = InpGridRangeLookbackBars;
   if(lookback < 1)
      return false;

   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   int copied = CopyRates(_Symbol,PERIOD_M1,0,lookback + 1,rates);
   if(copied < lookback + 1)
      return false; // Need the requested number of completed candles plus the live one.

   double ranges[];
   if(ArrayResize(ranges,lookback) < lookback)
      return false;
   for(int i=0; i<lookback; i++)
     {
      int shift = i + 1; // shift 0 is the forming candle; do not use it.
      ranges[i] = MathMax(0.0,rates[shift].high - rates[shift].low);
     }

   // Insertion sort; the default sample is small (20 bars).
   for(int i=1; i<lookback; i++)
     {
      double value = ranges[i];
      int j = i - 1;
      while(j >= 0 && ranges[j] > value)
        {
         ranges[j + 1] = ranges[j];
         j--;
        }
      ranges[j + 1] = value;
     }

   if((lookback % 2) == 1)
      median_range_out = ranges[lookback / 2];
   else
      median_range_out = (ranges[lookback / 2 - 1] + ranges[lookback / 2]) * 0.5;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return false;
   double spread = MathMax(0.0,tick.ask - tick.bid);
   double raw_step = median_range_out * InpGridStepMultiplier;

   double min_step = TickSize();
   if(spread > 0.0 && InpMinSpreadMultiple > 0.0)
      min_step = MathMax(min_step,spread * InpMinSpreadMultiple);

   long stop_level = (long)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freeze_level = (long)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   long broker_distance_points = stop_level;
   if(freeze_level > broker_distance_points)
      broker_distance_points = freeze_level;
   if(broker_distance_points > 0)
     {
      // HA fatigue can select a one-grid TP, so size the grid against the smallest
      // runtime target rather than only the configured default TP.
      int smallest_runtime_tp = 1;
      double tp_min_step = ((double)broker_distance_points * _Point + TickSize()) /
                           (double)smallest_runtime_tp;
      min_step = MathMax(min_step,tp_min_step);
     }

   step_out = MathMax(raw_step,min_step);
   double tick_size = TickSize();
   if(tick_size > 0.0)
      step_out = MathCeil(step_out / tick_size - 1.0e-10) * tick_size;
   step_out = NormalizeDouble(step_out,_Digits);
   floor_out = min_step;
   return (step_out > 0.0 && MathIsValidNumber(step_out));
  }

bool LoadOrCreateGrid(const double current_price)
  {
   string base_key = GridStateKey("BASE");
   string step_key = GridStateKey("STEP");
   bool can_load = (!InpResetGridOnInit && !MQLInfoInteger(MQL_TESTER) &&
                    GlobalVariableCheck(base_key) && GlobalVariableCheck(step_key));

   if(can_load)
     {
      g_grid_base = GlobalVariableGet(base_key);
      g_grid_step = GlobalVariableGet(step_key);
      if(g_grid_base > 0.0 && g_grid_step > 0.0)
        {
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
   if(!MQLInfoInteger(MQL_TESTER))
     {
      GlobalVariableSet(base_key,g_grid_base);
      GlobalVariableSet(step_key,g_grid_step);
      GlobalVariablesFlush();
     }

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

double GridLevelPrice(const bool is_up,const int index);

void DrawGridLine(const bool is_up,const int index)
  {
   if(!InpDrawGridLevels || index < 1)
      return;
   double price = GridLevelPrice(is_up,index);
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
//| Curved grid coordinates, line state and epoch reflow              |
//+------------------------------------------------------------------+
bool SelectOurPosition(const ulong ticket);
int PositionLineCode(const ulong ticket);
void RefreshGridEpochIfDue();
void CoolGridHeatOnNewM1();

bool ResizeGridArrays(const bool is_up,const int required)
  {
   if(is_up)
     {
      if(ArrayResize(g_up_state,required) < required ||
         ArrayResize(g_up_spring_side,required) < required ||
         ArrayResize(g_up_heat,required) < required ||
         ArrayResize(g_up_poisoned,required) < required ||
         ArrayResize(g_up_fast_tp,required) < required ||
         ArrayResize(g_up_price,required) < required)
         return false;
     }
   else
     {
      if(ArrayResize(g_down_state,required) < required ||
         ArrayResize(g_down_spring_side,required) < required ||
         ArrayResize(g_down_heat,required) < required ||
         ArrayResize(g_down_poisoned,required) < required ||
         ArrayResize(g_down_fast_tp,required) < required ||
         ArrayResize(g_down_price,required) < required)
         return false;
     }
   return true;
  }

double RawGridLevelPrice(const bool is_up,const int index)
  {
   if(index < 1 || g_grid_base <= 0.0 || g_grid_step <= 0.0)
      return 0.0;
   double offset = g_grid_step * MathPow((double)index,InpGridSpacingExponent);
   double raw = (is_up ? g_grid_base + offset : g_grid_base - offset);
   return NormalizePriceToTick(raw,0);
  }

double GridLevelPrice(const bool is_up,const int index)
  {
   if(index < 1)
      return g_grid_base;
   if(is_up && index < ArraySize(g_up_price) && g_up_price[index] != 0.0)
      return g_up_price[index];
   if(!is_up && index < ArraySize(g_down_price) && g_down_price[index] != 0.0)
      return g_down_price[index];
   return RawGridLevelPrice(is_up,index);
  }

void SaveGridLineMemory(const bool is_up,const int index)
  {
   if(MQLInfoInteger(MQL_TESTER) || index < 1)
      return;
   double heat = 0.0;
   int poisoned = 0;
   int fast_tp = 0;
   double price = 0.0;
   if(is_up)
     {
      if(index >= ArraySize(g_up_heat))
         return;
      heat = g_up_heat[index];
      poisoned = g_up_poisoned[index];
      fast_tp = g_up_fast_tp[index];
      price = g_up_price[index];
     }
   else
     {
      if(index >= ArraySize(g_down_heat))
         return;
      heat = g_down_heat[index];
      poisoned = g_down_poisoned[index];
      fast_tp = g_down_fast_tp[index];
      price = g_down_price[index];
     }
   GlobalVariableSet(GridLineStateKey(is_up,index,"H"),heat);
   GlobalVariableSet(GridLineStateKey(is_up,index,"P"),(double)poisoned);
   GlobalVariableSet(GridLineStateKey(is_up,index,"F"),(double)fast_tp);
   GlobalVariableSet(GridLineStateKey(is_up,index,"PX"),price);
  }

void SaveGridCounts()
  {
   if(MQLInfoInteger(MQL_TESTER))
      return;
   GlobalVariableSet(GridStateKey("UCOUNT"),(double)g_up_count);
   GlobalVariableSet(GridStateKey("DCOUNT"),(double)g_down_count);
  }

void LoadGridLineMemory(const bool is_up,const int index)
  {
   if(index < 1)
      return;
   double heat = 0.0;
   int poisoned = 0;
   int fast_tp = 0;
   double price = 0.0;
   if(!InpResetGridOnInit && !MQLInfoInteger(MQL_TESTER))
     {
      string key = GridLineStateKey(is_up,index,"H");
      if(GlobalVariableCheck(key))
         heat = GlobalVariableGet(key);
      key = GridLineStateKey(is_up,index,"P");
      if(GlobalVariableCheck(key))
         poisoned = (GlobalVariableGet(key) > 0.5 ? 1 : 0);
      key = GridLineStateKey(is_up,index,"F");
      if(GlobalVariableCheck(key))
         fast_tp = (GlobalVariableGet(key) > 0.5 ? 1 : 0);
      key = GridLineStateKey(is_up,index,"PX");
      if(GlobalVariableCheck(key))
         price = GlobalVariableGet(key);
     }
   if(price <= 0.0)
      price = RawGridLevelPrice(is_up,index);
   if(is_up)
     {
      g_up_heat[index] = MathMax(0.0,MathMin(100.0,heat));
      g_up_poisoned[index] = poisoned;
      g_up_fast_tp[index] = fast_tp;
      g_up_price[index] = price;
     }
   else
     {
      g_down_heat[index] = MathMax(0.0,MathMin(100.0,heat));
      g_down_poisoned[index] = poisoned;
      g_down_fast_tp[index] = fast_tp;
      g_down_price[index] = price;
     }
  }

double GridLineHeat(const bool is_up,const int index)
  {
   if(index < 1)
      return 0.0;
   if(is_up && index < ArraySize(g_up_heat))
      return g_up_heat[index];
   if(!is_up && index < ArraySize(g_down_heat))
      return g_down_heat[index];
   return 0.0;
  }

bool GridLinePoisoned(const bool is_up,const int index)
  {
   if(index < 1)
      return false;
   if(is_up && index < ArraySize(g_up_poisoned))
      return (g_up_poisoned[index] != 0);
   if(!is_up && index < ArraySize(g_down_poisoned))
      return (g_down_poisoned[index] != 0);
   return false;
  }

bool GridLineFastTP(const bool is_up,const int index)
  {
   if(index < 1)
      return false;
   if(is_up && index < ArraySize(g_up_fast_tp))
      return (g_up_fast_tp[index] != 0);
   if(!is_up && index < ArraySize(g_down_fast_tp))
      return (g_down_fast_tp[index] != 0);
   return false;
  }

void SetGridLineHeat(const int line_code,const double heat)
  {
   int index = (int)MathAbs((double)line_code);
   if(line_code == 0 || index < 1)
      return;
   double bounded = MathMax(0.0,MathMin(100.0,heat));
   bool is_up = (line_code > 0);
   if(is_up && index < ArraySize(g_up_heat))
      g_up_heat[index] = bounded;
   else if(!is_up && index < ArraySize(g_down_heat))
      g_down_heat[index] = bounded;
   else
      return;
   SaveGridLineMemory(is_up,index);
  }

void SetGridLinePoisoned(const int line_code,const bool poisoned)
  {
   int index = (int)MathAbs((double)line_code);
   if(line_code == 0 || index < 1)
      return;
   bool is_up = (line_code > 0);
   if(is_up && index < ArraySize(g_up_poisoned))
      g_up_poisoned[index] = (poisoned ? 1 : 0);
   else if(!is_up && index < ArraySize(g_down_poisoned))
      g_down_poisoned[index] = (poisoned ? 1 : 0);
   else
      return;
   SaveGridLineMemory(is_up,index);
  }

void SetGridLineFastTP(const int line_code,const bool fast_tp)
  {
   int index = (int)MathAbs((double)line_code);
   if(line_code == 0 || index < 1)
      return;
   bool is_up = (line_code > 0);
   if(is_up && index < ArraySize(g_up_fast_tp))
      g_up_fast_tp[index] = (fast_tp ? 1 : 0);
   else if(!is_up && index < ArraySize(g_down_fast_tp))
      g_down_fast_tp[index] = (fast_tp ? 1 : 0);
   else
      return;
   SaveGridLineMemory(is_up,index);
  }

void AddGridLineHeat(const int line_code)
  {
   if(!InpEnableGridFatigue || line_code == 0)
      return;
   SetGridLineHeat(line_code,GridLineHeat(line_code > 0,
                    (int)MathAbs((double)line_code)) + InpGridHeatPerCross);
  }

bool GridLineLocallyReversed(const int line_code)
  {
   if(!InpEnableGridFatigue || line_code == 0)
      return false;
   bool is_up = (line_code > 0);
   int index = (int)MathAbs((double)line_code);
   return (!GridLinePoisoned(is_up,index) &&
           GridLineHeat(is_up,index) >= InpGridHeatReverseThreshold);
  }

bool IsGridLineOccupied(const int line_code)
  {
   if(line_code == 0)
      return false;
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      if(PositionLineCode(ticket) == line_code)
         return true;
     }
   return false;
  }

bool InitializeGridState(const double current_price)
  {
   g_up_count = InpInitialGridLevels;
   g_down_count = InpInitialGridLevels;
   if(!InpResetGridOnInit && !MQLInfoInteger(MQL_TESTER))
     {
      string count_key = GridStateKey("UCOUNT");
      if(GlobalVariableCheck(count_key))
        {
         int saved_count = (int)MathRound(GlobalVariableGet(count_key));
         saved_count = (int)MathMax(0.0,MathMin((double)InpMaxGridLevels,(double)saved_count));
         if(saved_count > g_up_count)
            g_up_count = saved_count;
        }
      count_key = GridStateKey("DCOUNT");
      if(GlobalVariableCheck(count_key))
        {
         int saved_count = (int)MathRound(GlobalVariableGet(count_key));
         saved_count = (int)MathMax(0.0,MathMin((double)InpMaxGridLevels,(double)saved_count));
         if(saved_count > g_down_count)
            g_down_count = saved_count;
        }
     }

   // Preserve line ids used by surviving positions when the EA restarts.
   for(int p=PositionsTotal()-1; p>=0; p--)
     {
      ulong ticket = PositionGetTicket(p);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      int line_code = PositionLineCode(ticket);
      int index = (int)MathAbs((double)line_code);
      if(index < 1 || index > InpMaxGridLevels)
         continue;
      if(line_code > 0 && index > g_up_count)
         g_up_count = index;
      if(line_code < 0 && index > g_down_count)
         g_down_count = index;
     }

   if(!ResizeGridArrays(true,g_up_count + 1) || !ResizeGridArrays(false,g_down_count + 1))
      return false;
   ArrayInitialize(g_up_state,0);
   ArrayInitialize(g_down_state,0);
   ArrayInitialize(g_up_spring_side,0);
   ArrayInitialize(g_down_spring_side,0);
   ArrayInitialize(g_up_heat,0.0);
   ArrayInitialize(g_down_heat,0.0);
   ArrayInitialize(g_up_poisoned,0);
   ArrayInitialize(g_down_poisoned,0);
   ArrayInitialize(g_up_fast_tp,0);
   ArrayInitialize(g_down_fast_tp,0);
   ArrayInitialize(g_up_price,0.0);
   ArrayInitialize(g_down_price,0.0);

   for(int i=1; i<=g_up_count; i++)
     {
      LoadGridLineMemory(true,i);
      g_up_state[i] = ComparePriceToLevel(current_price,GridLevelPrice(true,i));
      g_up_spring_side[i] = 0;
      SaveGridLineMemory(true,i);
      DrawGridLine(true,i);
     }
   for(int i=1; i<=g_down_count; i++)
     {
      LoadGridLineMemory(false,i);
      g_down_state[i] = ComparePriceToLevel(current_price,GridLevelPrice(false,i));
      g_down_spring_side[i] = 0;
      SaveGridLineMemory(false,i);
      DrawGridLine(false,i);
     }
   DrawBaseLine();
   g_last_heat_bar_time = iTime(_Symbol,PERIOD_M1,0);
   SaveGridCounts();
   return true;
  }

void ExpandGrid(const double price)
  {
   if(g_grid_step <= 0.0)
      return;
   int old_up_count = g_up_count;
   int old_down_count = g_down_count;
   int guard = 0;
   double upper_limit = price + g_grid_step;
   while(g_up_count < InpMaxGridLevels && guard < 10000)
     {
      guard++;
      int next_index = g_up_count + 1;
      double next_price = RawGridLevelPrice(true,next_index);
      double last_price = GridLevelPrice(true,g_up_count);
      double minimum_gap = MathMax(TickSize(),CrossTolerance());
      if(next_price < last_price + minimum_gap)
         next_price = NormalizePriceToTick(last_price + minimum_gap,1);
      if(next_price <= upper_limit)
        {
         if(!ResizeGridArrays(true,next_index + 1))
            break;
         g_up_count = next_index;
         g_up_state[next_index] = 0;
         g_up_spring_side[next_index] = 0;
         g_up_heat[next_index] = 0.0;
         g_up_poisoned[next_index] = 0;
         g_up_fast_tp[next_index] = 0;
         g_up_price[next_index] = next_price;
         SaveGridLineMemory(true,next_index);
         DrawGridLine(true,next_index);
        }
      else
         break;
     }

   guard = 0;
   double lower_limit = price - g_grid_step;
   while(g_down_count < InpMaxGridLevels && guard < 10000)
     {
      guard++;
      int next_index = g_down_count + 1;
      double next_price = RawGridLevelPrice(false,next_index);
      double last_price = GridLevelPrice(false,g_down_count);
      double minimum_gap = MathMax(TickSize(),CrossTolerance());
      if(next_price > last_price - minimum_gap)
         next_price = NormalizePriceToTick(last_price - minimum_gap,-1);
      if(next_price >= lower_limit)
        {
         if(!ResizeGridArrays(false,next_index + 1))
            break;
         g_down_count = next_index;
         g_down_state[next_index] = 0;
         g_down_spring_side[next_index] = 0;
         g_down_heat[next_index] = 0.0;
         g_down_poisoned[next_index] = 0;
         g_down_fast_tp[next_index] = 0;
         g_down_price[next_index] = next_price;
         SaveGridLineMemory(false,next_index);
         DrawGridLine(false,next_index);
        }
      else
         break;
     }
   if(g_up_count != old_up_count || g_down_count != old_down_count)
      SaveGridCounts();
  }

void ReflowGridSideForEpoch(const bool is_up)
  {
   int count = (is_up ? g_up_count : g_down_count);
   if(count < 1)
      return;
   double old_distance[];
   int anchored[];
   if(ArrayResize(old_distance,count + 1) < count + 1 ||
      ArrayResize(anchored,count + 1) < count + 1)
      return;
   old_distance[0] = 0.0;
   anchored[0] = 1;
   for(int i=1; i<=count; i++)
     {
      double old_price = (is_up ? g_up_price[i] : g_down_price[i]);
      old_distance[i] = MathMax(TickSize(),(is_up ? old_price - g_grid_base : g_grid_base - old_price));
      int line_code = (is_up ? i : -i);
      anchored[i] = (IsGridLineOccupied(line_code) ? 1 : 0);
     }

   int previous_anchor = 0;
   double previous_distance = 0.0;
   double min_gap = MathMax(TickSize(),CrossTolerance());
   for(int next=1; next<=count + 1; next++)
     {
      bool next_is_anchor = (next <= count && anchored[next] != 0);
      if(next <= count && !next_is_anchor)
         continue;
      double next_distance = (next_is_anchor ? old_distance[next] : 0.0);
      for(int k=previous_anchor + 1; k<next; k++)
        {
         double candidate = g_grid_step * MathPow((double)k,InpGridSpacingExponent);
         double lower = previous_distance + min_gap * (double)(k - previous_anchor);
         if(candidate < lower)
            candidate = lower;
         if(next_is_anchor)
           {
            double upper = next_distance - min_gap * (double)(next - k);
            if(candidate > upper)
               candidate = upper;
            if(candidate < lower)
               candidate = lower; // Retain a valid monotone line order if anchors are very close.
           }
         double new_price = (is_up ? g_grid_base + candidate : g_grid_base - candidate);
         new_price = NormalizePriceToTick(new_price,0);
         if(is_up)
            g_up_price[k] = new_price;
         else
            g_down_price[k] = new_price;
        }
      if(next_is_anchor)
        {
         previous_anchor = next;
         previous_distance = next_distance;
        }
     }

   for(int i=1; i<=count; i++)
     {
      if(is_up)
         g_up_spring_side[i] = 0;
      else
         g_down_spring_side[i] = 0;
      SaveGridLineMemory(is_up,i);
      DrawGridLine(is_up,i);
     }
  }

void ReflowGridPricesForEpoch(const double current_price)
  {
   ReflowGridSideForEpoch(true);
   ReflowGridSideForEpoch(false);
   for(int i=1; i<=g_up_count; i++)
     {
      g_up_state[i] = ComparePriceToLevel(current_price,GridLevelPrice(true,i));
      g_up_spring_side[i] = 0;
     }
   for(int i=1; i<=g_down_count; i++)
     {
      g_down_state[i] = ComparePriceToLevel(current_price,GridLevelPrice(false,i));
      g_down_spring_side[i] = 0;
     }
   RecolorGridLines();
  }

void RebuildGridForNewCycle(const double current_price,const bool clear_fatigue)
  {
   for(int i=1; i<=g_up_count; i++)
     {
      g_up_price[i] = RawGridLevelPrice(true,i);
      g_up_state[i] = ComparePriceToLevel(current_price,g_up_price[i]);
      g_up_spring_side[i] = 0;
      if(clear_fatigue)
        {
         g_up_heat[i] = 0.0;
         g_up_poisoned[i] = 0;
         g_up_fast_tp[i] = 0;
        }
      SaveGridLineMemory(true,i);
      DrawGridLine(true,i);
     }
   for(int i=1; i<=g_down_count; i++)
     {
      g_down_price[i] = RawGridLevelPrice(false,i);
      g_down_state[i] = ComparePriceToLevel(current_price,g_down_price[i]);
      g_down_spring_side[i] = 0;
      if(clear_fatigue)
        {
         g_down_heat[i] = 0.0;
         g_down_poisoned[i] = 0;
         g_down_fast_tp[i] = 0;
        }
      SaveGridLineMemory(false,i);
      DrawGridLine(false,i);
     }
   DrawBaseLine();
   RecolorGridLines();
  }

//+------------------------------------------------------------------+
//| Closed-candle direction and morphology                            |
//+------------------------------------------------------------------+
double CandleMorphologyScore(const int side,const double open_price,const double high_price,
                             const double low_price,const double close_price)
  {
   double full_range = MathMax(high_price - low_price,TickSize());
   double body = MathAbs(close_price - open_price);
   double body_ratio = MathMax(0.0,MathMin(1.0,body / full_range));
   double upper_wick = MathMax(0.0,high_price - MathMax(open_price,close_price));
   double lower_wick = MathMax(0.0,MathMin(open_price,close_price) - low_price);
   double upper_ratio = MathMax(0.0,MathMin(1.0,upper_wick / full_range));
   double lower_ratio = MathMax(0.0,MathMin(1.0,lower_wick / full_range));
   double wick_tolerance = MathMax(TickSize() * 0.05,full_range * 1.0e-8);

   // A clean HA momentum candle has no adverse-side wick.
   if((side > 0 && lower_wick <= wick_tolerance) ||
      (side < 0 && upper_wick <= wick_tolerance))
      return 1.0;

   // Small bodies trapped between two substantial wicks are turbulent/doji-like.
   if(body_ratio <= 0.25 && upper_ratio >= 0.30 && lower_ratio >= 0.30)
      return 0.2;

   double adverse_wick_ratio = (side > 0 ? lower_ratio : upper_ratio);
   double score = 0.2 + 0.8 * body_ratio * (1.0 - adverse_wick_ratio);
   return MathMax(0.0,MathMin(1.0,score));
  }

bool CalculateClosedCandleSignal(int &side_out,datetime &current_bar_time,double &score_out)
  {
   side_out = 0;
   current_bar_time = 0;
   score_out = 0.0;
   int history = InpSignalHistoryBars;
   if(history < 50)
      history = 50;
   if(history > 1500)
      history = 1500;

   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   int copied = CopyRates(_Symbol,InpSignalTimeframe,0,history,rates);
   if(copied < 3)
      return false;
   current_bar_time = rates[0].time;

   if(InpSignalCandleMode == SIGNAL_STANDARD_CANDLE)
     {
      side_out = (rates[1].close >= rates[1].open ? 1 : -1);
      score_out = CandleMorphologyScore(side_out,rates[1].open,rates[1].high,
                                        rates[1].low,rates[1].close);
      return true;
     }

   double previous_ha_open = 0.0;
   double previous_ha_close = 0.0;
   for(int shift=copied - 1; shift>=0; shift--)
     {
      double ha_close = (rates[shift].open + rates[shift].high + rates[shift].low + rates[shift].close) / 4.0;
      double ha_open;
      if(shift == copied - 1)
         ha_open = (rates[shift].open + rates[shift].close) / 2.0;
      else
         ha_open = (previous_ha_open + previous_ha_close) / 2.0;
      double ha_high = MathMax(rates[shift].high,MathMax(ha_open,ha_close));
      double ha_low = MathMin(rates[shift].low,MathMin(ha_open,ha_close));

      if(shift == 1)
        {
         side_out = (ha_close >= ha_open ? 1 : -1);
         score_out = CandleMorphologyScore(side_out,ha_open,ha_high,ha_low,ha_close);
        }
      previous_ha_open = ha_open;
      previous_ha_close = ha_close;
     }
   return (side_out != 0);
  }

void ClosePositionsOppositeToTradeSide(const int new_trade_side);

void RefreshClosedCandleSignal(const bool force)
  {
   datetime chart_bar_time = iTime(_Symbol,InpSignalTimeframe,0);
   if(!force && chart_bar_time > 0 && chart_bar_time == g_last_signal_bar_time)
      return;

   int new_side = 0;
   datetime current_bar_time = 0;
   double new_score = 0.0;
   if(!CalculateClosedCandleSignal(new_side,current_bar_time,new_score))
      return;

   g_last_signal_bar_time = (current_bar_time > 0 ? current_bar_time : chart_bar_time);
   if(new_side == 0)
      return;

   int old_side = g_signal_side;
   double old_score = g_signal_score;
   g_signal_side = new_side;
   g_signal_score = MathMax(0.0,MathMin(1.0,new_score));
   if(old_side != new_side || MathAbs(old_score - g_signal_score) >= 0.05)
     {
      g_last_action = StringFormat("M1 sinyali %s, HA morfoloji %.2f",SideName(new_side),g_signal_score);
      PrintFormat("Closed candle signal: %s -> %s; morphology %.2f -> %.2f (%s)",
                  SideName(old_side),SideName(new_side),old_score,g_signal_score,
                  (InpSignalCandleMode == SIGNAL_HEIKEN_ASHI ? "Heiken Ashi" : "standard candle"));
      RecolorGridLines();
      if(old_side != new_side && InpCloseOppositeOnColorChange && old_side != 0)
         ClosePositionsOppositeToTradeSide(TradeSideForSignal(new_side));
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

int FindRuntimePositionSettings(const ulong identifier)
  {
   for(int i=0; i<ArraySize(g_position_settings); i++)
      if(g_position_settings[i].identifier == identifier)
         return i;
   return -1;
  }

bool ReadPositionSettingsByIdentifier(const ulong identifier,int &line_code,double &grid_step,
                                     int &tp_grids,int &sl_grids,long &open_time_msc)
  {
   line_code = 0;
   grid_step = 0.0;
   tp_grids = 0;
   sl_grids = 0;
   open_time_msc = 0;
   int index = FindRuntimePositionSettings(identifier);
   if(index >= 0)
     {
      line_code = g_position_settings[index].line_code;
      grid_step = g_position_settings[index].grid_step;
      tp_grids = g_position_settings[index].tp_grids;
      sl_grids = g_position_settings[index].sl_grids;
      open_time_msc = g_position_settings[index].open_time_msc;
      return true;
     }
   if(MQLInfoInteger(MQL_TESTER) || identifier == 0)
      return false;

   string key = PositionStateKey(identifier,"GS");
   if(!GlobalVariableCheck(key))
      return false;
   grid_step = GlobalVariableGet(key);
   key = PositionStateKey(identifier,"LN");
   if(GlobalVariableCheck(key))
      line_code = (int)MathRound(GlobalVariableGet(key));
   key = PositionStateKey(identifier,"TP");
   if(GlobalVariableCheck(key))
      tp_grids = (int)MathRound(GlobalVariableGet(key));
   key = PositionStateKey(identifier,"SL");
   if(GlobalVariableCheck(key))
      sl_grids = (int)MathRound(GlobalVariableGet(key));
   key = PositionStateKey(identifier,"OT");
   if(GlobalVariableCheck(key))
      open_time_msc = (long)MathRound(GlobalVariableGet(key));
   return true;
  }

int PositionLineCode(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket))
      return 0;
   ulong identifier = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   int line_code = 0;
   double step = 0.0;
   int tp = 0;
   int sl = 0;
   long open_time = 0;
   if(ReadPositionSettingsByIdentifier(identifier,line_code,step,tp,sl,open_time) && line_code != 0)
      return line_code;
   return ParseLineCode(PositionGetString(POSITION_COMMENT));
  }

void StorePositionSettings(const ulong identifier,const int line_code,const double grid_step,
                           const int tp_grids,const int sl_grids,const long open_time_msc)
  {
   if(identifier == 0)
      return;
   int index = FindRuntimePositionSettings(identifier);
   if(index < 0)
     {
      int n = ArraySize(g_position_settings);
      if(ArrayResize(g_position_settings,n + 1) < n + 1)
         return;
      index = n;
      g_position_settings[index].identifier = identifier;
     }
   g_position_settings[index].line_code = line_code;
   g_position_settings[index].grid_step = grid_step;
   g_position_settings[index].tp_grids = tp_grids;
   g_position_settings[index].sl_grids = sl_grids;
   g_position_settings[index].open_time_msc = open_time_msc;

   if(MQLInfoInteger(MQL_TESTER))
      return; // Runtime map is isolated per pass and preserves each epoch's settings.
   GlobalVariableSet(PositionStateKey(identifier,"LN"),(double)line_code);
   GlobalVariableSet(PositionStateKey(identifier,"GS"),grid_step);
   GlobalVariableSet(PositionStateKey(identifier,"TP"),(double)tp_grids);
   GlobalVariableSet(PositionStateKey(identifier,"SL"),(double)sl_grids);
   GlobalVariableSet(PositionStateKey(identifier,"OT"),(double)open_time_msc);
   GlobalVariablesFlush();
  }

void RemovePendingSettingsAt(const int index)
  {
   int total = ArraySize(g_pending_settings);
   if(index < 0 || index >= total)
      return;
   for(int i=index; i<total - 1; i++)
     {
      g_pending_settings[i].side = g_pending_settings[i + 1].side;
      g_pending_settings[i].line_code = g_pending_settings[i + 1].line_code;
      g_pending_settings[i].comment = g_pending_settings[i + 1].comment;
      g_pending_settings[i].grid_step = g_pending_settings[i + 1].grid_step;
      g_pending_settings[i].tp_grids = g_pending_settings[i + 1].tp_grids;
      g_pending_settings[i].sl_grids = g_pending_settings[i + 1].sl_grids;
      g_pending_settings[i].request_time_msc = g_pending_settings[i + 1].request_time_msc;
     }
   ArrayResize(g_pending_settings,total - 1);
  }

void AddPendingPositionSettings(const int side,const int line_code,const string comment,
                                const double grid_step,const int tp_grids,const int sl_grids,
                                const long request_time_msc)
  {
   int n = ArraySize(g_pending_settings);
   if(ArrayResize(g_pending_settings,n + 1) < n + 1)
      return;
   g_pending_settings[n].side = side;
   g_pending_settings[n].line_code = line_code;
   g_pending_settings[n].comment = comment;
   g_pending_settings[n].grid_step = grid_step;
   g_pending_settings[n].tp_grids = tp_grids;
   g_pending_settings[n].sl_grids = sl_grids;
   g_pending_settings[n].request_time_msc = request_time_msc;
  }

bool ConsumePendingPositionSettings(const ulong ticket,const int line_code,
                                    double &grid_step,int &tp_grids,int &sl_grids)
  {
   if(!PositionSelectByTicket(ticket))
      return false;
   int side = SideFromPositionType(PositionGetInteger(POSITION_TYPE));
   long position_time = PositionGetInteger(POSITION_TIME_MSC);
   for(int i=0; i<ArraySize(g_pending_settings); i++)
     {
      if(g_pending_settings[i].side != side || g_pending_settings[i].line_code != line_code)
         continue;
      if(position_time + 1000 < g_pending_settings[i].request_time_msc)
         continue;
      grid_step = g_pending_settings[i].grid_step;
      tp_grids = g_pending_settings[i].tp_grids;
      sl_grids = g_pending_settings[i].sl_grids;
      RemovePendingSettingsAt(i);
      return true;
     }
   return false;
  }

void DeletePositionSettings(const ulong identifier)
  {
   int index = FindRuntimePositionSettings(identifier);
   if(index >= 0)
     {
      int total = ArraySize(g_position_settings);
      for(int i=index; i<total - 1; i++)
        {
         g_position_settings[i].identifier = g_position_settings[i + 1].identifier;
         g_position_settings[i].line_code = g_position_settings[i + 1].line_code;
         g_position_settings[i].grid_step = g_position_settings[i + 1].grid_step;
         g_position_settings[i].tp_grids = g_position_settings[i + 1].tp_grids;
         g_position_settings[i].sl_grids = g_position_settings[i + 1].sl_grids;
         g_position_settings[i].open_time_msc = g_position_settings[i + 1].open_time_msc;
        }
      ArrayResize(g_position_settings,total - 1);
     }
   if(MQLInfoInteger(MQL_TESTER) || identifier == 0)
      return;
   GlobalVariableDel(PositionStateKey(identifier,"LN"));
   GlobalVariableDel(PositionStateKey(identifier,"GS"));
   GlobalVariableDel(PositionStateKey(identifier,"TP"));
   GlobalVariableDel(PositionStateKey(identifier,"SL"));
   GlobalVariableDel(PositionStateKey(identifier,"OT"));
   GlobalVariablesFlush();
  }

void GetPositionGridSettings(const ulong ticket,double &grid_step,int &tp_grids,int &sl_grids)
  {
   grid_step = g_grid_step;
   tp_grids = InpTakeProfitGrids;
   sl_grids = InpStopLossGrids;
   if(!PositionSelectByTicket(ticket))
      return;

   ulong identifier = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   long open_time_msc = PositionGetInteger(POSITION_TIME_MSC);
   int line_code = PositionLineCode(ticket);
   int saved_line = 0;
   int saved_tp = 0;
   int saved_sl = 0;
   double saved_step = 0.0;
   long saved_open_time = 0;
   bool have_saved = ReadPositionSettingsByIdentifier(identifier,saved_line,saved_step,
                                                       saved_tp,saved_sl,saved_open_time);
   bool should_store = !have_saved;
   if(have_saved)
     {
      if(saved_line != 0)
         line_code = saved_line;
      else
         should_store = true;
      if(saved_step > 0.0)
         grid_step = saved_step;
      else
         should_store = true;
      if(saved_tp > 0)
         tp_grids = saved_tp;
      else
         should_store = true;
      if(saved_sl > 0)
         sl_grids = saved_sl;
      else
         should_store = true;
      if(saved_open_time > 0)
         open_time_msc = saved_open_time;
      else
         should_store = true;
     }
   else
      ConsumePendingPositionSettings(ticket,line_code,grid_step,tp_grids,sl_grids);

   if(should_store)
      StorePositionSettings(identifier,line_code,grid_step,tp_grids,sl_grids,open_time_msc);
  }

int CountOurPositions(const int side_filter=0)
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
      if(PositionLineCode(ticket) == line_code)
         return true;
     }
   return false;
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

int ServerProtectionTPGrids(const int runtime_tp_grids)
  {
   if(!InpEnableSymbioticLayering)
      return runtime_tp_grids;
   int symbiotic_backup_tp = (int)MathCeil(InpSymbioticProfitGrids) + 1;
   if(runtime_tp_grids > symbiotic_backup_tp)
      return runtime_tp_grids;
   return symbiotic_backup_tp;
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
   int protection_tp_grids = ServerProtectionTPGrids(tp_grids);
   double desired_tp = PositionTakeProfit(entry,side,grid_step,protection_tp_grids);
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

long CurrentTimeMsc()
  {
   MqlTick tick;
   if(SymbolInfoTick(_Symbol,tick) && tick.time_msc > 0)
      return (long)tick.time_msc;
   return (long)TimeCurrent() * 1000;
  }

void RecordPositionLifetime(const long open_time_msc,const long close_time_msc)
  {
   if(open_time_msc <= 0 || close_time_msc <= open_time_msc)
      return;
   double duration_seconds = (double)(close_time_msc - open_time_msc) / 1000.0;
   g_position_lifetime_seconds_squared += duration_seconds * duration_seconds;
  }

void RecordTakeProfitPrice(const double price,const double volume)
  {
   if(price <= 0.0 || volume <= 0.0)
      return;
   g_tp_price_volume_sum += price * volume;
   g_tp_volume_sum += volume;
   if(!MQLInfoInteger(MQL_TESTER))
     {
      GlobalVariableSet(GridStateKey("TPWSUM"),g_tp_price_volume_sum);
      GlobalVariableSet(GridStateKey("TPVSUM"),g_tp_volume_sum);
     }
  }

void LoadTakeProfitPriceStats()
  {
   g_tp_price_volume_sum = 0.0;
   g_tp_volume_sum = 0.0;
   if(MQLInfoInteger(MQL_TESTER))
      return;
   string key = GridStateKey("TPWSUM");
   if(GlobalVariableCheck(key))
      g_tp_price_volume_sum = GlobalVariableGet(key);
   key = GridStateKey("TPVSUM");
   if(GlobalVariableCheck(key))
      g_tp_volume_sum = GlobalVariableGet(key);
  }

void ResetTakeProfitPriceStats()
  {
   g_tp_price_volume_sum = 0.0;
   g_tp_volume_sum = 0.0;
   if(!MQLInfoInteger(MQL_TESTER))
     {
      GlobalVariableSet(GridStateKey("TPWSUM"),0.0);
      GlobalVariableSet(GridStateKey("TPVSUM"),0.0);
     }
  }

void RecordSuccessfulGridTP(const int line_code,const long open_time_msc,const long close_time_msc)
  {
   if(!InpEnableGridFatigue || line_code == 0 || open_time_msc <= 0 || close_time_msc < open_time_msc)
      return;
   long duration_msc = close_time_msc - open_time_msc;
   if(duration_msc <= (long)InpFastTPMaxSeconds * 1000)
     {
      SetGridLineHeat(line_code,0.0);
      SetGridLinePoisoned(line_code,false);
      SetGridLineFastTP(line_code,true);
     }
  }

void PoisonGridLineAfterSL(const int line_code)
  {
   if(!InpEnableGridFatigue || line_code == 0)
      return;
   SetGridLineHeat(line_code,InpGridHeatToxicThreshold);
   SetGridLinePoisoned(line_code,true);
   SetGridLineFastTP(line_code,false);
  }

bool CloseOurPosition(const ulong ticket,const string reason)
  {
   if(!SelectOurPosition(ticket))
      return true; // Already closed by server-side TP/SL.
   ulong identifier = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   int side = SideFromPositionType(PositionGetInteger(POSITION_TYPE));
   long open_time_msc = PositionGetInteger(POSITION_TIME_MSC);
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
   RecordPositionLifetime(open_time_msc,CurrentTimeMsc());
   DeletePositionSettings(identifier);
   PrintFormat("Pozisyon kapandı: ticket=%I64u side=%s reason=%s",ticket,SideName(side),reason);
   g_last_action = reason;
   return true;
  }

void CloseAllOurPositions(const string reason)
  {
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
      CloseOurPosition(tickets[i],reason);
  }

void ReseedGridCrossState(const double current_price)
  {
   if(current_price <= 0.0)
      return;
   for(int i=1; i<=g_up_count; i++)
     {
      g_up_state[i] = ComparePriceToLevel(current_price,GridLevelPrice(true,i));
      g_up_spring_side[i] = 0;
     }
   for(int i=1; i<=g_down_count; i++)
     {
      g_down_state[i] = ComparePriceToLevel(current_price,GridLevelPrice(false,i));
      g_down_spring_side[i] = 0;
     }
  }

string TradingHoursWindowText()
  {
   return StringFormat("%02d:%02d-%02d:%02d",InpTradingStartHour,InpTradingStartMinute,
                       InpTradingEndHour,InpTradingEndMinute);
  }

bool HandleTradingHours()
  {
   if(!InpEnableTradingHours)
      return false;

   datetime turkey_time = CurrentTurkeyTime();
   bool allowed = IsWithinTradingHours(turkey_time);
   if(!allowed)
     {
      if(!g_was_outside_trading_hours)
        {
         string local_clock = (turkey_time > 0 ? TimeToString(turkey_time,TIME_MINUTES) : "--:--");
         PrintFormat("Türkiye işlem penceresi dışında: saat=%s pencere=%s. Bu EA'nın pozisyonları kapatılıyor ve yeni girişler durduruluyor.",
                     local_clock,TradingHoursWindowText());
        }
      g_was_outside_trading_hours = true;
      datetime server_now = TimeCurrent();
      if(CountOurPositions(0) > 0 &&
         (g_last_hours_close_attempt <= 0 || server_now <= 0 || server_now < g_last_hours_close_attempt ||
          server_now - g_last_hours_close_attempt >= 5))
        {
         CloseAllOurPositions("Türkiye işlem saati dışında pozisyon kapatma");
         g_last_hours_close_attempt = server_now;
        }
      int remaining = CountOurPositions(0);
      if(remaining > 0)
         g_last_action = StringFormat("Saat filtresi: %d pozisyon kapatılmayı bekliyor",remaining);
      else
        {
         string local_clock = (turkey_time > 0 ? TimeToString(turkey_time,TIME_MINUTES) : "--:--");
         g_last_action = StringFormat("Saat filtresi: Türkiye %s, %s dışında; beklemede",
                                      local_clock,TradingHoursWindowText());
        }
      return true;
     }

   if(g_was_outside_trading_hours)
     {
      // If a close was rejected while the market was shut, finish liquidating before resuming.
      if(CountOurPositions(0) > 0)
        {
         datetime server_now = TimeCurrent();
         if(g_last_hours_close_attempt <= 0 || server_now <= 0 || server_now < g_last_hours_close_attempt ||
            server_now - g_last_hours_close_attempt >= 5)
           {
            CloseAllOurPositions("Türkiye işlem penceresi açıldı; önce kalan pozisyonları kapat");
            g_last_hours_close_attempt = server_now;
           }
        }
      int remaining = CountOurPositions(0);
      if(remaining > 0)
        {
         g_last_action = StringFormat("Seans açıldı ancak %d eski pozisyon kapanamadı; yeni giriş bekletiliyor",remaining);
         return true;
        }

      g_was_outside_trading_hours = false;
      g_last_hours_close_attempt = 0;
      g_reseed_crosses_on_next_tick = true;
      g_last_action = StringFormat("Türkiye işlem penceresi açıldı (%s); yeni kesiş bekleniyor",
                                   TradingHoursWindowText());
      PrintFormat("Türkiye işlem penceresi açıldı (%s); dışarıda oluşan kesişler yok sayıldı.",
                  TradingHoursWindowText());
     }
   return false;
  }

bool HandleEquityProfitTarget()
  {
   if(InpCloseAllAtEquityGain <= 0.0 || g_profit_target_start_equity <= 0.0)
      return false;

   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(!g_profit_target_liquidating &&
      current_equity - g_profit_target_start_equity >= InpCloseAllAtEquityGain)
     {
      g_profit_target_liquidating = true;
      SaveProfitTargetState();
      g_last_action = "Özsermaye hedefi ulaştı; EA pozisyonları kapatılıyor";
      PrintFormat("Özsermaye hedefi ulaştı: başlangıç=%.2f güncel=%.2f hedef=%.2f %s; bu EA'nın pozisyonları kapatılıyor.",
                  g_profit_target_start_equity,current_equity,InpCloseAllAtEquityGain,
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
      MqlTick tick;
      double current_price = g_grid_base;
      if(SymbolInfoTick(_Symbol,tick))
         current_price = MidPrice(tick);
      double previous_base = g_grid_base;
      bool moved_to_poc = false;
      if(g_tp_volume_sum > 0.0 && g_tp_price_volume_sum > 0.0)
        {
         double poc_price = g_tp_price_volume_sum / g_tp_volume_sum;
         if(poc_price > 0.0 && MathIsValidNumber(poc_price))
           {
            g_grid_base = NormalizePriceToTick(poc_price,0);
            moved_to_poc = (MathAbs(g_grid_base - previous_base) >= TickSize() * 0.5);
           }
        }

      // All positions have closed, so every line is free to return to the new curved epoch.
      RebuildGridForNewCycle(current_price,moved_to_poc);
      if(!MQLInfoInteger(MQL_TESTER))
        {
         GlobalVariableSet(GridStateKey("BASE"),g_grid_base);
         GlobalVariableSet(GridStateKey("STEP"),g_grid_step);
        }
      ResetTakeProfitPriceStats();

      g_profit_target_start_equity = new_equity;
      g_profit_target_liquidating = false;
      SaveProfitTargetState();
      g_last_action = (moved_to_poc ? "Kâr hedefi tamamlandı; grid TP-POC noktasına taşındı" :
                                      "Kâr hedefi tamamlandı; yeni hedef döngüsü başladı");
      PrintFormat("Yeni kâr hedefi döngüsü: başlangıç özsermayesi=%.2f %s hedef=%.2f; base %.*f -> %.*f%s",
                  g_profit_target_start_equity,AccountInfoString(ACCOUNT_CURRENCY),
                  InpCloseAllAtEquityGain,_Digits,previous_base,_Digits,g_grid_base,
                  (moved_to_poc ? " (TP-weighted POC)" : ""));
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

int EntryTakeProfitGrids(const int line_code)
  {
   if(g_signal_score > 0.8)
      return 5;
   if(g_signal_score < 0.3)
      return 1;
   int grids = InpTakeProfitGrids;
   if(InpEnableGridFatigue && line_code != 0 &&
      GridLineFastTP(line_code > 0,(int)MathAbs((double)line_code)))
      grids++;
   return grids;
  }

bool ReverseModeForGridLine(const int line_code)
  {
   int intended_side = TradeSideForSignal(g_signal_side);
   if(GridLineLocallyReversed(line_code))
      intended_side = -intended_side;
   return (intended_side != 0 && intended_side != g_signal_side);
  }

bool OpenGridPosition(const int side,const int line_code,const double signal_price,
                      const double position_grid_step,const int tp_grids)
  {
   if(side == 0 || position_grid_step <= 0.0 || g_signal_side == 0)
      return false;
   if(InpEnableTradingHours && !IsWithinTradingHours(CurrentTurkeyTime()))
     {
      g_last_action = "Türkiye işlem saati dışında yeni giriş engellendi";
      return false;
     }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick) || tick.ask <= 0.0 || tick.bid <= 0.0)
      return false;

   double spread_price = MathMax(0.0,tick.ask - tick.bid);
   double spread_points = spread_price / _Point;
   if(InpMaxSpreadPoints > 0 && spread_points > InpMaxSpreadPoints)
     {
      g_last_action = StringFormat("Spread yüksek: %.1f point",spread_points);
      return false;
     }
   if(InpMaxSpreadGridFraction > 0.0 && spread_price > position_grid_step * InpMaxSpreadGridFraction)
     {
      g_last_action = StringFormat("Spread grid adımına göre yüksek: %.1f point",spread_points);
      return false;
     }

   int side_count = CountOurPositions(side);
   int total_count = CountOurPositions(0);
   if(InpMaxTotalPositions > 0 && total_count >= InpMaxTotalPositions)
     {
      g_last_action = "Toplam pozisyon sınırı dolu";
      return false;
     }
   if(InpMaxLayersPerSide > 0 && side_count >= InpMaxLayersPerSide)
     {
      g_last_action = StringFormat("%s katman sınırı dolu",SideName(side));
      return false;
     }
   if(InpOnePositionPerGridLine && HasPositionOnGridLine(side,line_code))
     {
      g_last_action = "Bu grid çizgisinde aynı yönlü pozisyon açık";
      return false;
     }

   double volume = OrderVolume();
   if(volume <= 0.0)
     {
      g_last_action = "Lot hacmi broker sınırlarına uymuyor";
      return false;
     }

   double expected_entry = (side > 0 ? tick.ask : tick.bid);
   int server_tp_grids = ServerProtectionTPGrids(tp_grids);
   double expected_tp = PositionTakeProfit(expected_entry,side,position_grid_step,server_tp_grids);
   double expected_sl = PositionStopLoss(expected_entry,side,position_grid_step,InpStopLossGrids);
   if(expected_tp <= 0.0 || expected_sl <= 0.0)
     {
      g_last_action = "Pozitif olmayan TP/SL fiyatı nedeniyle giriş atlandı";
      return false;
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

   ulong ticket = 0;
   FindPositionFromDeal(trade.ResultDeal(),side,comment,request_time_msc,ticket);
   if(ticket > 0 && PositionSelectByTicket(ticket))
     {
      ulong identifier = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      double fill_price = PositionGetDouble(POSITION_PRICE_OPEN);
      long open_time_msc = PositionGetInteger(POSITION_TIME_MSC);
      if(open_time_msc <= 0)
         open_time_msc = request_time_msc;
      StorePositionSettings(identifier,line_code,position_grid_step,tp_grids,
                            InpStopLossGrids,open_time_msc);
      ModifyPositionProtection(ticket,side,fill_price,position_grid_step,tp_grids,InpStopLossGrids);
      PrintFormat("Grid giriş: %s line=%s signal=%.*f fill=%.*f lot=%.8f gridStep=%.*f localTP=%.*f serverTP=%.*f SL=%.*f",
                  SideName(side),line_text,_Digits,signal_price,_Digits,fill_price,
                  PositionGetDouble(POSITION_VOLUME),_Digits,position_grid_step,
                  _Digits,PositionTakeProfit(fill_price,side,position_grid_step,tp_grids),
                  _Digits,PositionTakeProfit(fill_price,side,position_grid_step,server_tp_grids),
                  _Digits,PositionStopLoss(fill_price,side,position_grid_step,InpStopLossGrids));
     }
   else
     {
      AddPendingPositionSettings(side,line_code,comment,position_grid_step,tp_grids,
                                 InpStopLossGrids,request_time_msc);
      PrintFormat("Grid emri kabul edildi side=%s line=%s; pozisyon sonraki tikte bulunacak.",SideName(side),line_text);
     }

   // A fast-TP advantage applies to exactly the next accepted entry on this line.
   if(InpEnableGridFatigue && GridLineFastTP(line_code > 0,(int)MathAbs((double)line_code)))
      SetGridLineFastTP(line_code,false);
   g_last_action = StringFormat("Yeni %s giriş: %s TP=%d",SideName(side),line_text,tp_grids);
   return true;
  }

void HandleGridCross(const bool is_up,const int index,const int cross_direction,
                     const double current_price)
  {
   int line_code = (is_up ? index : -index);
   bool is_poisoned = (InpEnableGridFatigue && GridLinePoisoned(is_up,index));
   if(is_poisoned)
     {
      g_last_action = StringFormat("Zehirli çizgi beklemede: %s%d",
                                   (is_up ? "U_" : "D_"),index);
      return;
     }

   int trade_side = TradeSideForSignal(g_signal_side);
   if(GridLineLocallyReversed(line_code))
      trade_side = -trade_side;
   if(trade_side == 0)
      return;

   if(g_signal_score > 0.8)
     {
      if(cross_direction != g_signal_side)
         return; // Pure trend morphology only accepts signal-direction breakouts.
     }
   else if(!InpEnterOnAnyCross && cross_direction != trade_side)
      return;

   int tp_grids = EntryTakeProfitGrids(line_code);
   OpenGridPosition(trade_side,line_code,current_price,g_grid_step,tp_grids);
  }

void RememberTick(const MqlTick &tick)
  {
   double price = MidPrice(tick);
   if(price <= 0.0)
      return;
   long time_msc = (long)tick.time_msc;
   if(time_msc <= 0)
      time_msc = CurrentTimeMsc();
   if(g_tick_history_count < 5)
     {
      g_tick_time_history[g_tick_history_count] = time_msc;
      g_tick_price_history[g_tick_history_count] = price;
      g_tick_history_count++;
     }
   else
     {
      for(int i=0; i<4; i++)
        {
         g_tick_time_history[i] = g_tick_time_history[i + 1];
         g_tick_price_history[i] = g_tick_price_history[i + 1];
        }
      g_tick_time_history[4] = time_msc;
      g_tick_price_history[4] = price;
     }
   g_last_tick_time_msc = time_msc;
   g_last_tick_price = price;
  }

bool IsBallisticCross(const double line_price,const int previous_side,
                      const double previous_tick_price,const long previous_tick_time_msc,
                      const double current_price,const long current_time_msc)
  {
   if(g_grid_step <= 0.0 || current_time_msc <= 0)
      return false;
   double required_jump = g_grid_step * 0.40;

   // Evaluate the net move from the oldest of the last five ticks still inside 200 ms
   // that was definitely on the approach side of this particular line.
   for(int i=0; i<g_tick_history_count; i++)
     {
      long elapsed = current_time_msc - g_tick_time_history[i];
      if(elapsed < 0 || elapsed > 200)
         continue;
      if(ComparePriceToLevel(g_tick_price_history[i],line_price) != previous_side)
         continue;
      double displacement = MathAbs(current_price - g_tick_price_history[i]);
      double velocity = displacement / MathMax(0.001,(double)elapsed / 1000.0);
      if(displacement >= required_jump && velocity >= required_jump / 0.2)
         return true;
      break;
     }

   long single_tick_elapsed = current_time_msc - previous_tick_time_msc;
   if(previous_tick_price > 0.0 && single_tick_elapsed >= 0 && single_tick_elapsed <= 200 &&
      MathAbs(current_price - previous_tick_price) >= required_jump)
      return true;
   return false;
  }

int ProcessLineCross(const bool is_up,const int index,const int previous_state,
                     const int now_side,const double price,const double previous_tick_price,
                     const long previous_tick_time_msc,const long current_time_msc)
  {
   int line_code = (is_up ? index : -index);
   int spring_side = (is_up ? g_up_spring_side[index] : g_down_spring_side[index]);
   AddGridLineHeat(line_code);

   if(previous_state == 2)
     {
      if(spring_side == 0)
         return now_side;
      if(now_side == spring_side)
         return 2; // Still beyond the line; wait for the true return crossing.
      if(is_up)
         g_up_spring_side[index] = 0;
      else
         g_down_spring_side[index] = 0;
      HandleGridCross(is_up,index,now_side,price);
      return now_side;
     }

   double line_price = GridLevelPrice(is_up,index);
   bool ballistic = IsBallisticCross(line_price,previous_state,previous_tick_price,
                                      previous_tick_time_msc,price,current_time_msc);
   bool reverse_mode = ReverseModeForGridLine(line_code);
   if(ballistic && reverse_mode)
     {
      if(is_up)
         g_up_spring_side[index] = now_side;
      else
         g_down_spring_side[index] = now_side;
      g_last_action = StringFormat("Balistik geçiş: %s%d yay kuruldu; geri kesiş bekleniyor",
                                   (is_up ? "U_" : "D_"),index);
      return 2;
     }

   HandleGridCross(is_up,index,now_side,price);
   return now_side;
  }

void ProcessGridCrosses(const double price,const double previous_tick_price,
                        const long previous_tick_time_msc,const long current_time_msc)
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
      if(previous == 0)
        {
         g_up_state[i] = now_side;
         continue;
        }
      if(previous == 2)
        {
         if(g_up_spring_side[i] != 0 && now_side != g_up_spring_side[i])
            g_up_state[i] = ProcessLineCross(true,i,previous,now_side,price,
                                              previous_tick_price,previous_tick_time_msc,current_time_msc);
         continue;
        }
      if(now_side != previous)
         g_up_state[i] = ProcessLineCross(true,i,previous,now_side,price,
                                           previous_tick_price,previous_tick_time_msc,current_time_msc);
     }

   for(int i=g_down_count; i>=1; i--)
     {
      int now_side = ComparePriceToLevel(price,GridLevelPrice(false,i));
      if(now_side == 0)
         continue;
      int previous = g_down_state[i];
      if(previous == 0)
        {
         g_down_state[i] = now_side;
         continue;
        }
      if(previous == 2)
        {
         if(g_down_spring_side[i] != 0 && now_side != g_down_spring_side[i])
            g_down_state[i] = ProcessLineCross(false,i,previous,now_side,price,
                                                previous_tick_price,previous_tick_time_msc,current_time_msc);
         continue;
        }
      if(now_side != previous)
         g_down_state[i] = ProcessLineCross(false,i,previous,now_side,price,
                                             previous_tick_price,previous_tick_time_msc,current_time_msc);
     }
  }

//+------------------------------------------------------------------+
//| Open position management                                         |
//+------------------------------------------------------------------+
bool CloseSymbioticPartial(const ulong ticket,const double requested_volume)
  {
   if(!SelectOurPosition(ticket) || requested_volume <= 0.0)
      return false;
   double current_volume = PositionGetDouble(POSITION_VOLUME);
   double min_volume = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double volume_step = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(min_volume <= 0.0 || volume_step <= 0.0 ||
      requested_volume < min_volume - 1.0e-10 ||
      requested_volume >= current_volume - 1.0e-10)
      return false;

   bool sent = trade.PositionClosePartial(ticket,requested_volume,InpDeviationPoints);
   if(!TradeRetcodeOK(sent))
     {
      PrintFormat("Sembiyotik kısmi kapama başarısız ticket=%I64u lot=%.8f retcode=%u (%s)",
                  ticket,requested_volume,trade.ResultRetcode(),trade.ResultRetcodeDescription());
      return false;
     }
   PrintFormat("Sembiyotik katman: ticket=%I64u lot=%.8f kısmi kapatıldı",ticket,requested_volume);
   return true;
  }

void ManageSymbioticPairs(const MqlTick &tick)
  {
   if(!InpEnableSymbioticLayering || InpSymbioticMaxCloseFraction <= 0.0)
      return;

   ulong best_fresh_ticket = 0;
   ulong best_sick_ticket = 0;
   long best_fresh_time = -1;
   long best_sick_time = 0;
   double best_sick_loss = 0.0;

   for(int p=PositionsTotal()-1; p>=0; p--)
     {
      ulong fresh_ticket = PositionGetTicket(p);
      if(fresh_ticket == 0 || !SelectOurPosition(fresh_ticket))
         continue;
      int side = SideFromPositionType(PositionGetInteger(POSITION_TYPE));
      long fresh_time = PositionGetInteger(POSITION_TIME_MSC);
      double fresh_entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double fresh_profit = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      double fresh_step = g_grid_step;
      int fresh_tp = InpTakeProfitGrids;
      int fresh_sl = InpStopLossGrids;
      GetPositionGridSettings(fresh_ticket,fresh_step,fresh_tp,fresh_sl);
      if(!SelectOurPosition(fresh_ticket) || fresh_step <= 0.0 || fresh_time <= 0 || fresh_profit <= 0.0)
         continue;
      fresh_entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double close_price = (side > 0 ? tick.bid : tick.ask);
      double profit_grids = (side > 0 ? close_price - fresh_entry : fresh_entry - close_price) / fresh_step;
      if(profit_grids + 1.0e-8 < InpSymbioticProfitGrids)
         continue;

      ulong sick_for_fresh = 0;
      long sick_time_for_fresh = 0;
      double sick_loss_for_fresh = 0.0;
      for(int q=PositionsTotal()-1; q>=0; q--)
        {
         ulong sick_ticket = PositionGetTicket(q);
         if(sick_ticket == 0 || sick_ticket == fresh_ticket || !SelectOurPosition(sick_ticket))
            continue;
         if(SideFromPositionType(PositionGetInteger(POSITION_TYPE)) != side)
            continue;
         long sick_time = PositionGetInteger(POSITION_TIME_MSC);
         double sick_entry = PositionGetDouble(POSITION_PRICE_OPEN);
         double sick_net = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
         double sick_volume = PositionGetDouble(POSITION_VOLUME);
         if(sick_time <= 0 || sick_time >= fresh_time || sick_net >= 0.0 || sick_volume <= 0.0)
            continue;
         bool better_entry = (side > 0 ? fresh_entry < sick_entry : fresh_entry > sick_entry);
         if(!better_entry)
            continue;

         double sick_step = g_grid_step;
         int sick_tp = InpTakeProfitGrids;
         int sick_sl = InpStopLossGrids;
         GetPositionGridSettings(sick_ticket,sick_step,sick_tp,sick_sl);
         if(!SelectOurPosition(sick_ticket) || sick_step <= 0.0)
            continue;
         double sick_stop = PositionStopLoss(sick_entry,side,sick_step,sick_sl);
         bool sick_stop_hit = (side > 0 ? tick.bid <= sick_stop : tick.ask >= sick_stop);
         if(sick_stop_hit)
            continue;

         double sick_loss = -sick_net;
         if(sick_for_fresh == 0 || sick_time < sick_time_for_fresh ||
            (sick_time == sick_time_for_fresh && sick_loss > sick_loss_for_fresh))
           {
            sick_for_fresh = sick_ticket;
            sick_time_for_fresh = sick_time;
            sick_loss_for_fresh = sick_loss;
           }
        }

      if(sick_for_fresh > 0 && fresh_time > best_fresh_time)
        {
         best_fresh_ticket = fresh_ticket;
         best_sick_ticket = sick_for_fresh;
         best_fresh_time = fresh_time;
         best_sick_time = sick_time_for_fresh;
         best_sick_loss = sick_loss_for_fresh;
        }
     }

   if(best_fresh_ticket == 0 || best_sick_ticket == 0)
      return;
   if(!SelectOurPosition(best_fresh_ticket))
      return;
   double fresh_profit_budget = MathMax(0.0,PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP));
   if(fresh_profit_budget <= 0.0)
      return;
   int fresh_side = SideFromPositionType(PositionGetInteger(POSITION_TYPE));
   double fresh_entry_price = PositionGetDouble(POSITION_PRICE_OPEN);
   double fresh_step_value = g_grid_step;
   int fresh_tp_value = InpTakeProfitGrids;
   int fresh_sl_value = InpStopLossGrids;
   GetPositionGridSettings(best_fresh_ticket,fresh_step_value,fresh_tp_value,fresh_sl_value);
   if(!SelectOurPosition(best_fresh_ticket) || fresh_step_value <= 0.0)
      return;
   double current_close = (fresh_side > 0 ? tick.bid : tick.ask);
   double current_profit_grids = (fresh_side > 0 ? current_close - fresh_entry_price : fresh_entry_price - current_close) /
                                 fresh_step_value;
   if(current_profit_grids + 1.0e-8 < InpSymbioticProfitGrids)
      return;

   if(!SelectOurPosition(best_sick_ticket))
      return;
   double sick_volume = PositionGetDouble(POSITION_VOLUME);
   double sick_net_loss = -(PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP));
   if(sick_volume <= 0.0 || sick_net_loss <= 0.0)
      return;
   double volume_step = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double min_volume = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   if(volume_step <= 0.0 || min_volume <= 0.0)
      return;

   double loss_per_lot = sick_net_loss / sick_volume;
   double fraction_cap = MathMin(0.50,InpSymbioticMaxCloseFraction);
   double affordable_volume = fresh_profit_budget / loss_per_lot;
   double requested_partial = MathMin(sick_volume * fraction_cap,affordable_volume);
   requested_partial = MathFloor(requested_partial / volume_step + 1.0e-10) * volume_step;
   requested_partial = NormalizeDouble(requested_partial,8);
   if(requested_partial >= sick_volume - min_volume + 1.0e-10)
      requested_partial = MathFloor((sick_volume - min_volume) / volume_step + 1.0e-10) * volume_step;
   bool close_sick_fully = false;
   if(requested_partial < min_volume - 1.0e-10)
     {
      // With broker steps such as 0.01 lot, half of a 0.01-lot position is not tradable.
      // Close it fully only when the fresh position's profit can cover the whole loss.
      if(fresh_profit_budget + 1.0e-8 >= sick_net_loss)
        {
         requested_partial = sick_volume;
         close_sick_fully = true;
        }
      else
         requested_partial = 0.0;
     }

   string reason = StringFormat("Sembiyotik kâr kilidi: %.2f grid; eski ticket=%I64u",current_profit_grids,best_sick_ticket);
   if(!CloseOurPosition(best_fresh_ticket,reason))
      return;
   if(close_sick_fully)
      CloseOurPosition(best_sick_ticket,"Sembiyotik sübvansiyon: yeni işlem kârı tam zararı karşıladı");
   else if(requested_partial > 0.0)
      CloseSymbioticPartial(best_sick_ticket,requested_partial);
   string subsidy_mode = (close_sick_fully ? "eski pozisyon tam kapandı" :
                          (requested_partial > 0.0 ? "eski pozisyon kısmi kapandı" : "eski pozisyon korunuyor"));
   g_last_action = StringFormat("Sembiyotik katman: yeni ticket kapandı, %s ticket=%I64u lot=%.8f",
                                subsidy_mode,best_sick_ticket,requested_partial);
   PrintFormat("Sembiyotik çift çözüldü: fresh=%I64u sick=%I64u sickOpenMs=%I64d önceki zarar=%.2f, %s lot=%.8f",
               best_fresh_ticket,best_sick_ticket,best_sick_time,best_sick_loss,subsidy_mode,requested_partial);
  }

bool HasEligibleSymbioticSickPartner(const ulong fresh_ticket,const MqlTick &tick)
  {
   if(!InpEnableSymbioticLayering || !SelectOurPosition(fresh_ticket))
      return false;
   int side = SideFromPositionType(PositionGetInteger(POSITION_TYPE));
   long fresh_time = PositionGetInteger(POSITION_TIME_MSC);
   double fresh_entry = PositionGetDouble(POSITION_PRICE_OPEN);
   double fresh_net = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
   if(fresh_time <= 0 || fresh_net <= 0.0)
      return false;

   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong sick_ticket = PositionGetTicket(i);
      if(sick_ticket == 0 || sick_ticket == fresh_ticket || !SelectOurPosition(sick_ticket))
         continue;
      if(SideFromPositionType(PositionGetInteger(POSITION_TYPE)) != side)
         continue;
      long sick_time = PositionGetInteger(POSITION_TIME_MSC);
      double sick_entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double sick_net = PositionGetDouble(POSITION_PROFIT) + PositionGetDouble(POSITION_SWAP);
      if(sick_time <= 0 || sick_time >= fresh_time || sick_net >= 0.0)
         continue;
      bool better_entry = (side > 0 ? fresh_entry < sick_entry : fresh_entry > sick_entry);
      if(!better_entry)
         continue;

      double sick_step = g_grid_step;
      int sick_tp = InpTakeProfitGrids;
      int sick_sl = InpStopLossGrids;
      GetPositionGridSettings(sick_ticket,sick_step,sick_tp,sick_sl);
      if(!SelectOurPosition(sick_ticket) || sick_step <= 0.0)
         continue;
      double sick_stop = PositionStopLoss(sick_entry,side,sick_step,sick_sl);
      bool stop_hit = (side > 0 ? tick.bid <= sick_stop : tick.ask >= sick_stop);
      if(!stop_hit)
         return true;
     }
   return false;
  }

void ManageOpenPositions(const MqlTick &tick)
  {
   ManageSymbioticPairs(tick);
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
      double volume = PositionGetDouble(POSITION_VOLUME);
      long open_time_msc = PositionGetInteger(POSITION_TIME_MSC);
      int line_code = PositionLineCode(ticket);
      double step = g_grid_step;
      int tp_grids = InpTakeProfitGrids;
      int sl_grids = InpStopLossGrids;
      GetPositionGridSettings(ticket,step,tp_grids,sl_grids);
      if(!SelectOurPosition(ticket) || step <= 0.0 || entry <= 0.0)
         continue;

      double target = PositionTakeProfit(entry,side,step,tp_grids);
      double stop = PositionStopLoss(entry,side,step,sl_grids);
      // Use executable close prices: Bid closes LONG; Ask closes SHORT.
      double close_price = (side > 0 ? tick.bid : tick.ask);
      bool tp_hit = (side > 0 ? close_price >= target : close_price <= target);
      bool sl_hit = (side > 0 ? close_price <= stop : close_price >= stop);

      if(tp_hit)
        {
         bool waiting_for_symbiotic_pair =
            (InpEnableSymbioticLayering && (double)tp_grids < InpSymbioticProfitGrids &&
             HasEligibleSymbioticSickPartner(ticket,tick));
         if(!waiting_for_symbiotic_pair)
           {
            if(CloseOurPosition(ticket,StringFormat("TP (%d grid)",tp_grids)))
              {
               RecordTakeProfitPrice(target,volume);
               RecordSuccessfulGridTP(line_code,open_time_msc,CurrentTimeMsc());
              }
            continue;
           }
         g_last_action = StringFormat("Pozisyon TP seviyesinde; sembiyotik çift için %.2f grid bekleniyor",
                                      InpSymbioticProfitGrids);
        }
      if(sl_hit)
        {
         if(CloseOurPosition(ticket,StringFormat("SL (%d grid)",sl_grids)))
            PoisonGridLineAfterSL(line_code);
         continue;
        }

      ModifyPositionProtection(ticket,side,entry,step,tp_grids,sl_grids);
     }
  }

void CoolGridHeatOnNewM1()
  {
   if(!InpEnableGridFatigue)
      return;
   datetime current_bar = iTime(_Symbol,PERIOD_M1,0);
   if(current_bar <= 0)
      return;
   if(g_last_heat_bar_time <= 0)
     {
      g_last_heat_bar_time = current_bar;
      return;
     }
   if(current_bar <= g_last_heat_bar_time)
      return;

   int elapsed_bars = (int)((current_bar - g_last_heat_bar_time) / 60);
   if(elapsed_bars < 1)
      elapsed_bars = 1;
   double retention = 1.0 - InpGridHeatDecayPerM1 / 100.0;
   double factor = MathPow(retention,(double)elapsed_bars);
   for(int i=1; i<=g_up_count; i++)
     {
      double cooled = g_up_heat[i] * factor;
      if(cooled < 0.01)
         cooled = 0.0;
      if(MathAbs(cooled - g_up_heat[i]) > 1.0e-8)
         SetGridLineHeat(i,cooled);
      if(g_up_poisoned[i] != 0 && cooled < InpGridHeatReverseThreshold)
         SetGridLinePoisoned(i,false);
     }
   for(int i=1; i<=g_down_count; i++)
     {
      double cooled = g_down_heat[i] * factor;
      if(cooled < 0.01)
         cooled = 0.0;
      if(MathAbs(cooled - g_down_heat[i]) > 1.0e-8)
         SetGridLineHeat(-i,cooled);
      if(g_down_poisoned[i] != 0 && cooled < InpGridHeatReverseThreshold)
         SetGridLinePoisoned(-i,false);
     }
   g_last_heat_bar_time = current_bar;
  }

void RefreshGridEpochIfDue()
  {
   datetime now = TimeCurrent();
   if(now <= 0)
      return;
   if(g_last_epoch_recalculation <= 0)
     {
      g_last_epoch_recalculation = now;
      return;
     }
   if(now < g_last_epoch_recalculation)
     {
      g_last_epoch_recalculation = now;
      return;
     }
   if(now - g_last_epoch_recalculation < InpGridEpochMinutes * 60)
      return;
   g_last_epoch_recalculation = now;

   double new_step = 0.0;
   double median_range = 0.0;
   double min_step = 0.0;
   if(!CalculateInitialGridStep(new_step,median_range,min_step))
      return;
   if(g_grid_step <= 0.0 || new_step <= 0.0)
      return;
   double relative_change = MathAbs(new_step - g_grid_step) / g_grid_step;
   if(relative_change + 1.0e-10 < InpGridEpochDeviation)
      return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return;
   double current_price = MidPrice(tick);
   if(current_price <= 0.0 || new_step * InpStopLossGrids >= current_price * 0.90)
     {
      Print("Epoch grid güncellemesi güvenlik sınırını aştı; mevcut grid korunuyor.");
      return;
     }

   double old_step = g_grid_step;
   g_grid_step = new_step;
   ReflowGridPricesForEpoch(current_price); // Anchored occupied lines and all position settings stay intact.
   if(!MQLInfoInteger(MQL_TESTER))
     {
      GlobalVariableSet(GridStateKey("BASE"),g_grid_base);
      GlobalVariableSet(GridStateKey("STEP"),g_grid_step);
     }
   g_last_action = StringFormat("Epoch grid akordeon: adım %.1f%% değişti",relative_change * 100.0);
   PrintFormat("Yeni 15-dakika epoch grid: median M1=%.*f min=%.*f step %.*f -> %.*f (değişim %.1f%%); açık pozisyon GS değerleri korunuyor.",
               _Digits,median_range,_Digits,min_step,_Digits,old_step,_Digits,g_grid_step,relative_change * 100.0);
  }

void UpdateStressMetrics(const long now_msc)
  {
   if(now_msc <= 0)
      return;
   if(g_last_stress_time_msc <= 0)
     {
      g_last_stress_time_msc = now_msc;
      return;
     }
   if(now_msc <= g_last_stress_time_msc)
      return;
   double elapsed_seconds = (double)(now_msc - g_last_stress_time_msc) / 1000.0;
   bool has_our_positions = (CountOurPositions(0) > 0);
   bool underwater = (has_our_positions &&
                      AccountInfoDouble(ACCOUNT_EQUITY) < AccountInfoDouble(ACCOUNT_BALANCE) - 1.0e-8);
   if(underwater)
      g_underwater_episode_seconds += elapsed_seconds;
   else if(g_underwater_episode_seconds > 0.0)
     {
      g_underwater_seconds_squared += g_underwater_episode_seconds * g_underwater_episode_seconds;
      g_underwater_episode_seconds = 0.0;
     }
   g_last_stress_time_msc = now_msc;
  }

//+------------------------------------------------------------------+
//| Status and standard MT5 events                                   |
//+------------------------------------------------------------------+
void UpdateChartStatus()
  {
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
   string signal_type = (InpSignalCandleMode == SIGNAL_HEIKEN_ASHI ? "HA" : "normal");
   string trading_status = "İşlem saat filtresi: kapalı";
   if(InpEnableTradingHours)
     {
      datetime turkey_time = CurrentTurkeyTime();
      string local_clock = (turkey_time > 0 ? TimeToString(turkey_time,TIME_MINUTES) : "--:--");
      trading_status = StringFormat("Türkiye saati %s | pencere %s | %s",
                                    local_clock,TradingHoursWindowText(),
                                    (IsWithinTradingHours(turkey_time) ? "işlem açık" : "işlem kapalı"));
     }
   string target_status = "Özsermaye hedefi: kapalı";
   if(InpCloseAllAtEquityGain > 0.0)
     {
      double equity_gain = AccountInfoDouble(ACCOUNT_EQUITY) - g_profit_target_start_equity;
      target_status = StringFormat("Özsermaye hedefi: %.2f / %.2f %s%s",
                                   equity_gain,InpCloseAllAtEquityGain,
                                   AccountInfoString(ACCOUNT_CURRENCY),
                                   (g_profit_target_liquidating ? " (pozisyonlar kapatılıyor)" : ""));
     }

   Comment("M1 Auto Grid HA v1.05\n",
           "Sembol: ",_Symbol," | Mum yönü: ",signal_type," ",EnumToString(InpSignalTimeframe)," ",SideName(g_signal_side),
           " | morfoloji: ",DoubleToString(g_signal_score,2),"\n",
           "İşlem yönü: ",SideName(TradeSideForSignal(g_signal_side)),
           (GlobalReverseModeActive() ? " (ters yön etkin)" : ""),"\n",
           trading_status,"\n",
           "Grid base: ",DoubleToString(g_grid_base,_Digits)," | anlık: ",DoubleToString(current_price,_Digits),"\n",
           "Epoch adımı: ",DoubleToString(g_grid_step,_Digits)," (",DoubleToString(step_points,1)," point / ",
           DoubleToString(step_pips,2)," pip) | varsayılan TP ",
           IntegerToString(InpTakeProfitGrids)," / SL ",IntegerToString(InpStopLossGrids)," grid\n",
           "Pozisyon LONG/SHORT: ",IntegerToString(long_count)," / ",IntegerToString(short_count),
           " | Sınır/yan: ",IntegerToString(InpMaxLayersPerSide),"\n",
           "Isı/epoch: ", (InpEnableGridFatigue ? "aktif" : "kapalı")," / ",IntegerToString(InpGridEpochMinutes)," dk",
           " | symbiotic: ",(InpEnableSymbioticLayering ? "aktif" : "kapalı"),"\n",
           target_status,"\n",
           "Durum: ",g_last_action);
  }

ENUM_TIMEFRAMES CandleModeTimeframe()
  {
   if(InpCandleModeTimeframe == PERIOD_CURRENT)
      return (ENUM_TIMEFRAMES)_Period;
   return InpCandleModeTimeframe;
  }

string CandleModeWindowText()
  {
   return StringFormat("%02d:%02d-%02d:%02d",InpCandleModeStartHour,InpCandleModeStartMinute,
                       InpCandleModeEndHour,InpCandleModeEndMinute);
  }

bool IsCandleModePosition(const ulong ticket)
  {
   if(ticket == 0 || !PositionSelectByTicket(ticket))
      return false;
   return (PositionGetString(POSITION_SYMBOL) == _Symbol &&
           (ulong)PositionGetInteger(POSITION_MAGIC) == InpCandleModeMagicNumber);
  }

int CountCandleModePositions(const int side_filter=0)
  {
   int count = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsCandleModePosition(ticket))
         continue;
      int side = SideFromPositionType(PositionGetInteger(POSITION_TYPE));
      if(side_filter == 0 || side == side_filter)
         count++;
     }
   return count;
  }

void CloseCandleModePosition(const ulong ticket,const string reason)
  {
   if(!IsCandleModePosition(ticket))
      return;
   bool sent = trade.PositionClose(ticket,InpCandleModeDeviationPoints);
   if(!TradeRetcodeOK(sent))
     {
      PrintFormat("Mum modu pozisyon kapatılamadı ticket=%I64u neden=%s retcode=%u (%s)",
                  ticket,reason,trade.ResultRetcode(),trade.ResultRetcodeDescription());
      g_candle_mode_last_action = StringFormat("Kapatma başarısız ticket=%I64u (%s)",ticket,reason);
      return;
     }
   PrintFormat("Mum modu pozisyon kapatıldı ticket=%I64u neden=%s",ticket,reason);
   g_candle_mode_last_action = StringFormat("Pozisyon kapatıldı: %s",reason);
  }

void CloseAllCandleModePositions(const string reason)
  {
   ulong tickets[];
   ArrayResize(tickets,0);
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsCandleModePosition(ticket))
         continue;
      int n = ArraySize(tickets);
      if(ArrayResize(tickets,n + 1) >= n + 1)
         tickets[n] = ticket;
     }
   for(int i=0; i<ArraySize(tickets); i++)
      CloseCandleModePosition(tickets[i],reason);
  }

double CandleModeOrderVolume()
  {
   double min_volume = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double max_volume = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double volume_step = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(min_volume <= 0.0 || volume_step <= 0.0)
      return 0.0;
   if(InpCandleModeUseBrokerMinimumVolume)
      return min_volume;

   double requested = InpCandleModeFixedLots;
   if(requested <= 0.0)
      return 0.0;
   if(max_volume > 0.0 && requested > max_volume)
      requested = max_volume;
   double volume = NormalizeDouble(MathFloor(requested / volume_step + 1.0e-10) * volume_step,8);
   if(volume + 1.0e-10 < min_volume)
     {
      PrintFormat("Mum modu lot atlandı: %.8f broker minimum lotu %.8f altında.",requested,min_volume);
      return 0.0;
     }
   return volume;
  }

int CandleModeColor(const double open_price,const double close_price)
  {
   if(close_price > open_price)
      return 1;
   if(close_price < open_price)
      return -1;
   return 0; // Doji: no direction and does not count toward TP/SL.
  }

void CandleModeCopyRate(const MqlRates &source,MqlRates &destination)
  {
   destination.time = source.time;
   destination.open = source.open;
   destination.high = source.high;
   destination.low = source.low;
   destination.close = source.close;
   destination.tick_volume = source.tick_volume;
   destination.spread = source.spread;
   destination.real_volume = source.real_volume;
  }

bool CandleModeReadClosedBar(MqlRates &bar_out,int &color_out)
  {
   color_out = 0;
   ENUM_TIMEFRAMES timeframe = CandleModeTimeframe();
   if(InpCandleModeCandleType == SIGNAL_STANDARD_CANDLE)
     {
      MqlRates rates[];
      ArraySetAsSeries(rates,true);
      int copied = CopyRates(_Symbol,timeframe,1,1,rates);
      if(copied != 1)
         return false;
      CandleModeCopyRate(rates[0],bar_out);
      color_out = CandleModeColor(bar_out.open,bar_out.close);
      return true;
     }

   int history_count = InpCandleModeHACalculationBars;
   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   int copied = CopyRates(_Symbol,timeframe,0,history_count,rates);
   if(copied < history_count)
      return false;

   double previous_ha_open = 0.0;
   double previous_ha_close = 0.0;
   bool found = false;
   for(int i=copied-1; i>=0; i--)
     {
      double ha_close = (rates[i].open + rates[i].high + rates[i].low + rates[i].close) / 4.0;
      double ha_open;
      if(i == copied-1)
         ha_open = (rates[i].open + rates[i].close) * 0.5;
      else
         ha_open = (previous_ha_open + previous_ha_close) * 0.5;
      if(i == 1)
        {
         CandleModeCopyRate(rates[i],bar_out);
         color_out = CandleModeColor(ha_open,ha_close);
         found = true;
        }
      previous_ha_open = ha_open;
      previous_ha_close = ha_close;
     }
   return found;
  }

int CandleModeExitCondition(const int side,const int green_count,const int red_count)
  {
   int favorable_count = (side > 0 ? green_count : red_count);
   int adverse_count = (side > 0 ? red_count : green_count);
   if(adverse_count >= InpCandleModeStopLossCandles)
      return -1;
   if(favorable_count >= InpCandleModeTakeProfitCandles)
      return 1;
   return 0;
  }

bool CandleModeCountColorsSinceEntry(const datetime position_open_time,const int side,
                                     int &green_count,int &red_count,int &exit_condition)
  {
   green_count = 0;
   red_count = 0;
   exit_condition = 0;
   if(position_open_time <= 0)
      return false;

   ENUM_TIMEFRAMES timeframe = CandleModeTimeframe();
   int entry_shift = iBarShift(_Symbol,timeframe,position_open_time,false);
   if(entry_shift < 0)
      return false;
   if(entry_shift == 0)
      return true; // The entry candle has not closed yet.

   int available_bars = Bars(_Symbol,timeframe);
   if(available_bars <= entry_shift)
      return false;
   int request_count = entry_shift;
   if(InpCandleModeCandleType == SIGNAL_HEIKEN_ASHI)
     {
      long wanted = (long)entry_shift + (long)InpCandleModeHACalculationBars;
      int max_history = available_bars - 1; // CopyRates starts at shift 1.
      if(wanted > max_history)
         wanted = max_history;
      if(wanted < entry_shift)
         return false;
      request_count = (int)wanted;
     }

   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   int copied = CopyRates(_Symbol,timeframe,1,request_count,rates);
   if(copied < entry_shift)
      return false;

   if(InpCandleModeCandleType == SIGNAL_STANDARD_CANDLE)
     {
      // Walk from the oldest candle forward so the first TP/SL threshold is preserved after restart.
      for(int i=copied-1; i>=0; i--)
        {
         int shift = i + 1;
         if(shift > entry_shift)
            continue;
         int bar_color = CandleModeColor(rates[i].open,rates[i].close);
         if(bar_color > 0)
            green_count++;
         else if(bar_color < 0)
            red_count++;
         exit_condition = CandleModeExitCondition(side,green_count,red_count);
         if(exit_condition != 0)
            return true;
        }
      return true;
     }

   double previous_ha_open = 0.0;
   double previous_ha_close = 0.0;
   for(int i=copied-1; i>=0; i--)
     {
      double ha_close = (rates[i].open + rates[i].high + rates[i].low + rates[i].close) / 4.0;
      double ha_open;
      if(i == copied-1)
         ha_open = (rates[i].open + rates[i].close) * 0.5;
      else
         ha_open = (previous_ha_open + previous_ha_close) * 0.5;
      int shift = i + 1;
      if(shift <= entry_shift)
        {
         int bar_color = CandleModeColor(ha_open,ha_close);
         if(bar_color > 0)
            green_count++;
         else if(bar_color < 0)
            red_count++;
         exit_condition = CandleModeExitCondition(side,green_count,red_count);
         if(exit_condition != 0)
            return true;
        }
      previous_ha_open = ha_open;
      previous_ha_close = ha_close;
     }
   return true;
  }

void CandleModeManageOpenPositions()
  {
   ulong tickets[];
   ArrayResize(tickets,0);
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !IsCandleModePosition(ticket))
         continue;
      int n = ArraySize(tickets);
      if(ArrayResize(tickets,n + 1) >= n + 1)
         tickets[n] = ticket;
     }

   for(int i=0; i<ArraySize(tickets); i++)
     {
      ulong ticket = tickets[i];
      if(!IsCandleModePosition(ticket))
         continue;
      int side = SideFromPositionType(PositionGetInteger(POSITION_TYPE));
      datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
      int green_count = 0;
      int red_count = 0;
      int exit_condition = 0;
      if(!CandleModeCountColorsSinceEntry(open_time,side,green_count,red_count,exit_condition))
        {
         g_candle_mode_last_action = StringFormat("Mum geçmişi bekleniyor: ticket=%I64u",ticket);
         continue;
        }

      if(exit_condition < 0)
         CloseCandleModePosition(ticket,StringFormat("SL: %d ters renkli mum",
                                                     (side > 0 ? red_count : green_count)));
      else if(exit_condition > 0)
         CloseCandleModePosition(ticket,StringFormat("TP: %d uygun renkli mum",
                                                     (side > 0 ? green_count : red_count)));
     }
  }

void CandleModeOpenPosition(const int candle_color,const datetime signal_bar_time)
  {
   if(candle_color == 0)
      return;
   int side = (InpCandleModeReverseDirection ? -candle_color : candle_color);
   if(InpCandleModeMaxTotalPositions > 0 &&
      CountCandleModePositions(0) >= InpCandleModeMaxTotalPositions)
     {
      g_candle_mode_last_action = "Mum modu: toplam pozisyon sınırına ulaşıldı";
      return;
     }
   if(InpCandleModeMaxPositionsPerSide > 0 &&
      CountCandleModePositions(side) >= InpCandleModeMaxPositionsPerSide)
     {
      g_candle_mode_last_action = StringFormat("Mum modu: %s pozisyon sınırına ulaşıldı",SideName(side));
      return;
     }

   double volume = CandleModeOrderVolume();
   if(volume <= 0.0)
     {
      g_candle_mode_last_action = "Mum modu: geçerli lot bulunamadı";
      return;
     }
   string candle_name = (candle_color > 0 ? "green" : "red");
   string side_name = (side > 0 ? "BUY" : "SELL");
   string comment = StringFormat("CNDL_%s_%I64d",side_name,(long)signal_bar_time);
   bool sent = (side > 0 ? trade.Buy(volume,_Symbol,0.0,0.0,0.0,comment) :
                           trade.Sell(volume,_Symbol,0.0,0.0,0.0,comment));
   if(!TradeRetcodeOK(sent))
     {
      PrintFormat("Mum modu %s sinyalinde %s açılamadı lot=%.8f retcode=%u (%s)",
                  candle_name,side_name,volume,trade.ResultRetcode(),trade.ResultRetcodeDescription());
      g_candle_mode_last_action = StringFormat("%s sinyalinde giriş başarısız",candle_name);
      return;
     }
   g_candle_mode_last_action = StringFormat("%s mum -> %s açıldı (%.2f lot)",candle_name,side_name,volume);
   PrintFormat("Mum modu giriş: %s mum, %s, lot=%.8f, mum=%s; TP=%d uygun renk/SL=%d ters renk mum",
               candle_name,side_name,volume,TimeToString(signal_bar_time,TIME_DATE|TIME_MINUTES),
               InpCandleModeTakeProfitCandles,InpCandleModeStopLossCandles);
  }

bool HandleCandleModeTradingHours()
  {
   if(!InpCandleModeEnableTradingHours)
      return false;

   datetime turkey_time = CurrentCandleModeTurkeyTime();
   bool allowed = IsWithinCandleModeTradingHours(turkey_time);
   if(!allowed)
     {
      if(!g_candle_mode_was_outside_hours)
        {
         string local_clock = (turkey_time > 0 ? TimeToString(turkey_time,TIME_MINUTES) : "--:--");
         PrintFormat("Mum modu Türkiye işlem penceresi dışında: saat=%s pencere=%s; mum modu pozisyonları kapatılıyor.",
                     local_clock,CandleModeWindowText());
        }
      g_candle_mode_was_outside_hours = true;
      datetime server_now = TimeCurrent();
      if(CountCandleModePositions(0) > 0 &&
         (g_candle_mode_last_close_attempt <= 0 || server_now <= 0 ||
          server_now < g_candle_mode_last_close_attempt ||
          server_now - g_candle_mode_last_close_attempt >= 5))
        {
         CloseAllCandleModePositions("Türkiye işlem saati dışında");
         g_candle_mode_last_close_attempt = server_now;
        }
      int remaining = CountCandleModePositions(0);
      if(remaining > 0)
         g_candle_mode_last_action = StringFormat("Saat filtresi: %d mum modu pozisyonu kapanmayı bekliyor",remaining);
      else
         g_candle_mode_last_action = StringFormat("Saat filtresi: Türkiye %s, %s dışında; beklemede",
                                                  (turkey_time > 0 ? TimeToString(turkey_time,TIME_MINUTES) : "--:--"),
                                                  CandleModeWindowText());
      return true;
     }

   if(g_candle_mode_was_outside_hours)
     {
      if(CountCandleModePositions(0) > 0)
        {
         datetime server_now = TimeCurrent();
         if(g_candle_mode_last_close_attempt <= 0 || server_now <= 0 ||
            server_now < g_candle_mode_last_close_attempt ||
            server_now - g_candle_mode_last_close_attempt >= 5)
           {
            CloseAllCandleModePositions("Seans açıldı; önce kalan mum modu pozisyonlarını kapat");
            g_candle_mode_last_close_attempt = server_now;
           }
        }
      int remaining = CountCandleModePositions(0);
      if(remaining > 0)
        {
         g_candle_mode_last_action = StringFormat("Seans açıldı ancak %d eski pozisyon kapanmadı; giriş bekletiliyor",remaining);
         return true;
        }

      g_candle_mode_was_outside_hours = false;
      g_candle_mode_last_close_attempt = 0;
      datetime latest_closed_bar = iTime(_Symbol,CandleModeTimeframe(),1);
      if(latest_closed_bar > 0)
         g_candle_mode_last_processed_bar = latest_closed_bar;
      g_candle_mode_last_action = StringFormat("Seans açıldı (%s); sonraki mum kapanışı bekleniyor",
                                               CandleModeWindowText());
      PrintFormat("Mum modu Türkiye işlem penceresi açıldı (%s); sonraki mum kapanışı bekleniyor.",
                  CandleModeWindowText());
     }
   return false;
  }

void UpdateCandleModeChartStatus()
  {
   if(!InpCandleModeShowChartStatus)
     {
      Comment("");
      return;
     }
   int buy_count = CountCandleModePositions(1);
   int sell_count = CountCandleModePositions(-1);
   string candle_type = (InpCandleModeCandleType == SIGNAL_HEIKEN_ASHI ? "Heiken Ashi" : "Standart");
   string trading_status = "saat filtresi kapalı";
   if(InpCandleModeEnableTradingHours)
     {
      datetime turkey_time = CurrentCandleModeTurkeyTime();
      trading_status = StringFormat("Türkiye %s | %s | %s",
                                    (turkey_time > 0 ? TimeToString(turkey_time,TIME_MINUTES) : "--:--"),
                                    CandleModeWindowText(),
                                    (IsWithinCandleModeTradingHours(turkey_time) ? "işlem açık" : "işlem kapalı"));
     }
   Comment("M1 Auto Grid HA v1.05 | ÖZEL MUM MODU\n",
           "Sembol: ",_Symbol," | Mum: ",candle_type," ",EnumToString(CandleModeTimeframe())," | ters yön: ",
           (InpCandleModeReverseDirection ? "açık" : "kapalı"),"\n",
           "TP/SL: ",IntegerToString(InpCandleModeTakeProfitCandles)," uygun / ",
           IntegerToString(InpCandleModeStopLossCandles)," ters renk mum (birikimli)\n",
           trading_status,"\n",
           "BUY/SELL: ",IntegerToString(buy_count)," / ",IntegerToString(sell_count),
           " | limit: ",IntegerToString(InpCandleModeMaxTotalPositions),"\n",
           "Lot: ",DoubleToString(InpCandleModeFixedLots,2)," | Magic: ",
           StringFormat("%I64u",InpCandleModeMagicNumber),"\n",
           "Çıkışlar mum kapanışında yerel yönetilir; broker TP/SL emri kullanılmaz.\n",
           "Durum: ",g_candle_mode_last_action);
  }

int InitializeCandleMode()
  {
   if(PeriodSeconds(CandleModeTimeframe()) <= 0 ||
      InpCandleModeTakeProfitCandles < 1 || InpCandleModeStopLossCandles < 1 ||
      InpCandleModeHACalculationBars < 2 || InpCandleModeHACalculationBars > 20000 ||
      InpCandleModeMaxPositionsPerSide < 0 || InpCandleModeMaxTotalPositions < 0 ||
      InpCandleModeDeviationPoints < 0 || InpCandleModeMagicNumber == 0 ||
      InpCandleModeMagicNumber == InpMagicNumber ||
      (!InpCandleModeUseBrokerMinimumVolume && InpCandleModeFixedLots <= 0.0) ||
      InpCandleModeStartHour < 0 || InpCandleModeStartHour > 23 ||
      InpCandleModeEndHour < 0 || InpCandleModeEndHour > 23 ||
      InpCandleModeStartMinute < 0 || InpCandleModeStartMinute > 59 ||
      InpCandleModeEndMinute < 0 || InpCandleModeEndMinute > 59 ||
      InpCandleModeTesterUtcOffsetWinterHours < -12 || InpCandleModeTesterUtcOffsetWinterHours > 14 ||
      InpCandleModeTesterUtcOffsetSummerHours < -12 || InpCandleModeTesterUtcOffsetSummerHours > 14 ||
      (InpCandleModeCandleType != SIGNAL_HEIKEN_ASHI &&
       InpCandleModeCandleType != SIGNAL_STANDARD_CANDLE))
     {
      Print("Mum modu hatalı girdiler: zaman dilimi, saat, TP/SL, lot, pozisyon sınırları ve Grid'den farklı Magic numarasını kontrol edin.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      Print("Mum modu için hedging hesap gerekir; her mumda ayrı BUY/SELL katmanı açılır.");
      return INIT_FAILED;
     }
   int grid_mode_positions = CountOurPositions(0);
   if(grid_mode_positions > 0)
     {
      PrintFormat("Mum modu başlatılmadı: %d eski grid pozisyonu açık. Candle mode bunları yönetmez; önce kapatın veya grid moduna dönün.",
                  grid_mode_positions);
      return INIT_FAILED;
     }

   trade.SetExpertMagicNumber(InpCandleModeMagicNumber);
   trade.SetDeviationInPoints(InpCandleModeDeviationPoints);
   trade.SetAsyncMode(false);
   trade.SetTypeFillingBySymbol(_Symbol);

   datetime last_closed_bar = iTime(_Symbol,CandleModeTimeframe(),1);
   if(last_closed_bar <= 0)
     {
      MqlRates startup_rates[];
      ArraySetAsSeries(startup_rates,true);
      if(CopyRates(_Symbol,CandleModeTimeframe(),0,2,startup_rates) >= 2)
         last_closed_bar = startup_rates[1].time;
     }
   if(last_closed_bar <= 0)
     {
      Print("Mum modu başlatılamadı: seçilen zaman diliminin kapanmış mum geçmişi yüklenemedi.");
      return INIT_FAILED;
     }
   g_candle_mode_last_processed_bar = last_closed_bar;
   g_candle_mode_last_close_attempt = 0;
   g_candle_mode_was_outside_hours = false;
   g_candle_mode_last_action = "Mum modu hazır; sonraki mum kapanışı bekleniyor";
   EventSetTimer(1);
   PrintFormat("Özel mum modu etkin: %s %s; ters yön=%s; TP=%d uygun renk/SL=%d ters renk mum (birikimli); her renkli kapanışta yeni pozisyon.",
               _Symbol,EnumToString(CandleModeTimeframe()),
               (InpCandleModeReverseDirection ? "açık" : "kapalı"),
               InpCandleModeTakeProfitCandles,InpCandleModeStopLossCandles);
   Print("Mum modu çıkışları mum kapanışında EA tarafından yerel olarak yönetilir; broker sunucusuna fiyat bazlı TP/SL gönderilmez, EA açık kalmalıdır.");
   if(InpCandleModeEnableTradingHours)
      PrintFormat("Mum modu Türkiye işlem saati: %s; tester sunucu UTC offseti kış/yaz=%d/%d (Avrupa DST %s)",
                  CandleModeWindowText(),InpCandleModeTesterUtcOffsetWinterHours,
                  InpCandleModeTesterUtcOffsetSummerHours,
                  (InpCandleModeTesterUsesEuropeanDST ? "açık" : "kapalı"));
   HandleCandleModeTradingHours();
   UpdateCandleModeChartStatus();
   return INIT_SUCCEEDED;
  }

void ProcessCandleModeEvent()
  {
   if(HandleCandleModeTradingHours())
     {
      UpdateCandleModeChartStatus();
      return;
     }

   datetime closed_bar_time = iTime(_Symbol,CandleModeTimeframe(),1);
   if(closed_bar_time <= 0 || closed_bar_time == g_candle_mode_last_processed_bar)
     {
      UpdateCandleModeChartStatus();
      return;
     }
   if(closed_bar_time < g_candle_mode_last_processed_bar)
      g_candle_mode_last_processed_bar = closed_bar_time;

   MqlRates closed_bar;
   int candle_color = 0;
   if(!CandleModeReadClosedBar(closed_bar,candle_color))
     {
      g_candle_mode_last_action = "Kapanmış mum verisi bekleniyor";
      UpdateCandleModeChartStatus();
      return;
     }
   g_candle_mode_last_processed_bar = closed_bar.time;
   CandleModeManageOpenPositions();
   CandleModeOpenPosition(candle_color,closed_bar.time);
   UpdateCandleModeChartStatus();
  }

double OnTester()
  {
   if(InpEnableCandleMode)
     {
      double candle_mode_profit = TesterStatistics(STAT_PROFIT);
      if(!MQLInfoInteger(MQL_OPTIMIZATION))
         PrintFormat("Candle mode tester net profit=%.2f %s; grid tester score disabled.",
                     candle_mode_profit,AccountInfoString(ACCOUNT_CURRENCY));
      return candle_mode_profit;
     }
   double profit = TesterStatistics(STAT_PROFIT);
   double equity_drawdown = TesterStatistics(STAT_EQUITY_DD);
   double initial_deposit = TesterStatistics(STAT_INITIAL_DEPOSIT);
   double trades = TesterStatistics(STAT_TRADES);
   double fitness = profit;
   bool rejected_sample = false;

   if(InpUseRiskAdjustedTesterScore)
     {
      if(InpOptimizationMinTrades > 0 && trades < InpOptimizationMinTrades)
        {
         fitness = -1000000.0 + trades; // Reject small samples so a few lucky trades do not win.
         rejected_sample = true;
        }
      else
        {
         double drawdown_floor = MathMax(initial_deposit * 0.005,0.01);
         fitness = profit / MathMax(equity_drawdown,drawdown_floor);
        }
     }

   long now_msc = CurrentTimeMsc();
   double current_underwater_episode = g_underwater_episode_seconds;
   if(g_last_stress_time_msc > 0 && now_msc > g_last_stress_time_msc &&
      CountOurPositions(0) > 0 &&
      AccountInfoDouble(ACCOUNT_EQUITY) < AccountInfoDouble(ACCOUNT_BALANCE) - 1.0e-8)
      current_underwater_episode += (double)(now_msc - g_last_stress_time_msc) / 1000.0;
   double stress_seconds_squared = g_underwater_seconds_squared +
                                   current_underwater_episode * current_underwater_episode +
                                   g_position_lifetime_seconds_squared;
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      long open_time_msc = PositionGetInteger(POSITION_TIME_MSC);
      if(open_time_msc > 0 && now_msc > open_time_msc)
        {
         double age_seconds = (double)(now_msc - open_time_msc) / 1000.0;
         stress_seconds_squared += age_seconds * age_seconds;
        }
     }
   double stress_equivalent_hours = MathSqrt(MathMax(0.0,stress_seconds_squared)) / 3600.0;
   double stress_factor = 1.0 + MathMax(0.0,InpTesterStressPenaltyStrength) * stress_equivalent_hours;
   if(!rejected_sample && stress_factor > 1.0)
      fitness = (fitness >= 0.0 ? fitness / stress_factor : fitness * stress_factor);

   // In optimization mode, use the Optimization Results table to rank passes.
   // Print one detailed line for a single backtest run (not once per optimizer pass).
   if(!MQLInfoInteger(MQL_OPTIMIZATION))
      PrintFormat("Tester fitness=%.6f netProfit=%.2f equityDD=%.2f trades=%.0f stressEquivalent=%.2f h; gridMultiplier=%.2f TP=%d SL=%d reverse=%s",
                  fitness,profit,equity_drawdown,trades,stress_equivalent_hours,InpGridStepMultiplier,
                  InpTakeProfitGrids,InpStopLossGrids,
                  (InpReverseTradeDirection ? "true" : "false"));
   return fitness;
  }

int OnInit()
  {
   if(InpEnableCandleMode)
      return InitializeCandleMode();
   if(InpCandleModeMagicNumber > 0 && InpCandleModeMagicNumber != InpMagicNumber)
     {
      int candle_mode_positions = CountCandleModePositions(0);
      if(candle_mode_positions > 0)
        {
         PrintFormat("Grid modu başlatılmadı: %d mum modu pozisyonu hâlâ açık. Mum modunu yeniden etkinleştirin veya bu pozisyonları manuel kapatın.",
                     candle_mode_positions);
         return INIT_FAILED;
        }
     }

   if(InpGridRangeLookbackBars < 5 || InpGridStepMultiplier <= 0.0 ||
      InpMinSpreadMultiple < 0.0 || InpInitialGridLevels < 1 ||
      InpMaxGridLevels < InpInitialGridLevels || InpTakeProfitGrids < 1 ||
      InpStopLossGrids < 1 || InpMaxLayersPerSide < 0 ||
      InpMaxTotalPositions < 0 || InpMaxSpreadPoints < 0 || InpMaxSpreadGridFraction < 0.0 || InpSignalHistoryBars < 2 ||
      InpDeviationPoints < 0 || InpOptimizationMinTrades < 0 || InpCloseAllAtEquityGain < 0.0 ||
      InpGridHeatPerCross <= 0.0 || InpGridHeatPerCross > 100.0 ||
      InpGridHeatDecayPerM1 < 0.0 || InpGridHeatDecayPerM1 > 100.0 ||
      InpGridHeatReverseThreshold <= 0.0 || InpGridHeatToxicThreshold <= InpGridHeatReverseThreshold ||
      InpGridHeatToxicThreshold > 100.0 || InpFastTPMaxSeconds < 0 ||
      InpGridEpochMinutes < 1 || InpGridEpochDeviation <= 0.0 ||
      InpGridSpacingExponent < 1.0 || InpGridSpacingExponent > 2.0 ||
      InpTradingStartHour < 0 || InpTradingStartHour > 23 ||
      InpTradingEndHour < 0 || InpTradingEndHour > 23 ||
      InpTradingStartMinute < 0 || InpTradingStartMinute > 59 ||
      InpTradingEndMinute < 0 || InpTradingEndMinute > 59 ||
      InpTesterServerUtcOffsetWinterHours < -12 || InpTesterServerUtcOffsetWinterHours > 14 ||
      InpTesterServerUtcOffsetSummerHours < -12 || InpTesterServerUtcOffsetSummerHours > 14 ||
      InpSymbioticProfitGrids <= 0.0 || InpSymbioticMaxCloseFraction < 0.0 ||
      InpSymbioticMaxCloseFraction > 0.50 || InpTesterStressPenaltyStrength < 0.0)
     {
      Print("Hatalı girdiler: grid/mum/TP/SL sınırlarını kontrol edin.");
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

   LoadProfitTargetState();
   LoadTakeProfitPriceStats();
   RefreshClosedCandleSignal(true);
   g_last_epoch_recalculation = TimeCurrent();
   g_last_stress_time_msc = (tick.time_msc > 0 ? (long)tick.time_msc : CurrentTimeMsc());
   RememberTick(tick);
   EventSetTimer(1);

   PrintFormat("EA hazır: %s base=%.*f step=%.*f exponent=%.2f signal=%s/%s score=%.2f trade=%s; TP=%d SL=%d hedging",
               _Symbol,_Digits,g_grid_base,_Digits,g_grid_step,InpGridSpacingExponent,
               (InpSignalCandleMode == SIGNAL_HEIKEN_ASHI ? "Heiken Ashi" : "normal mum"),
               SideName(g_signal_side),g_signal_score,SideName(TradeSideForSignal(g_signal_side)),
               InpTakeProfitGrids,InpStopLossGrids);
   Print("Grid lines use curved spacing and 15-minute epochs; open positions retain their stored epoch GS/TP/SL settings.");
   if(InpCloseAllAtEquityGain > 0.0)
      PrintFormat("Özsermaye kâr hedefi etkin: başlangıç=%.2f hedef=%.2f %s",
                  g_profit_target_start_equity,InpCloseAllAtEquityGain,
                  AccountInfoString(ACCOUNT_CURRENCY));
   if(InpEnableTradingHours)
      PrintFormat("Türkiye saat filtresi etkin: %s; Strategy Tester sunucu UTC offseti kış/yaz=%d/%d saat (Avrupa DST %s)",
                  TradingHoursWindowText(),InpTesterServerUtcOffsetWinterHours,
                  InpTesterServerUtcOffsetSummerHours,
                  (InpTesterServerUsesEuropeanDST ? "açık" : "kapalı"));
   HandleTradingHours(); // Enforce the window immediately on attach/restart.
   UpdateChartStatus();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   DeleteOwnGridObjects();
   Comment("");
  }

void OnTimer()
  {
   if(InpEnableCandleMode)
     {
      ProcessCandleModeEvent();
      return;
     }
   RefreshClosedCandleSignal(false);
   CoolGridHeatOnNewM1();
   bool trading_hours_blocked = HandleTradingHours();
   if(!trading_hours_blocked)
     {
      bool profit_target_handled = HandleEquityProfitTarget();
      if(!profit_target_handled)
         RefreshGridEpochIfDue();
     }
   UpdateChartStatus();

   // Keep terminal globals durable without polluting optimization passes.
   if(!MQLInfoInteger(MQL_TESTER) && g_grid_base > 0.0 && g_grid_step > 0.0)
     {
      GlobalVariableSet(GridStateKey("BASE"),g_grid_base);
      GlobalVariableSet(GridStateKey("STEP"),g_grid_step);
      if(g_profit_target_start_equity > 0.0)
        {
         GlobalVariableSet(GridStateKey("PTBASE"),g_profit_target_start_equity);
         GlobalVariableSet(GridStateKey("PTAMT"),InpCloseAllAtEquityGain);
         GlobalVariableSet(GridStateKey("PTLIQ"),(g_profit_target_liquidating ? 1.0 : 0.0));
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
   if(InpEnableCandleMode)
     {
      ProcessCandleModeEvent();
      return;
     }
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick) || tick.bid <= 0.0 || tick.ask <= 0.0)
      return;

   double previous_tick_price = g_last_tick_price;
   long previous_tick_time_msc = g_last_tick_time_msc;
   long current_tick_time_msc = (tick.time_msc > 0 ? (long)tick.time_msc : CurrentTimeMsc());
   RememberTick(tick);
   RefreshClosedCandleSignal(false);
   CoolGridHeatOnNewM1();
   UpdateStressMetrics(current_tick_time_msc);

   if(HandleTradingHours())
     {
      UpdateChartStatus();
      return;
     }
   bool suppress_grid_crosses = g_reseed_crosses_on_next_tick;
   if(suppress_grid_crosses)
     {
      ReseedGridCrossState(MidPrice(tick));
      g_reseed_crosses_on_next_tick = false;
     }
   if(HandleEquityProfitTarget())
     {
      UpdateChartStatus();
      return;
     }
   RefreshGridEpochIfDue();
   ManageOpenPositions(tick);
   double grid_price = MidPrice(tick);
   if(!suppress_grid_crosses && grid_price > 0.0)
      ProcessGridCrosses(grid_price,previous_tick_price,previous_tick_time_msc,current_tick_time_msc);
   UpdateChartStatus();
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(InpEnableCandleMode)
      return; // Candle mode has independent, count-based position management.
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL) != _Symbol ||
      (ulong)HistoryDealGetInteger(trans.deal,DEAL_MAGIC) != InpMagicNumber)
      return;

   long entry_kind = HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   ulong identifier = (ulong)HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID);
   long deal_time_msc = HistoryDealGetInteger(trans.deal,DEAL_TIME_MSC);

   if(entry_kind == DEAL_ENTRY_IN)
     {
      string deal_comment = HistoryDealGetString(trans.deal,DEAL_COMMENT);
      int line_code = ParseLineCode(deal_comment);
      long deal_type = HistoryDealGetInteger(trans.deal,DEAL_TYPE);
      int side = (deal_type == DEAL_TYPE_BUY ? 1 : -1);
      for(int i=0; i<ArraySize(g_pending_settings); i++)
        {
         if(g_pending_settings[i].side != side ||
            (line_code != 0 && g_pending_settings[i].line_code != line_code) ||
            (line_code == 0 && StringFind(deal_comment,g_pending_settings[i].comment) < 0) ||
            deal_time_msc + 1000 < g_pending_settings[i].request_time_msc)
            continue;
         StorePositionSettings(identifier,g_pending_settings[i].line_code,
                               g_pending_settings[i].grid_step,g_pending_settings[i].tp_grids,
                               g_pending_settings[i].sl_grids,deal_time_msc);
         RemovePendingSettingsAt(i);
         break;
        }
      return;
     }

   if(entry_kind != DEAL_ENTRY_OUT && entry_kind != DEAL_ENTRY_OUT_BY && entry_kind != DEAL_ENTRY_INOUT)
      return;

   bool still_open = false;
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket) &&
         PositionGetString(POSITION_SYMBOL) == _Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC) == InpMagicNumber &&
         (ulong)PositionGetInteger(POSITION_IDENTIFIER) == identifier)
        {
         still_open = true;
         break;
        }
     }

   int line_code = 0;
   double position_step = 0.0;
   int position_tp = 0;
   int position_sl = 0;
   long open_time_msc = 0;
   bool have_state = ReadPositionSettingsByIdentifier(identifier,line_code,position_step,
                                                       position_tp,position_sl,open_time_msc);
   if(line_code == 0)
      line_code = ParseLineCode(HistoryDealGetString(trans.deal,DEAL_COMMENT));
   long reason = HistoryDealGetInteger(trans.deal,DEAL_REASON);
   double deal_price = HistoryDealGetDouble(trans.deal,DEAL_PRICE);
   double deal_volume = HistoryDealGetDouble(trans.deal,DEAL_VOLUME);

   if(reason == DEAL_REASON_SL)
      PoisonGridLineAfterSL(line_code);
   if(reason == DEAL_REASON_TP)
     {
      RecordTakeProfitPrice(deal_price,deal_volume);
      RecordSuccessfulGridTP(line_code,open_time_msc,deal_time_msc);
     }

   if(!still_open && identifier > 0)
     {
      if(have_state)
         RecordPositionLifetime(open_time_msc,deal_time_msc);
      DeletePositionSettings(identifier);
     }
  }

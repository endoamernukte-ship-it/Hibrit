#property strict
#property version   "1.04"
#property description "M1 volatility-sized fixed-price grid with closed-candle Heiken Ashi direction and sequential grid strategy"

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

input group "Sıralı Grid Stratejisi (Long/Short Blokları)"
input bool                  InpUseSequentialGrid        = true;   // true: Fiyat başlangıç noktasından itibaren sıralı blok yönleri kullan
input int                   InpSeqUpLongCount           = 2;      // Yukarı yönde Long blok adedi
input int                   InpSeqUpShortCount          = 2;      // Yukarı yönde Short blok adedi
input int                   InpSeqDownShortCount        = 2;      // Aşağı yönde Short blok adedi
input int                   InpSeqDownLongCount         = 2;      // Aşağı yönde Long blok adedi

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

// Grid coordinates and spacing stay fixed for this grid generation.
double g_grid_base = 0.0;
double g_grid_step = 0.0;
int    g_up_count = 0;
int    g_down_count = 0;
int    g_up_state[];       // -1 = current price below line; +1 = above; 0 = not armed
int    g_down_state[];

int      g_signal_side = 0; // +1 LONG, -1 SHORT, 0 no valid closed-bar signal
double   g_profit_target_start_equity = 0.0;
bool     g_profit_target_liquidating = false;
datetime g_last_signal_bar_time = 0;
datetime g_last_state_flush = 0;
string   g_last_action = "Başlatılıyor";
string   g_grid_object_prefix = "";

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

int TradeSideForSignal(const int signal_side)
  {
   if(signal_side == 0)
      return 0;
   return (InpReverseTradeDirection ? -signal_side : signal_side);
  }

//+------------------------------------------------------------------+
//| Sequential grid side determination                               |
//+------------------------------------------------------------------+
int GetGridLineSide(const bool is_up,const int index)
  {
   if(!InpUseSequentialGrid)
      return TradeSideForSignal(g_signal_side);

   if(is_up)
     {
      int c1 = MathMax(1,InpSeqUpLongCount);
      int c2 = MathMax(1,InpSeqUpShortCount);
      int cycle = c1 + c2;
      int rem = (index - 1) % cycle;
      return (rem < c1 ? 1 : -1);
     }
   else
     {
      int c1 = MathMax(1,InpSeqDownShortCount);
      int c2 = MathMax(1,InpSeqDownLongCount);
      int cycle = c1 + c2;
      int rem = (index - 1) % cycle;
      return (rem < c1 ? -1 : 1);
     }
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
   if(InpTakeProfitGrids > 0 && broker_distance_points > 0)
     {
      double tp_min_step = ((double)broker_distance_points * _Point + TickSize()) / (double)InpTakeProfitGrids;
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
color GridLineColor(const bool is_up,const int index)
  {
   int side = GetGridLineSide(is_up,index);
   if(side > 0)
      return clrLimeGreen;
   if(side < 0)
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
   SetHorizontalLine(GridObjectName(is_up,index),price,GridLineColor(is_up,index),STYLE_DOT,1);
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
   g_up_count = InpInitialGridLevels;
   g_down_count = InpInitialGridLevels;
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
   if(g_grid_step <= 0.0)
      return;
   int guard = 0;
   double upper_limit = price + g_grid_step;
   while(g_up_count < InpMaxGridLevels && guard < 10000)
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
   while(g_down_count < InpMaxGridLevels && guard < 10000)
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
bool CalculateClosedCandleSignal(int &side_out,datetime &current_bar_time)
  {
   side_out = 0;
   current_bar_time = 0;
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

      if(shift == 1)
         side_out = (ha_close >= ha_open ? 1 : -1);
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
                  (InpSignalCandleMode == SIGNAL_HEIKEN_ASHI ? "Heiken Ashi" : "standard candle"));
      RecolorGridLines();
      if(InpCloseOppositeOnColorChange && old_side != 0 && !InpUseSequentialGrid)
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

int PositionLineCode(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket))
      return 0;
   if(MQLInfoInteger(MQL_TESTER))
      return ParseLineCode(PositionGetString(POSITION_COMMENT));
   ulong identifier = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   string key = PositionStateKey(identifier,"LN");
   if(GlobalVariableCheck(key))
      return (int)MathRound(GlobalVariableGet(key));
   return ParseLineCode(PositionGetString(POSITION_COMMENT));
  }

void StorePositionSettings(const ulong identifier,const int line_code,const double grid_step,
                           const int tp_grids,const int sl_grids)
  {
   if(MQLInfoInteger(MQL_TESTER))
      return;
   GlobalVariableSet(PositionStateKey(identifier,"LN"),(double)line_code);
   GlobalVariableSet(PositionStateKey(identifier,"GS"),grid_step);
   GlobalVariableSet(PositionStateKey(identifier,"TP"),(double)tp_grids);
   GlobalVariableSet(PositionStateKey(identifier,"SL"),(double)sl_grids);
   GlobalVariablesFlush();
  }

void DeletePositionSettings(const ulong identifier)
  {
   if(MQLInfoInteger(MQL_TESTER))
      return;
   GlobalVariableDel(PositionStateKey(identifier,"LN"));
   GlobalVariableDel(PositionStateKey(identifier,"GS"));
   GlobalVariableDel(PositionStateKey(identifier,"TP"));
   GlobalVariableDel(PositionStateKey(identifier,"SL"));
   GlobalVariablesFlush();
  }

void GetPositionGridSettings(const ulong ticket,double &grid_step,int &tp_grids,int &sl_grids)
  {
   grid_step = g_grid_step;
   tp_grids = InpTakeProfitGrids;
   sl_grids = InpStopLossGrids;
   if(!PositionSelectByTicket(ticket))
      return;

   if(MQLInfoInteger(MQL_TESTER))
      return;

   ulong identifier = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   string key = PositionStateKey(identifier,"GS");
   if(GlobalVariableCheck(key))
     {
      double saved = GlobalVariableGet(key);
      if(saved > 0.0)
         grid_step = saved;
     }
   key = PositionStateKey(identifier,"TP");
   if(GlobalVariableCheck(key))
     {
      int saved_tp = (int)MathRound(GlobalVariableGet(key));
      if(saved_tp > 0)
         tp_grids = saved_tp;
     }
   key = PositionStateKey(identifier,"SL");
   if(GlobalVariableCheck(key))
     {
      int saved_sl = (int)MathRound(GlobalVariableGet(key));
      if(saved_sl > 0)
         sl_grids = saved_sl;
     }

   // If a market deal was accepted but its ticket was not immediately discoverable,
   // persist the settings on the next management pass using the position comment.
   string step_key = PositionStateKey(identifier,"GS");
   if(!GlobalVariableCheck(step_key))
      StorePositionSettings(identifier,PositionLineCode(ticket),grid_step,tp_grids,sl_grids);
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
      g_profit_target_start_equity = new_equity;
      g_profit_target_liquidating = false;
      SaveProfitTargetState();
      MqlTick tick;
      if(SymbolInfoTick(_Symbol,tick))
         ReseedGridCrossState(MidPrice(tick));
      g_last_action = "Kâr hedefi tamamlandı; yeni hedef döngüsü başladı";
      PrintFormat("Yeni kâr hedefi döngüsü: başlangıç özsermayesi=%.2f %s hedef=%.2f",
                  g_profit_target_start_equity,AccountInfoString(ACCOUNT_CURRENCY),
                  InpCloseAllAtEquityGain);
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
   if(side == 0 || g_grid_step <= 0.0)
      return false;
   if(!InpUseSequentialGrid && g_signal_side == 0)
      return false;

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
   if(InpMaxSpreadGridFraction > 0.0 && spread_price > g_grid_step * InpMaxSpreadGridFraction)
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
   double expected_tp = PositionTakeProfit(expected_entry,side,g_grid_step,InpTakeProfitGrids);
   double expected_sl = PositionStopLoss(expected_entry,side,g_grid_step,InpStopLossGrids);
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
      StorePositionSettings(identifier,line_code,g_grid_step,InpTakeProfitGrids,InpStopLossGrids);
      ModifyPositionProtection(ticket,side,fill_price,g_grid_step,InpTakeProfitGrids,InpStopLossGrids);
      PrintFormat("Grid giriş: %s line=%s signal=%.*f fill=%.*f lot=%.8f gridStep=%.*f TP=%.*f SL=%.*f",
                  SideName(side),line_text,_Digits,signal_price,_Digits,fill_price,
                  PositionGetDouble(POSITION_VOLUME),_Digits,g_grid_step,
                  _Digits,PositionTakeProfit(fill_price,side,g_grid_step,InpTakeProfitGrids),
                  _Digits,PositionStopLoss(fill_price,side,g_grid_step,InpStopLossGrids));
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
   int trade_side = GetGridLineSide(is_up,index);
   if(trade_side == 0)
      return;
   if(!InpUseSequentialGrid && !InpEnterOnAnyCross && cross_direction != trade_side)
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
      int tp_grids = InpTakeProfitGrids;
      int sl_grids = InpStopLossGrids;
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
   string target_status = "Özsermaye hedefi: kapalı";
   if(InpCloseAllAtEquityGain > 0.0)
     {
      double equity_gain = AccountInfoDouble(ACCOUNT_EQUITY) - g_profit_target_start_equity;
      target_status = StringFormat("Özsermaye hedefi: %.2f / %.2f %s%s",
                                   equity_gain,InpCloseAllAtEquityGain,
                                   AccountInfoString(ACCOUNT_CURRENCY),
                                   (g_profit_target_liquidating ? " (pozisyonlar kapatılıyor)" : ""));
     }

   Comment("M1 Auto Grid HA v1.04\n",
           "Sembol: ",_Symbol," | Sıralı Grid: ",(InpUseSequentialGrid ? "Aktif" : "Pasif"),"\n",
           "Grid base: ",DoubleToString(g_grid_base,_Digits)," | anlık: ",DoubleToString(current_price,_Digits),"\n",
           "Sabit adım: ",DoubleToString(g_grid_step,_Digits)," (",DoubleToString(step_points,1)," point / ",
           DoubleToString(step_pips,2)," pip) | TP ",
           IntegerToString(InpTakeProfitGrids)," grid / SL ",IntegerToString(InpStopLossGrids)," grid\n",
           "Pozisyon LONG/SHORT: ",IntegerToString(long_count)," / ",IntegerToString(short_count),
           " | Sınır/yan: ",IntegerToString(InpMaxLayersPerSide),"\n",
           target_status,"\n",
           "Durum: ",g_last_action);
  }

double OnTester()
  {
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
      PrintFormat("Tester fitness=%.6f netProfit=%.2f equityDD=%.2f trades=%.0f; gridMultiplier=%.2f TP=%d SL=%d reverse=%s",
                  fitness,profit,equity_drawdown,trades,InpGridStepMultiplier,
                  InpTakeProfitGrids,InpStopLossGrids,
                  (InpReverseTradeDirection ? "true" : "false"));
   return fitness;
  }

int OnInit()
  {
   if(InpGridRangeLookbackBars < 5 || InpGridStepMultiplier <= 0.0 ||
      InpMinSpreadMultiple < 0.0 || InpInitialGridLevels < 1 ||
      InpMaxGridLevels < InpInitialGridLevels || InpTakeProfitGrids < 1 ||
      InpStopLossGrids < 1 || InpMaxLayersPerSide < 0 ||
      InpMaxTotalPositions < 0 || InpMaxSpreadPoints < 0 || InpMaxSpreadGridFraction < 0.0 || InpSignalHistoryBars < 2 ||
      InpDeviationPoints < 0 || InpOptimizationMinTrades < 0 || InpCloseAllAtEquityGain < 0.0 ||
      InpSeqUpLongCount < 1 || InpSeqUpShortCount < 1 || InpSeqDownShortCount < 1 || InpSeqDownLongCount < 1)
     {
      Print("Hatalı girdiler: grid/mum/TP/SL sınırlarını ve sıralı grid adetlerini kontrol edin.");
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
   RefreshClosedCandleSignal(true);
   EventSetTimer(1);

   PrintFormat("EA hazır: %s base=%.*f step=%.*f sequential=%s; TP=%d SL=%d hedging",
               _Symbol,_Digits,g_grid_base,_Digits,g_grid_step,
               (InpUseSequentialGrid ? "aktif" : "pasif"),
               InpTakeProfitGrids,InpStopLossGrids);
   if(InpCloseAllAtEquityGain > 0.0)
      PrintFormat("Özsermaye kâr hedefi etkin: başlangıç=%.2f hedef=%.2f %s",
                  g_profit_target_start_equity,InpCloseAllAtEquityGain,
                  AccountInfoString(ACCOUNT_CURRENCY));
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
   RefreshClosedCandleSignal(false);
   HandleEquityProfitTarget();
   UpdateChartStatus();
   // Touch saved grid globals while the EA is active so MT5 keeps them current.
   if(g_grid_base > 0.0 && g_grid_step > 0.0)
     {
      GlobalVariableSet(GridStateKey("BASE"),g_grid_base);
      GlobalVariableSet(GridStateKey("STEP"),g_grid_step);
      if(!MQLInfoInteger(MQL_TESTER) && g_profit_target_start_equity > 0.0)
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
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick) || tick.bid <= 0.0 || tick.ask <= 0.0)
      return;

   RefreshClosedCandleSignal(false);
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
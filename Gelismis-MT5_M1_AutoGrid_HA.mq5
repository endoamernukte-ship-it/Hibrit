Tabii ki! Aşağıda **7 özgün fikrin tamamının entegre edildiği, doğrudan `.mq5` dosyası olarak kaydedebileceğiniz temiz kod bloğu** yer almaktadır.

Bunu bir `.mq5` dosyasına dönüştürmek için yapmanız gerekenler çok basit:
1. MetaTrader 5'i açın ve klavyeden **F4** (veya MetaEditor'u) açın.
2. Sol üstte **Dosya (File) -> Yeni (New) -> Uzman Danışman (Expert Advisor)** seçeneğine tıklayın.
3. Dosya adına **M1_AutoGrid_HA_Ultimate** yazın ve *İleri* deyip *Bitir*e tıklayın.
4. MetaEditor'un otomatik getirdiği şablon kodları tamamen silin (**Ctrl+A yapıp silin**).
5. Aşağıdaki kodu kopyalayıp boş sayfaya yapıştırın (**Ctrl+V**).
6. Klavyeden **F7** tuşuna basarak derleyin (Compile).
7. Derlendikten sonra MetaTrader 5'e dönüp EA'yı grafiğe sürükleyebilirsiniz.

İşte **M1_AutoGrid_HA_Ultimate.mq5** dosyanızın içeriği:

```mql5
//+------------------------------------------------------------------+
//|                                     M1_AutoGrid_HA_Ultimate.mq5  |
//|                      Telif Hakkı 2024, MetaQuotes Software Corp. |
//|                                             https://www.mql5.com |
//+------------------------------------------------------------------+
#property strict
#property version   "2.00"
#property description "M1 volatility-sized dynamic grid with fatigue, tectonic shift, HA anatomy, kinetic filter, quantum layering and gravitational space"

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
input bool                  InpCloseOppositeOnColorChange      = false;
input bool                  InpReverseTradeDirection    = false;

input group "Otomatik grid aralığı"
input int                   InpGridRangeLookbackBars    = 20;
input double                InpGridStepMultiplier       = 0.50;
input double                InpMinSpreadMultiple        = 2.00;
input int                   InpInitialGridLevels        = 30;
input int                   InpMaxGridLevels            = 1000;
input bool                  InpResetGridOnInit          = false;
input bool                  InpDrawGridLevels           = true;
input bool                  InpEnterOnAnyCross          = true;

input group "Çıkışlar (her katman için)"
input int                   InpTakeProfitGrids          = 3;
input int                   InpStopLossGrids            = 10;

input group "Pozisyon ve lot sınırları"
input bool                  InpUseBrokerMinimumVolume   = false;
input double                InpFixedLots                = 0.01;
input int                   InpMaxLayersPerSide         = 5;
input int                   InpMaxTotalPositions        = 10;
input bool                  InpOnePositionPerGridLine   = true;
input int                   InpMaxSpreadPoints          = 0;
input double                InpMaxSpreadGridFraction    = 0.50;

input group "Çizgi Yorgunluğu (Isı) ve Termodinamik"
input bool                  InpUseLineFatigue = true;
input double                InpLineHeatCrossInc = 0.10;
input double                InpLineHeatCoolPerBar = 0.10;
input double                InpLineHeatSL = 1.00;
input double                InpLineHeatBlock = 0.70;
input double                InpLineHeatReverse = 0.50;
input int                   InpLineBonusTPGrids = 1;

input group "Tektonik Grid Kayması (Epoch)"
input bool                  InpUseTectonicShift = true;
input int                   InpTectonicMinutes = 15;
input double                InpTectonicDeviation = 0.50;

input group "Heiken Ashi Anatomik Enerji"
input bool                  InpUseAnatomicalEnergy = true;
input double                InpAnatomicalHighScore = 0.80;
input double                InpAnatomicalLowScore = 0.30;
input int                   InpAnatomicalTpBonusHigh = 2;
input int                   InpAnatomicalTpLow = 1;

input group "Kinetik (Balistik) Geçiş Filtresi"
input bool                  InpUseKineticFilter = true;
input int                   InpBallisticMaxMs = 200;
input double                InpBallisticJumpFraction = 0.40;

input group "Kuantum Dolanıklık (Yamyam Katmanlar)"
input bool                  InpUseQuantumEntanglement = true;
input double                InpQuantumHelperProfitGrids = 1.5;
input double                InpQuantumCloseSickFraction = 0.5;

input group "Kütleçekimsel Grid Uzayı"
input bool                  InpUseGravitationalSpace = true;
input double                InpGravitationalExponent = 1.15;
input bool                  InpUseLivingCenter = true;

input group "İşlem"
input ulong                 InpMagicNumber              = 20261008;
input int                   InpDeviationPoints           = 20;
input bool                  InpShowChartStatus           = true;

input group "Özsermaye kâr hedefi"
input double                InpCloseAllAtEquityGain       = 0.0;

input group "Strateji Sınayıcı optimizasyonu"
input bool                  InpUseRiskAdjustedTesterScore = true;
input int                   InpOptimizationMinTrades      = 30;
input bool                  InpUseUnderwaterPenalty = true;
input double                InpUnderwaterPenaltyWeight = 0.00001;

// Grid coordinates and spacing stay fixed for this grid generation (unless tectonic shift).
double g_grid_base = 0.0;
double g_grid_step = 0.0;
int    g_up_count = 0;
int    g_down_count = 0;
int    g_up_state[];       // -1, +1, 0, or 2 = spring armed
int    g_down_state[];
double g_up_heat[];
double g_down_heat[];
int    g_up_bonus[];
int    g_down_bonus[];
int    g_up_spring_dir[];
int    g_down_spring_dir[];

int      g_signal_side = 0;
double   g_signal_score = 0.5;
bool     g_effective_reverse = false;
bool     g_effective_enter_any_cross = true;
int      g_dynamic_tp_grids = 3;
double   g_profit_target_start_equity = 0.0;
bool     g_profit_target_liquidating = false;
datetime g_last_signal_bar_time = 0;
datetime g_last_state_flush = 0;
datetime g_last_cool_bar_time = 0;
datetime g_last_tectonic_time = 0;
string   g_last_action = "Başlatılıyor";
string   g_grid_object_prefix = "";

double   g_prev_price = 0.0;
long     g_prev_time_msc = 0;
double   g_tp_price_sum = 0.0;
int      g_tp_count = 0;
double   g_underwater_seconds_squared = 0.0;
datetime g_underwater_start = 0;

// Forward declarations
void CoolGridLines();
void CheckTectonicShift();
void CheckUnderwater();
void CheckQuantumEntanglement(const MqlTick &tick);

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
   return (g_effective_reverse ? -signal_side : signal_side);
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
   return "M1G_" + StringFormat("%I64u",(ulong)HashText(seed));
  }

string GridStateKey(const string field)
  {
   return InstanceStatePrefix() + "_" + field;
  }

void SaveProfitTargetState()
  {
   if(MQLInfoInteger(MQL_TESTER))
      return;
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
      return false;

   double ranges[];
   if(ArrayResize(ranges,lookback) < lookback)
      return false;
   for(int i=0; i<lookback; i++)
     {
      int shift = i + 1;
      ranges[i] = MathMax(0.0,rates[shift].high - rates[shift].low);
     }

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
//| Fixed / Gravitational grid coordinates                           |
//+------------------------------------------------------------------+
double GridLevelPrice(const bool is_up,const int index)
  {
   double exp = (InpUseGravitationalSpace ? InpGravitationalExponent : 1.0);
   double units = MathPow((double)index,exp);
   if(is_up)
      return g_grid_base + g_grid_step * units;
   return g_grid_base - g_grid_step * units;
  }

bool InitializeGridState(const double current_price)
  {
   g_up_count = InpInitialGridLevels;
   g_down_count = InpInitialGridLevels;
   if(ArrayResize(g_up_state,g_up_count + 1) < g_up_count + 1 ||
      ArrayResize(g_down_state,g_down_count + 1) < g_down_count + 1 ||
      ArrayResize(g_up_heat,g_up_count + 1) < g_up_count + 1 ||
      ArrayResize(g_down_heat,g_down_count + 1) < g_down_count + 1 ||
      ArrayResize(g_up_bonus,g_up_count + 1) < g_up_count + 1 ||
      ArrayResize(g_down_bonus,g_down_count + 1) < g_down_count + 1 ||
      ArrayResize(g_up_spring_dir,g_up_count + 1) < g_up_count + 1 ||
      ArrayResize(g_down_spring_dir,g_down_count + 1) < g_down_count + 1)
      return false;
   ArrayInitialize(g_up_state,0);
   ArrayInitialize(g_down_state,0);
   ArrayInitialize(g_up_heat,0.0);
   ArrayInitialize(g_down_heat,0.0);
   ArrayInitialize(g_up_bonus,0);
   ArrayInitialize(g_down_bonus,0);
   ArrayInitialize(g_up_spring_dir,0);
   ArrayInitialize(g_down_spring_dir,0);

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
         if(ArrayResize(g_up_state,next_index + 1) < next_index + 1) break;
         if(ArrayResize(g_up_heat,next_index + 1) < next_index + 1) break;
         if(ArrayResize(g_up_bonus,next_index + 1) < next_index + 1) break;
         if(ArrayResize(g_up_spring_dir,next_index + 1) < next_index + 1) break;
         g_up_count = next_index;
         g_up_state[next_index] = 0;
         g_up_heat[next_index] = 0.0;
         g_up_bonus[next_index] = 0;
         g_up_spring_dir[next_index] = 0;
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
         if(ArrayResize(g_down_state,next_index + 1) < next_index + 1) break;
         if(ArrayResize(g_down_heat,next_index + 1) < next_index + 1) break;
         if(ArrayResize(g_down_bonus,next_index + 1) < next_index + 1) break;
         if(ArrayResize(g_down_spring_dir,next_index + 1) < next_index + 1) break;
         g_down_count = next_index;
         g_down_state[next_index] = 0;
         g_down_heat[next_index] = 0.0;
         g_down_bonus[next_index] = 0;
         g_down_spring_dir[next_index] = 0;
         DrawGridLine(false,next_index);
        }
      else
         break;
     }
  }

void CoolGridLines()
  {
   if(!InpUseLineFatigue)
      return;
   for(int i=1; i<=g_up_count; i++)
      g_up_heat[i] = MathMax(0.0,g_up_heat[i] - InpLineHeatCoolPerBar);
   for(int i=1; i<=g_down_count; i++)
      g_down_heat[i] = MathMax(0.0,g_down_heat[i] - InpLineHeatCoolPerBar);
  }

//+------------------------------------------------------------------+
//| Closed-candle direction + Anatomical Energy                      |
//+------------------------------------------------------------------+
bool CalculateClosedCandleSignal(int &side_out,datetime &current_bar_time,double &score_out)
  {
   side_out = 0;
   current_bar_time = 0;
   score_out = 0.5;
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
      score_out = 0.5;
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
         double body = MathAbs(ha_close - ha_open);
         double range = ha_high - ha_low;
         if(range <= 0.0)
            score_out = 0.5;
         else
           {
            double body_ratio = body / range;
            if(side_out > 0)
              {
               double lower_wick = ha_open - ha_low;
               double adverse = lower_wick / range;
               score_out = 0.2 + 0.8 * body_ratio * (1.0 - adverse);
              }
            else
              {
               double upper_wick = ha_high - ha_close;
               double adverse = upper_wick / range;
               score_out = 0.2 + 0.8 * body_ratio * (1.0 - adverse);
              }
            if(score_out < 0.0) score_out = 0.0;
            if(score_out > 1.0) score_out = 1.0;
           }
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
   double new_score = 0.5;
   if(!CalculateClosedCandleSignal(new_side,current_bar_time,new_score))
      return;

   if(force || current_bar_time != g_last_signal_bar_time)
      CoolGridLines();

   g_last_signal_bar_time = (current_bar_time > 0 ? current_bar_time : chart_bar_time);
   if(new_side == 0)
      return;

   g_signal_score = new_score;
   int old_side = g_signal_side;
   g_signal_side = new_side;

   g_effective_reverse = InpReverseTradeDirection;
   if(InpUseAnatomicalEnergy && g_signal_score < InpAnatomicalLowScore)
      g_effective_reverse = true;
   g_effective_enter_any_cross = InpEnterOnAnyCross;
   if(InpUseAnatomicalEnergy && g_signal_score > InpAnatomicalHighScore)
      g_effective_enter_any_cross = false;
   g_dynamic_tp_grids = InpTakeProfitGrids;
   if(InpUseAnatomicalEnergy)
     {
      if(g_signal_score > InpAnatomicalHighScore)
         g_dynamic_tp_grids = InpTakeProfitGrids + InpAnatomicalTpBonusHigh;
      else if(g_signal_score < InpAnatomicalLowScore)
         g_dynamic_tp_grids = InpAnatomicalTpLow;
     }

   if(old_side != new_side)
     {
      g_last_action = StringFormat("M1 sinyali %s oldu (skor %.2f)",SideName(new_side),g_signal_score);
      PrintFormat("Closed M1 signal changed: %s -> %s score=%.2f (%s)",SideName(old_side),SideName(new_side),g_signal_score,
                  (InpSignalCandleMode == SIGNAL_HEIKEN_ASHI ? "Heiken Ashi" : "standard candle"));
      RecolorGridLines();
      if(InpCloseOppositeOnColorChange && old_side != 0)
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
   GlobalVariableSet(PositionStateKey(identifier,"SL"),0.0);
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
      return true;
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
     {
      g_up_state[i] = ComparePriceToLevel(current_price,GridLevelPrice(true,i));
      g_up_spring_dir[i] = 0;
     }
   for(int i=1; i<=g_down_count; i++)
     {
      g_down_state[i] = ComparePriceToLevel(current_price,GridLevelPrice(false,i));
      g_down_spring_dir[i] = 0;
     }
  }

//+------------------------------------------------------------------+
//| Tectonic shift and underwater penalty helpers                    |
//+------------------------------------------------------------------+
void CheckTectonicShift()
  {
   if(!InpUseTectonicShift || g_grid_step <= 0.0)
      return;
   datetime now = TimeCurrent();
   if(g_last_tectonic_time == 0)
     {
      g_last_tectonic_time = now;
      return;
     }
   if(now - g_last_tectonic_time < InpTectonicMinutes * 60)
      return;
   g_last_tectonic_time = now;

   double median_range = 0.0;
   double min_step = 0.0;
   double new_step = 0.0;
   if(!CalculateInitialGridStep(new_step,median_range,min_step))
      return;
   double dev = MathAbs(new_step - g_grid_step) / g_grid_step;
   if(dev > InpTectonicDeviation)
     {
      PrintFormat("Tectonic shift: step %.5f -> %.5f (dev %.2f%%)",g_grid_step,new_step,dev * 100.0);
      g_grid_step = new_step;
      GlobalVariableSet(GridStateKey("STEP"),g_grid_step);
      MqlTick tick;
      if(SymbolInfoTick(_Symbol,tick))
         ReseedGridCrossState(MidPrice(tick));
      RecolorGridLines();
     }
  }

void CheckUnderwater()
  {
   if(!InpUseUnderwaterPenalty)
      return;
   double eq = AccountInfoDouble(ACCOUNT_EQUITY);
   double start = g_profit_target_start_equity;
   if(start <= 0.0)
      start = AccountInfoDouble(ACCOUNT_BALANCE);
   datetime now = TimeCurrent();
   if(eq < start)
     {
      if(g_underwater_start == 0)
         g_underwater_start = now;
      ulong dur = (ulong)(now - g_underwater_start);
      g_underwater_seconds_squared += (double)(dur) * (double)(dur);
     }
   else
     {
      g_underwater_start = 0;
     }
  }

//+------------------------------------------------------------------+
//| Quantum entanglement                                             |
//+------------------------------------------------------------------+
void CheckQuantumEntanglement(const MqlTick &tick)
  {
   if(!InpUseQuantumEntanglement)
      return;

   ulong helper_ticket = 0;
   double helper_profit = 0.0;
   double best_helper_grids = -1e9;
   ulong sick_ticket = 0;
   double sick_entry = 0.0;
   double sick_vol = 0.0;
   int sick_side = 0;
   datetime oldest_time = 0;

   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong tk = PositionGetTicket(i);
      if(tk == 0 || !SelectOurPosition(tk))
         continue;
      int side = SideFromPositionType(PositionGetInteger(POSITION_TYPE));
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double vol = PositionGetDouble(POSITION_VOLUME);
      double step = g_grid_step;
      int tp_d = InpTakeProfitGrids;
      int sl_d = InpStopLossGrids;
      GetPositionGridSettings(tk,step,tp_d,sl_d);
      if(step <= 0.0)
         continue;
      double close_price = (side > 0 ? tick.bid : tick.ask);
      double profit_grids = side * (close_price - entry) / step;
      datetime ptime = (datetime)PositionGetInteger(POSITION_TIME);

      if(profit_grids >= InpQuantumHelperProfitGrids && profit_grids > best_helper_grids)
        {
         best_helper_grids = profit_grids;
         helper_ticket = tk;
         helper_profit = PositionGetDouble(POSITION_PROFIT);
        }
      if(profit_grids < 0.0)
        {
         if(sick_ticket == 0 || ptime < oldest_time)
           {
            oldest_time = ptime;
            sick_ticket = tk;
            sick_entry = entry;
            sick_vol = vol;
            sick_side = side;
           }
        }
     }

   if(helper_ticket > 0 && sick_ticket > 0)
     {
      PrintFormat("Quantum: helper=%I64u profit=%.2f kapatılıp sick=%I64u kısmen kapatılacak.",helper_ticket,helper_profit,sick_ticket);
      if(CloseOurPosition(helper_ticket,"Quantum helper kapandı"))
        {
         double tick_value = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
         double tick_size = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
         double close_price = (sick_side > 0 ? tick.bid : tick.ask);
         double price_move = MathAbs(close_price - sick_entry);
         double vol_to_close = 0.0;
         if(price_move > 0.0 && tick_size > 0.0 && tick_value > 0.0)
           {
            double profit_per_lot = (price_move / tick_size) * tick_value;
            if(profit_per_lot > 0.0)
               vol_to_close = MathAbs(helper_profit) / profit_per_lot;
           }
         double max_vol = sick_vol * InpQuantumCloseSickFraction;
         if(vol_to_close <= 0.0 || vol_to_close > max_vol)
            vol_to_close = max_vol;
         double vol_step = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
         double min_vol = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
         if(vol_step > 0.0)
            vol_to_close = MathFloor(vol_to_close / vol_step + 1.0e-10) * vol_step;
         vol_to_close = NormalizeDouble(vol_to_close,8);
         if(vol_to_close + 1.0e-10 >= min_vol)
           {
            bool ok = trade.PositionClosePartial(sick_ticket,vol_to_close,InpDeviationPoints);
            if(TradeRetcodeOK(ok))
               PrintFormat("Quantum: sick pozisyon kısmen kapatıldı vol=%.8f",vol_to_close);
            else
               PrintFormat("Quantum partial close failed retcode=%u (%s)",trade.ResultRetcode(),trade.ResultRetcodeDescription());
           }
        }
     }
  }

//+------------------------------------------------------------------+
//| Equity profit target with living center                          |
//+------------------------------------------------------------------+
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

   double new_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(new_equity <= 0.0)
      new_equity = AccountInfoDouble(ACCOUNT_BALANCE);
   if(new_equity > 0.0)
     {
      g_profit_target_start_equity = new_equity;
      g_profit_target_liquidating = false;
      SaveProfitTargetState();

      if(InpUseLivingCenter && g_tp_count > 0)
        {
         double new_base = g_tp_price_sum / (double)g_tp_count;
         g_grid_base = NormalizePriceToTick(new_base,0);
         GlobalVariableSet(GridStateKey("BASE"),g_grid_base);
         PrintFormat("Living center: grid base moved to %.5f (from %d TP)",g_grid_base,g_tp_count);
         g_tp_price_sum = 0.0;
         g_tp_count = 0;
        }
      else
        {
         g_tp_price_sum = 0.0;
         g_tp_count = 0;
        }

      MqlTick tick;
      if(SymbolInfoTick(_Symbol,tick))
         ReseedGridCrossState(MidPrice(tick));
      RecolorGridLines();
      g_last_action = "Kâr hedefi tamamlandı; yeni hedef döngüsü başladı";
      PrintFormat("Yeni kâr hedefi döngüsü: başlangıç özsermayesi=%.2f %s hedef=%.2f",
                  g_profit_target_start_equity,AccountInfoString(ACCOUNT_CURRENCY),
                  InpCloseAllAtEquityGain);
     }
   return true;
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
   if(side == 0 || g_grid_step <= 0.0 || g_signal_side == 0)
      return false;

   bool is_up = (line_code > 0);
   int idx = (line_code > 0 ? line_code : -line_code);
   double heat = 0.0;
   int bonus = 0;
   if(is_up && idx <= g_up_count)
     {
      heat = g_up_heat[idx];
      bonus = g_up_bonus[idx];
     }
   else if(!is_up && idx <= g_down_count)
     {
      heat = g_down_heat[idx];
      bonus = g_down_bonus[idx];
     }

   if(InpUseLineFatigue && heat >= InpLineHeatBlock)
     {
      g_last_action = "Çizgi ısısı yüksek: giriş engellendi";
      return false;
     }

   int trade_side = TradeSideForSignal(g_signal_side);
   if(InpUseLineFatigue && heat >= InpLineHeatReverse && heat < InpLineHeatBlock)
      trade_side = -trade_side;

   if(trade_side == 0)
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

   int side_count = CountOurPositions(trade_side);
   int total_count = CountOurPositions(0);
   if(InpMaxTotalPositions > 0 && total_count >= InpMaxTotalPositions)
     {
      g_last_action = "Toplam pozisyon sınırı dolu";
      return false;
     }
   if(InpMaxLayersPerSide > 0 && side_count >= InpMaxLayersPerSide)
     {
      g_last_action = StringFormat("%s katman sınırı dolu",SideName(trade_side));
      return false;
     }
   if(InpOnePositionPerGridLine && HasPositionOnGridLine(trade_side,line_code))
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

   int tp_grids = g_dynamic_tp_grids + bonus;
   if(tp_grids < 1)
      tp_grids = 1;
   int sl_grids = InpStopLossGrids;

   double expected_entry = (trade_side > 0 ? tick.ask : tick.bid);
   double expected_tp = PositionTakeProfit(expected_entry,trade_side,g_grid_step,tp_grids);
   double expected_sl = PositionStopLoss(expected_entry,trade_side,g_grid_step,sl_grids);
   if(expected_tp <= 0.0 || expected_sl <= 0.0)
     {
      g_last_action = "Pozitif olmayan TP/SL fiyatı nedeniyle giriş atlandı";
      return false;
     }
   string line_text = (line_code > 0 ? "U" + IntegerToString(line_code) : "D" + IntegerToString(-line_code));
   string comment = "M1G:" + line_text;
   long request_time_msc = (long)tick.time_msc;

   bool sent = false;
   if(trade_side > 0)
      sent = trade.Buy(volume,_Symbol,0.0,expected_sl,expected_tp,comment);
   else
      sent = trade.Sell(volume,_Symbol,0.0,expected_sl,expected_tp,comment);

   if(!TradeRetcodeOK(sent))
     {
      PrintFormat("Grid girişi başarısız side=%s line=%s lot=%.8f retcode=%u (%s)",
                  SideName(trade_side),line_text,volume,trade.ResultRetcode(),trade.ResultRetcodeDescription());
      g_last_action = "Emir broker tarafından reddedildi";
      return false;
     }

   ulong ticket = 0;
   FindPositionFromDeal(trade.ResultDeal(),trade_side,comment,request_time_msc,ticket);
   if(ticket > 0 && PositionSelectByTicket(ticket))
     {
      ulong identifier = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      double fill_price = PositionGetDouble(POSITION_PRICE_OPEN);
      StorePositionSettings(identifier,line_code,g_grid_step,tp_grids,sl_grids);
      ModifyPositionProtection(ticket,trade_side,fill_price,g_grid_step,tp_grids,sl_grids);
      PrintFormat("Grid giriş: %s line=%s signal=%.*f fill=%.*f lot=%.8f gridStep=%.*f TP=%.*f SL=%.*f (Isı=%.2f Bonus=%d)",
                  SideName(trade_side),line_text,_Digits,signal_price,_Digits,fill_price,
                  PositionGetDouble(POSITION_VOLUME),_Digits,g_grid_step,
                  _Digits,PositionTakeProfit(fill_price,trade_side,g_grid_step,tp_grids),
                  _Digits,PositionStopLoss(fill_price,trade_side,g_grid_step,sl_grids),heat,bonus);
     }
   else
     {
      PrintFormat("Grid emri kabul edildi side=%s line=%s; pozisyon sonraki tikte bulunacak.",SideName(trade_side),line_text);
     }

   g_last_action = StringFormat("Yeni %s giriş: %s",SideName(trade_side),line_text);
   return true;
  }

void HandleGridCross(const bool is_up,const int index,const int cross_direction,
                     const double current_price)
  {
   int trade_side = TradeSideForSignal(g_signal_side);
   if(trade_side == 0)
      return;
   if(!g_effective_enter_any_cross && cross_direction != trade_side)
      return;

   int line_code = (is_up ? index : -index);
   OpenGridPosition(trade_side,line_code,current_price);
  }

void ProcessGridCrosses(const double price,const MqlTick &tick)
  {
   if(g_grid_step <= 0.0 || g_grid_base <= 0.0)
      return;
   ExpandGrid(price);

   for(int i=1; i<=g_up_count; i++)
     {
      int now_side = ComparePriceToLevel(price,GridLevelPrice(true,i));
      if(now_side == 0)
         continue;
      int previous = g_up_state[i];
      if(previous == 2)
        {
         int spring = g_up_spring_dir[i];
         if(now_side != spring)
           {
            g_up_state[i] = now_side;
            g_up_spring_dir[i] = 0;
            HandleGridCross(true,i,now_side,price);
           }
         else
           {
            g_up_state[i] = 2;
           }
         continue;
        }
      if(previous != 0 && now_side != previous)
        {
         g_up_heat[i] += InpLineHeatCrossInc;
         if(g_up_heat[i] > 1.0)
            g_up_heat[i] = 1.0;
         bool ballistic = false;
         if(InpUseKineticFilter && g_prev_time_msc > 0)
           {
            long dt = tick.time_msc - g_prev_time_msc;
            double jump = MathAbs(price - g_prev_price);
            if(dt <= InpBallisticMaxMs && jump >= g_grid_step * InpBallisticJumpFraction)
               ballistic = true;
           }
         if(ballistic && InpUseKineticFilter && g_effective_reverse)
           {
            g_up_state[i] = 2;
            g_up_spring_dir[i] = now_side;
            g_last_action = "Balistik geçiş: yay kuruldu";
            continue;
           }
         g_up_state[i] = now_side;
         HandleGridCross(true,i,now_side,price);
        }
      else
        {
         g_up_state[i] = now_side;
        }
     }

   for(int i=g_down_count; i>=1; i--)
     {
      int now_side = ComparePriceToLevel(price,GridLevelPrice(false,i));
      if(now_side == 0)
         continue;
      int previous = g_down_state[i];
      if(previous == 2)
        {
         int spring = g_down_spring_dir[i];
         if(now_side != spring)
           {
            g_down_state[i] = now_side;
            g_down_spring_dir[i] = 0;
            HandleGridCross(false,i,now_side,price);
           }
         else
           {
            g_down_state[i] = 2;
           }
         continue;
        }
      if(previous != 0 && now_side != previous)
        {
         g_down_heat[i] += InpLineHeatCrossInc;
         if(g_down_heat[i] > 1.0)
            g_down_heat[i] = 1.0;
         bool ballistic = false;
         if(InpUseKineticFilter && g_prev_time_msc > 0)
           {
            long dt = tick.time_msc - g_prev_time_msc;
            double jump = MathAbs(price - g_prev_price);
            if(dt <= InpBallisticMaxMs && jump >= g_grid_step * InpBallisticJumpFraction)
               ballistic = true;
           }
         if(ballistic && InpUseKineticFilter && g_effective_reverse)
           {
            g_down_state[i] = 2;
            g_down_spring_dir[i] = now_side;
            g_last_action = "Balistik geçiş: yay kuruldu";
            continue;
           }
         g_down_state[i] = now_side;
         HandleGridCross(false,i,now_side,price);
        }
      else
        {
         g_down_state[i] = now_side;
        }
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
      double close_price = (side > 0 ? tick.bid : tick.ask);
      bool tp_hit = (side > 0 ? close_price >= target : close_price <= target);
      bool sl_hit = (side > 0 ? close_price <= stop : close_price >= stop);

      if(tp_hit)
        {
         int lc = PositionLineCode(ticket);
         if(lc != 0)
           {
            bool is_up = (lc > 0);
            int idx = (lc > 0 ? lc : -lc);
            if(is_up && idx <= g_up_count)
              {
               g_up_heat[idx] = 0.0;
               g_up_bonus[idx] = InpLineBonusTPGrids;
              }
            else if(!is_up && idx <= g_down_count)
              {
               g_down_heat[idx] = 0.0;
               g_down_bonus[idx] = InpLineBonusTPGrids;
              }
           }
         g_tp_price_sum += target;
         g_tp_count++;
         CloseOurPosition(ticket,StringFormat("TP (%d grid)",tp_grids));
         continue;
        }
      if(sl_hit)
        {
         int lc = PositionLineCode(ticket);
         if(lc != 0)
           {
            bool is_up = (lc > 0);
            int idx = (lc > 0 ? lc : -lc);
            if(is_up && idx <= g_up_count)
              {
               g_up_heat[idx] = InpLineHeatSL;
               g_up_bonus[idx] = 0;
              }
            else if(!is_up && idx <= g_down_count)
              {
               g_down_heat[idx] = InpLineHeatSL;
               g_down_bonus[idx] = 0;
              }
           }
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

   Comment("M1 Auto Grid HA v2.00 (7 Özgün Fikir)\n",
           "Sembol: ",_Symbol," | Mum yönü: ",signal_type," ",EnumToString(InpSignalTimeframe)," ",SideName(g_signal_side),"\n",
           "İşlem yönü: ",SideName(TradeSideForSignal(g_signal_side)),
           (g_effective_reverse ? " (ters yön açık)" : ""),"\n",
           "Sinyal skoru: ",DoubleToString(g_signal_score,2)," | Dinamik TP Grid: ",IntegerToString(g_dynamic_tp_grids),"\n",
           "Grid base: ",DoubleToString(g_grid_base,_Digits)," | anlık: ",DoubleToString(current_price,_Digits),"\n",
           "Sabit adım: ",DoubleToString(g_grid_step,_Digits)," (",DoubleToString(step_points,1)," point / ",
           DoubleToString(step_pips,2)," pip) | TP ",IntegerToString(InpTakeProfitGrids)," grid / SL ",IntegerToString(InpStopLossGrids)," grid\n",
           "Pozisyon LONG/SHORT: ",IntegerToString(long_count)," / ",IntegerToString(short_count),
           " | Sınır/yan: ",IntegerToString(InpMaxLayersPerSide),"\n",
           target_status,"\n",
           "Sualtı ceza skoru (sn²): ",DoubleToString(g_underwater_seconds_squared,0),"\n",
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
         fitness = -1000000.0 + trades;
      else
        {
         double drawdown_floor = MathMax(initial_deposit * 0.005,0.01);
         fitness = profit / MathMax(equity_drawdown,drawdown_floor);
         if(InpUseUnderwaterPenalty)
            fitness -= InpUnderwaterPenaltyWeight * g_underwater_seconds_squared;
        }
     }

   if(!MQLInfoInteger(MQL_OPTIMIZATION))
      PrintFormat("Tester fitness=%.6f netProfit=%.2f equityDD=%.2f trades=%.0f underwaterPenalty=%.2f; gridMultiplier=%.2f TP=%d SL=%d reverse=%s",
                  fitness,profit,equity_drawdown,trades,
                  (InpUseUnderwaterPenalty ? InpUnderwaterPenaltyWeight * g_underwater_seconds_squared : 0.0),
                  InpGridStepMultiplier,InpTakeProfitGrids,InpStopLossGrids,
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
      InpDeviationPoints < 0 || InpOptimizationMinTrades < 0 || InpCloseAllAtEquityGain < 0.0)
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

   g_effective_reverse = InpReverseTradeDirection;
   g_effective_enter_any_cross = InpEnterOnAnyCross;
   g_dynamic_tp_grids = InpTakeProfitGrids;
   g_signal_score = 0.5;
   g_prev_price = 0.0;
   g_prev_time_msc = 0;
   g_tp_price_sum = 0.0;
   g_tp_count = 0;
   g_underwater_seconds_squared = 0.0;
   g_underwater_start = 0;

   g_grid_object_prefix = StringFormat("M1AG_%I64u_%I64u_%s_",InpMagicNumber,(ulong)HashSymbol(_Symbol),RunModeTag());
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

   PrintFormat("EA hazır: %s base=%.*f step=%.*f signal=%s %s trade=%s; TP=%d SL=%d hedging",
               _Symbol,_Digits,g_grid_base,_Digits,g_grid_step,
               (InpSignalCandleMode == SIGNAL_HEIKEN_ASHI ? "Heiken Ashi" : "normal mum"),
               SideName(g_signal_side),SideName(TradeSideForSignal(g_signal_side)),
               InpTakeProfitGrids,InpStopLossGrids);
   Print("7 Özgün Fikir Aktif: Çizgi Isısı, Tektonik Kayma, HA Anatomisi, Balistik Filtre, Kuantum Katman, Kütleçekim Uzayı, Sualtı Cezası.");
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
   CheckTectonicShift();
   CheckUnderwater();
   HandleEquityProfitTarget();
   UpdateChartStatus();
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
   CheckQuantumEntanglement(tick);
   double grid_price = MidPrice(tick);
   if(grid_price > 0.0)
      ProcessGridCrosses(grid_price,tick);
   g_prev_price = grid_price;
   g_prev_time_msc = tick.time_msc;
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
//+------------------------------------------------------------------+
```
//+------------------------------------------------------------------+
//| Forex Dynamic Engine - Squeeze Momentum hybrid EA                  |
//| Core Squeeze calculations adapted from SqueezeMomentum_LB_EA.mq5.   |
//| Educational prototype: test on demo; not an HFT or profit guarantee.|
//+------------------------------------------------------------------+
#property strict
#property version "1.00"
#include <Trade/Trade.mqh>

CTrade trade;
enum ENUM_SQZ_BAR_COLOR { SQZ_COLOR_NONE=0, SQZ_COLOR_LIME, SQZ_COLOR_GREEN, SQZ_COLOR_RED, SQZ_COLOR_MAROON };
enum ENUM_SQZ_STATE { SQZ_STATE_UNKNOWN=0, SQZ_STATE_ON, SQZ_STATE_OFF, SQZ_STATE_NONE };
enum ENUM_MARKET_REGIME { REGIME_UNKNOWN=0, REGIME_RANGE, REGIME_TREND, REGIME_VOLATILE, REGIME_FAKEOUT };
enum ENUM_ENGINE_MODE { MODE_DEFENSE=0, MODE_NORMAL, MODE_HUNTER };

input group "Squeeze Momentum (closed bars)"
input ENUM_TIMEFRAMES InpTimeframe=PERIOD_CURRENT;
input int InpBBLength=20;
input double InpBBMultFactor=2.0;
input int InpKCLength=20;
input double InpKCMultFactor=1.5;
input bool InpUseTrueRange=true;
input group "Regime"
input int InpATRPeriod=14;
input int InpATRBaselineBars=30;            // mean ATR on bars 2..N+1
input int InpADXPeriod=14;
input int InpEMAPeriod=50;
input double InpRangeADX=20.0;
input double InpTrendADX=25.0;
input double InpRangeATRRatio=0.85;
input double InpVolatileATRRatio=1.8;
input int InpReleaseConfirmBars=2;
input group "Grid"
input double InpBaseLot=0.01;
input double InpGridATR=1.0;
input double InpDefenseStepFactor=2.0;
input double InpHunterStepFactor=0.75;
input double InpRangeMultiplier=1.0;
input double InpTrendMultiplier=1.1;
input int InpMaxGridPositions=4;
input double InpMaxGrossLots=0.10;         // includes grid, scalp and hedge
input double InpBasketTargetMoney=10.0;    // deposit currency, floating profit+swap
input bool InpCompound=false;
input double InpCompoundReferenceBalance=10000.0;
input double InpMaxCompoundFactor=2.0;
input group "Hedge and scalp"
input bool InpEnableHedge=true;
input double InpHedgeDrawdownPercent=3.0; // grid floating loss / account balance
input double InpHedgeReleasePercent=1.0;
input double InpHedgeRatio=1.0;           // <= 1; subject to gross cap and margin
input bool InpEnableScalp=true;
input double InpScalpLot=0.01;
input int InpMaxScalps=1;
input double InpScalpSLATR=0.6;
input double InpScalpTPATR=0.4;
input double InpGridSLATR=4.0;            // per-position broker-side SL
input group "Execution and circuit breaker"
input ulong InpMagicNumber=20261106;       // grid=base, scalp=base+1, hedge=base+2
input int InpDeviationPoints=20;
input int InpMaxSpreadPoints=30;           // 0 disables spread filter
input int InpCooldownSeconds=10;
input double InpMinFreeMarginPercent=200.0; // free margin >= required margin * percent/100
input double InpAccountLossStopPercent=15.0; // (balance-equity)/balance, account-wide
input bool InpAllowTrading=false;          // must explicitly enable live orders

struct MarketSnapshot
  {
   ENUM_MARKET_REGIME regime;
   ENUM_ENGINE_MODE mode;
   ENUM_SQZ_STATE squeeze, previous_squeeze;
   double momentum, previous_momentum, atr, atr_ratio, adx, ema, close;
   int signal, trend_side;
   datetime bar_time;
   bool valid;
  };
struct GridPlan { double step, lot; int side; bool frozen; };
struct Exposure
  {
   int grids, scalps, hedges, grid_side;
   double grid_buy, grid_sell, hedge_buy, hedge_sell, gross, pnl, grid_pnl;
   double last_grid_price;
   long last_grid_time;
  };
MarketSnapshot g_market;
ENUM_TIMEFRAMES g_tf;
int g_atr=INVALID_HANDLE, g_adx=INVALID_HANDLE, g_ema=INVALID_HANDLE;
datetime g_bar=0, g_last_order=0;
int g_calm_bars=0;
bool g_flatten=false, g_stop=false;
string g_stop_key, g_flat_key;

double LinearRegressionEnd(const double &series[], const int end_index, const int period)
  {
   int start = end_index - period + 1;
   if(start < 0 || period < 2)
      return 0.0;

   double sum_x  = period * (period - 1) / 2.0;
   double sum_x2 = (period - 1) * period * (2 * period - 1) / 6.0;
   double sum_y  = 0.0;
   double sum_xy = 0.0;
   for(int k = 0; k < period; k++)
     {
      double y = series[start + k];
      sum_y  += y;
      sum_xy += k * y;
     }

   double denominator = period * sum_x2 - sum_x * sum_x;
   if(MathAbs(denominator) < 1.0e-12)
      return sum_y / period;

   double slope     = (period * sum_xy - sum_x * sum_y) / denominator;
   double intercept = (sum_y - slope * sum_x) / period;
   // linreg(..., offset=0): doğrunun en son mumdaki değeri
   return intercept + slope * (period - 1);
  }

ENUM_SQZ_BAR_COLOR BarColor(const double value, const double previous_value)
  {
   // PineScript:
   //   bcolor = iff(val > 0, iff(val > nz(val[1]), lime, green),
   //                         iff(val < nz(val[1]), red,  maroon))
   if(value > 0.0)
      return (value > previous_value) ? SQZ_COLOR_LIME : SQZ_COLOR_GREEN;
   return (value < previous_value) ? SQZ_COLOR_RED : SQZ_COLOR_MAROON;
  }

// Mum serisi için momentum değerlerini ve çubuk renklerini hesaplar.
// rates kronolojik sıradadır (0 = en eski). Son index oluşan mumdur.
bool ComputeMomentum(const MqlRates &rates[],
                     double &values[],
                     ENUM_SQZ_BAR_COLOR &colors[],
                     bool &valid[])
  {
   int total = ArraySize(rates);
   if(total <= 0)
      return false;
   if(ArrayResize(values, total) < total ||
      ArrayResize(colors, total) < total ||
      ArrayResize(valid,  total) < total)
      return false;

   ArrayInitialize(values, 0.0);
   for(int i = 0; i < total; i++)
     {
      colors[i] = SQZ_COLOR_NONE;
      valid[i]  = false;
     }

   // 1) x = close - avg(avg(highest(high,KC), lowest(low,KC)), sma(close,KC))
   double detrend[];
   bool   detrend_valid[];
   if(ArrayResize(detrend, total) < total || ArrayResize(detrend_valid, total) < total)
      return false;
   ArrayInitialize(detrend, 0.0);
   for(int i = 0; i < total; i++)
      detrend_valid[i] = false;

   for(int i = InpKCLength - 1; i < total; i++)
     {
      double highest = rates[i].high;
      double lowest  = rates[i].low;
      double sum_close = 0.0;
      for(int j = i - InpKCLength + 1; j <= i; j++)
        {
         highest    = MathMax(highest, rates[j].high);
         lowest     = MathMin(lowest,  rates[j].low);
         sum_close += rates[j].close;
        }
      double sma_close = sum_close / InpKCLength;
      double hl_mid    = (highest + lowest) * 0.5;   // avg(highest, lowest)
      double mid       = (hl_mid + sma_close) * 0.5; // avg(avg(...), sma)
      detrend[i]       = rates[i].close - mid;
      detrend_valid[i] = true;
     }

   // 2) val = linreg(x, KC, 0)
   for(int i = 2 * InpKCLength - 2; i < total; i++)
     {
      bool ready = true;
      for(int j = i - InpKCLength + 1; j <= i; j++)
        {
         if(!detrend_valid[j])
           {
            ready = false;
            break;
           }
        }
      if(!ready)
         continue;
      values[i] = LinearRegressionEnd(detrend, i, InpKCLength);
      valid[i]  = true;
     }

   // 3) Çubuk renkleri (önceki mum yoksa nz(val[1]) = 0 kabul edilir)
   for(int i = 0; i < total; i++)
     {
      if(!valid[i])
         continue;
      double previous_value = (i > 0 && valid[i - 1]) ? values[i - 1] : 0.0;
      colors[i] = BarColor(values[i], previous_value);
     }
   return true;
  }

// İki komşu mum rengine bakarak sinyal üretir.
//   +1 = BUY sinyali, -1 = SELL sinyali, 0 = sinyal yok
int SignalFromTransition(const ENUM_SQZ_BAR_COLOR previous_color,
                         const ENUM_SQZ_BAR_COLOR current_color)
  {
   // Açık yeşil (lime) -> Koyu yeşil (green): momentum pozitifken zayıflıyor
   if(previous_color == SQZ_COLOR_LIME && current_color == SQZ_COLOR_GREEN)
      return -1;
   // Kırmızı (red) -> Bordo (maroon): momentum negatifken toparlanıyor
   if(previous_color == SQZ_COLOR_RED && current_color == SQZ_COLOR_MAROON)
      return 1;
   return 0;
  }

// BB/KC sıkışma durumu (sqzOn/sqzOff/noSqz). Sinyal şartı DEĞİLDİR;
// sadece bilgi panelinde gösterilir (Pine'daki 0 çizgisi noktaları).
ENUM_SQZ_STATE ComputeSqueezeState(const MqlRates &rates[], const int index)
  {
   int needed = (int)MathMax(InpBBLength, InpKCLength);
   if(index < needed - 1)
      return SQZ_STATE_UNKNOWN;

   // Bollinger: basis = sma(close, BB), dev = BB_Mult * stdev(close, BB)
   // NOT: Gönderilen kodda dev satırında multKC yazıyordu; orijinal
   // LazyBear kodunda BB sapması BB MultFactor ile hesaplanır. Bu
   // fark sadece sıkışma durumunu etkiler, momentum çubuklarını ve
   // dolayısıyla sinyalleri etkilemez.
   double basis = 0.0;
   for(int j = index - InpBBLength + 1; j <= index; j++)
      basis += rates[j].close;
   basis /= InpBBLength;

   double variance = 0.0;
   for(int j = index - InpBBLength + 1; j <= index; j++)
     {
      double diff = rates[j].close - basis;
      variance += diff * diff;
     }
   double dev = InpBBMultFactor * MathSqrt(variance / InpBBLength);
   double upper_bb = basis + dev;
   double lower_bb = basis - dev;

   // Keltner: ma = sma(close, KC), rangema = sma(range, KC)
   double ma = 0.0;
   double range_sum = 0.0;
   for(int j = index - InpKCLength + 1; j <= index; j++)
     {
      ma += rates[j].close;
      double range = rates[j].high - rates[j].low;
      if(InpUseTrueRange && j > 0)
        {
         double prev_close = rates[j - 1].close;
         range = MathMax(range, MathMax(MathAbs(rates[j].high - prev_close),
                                        MathAbs(rates[j].low  - prev_close)));
        }
      range_sum += range;
     }
   ma /= InpKCLength;
   double range_ma = range_sum / InpKCLength;
   double upper_kc = ma + range_ma * InpKCMultFactor;
   double lower_kc = ma - range_ma * InpKCMultFactor;

   bool sqz_on  = (lower_bb > lower_kc) && (upper_bb < upper_kc);
   bool sqz_off = (lower_bb < lower_kc) && (upper_bb > upper_kc);
   if(sqz_on)
      return SQZ_STATE_ON;
   if(sqz_off)
      return SQZ_STATE_OFF;
   return SQZ_STATE_NONE;
  }


// Read exactly one CLOSED indicator value; CopyBuffer is in shift coordinates.
bool ReadIndicator(const int handle,const int buffer,const int shift,double &value)
  {
   double v[1];
   if(CopyBuffer(handle,buffer,shift,1,v)!=1 || !MathIsValidNumber(v[0]) || v[0]==EMPTY_VALUE)
      return false;
   value=v[0];
   return true;
  }

ENUM_MARKET_REGIME DetectMarketRegime(const MarketSnapshot &s)
  {
   // Priority matters: panic and failed breakouts must override ordinary regimes.
   if(s.atr_ratio>=InpVolatileATRRatio && s.squeeze==SQZ_STATE_OFF)
      return REGIME_VOLATILE;
   bool reversal=(s.momentum*s.previous_momentum>0.0 &&
                  MathAbs(s.momentum)<MathAbs(s.previous_momentum));
   bool ema_conflict=(s.momentum>0.0 && s.close<s.ema) ||
                     (s.momentum<0.0 && s.close>s.ema);
   if(s.previous_squeeze==SQZ_STATE_OFF && (s.squeeze==SQZ_STATE_ON || (reversal && ema_conflict)))
      return REGIME_FAKEOUT;
   bool acceleration=(s.momentum*s.previous_momentum>0.0 &&
                      MathAbs(s.momentum)>MathAbs(s.previous_momentum));
   if(s.squeeze==SQZ_STATE_OFF && s.adx>=InpTrendADX && acceleration && !ema_conflict && s.momentum!=0.0)
      return REGIME_TREND;
   if(s.squeeze==SQZ_STATE_ON || (s.adx<=InpRangeADX && s.atr_ratio<=InpRangeATRRatio))
      return REGIME_RANGE;
   return REGIME_UNKNOWN; // ambiguous states freeze rather than guess
  }

bool ReadSnapshot(MarketSnapshot &s)
  {
   int need=(int)MathMax(2*InpKCLength+8,InpBBLength+4);
   MqlRates rates[];
   ArraySetAsSeries(rates,false);
   int count=CopyRates(_Symbol,g_tf,0,need,rates);
   if(count<need) return false;
   double values[]; ENUM_SQZ_BAR_COLOR colors[]; bool valid[];
   if(!ComputeMomentum(rates,values,colors,valid)) return false;
   int i=count-2;
   if(i<2 || !valid[i] || !valid[i-1] || !valid[i-2]) return false;
   s.squeeze=ComputeSqueezeState(rates,i);
   s.previous_squeeze=ComputeSqueezeState(rates,i-1);
   if(s.squeeze==SQZ_STATE_UNKNOWN || s.previous_squeeze==SQZ_STATE_UNKNOWN) return false;
   double baseline[];
   if(!ReadIndicator(g_atr,0,1,s.atr) || !ReadIndicator(g_adx,0,1,s.adx) ||
      !ReadIndicator(g_ema,0,1,s.ema) ||
      CopyBuffer(g_atr,0,2,InpATRBaselineBars,baseline)!=InpATRBaselineBars) return false;
   double sum=0.0;
   for(int j=0;j<InpATRBaselineBars;j++)
     {
      if(!MathIsValidNumber(baseline[j]) || baseline[j]<=0 || baseline[j]==EMPTY_VALUE) return false;
      sum+=baseline[j];
     }
   if(s.atr<=0 || sum<=0) return false;
   s.atr_ratio=s.atr/(sum/InpATRBaselineBars);
   s.momentum=values[i]; s.previous_momentum=values[i-1];
   s.close=rates[i].close; s.bar_time=rates[i].time;
   s.signal=SignalFromTransition(colors[i-1],colors[i]);
   s.trend_side=(s.momentum>0.0 ? 1 : (s.momentum<0.0 ? -1 : 0));
   s.regime=DetectMarketRegime(s);
   s.mode=(s.regime==REGIME_TREND ? MODE_HUNTER :
           (s.regime==REGIME_RANGE ? MODE_NORMAL : MODE_DEFENSE));
   s.valid=true;
   return true;
  }

double VolumeDown(double volume)
  {
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   double minvol=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxvol=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   if(step<=0 || minvol<=0 || maxvol<=0 || !MathIsValidNumber(volume)) return 0;
   volume=NormalizeDouble(MathFloor(MathMin(volume,maxvol)/step+1e-9)*step,8);
   return volume+1e-9<minvol ? 0.0 : volume;
  }

bool IsOurs(const ulong ticket)
  {
   if(ticket==0 || !PositionSelectByTicket(ticket) || PositionGetString(POSITION_SYMBOL)!=_Symbol) return false;
   ulong m=(ulong)PositionGetInteger(POSITION_MAGIC);
   return m==InpMagicNumber || m==InpMagicNumber+1 || m==InpMagicNumber+2;
  }

void ReadExposure(Exposure &e)
  {
   ZeroMemory(e);
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(!IsOurs(ticket)) continue;
      ulong m=(ulong)PositionGetInteger(POSITION_MAGIC);
      int side=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? 1 : -1;
      double lots=PositionGetDouble(POSITION_VOLUME);
      double profit=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
      e.gross+=lots; e.pnl+=profit;
      if(m==InpMagicNumber)
        {
         e.grids++; e.grid_pnl+=profit;
         if(side>0) e.grid_buy+=lots; else e.grid_sell+=lots;
         long t=PositionGetInteger(POSITION_TIME_MSC);
         if(t>=e.last_grid_time) { e.last_grid_time=t; e.last_grid_price=PositionGetDouble(POSITION_PRICE_OPEN); }
        }
      else if(m==InpMagicNumber+1) e.scalps++;
      else { e.hedges++; if(side>0) e.hedge_buy+=lots; else e.hedge_sell+=lots; }
     }
   if(e.grid_buy>0 && e.grid_sell==0) e.grid_side=1;
   else if(e.grid_sell>0 && e.grid_buy==0) e.grid_side=-1;
   else e.grid_side=0;
  }

double GridDrawdown(const Exposure &e)
  {
   double balance=AccountInfoDouble(ACCOUNT_BALANCE);
   return balance>0 ? MathMax(0.0,-e.grid_pnl)*100.0/balance : 100.0;
  }

GridPlan CalculateDynamicGrid(const MarketSnapshot &s,const Exposure &e)
  {
   GridPlan p;
   p.frozen=(s.mode==MODE_DEFENSE);
   p.side=(s.regime==REGIME_TREND ? s.trend_side : s.signal);
   double factor=(s.mode==MODE_DEFENSE ? InpDefenseStepFactor :
                  (s.mode==MODE_HUNTER ? InpHunterStepFactor : 1.0));
   p.step=s.atr*InpGridATR*factor;
   double multiplier=(s.regime==REGIME_TREND ? InpTrendMultiplier : InpRangeMultiplier);
   double compound=1.0;
   if(InpCompound)
      compound=MathMin(InpMaxCompoundFactor,MathMax(1.0,AccountInfoDouble(ACCOUNT_BALANCE)/InpCompoundReferenceBalance));
   p.lot=VolumeDown(InpBaseLot*compound*MathPow(multiplier,e.grids));
   return p;
  }

bool RetcodeAccepted(const bool sent)
  {
   uint code=trade.ResultRetcode();
   if(!sent || (code!=TRADE_RETCODE_DONE && code!=TRADE_RETCODE_DONE_PARTIAL && code!=TRADE_RETCODE_PLACED))
     {
      PrintFormat("Trade rejected: sent=%d retcode=%u %s",sent,code,trade.ResultRetcodeDescription());
      return false;
     }
   // Also rate-limit accepted partial/placed requests. Reconcile from positions next tick.
   g_last_order=TimeCurrent();
   return true;
  }

bool SpreadOK(const MqlTick &tick)
  {
   return tick.ask>0 && tick.bid>0 && tick.ask>=tick.bid &&
          (InpMaxSpreadPoints==0 || (tick.ask-tick.bid)/_Point<=InpMaxSpreadPoints);
  }

double TickPrice(double price,int direction)
  {
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tick<=0) tick=_Point;
   double n=price/tick;
   return NormalizeDouble((direction>0 ? MathCeil(n-1e-9) : MathFloor(n+1e-9))*tick,_Digits);
  }

bool HasOwnOrders()
  {
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0 || OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      ulong m=(ulong)OrderGetInteger(ORDER_MAGIC);
      if(m==InpMagicNumber || m==InpMagicNumber+1 || m==InpMagicNumber+2) return true;
     }
   return false;
  }

bool OpenLayer(const ulong magic,const int side,double lots,const double sl_distance,const double tp_distance,const string label)
  {
   if(!InpAllowTrading || side==0 || HasOwnOrders() || TimeCurrent()-g_last_order<InpCooldownSeconds) return false;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick) || !SpreadOK(tick)) return false;
   Exposure e; ReadExposure(e);
   lots=VolumeDown(MathMin(lots,InpMaxGrossLots-e.gross));
   if(lots<=0) return false;
   ENUM_ORDER_TYPE type=(side>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   double entry=(side>0 ? tick.ask : tick.bid), margin=0;
   if(!OrderCalcMargin(type,_Symbol,lots,entry,margin) || margin<=0 ||
      AccountInfoDouble(ACCOUNT_MARGIN_FREE)<margin*InpMinFreeMarginPercent/100.0)
     { Print("Order skipped: margin calculation or free margin limit."); return false; }
   double stop_level=SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   // Stops are checked from the close-side quote, not entry (spread matters).
   double reference=(side>0 ? tick.bid : tick.ask);
   double sl=0,tp=0;
   if(sl_distance>0)
     {
      double raw=(side>0 ? MathMin(entry-sl_distance,reference-stop_level-_Point) :
                           MathMax(entry+sl_distance,reference+stop_level+_Point));
      sl=TickPrice(raw,side>0 ? -1 : 1);
     }
   if(tp_distance>0)
     {
      double raw=(side>0 ? MathMax(entry+tp_distance,reference+stop_level+_Point) :
                           MathMin(entry-tp_distance,reference-stop_level-_Point));
      tp=TickPrice(raw,side>0 ? 1 : -1);
     }
   if((sl_distance>0 && sl<=0) || (tp_distance>0 && tp<=0)) return false;
   trade.SetExpertMagicNumber(magic);
   g_last_order=TimeCurrent(); // also throttle rejected orders
   bool sent=(side>0 ? trade.Buy(lots,_Symbol,0,sl,tp,label) : trade.Sell(lots,_Symbol,0,sl,tp,label));
   return RetcodeAccepted(sent);
  }

bool CloseTicket(const ulong ticket)
  {
   if(!InpAllowTrading || !IsOurs(ticket)) return false;
   bool sent=trade.PositionClose(ticket,InpDeviationPoints);
   return RetcodeAccepted(sent);
  }

void SetFlatten(const bool emergency)
  {
   g_flatten=true; GlobalVariableSet(g_flat_key,1.0);
   if(emergency) { g_stop=true; GlobalVariableSet(g_stop_key,1.0); }
  }

void CloseAllOurs()
  {
   // Cancel any still-active own orders before closing positions.
   for(int i=OrdersTotal()-1;i>=0;i--)
     {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0 || OrderGetString(ORDER_SYMBOL)!=_Symbol) continue;
      ulong m=(ulong)OrderGetInteger(ORDER_MAGIC);
      if(InpAllowTrading && (m==InpMagicNumber || m==InpMagicNumber+1 || m==InpMagicNumber+2))
         RetcodeAccepted(trade.OrderDelete(ticket));
     }
   // Retry on subsequent ticks on rejection/partial execution; never reopen while flattening.
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(IsOurs(ticket)) CloseTicket(ticket);
     }
   Exposure e; ReadExposure(e);
   if(e.grids+e.scalps+e.hedges==0 && !HasOwnOrders())
     { g_flatten=false; GlobalVariableSet(g_flat_key,0.0); }
  }

void CloseHedges()
  {
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      ulong ticket=PositionGetTicket(i);
      if(IsOurs(ticket) && (ulong)PositionGetInteger(POSITION_MAGIC)==InpMagicNumber+2)
         CloseTicket(ticket);
     }
  }

// Called on every tick for protection, and on a newly closed bar for scalp signals.
void ManageHedgingAndScalp(const bool new_bar)
  {
   Exposure e; ReadExposure(e);
   if(e.grids==0)
     {
      // Never leave an orphan hedge or scalp after the underlying basket disappears.
      if(e.hedges+e.scalps>0) { SetFlatten(false); CloseAllOurs(); }
      return;
     }
   if(e.grid_side==0) { SetFlatten(true); CloseAllOurs(); return; }
   double dd=GridDrawdown(e);
   bool lock=InpEnableHedge && (dd>=InpHedgeDrawdownPercent ||
                                (g_market.valid && g_market.regime==REGIME_VOLATILE));
   if(e.hedges>0 && !lock && g_market.valid && g_calm_bars>=InpReleaseConfirmBars &&
      dd<=InpHedgeReleasePercent)
     {
      CloseHedges();
      return; // do not trade while closing a hedge
     }
   if(lock)
     {
      // Target is signed grid exposure * ratio, net of already opened hedges.
      double grid_net=e.grid_buy-e.grid_sell;
      double hedge_net=e.hedge_buy-e.hedge_sell;
      double target=-grid_net*InpHedgeRatio;
      double required=target-hedge_net;
      // Grid SL/manual closures can make an existing hedge oversized or wrong-way.
      // Flatten hedge tickets, then rebuild on a later tick instead of over-hedging.
      double tolerance=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP)*0.5;
      if(e.hedges>0 && (hedge_net*target<=0 || MathAbs(hedge_net)>MathAbs(target)+tolerance))
        { CloseHedges(); return; }
      if(required*grid_net<0 && VolumeDown(MathAbs(required))>0)
         OpenLayer(InpMagicNumber+2,required>0 ? 1 : -1,MathAbs(required),0,0,"FDE hedge");
      return;
     }
   if(e.hedges>0 || !new_bar || !InpEnableScalp || !g_market.valid ||
      g_market.mode==MODE_DEFENSE || e.scalps>=InpMaxScalps || g_market.signal==0) return;
   OpenLayer(InpMagicNumber+1,g_market.signal,InpScalpLot,
             g_market.atr*InpScalpSLATR,g_market.atr*InpScalpTPATR,"FDE scalp");
  }

void ManageGrid(const bool new_bar)
  {
   if(!g_market.valid || g_stop || g_flatten) return;
   Exposure e; ReadExposure(e);
   if(e.hedges>0 || e.grids>=InpMaxGridPositions ||
      (InpEnableHedge && GridDrawdown(e)>=InpHedgeDrawdownPercent)) return;
   GridPlan p=CalculateDynamicGrid(g_market,e);
   if(p.frozen || p.step<=0 || p.lot<=0) return;
   MqlTick tick; if(!SymbolInfoTick(_Symbol,tick) || !SpreadOK(tick)) return;
   if(e.grids==0)
     {
      // First grid starts only on a new closed bar, no historical entries on startup.
      if(!new_bar || p.side==0) return;
     }
   else
     {
      // Never mix directions. Trend reversal freezes old basket, it does not flip it.
      if(e.grid_side==0 || (g_market.regime==REGIME_TREND && p.side!=e.grid_side)) return;
      p.side=e.grid_side;
      double current=(p.side>0 ? tick.ask : tick.bid);
      double delta=(current-e.last_grid_price)*p.side;
      // Hunter pyramids in profit; range grid averages only after an adverse step.
      if(g_market.regime==REGIME_TREND ? delta<p.step : delta>-p.step) return;
     }
   OpenLayer(InpMagicNumber,p.side,p.lot,g_market.atr*InpGridSLATR,0,"FDE grid");
  }

bool ProcessClosedBar(const bool allow_new_entries)
  {
   MarketSnapshot next;
   ZeroMemory(next);
   if(!ReadSnapshot(next)) { g_market.valid=false; return false; }
   g_market=next;
   if(next.regime==REGIME_RANGE || next.regime==REGIME_TREND) g_calm_bars++;
   else g_calm_bars=0;
   PrintFormat("FDE bar=%s regime=%s mode=%s momentum=%.6f ATR=%.6f ratio=%.2f ADX=%.1f signal=%d",
               TimeToString(next.bar_time),EnumToString(next.regime),EnumToString(next.mode),
               next.momentum,next.atr,next.atr_ratio,next.adx,next.signal);
   if(allow_new_entries) ManageHedgingAndScalp(true);
   return true;
  }

bool InputsValid()
  {
   return InpBBLength>=2 && InpKCLength>=2 && InpBBLength<=1000 && InpKCLength<=1000 &&
      MathIsValidNumber(InpBBMultFactor) && InpBBMultFactor>0 &&
      MathIsValidNumber(InpKCMultFactor) && InpKCMultFactor>0 &&
      InpATRPeriod>=2 && InpATRBaselineBars>=2 && InpATRBaselineBars<=1000 &&
      InpADXPeriod>=2 && InpEMAPeriod>=2 && InpReleaseConfirmBars>=1 &&
      MathIsValidNumber(InpRangeADX) && MathIsValidNumber(InpTrendADX) &&
      InpRangeADX>=0 && InpRangeADX<InpTrendADX && InpTrendADX<=100 &&
      MathIsValidNumber(InpRangeATRRatio) && MathIsValidNumber(InpVolatileATRRatio) &&
      InpRangeATRRatio>0 && InpVolatileATRRatio>1 && InpRangeATRRatio<InpVolatileATRRatio &&
      MathIsValidNumber(InpBaseLot) && InpBaseLot>0 && MathIsValidNumber(InpGridATR) && InpGridATR>0 &&
      MathIsValidNumber(InpDefenseStepFactor) && InpDefenseStepFactor>=1 &&
      MathIsValidNumber(InpHunterStepFactor) && InpHunterStepFactor>0 && InpHunterStepFactor<=1 &&
      MathIsValidNumber(InpRangeMultiplier) && InpRangeMultiplier>0 && InpRangeMultiplier<=3 &&
      MathIsValidNumber(InpTrendMultiplier) && InpTrendMultiplier>0 && InpTrendMultiplier<=3 &&
      InpMaxGridPositions>=1 && InpMaxGridPositions<=100 &&
      MathIsValidNumber(InpMaxGrossLots) && InpMaxGrossLots>0 &&
      MathIsValidNumber(InpBasketTargetMoney) && InpBasketTargetMoney>0 &&
      MathIsValidNumber(InpCompoundReferenceBalance) && InpCompoundReferenceBalance>0 &&
      MathIsValidNumber(InpMaxCompoundFactor) && InpMaxCompoundFactor>=1 &&
      MathIsValidNumber(InpHedgeDrawdownPercent) && InpHedgeDrawdownPercent>0 &&
      MathIsValidNumber(InpHedgeReleasePercent) && InpHedgeReleasePercent>=0 &&
      InpHedgeReleasePercent<InpHedgeDrawdownPercent &&
      MathIsValidNumber(InpHedgeRatio) && InpHedgeRatio>0 && InpHedgeRatio<=1 &&
      MathIsValidNumber(InpScalpLot) && InpScalpLot>0 && InpMaxScalps>=0 &&
      MathIsValidNumber(InpScalpSLATR) && InpScalpSLATR>0 &&
      MathIsValidNumber(InpScalpTPATR) && InpScalpTPATR>0 &&
      MathIsValidNumber(InpGridSLATR) && InpGridSLATR>0 &&
      InpMagicNumber>0 && InpMagicNumber<9223372036854775805 &&
      InpDeviationPoints>=0 && InpMaxSpreadPoints>=0 && InpCooldownSeconds>=1 &&
      MathIsValidNumber(InpMinFreeMarginPercent) && InpMinFreeMarginPercent>=100 &&
      MathIsValidNumber(InpAccountLossStopPercent) && InpAccountLossStopPercent>0 && InpAccountLossStopPercent<100;
  }

int OnInit()
  {
   if(!InputsValid()) { Print("FDE: invalid inputs."); return INIT_PARAMETERS_INCORRECT; }
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     { Print("FDE requires a hedging account; netting/exchange accounts are not supported."); return INIT_FAILED; }
   g_tf=(InpTimeframe==PERIOD_CURRENT ? (ENUM_TIMEFRAMES)Period() : InpTimeframe);
   if(PeriodSeconds(g_tf)<=0 || !SymbolSelect(_Symbol,true)) return INIT_FAILED;
   g_stop_key=StringFormat("FDE.%I64d.%s.%I64u.S",AccountInfoInteger(ACCOUNT_LOGIN),_Symbol,InpMagicNumber);
   g_flat_key=StringFormat("FDE.%I64d.%s.%I64u.F",AccountInfoInteger(ACCOUNT_LOGIN),_Symbol,InpMagicNumber);
   if(StringLen(g_stop_key)>63 || StringLen(g_flat_key)>63)
     { Print("FDE: terminal global variable key too long."); return INIT_FAILED; }
   g_stop=GlobalVariableCheck(g_stop_key) && GlobalVariableGet(g_stop_key)>0;
   g_flatten=GlobalVariableCheck(g_flat_key) && GlobalVariableGet(g_flat_key)>0;
   g_atr=iATR(_Symbol,g_tf,InpATRPeriod);
   g_adx=iADX(_Symbol,g_tf,InpADXPeriod);
   g_ema=iMA(_Symbol,g_tf,InpEMAPeriod,0,MODE_EMA,PRICE_CLOSE);
   if(g_atr==INVALID_HANDLE || g_adx==INVALID_HANDLE || g_ema==INVALID_HANDLE)
     { Print("FDE: indicator handle creation failed."); return INIT_FAILED; }
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetAsyncMode(false);
   if(!trade.SetTypeFillingBySymbol(_Symbol)) { Print("FDE: symbol filling mode unavailable."); return INIT_FAILED; }
   g_bar=iTime(_Symbol,g_tf,0);
   g_market.valid=false;
   PrintFormat("FDE ready. Trading=%s; stop latch=%s. Use unique magic numbers per instance.",
               InpAllowTrading ? "ON" : "OFF",g_stop ? "ON" : "OFF");
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   if(g_atr!=INVALID_HANDLE) IndicatorRelease(g_atr);
   if(g_adx!=INVALID_HANDLE) IndicatorRelease(g_adx);
   if(g_ema!=INVALID_HANDLE) IndicatorRelease(g_ema);
  }

void OnTick()
  {
   // Account-wide equity check; only this EA's positions/orders are closed.
   double balance=AccountInfoDouble(ACCOUNT_BALANCE), equity=AccountInfoDouble(ACCOUNT_EQUITY);
   if(balance>0 && (balance-equity)*100.0/balance>=InpAccountLossStopPercent && !g_stop)
     { Print("FDE: account loss circuit breaker latched."); SetFlatten(true); }
   if(g_stop || g_flatten)
     {
      if(g_stop && !g_flatten)
        {
         Exposure stopped; ReadExposure(stopped);
         if(stopped.grids+stopped.scalps+stopped.hedges==0 && !HasOwnOrders()) return;
         SetFlatten(true);
        }
      CloseAllOurs();
      return;
     }
   Exposure e; ReadExposure(e);
   if(e.grids>0 && e.pnl>=InpBasketTargetMoney)
     { Print("FDE: basket profit target reached."); SetFlatten(false); CloseAllOurs(); return; }

   datetime current=iTime(_Symbol,g_tf,0);
   if(current<=0) { g_market.valid=false; ManageHedgingAndScalp(false); return; }
   bool new_bar=(g_bar>0 && current!=g_bar);
   if(new_bar || !g_market.valid)
     {
      // On initial attachment build a snapshot, but do not replay old signals.
      if(!ProcessClosedBar(new_bar)) { ManageHedgingAndScalp(false); return; }
      g_bar=current;
     }
   ManageHedgingAndScalp(false);
   if(!g_flatten && !g_stop) ManageGrid(new_bar);
  }

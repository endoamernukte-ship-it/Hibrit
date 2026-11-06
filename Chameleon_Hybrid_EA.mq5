//+------------------------------------------------------------------+
//| Chameleon Hybrid EA - research / demo first                      |
//| Single symbol, single EA instance per account/symbol/magic.      |
//| No profitability or stop execution guarantees.                   |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "Regime-driven market grid, scalp and defensive risk reduction"
#include <Trade/Trade.mqh>

input ulong InpMagic = 5501284;
input ENUM_TIMEFRAMES InpTimeframe = PERIOD_M5;
input int InpATRPeriod = 14;
input int InpADXPeriod = 14;
input int InpEMAPeriod = 50;
input int InpLookback = 20;
input int InpConfirmBars = 2;
input int InpCooldownBars = 3;
input double InpRiskPerTradePct = 0.15;
input double InpMaxOpenRiskPct = 1.0;
input double InpDailyLossPct = 2.0;
input double InpBasketLossPct = 1.0;
input int InpMaxPositions = 4;
input double InpMinFreeMarginPct = 200.0;
input double InpMaxSpreadPoints = 25;
input double InpMaxSpreadATR = 0.12;
input double InpPanicATRRatio = 2.0;
input double InpPanicBarATR = 3.0;
input double InpTrendADX = 25;
input double InpTrendEfficiency = 0.45;
input double InpGridATR = 0.8;
input double InpStopATR = 2.0;
input double InpTakeATR = 1.2;
input double InpTrailATR = 1.5;
input double InpSlippagePoints = 10;
input double InpCostBufferPerLot = 10.0; // account currency, round trip estimate
input int InpMaxTickAgeSec = 15;
input int InpMinTradeIntervalSec = 60;
input bool InpEnableScalp = true;
input bool InpEnableFakeout = true;
input bool InpEnableHedge = false; // hedging accounts only; default is reduce/close
input double InpHedgeFraction = 0.25;
input double InpHedgeTriggerPct = 0.4; // floating basket loss / equity
input double InpShockATR = 1.5; // current bar move from open
input bool InpAllowLive = false;   // explicitly opt in for real accounts

enum Plan { PLAN_NONE, PLAN_RANGE, PLAN_TREND_LONG, PLAN_TREND_SHORT, PLAN_PANIC, PLAN_FAKE_LONG, PLAN_FAKE_SHORT };
CTrade trade;
int hATR=INVALID_HANDLE, hADX=INVALID_HANDLE, hEMA=INVALID_HANDLE;
Plan current=PLAN_NONE, candidate=PLAN_NONE, target=PLAN_NONE;
int confirmCount=0, cooldown=0;
bool transitioning=false, halted=false;
datetime lastBar=0, lastTrade=0, lastScalpBar=0;
double atr=0, adx=0, ema=0, atrBase=0, efficiency=0, rangeHigh=0, rangeLow=0;
double lastClose=0, prevClose=0, lastHigh=0, lastLow=0;
MqlTick tick;
string prefix;

string Key(string suffix) { return prefix+suffix; }
int DayKey(datetime t)
{
   MqlDateTime d; TimeToStruct(t,d);
   return d.year*1000+d.day_of_year;
}
void SetHalt(string why)
{
   if(!halted) Print("HALT: ",why);
   halted=true; GlobalVariableSet(Key("halt"),1);
}
bool TradingAllowed()
{
   if(!MQLInfoInteger(MQL_TRADE_ALLOWED) || !TerminalInfoInteger(TERMINAL_TRADE_ALLOWED) || !AccountInfoInteger(ACCOUNT_TRADE_ALLOWED)) return false;
   if(AccountInfoInteger(ACCOUNT_TRADE_MODE)==ACCOUNT_TRADE_MODE_REAL && !InpAllowLive) return false;
   return true;
}
bool TickValid()
{
   if(!SymbolInfoTick(_Symbol,tick) || tick.bid<=0 || tick.ask<=tick.bid || tick.time<=0) return false;
   datetime now=TimeTradeServer();
   if(now>0 && now-tick.time>InpMaxTickAgeSec) return false;
   return true;
}
bool SpreadOK()
{
   if(atr<=0) return false;
   double s=tick.ask-tick.bid;
   return s<=InpMaxSpreadPoints*_Point && s<=InpMaxSpreadATR*atr;
}
int OwnedPositions()
{
   int n=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket>0 && PositionGetString(POSITION_SYMBOL)==_Symbol && (ulong)PositionGetInteger(POSITION_MAGIC)==InpMagic) n++;
   }
   return n;
}
int OwnedOrders()
{
   int n=0;
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket>0 && OrderGetString(ORDER_SYMBOL)==_Symbol && (ulong)OrderGetInteger(ORDER_MAGIC)==InpMagic) n++;
   }
   return n;
}
bool TradeResultOK()
{
   uint r=trade.ResultRetcode();
   return r==TRADE_RETCODE_DONE || r==TRADE_RETCODE_DONE_PARTIAL || r==TRADE_RETCODE_PLACED;
}
void CancelOwnedOrders()
{
   for(int i=OrdersTotal()-1;i>=0;i--)
   {
      ulong ticket=OrderGetTicket(i);
      if(ticket==0 || OrderGetString(ORDER_SYMBOL)!=_Symbol || (ulong)OrderGetInteger(ORDER_MAGIC)!=InpMagic) continue;
      if(!trade.OrderDelete(ticket) || !TradeResultOK()) Print("Cancel failed ",ticket," ret=",trade.ResultRetcode());
   }
}
void CloseOwnedPositions()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol || (ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      if(!trade.PositionClose(ticket) || !TradeResultOK()) Print("Close failed ",ticket," ret=",trade.ResultRetcode());
   }
}
double BasketPnL()
{
   double total=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t>0 && PositionGetString(POSITION_SYMBOL)==_Symbol && (ulong)PositionGetInteger(POSITION_MAGIC)==InpMagic)
         total+=PositionGetDouble(POSITION_PROFIT)+PositionGetDouble(POSITION_SWAP);
   }
   return total; // floating profit and swap; commissions not included
}
bool AccountDailyLimit()
{
   int day=DayKey(TimeCurrent());
   if(!GlobalVariableCheck(Key("day")) || (int)GlobalVariableGet(Key("day"))!=day)
   {
      GlobalVariableSet(Key("day"),day);
      GlobalVariableSet(Key("equity"),AccountInfoDouble(ACCOUNT_EQUITY));
   }
   double start=GlobalVariableGet(Key("equity"));
   return start>0 && AccountInfoDouble(ACCOUNT_EQUITY)<=start*(1.0-InpDailyLossPct/100.0);
}
bool UpdateIndicators()
{
   double a[], x[], e[]; MqlRates rates[];
   ArraySetAsSeries(a,true); ArraySetAsSeries(x,true); ArraySetAsSeries(e,true); ArraySetAsSeries(rates,true);
   int need=InpLookback+4;
   if(CopyBuffer(hATR,0,1,InpLookback+1,a)<InpLookback+1 || CopyBuffer(hADX,0,1,1,x)<1 || CopyBuffer(hEMA,0,1,1,e)<1 || CopyRates(_Symbol,InpTimeframe,1,need,rates)<need) return false;
   atr=a[0]; adx=x[0]; ema=e[0]; atrBase=0;
   for(int i=1;i<=InpLookback;i++) atrBase+=a[i];
   atrBase/=InpLookback;
   if(atr<=0 || atrBase<=0) return false;
   lastClose=rates[0].close; prevClose=rates[1].close; lastHigh=rates[0].high; lastLow=rates[0].low;
   rangeHigh=rates[1].high; rangeLow=rates[1].low;
   double path=0;
   for(int i=0;i<InpLookback;i++)
   {
      path+=MathAbs(rates[i].close-rates[i+1].close);
      if(i>=1) { rangeHigh=MathMax(rangeHigh,rates[i].high); rangeLow=MathMin(rangeLow,rates[i].low); }
   }
   efficiency=(path>0 ? MathAbs(rates[0].close-rates[InpLookback].close)/path : 0);
   return true;
}
Plan DetectPlan()
{
   if(atr/atrBase>=InpPanicATRRatio || lastHigh-lastLow>=InpPanicBarATR*atr) return PLAN_PANIC;
   // Fakeout must breach the preceding range and close back inside it.
   if(InpEnableFakeout && lastHigh>rangeHigh+0.1*atr && lastClose<rangeHigh && lastClose<lastHigh-0.3*atr) return PLAN_FAKE_SHORT;
   if(InpEnableFakeout && lastLow<rangeLow-0.1*atr && lastClose>rangeLow && lastClose>lastLow+0.3*atr) return PLAN_FAKE_LONG;
   if(adx>=InpTrendADX && efficiency>=InpTrendEfficiency)
   {
      if(lastClose>ema && lastClose>prevClose) return PLAN_TREND_LONG;
      if(lastClose<ema && lastClose<prevClose) return PLAN_TREND_SHORT;
   }
   return PLAN_RANGE;
}
// Estimated remaining equity loss at each owned position's stop, including cost buffer.
// If a stop is absent or calculation fails, block all new entries.
double OpenRisk()
{
   double sum=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol || (ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      double sl=PositionGetDouble(POSITION_SL), vol=PositionGetDouble(POSITION_VOLUME);
      if(sl<=0) return DBL_MAX;
      ENUM_ORDER_TYPE type=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
      double profit=0, mark=(type==ORDER_TYPE_BUY ? tick.bid : tick.ask);
      if(!OrderCalcProfit(type,_Symbol,vol,mark,sl,profit)) return DBL_MAX;
      sum+=MathMax(0.0,-profit)+vol*InpCostBufferPerLot;
   }
   // This EA uses market entries only; unexpected owned pending orders block entry.
   if(OwnedOrders()>0) return DBL_MAX;
   return sum;
}
double RoundVolumeDown(double v)
{
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP), minv=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN), maxv=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   if(step<=0 || minv<=0 || maxv<minv) return 0;
   v=MathMin(v,maxv);
   v=NormalizeDouble(MathFloor((v+1e-10)/step)*step,8);
   if(v<minv) return 0;
   return v;
}
double NormalizePrice(double p)
{
   double ts=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(ts<=0) return 0;
   return NormalizeDouble(MathRound(p/ts)*ts,_Digits);
}
bool SendMarket(int dir, double stopDistance, double takeDistance, string label, double riskMultiplier=1.0, double maxVolume=DBL_MAX)
{
   if(halted || transitioning || current==PLAN_PANIC || !TradingAllowed() || !TickValid() || !SpreadOK()) return false;
   if(OwnedPositions()>=InpMaxPositions || TimeCurrent()-lastTrade<InpMinTradeIntervalSec) return false;
   // In netting mode we cannot safely isolate this EA from other positions.
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING && PositionSelect(_Symbol)) return false;
   ENUM_ORDER_TYPE type=(dir>0 ? ORDER_TYPE_BUY : ORDER_TYPE_SELL);
   double entry=(dir>0 ? tick.ask : tick.bid);
   double minDist=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   stopDistance=MathMax(stopDistance,minDist+2*_Point);
   takeDistance=MathMax(takeDistance,minDist+2*_Point);
   double sl=NormalizePrice(entry-dir*stopDistance), tp=NormalizePrice(entry+dir*takeDistance);
   // Broker validates stops against bid for buys and ask for sells.
   if(sl<=0 || tp<=0 || (dir>0 && (tick.bid-sl<minDist || tp-tick.bid<minDist)) || (dir<0 && (sl-tick.ask<minDist || tick.ask-tp<minDist))) return false;
   double p=0;
   if(!OrderCalcProfit(type,_Symbol,1.0,entry,sl,p) || p>=0) return false;
   double equity=AccountInfoDouble(ACCOUNT_EQUITY);
   double budget=MathMin(equity*InpRiskPerTradePct/100.0*riskMultiplier, equity*InpMaxOpenRiskPct/100.0-OpenRisk());
   double perLot=-p+InpCostBufferPerLot;
   if(budget<=0 || perLot<=0) return false;
   double volume=RoundVolumeDown(MathMin(budget/perLot,maxVolume));
   if(volume<=0) return false;
   double margin=0, free=AccountInfoDouble(ACCOUNT_MARGIN_FREE);
   if(!OrderCalcMargin(type,_Symbol,volume,entry,margin) || margin<=0 || free-margin<=0 || (free-margin)/margin*100.0<InpMinFreeMarginPct) return false;
   bool ok=(dir>0 ? trade.Buy(volume,_Symbol,0,sl,tp,label) : trade.Sell(volume,_Symbol,0,sl,tp,label));
   if(!ok || !TradeResultOK()) { Print("Entry failed: ",label," ret=",trade.ResultRetcode()); return false; }
   lastTrade=TimeCurrent();
   Print("Entry ",label," volume=",volume," sl=",sl," tp=",tp);
   return true;
}
void TrailPositions()
{
   if(current!=PLAN_TREND_LONG && current!=PLAN_TREND_SHORT) return;
   double minDist=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol || (ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      bool buy=PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY;
      double old=PositionGetDouble(POSITION_SL), tp=PositionGetDouble(POSITION_TP), open=PositionGetDouble(POSITION_PRICE_OPEN);
      double sl=NormalizePrice(buy ? tick.bid-InpTrailATR*atr : tick.ask+InpTrailATR*atr);
      if(buy && sl>open && sl>old+_Point && tick.bid-sl>minDist)
      { if(!trade.PositionModify(t,sl,tp) || !TradeResultOK()) Print("Trail failed ",t," ret=",trade.ResultRetcode()); }
      if(!buy && sl<open && (old==0 || sl<old-_Point) && sl-tick.ask>minDist)
      { if(!trade.PositionModify(t,sl,tp) || !TradeResultOK()) Print("Trail failed ",t," ret=",trade.ResultRetcode()); }
   }
}
bool LastEntryPrice(int dir, double &price)
{
   bool found=false; long latest=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol || (ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      if((dir>0 && PositionGetInteger(POSITION_TYPE)!=POSITION_TYPE_BUY) || (dir<0 && PositionGetInteger(POSITION_TYPE)!=POSITION_TYPE_SELL)) continue;
      long when=PositionGetInteger(POSITION_TIME_MSC);
      if(!found || when>latest) { latest=when; price=PositionGetDouble(POSITION_PRICE_OPEN); found=true; }
   }
   return found;
}
void RunPlan()
{
   if(!TickValid() || !SpreadOK()) return;
   TrailPositions();
   double mid=(tick.bid+tick.ask)/2.0, width=rangeHigh-rangeLow;
   int dir=0; string label="grid"; double mult=1.0;
   if(current==PLAN_TREND_LONG) dir=1;
   else if(current==PLAN_TREND_SHORT) dir=-1;
   else if(current==PLAN_RANGE && width>atr)
   {
      if(mid<rangeLow+width*0.25 && lastClose>prevClose) dir=1;
      else if(mid>rangeHigh-width*0.25 && lastClose<prevClose) dir=-1;
   }
   else if(current==PLAN_FAKE_LONG || current==PLAN_FAKE_SHORT)
   {
      // One attempt per confirmed fakeout activation, not per tick.
      if(OwnedPositions()>0) return;
      dir=(current==PLAN_FAKE_LONG ? 1 : -1); label="fakeout"; mult=0.5;
   }
   if(dir==0) return;
   double last=0;
   bool exists=LastEntryPrice(dir,last);
   if(exists)
   {
      // Range adds only on adverse movement; trend adds on favorable pullback.
      double step=InpGridATR*atr;
      if((dir>0 && tick.ask>last-step) || (dir<0 && tick.bid<last+step)) return;
      if(current==PLAN_FAKE_LONG || current==PLAN_FAKE_SHORT) return;
   }
   if(SendMarket(dir,InpStopATR*atr,InpTakeATR*atr,label,mult))
   {
      if(current==PLAN_FAKE_LONG || current==PLAN_FAKE_SHORT) { current=PLAN_NONE; cooldown=InpCooldownBars; }
      return;
   }
}
// Optional partial hedge on an intrabar shock. It is a distinct, stopped
// position, only on hedging accounts. If it cannot be placed, flatten instead.
bool TryDefensiveHedge()
{
   if(!InpEnableHedge || AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING || !TradingAllowed() || !TickValid() || !SpreadOK()) return false;
   double net=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong t=PositionGetTicket(i);
      if(t==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol || (ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      double v=PositionGetDouble(POSITION_VOLUME);
      net+=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? v : -v);
   }
   if(MathAbs(net)<SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN)) return false;
   int dir=(net>0 ? -1 : 1);
   return SendMarket(dir,InpStopATR*atr,InpTakeATR*atr,"defensive-hedge",1.0,MathAbs(net)*InpHedgeFraction);
}
void RunScalp()
{
   if(!InpEnableScalp || current!=PLAN_RANGE || lastScalpBar==lastBar || !TickValid() || !SpreadOK()) return;
   double width=rangeHigh-rangeLow, mid=(tick.bid+tick.ask)*0.5;
   if(width<atr) return;
   int dir=0;
   if(mid<rangeLow+0.35*width && lastClose>prevClose) dir=1;
   if(mid>rangeHigh-0.35*width && lastClose<prevClose) dir=-1;
   if(dir==0) return;
   // A scalp is a separate small-risk entry sharing the grid budget.
   if(SendMarket(dir,InpStopATR*atr,0.6*atr,"scalp",0.5)) lastScalpBar=lastBar;
}
void Process()
{
   if(!TickValid()) return;
   if(AccountDailyLimit()) SetHalt("daily equity loss limit");
   double eq=AccountInfoDouble(ACCOUNT_EQUITY);
   if(eq>0 && BasketPnL()<=-eq*InpBasketLossPct/100.0) SetHalt("basket loss limit");
   if(halted)
   {
      CancelOwnedOrders(); CloseOwnedPositions(); return;
   }
   if(!TradingAllowed()) return;
   if(transitioning)
   {
      CancelOwnedOrders(); CloseOwnedPositions();
      if(OwnedPositions()==0 && OwnedOrders()==0)
      {
         current=target; transitioning=false; cooldown=InpCooldownBars;
         Print("Transition complete, plan=",(int)current);
      }
      return;
   }
   datetime bar=iTime(_Symbol,InpTimeframe,0);
   if(bar<=0) return;
   if(bar!=lastBar)
   {
      if(!UpdateIndicators()) return;
      lastBar=bar;
      Plan next=DetectPlan();
      if(next==PLAN_PANIC)
      {
         target=PLAN_PANIC; transitioning=true; candidate=PLAN_NONE; confirmCount=0;
         CancelOwnedOrders(); CloseOwnedPositions(); return;
      }
      if(cooldown>0) cooldown--;
      if(next==candidate) confirmCount++; else { candidate=next; confirmCount=1; }
      if(next!=current && confirmCount>=InpConfirmBars && cooldown==0)
      {
         target=next; transitioning=true; candidate=PLAN_NONE; confirmCount=0;
         CancelOwnedOrders(); CloseOwnedPositions(); return;
      }
   }
   if(current!=PLAN_NONE && current!=PLAN_PANIC && atr>0 && OwnedPositions()>0 &&
      BasketPnL()<=-eq*InpHedgeTriggerPct/100.0 &&
      MathAbs((tick.bid+tick.ask)*0.5-iOpen(_Symbol,InpTimeframe,0))>=InpShockATR*atr)
   {
      // Freeze all entries immediately. A successful hedge is held until the
      // next confirmed regime transition; otherwise reduce risk by flattening.
      bool hedged=TryDefensiveHedge();
      current=PLAN_PANIC; cooldown=InpCooldownBars; candidate=PLAN_NONE; confirmCount=0;
      CancelOwnedOrders();
      if(!hedged) { target=PLAN_PANIC; transitioning=true; CloseOwnedPositions(); }
      return;
   }
   if(current!=PLAN_NONE && current!=PLAN_PANIC) { RunScalp(); RunPlan(); }
}
int OnInit()
{
   if(InpATRPeriod<2 || InpADXPeriod<2 || InpEMAPeriod<2 || InpLookback<5 || InpConfirmBars<1 || InpCooldownBars<0 || InpRiskPerTradePct<=0 || InpMaxOpenRiskPct<=0 || InpDailyLossPct<=0 || InpDailyLossPct>=100 || InpBasketLossPct<=0 || InpMaxPositions<1 || InpGridATR<=0 || InpStopATR<=0 || InpTakeATR<=0 || InpTrailATR<=0 || InpMaxSpreadPoints<=0 || InpMaxSpreadATR<=0 || InpMaxTickAgeSec<1 || InpMinTradeIntervalSec<0 || InpCostBufferPerLot<0 || InpHedgeFraction<=0 || InpHedgeFraction>1 || InpHedgeTriggerPct<=0 || InpHedgeTriggerPct>=InpBasketLossPct || InpShockATR<=0 || InpMinFreeMarginPct<0 || InpSlippagePoints<0)
      return INIT_PARAMETERS_INCORRECT;
   prefix=StringFormat("CHM.%I64d.%s.%I64u.",AccountInfoInteger(ACCOUNT_LOGIN),_Symbol,InpMagic);
   hATR=iATR(_Symbol,InpTimeframe,InpATRPeriod); hADX=iADX(_Symbol,InpTimeframe,InpADXPeriod); hEMA=iMA(_Symbol,InpTimeframe,InpEMAPeriod,0,MODE_EMA,PRICE_CLOSE);
   if(hATR==INVALID_HANDLE || hADX==INVALID_HANDLE || hEMA==INVALID_HANDLE) return INIT_FAILED;
   trade.SetExpertMagicNumber(InpMagic); trade.SetDeviationInPoints((ulong)InpSlippagePoints); trade.SetTypeFillingBySymbol(_Symbol); trade.SetAsyncMode(false);
   halted=GlobalVariableCheck(Key("halt")) && GlobalVariableGet(Key("halt"))>0;
   // Restart conservatively: flatten owned positions before selecting a plan.
   if(!halted && (OwnedPositions()>0 || OwnedOrders()>0)) { target=PLAN_NONE; transitioning=true; }
   EventSetTimer(1);
   Print("Chameleon initialized. Live trading ",InpAllowLive ? "enabled" : "disabled", "; optional hedge requires hedging account.");
   return INIT_SUCCEEDED;
}
void OnTick() { Process(); }
void OnTimer() { Process(); }
void OnTradeTransaction(const MqlTradeTransaction &trans,const MqlTradeRequest &request,const MqlTradeResult &result)
{
   // Process() re-reads server positions/orders on each tick/timer.
   if(trans.symbol==_Symbol && (trans.type==TRADE_TRANSACTION_REQUEST))
      Print("Trade transaction retcode=",result.retcode);
}
void OnDeinit(const int reason)
{
   EventKillTimer();
   if(hATR!=INVALID_HANDLE) IndicatorRelease(hATR);
   if(hADX!=INVALID_HANDLE) IndicatorRelease(hADX);
   if(hEMA!=INVALID_HANDLE) IndicatorRelease(hEMA);
}

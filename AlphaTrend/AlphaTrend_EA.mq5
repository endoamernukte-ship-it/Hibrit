// AlphaTrend Strategy, adapted from KivancOzbilgic's Pine Script v5.
// Mozilla Public License 2.0: https://mozilla.org/MPL/2.0/
#property copyright "KivancOzbilgic; MT5 adaptation"
#property link      "https://mozilla.org/MPL/2.0/"
#property version   "1.00"
#property strict
#include <Trade/Trade.mqh>
#include "AlphaTrendCore.mqh"

input double          InpMultiplier=1.0;          // Multiplier
input int             InpPeriod=14;               // Common Period
input ENUM_AT_SOURCE  InpSource=AT_CLOSE;         // RSI source (MFI always uses HLC3)
input bool            InpNoVolumeData=false;      // Change calculation (no volume data)?
input ENUM_AT_VOLUME  InpVolume=AT_TICK_VOLUME;   // MFI volume source
input double          InpLots=0.01;               // Target position size, lots
input ulong           InpMagic=20261106;           // Expert magic number
input ulong           InpDeviation=20;             // Maximum deviation in points
input int             InpHistoryBars=20000;       // Calculation history including current bar

CTrade trade;
datetime observed_bar=0;

bool TradeSucceeded()
{
   uint rc=trade.ResultRetcode();
   return rc==TRADE_RETCODE_DONE || rc==TRADE_RETCODE_DONE_PARTIAL || rc==TRADE_RETCODE_PLACED;
}

bool ValidLots()
{
   double minvol=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double maxvol=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step<=0 || InpLots<minvol-1e-9 || InpLots>maxvol+1e-9) return false;
   return MathAbs(InpLots/step-MathRound(InpLots/step))<1e-7;
}

void ExecuteSignal(int direction)
{
   // Netting positions are shared per symbol, so never touch somebody else's position.
   bool netting=(AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
   bool same=false, opposite=false;
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic)
      {
         if(netting) { Print("AlphaTrend: external netting position exists; signal skipped."); return; }
         continue;
      }
      int side=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? 1 : -1);
      if(side==direction) same=true; else opposite=true;
   }
   if(same && !opposite) return; // strategy.entry default pyramiding = 0
   // Close opposing owned positions before opening the new target direction.
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol ||
         (ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      int side=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? 1 : -1);
      if(side!=direction)
      {
         if(!trade.PositionClose(ticket,InpDeviation) || !TradeSucceeded())
         {
            PrintFormat("AlphaTrend: close failed, ticket=%I64u, retcode=%u %s",ticket,trade.ResultRetcode(),trade.ResultRetcodeDescription());
            return;
         }
         // A partial fill or an asynchronous placement must not be followed by a new position.
         if(PositionSelectByTicket(ticket)) { Print("AlphaTrend: position not fully closed; reversal aborted."); return; }
      }
   }
   if(same) return;
   bool sent=(direction>0 ? trade.Buy(InpLots,_Symbol,0,0,0,"AlphaTrend Long")
                          : trade.Sell(InpLots,_Symbol,0,0,0,"AlphaTrend Short"));
   if(!sent || !TradeSucceeded())
      PrintFormat("AlphaTrend: entry failed, retcode=%u %s",trade.ResultRetcode(),trade.ResultRetcodeDescription());
}

int OnInit()
{
   if(InpPeriod<1 || InpPeriod>100000 || !MathIsValidNumber(InpMultiplier) ||
      InpHistoryBars<InpPeriod+4 || !ValidLots())
   {
      Print("AlphaTrend: invalid period, multiplier, history or broker lot size.");
      return INIT_PARAMETERS_INCORRECT;
   }
   trade.SetExpertMagicNumber(InpMagic);
   trade.SetDeviationInPoints(InpDeviation);
   trade.SetTypeFillingBySymbol(_Symbol);
   return INIT_SUCCEEDED;
}

void OnTick()
{
   datetime current=iTime(_Symbol,_Period,0);
   if(current==0) return;
   // Do not enter on an old signal when attaching/restarting the EA.
   if(observed_bar==0) { observed_bar=current; return; }
   if(current==observed_bar) return;
   MqlRates rates[];
   ArraySetAsSeries(rates,false);
   int n=CopyRates(_Symbol,_Period,0,InpHistoryBars,rates);
   if(n<InpPeriod+4 || rates[n-1].time!=current) return; // retry once history is ready
   double alpha[]; int buy[],sell[];
   if(!ATCalculate(rates,n,InpPeriod,InpMultiplier,InpNoVolumeData,InpSource,InpVolume,alpha,buy,sell)) return;
   observed_bar=current; // one attempt per signal, no retry on rejected orders
   int last=n-2; // most recently closed bar; execute at first available tick of new bar
   if(buy[last]!=0) ExecuteSignal(1);
   else if(sell[last]!=0) ExecuteSignal(-1);
}

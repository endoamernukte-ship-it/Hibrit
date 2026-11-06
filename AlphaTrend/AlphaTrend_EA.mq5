// AlphaTrend Strategy, adapted from KivancOzbilgic's Pine Script v5.
// Mozilla Public License 2.0: https://mozilla.org/MPL/2.0/
#property copyright "KivancOzbilgic; MT5 adaptation"
#property link      "https://mozilla.org/MPL/2.0/"
#property version   "1.10"
#property strict
#include <Trade/Trade.mqh>
// The calculation is embedded so this EA can be compiled as a single file.
// AlphaTrend calculation adapted from KivancOzbilgic's Pine Script v5.
// Original source and this adaptation are subject to Mozilla Public License 2.0.
// https://mozilla.org/MPL/2.0/
enum ENUM_AT_SOURCE { AT_CLOSE, AT_OPEN, AT_HIGH, AT_LOW, AT_HL2, AT_HLC3, AT_OHLC4 };
enum ENUM_AT_VOLUME { AT_TICK_VOLUME, AT_REAL_VOLUME };

// Pine comparisons round operands to nine decimal places.
double ATComparable(double value) { return MathRound(value*1000000000.0)/1000000000.0; }

double ATSource(const MqlRates &r, ENUM_AT_SOURCE source)
{
   switch(source)
   {
      case AT_OPEN: return r.open;
      case AT_HIGH: return r.high;
      case AT_LOW: return r.low;
      case AT_HL2: return (r.high+r.low)/2.0;
      case AT_HLC3: return (r.high+r.low+r.close)/3.0;
      case AT_OHLC4: return (r.open+r.high+r.low+r.close)/4.0;
      default: return r.close;
   }
}

// rates must be in oldest-to-newest order. EMPTY_VALUE represents Pine's na.
// buy/sell are the unfiltered strategy.entry crosses, NOT the plotshape filter.
bool ATCalculate(const MqlRates &rates[], int n, int period, double coeff,
                 bool no_volume, ENUM_AT_SOURCE source, ENUM_AT_VOLUME volume_mode,
                 double &alpha[], int &buy[], int &sell[])
{
   if(n<=0 || period<1) return false;
   if(ArrayResize(alpha,n)!=n || ArrayResize(buy,n)!=n || ArrayResize(sell,n)!=n) return false;
   double tr[], pos[], neg[];
   if(ArrayResize(tr,n)!=n || ArrayResize(pos,n)!=n || ArrayResize(neg,n)!=n) return false;
   double tr_sum=0.0, pos_sum=0.0, neg_sum=0.0;
   double gain_sum=0.0, loss_sum=0.0, avg_gain=0.0, avg_loss=0.0;
   for(int i=0;i<n;i++)
   {
      buy[i]=0; sell[i]=0;
      tr[i]=0.0; pos[i]=0.0; neg[i]=0.0;
      double typical=(rates[i].high+rates[i].low+rates[i].close)/3.0;
      double vol=(double)(volume_mode==AT_REAL_VOLUME ? rates[i].real_volume : rates[i].tick_volume);
      if(i>0)
      {
         tr[i]=MathMax(rates[i].high-rates[i].low,
                       MathMax(MathAbs(rates[i].high-rates[i-1].close),MathAbs(rates[i].low-rates[i-1].close)));
         double previous_typical=(rates[i-1].high+rates[i-1].low+rates[i-1].close)/3.0;
         double typical_change=ATComparable(typical-previous_typical);
         if(typical_change>0.0) pos[i]=typical*vol;
         if(typical_change<0.0) neg[i]=typical*vol;
         double change=ATSource(rates[i],source)-ATSource(rates[i-1],source);
         double gain=MathMax(change,0.0), loss=MathMax(-change,0.0);
         if(i<=period)
         {
            gain_sum+=gain; loss_sum+=loss;
            if(i==period) { avg_gain=gain_sum/period; avg_loss=loss_sum/period; }
         }
         else
         {
            avg_gain=(avg_gain*(period-1)+gain)/period;
            avg_loss=(avg_loss*(period-1)+loss)/period;
         }
      }
      else
      {
         // Pine v5's documented ta.mfi equivalent treats the first na change
         // as false in both ternary conditions, adding flow to both sums.
         pos[i]=typical*vol; neg[i]=typical*vol;
      }
      tr_sum+=tr[i]; pos_sum+=pos[i]; neg_sum+=neg[i];
      if(i>=period)
      {
         tr_sum-=tr[i-period]; pos_sum-=pos[i-period]; neg_sum-=neg[i-period];
      }
      // ta.tr (the variable, unlike ta.tr(true)) is na on the first bar.
      if(i<period) { alpha[i]=EMPTY_VALUE; continue; }
      double oscillator=EMPTY_VALUE;
      if(no_volume)
      {
         if(ATComparable(avg_loss)==0.0) oscillator=100.0;
         else if(avg_loss>0.0) oscillator=100.0-100.0/(1.0+avg_gain/avg_loss);
      }
      else if(neg_sum==0.0 && pos_sum>0.0) oscillator=100.0;
      else if(neg_sum>0.0) oscillator=100.0-100.0/(1.0+pos_sum/neg_sum);
      double previous=(alpha[i-1]==EMPTY_VALUE ? 0.0 : alpha[i-1]);
      double atr=tr_sum/period;
      double up=rates[i].low-atr*coeff;
      double down=rates[i].high+atr*coeff;
      // An na comparison in Pine v5's conditional selects its false branch.
      alpha[i]=(oscillator!=EMPTY_VALUE && ATComparable(oscillator)>=50.0)
               ? (ATComparable(up)<ATComparable(previous) ? previous : up)
               : (ATComparable(down)>ATComparable(previous) ? previous : down);
      if(i>=3 && alpha[i-1]!=EMPTY_VALUE && alpha[i-2]!=EMPTY_VALUE && alpha[i-3]!=EMPTY_VALUE)
      {
         buy[i]=(ATComparable(alpha[i])>ATComparable(alpha[i-2]) && ATComparable(alpha[i-1])<=ATComparable(alpha[i-3])) ? 1 : 0;
         sell[i]=(ATComparable(alpha[i])<ATComparable(alpha[i-2]) && ATComparable(alpha[i-1])>=ATComparable(alpha[i-3])) ? 1 : 0;
      }
   }
   return true;
}

input group "1) AlphaTrend ayarlari"
input double          InpMultiplier=1.0;          // Multiplier
input int             InpPeriod=14;               // Common Period
input ENUM_AT_SOURCE  InpSource=AT_CLOSE;         // RSI source (MFI always uses HLC3)
input bool            InpNoVolumeData=false;      // Change calculation (no volume data)?
input ENUM_AT_VOLUME  InpVolume=AT_TICK_VOLUME;   // MFI volume source
input int             InpHistoryBars=20000;       // Hesaplama gecmisi (acik mum dahil)

input group "2) Ters islem"
input bool            InpReverseTrading=false;     // BUY sinyali SELL, SELL sinyali BUY acar

input group "3) Cikislar (0 = kapali)"
input int             InpTakeProfitSignalCount=0;  // TP: girisle ayni yonlu uygun sinyal sayisi
input int             InpStopLossSignalCount=0;    // SL: girisle ters yonlu uygun sinyal sayisi
input int             InpFixedTakeProfitPoints=0;  // Ekstra sabit TP (point)
input int             InpFixedStopLossPoints=0;    // Ekstra sabit SL (point)

input group "4) Pozisyon ve emir"
input double          InpLots=0.01;               // Target position size, lots
input ulong           InpMagic=20261106;           // Expert magic number
input ulong           InpDeviation=20;             // Maximum deviation in points

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

// The extra fixed SL/TP is submitted with the entry order. Distances are
// measured in MT5 points from the current Ask (buy) or Bid (sell).
double PriceOnTick(double price, bool round_up)
{
   double tick=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(tick<=0.0) tick=_Point;
   double units=price/tick;
   return NormalizeDouble((round_up ? MathCeil(units-1e-10) : MathFloor(units+1e-10))*tick,_Digits);
}

bool BuildFixedExits(int direction, double &sl, double &tp)
{
   sl=0.0; tp=0.0;
   if(InpFixedTakeProfitPoints==0 && InpFixedStopLossPoints==0) return true;
   MqlTick quote;
   if(!SymbolInfoTick(_Symbol,quote) || quote.bid<=0.0 || quote.ask<=0.0 || quote.ask<quote.bid)
   {
      Print("AlphaTrend: SL/TP icin gecerli fiyat alinamadi.");
      return false;
   }
   double entry=(direction>0 ? quote.ask : quote.bid);
   if(InpFixedTakeProfitPoints>0)
      tp=PriceOnTick(entry+direction*InpFixedTakeProfitPoints*_Point,direction>0);
   if(InpFixedStopLossPoints>0)
      sl=PriceOnTick(entry-direction*InpFixedStopLossPoints*_Point,direction<0);
   double min_distance=(double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point;
   double close_price=(direction>0 ? quote.bid : quote.ask);
   if((InpFixedTakeProfitPoints>0 && (tp<=0.0 || direction*(tp-close_price)<min_distance || direction*(tp-close_price)<=0.0)) ||
      (InpFixedStopLossPoints>0 && (sl<=0.0 || direction*(close_price-sl)<min_distance || direction*(close_price-sl)<=0.0)))
   {
      Print("AlphaTrend: sabit SL/TP mesafesi spread veya broker minimumu icin cok yakin; emir gonderilmedi.");
      return false;
   }
   return true;
}

// Signal-count exits use raw AlphaTrend signal directions, as in the other EA.
// Only closed bars after position entry are counted, with the closing price
// strictly beyond the entry price in the profitable/adverse direction.
void ManageSignalExits(const MqlRates &rates[], int n, const int &buy[], const int &sell[])
{
   if(InpTakeProfitSignalCount==0 && InpStopLossSignalCount==0) return;
   for(int p=PositionsTotal()-1;p>=0;p--)
   {
      ulong ticket=PositionGetTicket(p);
      if(ticket==0 || PositionGetString(POSITION_SYMBOL)!=_Symbol ||
         (ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagic) continue;
      int side=(PositionGetInteger(POSITION_TYPE)==POSITION_TYPE_BUY ? 1 : -1);
      double entry=PositionGetDouble(POSITION_PRICE_OPEN);
      datetime opened=(datetime)PositionGetInteger(POSITION_TIME);
      if(entry<=0.0 || opened==0) continue;
      // Never silently count only part of a position's history.
      if(rates[0].time>opened)
      {
         PrintFormat("AlphaTrend: ticket=%I64u icin acilistan itibaren yeterli gecmis yok; InpHistoryBars degerini artirin.",ticket);
         continue;
      }
      int tp_count=0, sl_count=0;
      string reason="";
      for(int i=0;i<n-1;i++)
      {
         // The next bar's actual open time is the close boundary, including gaps.
         if(rates[i+1].time<=opened) continue;
         int raw=(buy[i]!=0 ? 1 : (sell[i]!=0 ? -1 : 0));
         if(raw==0) continue;
         double change=side*(rates[i].close-entry);
         if(raw==side && change>0.0) tp_count++;
         else if(raw==-side && change<0.0) sl_count++;
         if(InpTakeProfitSignalCount>0 && tp_count>=InpTakeProfitSignalCount) { reason="TP sinyal sayisi"; break; }
         if(InpStopLossSignalCount>0 && sl_count>=InpStopLossSignalCount) { reason="SL sinyal sayisi"; break; }
      }
      if(reason=="") continue;
      if(!trade.PositionClose(ticket,InpDeviation) || !TradeSucceeded() || PositionSelectByTicket(ticket))
         PrintFormat("AlphaTrend: %s kapatma basarisiz/eksik; ticket=%I64u retcode=%u %s",reason,ticket,trade.ResultRetcode(),trade.ResultRetcodeDescription());
      else PrintFormat("AlphaTrend: ticket=%I64u %s ile kapandi (TP=%d, SL=%d).",ticket,reason,tp_count,sl_count);
   }
}

bool HasOwnedPosition()
{
   for(int i=PositionsTotal()-1;i>=0;i--)
   {
      ulong ticket=PositionGetTicket(i);
      if(ticket!=0 && PositionGetString(POSITION_SYMBOL)==_Symbol &&
         (ulong)PositionGetInteger(POSITION_MAGIC)==InpMagic) return true;
   }
   return false;
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
   double sl=0.0,tp=0.0;
   if(!BuildFixedExits(direction,sl,tp)) return;
   bool sent=(direction>0 ? trade.Buy(InpLots,_Symbol,0,sl,tp,"AlphaTrend Long")
                          : trade.Sell(InpLots,_Symbol,0,sl,tp,"AlphaTrend Short"));
   if(!sent || !TradeSucceeded())
      PrintFormat("AlphaTrend: entry failed, retcode=%u %s",trade.ResultRetcode(),trade.ResultRetcodeDescription());
}

int OnInit()
{
   if(InpPeriod<1 || InpPeriod>100000 || !MathIsValidNumber(InpMultiplier) ||
      InpHistoryBars<InpPeriod+4 || !ValidLots() || InpTakeProfitSignalCount<0 ||
      InpStopLossSignalCount<0 || InpFixedTakeProfitPoints<0 || InpFixedStopLossPoints<0)
   {
      Print("AlphaTrend: gecersiz periyot, gecmis, lot veya cikis ayari.");
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
   bool signal_exit_mode=(InpTakeProfitSignalCount>0 || InpStopLossSignalCount>0);
   if(signal_exit_mode)
   {
      ManageSignalExits(rates,n,buy,sell);
      // Waiting for a count exit replaces Pine's immediate reversal while a
      // position remains open. This makes counts greater than one meaningful.
      if(HasOwnedPosition()) return;
   }
   int raw=(buy[last]!=0 ? 1 : (sell[last]!=0 ? -1 : 0));
   if(raw!=0) ExecuteSignal(InpReverseTrading ? -raw : raw);
}

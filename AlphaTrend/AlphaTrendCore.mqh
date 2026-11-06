// AlphaTrend calculation adapted from KivancOzbilgic's Pine Script v5.
// Original source and this adaptation are subject to Mozilla Public License 2.0.
// https://mozilla.org/MPL/2.0/
#ifndef ALPHATREND_CORE_MQH
#define ALPHATREND_CORE_MQH

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
#endif

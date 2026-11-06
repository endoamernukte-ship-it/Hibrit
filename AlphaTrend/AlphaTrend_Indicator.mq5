// Visual companion for AlphaTrend Strategy by KivancOzbilgic.
// Mozilla Public License 2.0: https://mozilla.org/MPL/2.0/
#property copyright "KivancOzbilgic; MT5 adaptation"
#property link "https://mozilla.org/MPL/2.0/"
#property version "1.00"
#property indicator_chart_window
#property indicator_buffers 6
#property indicator_plots 5
#property indicator_label1 "AlphaTrend fill"
#property indicator_type1 DRAW_FILLING
#property indicator_color1 clrLimeGreen,clrMaroon
#property indicator_label2 "AlphaTrend"
#property indicator_type2 DRAW_LINE
#property indicator_color2 clrBlue
#property indicator_width2 3
#property indicator_label3 "AlphaTrend[2]"
#property indicator_type3 DRAW_LINE
#property indicator_color3 clrRed
#property indicator_width3 3
#property indicator_label4 "BUY"
#property indicator_type4 DRAW_ARROW
#property indicator_color4 clrBlue
#property indicator_label5 "SELL"
#property indicator_type5 DRAW_ARROW
#property indicator_color5 clrMaroon
#include "AlphaTrendCore.mqh"

input double          InpMultiplier=1.0;          // Multiplier
input int             InpPeriod=14;               // Common Period
input ENUM_AT_SOURCE  InpSource=AT_CLOSE;         // RSI source
input bool            InpShowSignals=false;       // Show Signals?
input bool            InpNoVolumeData=false;      // Change calculation (no volume data)?
input ENUM_AT_VOLUME  InpVolume=AT_TICK_VOLUME;   // MFI volume source
input int             InpHistoryBars=20000;       // Calculation history including current bar

double fill_a[],fill_b[],line_a[],line_b[],buy_plot[],sell_plot[];
int OnInit()
{
   if(InpPeriod<1 || InpPeriod>100000 || InpHistoryBars<InpPeriod+4 || !MathIsValidNumber(InpMultiplier)) return INIT_PARAMETERS_INCORRECT;
   SetIndexBuffer(0,fill_a,INDICATOR_DATA); SetIndexBuffer(1,fill_b,INDICATOR_DATA);
   SetIndexBuffer(2,line_a,INDICATOR_DATA); SetIndexBuffer(3,line_b,INDICATOR_DATA);
   SetIndexBuffer(4,buy_plot,INDICATOR_DATA); SetIndexBuffer(5,sell_plot,INDICATOR_DATA);
   ArraySetAsSeries(fill_a,false); ArraySetAsSeries(fill_b,false);
   ArraySetAsSeries(line_a,false); ArraySetAsSeries(line_b,false);
   ArraySetAsSeries(buy_plot,false); ArraySetAsSeries(sell_plot,false);
   for(int p=0;p<5;p++) PlotIndexSetDouble(p,PLOT_EMPTY_VALUE,EMPTY_VALUE);
   PlotIndexSetInteger(3,PLOT_ARROW,233); PlotIndexSetInteger(4,PLOT_ARROW,234);
   IndicatorSetString(INDICATOR_SHORTNAME,"AlphaTrend Strategy");
   return INIT_SUCCEEDED;
}

int OnCalculate(const int rates_total,const int prev_calculated,const datetime &time[],
                const double &open[],const double &high[],const double &low[],const double &close[],
                const long &tick_volume[],const long &volume[],const int &spread[])
{
   if(rates_total<InpPeriod+4) return 0;
   ArrayInitialize(fill_a,EMPTY_VALUE); ArrayInitialize(fill_b,EMPTY_VALUE);
   ArrayInitialize(line_a,EMPTY_VALUE); ArrayInitialize(line_b,EMPTY_VALUE);
   ArrayInitialize(buy_plot,EMPTY_VALUE); ArrayInitialize(sell_plot,EMPTY_VALUE);
   MqlRates rates[]; ArraySetAsSeries(rates,false);
   int n=CopyRates(_Symbol,_Period,0,MathMin(rates_total,InpHistoryBars),rates);
   if(n<InpPeriod+4) return 0;
   double alpha[]; int buy[],sell[];
   if(!ATCalculate(rates,n,InpPeriod,InpMultiplier,InpNoVolumeData,InpSource,InpVolume,alpha,buy,sell)) return 0;
   int offset=rates_total-n, last_buy=-1, last_sell=-1;
   for(int i=0;i<n;i++)
   {
      int j=offset+i;
      line_a[j]=alpha[i];
      if(i>=2 && alpha[i]!=EMPTY_VALUE && alpha[i-2]!=EMPTY_VALUE)
      {
         line_b[j]=alpha[i-2]; fill_a[j]=alpha[i]; fill_b[j]=alpha[i-2];
         // O1 > K2 and O2 > K1 apply only to shapes, not EA orders.
         if(InpShowSignals && buy[i]!=0 && last_buy>=0 && last_sell>=0 && last_buy<last_sell)
            buy_plot[j]=alpha[i-2]*0.9999;
         if(InpShowSignals && sell[i]!=0 && last_buy>=0 && last_sell>=0 && last_sell<last_buy)
            sell_plot[j]=alpha[i-2]*1.0001;
      }
      if(buy[i]!=0) last_buy=i;
      if(sell[i]!=0) last_sell=i;
   }
   return rates_total;
}

//+------------------------------------------------------------------+
//|                                      T3_CCI_SignalTraderEA.mq5   |
//| FX Sniper: T3-CCI Pine indicator signal trader for MetaTrader 5  |
//| Opens LONG on green (T3-CCI >= 0), SHORT on red (T3-CCI < 0).    |
//| No grid logic: trades are opened directly from the Pine signal.   |
//+------------------------------------------------------------------+
#property strict
#property version   "1.00"
#property description "Pine-compatible FX Sniper T3-CCI signal trader; no grid logic"

#include <Trade/Trade.mqh>

CTrade trade;

enum ENUM_T3_TP_MODE
  {
   T3_TP_NONE = 0,             // Take profit kapalı
   T3_TP_POINTS = 1,           // Sabit points mesafesi
   T3_TP_ATR = 2,              // ATR çarpanı
   T3_TP_OPPOSITE_SIGNAL = 3,  // Karşı renk/sinyal gelince kapat
   T3_TP_AFTER_BARS = 4        // Girişten sonra N sinyal mumu geçince kapat
  };

enum ENUM_T3_SL_MODE
  {
   T3_SL_NONE = 0,             // Stop loss kapalı
   T3_SL_POINTS = 1,           // Sabit points mesafesi
   T3_SL_ATR = 2                // ATR çarpanı
  };

enum ENUM_T3_LOT_MODE
  {
   T3_LOT_FIXED = 0,            // Sabit lot
   T3_LOT_RISK_PERCENT = 1      // SL mesafesine göre bakiye riski
  };

input group "Pine sinyali: FX Sniper T3-CCI"
input ENUM_TIMEFRAMES InpSignalTimeframe = PERIOD_CURRENT; // Sinyal zaman dilimi
input int             InpCCIPeriod = 14;                  // Pine CCI_Period
input int             InpT3Period = 5;                     // Pine T3_Period
input double          InpT3Factor = 0.618;                 // Pine b
input int             InpHistoryBars = 3000;               // T3 başlangıç yakınsaması için geçmiş
input bool            InpUseClosedBar = true;              // true: kapanmış mum; false: canlı mum
input int             InpLiveRefreshSeconds = 1;            // Canlı mum hesaplama aralığı
input bool            InpTradeOnStartupSignal = true;       // EA başlarken mevcut renge göre ilk işlem aç
input bool            InpReverseSignal = false;             // true: yeşil=SHORT, kırmızı=LONG

input group "İşlem yönetimi"
input bool            InpCloseOnOppositeSignal = true;      // Renk değişince ters pozisyonu kapat ve yeni yöne gir
input int             InpMaxPositions = 1;                  // Bu sembol/magic için açık pozisyon sınırı; 0=sınırsız
input int             InpMaxSpreadPoints = 0;               // 0=spread filtresi kapalı
input ENUM_T3_LOT_MODE InpLotMode = T3_LOT_FIXED;
input double          InpFixedLots = 0.01;
input double          InpRiskPercent = 1.0;                 // SL mesafesi baz alınır
input ulong           InpMagicNumber = 20261106;
input ulong           InpDeviationPoints = 20;

input group "Take profit"
input ENUM_T3_TP_MODE InpTakeProfitMode = T3_TP_OPPOSITE_SIGNAL;
input double          InpTakeProfitPoints = 1000.0;          // TP_POINTS modu
input double          InpTakeProfitATRMultiplier = 2.0;      // TP_ATR modu
input int             InpTakeProfitAfterBars = 10;           // TP_AFTER_BARS modu

input group "Stop loss"
input ENUM_T3_SL_MODE InpStopLossMode = T3_SL_ATR;
input double          InpStopLossPoints = 1000.0;            // SL_POINTS modu
input double          InpStopLossATRMultiplier = 2.0;        // SL_ATR modu
input int             InpATRPeriod = 14;

input group "Görsel ve bildirimler"
input bool            InpDrawSignalArrows = true;
input bool            InpAlertsOn = false;
input bool            InpPushOn = false;
input bool            InpShowStatus = true;

int      g_atrHandle = INVALID_HANDLE;
int      g_signalSide = 0;              // Pine histogram yönü: +1 yeşil, -1 kırmızı
bool     g_signalReady = false;
datetime g_lastChartBarTime = 0;
datetime g_lastLiveCalculation = 0;
string   g_lastStatus = "Başlatılıyor";

ENUM_TIMEFRAMES SignalTimeframe()
  {
   return (InpSignalTimeframe == PERIOD_CURRENT ? (ENUM_TIMEFRAMES)_Period : InpSignalTimeframe);
  }

string SignalName(const int side)
  {
   if(side > 0) return "YEŞİL / LONG";
   if(side < 0) return "KIRMIZI / SHORT";
   return "SİNYAL BEKLENİYOR";
  }

int TradeSideForSignal(const int signalSide)
  {
   if(signalSide == 0) return 0;
   return (InpReverseSignal ? -signalSide : signalSide);
  }

double NormalizePrice(const double price)
  {
   return NormalizeDouble(price,(int)SymbolInfoInteger(_Symbol,SYMBOL_DIGITS));
  }

bool GetATR(const int shift,double &atr)
  {
   atr=0.0;
   if(g_atrHandle==INVALID_HANDLE) return false;
   double values[];
   ArrayResize(values,1);
   if(CopyBuffer(g_atrHandle,0,shift,1,values)!=1 || values[0]<=0.0)
      return false;
   atr=values[0];
   return true;
  }

// Implements Pine cci(close, CCI_Period) and its six recursive T3 stages.
bool CalculatePineT3CCI(int &sideOut,datetime &chartBarTime)
  {
   sideOut=0;
   chartBarTime=0;
   const int period=InpCCIPeriod;
   if(period<1 || InpT3Period<1) return false;

   int history=InpHistoryBars;
   if(history<period+50) history=period+50;
   if(history>10000) history=10000;

   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   const int copied=CopyRates(_Symbol,SignalTimeframe(),0,history,rates);
   const int targetShift=(InpUseClosedBar ? 1 : 0);
   if(copied<period+targetShift) return false;
   chartBarTime=rates[0].time;

   double cci[],e1[],e2[],e3[],e4[],e5[],e6[],value[];
   ArrayResize(cci,copied); ArrayResize(e1,copied); ArrayResize(e2,copied);
   ArrayResize(e3,copied); ArrayResize(e4,copied); ArrayResize(e5,copied);
   ArrayResize(e6,copied); ArrayResize(value,copied);
   ArraySetAsSeries(cci,true); ArraySetAsSeries(e1,true); ArraySetAsSeries(e2,true);
   ArraySetAsSeries(e3,true); ArraySetAsSeries(e4,true); ArraySetAsSeries(e5,true);
   ArraySetAsSeries(e6,true); ArraySetAsSeries(value,true);
   ArrayInitialize(cci,0.0); ArrayInitialize(e1,0.0); ArrayInitialize(e2,0.0);
   ArrayInitialize(e3,0.0); ArrayInitialize(e4,0.0); ArrayInitialize(e5,0.0);
   ArrayInitialize(e6,0.0); ArrayInitialize(value,0.0);

   // CopyRates is series-indexed: [0] newest; older bars have larger indices.
   for(int shift=copied-period;shift>=0;shift--)
     {
      double sum=0.0;
      for(int j=0;j<period;j++) sum+=rates[shift+j].close;
      const double sma=sum/(double)period;
      double deviation=0.0;
      for(int j=0;j<period;j++) deviation+=MathAbs(rates[shift+j].close-sma);
      deviation/=(double)period;
      cci[shift]=(deviation>0.0 ? (rates[shift].close-sma)/(0.015*deviation) : 0.0);
     }

   const double nn=(double)MathMax(1,InpT3Period);
   const double nr=1.0+0.5*(nn-1.0);
   const double w1=2.0/(nr+1.0);
   const double w2=1.0-w1;
   const double b=InpT3Factor;
   const double b2=b*b;
   const double b3=b2*b;
   const double c1=-b3;
   const double c2=3.0*(b2+b3);
   const double c3=-3.0*(2.0*b2+b+b3);
   const double c4=1.0+3.0*b+b3+3.0*b2;

   for(int shift=copied-period;shift>=0;shift--)
     {
      const double p1=(shift+1<copied ? e1[shift+1] : 0.0);
      const double p2=(shift+1<copied ? e2[shift+1] : 0.0);
      const double p3=(shift+1<copied ? e3[shift+1] : 0.0);
      const double p4=(shift+1<copied ? e4[shift+1] : 0.0);
      const double p5=(shift+1<copied ? e5[shift+1] : 0.0);
      const double p6=(shift+1<copied ? e6[shift+1] : 0.0);
      e1[shift]=w1*cci[shift]+w2*p1;
      e2[shift]=w1*e1[shift]+w2*p2;
      e3[shift]=w1*e2[shift]+w2*p3;
      e4[shift]=w1*e3[shift]+w2*p4;
      e5[shift]=w1*e4[shift]+w2*p5;
      e6[shift]=w1*e5[shift]+w2*p6;
      value[shift]=c1*e6[shift]+c2*e5[shift]+c3*e4[shift]+c4*e3[shift];
     }

   // Pine pos holds its previous direction when xccir is exactly zero.
   for(int shift=targetShift;shift<=copied-period;shift++)
     {
      if(value[shift]>0.0) { sideOut=1; return true; }
      if(value[shift]<0.0) { sideOut=-1; return true; }
     }
   return false;
  }

int CountOurPositions(const int sideFilter=0)
  {
   int count=0;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      const ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      const long type=PositionGetInteger(POSITION_TYPE);
      const int side=(type==POSITION_TYPE_BUY ? 1 : -1);
      if(sideFilter==0 || side==sideFilter) count++;
     }
   return count;
  }

bool ClosePositions(const int sideFilter,const string reason)
  {
   bool allClosed=true;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      const ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol) continue;
      if((ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      const long type=PositionGetInteger(POSITION_TYPE);
      const int side=(type==POSITION_TYPE_BUY ? 1 : -1);
      if(sideFilter!=0 && side!=sideFilter) continue;
      if(!trade.PositionClose(ticket))
        {
         allClosed=false;
         PrintFormat("Pozisyon kapatılamadı ticket=%I64u retcode=%u (%s)",ticket,
                     trade.ResultRetcode(),trade.ResultRetcodeDescription());
        }
      else
         PrintFormat("Pozisyon kapandı ticket=%I64u neden=%s",ticket,reason);
     }
   return allClosed;
  }

double StopDistance(const int shift)
  {
   if(InpStopLossMode==T3_SL_POINTS)
      return MathMax(0.0,InpStopLossPoints)*_Point;
   if(InpStopLossMode==T3_SL_ATR)
     {
      double atr=0.0;
      if(GetATR(shift,atr)) return atr*MathMax(0.0,InpStopLossATRMultiplier);
     }
   return 0.0;
  }

double TakeProfitDistance(const int shift)
  {
   if(InpTakeProfitMode==T3_TP_POINTS)
      return MathMax(0.0,InpTakeProfitPoints)*_Point;
   if(InpTakeProfitMode==T3_TP_ATR)
     {
      double atr=0.0;
      if(GetATR(shift,atr)) return atr*MathMax(0.0,InpTakeProfitATRMultiplier);
     }
   return 0.0;
  }

double NormalizeLots(double lots)
  {
   const double minLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   const double maxLot=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   const double step=SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(step>0.0) lots=MathFloor(lots/step)*step;
   lots=MathMax(minLot,MathMin(maxLot,lots));
   return NormalizeDouble(lots,8);
  }

double CalculateLots(const double stopDistance)
  {
   if(InpLotMode==T3_LOT_FIXED || stopDistance<=0.0)
      return NormalizeLots(InpFixedLots);
   const double riskMoney=AccountInfoDouble(ACCOUNT_BALANCE)*MathMax(0.0,InpRiskPercent)/100.0;
   const double tickSize=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   const double tickValue=SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_VALUE);
   if(tickSize<=0.0 || tickValue<=0.0 || riskMoney<=0.0)
      return NormalizeLots(InpFixedLots);
   return NormalizeLots(riskMoney/(stopDistance/tickSize*tickValue));
  }

bool SpreadAllowed()
  {
   if(InpMaxSpreadPoints<=0) return true;
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return false;
   return ((tick.ask-tick.bid)/_Point <= (double)InpMaxSpreadPoints);
  }

bool OpenTrade(const int side,const int atrShift)
  {
   if(side==0 || !SpreadAllowed())
     {
      if(side!=0) g_lastStatus="Spread filtresi nedeniyle giriş atlandı";
      return false;
     }
   if(InpMaxPositions>0 && CountOurPositions()>=InpMaxPositions)
     {
      g_lastStatus="Maksimum pozisyon sınırında; yeni giriş atlandı";
      return false;
     }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick)) return false;
   const double entry=(side>0 ? tick.ask : tick.bid);
   double slDistance=StopDistance(atrShift);
   double tpDistance=TakeProfitDistance(atrShift);
   const double minDistance=((double)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL)*_Point+
                             SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE));
   if(slDistance>0.0) slDistance=MathMax(slDistance,minDistance);
   if(tpDistance>0.0) tpDistance=MathMax(tpDistance,minDistance);
   const double sl=(slDistance>0.0 ? NormalizePrice(entry-side*slDistance) : 0.0);
   const double tp=(tpDistance>0.0 ? NormalizePrice(entry+side*tpDistance) : 0.0);
   const double lots=CalculateLots(slDistance);
   const string comment=(side>0 ? "T3-CCI LONG" : "T3-CCI SHORT");
   const bool sent=(side>0 ? trade.Buy(lots,_Symbol,0.0,sl,tp,comment)
                           : trade.Sell(lots,_Symbol,0.0,sl,tp,comment));
   const uint retcode=trade.ResultRetcode();
   const bool accepted=(sent && (retcode==TRADE_RETCODE_DONE ||
                                 retcode==TRADE_RETCODE_DONE_PARTIAL ||
                                 retcode==TRADE_RETCODE_PLACED));
   if(!accepted)
     {
      g_lastStatus=StringFormat("Emir reddedildi: %s",trade.ResultRetcodeDescription());
      PrintFormat("T3-CCI %s emir başarısız: retcode=%u %s",(side>0?"LONG":"SHORT"),
                  trade.ResultRetcode(),trade.ResultRetcodeDescription());
      return false;
     }
   g_lastStatus=StringFormat("%s açıldı, lot=%.4f",(side>0?"LONG":"SHORT"),lots);
   PrintFormat("T3-CCI %s açıldı | lot=%.4f entry=%.*f SL=%.*f TP=%.*f signal=%s",
               (side>0?"LONG":"SHORT"),lots,_Digits,trade.ResultPrice(),_Digits,sl,
               _Digits,tp,SignalName(g_signalSide));
   if(InpAlertsOn) Alert("T3-CCI ",comment," ",_Symbol);
   if(InpPushOn) SendNotification("T3-CCI "+comment+" "+_Symbol);
   return true;
  }

void DrawSignal(const int side,const datetime barTime,const double price)
  {
   if(!InpDrawSignalArrows || barTime<=0 || price<=0.0) return;
   const string name=StringFormat("T3CCI_%I64u_%s_%I64d",InpMagicNumber,_Symbol,(long)barTime);
   if(ObjectFind(0,name)>=0) return;
   if(!ObjectCreate(0,name,OBJ_ARROW,0,barTime,price)) return;
   ObjectSetInteger(0,name,OBJPROP_ARROWCODE,(side>0 ? 233 : 234));
   ObjectSetInteger(0,name,OBJPROP_COLOR,(side>0 ? clrLimeGreen : clrRed));
   ObjectSetInteger(0,name,OBJPROP_WIDTH,2);
  }

void HandleNewSignal(const int signalSide,const datetime barTime,const int atrShift)
  {
   const int tradeSide=TradeSideForSignal(signalSide);
   g_signalSide=signalSide;
   DrawSignal(signalSide,barTime,(signalSide>0 ? iLow(_Symbol,SignalTimeframe(),atrShift) :
                                                  iHigh(_Symbol,SignalTimeframe(),atrShift)));

   if(InpTakeProfitMode==T3_TP_OPPOSITE_SIGNAL)
      ClosePositions(-tradeSide,"TP: karşı T3-CCI sinyali");
   else if(InpCloseOnOppositeSignal)
      ClosePositions(-tradeSide,"karşı T3-CCI sinyali");

   // A signal direction is acted on only when the histogram changes color,
   // or once on startup when InpTradeOnStartupSignal is enabled.
   if(CountOurPositions(tradeSide)>0)
     {
      g_lastStatus=StringFormat("Sinyal %s; aynı yönde pozisyon zaten açık",SignalName(signalSide));
      return;
     }
   if(InpMaxPositions>0 && CountOurPositions()>=InpMaxPositions)
     {
      g_lastStatus=StringFormat("Sinyal %s; mevcut pozisyon korunuyor",SignalName(signalSide));
      return;
     }
   OpenTrade(tradeSide,atrShift);
  }

void ProcessSignal(const bool force=false)
  {
   const datetime chartBarTime=iTime(_Symbol,SignalTimeframe(),0);
   const datetime now=TimeCurrent();
   bool recalculate=force;
   if(!recalculate)
     {
      if(InpUseClosedBar)
         recalculate=(chartBarTime>0 && chartBarTime!=g_lastChartBarTime);
      else
         recalculate=(g_lastLiveCalculation==0 ||
                      (long)(now-g_lastLiveCalculation)>=(long)MathMax(1,InpLiveRefreshSeconds));
     }
   if(!recalculate) return;

   int signal=0;
   datetime barTime=0;
   if(!CalculatePineT3CCI(signal,barTime)) return;
   g_lastLiveCalculation=now;
   g_lastChartBarTime=(barTime>0 ? barTime : chartBarTime);

   const int atrShift=(InpUseClosedBar ? 1 : 0);
   if(!g_signalReady)
     {
      g_signalReady=true;
      g_signalSide=signal;
      g_lastStatus=StringFormat("İlk T3-CCI yönü: %s",SignalName(signal));
      if(InpTradeOnStartupSignal)
         HandleNewSignal(signal,barTime,atrShift);
      return;
     }
   if(signal!=g_signalSide)
      HandleNewSignal(signal,barTime,atrShift);
  }

void ManageBarCountTakeProfit()
  {
   if(InpTakeProfitMode!=T3_TP_AFTER_BARS || InpTakeProfitAfterBars<1) return;
   for(int i=PositionsTotal()-1;i>=0;i--)
     {
      const ulong ticket=PositionGetTicket(i);
      if(ticket==0 || !PositionSelectByTicket(ticket)) continue;
      if(PositionGetString(POSITION_SYMBOL)!=_Symbol ||
         (ulong)PositionGetInteger(POSITION_MAGIC)!=InpMagicNumber) continue;
      const datetime openTime=(datetime)PositionGetInteger(POSITION_TIME);
      const int bars=iBarShift(_Symbol,SignalTimeframe(),openTime,false);
      if(bars>=InpTakeProfitAfterBars)
        {
         if(trade.PositionClose(ticket))
           {
            g_lastStatus=StringFormat("TP: %d sinyal mumu sonunda pozisyon kapandı",bars);
            PrintFormat("TP_AFTER_BARS: ticket=%I64u elapsedBars=%d",ticket,bars);
           }
        }
     }
  }

void UpdatePanel()
  {
   if(!InpShowStatus) { Comment(""); return; }
   string tpMode="Kapalı";
   if(InpTakeProfitMode==T3_TP_POINTS) tpMode=StringFormat("%.0f point",InpTakeProfitPoints);
   if(InpTakeProfitMode==T3_TP_ATR) tpMode=StringFormat("ATR x %.2f",InpTakeProfitATRMultiplier);
   if(InpTakeProfitMode==T3_TP_OPPOSITE_SIGNAL) tpMode="Karşı sinyal";
   if(InpTakeProfitMode==T3_TP_AFTER_BARS) tpMode=StringFormat("%d sinyal mumu",InpTakeProfitAfterBars);
   string slMode="Kapalı";
   if(InpStopLossMode==T3_SL_POINTS) slMode=StringFormat("%.0f point",InpStopLossPoints);
   if(InpStopLossMode==T3_SL_ATR) slMode=StringFormat("ATR x %.2f",InpStopLossATRMultiplier);
   Comment("FX Sniper T3-CCI Signal Trader v1.00\n",
           "Sembol: ",_Symbol," | TF: ",EnumToString(SignalTimeframe()),"\n",
           "Histogram: ",SignalName(g_signalSide)," | işlem yönü: ",
           (TradeSideForSignal(g_signalSide)>0?"LONG":(TradeSideForSignal(g_signalSide)<0?"SHORT":"-")),
           (InpReverseSignal?" (ters sinyal açık)":""),"\n",
           "TP: ",tpMode," | SL: ",slMode,"\n",
           "Pozisyon LONG/SHORT: ",IntegerToString(CountOurPositions(1))," / ",
           IntegerToString(CountOurPositions(-1))," | Açık pozisyon: ",IntegerToString(CountOurPositions()),"\n",
           "Durum: ",g_lastStatus);
  }

int OnInit()
  {
   if(InpCCIPeriod<1 || InpT3Period<1 || InpHistoryBars<1 || InpLiveRefreshSeconds<1 ||
      InpATRPeriod<1 || InpMaxPositions<0 || InpMaxSpreadPoints<0 ||
      (InpTakeProfitMode==T3_TP_AFTER_BARS && InpTakeProfitAfterBars<1) || InpFixedLots<=0.0 || InpRiskPercent<0.0 || InpTakeProfitPoints<0.0 ||
      InpStopLossPoints<0.0 || InpTakeProfitATRMultiplier<0.0 || InpStopLossATRMultiplier<0.0)
     {
      Print("Hatalı girdi: T3-CCI, lot, TP/SL ve pozisyon ayarlarını kontrol edin.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE)!=ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("Bilgi: Hesap netting modunda; sembolde aynı anda tek net pozisyon tutulabilir.");

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetAsyncMode(false);
   trade.SetTypeFillingBySymbol(_Symbol);
   g_atrHandle=iATR(_Symbol,SignalTimeframe(),InpATRPeriod);
   if(g_atrHandle==INVALID_HANDLE)
     {
      PrintFormat("ATR handle oluşturulamadı, err=%d",GetLastError());
      return INIT_FAILED;
     }
   EventSetTimer(1);
   ProcessSignal(true);
   UpdatePanel();
   PrintFormat("T3-CCI Signal Trader hazır | %s %s | CCI(%d), T3(%d), b=%.3f | closedBar=%s reverse=%s | TP mode=%d SL mode=%d",
               _Symbol,EnumToString(SignalTimeframe()),InpCCIPeriod,InpT3Period,InpT3Factor,
               (InpUseClosedBar?"true":"false"),(InpReverseSignal?"true":"false"),
               (int)InpTakeProfitMode,(int)InpStopLossMode);
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(g_atrHandle!=INVALID_HANDLE) IndicatorRelease(g_atrHandle);
   Comment("");
  }

void OnTick()
  {
   ProcessSignal(false);
   ManageBarCountTakeProfit();
   UpdatePanel();
  }

void OnTimer()
  {
   ProcessSignal(false);
   ManageBarCountTakeProfit();
   UpdatePanel();
  }
//+------------------------------------------------------------------+

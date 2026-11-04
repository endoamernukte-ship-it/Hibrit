//+------------------------------------------------------------------+
//|                                             MT5_HA_MTF_Robot.mq5 |
//|          Coklu Zaman Dilimli Heiken Ashi Robotu (3 TF) v1.10      |
//|                                                                  |
//|  Pine "Heiken Ashi MTF" indikatorunun robot karsiligi:            |
//|    ha_diff = ha_open - ha_close                                   |
//|    KIRMIZI : ha_open > ha_close                                   |
//|    YESIL   : ha_close > ha_open                                   |
//|    NOTR    : ha_open == ha_close                                  |
//|                                                                  |
//|  Hazir ayarlar:                                                   |
//|   1) Ucu de yesilken gir, biri kirmiziya donunce cik:             |
//|        InpEntryAgreeCount = 3, InpExitOppositeCount = 1           |
//|   2) Ikisi ayni renkteyken gir, diger renk cokluga gecince ters   |
//|      pozisyona don:                                               |
//|        InpEntryAgreeCount = 2, InpExitOppositeCount = 2,          |
//|        InpReverseOnExit = true                                    |
//|   3) Ucu de yesilken her mumda sinirlara kadar pramitle:          |
//|        InpEnablePyramiding = true, InpMaxPositionsPerSide = 5,    |
//|        InpPyramidTimeframe = PERIOD_CURRENT                       |
//|                                                                  |
//|  Not: Pramitleme veya ayni anda iki yonde pozisyon icin hesabin   |
//|  hedging (netting kapali) olmasi gerekir.                         |
//+------------------------------------------------------------------+
#property strict
#property version   "1.10"
#property description "Pine Heiken Ashi MTF robotu: 3 zaman dilimi, esnek giris/cikis/ters donus ve pramitleme"

#include <Trade/Trade.mqh>

CTrade trade;

//+------------------------------------------------------------------+
//| Girdi parametreleri                                              |
//+------------------------------------------------------------------+
input group "Sinyal zaman dilimleri"
input bool             InpUseTF1      = true;            // TF1 kullan
input ENUM_TIMEFRAMES  InpTF1         = PERIOD_H1;       // Zaman dilimi 1
input bool             InpUseTF2      = true;            // TF2 kullan
input ENUM_TIMEFRAMES  InpTF2         = PERIOD_H4;       // Zaman dilimi 2
input bool             InpUseTF3      = true;            // TF3 kullan
input ENUM_TIMEFRAMES  InpTF3         = PERIOD_D1;       // Zaman dilimi 3
input bool             InpSignalOnClosedBar = true;      // true: kapanmis mum, false: olusan mum
input int              InpHACalcBars  = 400;             // HA gecmis bar sayisi (50-2000)

input group "Giris kurallari"
input int  InpEntryAgreeCount = 3;      // Kac TF ayni renkte olmali (1-3)
input bool InpAllowLong       = true;   // LONG girislerine izin ver
input bool InpAllowShort      = true;   // SHORT girislerine izin ver
input bool InpAllowHedging    = false;  // Ayni anda ters yonde de pozisyon tut

input group "Cikis kurallari"
input int  InpExitOppositeCount  = 1;      // Kac TF ters renge donunce cik (0=kapali, 1-3)
input bool InpExitWhenSignalLost = false;  // Giris kosulu bozulunca cik
input bool InpReverseOnExit      = false;  // true: cikista ters sinyal hazirsa hemen ters ac

input group "Pramitleme (kademeli giris)"
input bool            InpEnablePyramiding    = true;            // Pramitleme acik
input int             InpMaxPositionsPerSide = 5;               // Ayni yonde maksimum pozisyon (0=sinirsiz)
input int             InpMaxTotalPositions   = 10;              // Toplam maksimum pozisyon (0=sinirsiz)
input ENUM_TIMEFRAMES InpPyramidTimeframe    = PERIOD_CURRENT;  // Her yeni mumunda bir ek giris
input double          InpPyramidStepPoints   = 0.0;             // Son girise gore lehe min mesafe (point, 0=kapali)
input double          InpLotMultiplierPerAdd = 1.0;             // Her ek giriste lot carpani (1.0=sabit)

input group "Lot ve risk"
input bool   InpUseBrokerMinimumVolume = false; // Broker minimum hacmini kullan
input double InpFixedLots              = 0.01;  // Sabit lot (minimum altindaysa giris atlanir)
input int    InpTakeProfitPoints       = 0;     // TP (point, 0=kapali)
input int    InpStopLossPoints         = 0;     // SL (point, 0=kapali)
input int    InpMaxSpreadPoints        = 0;     // Maksimum spread (point, 0=kapali)

input group "Genel"
input ulong InpMagicNumber     = 20261017; // Sihirli numara
input int   InpDeviationPoints = 20;       // Kayma toleransi (point)
input bool  InpShowPanel       = true;     // Grafikte renk panelini goster

//+------------------------------------------------------------------+
//| Global degiskenler                                               |
//+------------------------------------------------------------------+
// Her zaman dilimi icin Heiken Ashi onbellegi (0=TF1, 1=TF2, 2=TF3)
datetime g_ha_bar_time[3];
double   g_ha_prev_open[3];
double   g_ha_prev_close[3];
int      g_ha_closed_color[3];
int      g_ha_closed_shift[3];
bool     g_ha_valid[3];

int  g_color[3];             // +1 yesil, -1 kirmizi, 0 notr
bool g_color_ok[3];          // o zaman dilimi icin veri okunabildi mi
int  g_long_votes   = 0;
int  g_short_votes  = 0;
bool g_signal_ready = false;
bool g_raw_long     = false;
bool g_raw_short    = false;
bool g_long_entry   = false;
bool g_short_entry  = false;

bool g_block_long  = false;  // sinyal sifirlanana kadar yeni long acma
bool g_block_short = false;  // sinyal sifirlanana kadar yeni short acma

datetime g_last_bar_long    = 0;
datetime g_last_bar_short   = 0;
double   g_last_price_long  = 0.0;
double   g_last_price_short = 0.0;
datetime g_last_entry_time  = 0;

string g_panel_prefix = "";
bool   g_panel_visible = false;
string g_last_action  = "Baslatildi; sinyal bekleniyor";

//+------------------------------------------------------------------+
//| Temel yardimcilar                                                |
//+------------------------------------------------------------------+
string SideName(const int side)
  {
   if(side > 0)
      return "LONG";
   if(side < 0)
      return "SHORT";
   return "YOK";
  }

string TFName(const ENUM_TIMEFRAMES tf)
  {
   string s = EnumToString(tf);
   string prefix = "PERIOD_";
   if(StringFind(s,prefix) == 0)
      s = StringSubstr(s,StringLen(prefix));
   return s;
  }

int SideFromPositionType(const long type)
  {
   if(type == POSITION_TYPE_BUY)
      return 1;
   if(type == POSITION_TYPE_SELL)
      return -1;
   return 0;
  }

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

int CountPositions(const int side_filter=0)
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

double TickSize()
  {
   double size = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(size <= 0.0)
      size = _Point;
   return size;
  }

double NormalizePriceToTick(const double price,const int round_direction)
  {
   // +1 yukari, -1 asagi, 0 en yakin
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

bool NormalizeVolume(double &volume)
  {
   double min_volume  = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double max_volume  = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double volume_step = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(min_volume <= 0.0 || volume_step <= 0.0)
      return false;
   if(!MathIsValidNumber(volume) || volume <= 0.0)
      return false;
   if(max_volume > 0.0 && volume > max_volume)
      volume = max_volume;
   volume = MathFloor(volume / volume_step + 1.0e-10) * volume_step;
   volume = NormalizeDouble(volume,8);
   if(volume + 1.0e-10 < min_volume)
     {
      PrintFormat("Hacim atlandi: hesaplanan lot %.8f broker minimumu %.8f altinda.",volume,min_volume);
      return false;
     }
   return true;
  }

datetime SideLastBar(const int side)
  {
   if(side > 0)
      return g_last_bar_long;
   return g_last_bar_short;
  }

double SideLastPrice(const int side)
  {
   if(side > 0)
      return g_last_price_long;
   return g_last_price_short;
  }

void ResetSideState(const int side)
  {
   if(side > 0)
     {
      g_last_bar_long = 0;
      g_last_price_long = 0.0;
     }
   else
     {
      g_last_bar_short = 0;
      g_last_price_short = 0.0;
     }
  }

//+------------------------------------------------------------------+
//| Heiken Ashi hesabi ve onbellegi                                  |
//+------------------------------------------------------------------+
int HAColor(const double ha_open,const double ha_close)
  {
   if(ha_open > ha_close)
      return -1;   // Pine: kirmizi
   if(ha_close > ha_open)
      return 1;    // Pine: yesil
   return 0;       // Pine: notr
  }

bool RefreshHACache(const int idx,const ENUM_TIMEFRAMES tf)
  {
   int bars = InpHACalcBars;
   if(bars < 50)
      bars = 50;
   if(bars > 2000)
      bars = 2000;

   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   int copied = CopyRates(_Symbol,tf,0,bars,rates);
   if(copied < 5)
      return false;

   // Piyasa acikken son kapanmis bar shift 1, kapaliyken (yeni bar olusmuyorsa) shift 0 olabilir.
   int last_closed = 1;
   datetime newest_close = (datetime)((long)rates[0].time + (long)PeriodSeconds(tf));
   if(TimeCurrent() >= newest_close)
      last_closed = 0;
   if(last_closed >= copied)
      last_closed = copied - 1;

   double prev_open  = 0.0;
   double prev_close = 0.0;
   for(int shift=copied-1; shift>=last_closed; shift--)
     {
      double o = rates[shift].open;
      double h = rates[shift].high;
      double l = rates[shift].low;
      double c = rates[shift].close;
      double ha_close = (o + h + l + c) / 4.0;
      double ha_open;
      if(shift == copied-1)
         ha_open = (o + c) / 2.0;
      else
         ha_open = (prev_open + prev_close) / 2.0;
      prev_open  = ha_open;
      prev_close = ha_close;
     }

   g_ha_bar_time[idx]     = rates[0].time;
   g_ha_prev_open[idx]    = prev_open;
   g_ha_prev_close[idx]   = prev_close;
   g_ha_closed_color[idx] = HAColor(prev_open,prev_close);
   g_ha_closed_shift[idx] = last_closed;
   g_ha_valid[idx]        = true;
   return true;
  }

bool ResolveTFColor(const int idx,const ENUM_TIMEFRAMES tf,int &color_out)
  {
   color_out = 0;
   datetime current_bar = iTime(_Symbol,tf,0);
   if(current_bar <= 0)
      return false;

   if(!g_ha_valid[idx] || g_ha_bar_time[idx] != current_bar)
     {
      if(!RefreshHACache(idx,tf))
         return false;
     }

   if(InpSignalOnClosedBar || g_ha_closed_shift[idx] == 0)
     {
      color_out = g_ha_closed_color[idx];
      return true;
     }

   // Olusan mum: HA open son kapanmis HA degerlerinden sabittir, HA close anlik OHLC ile hareket eder.
   MqlRates cur[];
   ArraySetAsSeries(cur,true);
   if(CopyRates(_Symbol,tf,0,1,cur) < 1)
      return false;
   double ha_open  = (g_ha_prev_open[idx] + g_ha_prev_close[idx]) / 2.0;
   double ha_close = (cur[0].open + cur[0].high + cur[0].low + cur[0].close) / 4.0;
   color_out = HAColor(ha_open,ha_close);
   return true;
  }

//+------------------------------------------------------------------+
//| Sinyal birlestirme (Pine ha_diff mantigi)                        |
//+------------------------------------------------------------------+
void RefreshSignals()
  {
   int used_count = 0;
   if(InpUseTF1)
      used_count++;
   if(InpUseTF2)
      used_count++;
   if(InpUseTF3)
      used_count++;

   g_long_votes  = 0;
   g_short_votes = 0;
   for(int i=0; i<3; i++)
     {
      g_color[i]    = 0;
      g_color_ok[i] = false;
     }

   bool ready = true;

   if(InpUseTF1)
     {
      int c1 = 0;
      if(ResolveTFColor(0,InpTF1,c1))
        {
         g_color[0]    = c1;
         g_color_ok[0] = true;
         if(c1 > 0)
            g_long_votes++;
         else if(c1 < 0)
            g_short_votes++;
        }
      else
         ready = false;
     }

   if(InpUseTF2)
     {
      int c2 = 0;
      if(ResolveTFColor(1,InpTF2,c2))
        {
         g_color[1]    = c2;
         g_color_ok[1] = true;
         if(c2 > 0)
            g_long_votes++;
         else if(c2 < 0)
            g_short_votes++;
        }
      else
         ready = false;
     }

   if(InpUseTF3)
     {
      int c3 = 0;
      if(ResolveTFColor(2,InpTF3,c3))
        {
         g_color[2]    = c3;
         g_color_ok[2] = true;
         if(c3 > 0)
            g_long_votes++;
         else if(c3 < 0)
            g_short_votes++;
        }
      else
         ready = false;
     }

   if(used_count < 1)
      ready = false;
   g_signal_ready = ready;

   // Esitlik durumunda giris yok; boylece 1 TF esigi ile belirsizlik olusmaz.
   g_raw_long  = (ready && g_long_votes  >= InpEntryAgreeCount && g_long_votes  > g_short_votes);
   g_raw_short = (ready && g_short_votes >= InpEntryAgreeCount && g_short_votes > g_long_votes);
   g_long_entry  = (g_raw_long  && InpAllowLong);
   g_short_entry = (g_raw_short && InpAllowShort);

   // Bekleme kilidi yalnizca sinyal gecersiz olunca acilir.
   if(!g_raw_long)
      g_block_long = false;
   if(!g_raw_short)
      g_block_short = false;
  }

bool ExitConditionMet(const int side)
  {
   if(!g_signal_ready)
      return false;
   if(side > 0)
     {
      if(InpExitOppositeCount > 0 && g_short_votes >= InpExitOppositeCount)
         return true;
      if(InpExitWhenSignalLost && g_long_votes < InpEntryAgreeCount)
         return true;
     }
   else
     {
      if(InpExitOppositeCount > 0 && g_long_votes >= InpExitOppositeCount)
         return true;
      if(InpExitWhenSignalLost && g_short_votes < InpEntryAgreeCount)
         return true;
     }
   return false;
  }

//+------------------------------------------------------------------+
//| Pozisyon kapatma                                                 |
//+------------------------------------------------------------------+
bool CloseOnePosition(const ulong ticket,const string reason)
  {
   if(!SelectOurPosition(ticket))
      return true;
   int side = SideFromPositionType(PositionGetInteger(POSITION_TYPE));

   bool sent = trade.PositionClose(ticket,InpDeviationPoints);
   if(!TradeRetcodeOK(sent))
     {
      PrintFormat("Kapatma basarisiz ticket=%I64u side=%s reason=%s retcode=%u (%s)",
                  ticket,SideName(side),reason,trade.ResultRetcode(),trade.ResultRetcodeDescription());
      return false;
     }
   if(PositionSelectByTicket(ticket))
     {
      double remaining = PositionGetDouble(POSITION_VOLUME);
      if(remaining > 0.0)
        {
         PrintFormat("Pozisyon tamamen kapanmadi ticket=%I64u kalan hacim=%.8f",ticket,remaining);
         return false;
        }
     }
   PrintFormat("Pozisyon kapandi: ticket=%I64u side=%s reason=%s",ticket,SideName(side),reason);
   g_last_action = reason;
   return true;
  }

int CloseAllPositions(const int side,const string reason)
  {
   ulong tickets[];
   ArrayResize(tickets,0);
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      if(SideFromPositionType(PositionGetInteger(POSITION_TYPE)) != side)
         continue;
      int n = ArraySize(tickets);
      if(ArrayResize(tickets,n+1) >= n+1)
         tickets[n] = ticket;
     }

   int closed = 0;
   int failed = 0;
   for(int i=0; i<ArraySize(tickets); i++)
     {
      if(CloseOnePosition(tickets[i],reason))
         closed++;
      else
         failed++;
     }
   if(closed > 0 || failed > 0)
      PrintFormat("%s kapatma: %d kapandi, %d basarisiz",SideName(side),closed,failed);
   return failed;
  }

//+------------------------------------------------------------------+
//| Lot hesabi                                                       |
//+------------------------------------------------------------------+
double VolumeForSide(const int side)
  {
   double volume = InpFixedLots;
   if(InpUseBrokerMinimumVolume)
      volume = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   if(volume <= 0.0)
      return 0.0;

   int existing = CountPositions(side);
   if(existing > 0 && InpLotMultiplierPerAdd > 0.0 &&
      MathAbs(InpLotMultiplierPerAdd - 1.0) > 1.0e-9)
      volume = volume * MathPow(InpLotMultiplierPerAdd,existing);

   if(!NormalizeVolume(volume))
      return 0.0;
   return volume;
  }

//+------------------------------------------------------------------+
//| Yeni sinyal veya pramit girisi                                   |
//+------------------------------------------------------------------+
bool OpenSignalPosition(const int side,const bool is_add)
  {
   if(side == 0 || !g_signal_ready)
      return false;
   if(side > 0 && !g_long_entry)
      return false;
   if(side < 0 && !g_short_entry)
      return false;
   if(is_add && !InpEnablePyramiding)
      return false;

   datetime now = TimeCurrent();
   if(g_last_entry_time > 0 && now - g_last_entry_time < 1)
      return false;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick) || tick.ask <= 0.0 || tick.bid <= 0.0)
      return false;

   if(InpMaxSpreadPoints > 0)
     {
      double spread = (tick.ask - tick.bid) / _Point;
      if(spread > InpMaxSpreadPoints)
        {
         g_last_action = StringFormat("Spread yuksek: %.1f point",spread);
         return false;
        }
     }

   int side_count  = CountPositions(side);
   int total_count = CountPositions(0);

   if(is_add && side_count == 0)
      return false;
   if(!is_add && side_count > 0)
      return false;
   if(InpMaxTotalPositions > 0 && total_count >= InpMaxTotalPositions)
     {
      g_last_action = "Toplam pozisyon siniri dolu";
      return false;
     }
   if(InpMaxPositionsPerSide > 0 && side_count >= InpMaxPositionsPerSide)
     {
      g_last_action = StringFormat("%s pozisyon siniri dolu",SideName(side));
      return false;
     }
   if(!InpAllowHedging && side_count == 0 && CountPositions(-side) > 0)
     {
      g_last_action = "Ters yonde pozisyon var; yeni yon icin once cikis gerekli";
      return false;
     }

   double volume = VolumeForSide(side);
   if(volume <= 0.0)
     {
      g_last_action = "Lot hacmi broker sinirlarina uymuyor";
      return false;
     }

   double entry = tick.ask;
   if(side < 0)
      entry = tick.bid;

   double sl = 0.0;
   double tp = 0.0;
   if(InpStopLossPoints > 0)
      sl = NormalizePriceToTick(entry - side * (double)InpStopLossPoints * _Point,(side > 0 ? -1 : 1));
   if(InpTakeProfitPoints > 0)
      tp = NormalizePriceToTick(entry + side * (double)InpTakeProfitPoints * _Point,(side > 0 ? 1 : -1));
   if(sl < 0.0)
      sl = 0.0;
   if(tp < 0.0)
      tp = 0.0;

   string comment = "HA-MTF L";
   if(side < 0)
      comment = "HA-MTF S";
   if(is_add)
      comment = comment + "+";

   g_last_entry_time = now;
   bool sent = false;
   if(side > 0)
      sent = trade.Buy(volume,_Symbol,0.0,sl,tp,comment);
   else
      sent = trade.Sell(volume,_Symbol,0.0,sl,tp,comment);

   if(!TradeRetcodeOK(sent))
     {
      PrintFormat("Giris basarisiz side=%s lot=%.8f retcode=%u (%s)",
                  SideName(side),volume,trade.ResultRetcode(),trade.ResultRetcodeDescription());
      g_last_action = "Emir broker tarafindan reddedildi";
      return false;
     }

   double fill = trade.ResultPrice();
   if(fill <= 0.0)
      fill = entry;
   datetime pyramid_bar = iTime(_Symbol,InpPyramidTimeframe,0);
   if(side > 0)
     {
      g_last_bar_long   = pyramid_bar;
      g_last_price_long = fill;
     }
   else
     {
      g_last_bar_short   = pyramid_bar;
      g_last_price_short = fill;
     }

   if(is_add)
      g_last_action = StringFormat("Ek %s acildi (%.2f lot)",SideName(side),volume);
   else
      g_last_action = StringFormat("Yeni %s acildi (%.2f lot)",SideName(side),volume);

   string add_text = "ILK";
   if(is_add)
      add_text = "EK";
   PrintFormat("HA-MTF giris: %s %s lot=%.8f fill=%s oy Y/K=%d/%d",
               SideName(side),add_text,volume,DoubleToString(fill,_Digits),
               g_long_votes,g_short_votes);
   return true;
  }

//+------------------------------------------------------------------+
//| Cikis yonetimi                                                   |
//+------------------------------------------------------------------+
void OnSideExit(const int exited_side)
  {
   if(CountPositions(exited_side) == 0)
      ResetSideState(exited_side);

   if(exited_side > 0)
      g_block_long = true;
   else
      g_block_short = true;

   if(!InpReverseOnExit)
     {
      // Cikis aninda ters yon girisi zaten hazirsa, ayni tikte ters acmak yerine yeni sinyal beklenir.
      int other = -exited_side;
      bool other_entry = g_short_entry;
      if(other > 0)
         other_entry = g_long_entry;
      if(other_entry && CountPositions(other) == 0)
        {
         if(other > 0)
            g_block_long = true;
         else
            g_block_short = true;
        }
     }
  }

bool ProcessExits()
  {
   int long_count  = CountPositions(1);
   int short_count = CountPositions(-1);
   bool long_exit  = (long_count  > 0 && ExitConditionMet(1));
   bool short_exit = (short_count > 0 && ExitConditionMet(-1));
   if(!long_exit && !short_exit)
      return false;

   if(long_exit)
     {
      int failed = CloseAllPositions(1,"LONG cikis: renk kosulu");
      if(failed == 0 && CountPositions(1) == 0)
         OnSideExit(1);
      else
         g_last_action = "LONG cikis tamamlanamadi; tekrar denenecek";
     }
   if(short_exit)
     {
      int failed = CloseAllPositions(-1,"SHORT cikis: renk kosulu");
      if(failed == 0 && CountPositions(-1) == 0)
         OnSideExit(-1);
      else
         g_last_action = "SHORT cikis tamamlanamadi; tekrar denenecek";
     }

   // Opsiyonel aninda ters donus; yalnizca hic pozisyon kalmadiginda.
   if(InpReverseOnExit && CountPositions(0) == 0)
     {
      if(long_exit && g_short_entry)
        {
         g_block_short = false;
         OpenSignalPosition(-1,false);
        }
      else if(short_exit && g_long_entry)
        {
         g_block_long = false;
         OpenSignalPosition(1,false);
        }
     }
   return true;
  }

//+------------------------------------------------------------------+
//| Pramitleme                                                       |
//+------------------------------------------------------------------+
void TryPyramidAdd(const int side,const int side_count,const int other_count)
  {
   if(InpMaxPositionsPerSide > 0 && side_count >= InpMaxPositionsPerSide)
      return;
   if(InpMaxTotalPositions > 0 && side_count + other_count >= InpMaxTotalPositions)
      return;

   datetime bar = iTime(_Symbol,InpPyramidTimeframe,0);
   if(bar <= 0 || bar == SideLastBar(side))
      return;

   if(InpPyramidStepPoints > 0.0)
     {
      double last = SideLastPrice(side);
      if(last > 0.0)
        {
         MqlTick tick;
         if(!SymbolInfoTick(_Symbol,tick))
            return;
         double price = tick.ask;
         if(side < 0)
            price = tick.bid;
         if((price - last) * (double)side < InpPyramidStepPoints * _Point)
            return;
        }
     }

   OpenSignalPosition(side,true);
  }

void HandleEntries()
  {
   int long_count  = CountPositions(1);
   int short_count = CountPositions(-1);

   if(g_long_entry && !g_block_long)
     {
      if(long_count == 0)
        {
         if(InpAllowHedging || short_count == 0)
            OpenSignalPosition(1,false);
        }
      else
        {
         if(InpEnablePyramiding)
            TryPyramidAdd(1,long_count,short_count);
        }
     }

   if(g_short_entry && !g_block_short)
     {
      if(short_count == 0)
        {
         if(InpAllowHedging || long_count == 0)
            OpenSignalPosition(-1,false);
        }
      else
        {
         if(InpEnablePyramiding)
            TryPyramidAdd(-1,short_count,long_count);
        }
     }
  }

//+------------------------------------------------------------------+
//| Yeniden baslatma guvenligi: pramit sayaclarini esitle            |
//+------------------------------------------------------------------+
void InitPyramidStateFromPositions()
  {
   for(int side=-1; side<=1; side+=2)
     {
      long newest_msc = -1;
      double newest_price = 0.0;
      for(int i=PositionsTotal()-1; i>=0; i--)
        {
         ulong ticket = PositionGetTicket(i);
         if(ticket == 0 || !SelectOurPosition(ticket))
            continue;
         if(SideFromPositionType(PositionGetInteger(POSITION_TYPE)) != side)
            continue;
         long t = PositionGetInteger(POSITION_TIME_MSC);
         if(t > newest_msc)
           {
            newest_msc = t;
            newest_price = PositionGetDouble(POSITION_PRICE_OPEN);
           }
        }
      if(newest_msc < 0)
         continue;
      datetime bar = iTime(_Symbol,InpPyramidTimeframe,0);
      if(side > 0)
        {
         g_last_bar_long   = bar;
         g_last_price_long = newest_price;
        }
      else
        {
         g_last_bar_short   = bar;
         g_last_price_short = newest_price;
        }
     }
  }

//+------------------------------------------------------------------+
//| Grafik paneli                                                    |
//+------------------------------------------------------------------+
color ColorForState(const int state)
  {
   if(state > 0)
      return clrLime;
   if(state < 0)
      return clrTomato;
   return clrSilver;
  }

string StateText(const int state)
  {
   if(state > 0)
      return "YESIL";
   if(state < 0)
      return "KIRMIZI";
   return "NOTR";
  }

void SetPanelLabel(const string id,const int x,const int y,const string text,const color clr)
  {
   string name = g_panel_prefix + id;
   if(ObjectFind(0,name) < 0)
     {
      if(!ObjectCreate(0,name,OBJ_LABEL,0,0,0))
         return;
      ObjectSetInteger(0,name,OBJPROP_CORNER,CORNER_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_ANCHOR,ANCHOR_LEFT_UPPER);
      ObjectSetInteger(0,name,OBJPROP_FONTSIZE,9);
      ObjectSetString(0,name,OBJPROP_FONT,"Arial");
      ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
      ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
      ObjectSetInteger(0,name,OBJPROP_BACK,false);
     }
   ObjectSetString(0,name,OBJPROP_TEXT,text);
   ObjectSetInteger(0,name,OBJPROP_COLOR,clr);
   ObjectSetInteger(0,name,OBJPROP_XDISTANCE,x);
   ObjectSetInteger(0,name,OBJPROP_YDISTANCE,y);
  }

void DeletePanel()
  {
   if(g_panel_prefix == "")
      return;
   int total = ObjectsTotal(0,-1,-1);
   for(int i=total-1; i>=0; i--)
     {
      string name = ObjectName(0,i,-1,-1);
      if(StringFind(name,g_panel_prefix) == 0)
         ObjectDelete(0,name);
     }
   ChartRedraw();
   g_panel_visible = false;
  }

void UpdateTFRow(const int idx,const string label,const bool use,const ENUM_TIMEFRAMES tf,const int y)
  {
   string text = "";
   color clr = clrGray;
   if(!use)
     {
      text = label + " " + TFName(tf) + ": kapali";
      clr = clrDimGray;
     }
   else
     {
      if(!g_color_ok[idx])
        {
         text = label + " " + TFName(tf) + ": veri yok";
         clr = clrOrange;
        }
      else
        {
         clr = ColorForState(g_color[idx]);
         text = label + " " + TFName(tf) + ": " + StateText(g_color[idx]);
        }
     }
   SetPanelLabel("TF" + IntegerToString(idx+1),10,y,text,clr);
  }

void UpdatePanel()
  {
   if(!InpShowPanel)
     {
      if(g_panel_visible)
         DeletePanel();
      return;
     }

   int y = 22;
   string mode_text = "kapanmis mum";
   if(!InpSignalOnClosedBar)
      mode_text = "canli mum";
   SetPanelLabel("TITLE",10,y,"HA-MTF Robot v1.10 | " + _Symbol + " " + TFName(_Period) + " | " + mode_text,clrWhite);
   y = y + 18;
   UpdateTFRow(0,"TF1",InpUseTF1,InpTF1,y);
   y = y + 18;
   UpdateTFRow(1,"TF2",InpUseTF2,InpTF2,y);
   y = y + 18;
   UpdateTFRow(2,"TF3",InpUseTF3,InpTF3,y);
   y = y + 18;

   SetPanelLabel("VOTES",10,y,StringFormat("Yesil: %d  Kirmizi: %d  |  Giris esigi: %d  |  Cikis ters renk: %d",
                                           g_long_votes,g_short_votes,InpEntryAgreeCount,InpExitOppositeCount),clrSilver);
   y = y + 18;

   int lc = CountPositions(1);
   int sc = CountPositions(-1);
   int shown_count = sc;
   if(lc > 0)
      shown_count = lc;
   string max_text = "sinirsiz";
   if(InpMaxPositionsPerSide > 0)
      max_text = IntegerToString(InpMaxPositionsPerSide);
   SetPanelLabel("POS",10,y,StringFormat("Pozisyon LONG: %d  SHORT: %d  |  Pramit: %d/%s  |  Toplam sinir: %d",
                                         lc,sc,shown_count,max_text,InpMaxTotalPositions),clrSilver);
   y = y + 18;

   SetPanelLabel("STATUS",10,y,"Durum: " + g_last_action,clrKhaki);
   g_panel_visible = true;
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| EA olaylari                                                      |
//+------------------------------------------------------------------+
int OnInit()
  {
   int used = 0;
   if(InpUseTF1)
      used++;
   if(InpUseTF2)
      used++;
   if(InpUseTF3)
      used++;

   if(used < 1)
     {
      Print("Hatali girdi: en az bir zaman dilimi (TF1/TF2/TF3) secilmelidir.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpEntryAgreeCount < 1 || InpEntryAgreeCount > used)
     {
      PrintFormat("Hatali girdi: InpEntryAgreeCount=%d, kullanilan TF sayisi=%d. Deger 1..%d arasinda olmali.",
                  InpEntryAgreeCount,used,used);
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpExitOppositeCount < 0 || InpExitOppositeCount > 3)
     {
      Print("Hatali girdi: InpExitOppositeCount 0..3 arasinda olmali.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpMaxPositionsPerSide < 0 || InpMaxTotalPositions < 0)
     {
      Print("Hatali girdi: pozisyon sinirlari negatif olamaz (0=sinirsiz).");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpFixedLots <= 0.0 || InpLotMultiplierPerAdd <= 0.0)
     {
      Print("Hatali girdi: lot ve lot carpani sifirdan buyuk olmali.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpTakeProfitPoints < 0 || InpStopLossPoints < 0 || InpMaxSpreadPoints < 0 ||
      InpDeviationPoints < 0 || InpPyramidStepPoints < 0.0)
     {
      Print("Hatali girdi: TP/SL/spread/kayma/mesafe degerleri negatif olamaz.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(!InpAllowLong && !InpAllowShort)
     {
      Print("Hatali girdi: LONG ve SHORT girislerin ikisi birlikte kapali olamaz.");
      return INIT_PARAMETERS_INCORRECT;
     }
   if(InpExitOppositeCount == 0 && !InpExitWhenSignalLost &&
      InpTakeProfitPoints == 0 && InpStopLossPoints == 0)
     {
      Print("Hatali girdi: hicbir cikis kosulu yok. Renk cikisi, sinyal kaybi, TP veya SL'den en az biri gerekli.");
      return INIT_PARAMETERS_INCORRECT;
     }

   bool hedging = (AccountInfoInteger(ACCOUNT_MARGIN_MODE) == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
   bool needs_hedging = InpAllowHedging;
   if(InpEnablePyramiding && (InpMaxPositionsPerSide == 0 || InpMaxPositionsPerSide > 1))
      needs_hedging = true;
   if(!hedging && needs_hedging)
     {
      Print("EA baslatilamadi: bu ayarlar (pramitleme / ters yonde pozisyon) hedging hesap gerektirir. ",
            "Netting hesapta InpEnablePyramiding=false ve InpAllowHedging=false yapin.");
      return INIT_FAILED;
     }

   if(InpExitOppositeCount > used)
      PrintFormat("Uyari: InpExitOppositeCount=%d, kullanilan TF sayisi=%d. Bu cikis kosulu hic tetiklenmeyecek.",
                  InpExitOppositeCount,used);
   if(InpTF1 == InpTF2 || InpTF1 == InpTF3 || InpTF2 == InpTF3)
      Print("Uyari: ayni zaman dilimi birden fazla TF icin secildi; sinyaller birebir ayni olacaktir.");

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetAsyncMode(false);
   trade.SetTypeFillingBySymbol(_Symbol);

   g_panel_prefix = "HAMTF_" + IntegerToString((int)InpMagicNumber) + "_" + _Symbol + "_";
   DeletePanel();

   for(int i=0; i<3; i++)
     {
      g_ha_valid[i]        = false;
      g_ha_bar_time[i]     = 0;
      g_ha_prev_open[i]    = 0.0;
      g_ha_prev_close[i]   = 0.0;
      g_ha_closed_color[i] = 0;
      g_ha_closed_shift[i] = 0;
     }

   InitPyramidStateFromPositions();
   RefreshSignals();
   UpdatePanel();
   EventSetTimer(1);

   PrintFormat("HA-MTF Robot v1.10 hazir: %s | TF1=%s (%s) | TF2=%s (%s) | TF3=%s (%s) | mum=%s",
               _Symbol,
               TFName(InpTF1),(InpUseTF1 ? "acik" : "kapali"),
               TFName(InpTF2),(InpUseTF2 ? "acik" : "kapali"),
               TFName(InpTF3),(InpUseTF3 ? "acik" : "kapali"),
               (InpSignalOnClosedBar ? "kapanmis" : "canli"));
   PrintFormat("Giris: %d TF ayni renkte | Cikis: %d TF ters renkte | Sinyal kaybi cikisi: %s | Ters donus: %s",
               InpEntryAgreeCount,InpExitOppositeCount,
               (InpExitWhenSignalLost ? "acik" : "kapali"),
               (InpReverseOnExit ? "acik" : "kapali"));
   PrintFormat("Pramitleme: %s | maks/yan=%d | toplam=%d | mum=%s | lot carpani=%.2f | hedging hesap=%s",
               (InpEnablePyramiding ? "acik" : "kapali"),InpMaxPositionsPerSide,InpMaxTotalPositions,
               TFName(InpPyramidTimeframe),InpLotMultiplierPerAdd,(hedging ? "evet" : "hayir"));
   if(!g_signal_ready)
      Print("Uyari: secilen zaman dilimlerinden biri icin veri henuz hazir degil; robot veri gelince baslayacak.");

   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   DeletePanel();
   Comment("");
  }

void OnTimer()
  {
   RefreshSignals();
   UpdatePanel();
  }

void OnTick()
  {
   RefreshSignals();
   if(!g_signal_ready)
     {
      UpdatePanel();
      return;
     }

   if(ProcessExits())
     {
      UpdatePanel();
      return;
     }

   HandleEntries();
   UpdatePanel();
  }
//+------------------------------------------------------------------+

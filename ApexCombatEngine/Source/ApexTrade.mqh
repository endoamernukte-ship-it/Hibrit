//+------------------------------------------------------------------+
//|                                                     ApexTrade.mqh |
//|  APEX COMBAT ENGINE - Katman 1: Yurutme (Execution) + Defter      |
//|                                                                  |
//|  Tum broker etkilesimi tek bir sinifta toplanir:                  |
//|   * fiyat/lot normalizasyonu ve stops-level guvenlik boslugu      |
//|   * spread / freeze / marjin on kontrolleri                       |
//|   * rol + seviye etiketli emir ve pozisyon defteri                |
//|   * hata sonrasi geri cekilmeli yeniden deneme (self-healing)     |
//|   * yeniden baslatmada defterin biletlerden yeniden insasi        |
//+------------------------------------------------------------------+
#ifndef __APEX_TRADE_MQH__
#define __APEX_TRADE_MQH__ 1

#include <Trade/Trade.mqh>
#include "ApexTypes.mqh"

//+------------------------------------------------------------------+
//| Yurutme motoru                                                   |
//+------------------------------------------------------------------+
class CApexExecution
  {
private:
   CTrade            m_trade;
   string            m_symbol;
   ulong             m_magic;
   int               m_deviation;
   int               m_digits;
   double            m_point;
   double            m_tick;
   double            m_lot_min;
   double            m_lot_max;
   double            m_lot_step;
   double            m_point_value;
   long              m_stops_level;
   long              m_freeze_level;
   double            m_min_stop_dist;
   bool              m_ready;
   int               m_error_streak;
   datetime          m_last_error_time;
   SBookEntry        m_book[];
   string            m_last_error;

   // --- yardimcilar ---
   double            MinStopDistance()
     {
      return MathMax((double)m_stops_level, (double)m_freeze_level) * m_point + m_tick;
     }

   // Gecici (sunucu/fiyat kaynakli) hatalar: geri cekilmeli yeniden deneme
   bool              RetryableError(const uint code)
     {
      return (code == TRADE_RETCODE_REQUOTE         ||
              code == TRADE_RETCODE_PRICE_OFF       ||
              code == TRADE_RETCODE_TIMEOUT         ||
              code == TRADE_RETCODE_PRICE_CHANGED   ||
              code == TRADE_RETCODE_TOO_MANY_REQUESTS ||
              code == TRADE_RETCODE_CONNECTION);
     }

   void              NoteError(const string where, const bool ok)
     {
      if(ok)
        {
         m_error_streak = 0;
         m_last_error   = "";
         return;
        }
      m_error_streak++;
      m_last_error_time = TimeCurrent();
      m_last_error = StringFormat("%s | retcode=%u (%s)", where,
                                  m_trade.ResultRetcode(),
                                  m_trade.ResultRetcodeDescription());
      PrintFormat("[APEX:EXEC] HATA %s (seri=%d)", m_last_error, m_error_streak);
     }

public:
                     CApexExecution() { m_ready = false; m_error_streak = 0; m_last_error_time = 0; m_last_error = ""; }
                    ~CApexExecution() { }

   //+------------------------------------------------------------------+
   bool Init(const SApexConfig &cfg)
     {
      m_symbol   = cfg.symbol;
      m_magic    = cfg.magic;
      m_deviation= cfg.deviation;
      m_point    = SymbolInfoDouble(m_symbol, SYMBOL_POINT);
      m_digits   = (int)SymbolInfoInteger(m_symbol, SYMBOL_DIGITS);
      m_tick     = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_SIZE);
      m_lot_min  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MIN);
      m_lot_max  = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_MAX);
      m_lot_step = SymbolInfoDouble(m_symbol, SYMBOL_VOLUME_STEP);
      m_stops_level  = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_STOPS_LEVEL);
      m_freeze_level = SymbolInfoInteger(m_symbol, SYMBOL_TRADE_FREEZE_LEVEL);

      double tick_value = SymbolInfoDouble(m_symbol, SYMBOL_TRADE_TICK_VALUE);
      double tick_size  = m_tick > 0.0 ? m_tick : m_point;
      m_point_value     = ApexSafeDiv(tick_value, tick_size, 0.0); // 1.0 fiyat birimi basina para/lot

      if(m_point <= 0.0)      m_point = 0.00001;
      if(m_tick  <= 0.0)      m_tick  = m_point;
      if(m_lot_step <= 0.0)   m_lot_step = 0.01;
      if(m_lot_min  <= 0.0)   m_lot_min  = m_lot_step;
      if(m_lot_max  <= 0.0)   m_lot_max  = 100.0;
      m_min_stop_dist = MinStopDistance();

      m_trade.SetExpertMagicNumber(m_magic);
      m_trade.SetDeviationInPoints(m_deviation);
      m_trade.SetAsyncMode(false);
      m_trade.SetTypeFillingBySymbol(m_symbol);

      m_ready = (m_point_value > 0.0);
      ArrayResize(m_book, 0);
      return m_ready;
     }

   string Symbol()      { return m_symbol;   }
   double Point()       { return m_point;    }
   double Tick()        { return m_tick;     }
   int    Digits()      { return m_digits;   }
   double PointValue()  { return m_point_value; }
   double LotMin()      { return m_lot_min;  }
   double LotStep()     { return m_lot_step; }
   double MinStopDist() { return m_min_stop_dist; }
   string LastError()   { return m_last_error; }
   int    ErrorStreak() { return m_error_streak; }

   //+------------------------------------------------------------------+
   //| Fiyat / lot normalizasyonu                                       |
   //+------------------------------------------------------------------+
   double NormPrice(const double price, const int round_dir)
     {
      if(price <= 0.0 || m_tick <= 0.0)
         return NormalizeDouble(price, m_digits);
      double units = price / m_tick;
      if(round_dir > 0)       units = MathCeil(units - 1.0e-10);
      else if(round_dir < 0)  units = MathFloor(units + 1.0e-10);
      else                    units = MathRound(units);
      return NormalizeDouble(units * m_tick, m_digits);
     }

   double NormVolume(const double requested)
     {
      if(m_lot_step <= 0.0)
         return 0.0;
      double v = requested;
      if(m_lot_max > 0.0 && v > m_lot_max)
         v = m_lot_max;
      v = MathFloor(v / m_lot_step + 1.0e-9) * m_lot_step;
      v = NormalizeDouble(v, 8);
      if(v < m_lot_min - 1.0e-10)
         return 0.0;
      return v;
     }

   // Stop seviyelerini broker kisitlarina gore iteleyerek guvenli hale getirir
   bool   SafeStops(const int side, const double entry, double &sl, double &tp)
     {
      double mind = m_min_stop_dist;
      if(sl > 0.0)
        {
         double need = (side > 0) ? (entry - sl) : (sl - entry);
         if(need < mind)
            sl = (side > 0) ? NormPrice(entry - mind, -1) : NormPrice(entry + mind, 1);
        }
      if(tp > 0.0)
        {
         double need = (side > 0) ? (tp - entry) : (entry - tp);
         if(need < mind)
            tp = (side > 0) ? NormPrice(entry + mind, 1) : NormPrice(entry - mind, -1);
        }
      return true;
     }

   //+------------------------------------------------------------------+
   //| Piyasa kosullari                                                 |
   //+------------------------------------------------------------------+
   double SpreadPoints()
     {
      MqlTick tk;
      if(!SymbolInfoTick(m_symbol, tk) || tk.ask <= 0.0)
         return 1.0e9;
      double sp = (tk.ask - tk.bid);
      if(sp <= 0.0)
         sp = (double)SymbolInfoInteger(m_symbol, SYMBOL_SPREAD) * m_point;
      return sp / m_point;
     }

   bool   SpreadOK(const double max_points)
     {
      if(max_points <= 0)
         return true;
      return (SpreadPoints() <= max_points);
     }

   double Ask() { MqlTick tk; if(!SymbolInfoTick(m_symbol, tk)) return 0.0; return tk.ask; }
   double Bid() { MqlTick tk; if(!SymbolInfoTick(m_symbol, tk)) return 0.0; return tk.bid; }

   double MarginLevelPct()
     {
      double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
      double mar = AccountInfoDouble(ACCOUNT_MARGIN);
      if(mar <= 0.0)
         return 9999.0;
      return (eq / mar) * 100.0;
     }

   double FreeMarginPct()
     {
      double eq = AccountInfoDouble(ACCOUNT_EQUITY);
      double fm = AccountInfoDouble(ACCOUNT_MARGIN_FREE);
      if(eq <= 0.0)
         return 0.0;
      return ApexClamp(fm / eq, 0.0, 1.0);
     }

   //+------------------------------------------------------------------+
   //| Emir gonderimi - rol etiketli, geri cekilmeli yeniden denemeli   |
   //+------------------------------------------------------------------+
   ulong OpenMarket(const int side, const double lot_in, const double sl_in,
                    const double tp_in, const int role, const int level)
     {
      if(!m_ready)
         return 0;
      double lot = NormVolume(lot_in);
      if(lot <= 0.0)
        {
         Print("[APEX:EXEC] Lot broker limitlerine uymuyor, emir iptal.");
         return 0;
        }

      double sl = sl_in, tp = tp_in;
      double px = (side > 0 ? Ask() : Bid());
      if(px <= 0.0)
         return 0;
      SafeStops(side, px, sl, tp);

      string tag = ApexEncodeTag(role, side, level);
      bool ok = false;
      for(int attempt = 0; attempt < 3; attempt++)
        {
         ResetLastError();
         if(side > 0) ok = m_trade.Buy(lot, m_symbol, 0.0, sl, tp, tag);
         else         ok = m_trade.Sell(lot, m_symbol, 0.0, sl, tp, tag);

         uint code = m_trade.ResultRetcode();
         bool good = (ok && (code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_DONE_PARTIAL ||
                             code == TRADE_RETCODE_PLACED || code == TRADE_RETCODE_NO_CHANGES));
         if(good)
           {
            m_error_streak = 0;
            ulong tk = m_trade.ResultDeal();
            PrintFormat("[APEX:EXEC] %s %.2f lot acildi | rol=%s lvl=%+d | deal=%I64u",
                        ApexSideName(side), lot, ApexRoleName(role), level, tk);
            return m_trade.ResultOrder();
           }
         // Self-healing: yeniden fiyatla, lotu bir adim kirp, tekrar dene
         if(RetryableError(code) && attempt < 2)
           {
            Sleep(120);
            px = (side > 0 ? Ask() : Bid());
            SafeStops(side, px, sl, tp);
            continue;
           }
         if(code == TRADE_RETCODE_INVALID_VOLUME || code == TRADE_RETCODE_NO_MONEY)
           {
            lot = NormVolume(lot - m_lot_step);
            if(lot < m_lot_min)
               break;
            continue;
           }
         NoteError("OpenMarket", false);
         return 0;
        }
      NoteError("OpenMarket", false);
      return 0;
     }

   ulong PlacePending(const int order_type, const double lot_in, const double price_in,
                      const double sl_in, const double tp_in, const int role, const int level)
     {
      if(!m_ready)
         return 0;
      double lot = NormVolume(lot_in);
      if(lot <= 0.0)
         return 0;
      if(price_in <= 0.0)
         return 0;

      double sl = sl_in, tp = tp_in;
      int side = (order_type == ORDER_TYPE_BUY_LIMIT || order_type == ORDER_TYPE_BUY_STOP) ? 1 : -1;
      SafeStops(side, price_in, sl, tp);

      string tag = ApexEncodeTag(role, side, level);
      bool ok = false;
      for(int attempt = 0; attempt < 2; attempt++)
        {
         ResetLastError();
         switch((ENUM_ORDER_TYPE)order_type)
           {
            case ORDER_TYPE_BUY_LIMIT:  ok = m_trade.BuyLimit (lot, price_in, m_symbol, sl, tp, ORDER_TIME_GTC, 0, tag); break;
            case ORDER_TYPE_SELL_LIMIT: ok = m_trade.SellLimit(lot, price_in, m_symbol, sl, tp, ORDER_TIME_GTC, 0, tag); break;
            case ORDER_TYPE_BUY_STOP:   ok = m_trade.BuyStop  (lot, price_in, m_symbol, sl, tp, ORDER_TIME_GTC, 0, tag); break;
            case ORDER_TYPE_SELL_STOP:  ok = m_trade.SellStop (lot, price_in, m_symbol, sl, tp, ORDER_TIME_GTC, 0, tag); break;
            default: return 0;
           }
         uint code = m_trade.ResultRetcode();
         if(ok && (code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_PLACED || code == TRADE_RETCODE_NO_CHANGES))
           {
            m_error_streak = 0;
            return m_trade.ResultOrder();
           }
         if(RetryableError(code) && attempt == 0)
           {
            Sleep(120);
            continue;
           }
         break;
        }
      NoteError("PlacePending", false);
      return 0;
     }

   bool CloseTicket(const ulong ticket, const string reason)
     {
      if(ticket == 0)
         return true;
      if(!PositionSelectByTicket(ticket))
         return true;
      for(int a = 0; a < 3; a++)
        {
         ResetLastError();
         bool ok = m_trade.PositionClose(ticket, m_deviation);
         uint code = m_trade.ResultRetcode();
         if(ok && (code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_DONE_PARTIAL ||
                   code == TRADE_RETCODE_PLACED || code == TRADE_RETCODE_NO_CHANGES))
           {
            m_error_streak = 0;
            PrintFormat("[APEX:EXEC] Kapatildi ticket=%I64u neden=%s", ticket, reason);
            return true;
           }
         if(RetryableError(code))
           {
            Sleep(120);
            continue;
           }
         break;
        }
      NoteError(StringFormat("CloseTicket(%I64u,%s)", ticket, reason), false);
      return false;
     }

   bool ModifyStops(const ulong ticket, const double sl, const double tp)
     {
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         return false;
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      int    type  = (int)PositionGetInteger(POSITION_TYPE);
      int    side  = (type == POSITION_TYPE_BUY) ? 1 : -1;
      double nsl = sl, ntp = tp;
      SafeStops(side, entry, nsl, ntp);
      ResetLastError();
      bool ok = m_trade.PositionModify(ticket, nsl, ntp);
      uint code = m_trade.ResultRetcode();
      if(ok && (code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_NO_CHANGES))
         return true;
      return false;
     }

   bool DeleteOrder(const ulong ticket)
     {
      if(ticket == 0)
         return true;
      if(!OrderSelect(ticket))
         return true;
      ResetLastError();
      bool ok = m_trade.OrderDelete(ticket);
      uint code = m_trade.ResultRetcode();
      if(ok && (code == TRADE_RETCODE_DONE || code == TRADE_RETCODE_PLACED || code == TRADE_RETCODE_NO_CHANGES))
         return true;
      return false;
     }

   //+------------------------------------------------------------------+
   //| Defter: biletlerden yeniden insa (self-healing mutabakat)        |
   //+------------------------------------------------------------------+
   bool IsOurTicket(const ulong ticket)
     {
      if(!PositionSelectByTicket(ticket))
         return false;
      if(PositionGetString(POSITION_SYMBOL) != m_symbol)
         return false;
      if((ulong)PositionGetInteger(POSITION_MAGIC) != m_magic)
         return false;
      return true;
     }

   int RebuildBook()
     {
      ArrayResize(m_book, 0);
      int total = PositionsTotal();
      for(int i = 0; i < total; i++)
        {
         ulong tk = PositionGetTicket(i);
         if(tk == 0 || !IsOurTicket(tk))
            continue;

         SBookEntry e;
         e.ticket = tk;
         string comment = PositionGetString(POSITION_COMMENT);
         int role = 0, side = 0, level = 0;
         if(!ApexDecodeTag(comment, role, side, level))
           {
            // Etiket okunamadiysa (broker yorumu kirpti / elle acilan islem)
            // pozisyon yetim kalmasin: tipinden yonu, magic'den aidiyeti al.
            long type = PositionGetInteger(POSITION_TYPE);
            side = (type == POSITION_TYPE_BUY) ? 1 : -1;
            role = (int)ROLE_CORE;
            level = 0;
           }
         e.role    = role;
         e.side    = side;
         e.level   = level;
         e.lot     = PositionGetDouble(POSITION_VOLUME);
         e.entry   = PositionGetDouble(POSITION_PRICE_OPEN);
         e.sl      = PositionGetDouble(POSITION_SL);
         e.tp      = PositionGetDouble(POSITION_TP);
         e.profit  = PositionGetDouble(POSITION_PROFIT);
         e.swap    = PositionGetDouble(POSITION_SWAP);
         e.time    = (datetime)PositionGetInteger(POSITION_TIME);

         int n = ArraySize(m_book);
         ArrayResize(m_book, n + 1);
         m_book[n] = e;
        }
      return ArraySize(m_book);
     }

   int      BookSize()          { return ArraySize(m_book); }

   // Defter kaydi referans ile dondurulur: MQL5'te string/dinamik dizi
   // iceren yapisalarin deger ile kopyalanmasi derleyiciye bagli olarak
   // kisitlanabildigi icin her yer referans kullanir.
   bool     BookAt(const int i, SBookEntry &e)
     {
      if(i < 0 || i >= ArraySize(m_book))
         return false;
      e = m_book[i];
      return true;
     }

   int CountPos(const int role_filter, const int side_filter)
     {
      int c = 0;
      for(int i = 0; i < ArraySize(m_book); i++)
        {
         if(role_filter >= 0 && m_book[i].role != role_filter) continue;
         if(side_filter != 0 && m_book[i].side != side_filter) continue;
         c++;
        }
      return c;
     }

   int CountOrders(const int role_filter)
     {
      int c = 0;
      int total = OrdersTotal();
      for(int i = 0; i < total; i++)
        {
         ulong tk = OrderGetTicket(i);
         if(tk == 0) continue;
         if(!OrderSelect(tk)) continue;
         if(OrderGetString(ORDER_SYMBOL) != m_symbol) continue;
         if((ulong)OrderGetInteger(ORDER_MAGIC) != m_magic) continue;
         if(role_filter >= 0)
           {
            int role = 0, side = 0, level = 0;
            if(ApexDecodeTag(OrderGetString(ORDER_COMMENT), role, side, level))
              {
               if(role != role_filter) continue;
              }
            else if(role_filter != (int)ROLE_CORE)
               continue;
           }
         c++;
        }
      return c;
     }

   double BasketProfit(const int role_filter, const int side_filter)
     {
      double p = 0.0;
      for(int i = 0; i < ArraySize(m_book); i++)
        {
         if(role_filter >= 0 && m_book[i].role != role_filter) continue;
         if(side_filter != 0 && m_book[i].side != side_filter) continue;
         p += m_book[i].profit + m_book[i].swap;
        }
      return p;
     }

   double NetLots(const int role_filter)
     {
      double n = 0.0;
      for(int i = 0; i < ArraySize(m_book); i++)
        {
         if(role_filter >= 0 && m_book[i].role != role_filter) continue;
         n += m_book[i].side * m_book[i].lot;
        }
      return n;
     }

   double GrossLots(const int role_filter)
     {
      double n = 0.0;
      for(int i = 0; i < ArraySize(m_book); i++)
        {
         if(role_filter >= 0 && m_book[i].role != role_filter) continue;
         n += m_book[i].lot;
        }
      return n;
     }

   // Agirlikli ortalama giris fiyati (delta hesabinin referansi)
   double BasketVWAP(const int role_filter, const int side_filter)
     {
      double num = 0.0, den = 0.0;
      for(int i = 0; i < ArraySize(m_book); i++)
        {
         if(role_filter >= 0 && m_book[i].role != role_filter) continue;
         if(side_filter != 0 && m_book[i].side != side_filter) continue;
         num += m_book[i].entry * m_book[i].lot;
         den += m_book[i].lot;
        }
      if(den <= 0.0)
         return 0.0;
      return num / den;
     }

   // Para birimi cinsinden net delta (0 = tam notr)
   double NetDeltaMoney(const int role_filter)
     {
      double px = Bid();
      if(px <= 0.0)
         return 0.0;
      double d = 0.0;
      for(int i = 0; i < ArraySize(m_book); i++)
        {
         if(role_filter >= 0 && m_book[i].role != role_filter) continue;
         d += m_book[i].side * m_book[i].lot * (px - m_book[i].entry) * m_point_value;
        }
      return d;
     }

   // Kritik marjin testi: yeni lot acildiktan sonra marjin seviyesi tabaninin
   // uzerinde kaliyor mu? (hesap para biriminde yaklasik marjin ihtiyaci)
   bool CanAfford(const double lot, const double min_level_pct)
     {
      double margin_req = 0.0;
      if(!OrderCalcMargin(ORDER_TYPE_BUY, m_symbol, lot, Ask(), margin_req))
         return true;
      double eq  = AccountInfoDouble(ACCOUNT_EQUITY);
      double mar = AccountInfoDouble(ACCOUNT_MARGIN);
      double new_margin = mar + margin_req;
      if(new_margin <= 0.0)
         return true;
      return ((eq / new_margin) * 100.0) >= min_level_pct;
     }

   void CloseRole(const int role_filter, const string reason)
     {
      for(int i = ArraySize(m_book) - 1; i >= 0; i--)
        {
         if(role_filter >= 0 && m_book[i].role != role_filter)
            continue;
         CloseTicket(m_book[i].ticket, reason);
        }
     }

   void DeleteOrdersRole(const int role_filter)
     {
      int total = OrdersTotal();
      for(int i = total - 1; i >= 0; i--)
        {
         ulong tk = OrderGetTicket(i);
         if(tk == 0 || !OrderSelect(tk))
            continue;
         if(OrderGetString(ORDER_SYMBOL) != m_symbol)
            continue;
         if((ulong)OrderGetInteger(ORDER_MAGIC) != m_magic)
            continue;
         if(role_filter >= 0)
           {
            int role = 0, side = 0, level = 0;
            if(ApexDecodeTag(OrderGetString(ORDER_COMMENT), role, side, level))
              {
               if(role != role_filter)
                  continue;
              }
            else if(role_filter != (int)ROLE_CORE)
               continue;
           }
         DeleteOrder(tk);
        }
     }
  };

// Modul singleton'lari: baska moduller bunlari referans alir (pointer riski yok)
CApexExecution g_exec;

#endif
//+------------------------------------------------------------------+

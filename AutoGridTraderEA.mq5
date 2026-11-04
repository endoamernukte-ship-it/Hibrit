//+------------------------------------------------------------------+
//|                                             AutoGridTraderEA.mq5 |
//|  Otomatik Grid Robotu                                             |
//|  - Grid aralığı geçmiş mumlardan otomatik hesaplanır              |
//|    (varsayılan: fiyat değişimlerinin standart sapması × katsayı)  |
//|  - LONG:  fiyat bir gridi aşağıdan yukarı kesince açar;           |
//|            aşağı kesince EN ESKİ açık long'u kapatır (FIFO)       |
//|  - SHORT: fiyat bir gridi aşağı kestikçe açar;                    |
//|            yukarı kestikçe EN ESKİ açık short'u kapatır (FIFO)    |
//|  - Her grid seviyesinde aynı anda en fazla 1 açık long / 1 short  |
//|  - Aynı grid üzerinde long ve short kitapları bağımsızdır         |
//|  - Yalnız HEDGE hesaplarda çalışır (netting'te başlatma durur)    |
//+------------------------------------------------------------------+
#property copyright "AutoGridTraderEA"
#property version   "1.00"

#include <Trade\Trade.mqh>

//+------------------------------------------------------------------+
//| Ayarlar                                                           |
//+------------------------------------------------------------------+
enum ENUM_GRID_METHOD
  {
   GRID_METHOD_STDDEV   = 0,   // Standart sapma (fiyat değişimleri)
   GRID_METHOD_ATR      = 1,   // ATR
   GRID_METHOD_AVGRANGE = 2,   // Ortalama mum boyu
   GRID_METHOD_MINMAX   = 3    // Min-max aralığı / seviye sayısı
  };

enum ENUM_GRID_TRADE_MODE
  {
   GRID_TRADE_ON      = 0,     // Otomatik işlem
   GRID_TRADE_SIGNAL  = 1      // Sadece sinyal (emir yok)
  };

enum ENUM_GRID_LOT_MODE
  {
   GRID_LOT_FIXED = 0,         // Sabit lot
   GRID_LOT_RISK  = 1          // Risk yüzdesi
  };

input group             "═══ Grid Ayarları ═══"
input ENUM_GRID_METHOD  InpGridMethod      = GRID_METHOD_STDDEV; // Aralık hesabı yöntemi
input int               InpGridLookback    = 200;    // Geçmiş mum sayısı (hesap penceresi)
input double            InpGridMult        = 1.0;    // Aralık katsayı (hesaplanan değer × bu)
input int               InpGridATRPeriod   = 14;     // ATR periyodu (yalnız ATR yöntemi)
input int               InpGridLevels      = 10;     // Her yönde çizilecek seviye sayısı
input int               InpGridRecalcBars  = 0;      // Yeniden hesaplama (0 = bir kez, X = her X barda)

input group             "═══ Trade (İşlem) ═══"
input ENUM_GRID_TRADE_MODE InpTradeMode    = GRID_TRADE_ON; // İşlem modu
input bool              InpReverseMode     = false;  // Ters mod (yukarı geçiş = short açar)
input ENUM_GRID_LOT_MODE InpLotMode        = GRID_LOT_FIXED; // Lot modu
input double            InpFixedLot        = 0.01;   // Sabit lot
input double            InpRiskPercent     = 1.0;    // Risk % (grid aralığı mesafesine göre)
input double            InpRiskGridMult    = 1.0;    // Risk mesafesi = grid aralığı × bu
input bool              InpUseTPSL         = false;  // Opsiyonel TP/SL (varsayılan kapalı)
input double            InpTPGridMult      = 1.0;    // TP = grid aralığı × bu
input double            InpSLGridMult      = 1.0;    // SL = grid aralığı × bu
input long              InpMagic           = 20261032; // Magic number
input ulong             InpDeviation       = 30;     // Slippage (points)

input group             "═══ Görsel & Bildirim ═══"
input bool              InpDrawGrid        = true;   // Grid çizgilerini çiz
input bool              InpDrawSignals     = true;   // Açılış işaretleri
input bool              InpAlertsOn        = true;   // Terminal alert
input bool              InpPushOn          = false;  // Mobil push
input bool              InpShowPanel       = true;   // Durum paneli

//+------------------------------------------------------------------+
//| Durum                                                             |
//+------------------------------------------------------------------+
struct GridTrade
  {
   ulong  ticket;      // MT5 pozisyon bileti (0 = sinyal modunda sanal kayıt)
   int    dir;         // +1 long, -1 short
   int    levelIdx;    // açıldığı grid çizgisi (seviye kilidi için)
   double openPrice;
   double sl, tp;      // opsiyonel TP/SL seviyeleri (0 = yok)
   datetime openTime;
   long   openBar;
   string objMark;
  };

GridTrade g_longs[];    // FIFO: indeks 0 = en eski
GridTrade g_shorts[];

double g_tickSize, g_point, g_digits, g_pipSize;
double g_interval = 0.0;   // grid aralığı
double g_center   = 0.0;   // grid merkezi (referans fiyat)
int    g_curBand  = 0;     // fiyatın bulunduğu band indeksi
bool   g_hedgeMode = false;

datetime g_lastBarTime = 0;
int      g_barsSinceCalc = 0;
long     g_seq = 0;

double g_realizedPips = 0.0;
double g_realizedPct  = 0.0;
long   g_totalOpens = 0;
long   g_totalCloses = 0;

//+------------------------------------------------------------------+
//| Yardımcılar                                                       |
//+------------------------------------------------------------------+
double NormPrice(double price)
  {
   return NormalizeDouble(MathRound(price / g_tickSize) * g_tickSize, (int)g_digits);
  }

double NormalizeLots(double lots)
  {
   double minLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double maxLot  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double lotStep = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(lotStep > 0.0)
      lots = MathFloor(lots / lotStep) * lotStep;
   if(lots < minLot) lots = minLot;
   if(lots > maxLot) lots = maxLot;
   return NormalizeDouble(lots, 2);
  }

double CalcLots(double riskDistance)
  {
   if(InpLotMode == GRID_LOT_FIXED)
      return NormalizeLots(InpFixedLot);
   double balance = AccountInfoDouble(ACCOUNT_BALANCE);
   double riskMoney = balance * InpRiskPercent / 100.0;
   double tickValue = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_VALUE);
   if(tickValue <= 0.0 || g_tickSize <= 0.0 || riskDistance <= 0.0)
      return NormalizeLots(InpFixedLot);
   double lots = riskMoney / (riskDistance / g_tickSize * tickValue);
   return NormalizeLots(lots);
  }

void Notify(const string title, const string text)
  {
   if(InpAlertsOn)
      Alert(title, ": ", text);
   if(InpPushOn)
      SendNotification(title + ": " + text);
  }

//+------------------------------------------------------------------+
//| Grid aralığı hesabı                                               |
//+------------------------------------------------------------------+
double CalcGridInterval()
  {
   int n = InpGridLookback;
   if(n < 10) n = 10;
   double v = 0.0;

   if(InpGridMethod == GRID_METHOD_STDDEV)
     {
      // fiyat değişimlerinin (close-to-close) standart sapması
      double changes[];
      ArrayResize(changes, n);
      int cnt = 0;
      double sum = 0.0;
      for(int i = 1; i <= n; i++)
        {
         double c1 = iClose(_Symbol, _Period, i);
         double c0 = iClose(_Symbol, _Period, i + 1);
         if(c1 == 0.0 || c0 == 0.0)
            break;
         double d = c1 - c0;
         changes[cnt++] = d;
         sum += d;
        }
      if(cnt < 2)
         return 0.0;
      double mean = sum / cnt;
      double var = 0.0;
      for(int i = 0; i < cnt; i++)
        {
         double dv = changes[i] - mean;
         var += dv * dv;
        }
      v = MathSqrt(var / (cnt - 1)) * InpGridMult;
     }
   else if(InpGridMethod == GRID_METHOD_ATR)
     {
      int h = iATR(_Symbol, _Period, InpGridATRPeriod);
      if(h == INVALID_HANDLE)
         return 0.0;
      double buf[1];
      if(CopyBuffer(h, 0, 1, 1, buf) != 1)
        {
         IndicatorRelease(h);
         return 0.0;
        }
      IndicatorRelease(h);
      v = buf[0] * InpGridMult;
     }
   else if(InpGridMethod == GRID_METHOD_AVGRANGE)
     {
      double sum = 0.0;
      int cnt = 0;
      for(int i = 1; i <= n; i++)
        {
         double hi = iHigh(_Symbol, _Period, i);
         double lo = iLow(_Symbol, _Period, i);
         if(hi == 0.0 || lo == 0.0)
            break;
         sum += hi - lo;
         cnt++;
        }
      if(cnt == 0)
         return 0.0;
      v = (sum / cnt) * InpGridMult;
     }
   else // GRID_METHOD_MINMAX
     {
      double hi = -DBL_MAX, lo = DBL_MAX;
      int cnt = 0;
      for(int i = 1; i <= n; i++)
        {
         double h2 = iHigh(_Symbol, _Period, i);
         double l2 = iLow(_Symbol, _Period, i);
         if(h2 == 0.0 || l2 == 0.0)
            break;
         if(h2 > hi) hi = h2;
         if(l2 < lo) lo = l2;
         cnt++;
        }
      if(cnt == 0)
         return 0.0;
      int levels = MathMax(InpGridLevels, 1);
      v = ((hi - lo) / levels) * InpGridMult;
     }

   // anlamsız küçük aralıkları engelle (en az 5 tick)
   double floorMin = g_tickSize * 5.0;
   if(v < floorMin)
      v = floorMin;
   return NormalizeDouble(v, (int)g_digits);
  }

//+------------------------------------------------------------------+
//| Grid kurulumu / yeniden hesaplama                                 |
//+------------------------------------------------------------------+
void CalcGrid()
  {
   double interval = CalcGridInterval();
   if(interval <= 0.0)
     {
      Print("GT: grid aralığı hesaplanamadı, eski değer korunuyor.");
      return;
     }
   g_interval = interval;
   g_center = NormPrice(SymbolInfoDouble(_Symbol, SYMBOL_BID));
   int newBand = (int)MathFloor((SymbolInfoDouble(_Symbol, SYMBOL_BID) - g_center) / g_interval + 1e-9);
   g_curBand = newBand;

   // açık kayıtların seviye anahtarlarını yeni gride göre tazele
   for(int i = 0; i < ArraySize(g_longs); i++)
      g_longs[i].levelIdx = (int)MathRound((g_longs[i].openPrice - g_center) / g_interval);
   for(int i = 0; i < ArraySize(g_shorts); i++)
      g_shorts[i].levelIdx = (int)MathRound((g_shorts[i].openPrice - g_center) / g_interval);

   Print("GT: grid kuruldu - aralık=", DoubleToString(g_interval, g_digits),
         " merkez=", DoubleToString(g_center, g_digits),
         " band=", IntegerToString(g_curBand));
  }

void ClearGridObjects()
  {
   for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i);
      if(StringFind(name, "GT_") == 0)
         ObjectDelete(0, name);
     }
  }

void DrawGrid()
  {
   if(!InpDrawGrid)
      return;
   // eski grid çizgilerini temizle (oklar kalır)
   for(int i = ObjectsTotal(0, -1, -1) - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i);
      if(StringFind(name, "GT_GRID_") == 0)
         ObjectDelete(0, name);
     }
   for(int i = -InpGridLevels; i <= InpGridLevels; i++)
     {
      if(i == 0)
         continue;
      string name = "GT_GRID_" + IntegerToString(i);
      double price = NormPrice(g_center + i * g_interval);
      ObjectCreate(0, name, OBJ_HLINE, 0, 0, price);
      color c = (i % 5 == 0) ? clrSteelBlue : clrDimGray;
      ObjectSetInteger(0, name, OBJPROP_COLOR, c);
      ObjectSetInteger(0, name, OBJPROP_STYLE, STYLE_DOT);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, (i % 5 == 0) ? 1 : 0);
      ObjectSetInteger(0, name, OBJPROP_BACK, true);
     }
   ChartRedraw();
  }

//+------------------------------------------------------------------+
//| Kitap yardımcıları                                                 |
//+------------------------------------------------------------------+
bool BookHasLevel(const GridTrade &book[], int levelIdx)
  {
   for(int i = 0; i < ArraySize(book); i++)
      if(book[i].levelIdx == levelIdx)
         return true;
   return false;
  }

void BookAppend(GridTrade &book[], const GridTrade &rec)
  {
   int n = ArraySize(book);
   ArrayResize(book, n + 1);
   book[n] = rec;
  }

void BookRemoveFirst(GridTrade &book[])
  {
   int n = ArraySize(book);
   if(n == 0)
      return;
   for(int k = 0; k < n - 1; k++)
      book[k] = book[k + 1];
   ArrayResize(book, n - 1);
  }

//+------------------------------------------------------------------+
//| Açılış: verilen grid çizgisinde yer doluysa AÇILMAZ               |
//+------------------------------------------------------------------+
void TryOpen(GridTrade &book[], int dir, int lineIdx)
  {
   if(BookHasLevel(book, lineIdx))
     {
      Print("GT: seviye ", IntegerToString(lineIdx), " zaten dolu - yeni ",
            (dir > 0) ? "LONG" : "SHORT", " açılmadı (seviye başına 1 pozisyon).");
      return;
     }

   double px = (dir > 0) ? SymbolInfoDouble(_Symbol, SYMBOL_ASK)
                         : SymbolInfoDouble(_Symbol, SYMBOL_BID);
   px = NormPrice(px);

   double sl = 0.0, tp = 0.0;
   if(InpUseTPSL)
     {
      sl = NormPrice(px - dir * g_interval * InpSLGridMult);
      tp = NormPrice(px + dir * g_interval * InpTPGridMult);
      double minDist = SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL) * g_point;
      if(minDist > 0.0 && (MathAbs(px - sl) < minDist || MathAbs(tp - px) < minDist))
        {
         Print("GT: broker min. stop mesafesi sağlanamıyor - emir atlandı (seviyeler korunur).");
         return;
        }
     }

   GridTrade rec;
   rec.ticket = 0;
   rec.dir = dir;
   rec.levelIdx = lineIdx;
   rec.openPrice = px;
   rec.sl = sl;
   rec.tp = tp;
   rec.openTime = TimeCurrent();
   rec.openBar = g_barsSinceCalc;
   rec.objMark = "";

   if(InpTradeMode == GRID_TRADE_ON)
     {
      double lots = CalcLots(g_interval * InpRiskGridMult);
      CTrade trade;
      trade.SetExpertMagicNumber(InpMagic);
      trade.SetDeviationInPoints(InpDeviation);
      trade.SetTypeFillingBySymbol(_Symbol);
      bool ok = false;
      if(dir > 0)
         ok = trade.Buy(lots, _Symbol, 0.0, sl, tp, "GRID LONG");
      else
         ok = trade.Sell(lots, _Symbol, 0.0, sl, tp, "GRID SHORT");
      if(!(ok && trade.ResultRetcode() == TRADE_RETCODE_DONE))
        {
         Print("GT: emir gönderilemedi, retcode=", trade.ResultRetcode(),
               " comment=", trade.ResultComment());
         return;
        }
      ulong deal = trade.ResultDeal();
      ulong posId = 0;
      if(deal > 0)
         posId = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      if(posId == 0)
         posId = trade.ResultOrder();
      rec.ticket = posId;

      // opsiyonel TP/SL: dolum sonrası doğrulama (bağlanmamışsa ekle)
      if(InpUseTPSL && posId != 0 && PositionSelectByTicket(posId))
        {
         double curSL = PositionGetDouble(POSITION_SL);
         double curTP = PositionGetDouble(POSITION_TP);
         if(MathAbs(curSL - sl) > g_tickSize * 0.5 || MathAbs(curTP - tp) > g_tickSize * 0.5)
           {
            CTrade mod;
            mod.SetDeviationInPoints(InpDeviation);
            if(mod.PositionModify(posId, sl, tp))
               Print("GT: SL/TP pozisyona eklendi -> SL=", DoubleToString(sl, g_digits),
                     " TP=", DoubleToString(tp, g_digits));
            else
               Print("GT: SL/TP değiştirilemedi, retcode=", mod.ResultRetcode());
           }
        }
     }

   // açılış işareti
   if(InpDrawSignals)
     {
      string name = "GT_OPN_" + IntegerToString(++g_seq);
      ObjectCreate(0, name, OBJ_ARROW, 0, rec.openTime, rec.openPrice);
      ObjectSetInteger(0, name, OBJPROP_ARROWCODE, (dir > 0) ? 233 : 234);
      ObjectSetInteger(0, name, OBJPROP_COLOR, (dir > 0) ? clrDodgerBlue : clrOrangeRed);
      ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
      rec.objMark = name;
     }

   BookAppend(book, rec);
   g_totalOpens++;
   string modeTag = (InpTradeMode == GRID_TRADE_ON) ? "" : " [SİNYAL]";
   Print("GT: ", (dir > 0) ? "LONG" : "SHORT", " açıldı seviye=", IntegerToString(lineIdx),
         " fiyat=", DoubleToString(px, g_digits),
         (rec.ticket != 0) ? (" ticket=" + IntegerToString((long)rec.ticket)) : " (sanal)",
         modeTag);
   Notify("Grid " + ((dir > 0) ? "LONG" : "SHORT") + " açılışı",
          _Symbol + " seviye " + DoubleToString(px, g_digits));
  }

//+------------------------------------------------------------------+
//| Kapanış: kitaptan EN ESKİ pozisyonu kapatır (FIFO)                |
//+------------------------------------------------------------------+
void CloseOne(GridTrade &book[], int crossLine)
  {
   int n = ArraySize(book);
   if(n == 0)
      return;

   GridTrade rec = book[0];
   double exitPrice = SymbolInfoDouble(_Symbol, SYMBOL_BID);

   if(rec.ticket != 0 && PositionSelectByTicket(rec.ticket))
     {
      CTrade trade;
      trade.SetDeviationInPoints(InpDeviation);
      if(!trade.PositionClose(rec.ticket, InpDeviation))
         Print("GT: kapatma başarısız, retcode=", trade.ResultRetcode());
     }

   // gerçekleşen P/L takibi
   if(rec.openPrice > 0.0)
     {
      double movePips = MathAbs(exitPrice - rec.openPrice) / g_pipSize;
      double mult = (rec.dir > 0) ? (exitPrice / rec.openPrice - 1.0)
                                  : (1.0 - exitPrice / rec.openPrice);
      g_realizedPips += movePips * rec.dir;
      g_realizedPct += mult * 100.0;
     }
   g_totalCloses++;

   Print("GT: ", (rec.dir > 0) ? "LONG" : "SHORT", " kapatıldı (",
         IntegerToString(crossLine), ". çizgi geçişi, FIFO) fiyat=",
         DoubleToString(exitPrice, g_digits),
         (rec.ticket != 0) ? (" ticket=" + IntegerToString((long)rec.ticket)) : " (sanal)");
   Notify("Grid " + ((rec.dir > 0) ? "LONG" : "SHORT") + " kapanışı",
          _Symbol + " fiyat " + DoubleToString(exitPrice, g_digits));

   BookRemoveFirst(book);
  }

//+------------------------------------------------------------------+
//| Geçiş olayları                                                    |
//+------------------------------------------------------------------+
void OnCrossUp(int lineIdx)
  {
   // normal mod: yukarı geçiş LONG açar + açık SHORT'tan birini kapatır
   // ters mod:   yukarı geçiş SHORT açar + açık LONG'dan birini kapatır
   if(!InpReverseMode)
     {
      TryOpen(g_longs, +1, lineIdx);
      CloseOne(g_shorts, lineIdx);
     }
   else
     {
      TryOpen(g_shorts, -1, lineIdx);
      CloseOne(g_longs, lineIdx);
     }
  }

void OnCrossDown(int lineIdx)
  {
   // normal mod: aşağı geçiş SHORT açar + açık LONG'dan birini kapatır
   // ters mod:   aşağı geçiş LONG açar + açık SHORT'tan birini kapatır
   if(!InpReverseMode)
     {
      TryOpen(g_shorts, -1, lineIdx);
      CloseOne(g_longs, lineIdx);
     }
   else
     {
      TryOpen(g_longs, +1, lineIdx);
      CloseOne(g_shorts, lineIdx);
     }
  }

//+------------------------------------------------------------------+
//| Band yürüyüşü: fiyatın geçtiği her grid çizgisini olaya çevirir   |
//+------------------------------------------------------------------+
void BandWalk()
  {
   if(g_interval <= 0.0)
      return;
   double p = SymbolInfoDouble(_Symbol, SYMBOL_BID);
   int newBand = (int)MathFloor((p - g_center) / g_interval + 1e-9);
   int guard = 0;
   while(g_curBand < newBand && guard < 10000)
     {
      g_curBand++;
      OnCrossUp(g_curBand);          // bandın alt sınırındaki çizgi aşıldı
      guard++;
     }
   while(g_curBand > newBand && guard < 10000)
     {
      g_curBand--;
      OnCrossDown(g_curBand + 1);    // bandın üst sınırındaki çizgi aşıldı
      guard++;
     }
  }

//+------------------------------------------------------------------+
//| Kitap bakımı: manuel/SL/TP ile kapanan kayıtları temizle          |
//| (sinyal modundaki sanal kayıtlar ticket=0 → asla silinmez)        |
//+------------------------------------------------------------------+
void BookRemoveAt(GridTrade &book[], int idx)
  {
   int n = ArraySize(book);
   for(int k = idx; k < n - 1; k++)
      book[k] = book[k + 1];
   ArrayResize(book, n - 1);
  }

void ManageBooks()
  {
   for(int i = ArraySize(g_longs) - 1; i >= 0; i--)
      if(g_longs[i].ticket != 0 && !PositionSelectByTicket(g_longs[i].ticket))
         BookRemoveAt(g_longs, i);
   for(int i = ArraySize(g_shorts) - 1; i >= 0; i--)
      if(g_shorts[i].ticket != 0 && !PositionSelectByTicket(g_shorts[i].ticket))
         BookRemoveAt(g_shorts, i);
  }

//+------------------------------------------------------------------+
//| Yeniden hesaplama kontrolü                                        |
//+------------------------------------------------------------------+
void CheckRecalc()
  {
   datetime t = iTime(_Symbol, _Period, 0);
   if(t == 0 || t == g_lastBarTime)
      return;
   g_lastBarTime = t;
   g_barsSinceCalc++;
   if(InpGridRecalcBars > 0 && g_barsSinceCalc >= InpGridRecalcBars)
     {
      g_barsSinceCalc = 0;
      CalcGrid();
      DrawGrid();
     }
  }

//+------------------------------------------------------------------+
//| Mevcut pozisyonları sahiplen (magic filtresi)                     |
//+------------------------------------------------------------------+
void SortBook(GridTrade &book[])
  {
   int n = ArraySize(book);
   for(int i = 1; i < n; i++)
     {
      GridTrade key = book[i];
      int j = i - 1;
      while(j >= 0 && book[j].openTime > key.openTime)
        {
         book[j + 1] = book[j];
         j--;
        }
      book[j + 1] = key;
     }
  }

void AdoptExistingPositions()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0)
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol)
         continue;
      if(PositionGetInteger(POSITION_MAGIC) != InpMagic)
         continue;
      long dir = (PositionGetInteger(POSITION_TYPE) == POSITION_TYPE_BUY) ? 1 : -1;
      double openP = PositionGetDouble(POSITION_PRICE_OPEN);

      GridTrade rec;
      rec.ticket = ticket;
      rec.dir = (int)dir;
      rec.levelIdx = (g_interval > 0.0) ? (int)MathRound((openP - g_center) / g_interval) : 0;
      rec.openPrice = openP;
      rec.sl = PositionGetDouble(POSITION_SL);
      rec.tp = PositionGetDouble(POSITION_TP);
      rec.openTime = (datetime)PositionGetInteger(POSITION_TIME);
      rec.openBar = 0;
      rec.objMark = "";
      if(dir > 0)
         BookAppend(g_longs, rec);
      else
         BookAppend(g_shorts, rec);
      Print("GT: mevcut pozisyon sahiplendi, ticket=", ticket);
     }
   SortBook(g_longs);    // FIFO sırası: en eski en önde
   SortBook(g_shorts);
  }

//+------------------------------------------------------------------+
//| Durum paneli                                                      |
//+------------------------------------------------------------------+
void UpdateStatusPanel()
  {
   string txt = "";
   txt += "═══ AutoGrid Trader EA ═══\n";
   txt += StringFormat("Sembol: %s  Zaman Dilimi: %s\n", _Symbol, EnumToString(_Period));
   txt += StringFormat("Grid aralığı: %s  Merkez: %s\n",
                       DoubleToString(g_interval, g_digits), DoubleToString(g_center, g_digits));
   txt += StringFormat("Aktif band: %d  |  Çizgi: ±%d  |  Yeniden hesap: %s\n",
                       g_curBand, InpGridLevels,
                       (InpGridRecalcBars > 0) ? StringFormat("her %d barda", InpGridRecalcBars) : "kapalı");
   txt += StringFormat("Açık LONG: %d  |  Açık SHORT: %d  |  Toplam aç/kapa: %d/%d\n",
                       ArraySize(g_longs), ArraySize(g_shorts), g_totalOpens, g_totalCloses);
   txt += StringFormat("Mod: %s%s%s | Lot: %s",
                       (InpTradeMode == GRID_TRADE_ON) ? "OTOMATİK İŞLEM" : "SİNYAL",
                       InpReverseMode ? " + TERS" : "",
                       InpUseTPSL ? StringFormat(" + TP/SL (%.1f grid)", InpTPGridMult) : "",
                       (InpLotMode == GRID_LOT_FIXED) ? "sabit" : "risk %");
   txt += StringFormat("\nGerçekleşen: %.1f pip | %+.2f%%", g_realizedPips, g_realizedPct);
   Comment(txt);
  }

//+------------------------------------------------------------------+
//| OnInit                                                            |
//+------------------------------------------------------------------+
int OnInit()
  {
   // YALNIZCA hedge hesap
   long am = AccountInfoInteger(ACCOUNT_MARGIN_MODE);
   g_hedgeMode = (am == ACCOUNT_MARGIN_MODE_RETAIL_HEDGING);
   if(!g_hedgeMode)
     {
      Alert("AutoGridTrader: Bu robot YALNIZCA hedge hesaplarda çalışır! ",
            "Netting hesap algılandı - başlatma durduruldu.");
      Print("GT: netting hesap algılandı - hedge hesap gereklidir, EA başlatılmadı.");
      return INIT_FAILED;
     }

   g_point = SymbolInfoDouble(_Symbol, SYMBOL_POINT);
   g_tickSize = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(g_tickSize <= 0.0)
      g_tickSize = g_point;
   g_digits = (double)SymbolInfoInteger(_Symbol, SYMBOL_DIGITS);
   int digits = (int)g_digits;
   g_pipSize = (digits == 3 || digits == 5) ? g_point * 10.0 : g_point;

   CalcGrid();
   if(g_interval <= 0.0)
     {
      Alert("AutoGridTrader: grid aralığı hesaplanamadı! (yeterli geçmiş yok mu?)");
      return INIT_FAILED;
     }
   DrawGrid();
   AdoptExistingPositions();
   g_lastBarTime = iTime(_Symbol, _Period, 0);
   UpdateStatusPanel();
   Print("GT: AutoGridTraderEA başlatıldı. aralık=", DoubleToString(g_interval, g_digits));
   return INIT_SUCCEEDED;
  }

//+------------------------------------------------------------------+
//| OnDeinit                                                          |
//+------------------------------------------------------------------+
void OnDeinit(const int reason)
  {
   ClearGridObjects();
   Comment("");
  }

//+------------------------------------------------------------------+
//| OnTick                                                            |
//+------------------------------------------------------------------+
void OnTick()
  {
   CheckRecalc();
   BandWalk();       // fiyatın geçtiği her çizgi = 1 açılış / 1 kapanış olayı
   ManageBooks();    // dışarıdan kapanan kayıtları temizle
   if(InpShowPanel)
      UpdateStatusPanel();
  }
//+------------------------------------------------------------------+

#property strict
#property version   "1.11"
#property description "Fixed-price grid sized by volatility; direction from the TradingView Technical Summary"
#property description "(26 indicators) computed natively on the selected timeframe: Buy=long, Sell=short grid"
#property description "Neutral opens nothing; on a flip the grid rebuilds the other way and open positions"
#property description "close per your choice (opposite / all / keep). Optional MACD cross entries (Pine)."
#property description "Layer-cap rotation replaces the oldest same-side position at the fresh level;"
#property description "equity target can rebase to every new low and close on the rebound."

#include <Trade/Trade.mqh>

CTrade trade;

enum ENUM_SIGNAL_MODE
  {
   SIGNAL_TECHNICAL_SUMMARY = 0,  // TradingView Teknik Özet (26 gösterge)
   SIGNAL_HEIKEN_ASHI = 1,        // Kapanmış mum: Heiken Ashi rengi
   SIGNAL_STANDARD_CANDLE = 2     // Kapanmış mum: normal mum rengi
  };

enum ENUM_RATING_GROUP
  {
   RATING_ALL = 0,                // Özet: hareketli ortalamalar + osilatörler
   RATING_MOVING_AVERAGES = 1,    // Yalnız hareketli ortalamalar (15 bileşen)
   RATING_OSCILLATORS = 2         // Yalnız osilatörler (11 bileşen)
  };

enum ENUM_RATING_VOLUME
  {
   RATING_VOLUME_TICK = 0,        // Tick hacmi (VWMA için; çoğu sembolde tek veri)
   RATING_VOLUME_REAL = 1         // Gerçek hacim (yoksa VWMA bileşeni hesaba katılmaz)
  };

enum ENUM_DIRECTION_ACTION
  {
   DIRECTION_CLOSE_OPPOSITE = 0,  // Yeni yönün tersindeki pozisyonları kapat
   DIRECTION_CLOSE_ALL = 1,       // Bu EA'nın tüm pozisyonlarını kapat
   DIRECTION_KEEP_OPEN = 2        // Kapatma; yalnız yeni girişler yeni yönde olsun
  };

enum ENUM_NEUTRAL_ACTION
  {
   NEUTRAL_KEEP_OPEN = 0,         // Nötrde açık pozisyonlar korunur, yeni giriş açılmaz
   NEUTRAL_CLOSE_ALL = 1          // Nötrde bu EA'nın tüm pozisyonları kapatılır
  };

input group "Sinyal: TradingView Teknik Özet (seçilen dakika birimi)"
input ENUM_TIMEFRAMES       InpSignalTimeframe          = PERIOD_M1;   // İbrenin hesaplanacağı zaman dilimi
input ENUM_SIGNAL_MODE      InpSignalMode               = SIGNAL_TECHNICAL_SUMMARY;
input ENUM_RATING_GROUP     InpRatingGroup              = RATING_ALL;  // Hangi ibre: Özet / Ortalamalar / Osilatörler
input bool                  InpRatingUseClosedBar       = true;        // true: son KAPANMIŞ mum (repaint yok); false: oluşan mum (TradingView canlı ibre)
input int                   InpRatingHistoryBars        = 1200;        // Hesap için çekilecek mum (EMA200 yakınsaması; min 350)
input int                   InpRatingLiveRefreshSeconds = 5;           // Canlı (oluşan mum) modda yeniden hesap aralığı, sn
input int                   InpRatingConfirmBars        = 1;           // Yön için gereken ardışık aynı yönlü kapanmış mum (1 = anında)
input double                InpRatingNeutralBound       = 0.10;        // |puan| <= bu değer NÖTR (TradingView: 0.1)
input double                InpRatingStrongBound        = 0.50;        // |puan| >  bu değer GÜÇLÜ (TradingView: 0.5)
input ENUM_RATING_VOLUME    InpRatingVolumeSource       = RATING_VOLUME_TICK;
input bool                  InpLogRatingComponents      = true;        // Yön değişince 26 bileşenin oyunu Uzman günlüğüne yaz
input int                   InpSignalHistoryBars        = 300;         // (Heiken Ashi / normal mum modunda) geriye dönük mum sayısı
input bool                  InpReverseTradeDirection    = false;       // true: AL ibresinde SHORT, SAT ibresinde LONG aç

input group "MACD sinyal girişleri (Pine: Enhanced MACD)"
input bool                  InpUseMacdSignalEntries     = false;         // true: girişler YALNIZ güçlü MACD sinyallerinden (grid geçiş girişleri kapalı)
input ENUM_TIMEFRAMES       InpMacdTimeframe            = PERIOD_CURRENT; // MACD'nin hesaplanacağı zaman dilimi (Pine'daki grafik TF'i)
input int                   InpMacdFastLength           = 12;            // MACD hızlı EMA
input int                   InpMacdSlowLength           = 26;            // MACD yavaş EMA
input int                   InpMacdSignalLength         = 9;             // MACD sinyal EMA'sı
input int                   InpMacdHistoryBars          = 400;           // Hesap geçmişi (en az yavaş+sinyal+10 mum)
input bool                  InpMacdLogSignals           = true;          // Güçlü sinyal ve açılan girişler günlüğe yazılsın

input group "Yön değişimi ve nötr davranışı"
input ENUM_DIRECTION_ACTION InpOnDirectionFlip          = DIRECTION_CLOSE_OPPOSITE; // İbre ters yöne dönünce açık pozisyonlar
input ENUM_NEUTRAL_ACTION   InpOnNeutral                = NEUTRAL_KEEP_OPEN;        // İbre NÖTR'e geçince açık pozisyonlar
input bool                  InpRebaseGridOnDirectionChange = false;    // true: yön değişince grid'i anlık fiyattan yeniden kur

input group "Otomatik grid aralığı"
input int                   InpGridRangeLookbackBars    = 20;     // Son kapanmış mumlar (sinyal zaman diliminde)
input double                InpGridStepMultiplier       = 0.50;   // Medyan (High-Low) x çarpan
input double                InpMinSpreadMultiple        = 2.00;   // Adım en az spread x bu değer
input int                   InpInitialGridLevels        = 30;     // Başlangıçta her yönde
input int                   InpMaxGridLevels            = 1000;   // Her yönde üst sınır
input bool                  InpResetGridOnInit          = false;  // true: bu başlatılışta yeni B/S hesapla
input bool                  InpDrawGridLevels           = true;
input bool                  InpEnterOnAnyCross          = true;   // false: LONG yalnız yukarı, SHORT yalnız aşağı geçişte

input group "Çıkışlar (her katman için)"
input int                   InpTakeProfitGrids          = 3;
input int                   InpStopLossGrids            = 10;

input group "Pozisyon ve lot sınırları"
input bool                  InpUseBrokerMinimumVolume   = false;  // true ise otomatik broker minimum hacmi
input double                InpFixedLots                = 0.01;   // Varsayılan; minimum lotun altındaysa işlem atlanır
input int                   InpMaxLayersPerSide         = 5;      // 0 = sınırsız
input int                   InpMaxTotalPositions        = 10;     // Bu sembol + Magic; 0 = sınırsız
input bool                  InpRotateOldestAtLimit      = true;   // true: sınır dolunca en eski aynı yönlü pozisyonu kapat, yeni seviyeden taze giriş aç
input bool                  InpOnePositionPerGridLine   = true;
input int                   InpMaxSpreadPoints          = 0;      // 0 = point bazlı ek filtre kapalı
input double                InpMaxSpreadGridFraction    = 0.50;   // Spread > grid adımının bu oranıysa yeni giriş yok

input group "İşlem"
input ulong                 InpMagicNumber              = 20261008;
input int                   InpDeviationPoints           = 20;
input bool                  InpShowChartStatus           = true;

input group "Özsermaye kâr hedefi"
input double                InpCloseAllAtEquityGain       = 0.0;   // 0 = kapalı; pozitif tutar hesap para biriminde
input bool                  InpEquityTargetRebaseOnLow    = false; // true: her yeni özsermaye dibinde hedef tabanı dibe çekilir; dipten +hedef gelince tüm pozisyonlar kapanır

input group "Strateji Sınayıcı optimizasyonu"
input bool                  InpUseRiskAdjustedTesterScore = true; // true: Custom max için kâr / özsermaye düşüşü
input int                   InpOptimizationMinTrades      = 30;   // Risk ayarlı puanda minimum işlem; 0 = filtre yok

// Grid coordinates and spacing stay fixed for this grid generation.
double g_grid_base = 0.0;
double g_grid_step = 0.0;
int    g_up_count = 0;
int    g_down_count = 0;
int    g_up_state[];       // -1 = current price below line; +1 = above; 0 = not armed
int    g_down_state[];

int      g_signal_side = 0; // +1 LONG, -1 SHORT, 0 = NÖTR / geçerli sinyal yok
double   g_profit_target_start_equity = 0.0;
bool     g_profit_target_liquidating = false;
datetime g_last_signal_bar_time = 0;
datetime g_last_state_flush = 0;
datetime g_last_low_rebase_log = 0;
string   g_last_action = "Başlatılıyor";
string   g_grid_object_prefix = "";

// --- TradingView Teknik Özet durumu -------------------------------------
bool     g_signal_ready = false;      // ilk başarılı sinyal değerlendirmesi yapıldı mı
double   g_rating_value = 0.0;        // kullanılan grubun puanı (-1 .. +1)
double   g_rating_ma = 0.0;           // hareketli ortalama grubu puanı
double   g_rating_osc = 0.0;          // osilatör grubu puanı
int      g_rating_status = 0;         // -2 GÜÇLÜ SAT .. +2 GÜÇLÜ AL
int      g_rating_ma_votes = 0;       // ortalamaya giren bileşen sayısı
int      g_rating_osc_votes = 0;
datetime g_rating_bar_time = 0;       // puanı hesaplanan mumun açılış zamanı
datetime g_last_rating_calc = 0;      // canlı mod için hesaplama zaman damgası
datetime g_rating_retry_after = 0;    // başarısız hesap sonrası bekleme (her tikte yüklenmeyi önler)
int      g_rating_streak_side = 0;    // onay sayacı: yön
int      g_rating_streak_count = 0;   // onay sayacı: adet
datetime g_rating_streak_bar = 0;    // onay sayacının son işlendiği mum
string   g_rating_component_names[26];
double   g_rating_component_votes[26];

// --- Teknik Özet fiyat/hacim tamponu (artan sıra: [0] = en eski) ---------
datetime g_tv_time[];
double   g_tv_open[];
double   g_tv_high[];
double   g_tv_low[];
double   g_tv_close[];
double   g_tv_volume[];
int      g_tv_bars = 0;

// --- MACD sinyal girişleri durumu ------------------------------------
datetime g_macd_last_bar = 0;     // sinyali değerlendirilen son kapanmış mum
datetime g_macd_bar_time = 0;     // son güçlü sinyalin mumu
double   g_macd_line = 0.0;       // son kapanmış mumdaki MACD değeri
double   g_macd_signal = 0.0;     // son kapanmış mumdaki sinyal değeri
int      g_macd_side = 0;         // son kapanmış mumdaki güçlü sinyal yönü (+1/-1/0)
int      g_macd_entry_seq = 0;    // MACD girişlerine benzersiz çizgi kodu üretir

//+------------------------------------------------------------------+
//| Basic market and numeric helpers                                 |
//+------------------------------------------------------------------+
string SideName(const int side)
  {
   if(side > 0)
      return "LONG";
   if(side < 0)
      return "SHORT";
   return "BEKLENİYOR";
  }

string RatingStatusName(const int status)
  {
   switch(status)
     {
      case  2: return "GÜÇLÜ AL";
      case  1: return "AL";
      case -1: return "SAT";
      case -2: return "GÜÇLÜ SAT";
     }
   return "NÖTR";
  }

string SignalModeName()
  {
   switch(InpSignalMode)
     {
      case SIGNAL_TECHNICAL_SUMMARY: return "Teknik Özet";
      case SIGNAL_HEIKEN_ASHI:       return "Heiken Ashi";
      case SIGNAL_STANDARD_CANDLE:   return "normal mum";
     }
   return "Teknik Özet";
  }

string RatingGroupName()
  {
   switch(InpRatingGroup)
     {
      case RATING_MOVING_AVERAGES: return "Ortalamalar";
      case RATING_OSCILLATORS:     return "Osilatörler";
     }
   return "Özet (Ort.+Osc.)";
  }

int TradeSideForSignal(const int signal_side)
  {
   if(signal_side == 0)
      return 0;
   return (InpReverseTradeDirection ? -signal_side : signal_side);
  }

int SideFromPositionType(const long type)
  {
   if(type == POSITION_TYPE_BUY)
      return 1;
   if(type == POSITION_TYPE_SELL)
      return -1;
   return 0;
  }

double TickSize()
  {
   double size = SymbolInfoDouble(_Symbol,SYMBOL_TRADE_TICK_SIZE);
   if(size <= 0.0)
      size = _Point;
   return size;
  }

double PipSize()
  {
   if(_Digits == 3 || _Digits == 5)
      return _Point * 10.0;
   return _Point;
  }

double CrossTolerance()
  {
   return MathMax(TickSize() * 0.05,_Point * 0.01);
  }

double MidPrice(const MqlTick &tick)
  {
   if(tick.last > 0.0)
      return tick.last;
   if(tick.bid > 0.0 && tick.ask > 0.0)
      return (tick.bid + tick.ask) * 0.5;
   if(tick.bid > 0.0)
      return tick.bid;
   return tick.ask;
  }

double NormalizePriceToTick(const double price,const int round_direction)
  {
   // round_direction: +1 ceil, -1 floor, 0 nearest
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

int ComparePriceToLevel(const double price,const double level)
  {
   double eps = CrossTolerance();
   if(price > level + eps)
      return 1;
   if(price < level - eps)
      return -1;
   return 0;
  }

string RunModeTag()
  {
   return (MQLInfoInteger(MQL_TESTER) ? "T" : "L");
  }

uint HashText(const string text)
  {
   uint hash = 2166136261;
   for(int i=0; i<StringLen(text); i++)
     {
      hash ^= (uint)StringGetCharacter(text,i);
      hash *= 16777619;
     }
   return hash;
  }

uint HashSymbol(const string symbol)
  {
   return HashText(symbol);
  }

string InstanceStatePrefix()
  {
   string seed = StringFormat("%I64d_%I64u_%s_%s",
                              AccountInfoInteger(ACCOUNT_LOGIN),InpMagicNumber,_Symbol,RunModeTag());
   // Short key keeps position-state global variables under MT5's 63-character limit.
   return "M1G_" + StringFormat("%I64u",(ulong)HashText(seed));
  }

string GridStateKey(const string field)
  {
   return InstanceStatePrefix() + "_" + field;
  }

void SaveProfitTargetState()
  {
   if(MQLInfoInteger(MQL_TESTER))
      return; // Each tester pass starts from its own initial deposit/equity.
   GlobalVariableSet(GridStateKey("PTBASE"),g_profit_target_start_equity);
   GlobalVariableSet(GridStateKey("PTAMT"),InpCloseAllAtEquityGain);
   GlobalVariableSet(GridStateKey("PTLIQ"),(g_profit_target_liquidating ? 1.0 : 0.0));
   GlobalVariableSet(GridStateKey("PTLOW"),(InpEquityTargetRebaseOnLow ? 1.0 : 0.0));
   GlobalVariablesFlush();
  }

void LoadProfitTargetState()
  {
   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(current_equity <= 0.0)
      current_equity = AccountInfoDouble(ACCOUNT_BALANCE);

   if(MQLInfoInteger(MQL_TESTER))
     {
      g_profit_target_start_equity = current_equity;
      g_profit_target_liquidating = false;
      return;
     }

   string base_key = GridStateKey("PTBASE");
   string amount_key = GridStateKey("PTAMT");
   string liquidating_key = GridStateKey("PTLIQ");
   string low_key = GridStateKey("PTLOW");
   bool state_exists = (GlobalVariableCheck(base_key) &&
                        GlobalVariableCheck(amount_key) &&
                        GlobalVariableCheck(liquidating_key) &&
                        GlobalVariableCheck(low_key));
   if(state_exists)
     {
      double saved_amount = GlobalVariableGet(amount_key);
      bool saved_low_mode = (GlobalVariableGet(low_key) > 0.5);
      double amount_tolerance = MathMax(1.0e-8,MathAbs(InpCloseAllAtEquityGain) * 1.0e-8);
      if(GlobalVariableGet(base_key) > 0.0 &&
         MathAbs(saved_amount - InpCloseAllAtEquityGain) <= amount_tolerance &&
         saved_low_mode == InpEquityTargetRebaseOnLow)
        {
         g_profit_target_start_equity = GlobalVariableGet(base_key);
         g_profit_target_liquidating = (GlobalVariableGet(liquidating_key) > 0.5);
         return;
        }
     }

   // First run or changed target amount: start a fresh equity cycle.
   g_profit_target_start_equity = current_equity;
   g_profit_target_liquidating = false;
   SaveProfitTargetState();
  }

string PositionStateKey(const ulong position_id,const string field)
  {
   return InstanceStatePrefix() + "_" + StringFormat("%I64u",position_id) + "_" + field;
  }

string GridObjectName(const bool is_up,const int index)
  {
   return g_grid_object_prefix + (is_up ? "U_" : "D_") + IntegerToString(index);
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

//+------------------------------------------------------------------+
//| Automatic one-time volatility sizing (signal timeframe)          |
//+------------------------------------------------------------------+
bool CalculateInitialGridStep(double &step_out,double &median_range_out,double &floor_out)
  {
   step_out = 0.0;
   median_range_out = 0.0;
   floor_out = 0.0;

   int lookback = InpGridRangeLookbackBars;
   if(lookback < 1)
      return false;

   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   int copied = CopyRates(_Symbol,InpSignalTimeframe,0,lookback + 1,rates);
   if(copied < lookback + 1)
      return false; // Need the requested number of completed candles plus the live one.

   double ranges[];
   if(ArrayResize(ranges,lookback) < lookback)
      return false;
   for(int i=0; i<lookback; i++)
     {
      int shift = i + 1; // shift 0 is the forming candle; do not use it.
      ranges[i] = MathMax(0.0,rates[shift].high - rates[shift].low);
     }

   // Insertion sort; the default sample is small (20 bars).
   for(int i=1; i<lookback; i++)
     {
      double value = ranges[i];
      int j = i - 1;
      while(j >= 0 && ranges[j] > value)
        {
         ranges[j + 1] = ranges[j];
         j--;
        }
      ranges[j + 1] = value;
     }

   if((lookback % 2) == 1)
      median_range_out = ranges[lookback / 2];
   else
      median_range_out = (ranges[lookback / 2 - 1] + ranges[lookback / 2]) * 0.5;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return false;
   double spread = MathMax(0.0,tick.ask - tick.bid);
   double raw_step = median_range_out * InpGridStepMultiplier;

   double min_step = TickSize();
   if(spread > 0.0 && InpMinSpreadMultiple > 0.0)
      min_step = MathMax(min_step,spread * InpMinSpreadMultiple);

   long stop_level = (long)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_STOPS_LEVEL);
   long freeze_level = (long)SymbolInfoInteger(_Symbol,SYMBOL_TRADE_FREEZE_LEVEL);
   long broker_distance_points = stop_level;
   if(freeze_level > broker_distance_points)
      broker_distance_points = freeze_level;
   if(InpTakeProfitGrids > 0 && broker_distance_points > 0)
     {
      double tp_min_step = ((double)broker_distance_points * _Point + TickSize()) / (double)InpTakeProfitGrids;
      min_step = MathMax(min_step,tp_min_step);
     }

   step_out = MathMax(raw_step,min_step);
   double tick_size = TickSize();
   if(tick_size > 0.0)
      step_out = MathCeil(step_out / tick_size - 1.0e-10) * tick_size;
   step_out = NormalizeDouble(step_out,_Digits);
   floor_out = min_step;
   return (step_out > 0.0 && MathIsValidNumber(step_out));
  }

bool LoadOrCreateGrid(const double current_price)
  {
   string base_key = GridStateKey("BASE");
   string step_key = GridStateKey("STEP");
   bool can_load = (!InpResetGridOnInit && !MQLInfoInteger(MQL_TESTER) &&
                    GlobalVariableCheck(base_key) && GlobalVariableCheck(step_key));

   if(can_load)
     {
      g_grid_base = GlobalVariableGet(base_key);
      g_grid_step = GlobalVariableGet(step_key);
      if(g_grid_base > 0.0 && g_grid_step > 0.0)
        {
         g_last_action = "Önceki grid geri yüklendi";
         PrintFormat("Saved grid restored: base=%.*f step=%.*f",_Digits,g_grid_base,_Digits,g_grid_step);
         return true;
        }
     }

   double median_range = 0.0;
   double min_step = 0.0;
   double calculated_step = 0.0;
   if(!CalculateInitialGridStep(calculated_step,median_range,min_step))
     {
      PrintFormat("Grid adımı hesaplanamadı: %s üzerinde son %d kapanmış mumun terminalde yüklü olduğundan emin olun.",
                  EnumToString(InpSignalTimeframe),InpGridRangeLookbackBars);
      return false;
     }
   if(calculated_step * InpStopLossGrids >= current_price * 0.90)
     {
      Print("Grid adımı mevcut fiyata göre aşırı büyük; güvenlik nedeniyle EA başlatılmadı.");
      return false;
     }

   g_grid_base = NormalizePriceToTick(current_price,0);
   g_grid_step = calculated_step;
   GlobalVariableSet(base_key,g_grid_base);
   GlobalVariableSet(step_key,g_grid_step);
   GlobalVariablesFlush();

   PrintFormat("Yeni grid oluşturuldu: base=%.*f medyan %s aralığı=%.*f çarpan=%.2f alt sınır=%.*f adım=%.*f (%.1f point)",
               _Digits,g_grid_base,EnumToString(InpSignalTimeframe),_Digits,median_range,InpGridStepMultiplier,
               _Digits,min_step,_Digits,g_grid_step,g_grid_step / _Point);
   g_last_action = "Başlangıç grid'i hesaplandı";
   return true;
  }

//+------------------------------------------------------------------+
//| Optional visible grid levels                                      |
//+------------------------------------------------------------------+
color CurrentGridColor()
  {
   if(g_signal_side > 0)
      return clrLimeGreen;
   if(g_signal_side < 0)
      return clrTomato;
   return clrDarkGray;
  }

void SetHorizontalLine(const string name,const double price,const color line_color,
                       const ENUM_LINE_STYLE style,const int width)
  {
   if(ObjectFind(0,name) < 0)
     {
      if(!ObjectCreate(0,name,OBJ_HLINE,0,0,price))
         return;
     }
   ObjectSetDouble(0,name,OBJPROP_PRICE,price);
   ObjectSetInteger(0,name,OBJPROP_COLOR,line_color);
   ObjectSetInteger(0,name,OBJPROP_STYLE,style);
   ObjectSetInteger(0,name,OBJPROP_WIDTH,width);
   ObjectSetInteger(0,name,OBJPROP_BACK,true);
   ObjectSetInteger(0,name,OBJPROP_SELECTABLE,false);
   ObjectSetInteger(0,name,OBJPROP_HIDDEN,true);
  }

void DrawGridLine(const bool is_up,const int index)
  {
   if(!InpDrawGridLevels || index < 1)
      return;
   double price = (is_up ? g_grid_base + g_grid_step * index : g_grid_base - g_grid_step * index);
   if(price <= 0.0)
      return;
   SetHorizontalLine(GridObjectName(is_up,index),price,CurrentGridColor(),STYLE_DOT,1);
  }

void DrawBaseLine()
  {
   if(!InpDrawGridLevels || g_grid_base <= 0.0)
      return;
   SetHorizontalLine(g_grid_object_prefix + "BASE",g_grid_base,clrSilver,STYLE_DASH,1);
  }

void RecolorGridLines()
  {
   if(!InpDrawGridLevels)
      return;
   DrawBaseLine();
   for(int i=1; i<=g_up_count; i++)
      DrawGridLine(true,i);
   for(int i=1; i<=g_down_count; i++)
      DrawGridLine(false,i);
   ChartRedraw(0);
  }

void DeleteOwnGridObjects()
  {
   if(g_grid_object_prefix == "")
      return;
   int total = ObjectsTotal(0,-1,-1);
   for(int i=total - 1; i>=0; i--)
     {
      string name = ObjectName(0,i,-1,-1);
      if(StringFind(name,g_grid_object_prefix) == 0)
         ObjectDelete(0,name);
     }
  }

//+------------------------------------------------------------------+
//| Fixed grid coordinates and crossing state                        |
//+------------------------------------------------------------------+
double GridLevelPrice(const bool is_up,const int index)
  {
   if(is_up)
      return g_grid_base + g_grid_step * index;
   return g_grid_base - g_grid_step * index;
  }

bool InitializeGridState(const double current_price)
  {
   g_up_count = InpInitialGridLevels;
   g_down_count = InpInitialGridLevels;
   if(ArrayResize(g_up_state,g_up_count + 1) < g_up_count + 1 ||
      ArrayResize(g_down_state,g_down_count + 1) < g_down_count + 1)
      return false;
   ArrayInitialize(g_up_state,0);
   ArrayInitialize(g_down_state,0);

   // Seed existing levels relative to the current price to avoid false startup crosses.
   for(int i=1; i<=g_up_count; i++)
     {
      g_up_state[i] = ComparePriceToLevel(current_price,GridLevelPrice(true,i));
      DrawGridLine(true,i);
     }
   for(int i=1; i<=g_down_count; i++)
     {
      g_down_state[i] = ComparePriceToLevel(current_price,GridLevelPrice(false,i));
      DrawGridLine(false,i);
     }
   DrawBaseLine();
   return true;
  }

void ExpandGrid(const double price)
  {
   if(g_grid_step <= 0.0)
      return;
   int guard = 0;
   double upper_limit = price + g_grid_step;
   while(g_up_count < InpMaxGridLevels && guard < 10000)
     {
      guard++;
      int next_index = g_up_count + 1;
      if(GridLevelPrice(true,next_index) <= upper_limit)
        {
         if(ArrayResize(g_up_state,next_index + 1) < next_index + 1)
            break;
         g_up_count = next_index;
         g_up_state[next_index] = 0; // New line arms on this observation; it does not fire immediately.
         DrawGridLine(true,next_index);
        }
      else
         break;
     }

   guard = 0;
   double lower_limit = price - g_grid_step;
   while(g_down_count < InpMaxGridLevels && guard < 10000)
     {
      guard++;
      int next_index = g_down_count + 1;
      if(GridLevelPrice(false,next_index) >= lower_limit)
        {
         if(ArrayResize(g_down_state,next_index + 1) < next_index + 1)
            break;
         g_down_count = next_index;
         g_down_state[next_index] = 0;
         DrawGridLine(false,next_index);
        }
      else
         break;
     }
  }

//+------------------------------------------------------------------+
//| Yön değişince grid'i anlık fiyattan yeniden kur                  |
//| Base anlık fiyata çekilir, adım taze oynaklıktan yeniden         |
//| hesaplanır (hesaplanamazsa mevcut adım korunur), çizgiler ve     |
//| geçiş hafızası sıfırdan kurulur.                                 |
//+------------------------------------------------------------------+
bool RebaseGridAtCurrentPrice(const string reason)
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return false;
   double price = MidPrice(tick);
   if(price <= 0.0)
      return false;

   double recalculated_step = 0.0;
   double median_range = 0.0;
   double min_step = 0.0;
   if(CalculateInitialGridStep(recalculated_step,median_range,min_step) && recalculated_step > 0.0 &&
      recalculated_step * InpStopLossGrids < price * 0.90)
      g_grid_step = recalculated_step;

   g_grid_base = NormalizePriceToTick(price,0);
   GlobalVariableSet(GridStateKey("BASE"),g_grid_base);
   GlobalVariableSet(GridStateKey("STEP"),g_grid_step);
   GlobalVariablesFlush();

   DeleteOwnGridObjects();
   InitializeGridState(price); // yeni base/adım + taze geçiş hafızası + çizgiler
   RecolorGridLines();

   g_last_action = StringFormat("Grid yeniden kuruldu (%s)",reason);
   PrintFormat("Grid yeniden kuruldu: base=%.*f step=%.*f (%.1f point) neden=%s",
               _Digits,g_grid_base,_Digits,g_grid_step,g_grid_step / _Point,reason);
   return true;
  }

//+------------------------------------------------------------------+
//| TradingView "Teknik Özet" (Technical Ratings) motoru             |
//|                                                                  |
//| TradingView TechnicalRating kütüphanesindeki calcRatingAll() ve  |
//| ratingStatus() fonksiyonlarının birebir MQL5 karşılığıdır:       |
//| 15 ortalama/bulut filtresi + 11 osilatör = 26 bileşen. Her       |
//| bileşen +1 (AL), 0 (NÖTR) veya -1 (SAT) oy verir. Grup puanı     |
//| oyların ortalaması, "Özet" puanı iki grubun ortalamasıdır ve     |
//| -1 .. +1 arasında salınır. Verisi olmayan (Pine: na) bileşen     |
//| ortalamaya hiç dahil edilmez.                                    |
//|   puan > +0.5 -> GÜÇLÜ AL      puan > +0.1 -> AL                 |
//|   -0.1 <= puan <= +0.1 -> NÖTR                                   |
//|   puan < -0.1 -> SAT           puan < -0.5 -> GÜÇLÜ SAT          |
//+------------------------------------------------------------------+
#define TV_EPSILON 1.0e-10
#define TV_MIN_BARS 350

bool TvIsNa(const double value)
  {
   if(!MathIsValidNumber(value))
      return true;
   return (value >= DBL_MAX * 0.5 || value <= -DBL_MAX * 0.5);
  }

// Pine float karşılaştırmaları: a > b ancak (a - b) > 1e-10 ise; na her zaman false.
bool TvGt(const double a,const double b)
  {
   if(TvIsNa(a) || TvIsNa(b))
      return false;
   return (a - b > TV_EPSILON);
  }

bool TvLt(const double a,const double b)
  {
   if(TvIsNa(a) || TvIsNa(b))
      return false;
   return (b - a > TV_EPSILON);
  }

bool TvLe(const double a,const double b)
  {
   if(TvIsNa(a) || TvIsNa(b))
      return false;
   return !(a - b > TV_EPSILON);
  }

void TvAlloc(double &out[],const int size)
  {
   if(size < 1)
     {
      ArrayResize(out,0);
      return;
     }
   if(ArrayResize(out,size) < size)
      return;
   ArrayInitialize(out,EMPTY_VALUE);
  }

// ta.sma: penceredeki tüm değerler geçerliyse ortalama, değilse na.
void TvSma(const double &src[],const int len,double &out[])
  {
   int n = ArraySize(src);
   TvAlloc(out,n);
   if(len < 1 || n < len)
      return;
   double running = 0.0;
   int na_count = 0;
   for(int i=0; i<n; i++)
     {
      if(TvIsNa(src[i]))
         na_count++;
      else
         running += src[i];
      if(i >= len)
        {
         int drop = i - len;
         if(TvIsNa(src[drop]))
            na_count--;
         else
            running -= src[drop];
        }
      if(i >= len - 1 && na_count == 0)
         out[i] = running / (double)len;
     }
  }

// math.sum: pencerede na varsa sonuç na.
void TvSum(const double &src[],const int len,double &out[])
  {
   int n = ArraySize(src);
   TvAlloc(out,n);
   if(len < 1 || n < len)
      return;
   double running = 0.0;
   int na_count = 0;
   for(int i=0; i<n; i++)
     {
      if(TvIsNa(src[i]))
         na_count++;
      else
         running += src[i];
      if(i >= len)
        {
         int drop = i - len;
         if(TvIsNa(src[drop]))
            na_count--;
         else
            running -= src[drop];
        }
      if(i >= len - 1 && na_count == 0)
         out[i] = running;
     }
  }

// ta.ema: ilk geçerli değer SMA ile tohumlanır, sonra alpha = 2/(len+1) ile yürür.
void TvEma(const double &src[],const int len,double &out[])
  {
   int n = ArraySize(src);
   TvAlloc(out,n);
   if(len < 1 || n < len)
      return;
   double alpha = 2.0 / ((double)len + 1.0);
   double running = 0.0;
   int na_count = 0;
   bool seeded = false;
   double previous = 0.0;
   for(int i=0; i<n; i++)
     {
      if(TvIsNa(src[i]))
         na_count++;
      else
         running += src[i];
      if(i >= len)
        {
         int drop = i - len;
         if(TvIsNa(src[drop]))
            na_count--;
         else
            running -= src[drop];
        }
      if(!seeded)
        {
         if(i >= len - 1 && na_count == 0)
           {
            previous = running / (double)len;
            out[i] = previous;
            seeded = true;
           }
         continue;
        }
      if(TvIsNa(src[i]))
         continue;
      previous = alpha * src[i] + (1.0 - alpha) * previous;
      out[i] = previous;
     }
  }

// ta.rma (Wilder): alpha = 1/len, SMA tohumlu.
void TvRma(const double &src[],const int len,double &out[])
  {
   int n = ArraySize(src);
   TvAlloc(out,n);
   if(len < 1 || n < len)
      return;
   double alpha = 1.0 / (double)len;
   double running = 0.0;
   int na_count = 0;
   bool seeded = false;
   double previous = 0.0;
   for(int i=0; i<n; i++)
     {
      if(TvIsNa(src[i]))
         na_count++;
      else
         running += src[i];
      if(i >= len)
        {
         int drop = i - len;
         if(TvIsNa(src[drop]))
            na_count--;
         else
            running -= src[drop];
        }
      if(!seeded)
        {
         if(i >= len - 1 && na_count == 0)
           {
            previous = running / (double)len;
            out[i] = previous;
            seeded = true;
           }
         continue;
        }
      if(TvIsNa(src[i]))
         continue;
      previous = alpha * src[i] + (1.0 - alpha) * previous;
      out[i] = previous;
     }
  }

// ta.wma: ağırlıklar len, len-1, ... 1.
void TvWma(const double &src[],const int len,double &out[])
  {
   int n = ArraySize(src);
   TvAlloc(out,n);
   if(len < 1 || n < len)
      return;
   double denominator = (double)len * ((double)len + 1.0) * 0.5;
   for(int i=len - 1; i<n; i++)
     {
      double sum = 0.0;
      bool complete = true;
      for(int j=0; j<len; j++)
        {
         double value = src[i - j];
         if(TvIsNa(value))
           {
            complete = false;
            break;
           }
         sum += value * (double)(len - j);
        }
      if(complete)
         out[i] = sum / denominator;
     }
  }

// ta.hma(len) = wma(2*wma(src, len/2) - wma(src, len), round(sqrt(len)))
void TvHma(const double &src[],const int len,double &out[])
  {
   int half = len / 2;
   if(half < 1)
      half = 1;
   int root = (int)MathRound(MathSqrt((double)len));
   if(root < 1)
      root = 1;
   double fast[];
   double slow[];
   double diff[];
   TvWma(src,half,fast);
   TvWma(src,len,slow);
   int n = ArraySize(src);
   TvAlloc(diff,n);
   for(int i=0; i<n; i++)
     {
      if(TvIsNa(fast[i]) || TvIsNa(slow[i]))
         continue;
      diff[i] = 2.0 * fast[i] - slow[i];
     }
   TvWma(diff,root,out);
  }

// ta.vwma(len) = sum(src*volume, len) / sum(volume, len); hacim yoksa na.
void TvVwma(const double &src[],const double &vol[],const int len,double &out[])
  {
   int n = ArraySize(src);
   TvAlloc(out,n);
   if(len < 1 || n < len || ArraySize(vol) != n)
      return;
   double price_volume[];
   TvAlloc(price_volume,n);
   for(int i=0; i<n; i++)
     {
      if(TvIsNa(src[i]) || TvIsNa(vol[i]))
         continue;
      price_volume[i] = src[i] * vol[i];
     }
   double sum_pv[];
   double sum_vol[];
   TvSum(price_volume,len,sum_pv);
   TvSum(vol,len,sum_vol);
   for(int i=len - 1; i<n; i++)
     {
      if(TvIsNa(sum_pv[i]) || TvIsNa(sum_vol[i]))
         continue;
      if(sum_vol[i] <= 0.0)
         continue;
      out[i] = sum_pv[i] / sum_vol[i];
     }
  }

void TvHighest(const double &src[],const int len,double &out[])
  {
   int n = ArraySize(src);
   TvAlloc(out,n);
   if(len < 1 || n < len)
      return;
   for(int i=len - 1; i<n; i++)
     {
      double best = EMPTY_VALUE;
      bool complete = true;
      for(int j=0; j<len; j++)
        {
         double value = src[i - j];
         if(TvIsNa(value))
           {
            complete = false;
            break;
           }
         if(TvIsNa(best) || value > best)
            best = value;
        }
      if(complete)
         out[i] = best;
     }
  }

void TvLowest(const double &src[],const int len,double &out[])
  {
   int n = ArraySize(src);
   TvAlloc(out,n);
   if(len < 1 || n < len)
      return;
   for(int i=len - 1; i<n; i++)
     {
      double best = EMPTY_VALUE;
      bool complete = true;
      for(int j=0; j<len; j++)
        {
         double value = src[i - j];
         if(TvIsNa(value))
           {
            complete = false;
            break;
           }
         if(TvIsNa(best) || value < best)
            best = value;
        }
      if(complete)
         out[i] = best;
     }
  }

// ta.dev: kendi SMA'ine göre ortalama mutlak sapma.
void TvDev(const double &src[],const int len,double &out[])
  {
   int n = ArraySize(src);
   TvAlloc(out,n);
   if(len < 1 || n < len)
      return;
   double ma[];
   TvSma(src,len,ma);
   for(int i=len - 1; i<n; i++)
     {
      if(TvIsNa(ma[i]))
         continue;
      double sum = 0.0;
      bool complete = true;
      for(int j=0; j<len; j++)
        {
         double value = src[i - j];
         if(TvIsNa(value))
           {
            complete = false;
            break;
           }
         sum += MathAbs(value - ma[i]);
        }
      if(complete)
         out[i] = sum / (double)len;
     }
  }

// ta.rsi: 100 * rma(kazanç) / (rma(kazanç) + rma(kayıp))
void TvRsi(const double &src[],const int len,double &out[])
  {
   int n = ArraySize(src);
   TvAlloc(out,n);
   if(len < 1 || n < len + 1)
      return;
   double gain[];
   double loss[];
   TvAlloc(gain,n);
   TvAlloc(loss,n);
   for(int i=1; i<n; i++)
     {
      if(TvIsNa(src[i]) || TvIsNa(src[i - 1]))
         continue;
      double change = src[i] - src[i - 1];
      gain[i] = (change > 0.0 ? change : 0.0);
      loss[i] = (change < 0.0 ? -change : 0.0);
     }
   double up[];
   double down[];
   TvRma(gain,len,up);
   TvRma(loss,len,down);
   for(int i=0; i<n; i++)
     {
      if(TvIsNa(up[i]) || TvIsNa(down[i]))
         continue;
      double denominator = up[i] + down[i];
      if(denominator <= 0.0)
         continue;
      out[i] = 100.0 * up[i] / denominator;
     }
  }

// ta.stoch(src, high, low, len) = 100 * (src - lowest(low,len)) / (highest(high,len) - lowest(low,len))
void TvStoch(const double &src[],const double &high[],const double &low[],const int len,double &out[])
  {
   int n = ArraySize(src);
   TvAlloc(out,n);
   if(len < 1 || n < len || ArraySize(high) != n || ArraySize(low) != n)
      return;
   double highest[];
   double lowest[];
   TvHighest(high,len,highest);
   TvLowest(low,len,lowest);
   for(int i=len - 1; i<n; i++)
     {
      if(TvIsNa(src[i]) || TvIsNa(highest[i]) || TvIsNa(lowest[i]))
         continue;
      double range = highest[i] - lowest[i];
      if(range <= 0.0)
         continue;
      out[i] = 100.0 * (src[i] - lowest[i]) / range;
     }
  }

// Williams %R = -100 * (highest(high,len) - close) / (highest(high,len) - lowest(low,len))
void TvWilliamsR(const int len,double &out[])
  {
   int n = g_tv_bars;
   TvAlloc(out,n);
   if(len < 1 || n < len)
      return;
   double highest[];
   double lowest[];
   TvHighest(g_tv_high,len,highest);
   TvLowest(g_tv_low,len,lowest);
   for(int i=len - 1; i<n; i++)
     {
      if(TvIsNa(highest[i]) || TvIsNa(lowest[i]))
         continue;
      double range = highest[i] - lowest[i];
      if(range <= 0.0)
         continue;
      out[i] = -100.0 * (highest[i] - g_tv_close[i]) / range;
     }
  }

//+------------------------------------------------------------------+
//| Geçmiş veri: seçilen zaman diliminin mumları (artan sıra)        |
//+------------------------------------------------------------------+
bool TvLoadHistory(const int requested_bars)
  {
   int want = requested_bars;
   if(want < TV_MIN_BARS)
      want = TV_MIN_BARS;

   MqlRates rates[];
   ArraySetAsSeries(rates,false); // [0] = en eski mum
   int copied = CopyRates(_Symbol,InpSignalTimeframe,0,want,rates);
   if(copied < TV_MIN_BARS)
     {
      static datetime last_warning = 0;
      datetime now = TimeCurrent();
      if(last_warning == 0 || now - last_warning >= 60)
        {
         last_warning = now;
         PrintFormat("Teknik özet için yeterli mum yok: %s %s üzerinde %d mum gerekiyor, %d bulunabildi.",
                     _Symbol,EnumToString(InpSignalTimeframe),TV_MIN_BARS,copied);
        }
      return false;
     }

   g_tv_bars = copied;
   ArrayResize(g_tv_time,copied);
   ArrayResize(g_tv_open,copied);
   ArrayResize(g_tv_high,copied);
   ArrayResize(g_tv_low,copied);
   ArrayResize(g_tv_close,copied);
   ArrayResize(g_tv_volume,copied);
   for(int i=0; i<copied; i++)
     {
      g_tv_time[i] = rates[i].time;
      g_tv_open[i] = rates[i].open;
      g_tv_high[i] = rates[i].high;
      g_tv_low[i] = rates[i].low;
      g_tv_close[i] = rates[i].close;
      g_tv_volume[i] = (InpRatingVolumeSource == RATING_VOLUME_REAL
                        ? (double)rates[i].real_volume
                        : (double)rates[i].tick_volume);
     }
   return true;
  }

void TvInitComponentNames()
  {
   g_rating_component_names[0]  = "SMA10";
   g_rating_component_names[1]  = "SMA20";
   g_rating_component_names[2]  = "SMA30";
   g_rating_component_names[3]  = "SMA50";
   g_rating_component_names[4]  = "SMA100";
   g_rating_component_names[5]  = "SMA200";
   g_rating_component_names[6]  = "EMA10";
   g_rating_component_names[7]  = "EMA20";
   g_rating_component_names[8]  = "EMA30";
   g_rating_component_names[9]  = "EMA50";
   g_rating_component_names[10] = "EMA100";
   g_rating_component_names[11] = "EMA200";
   g_rating_component_names[12] = "HMA9";
   g_rating_component_names[13] = "VWMA20";
   g_rating_component_names[14] = "Ichimoku(9,26,52)";
   g_rating_component_names[15] = "RSI14";
   g_rating_component_names[16] = "Stoch(14,3,3)";
   g_rating_component_names[17] = "CCI20";
   g_rating_component_names[18] = "ADX(14,14)";
   g_rating_component_names[19] = "AwesomeOsc";
   g_rating_component_names[20] = "Momentum10";
   g_rating_component_names[21] = "MACD(12,26,9)";
   g_rating_component_names[22] = "StochRSI(14,14,3,3)";
   g_rating_component_names[23] = "WilliamsR14";
   g_rating_component_names[24] = "BullBearPower13";
   g_rating_component_names[25] = "UO(7,14,28)";
   ArrayInitialize(g_rating_component_votes,EMPTY_VALUE);
  }

void TvVoteMovingAverage(const double price,const double ma,double &vote_sum,int &vote_count,const int slot)
  {
   double vote = EMPTY_VALUE;
   if(!TvIsNa(price) && !TvIsNa(ma))
     {
      double difference = price - ma;
      // math.sign(close - ma); fiyat ile ortalama arasındaki fark yalnız yuvarlama
      // gürültüsü kadarsa (ör. dümdüz bir trend) oy NÖTR sayılır.
      double tolerance = MathMax(MathAbs(price),MathAbs(ma)) * TV_EPSILON;
      if(MathAbs(difference) <= tolerance)
         vote = 0.0;
      else
         vote = (difference > 0.0 ? 1.0 : -1.0);
     }
   g_rating_component_votes[slot] = vote;
   if(TvIsNa(vote))
      return;
   vote_sum += vote;
   vote_count++;
  }

void TvVoteOscillator(const double gate,const bool bull,const bool bear,double &vote_sum,int &vote_count,const int slot)
  {
   double vote = EMPTY_VALUE;
   if(!TvIsNa(gate))
      vote = (bull ? 1.0 : (bear ? -1.0 : 0.0));
   g_rating_component_votes[slot] = vote;
   if(TvIsNa(vote))
      return;
   vote_sum += vote;
   vote_count++;
  }

//+------------------------------------------------------------------+
//| calcRatingAll(): 26 bileşenin oyları ve iki grubun ortalaması    |
//+------------------------------------------------------------------+
bool TvComputeRatings(const int idx,double &ma_rating,double &osc_rating,double &total_rating)
  {
   ma_rating = EMPTY_VALUE;
   osc_rating = EMPTY_VALUE;
   total_rating = EMPTY_VALUE;
   ArrayInitialize(g_rating_component_votes,EMPTY_VALUE);

   int n = g_tv_bars;
   if(n < TV_MIN_BARS || idx < 1 || idx >= n)
      return false;

   double close_price = g_tv_close[idx];
   if(TvIsNa(close_price))
      return false;

   // --- hazırlık serileri
   double hl2[];
   ArrayResize(hl2,n);
   for(int i=0; i<n; i++)
      hl2[i] = (g_tv_high[i] + g_tv_low[i]) * 0.5;

   // --- MA grubu (15 bileşen)
   double sma10[];
   double sma20[];
   double sma30[];
   double sma50[];
   double sma100[];
   double sma200[];
   TvSma(g_tv_close,10,sma10);
   TvSma(g_tv_close,20,sma20);
   TvSma(g_tv_close,30,sma30);
   TvSma(g_tv_close,50,sma50);
   TvSma(g_tv_close,100,sma100);
   TvSma(g_tv_close,200,sma200);

   double ema10[];
   double ema20[];
   double ema30[];
   double ema50[];
   double ema100[];
   double ema200[];
   TvEma(g_tv_close,10,ema10);
   TvEma(g_tv_close,20,ema20);
   TvEma(g_tv_close,30,ema30);
   TvEma(g_tv_close,50,ema50);
   TvEma(g_tv_close,100,ema100);
   TvEma(g_tv_close,200,ema200);

   double hma9[];
   double vwma20[];
   TvHma(g_tv_close,9,hma9);
   TvVwma(g_tv_close,g_tv_volume,20,vwma20);

   // Ichimoku (9/26/52) — lead1 ve lead2 26 bar geriye kaydırılmış okunur.
   double hh9[];
   double ll9[];
   double hh26[];
   double ll26[];
   double hh52[];
   double ll52[];
   TvHighest(g_tv_high,9,hh9);
   TvLowest(g_tv_low,9,ll9);
   TvHighest(g_tv_high,26,hh26);
   TvLowest(g_tv_low,26,ll26);
   TvHighest(g_tv_high,52,hh52);
   TvLowest(g_tv_low,52,ll52);
   double conversion[];
   double base_line[];
   double lead1[];
   double lead2[];
   TvAlloc(conversion,n);
   TvAlloc(base_line,n);
   TvAlloc(lead1,n);
   TvAlloc(lead2,n);
   for(int i=0; i<n; i++)
     {
      if(!TvIsNa(hh9[i]) && !TvIsNa(ll9[i]))
         conversion[i] = (hh9[i] + ll9[i]) * 0.5;
      if(!TvIsNa(hh26[i]) && !TvIsNa(ll26[i]))
         base_line[i] = (hh26[i] + ll26[i]) * 0.5;
      if(!TvIsNa(conversion[i]) && !TvIsNa(base_line[i]))
         lead1[i] = (conversion[i] + base_line[i]) * 0.5;
      if(!TvIsNa(hh52[i]) && !TvIsNa(ll52[i]))
         lead2[i] = (hh52[i] + ll52[i]) * 0.5;
     }
   int displaced = idx - 26;
   double lead1_now = (displaced >= 0 ? lead1[displaced] : EMPTY_VALUE);
   double lead2_now = (displaced >= 0 ? lead2[displaced] : EMPTY_VALUE);

   double ma_sum = 0.0;
   int ma_count = 0;
   TvVoteMovingAverage(close_price,sma10[idx],ma_sum,ma_count,0);
   TvVoteMovingAverage(close_price,sma20[idx],ma_sum,ma_count,1);
   TvVoteMovingAverage(close_price,sma30[idx],ma_sum,ma_count,2);
   TvVoteMovingAverage(close_price,sma50[idx],ma_sum,ma_count,3);
   TvVoteMovingAverage(close_price,sma100[idx],ma_sum,ma_count,4);
   TvVoteMovingAverage(close_price,sma200[idx],ma_sum,ma_count,5);
   TvVoteMovingAverage(close_price,ema10[idx],ma_sum,ma_count,6);
   TvVoteMovingAverage(close_price,ema20[idx],ma_sum,ma_count,7);
   TvVoteMovingAverage(close_price,ema30[idx],ma_sum,ma_count,8);
   TvVoteMovingAverage(close_price,ema50[idx],ma_sum,ma_count,9);
   TvVoteMovingAverage(close_price,ema100[idx],ma_sum,ma_count,10);
   TvVoteMovingAverage(close_price,ema200[idx],ma_sum,ma_count,11);
   TvVoteMovingAverage(close_price,hma9[idx],ma_sum,ma_count,12);
   TvVoteMovingAverage(close_price,vwma20[idx],ma_sum,ma_count,13);
   bool ichimoku_bull = (TvGt(lead1_now,lead2_now) &&
                         TvGt(base_line[idx],lead1_now) &&
                         TvGt(conversion[idx],base_line[idx]) &&
                         TvGt(close_price,conversion[idx]));
   bool ichimoku_bear = (TvLt(lead1_now,lead2_now) &&
                         TvLt(base_line[idx],lead1_now) &&
                         TvLt(conversion[idx],base_line[idx]) &&
                         TvLt(close_price,conversion[idx]));
   TvVoteOscillator(lead2[idx],ichimoku_bull,ichimoku_bear,ma_sum,ma_count,14);

   // --- Osilatör grubu (11 bileşen)
   double osc_sum = 0.0;
   int osc_count = 0;

   // RSI(14)
   double rsi[];
   TvRsi(g_tv_close,14,rsi);
   double rsi_previous = (idx >= 1 ? rsi[idx - 1] : EMPTY_VALUE);
   TvVoteOscillator(rsi_previous,
                    (TvLt(rsi[idx],30.0) && TvLt(rsi_previous,rsi[idx])),
                    (TvGt(rsi[idx],70.0) && TvGt(rsi_previous,rsi[idx])),
                    osc_sum,osc_count,15);

   // Stochastic(14,3,3)
   double stoch_raw[];
   double k_stoch[];
   double d_stoch[];
   TvStoch(g_tv_close,g_tv_high,g_tv_low,14,stoch_raw);
   TvSma(stoch_raw,3,k_stoch);
   TvSma(k_stoch,3,d_stoch);
   double d_stoch_previous = (idx >= 1 ? d_stoch[idx - 1] : EMPTY_VALUE);
   TvVoteOscillator(d_stoch_previous,
                    (TvLt(k_stoch[idx],20.0) && TvLt(d_stoch[idx],20.0) && TvGt(k_stoch[idx],d_stoch[idx])),
                    (TvGt(k_stoch[idx],80.0) && TvGt(d_stoch[idx],80.0) && TvLt(k_stoch[idx],d_stoch[idx])),
                    osc_sum,osc_count,16);

   // CCI(20) — kaynak: kapanış
   double cci_ma[];
   double cci_dev[];
   double cci[];
   TvSma(g_tv_close,20,cci_ma);
   TvDev(g_tv_close,20,cci_dev);
   TvAlloc(cci,n);
   for(int i=19; i<n; i++)
     {
      if(TvIsNa(cci_ma[i]) || TvIsNa(cci_dev[i]) || cci_dev[i] <= 0.0)
         continue;
      cci[i] = (g_tv_close[i] - cci_ma[i]) / (0.015 * cci_dev[i]);
     }
   double cci_previous = (idx >= 1 ? cci[idx - 1] : EMPTY_VALUE);
   TvVoteOscillator(cci_previous,
                    (TvLt(cci[idx],-100.0) && TvGt(cci[idx],cci_previous)),
                    (TvGt(cci[idx],100.0) && TvLt(cci[idx],cci_previous)),
                    osc_sum,osc_count,17);

   // ADX / +DI / -DI (14,14)
   double true_range[];
   double plus_dm[];
   double minus_dm[];
   TvAlloc(true_range,n);
   TvAlloc(plus_dm,n);
   TvAlloc(minus_dm,n);
   true_range[0] = g_tv_high[0] - g_tv_low[0];
   plus_dm[0] = 0.0;
   minus_dm[0] = 0.0;
   for(int i=1; i<n; i++)
     {
      double previous_close = g_tv_close[i - 1];
      double range_high = MathMax(g_tv_high[i],previous_close);
      double range_low = MathMin(g_tv_low[i],previous_close);
      true_range[i] = MathMax(range_high - range_low,
                              MathMax(MathAbs(g_tv_high[i] - previous_close),
                                      MathAbs(g_tv_low[i] - previous_close)));
      double up_move = g_tv_high[i] - g_tv_high[i - 1];
      double down_move = g_tv_low[i - 1] - g_tv_low[i];
      plus_dm[i] = ((up_move > down_move && up_move > 0.0) ? up_move : 0.0);
      minus_dm[i] = ((down_move > up_move && down_move > 0.0) ? down_move : 0.0);
     }
   double smooth_tr[];
   double plus_rma[];
   double minus_rma[];
   double plus_di[];
   double minus_di[];
   double dx_raw[];
   double adx[];
   TvRma(true_range,14,smooth_tr);
   TvRma(plus_dm,14,plus_rma);
   TvRma(minus_dm,14,minus_rma);
   TvAlloc(plus_di,n);
   TvAlloc(minus_di,n);
   TvAlloc(dx_raw,n);
   for(int i=0; i<n; i++)
     {
      if(TvIsNa(smooth_tr[i]) || smooth_tr[i] <= 0.0)
         continue;
      if(!TvIsNa(plus_rma[i]))
         plus_di[i] = 100.0 * plus_rma[i] / smooth_tr[i];
      if(!TvIsNa(minus_rma[i]))
         minus_di[i] = 100.0 * minus_rma[i] / smooth_tr[i];
      if(TvIsNa(plus_di[i]) || TvIsNa(minus_di[i]))
         continue;
      double di_sum = plus_di[i] + minus_di[i];
      dx_raw[i] = MathAbs(plus_di[i] - minus_di[i]) / (di_sum == 0.0 ? 1.0 : di_sum);
     }
   TvRma(dx_raw,14,adx);
   for(int i=0; i<n; i++)
     {
      if(TvIsNa(adx[i]))
         continue;
      adx[i] = adx[i] * 100.0;
     }
   double adx_previous = (idx >= 1 ? adx[idx - 1] : EMPTY_VALUE);
   TvVoteOscillator(adx[idx],
                    (TvGt(adx[idx],20.0) && TvGt(adx[idx],adx_previous) && TvGt(plus_di[idx],minus_di[idx])),
                    (TvGt(adx[idx],20.0) && TvGt(adx[idx],adx_previous) && TvLt(plus_di[idx],minus_di[idx])),
                    osc_sum,osc_count,18);

   // Awesome Oscillator = sma(hl2,5) - sma(hl2,34)
   double ao_fast[];
   double ao_slow[];
   double ao[];
   TvSma(hl2,5,ao_fast);
   TvSma(hl2,34,ao_slow);
   TvAlloc(ao,n);
   for(int i=0; i<n; i++)
     {
      if(TvIsNa(ao_fast[i]) || TvIsNa(ao_slow[i]))
         continue;
      ao[i] = ao_fast[i] - ao_slow[i];
     }
   double ao_previous = (idx >= 1 ? ao[idx - 1] : EMPTY_VALUE);
   double ao_previous2 = (idx >= 2 ? ao[idx - 2] : EMPTY_VALUE);
   bool ao_cross_up = (TvGt(ao[idx],0.0) && TvLe(ao_previous,0.0));
   bool ao_cross_down = (TvLt(ao[idx],0.0) && !TvLt(ao_previous,0.0) && !TvIsNa(ao_previous));
   bool ao_turns_up = (TvGt(ao[idx],0.0) && TvGt(ao_previous,0.0) &&
                       TvGt(ao[idx],ao_previous) && TvGt(ao_previous2,ao_previous));
   bool ao_turns_down = (TvLt(ao[idx],0.0) && TvLt(ao_previous,0.0) &&
                         TvLt(ao[idx],ao_previous) && TvLt(ao_previous2,ao_previous));
   TvVoteOscillator(ao_previous,
                    (ao_cross_up || ao_turns_up),
                    (ao_cross_down || ao_turns_down),
                    osc_sum,osc_count,19);

   // Momentum(10) = close - close[10]
   double mom[];
   TvAlloc(mom,n);
   for(int i=10; i<n; i++)
      mom[i] = g_tv_close[i] - g_tv_close[i - 10];
   double mom_previous = (idx >= 1 ? mom[idx - 1] : EMPTY_VALUE);
   TvVoteOscillator(mom_previous,
                    TvGt(mom[idx],mom_previous),
                    TvLt(mom[idx],mom_previous),
                    osc_sum,osc_count,20);

   // MACD(12,26,9) — sinyal hattı EMA(9)
   double ema_fast[];
   double ema_slow[];
   double macd[];
   double macd_signal[];
   TvEma(g_tv_close,12,ema_fast);
   TvEma(g_tv_close,26,ema_slow);
   TvAlloc(macd,n);
   for(int i=0; i<n; i++)
     {
      if(TvIsNa(ema_fast[i]) || TvIsNa(ema_slow[i]))
         continue;
      macd[i] = ema_fast[i] - ema_slow[i];
     }
   TvEma(macd,9,macd_signal);
   TvVoteOscillator(macd_signal[idx],
                    TvGt(macd[idx],macd_signal[idx]),
                    TvLt(macd[idx],macd_signal[idx]),
                    osc_sum,osc_count,21);

   // Trend filtresi: close > ema(close,50) = yükseliş, close < ema(close,50) = düşüş
   bool up_trend = TvGt(close_price,ema50[idx]);
   bool down_trend = TvLt(close_price,ema50[idx]);

   // Stochastic RSI(14,14,3,3)
   double stoch_rsi_raw[];
   double k_rsi[];
   double d_rsi[];
   TvStoch(rsi,rsi,rsi,14,stoch_rsi_raw);
   TvSma(stoch_rsi_raw,3,k_rsi);
   TvSma(k_rsi,3,d_rsi);
   TvVoteOscillator(ema50[idx],
                    (down_trend && TvLt(k_rsi[idx],20.0) && TvLt(d_rsi[idx],20.0) && TvGt(k_rsi[idx],d_rsi[idx])),
                    (up_trend && TvGt(k_rsi[idx],80.0) && TvGt(d_rsi[idx],80.0) && TvLt(k_rsi[idx],d_rsi[idx])),
                    osc_sum,osc_count,22);

   // Williams %R(14)
   double williams[];
   TvWilliamsR(14,williams);
   double williams_previous = (idx >= 1 ? williams[idx - 1] : EMPTY_VALUE);
   TvVoteOscillator(williams_previous,
                    (TvLt(williams[idx],-80.0) && TvGt(williams[idx],williams_previous)),
                    (TvGt(williams[idx],-20.0) && TvLt(williams[idx],williams_previous)),
                    osc_sum,osc_count,23);

   // Bull Bear Power(13): bull = high - ema13, bear = low - ema13
   double ema13[];
   double bull_power[];
   double bear_power[];
   TvEma(g_tv_close,13,ema13);
   TvAlloc(bull_power,n);
   TvAlloc(bear_power,n);
   for(int i=0; i<n; i++)
     {
      if(TvIsNa(ema13[i]))
         continue;
      bull_power[i] = g_tv_high[i] - ema13[i];
      bear_power[i] = g_tv_low[i] - ema13[i];
     }
   double bear_power_previous = (idx >= 1 ? bear_power[idx - 1] : EMPTY_VALUE);
   double bull_power_previous = (idx >= 1 ? bull_power[idx - 1] : EMPTY_VALUE);
   TvVoteOscillator(ema50[idx],
                    (up_trend && TvLt(bear_power[idx],0.0) && TvGt(bear_power[idx],bear_power_previous)),
                    (down_trend && TvGt(bull_power[idx],0.0) && TvLt(bull_power[idx],bull_power_previous)),
                    osc_sum,osc_count,24);

   // Ultimate Oscillator(7,14,28) = 100 * (4*ort7 + 2*ort14 + ort28) / 7
   double true_low[];
   double true_high[];
   double uo_tr[];
   double uo_bp[];
   TvAlloc(true_low,n);
   TvAlloc(true_high,n);
   TvAlloc(uo_tr,n);
   TvAlloc(uo_bp,n);
   for(int i=1; i<n; i++)
     {
      true_low[i] = MathMin(g_tv_low[i],g_tv_close[i - 1]);
      true_high[i] = MathMax(g_tv_high[i],g_tv_close[i - 1]);
      uo_tr[i] = true_high[i] - true_low[i];
      uo_bp[i] = g_tv_close[i] - true_low[i];
     }
   double sum_bp7[];
   double sum_tr7[];
   double sum_bp14[];
   double sum_tr14[];
   double sum_bp28[];
   double sum_tr28[];
   TvSum(uo_bp,7,sum_bp7);
   TvSum(uo_tr,7,sum_tr7);
   TvSum(uo_bp,14,sum_bp14);
   TvSum(uo_tr,14,sum_tr14);
   TvSum(uo_bp,28,sum_bp28);
   TvSum(uo_tr,28,sum_tr28);
   double uo = EMPTY_VALUE;
   if(!TvIsNa(sum_tr7[idx]) && !TvIsNa(sum_tr14[idx]) && !TvIsNa(sum_tr28[idx]) &&
      sum_tr7[idx] > 0.0 && sum_tr14[idx] > 0.0 && sum_tr28[idx] > 0.0)
     {
      double average7 = sum_bp7[idx] / sum_tr7[idx];
      double average14 = sum_bp14[idx] / sum_tr14[idx];
      double average28 = sum_bp28[idx] / sum_tr28[idx];
      uo = 100.0 * (4.0 * average7 + 2.0 * average14 + average28) / 7.0;
     }
   TvVoteOscillator(uo,TvGt(uo,70.0),TvLt(uo,30.0),osc_sum,osc_count,25);

   // --- grup ortalamaları (na oylar dahil edilmez)
   if(ma_count > 0)
      ma_rating = ma_sum / (double)ma_count;
   if(osc_count > 0)
      osc_rating = osc_sum / (double)osc_count;

   g_rating_ma_votes = ma_count;
   g_rating_osc_votes = osc_count;

   if(!TvIsNa(ma_rating) && !TvIsNa(osc_rating))
      total_rating = (ma_rating + osc_rating) * 0.5;
   else if(!TvIsNa(ma_rating))
      total_rating = ma_rating;
   else if(!TvIsNa(osc_rating))
      total_rating = osc_rating;

   return (!TvIsNa(total_rating));
  }

double RatingValueForGroup()
  {
   switch(InpRatingGroup)
     {
      case RATING_MOVING_AVERAGES: return g_rating_ma;
      case RATING_OSCILLATORS:     return g_rating_osc;
     }
   return g_rating_value;
  }

string RatingValueText(const double value)
  {
   if(TvIsNa(value))
      return "veri yok";
   return DoubleToString(value,4);
  }

// ratingStatus(): 0.5 ve 0.1 sınırlarıyla beş kategori.
int TvRatingStatus(const double value)
  {
   if(TvIsNa(value))
      return 0;
   if(TvLt(value,-InpRatingStrongBound))
      return -2;
   if(TvLt(value,-InpRatingNeutralBound))
      return -1;
   if(TvGt(value,InpRatingStrongBound))
      return 2;
   if(TvGt(value,InpRatingNeutralBound))
      return 1;
   return 0;
  }

void LogRatingComponents()
  {
   if(!InpLogRatingComponents)
      return;
   string moving_averages = "";
   string oscillators = "";
   for(int i=0; i<26; i++)
     {
      string vote = "na";
      if(!TvIsNa(g_rating_component_votes[i]))
         vote = (g_rating_component_votes[i] > 0.5 ? "AL" : (g_rating_component_votes[i] < -0.5 ? "SAT" : "NÖTR"));
      if(i < 15)
         moving_averages += g_rating_component_names[i] + "=" + vote + "  ";
      else
         oscillators += g_rating_component_names[i] + "=" + vote + "  ";
     }
   Print("Teknik özet ortalamalar: ",moving_averages);
   Print("Teknik özet osilatörler: ",oscillators);
  }

//+------------------------------------------------------------------+
//| Sinyal yönü                                                      |
//+------------------------------------------------------------------+
void ClosePositionsOppositeToTradeSide(const int new_trade_side);
void CloseAllOurPositions(const string reason);
void ReseedGridCrossState(const double current_price);
bool OpenGridPosition(const int side,const int line_code,const double signal_price);

// Seçilen zaman diliminde TradingView Teknik Özet ibresini hesaplar.
bool CalculateTechnicalSummarySignal(int &side_out,datetime &bar_time_out)
  {
   side_out = 0;
   bar_time_out = 0;
   if(!TvLoadHistory(InpRatingHistoryBars))
      return false;

   // Kapanmış mum modunda terminalin son mumu gerçekten yeni bar olmalı; değilse
   // bir sonraki tikte/zamanlayıcıda yeniden denenir (bayat veriyle puan üretilmez).
   if(InpRatingUseClosedBar)
     {
      datetime live_bar_time = iTime(_Symbol,InpSignalTimeframe,0);
      if(live_bar_time > 0 && g_tv_time[g_tv_bars - 1] != live_bar_time)
         return false;
     }

   int idx = (InpRatingUseClosedBar ? g_tv_bars - 2 : g_tv_bars - 1);
   if(idx < 1)
      return false;

   double ma_rating = EMPTY_VALUE;
   double osc_rating = EMPTY_VALUE;
   double total_rating = EMPTY_VALUE;
   if(!TvComputeRatings(idx,ma_rating,osc_rating,total_rating))
      return false;

   g_rating_ma = ma_rating;
   g_rating_osc = osc_rating;
   g_rating_value = total_rating;
   g_rating_bar_time = g_tv_time[idx];
   bar_time_out = g_rating_bar_time;

   g_rating_status = TvRatingStatus(RatingValueForGroup());
   side_out = (g_rating_status > 0 ? 1 : (g_rating_status < 0 ? -1 : 0));
   return true;
  }

// Eski davranış: kapanmış mumun (Heiken Ashi veya normal) rengi.
bool CalculateClosedCandleSignal(int &side_out,datetime &current_bar_time)
  {
   side_out = 0;
   current_bar_time = 0;
   int history = InpSignalHistoryBars;
   if(history < 50)
      history = 50;
   if(history > 1500)
      history = 1500;

   MqlRates rates[];
   ArraySetAsSeries(rates,true);
   int copied = CopyRates(_Symbol,InpSignalTimeframe,0,history,rates);
   if(copied < 3)
      return false;
   current_bar_time = rates[0].time;

   if(InpSignalMode == SIGNAL_STANDARD_CANDLE)
     {
      side_out = (rates[1].close >= rates[1].open ? 1 : -1);
      return true;
     }

   double previous_ha_open = 0.0;
   double previous_ha_close = 0.0;
   for(int shift=copied - 1; shift>=0; shift--)
     {
      double ha_close = (rates[shift].open + rates[shift].high + rates[shift].low + rates[shift].close) / 4.0;
      double ha_open;
      if(shift == copied - 1)
         ha_open = (rates[shift].open + rates[shift].close) / 2.0;
      else
         ha_open = (previous_ha_open + previous_ha_close) / 2.0;

      if(shift == 1)
         side_out = (ha_close >= ha_open ? 1 : -1);
      previous_ha_open = ha_open;
      previous_ha_close = ha_close;
     }
   return (side_out != 0);
  }

// Yön değiştiğinde yapılacaklar: pozisyon kapatma seçeneği + grid'i yeni yönde kurma.
void ApplySignalSide(const int new_side)
  {
   int old_side = g_signal_side;
   if(old_side == new_side)
      return;

   g_signal_side = new_side;
   int old_trade_side = TradeSideForSignal(old_side);
   int new_trade_side = TradeSideForSignal(new_side);

   if(InpSignalMode == SIGNAL_TECHNICAL_SUMMARY)
      g_last_action = StringFormat("Teknik özet %s (%s) | grid yönü %s",
                                   RatingStatusName(g_rating_status),RatingValueText(RatingValueForGroup()),
                                   SideName(new_trade_side));
   else
      g_last_action = StringFormat("%s sinyali %s oldu",SignalModeName(),SideName(new_side));

   if(InpSignalMode == SIGNAL_TECHNICAL_SUMMARY)
      PrintFormat("Teknik özet değişti (%s): yön %s -> %s | ibre=%s puan=%s (MA=%s/%d oy, OSC=%s/%d oy) | islem yonu=%s",
                  EnumToString(InpSignalTimeframe),
                  SideName(old_side),SideName(new_side),
                  RatingStatusName(g_rating_status),RatingValueText(RatingValueForGroup()),
                  RatingValueText(g_rating_ma),g_rating_ma_votes,
                  RatingValueText(g_rating_osc),g_rating_osc_votes,
                  SideName(new_trade_side));
   else
      PrintFormat("Mum sinyali değişti (%s %s): %s -> %s | islem yonu=%s",
                  SignalModeName(),EnumToString(InpSignalTimeframe),
                  SideName(old_side),SideName(new_side),SideName(new_trade_side));

   RecolorGridLines();
   if(InpSignalMode == SIGNAL_TECHNICAL_SUMMARY)
      LogRatingComponents();

   bool first_signal = !g_signal_ready;
   g_signal_ready = true;
   if(InpUseMacdSignalEntries)
      return; // MACD giriş modunda çıkışlar yalnız grid TP/SL ile yapılır; ibre pozisyon kapatmaz.
   if(first_signal || old_trade_side == new_trade_side)
      return; // İlk kurulumda veya yön aynı kaldığında pozisyonlara dokunma.

   if(new_trade_side == 0)
     {
      // NÖTR: yeni işlem açılmaz (TradeSideForSignal 0 döndürür).
      if(InpOnNeutral == NEUTRAL_CLOSE_ALL)
         CloseAllOurPositions("Teknik özet NÖTR: tüm pozisyonlar kapatıldı");
      else
         g_last_action = "Teknik özet NÖTR: yeni giriş yok, açık pozisyonlar korunuyor";
     }
   else
     {
      // İbre ters yöne döndü: kapatma seçeneği uygulanır, grid yeni yöne kurulur.
      if(InpOnDirectionFlip == DIRECTION_CLOSE_OPPOSITE)
         ClosePositionsOppositeToTradeSide(new_trade_side);
      else if(InpOnDirectionFlip == DIRECTION_CLOSE_ALL)
         CloseAllOurPositions("Grid yönü değişti: tüm pozisyonlar kapatıldı");

      if(InpRebaseGridOnDirectionChange)
         RebaseGridAtCurrentPrice(StringFormat("Yön değişimi: %s",SideName(new_trade_side)));
     }

   // Geçiş hafızasını tazele: yeni yön yalnız yeni geçişlerde işlem açsın.
   MqlTick tick;
   if(SymbolInfoTick(_Symbol,tick))
      ReseedGridCrossState(MidPrice(tick));
  }

void RefreshTechnicalSummarySignal(const bool force)
  {
   datetime live_bar_time = iTime(_Symbol,InpSignalTimeframe,0);
   datetime now = TimeCurrent();
   bool recalculate = force;
   if(!recalculate)
     {
      if(InpRatingUseClosedBar)
         recalculate = (live_bar_time > 0 && live_bar_time != g_last_signal_bar_time);
      else
         recalculate = (g_last_rating_calc == 0 ||
                        (long)(now - g_last_rating_calc) >= (long)MathMax(1,InpRatingLiveRefreshSeconds));
     }
   if(!recalculate)
      return;
   if(g_rating_retry_after > 0 && now < g_rating_retry_after)
      return; // Henüz yeterli mum yok: 5 saniyede bir yeniden dene.
   g_last_rating_calc = now;

   int raw_side = 0;
   datetime bar_time = 0;
   if(!CalculateTechnicalSummarySignal(raw_side,bar_time))
     {
      g_rating_retry_after = now + 5;
      return;
     }
   g_rating_retry_after = 0;
   g_last_signal_bar_time = (live_bar_time > 0 ? live_bar_time : bar_time);

   int confirm_bars = 1;
   if(InpRatingUseClosedBar && InpRatingConfirmBars > 1)
      confirm_bars = InpRatingConfirmBars;
   int confirmed_side = raw_side;
   if(confirm_bars > 1)
     {
      if(bar_time != g_rating_streak_bar)
        {
         g_rating_streak_bar = bar_time;
         if(raw_side == g_rating_streak_side)
            g_rating_streak_count++;
         else
           {
            g_rating_streak_side = raw_side;
            g_rating_streak_count = 1;
           }
        }
      // Onay tamamlanana kadar mevcut yön korunur (nötre düşmez, ters yöne atlamaz).
      confirmed_side = (g_rating_streak_count >= confirm_bars ? g_rating_streak_side : g_signal_side);
     }

   ApplySignalSide(confirmed_side);
  }

void RefreshClosedCandleSignal(const bool force)
  {
   datetime chart_bar_time = iTime(_Symbol,InpSignalTimeframe,0);
   if(!force && chart_bar_time > 0 && chart_bar_time == g_last_signal_bar_time)
      return;

   int new_side = 0;
   datetime current_bar_time = 0;
   if(!CalculateClosedCandleSignal(new_side,current_bar_time))
      return;

   g_last_signal_bar_time = (current_bar_time > 0 ? current_bar_time : chart_bar_time);
   if(new_side == 0)
      return;

   ApplySignalSide(new_side);
  }

void RefreshSignal(const bool force)
  {
   if(InpSignalMode == SIGNAL_TECHNICAL_SUMMARY)
      RefreshTechnicalSummarySignal(force);
   else
      RefreshClosedCandleSignal(force);
  }

//+------------------------------------------------------------------+
//| Pine: "Enhanced MACD with Strong Buy/Sell Signals" (Ali_Smith)   |
//|                                                                  |
//|   [macdLine, signalLine, _] = ta.macd(close, fast, slow, signal) |
//|   strongBuy  = ta.crossover(macdLine, signalLine)  and macdLine > 0
//|   strongSell = ta.crossunder(macdLine, signalLine) and macdLine < 0
//|                                                                  |
//| MQL5 karşılığı birebirdir: ta.macd = ema(fast) - ema(slow),      |
//| sinyal = ema(macd, signalSmoothing); crossover/crossunder        |
//| kapanmış mumda değerlendirilir (repaint yok).                    |
//| Bu mod AÇIKKEN: girişler YALNIZ bu sinyallerdendir (grid         |
//| geçişleri giriş açmaz), çıkışlar grid TP/SL ayarlarıyla          |
//| yönetilir; ibre kaynaklı pozisyon kapatma yapılmaz.              |
//+------------------------------------------------------------------+
bool ComputeMacdStrongSignal(int &side_out,double &macd_out,double &signal_out)
  {
   side_out = 0;
   macd_out = EMPTY_VALUE;
   signal_out = EMPTY_VALUE;

   int minimum = InpMacdSlowLength + InpMacdSignalLength + 10;
   int want = (InpMacdHistoryBars > minimum ? InpMacdHistoryBars : minimum);

   MqlRates rates[];
   ArraySetAsSeries(rates,false); // [0] = en eski mum
   int copied = CopyRates(_Symbol,InpMacdTimeframe,0,want,rates);
   if(copied < minimum)
     {
      static datetime last_warning = 0;
      datetime now = TimeCurrent();
      if(last_warning == 0 || now - last_warning >= 60)
        {
         last_warning = now;
         PrintFormat("MACD sinyali için yeterli mum yok: %s üzerinde en az %d mum gerekiyor, %d bulundu.",
                     EnumToString(InpMacdTimeframe),minimum,copied);
        }
      return false;
     }

   double close_price[];
   ArrayResize(close_price,copied);
   for(int i=0; i<copied; i++)
      close_price[i] = rates[i].close;

   double ema_fast[];
   double ema_slow[];
   TvEma(close_price,InpMacdFastLength,ema_fast);
   TvEma(close_price,InpMacdSlowLength,ema_slow);

   double macd_line[];
   ArrayResize(macd_line,copied);
   for(int i=0; i<copied; i++)
     {
      if(TvIsNa(ema_fast[i]) || TvIsNa(ema_slow[i]))
         continue;
      macd_line[i] = ema_fast[i] - ema_slow[i];
     }
   double signal_line[];
   TvEma(macd_line,InpMacdSignalLength,signal_line);

   int idx = copied - 2; // son KAPANMIŞ mum (Pine geçmiş plot ile aynı sinyal kümesi)
   if(idx < 1)
      return false;
   double macd_now = macd_line[idx];
   double signal_now = signal_line[idx];
   double macd_prev = macd_line[idx - 1];
   double signal_prev = signal_line[idx - 1];
   macd_out = macd_now;
   signal_out = signal_now;
   if(TvIsNa(macd_now) || TvIsNa(signal_now) || TvIsNa(macd_prev) || TvIsNa(signal_prev))
      return false;

   // Pine ta.crossover / ta.crossunder: a[0] > b[0] && a[1] <= b[1]  (birebir)
   bool cross_over = (macd_now > signal_now && macd_prev <= signal_prev);
   bool cross_under = (macd_now < signal_now && macd_prev >= signal_prev);
   if(cross_over && macd_now > 0.0)
      side_out = 1;
   else if(cross_under && macd_now < 0.0)
      side_out = -1;
   return true;
  }

void ProcessMacdEntries()
  {
   if(!InpUseMacdSignalEntries)
      return;
   datetime closed_bar_time = iTime(_Symbol,InpMacdTimeframe,1);
   if(closed_bar_time <= 0 || closed_bar_time == g_macd_last_bar)
      return; // Bu kapanmış mum zaten değerlendirildi.
   g_macd_last_bar = closed_bar_time;

   int side = 0;
   double macd_now = EMPTY_VALUE;
   double signal_now = EMPTY_VALUE;
   if(!ComputeMacdStrongSignal(side,macd_now,signal_now))
      return;
   g_macd_line = macd_now;
   g_macd_signal = signal_now;
   g_macd_bar_time = closed_bar_time;
   g_macd_side = side;
   if(side == 0)
      return;

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
      return;
   if(InpMacdLogSignals)
      PrintFormat("MACD güçlü sinyal (%s): %s | macd=%.*f sinyal=%.*f | mum %s",
                  EnumToString(InpMacdTimeframe),SideName(side),
                  _Digits,macd_now,_Digits,signal_now,
                  TimeToString(closed_bar_time,TIME_DATE|TIME_MINUTES));

   // Benzersiz çizgi kodu: grid seviyeleri 1..InpMaxGridLevels (<=1000) aralığında
   // kaldığı için 5000+ serisi hiçbir grid çizgisiyle çakışmaz.
   int sequence = (++g_macd_entry_seq);
   int line_code = (side > 0 ? 5000 + sequence : -(5000 + sequence));
   bool opened = OpenGridPosition(side,line_code,MidPrice(tick));
   g_last_action = StringFormat("MACD %s sinyali: %s",SideName(side),
                                (opened ? "giriş açıldı" : "giriş atlandı (sınır/spread)"));
  }

//+------------------------------------------------------------------+
//| Position state, discovery and risk sizing                        |
//+------------------------------------------------------------------+
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

int ParseLineCode(const string comment)
  {
   int marker = StringFind(comment,"M1G:");
   if(marker < 0)
      return 0;
   string line = StringSubstr(comment,marker + 4);
   if(StringFind(line,"U") == 0)
      return (int)StringToInteger(StringSubstr(line,1));
   if(StringFind(line,"D") == 0)
      return -(int)MathAbs((double)StringToInteger(StringSubstr(line,1)));
   return 0;
  }

int PositionLineCode(const ulong ticket)
  {
   if(!PositionSelectByTicket(ticket))
      return 0;
   if(MQLInfoInteger(MQL_TESTER))
      return ParseLineCode(PositionGetString(POSITION_COMMENT));
   ulong identifier = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   string key = PositionStateKey(identifier,"LN");
   if(GlobalVariableCheck(key))
      return (int)MathRound(GlobalVariableGet(key));
   return ParseLineCode(PositionGetString(POSITION_COMMENT));
  }

void StorePositionSettings(const ulong identifier,const int line_code,const double grid_step,
                           const int tp_grids,const int sl_grids)
  {
   if(MQLInfoInteger(MQL_TESTER))
      return;
   GlobalVariableSet(PositionStateKey(identifier,"LN"),(double)line_code);
   GlobalVariableSet(PositionStateKey(identifier,"GS"),grid_step);
   GlobalVariableSet(PositionStateKey(identifier,"TP"),(double)tp_grids);
   GlobalVariableSet(PositionStateKey(identifier,"SL"),(double)sl_grids);
   GlobalVariablesFlush();
  }

void DeletePositionSettings(const ulong identifier)
  {
   if(MQLInfoInteger(MQL_TESTER))
      return;
   GlobalVariableDel(PositionStateKey(identifier,"LN"));
   GlobalVariableDel(PositionStateKey(identifier,"GS"));
   GlobalVariableDel(PositionStateKey(identifier,"TP"));
   GlobalVariableDel(PositionStateKey(identifier,"SL"));
   GlobalVariablesFlush();
  }

void GetPositionGridSettings(const ulong ticket,double &grid_step,int &tp_grids,int &sl_grids)
  {
   grid_step = g_grid_step;
   tp_grids = InpTakeProfitGrids;
   sl_grids = InpStopLossGrids;
   if(!PositionSelectByTicket(ticket))
      return;

   if(MQLInfoInteger(MQL_TESTER))
      return;

   ulong identifier = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   string key = PositionStateKey(identifier,"GS");
   if(GlobalVariableCheck(key))
     {
      double saved = GlobalVariableGet(key);
      if(saved > 0.0)
         grid_step = saved;
     }
   key = PositionStateKey(identifier,"TP");
   if(GlobalVariableCheck(key))
     {
      int saved_tp = (int)MathRound(GlobalVariableGet(key));
      if(saved_tp > 0)
         tp_grids = saved_tp;
     }
   key = PositionStateKey(identifier,"SL");
   if(GlobalVariableCheck(key))
     {
      int saved_sl = (int)MathRound(GlobalVariableGet(key));
      if(saved_sl > 0)
         sl_grids = saved_sl;
     }

   // If a market deal was accepted but its ticket was not immediately discoverable,
   // persist the settings on the next management pass using the position comment.
   string step_key = PositionStateKey(identifier,"GS");
   if(!GlobalVariableCheck(step_key))
      StorePositionSettings(identifier,PositionLineCode(ticket),grid_step,tp_grids,sl_grids);
  }

int CountOurPositions(const int side_filter=0)
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

bool HasPositionOnGridLine(const int side,const int line_code)
  {
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      if(SideFromPositionType(PositionGetInteger(POSITION_TYPE)) != side)
         continue;
      if(PositionLineCode(ticket) == line_code)
         return true;
     }
   return false;
  }

bool CloseOurPosition(const ulong ticket,const string reason);

//+------------------------------------------------------------------+
//| Position-limit rotation                                          |
//| At the per-side or total position cap, close the oldest position |
//| on the same side so the incoming signal can open a fresh entry   |
//| on the new grid level. Returns true when a slot was freed.       |
//+------------------------------------------------------------------+
bool CloseOldestPositionOnSide(const int side,const int protected_line_code)
  {
   ulong    oldest_ticket = 0;
   datetime oldest_time = 0;
   long     oldest_time_msc = 0;
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      if(SideFromPositionType(PositionGetInteger(POSITION_TYPE)) != side)
         continue;
      // Never sacrifice a position just opened on the level that is firing now.
      if(protected_line_code != 0 && PositionLineCode(ticket) == protected_line_code)
         continue;

      datetime open_time = (datetime)PositionGetInteger(POSITION_TIME);
      long open_time_msc = PositionGetInteger(POSITION_TIME_MSC);
      bool is_older = (oldest_ticket == 0 ||
                       open_time < oldest_time ||
                       (open_time == oldest_time && open_time_msc < oldest_time_msc));
      if(is_older)
        {
         oldest_ticket = ticket;
         oldest_time = open_time;
         oldest_time_msc = open_time_msc;
        }
     }

   if(oldest_ticket == 0)
      return false; // Nothing on this side can be rotated out.

   string reason = StringFormat("Sınır rotasyonu: en eski %s pozisyon kapatıldı",SideName(side));
   g_last_action = reason;
   if(!CloseOurPosition(oldest_ticket,reason))
      return false;

   // In netting-style partial closures a small residual could stay behind; only
   // report success when the slot is genuinely free.
   return !SelectOurPosition(oldest_ticket);
  }

double OrderVolume()
  {
   double min_volume = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MIN);
   double max_volume = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_MAX);
   double volume_step = SymbolInfoDouble(_Symbol,SYMBOL_VOLUME_STEP);
   if(min_volume <= 0.0 || volume_step <= 0.0)
      return 0.0;
   if(InpUseBrokerMinimumVolume)
      return min_volume;

   double requested = InpFixedLots;
   if(requested <= 0.0)
      return 0.0;
   if(max_volume > 0.0 && requested > max_volume)
      requested = max_volume;
   double result = MathFloor(requested / volume_step + 1.0e-10) * volume_step;
   result = NormalizeDouble(result,8);
   if(result + 1.0e-10 < min_volume)
     {
      PrintFormat("Hacim atlandı: istenen lot %.8f broker minimumu %.8f altında.",requested,min_volume);
      return 0.0;
     }
   return result;
  }

double PositionTakeProfit(const double entry,const int side,const double grid_step,const int grids)
  {
   double raw = entry + side * grid_step * grids;
   return NormalizePriceToTick(raw,(side > 0 ? 1 : -1));
  }

double PositionStopLoss(const double entry,const int side,const double grid_step,const int grids)
  {
   double raw = entry - side * grid_step * grids;
   return NormalizePriceToTick(raw,(side > 0 ? -1 : 1));
  }

bool ModifyPositionProtection(const ulong ticket,const int side,const double entry,
                              const double grid_step,const int tp_grids,const int sl_grids)
  {
   if(!PositionSelectByTicket(ticket))
      return false;
   double desired_tp = PositionTakeProfit(entry,side,grid_step,tp_grids);
   double desired_sl = PositionStopLoss(entry,side,grid_step,sl_grids);
   double current_tp = PositionGetDouble(POSITION_TP);
   double current_sl = PositionGetDouble(POSITION_SL);
   double tolerance = TickSize() * 0.5;
   if(MathAbs(current_tp - desired_tp) <= tolerance && MathAbs(current_sl - desired_sl) <= tolerance)
      return true;

   bool modified = trade.PositionModify(ticket,desired_sl,desired_tp);
   if(!TradeRetcodeOK(modified))
     {
      PrintFormat("Koruma emri güncellenemedi ticket=%I64u retcode=%u (%s). EA yerel fiyat kontrolünü sürdürecek.",
                  ticket,trade.ResultRetcode(),trade.ResultRetcodeDescription());
      return false;
     }
   return true;
  }

bool CloseOurPosition(const ulong ticket,const string reason)
  {
   if(!SelectOurPosition(ticket))
      return true; // Already closed by server-side TP/SL.
   ulong identifier = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   int side = SideFromPositionType(PositionGetInteger(POSITION_TYPE));
   bool sent = trade.PositionClose(ticket,InpDeviationPoints);
   if(!TradeRetcodeOK(sent))
     {
      PrintFormat("Kapatma başarısız ticket=%I64u neden=%s retcode=%u (%s)",
                  ticket,reason,trade.ResultRetcode(),trade.ResultRetcodeDescription());
      return false;
     }
   if(PositionSelectByTicket(ticket))
     {
      PrintFormat("Pozisyon tamamen kapanmadı ticket=%I64u kalan hacim=%.8f",ticket,
                  PositionGetDouble(POSITION_VOLUME));
      return false;
     }
   DeletePositionSettings(identifier);
   PrintFormat("Pozisyon kapandı: ticket=%I64u side=%s reason=%s",ticket,SideName(side),reason);
   g_last_action = reason;
   return true;
  }

void ReseedGridCrossState(const double current_price)
  {
   if(current_price <= 0.0)
      return;
   for(int i=1; i<=g_up_count; i++)
      g_up_state[i] = ComparePriceToLevel(current_price,GridLevelPrice(true,i));
   for(int i=1; i<=g_down_count; i++)
      g_down_state[i] = ComparePriceToLevel(current_price,GridLevelPrice(false,i));
  }

bool HandleEquityProfitTarget()
  {
   if(InpCloseAllAtEquityGain <= 0.0 || g_profit_target_start_equity <= 0.0)
      return false;

   double current_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(current_equity <= 0.0)
      current_equity = AccountInfoDouble(ACCOUNT_BALANCE);

   // Optional two-sided target: every new equity low becomes the new base.
   // Example: start 100, target 2. A drop to 95 re-bases the target to 97;
   // the next rise to 97 closes every position and starts a fresh cycle.
   if(InpEquityTargetRebaseOnLow && !g_profit_target_liquidating &&
      current_equity > 0.0 && current_equity < g_profit_target_start_equity)
     {
      double previous_base = g_profit_target_start_equity;
      g_profit_target_start_equity = current_equity;
      if(!MQLInfoInteger(MQL_TESTER))
        {
         GlobalVariableSet(GridStateKey("PTBASE"),g_profit_target_start_equity);
         GlobalVariableSet(GridStateKey("PTLOW"),1.0);
        }
      datetime low_now = TimeCurrent();
      if(g_last_low_rebase_log == 0 || low_now - g_last_low_rebase_log >= 10)
        {
         g_last_low_rebase_log = low_now;
         PrintFormat("Yeni özsermaye dibi: taban %.2f -> %.2f; yeni kapanış hedefi %.2f %s",
                     previous_base,g_profit_target_start_equity,
                     g_profit_target_start_equity + InpCloseAllAtEquityGain,
                     AccountInfoString(ACCOUNT_CURRENCY));
        }
      g_last_action = StringFormat("Yeni özsermaye dibi %.2f; hedef tabanı güncellendi",
                                   g_profit_target_start_equity);
     }

   if(!g_profit_target_liquidating &&
      current_equity - g_profit_target_start_equity >= InpCloseAllAtEquityGain)
     {
      g_profit_target_liquidating = true;
      SaveProfitTargetState();
      g_last_action = "Özsermaye hedefi ulaştı; EA pozisyonları kapatılıyor";
      PrintFormat("Özsermaye hedefi ulaştı: başlangıç=%.2f güncel=%.2f hedef=%.2f %s; bu EA'nın pozisyonları kapatılıyor.",
                  g_profit_target_start_equity,current_equity,InpCloseAllAtEquityGain,
                  AccountInfoString(ACCOUNT_CURRENCY));
     }

   if(!g_profit_target_liquidating)
      return false;

   ulong tickets[];
   ArrayResize(tickets,0);
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      int n = ArraySize(tickets);
      if(ArrayResize(tickets,n + 1) >= n + 1)
         tickets[n] = ticket;
     }
   for(int i=0; i<ArraySize(tickets); i++)
      CloseOurPosition(tickets[i],"Özsermaye kâr hedefi");

   int remaining = CountOurPositions(0);
   if(remaining > 0)
     {
      g_last_action = StringFormat("Kâr hedefi: %d EA pozisyonu daha kapatılacak",remaining);
      return true;
     }

   // Start the next profit cycle only after every position belonging to this EA is closed.
   double new_equity = AccountInfoDouble(ACCOUNT_EQUITY);
   if(new_equity <= 0.0)
      new_equity = AccountInfoDouble(ACCOUNT_BALANCE);
   if(new_equity > 0.0)
     {
      g_profit_target_start_equity = new_equity;
      g_profit_target_liquidating = false;
      SaveProfitTargetState();
      MqlTick tick;
      if(SymbolInfoTick(_Symbol,tick))
         ReseedGridCrossState(MidPrice(tick));
      g_last_action = "Kâr hedefi tamamlandı; yeni hedef döngüsü başladı";
      PrintFormat("Yeni kâr hedefi döngüsü: başlangıç özsermayesi=%.2f %s hedef=%.2f",
                  g_profit_target_start_equity,AccountInfoString(ACCOUNT_CURRENCY),
                  InpCloseAllAtEquityGain);
     }
   return true; // Do not open a replacement position on the same tick as target liquidation.
  }

void ClosePositionsOppositeToTradeSide(const int new_trade_side)
  {
   if(new_trade_side == 0)
      return;
   ulong tickets[];
   ArrayResize(tickets,0);
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      if(SideFromPositionType(PositionGetInteger(POSITION_TYPE)) == -new_trade_side)
        {
         int n = ArraySize(tickets);
         if(ArrayResize(tickets,n + 1) >= n + 1)
            tickets[n] = ticket;
        }
     }
   for(int i=0; i<ArraySize(tickets); i++)
      CloseOurPosition(tickets[i],StringFormat("Grid yönü %s: ters pozisyon kapatıldı",SideName(new_trade_side)));
  }

void CloseAllOurPositions(const string reason)
  {
   ulong tickets[];
   ArrayResize(tickets,0);
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      int n = ArraySize(tickets);
      if(ArrayResize(tickets,n + 1) >= n + 1)
         tickets[n] = ticket;
     }
   if(ArraySize(tickets) == 0)
      return;
   PrintFormat("%s (%d pozisyon)",reason,ArraySize(tickets));
   for(int i=0; i<ArraySize(tickets); i++)
      CloseOurPosition(tickets[i],reason);
  }

//+------------------------------------------------------------------+
//| Grid entry                                                        |
//+------------------------------------------------------------------+
bool FindPositionFromDeal(const ulong deal,const int expected_side,const string expected_comment,
                          const long earliest_time_msc,ulong &ticket_out)
  {
   ticket_out = 0;
   if(deal > 0 && HistoryDealSelect(deal))
     {
      ulong position_id = (ulong)HistoryDealGetInteger(deal,DEAL_POSITION_ID);
      if(position_id > 0)
        {
         for(int i=PositionsTotal()-1; i>=0; i--)
           {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket))
               continue;
            if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
               (ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber)
               continue;
            if((ulong)PositionGetInteger(POSITION_IDENTIFIER) == position_id)
              {
               ticket_out = ticket;
               return true;
              }
           }
        }
     }

   // Fallback for brokers that do not return a position id immediately.
   long newest_time = -1;
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !PositionSelectByTicket(ticket))
         continue;
      if(PositionGetString(POSITION_SYMBOL) != _Symbol ||
         (ulong)PositionGetInteger(POSITION_MAGIC) != InpMagicNumber ||
         SideFromPositionType(PositionGetInteger(POSITION_TYPE)) != expected_side)
         continue;
      long time_msc = PositionGetInteger(POSITION_TIME_MSC);
      string comment = PositionGetString(POSITION_COMMENT);
      if(time_msc + 1000 < earliest_time_msc)
         continue;
      if(expected_comment != "" && StringFind(comment,expected_comment) < 0)
         continue;
      if(time_msc >= newest_time)
        {
         newest_time = time_msc;
         ticket_out = ticket;
        }
     }
   return (ticket_out > 0);
  }

bool OpenGridPosition(const int side,const int line_code,const double signal_price)
  {
   if(side == 0 || g_grid_step <= 0.0)
      return false;
   if(!InpUseMacdSignalEntries && g_signal_side == 0)
      return false; // Nötr / sinyal yok: grid girişi açılmaz (MACD modunda yön MACD'den gelir)

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick) || tick.ask <= 0.0 || tick.bid <= 0.0)
      return false;

   double spread_price = MathMax(0.0,tick.ask - tick.bid);
   double spread_points = spread_price / _Point;
   if(InpMaxSpreadPoints > 0 && spread_points > InpMaxSpreadPoints)
     {
      g_last_action = StringFormat("Spread yüksek: %.1f point",spread_points);
      return false;
     }
   if(InpMaxSpreadGridFraction > 0.0 && spread_price > g_grid_step * InpMaxSpreadGridFraction)
     {
      g_last_action = StringFormat("Spread grid adımına göre yüksek: %.1f point",spread_points);
      return false;
     }

   if(InpOnePositionPerGridLine && HasPositionOnGridLine(side,line_code))
     {
      g_last_action = "Bu grid çizgisinde aynı yönlü pozisyon açık";
      return false;
     }

   // Validate the new order fully before any rotation closes an existing position,
   // so a rejected/undersized entry never leaves the grid short of a layer.
   double volume = OrderVolume();
   if(volume <= 0.0)
     {
      g_last_action = "Lot hacmi broker sınırlarına uymuyor";
      return false;
     }

   double expected_entry = (side > 0 ? tick.ask : tick.bid);
   double expected_tp = PositionTakeProfit(expected_entry,side,g_grid_step,InpTakeProfitGrids);
   double expected_sl = PositionStopLoss(expected_entry,side,g_grid_step,InpStopLossGrids);
   if(expected_tp <= 0.0 || expected_sl <= 0.0)
     {
      g_last_action = "Pozitif olmayan TP/SL fiyatı nedeniyle giriş atlandı";
      return false;
     }

   int side_count = CountOurPositions(side);
   int total_count = CountOurPositions(0);
   bool total_full = (InpMaxTotalPositions > 0 && total_count >= InpMaxTotalPositions);
   bool side_full = (InpMaxLayersPerSide > 0 && side_count >= InpMaxLayersPerSide);
   if(total_full || side_full)
     {
      if(!InpRotateOldestAtLimit)
        {
         g_last_action = (total_full
                          ? "Toplam pozisyon sınırı dolu"
                          : StringFormat("%s katman sınırı dolu",SideName(side)));
         return false;
        }

      // Position limit is reached: free exactly one slot by closing the oldest
      // position on this side, then open the fresh entry on the new level.
      // The side count therefore drops by one before returning to the cap.
      if(!CloseOldestPositionOnSide(side,line_code))
        {
         g_last_action = (total_full
                          ? "Toplam pozisyon sınırı dolu; rotasyon için uygun aynı yönlü pozisyon yok"
                          : StringFormat("%s katman sınırı dolu; rotasyon için uygun aynı yönlü pozisyon yok",SideName(side)));
         return false;
        }
      PrintFormat("Rotasyon: %s | en eski pozisyon kapatıldı, kalan yan=%d toplam=%d; yeni seviyeden giriş denenecek.",
                  SideName(side),CountOurPositions(side),CountOurPositions(0));
     }

   string line_text = (line_code > 0 ? "U" + IntegerToString(line_code) : "D" + IntegerToString(-line_code));
   string comment = "M1G:" + line_text;
   long request_time_msc = (long)tick.time_msc;

   bool sent = false;
   if(side > 0)
      sent = trade.Buy(volume,_Symbol,0.0,expected_sl,expected_tp,comment);
   else
      sent = trade.Sell(volume,_Symbol,0.0,expected_sl,expected_tp,comment);

   if(!TradeRetcodeOK(sent))
     {
      PrintFormat("Grid girişi başarısız side=%s line=%s lot=%.8f retcode=%u (%s)",
                  SideName(side),line_text,volume,trade.ResultRetcode(),trade.ResultRetcodeDescription());
      g_last_action = "Emir broker tarafından reddedildi";
      return false;
     }

   ulong ticket = 0;
   FindPositionFromDeal(trade.ResultDeal(),side,comment,request_time_msc,ticket);
   if(ticket > 0 && PositionSelectByTicket(ticket))
     {
      ulong identifier = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      double fill_price = PositionGetDouble(POSITION_PRICE_OPEN);
      StorePositionSettings(identifier,line_code,g_grid_step,InpTakeProfitGrids,InpStopLossGrids);
      ModifyPositionProtection(ticket,side,fill_price,g_grid_step,InpTakeProfitGrids,InpStopLossGrids);
      PrintFormat("Grid giriş: %s line=%s signal=%.*f fill=%.*f lot=%.8f gridStep=%.*f TP=%.*f SL=%.*f",
                  SideName(side),line_text,_Digits,signal_price,_Digits,fill_price,
                  PositionGetDouble(POSITION_VOLUME),_Digits,g_grid_step,
                  _Digits,PositionTakeProfit(fill_price,side,g_grid_step,InpTakeProfitGrids),
                  _Digits,PositionStopLoss(fill_price,side,g_grid_step,InpStopLossGrids));
     }
   else
     {
      PrintFormat("Grid emri kabul edildi side=%s line=%s; pozisyon sonraki tikte bulunacak.",SideName(side),line_text);
     }

   g_last_action = StringFormat("Yeni %s giriş: %s",SideName(side),line_text);
   return true;
  }

void HandleGridCross(const bool is_up,const int index,const int cross_direction,
                     const double current_price)
  {
   if(InpUseMacdSignalEntries)
      return; // Girişler MACD sinyallerinden; geçişler yalnız çizgi/hafıza bakımı için izlenir.
   int trade_side = TradeSideForSignal(g_signal_side);
   if(trade_side == 0)
      return;
   if(!InpEnterOnAnyCross && cross_direction != trade_side)
      return;

   int line_code = (is_up ? index : -index);
   OpenGridPosition(trade_side,line_code,current_price);
  }

void ProcessGridCrosses(const double price)
  {
   if(g_grid_step <= 0.0 || g_grid_base <= 0.0)
      return;
   ExpandGrid(price);

   // Keep deterministic order if one tick crosses several existing grid levels.
   for(int i=1; i<=g_up_count; i++)
     {
      int now_side = ComparePriceToLevel(price,GridLevelPrice(true,i));
      if(now_side == 0)
         continue;
      int previous = g_up_state[i];
      g_up_state[i] = now_side;
      if(previous != 0 && now_side != previous)
         HandleGridCross(true,i,now_side,price);
     }

   for(int i=g_down_count; i>=1; i--)
     {
      int now_side = ComparePriceToLevel(price,GridLevelPrice(false,i));
      if(now_side == 0)
         continue;
      int previous = g_down_state[i];
      g_down_state[i] = now_side;
      if(previous != 0 && now_side != previous)
         HandleGridCross(false,i,now_side,price);
     }
  }

//+------------------------------------------------------------------+
//| Open position management                                         |
//+------------------------------------------------------------------+
void ManageOpenPositions(const MqlTick &tick)
  {
   ulong tickets[];
   ArrayResize(tickets,0);
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      int n = ArraySize(tickets);
      if(ArrayResize(tickets,n + 1) >= n + 1)
         tickets[n] = ticket;
     }

   for(int i=0; i<ArraySize(tickets); i++)
     {
      ulong ticket = tickets[i];
      if(!SelectOurPosition(ticket))
         continue;

      int side = SideFromPositionType(PositionGetInteger(POSITION_TYPE));
      double entry = PositionGetDouble(POSITION_PRICE_OPEN);
      double step = g_grid_step;
      int tp_grids = InpTakeProfitGrids;
      int sl_grids = InpStopLossGrids;
      GetPositionGridSettings(ticket,step,tp_grids,sl_grids);
      if(step <= 0.0 || entry <= 0.0)
         continue;

      double target = PositionTakeProfit(entry,side,step,tp_grids);
      double stop = PositionStopLoss(entry,side,step,sl_grids);
      // Use executable close prices: Bid closes LONG; Ask closes SHORT.
      double close_price = (side > 0 ? tick.bid : tick.ask);
      bool tp_hit = (side > 0 ? close_price >= target : close_price <= target);
      bool sl_hit = (side > 0 ? close_price <= stop : close_price >= stop);

      if(tp_hit)
        {
         CloseOurPosition(ticket,StringFormat("TP (%d grid)",tp_grids));
         continue;
        }
      if(sl_hit)
        {
         CloseOurPosition(ticket,StringFormat("SL (%d grid)",sl_grids));
         continue;
        }

      ModifyPositionProtection(ticket,side,entry,step,tp_grids,sl_grids);
     }
  }

//+------------------------------------------------------------------+
//| Status and standard MT5 events                                   |
//+------------------------------------------------------------------+
void UpdateChartStatus()
  {
   if(!InpShowChartStatus)
     {
      Comment("");
      return;
     }

   MqlTick tick;
   double current_price = 0.0;
   if(SymbolInfoTick(_Symbol,tick))
      current_price = MidPrice(tick);
   int long_count = CountOurPositions(1);
   int short_count = CountOurPositions(-1);
   double step_points = (g_grid_step > 0.0 ? g_grid_step / _Point : 0.0);
   double step_pips = (g_grid_step > 0.0 ? g_grid_step / PipSize() : 0.0);
   string signal_line = StringFormat("Sinyal: %s %s -> %s",SignalModeName(),
                                     EnumToString(InpSignalTimeframe),SideName(g_signal_side));
   if(InpSignalMode == SIGNAL_TECHNICAL_SUMMARY)
     {
      string ma_text = RatingValueText(g_rating_ma);
      string osc_text = RatingValueText(g_rating_osc);
      string value_text = RatingValueText(RatingValueForGroup());
      string gauge_text = (TvIsNa(RatingValueForGroup()) ? "hesaplanıyor" : RatingStatusName(g_rating_status));
      signal_line = StringFormat("Teknik özet (%s %s): %s  puan %s | Ort. %s (%d oy) | Osc. %s (%d oy) | mum %s",
                                 RatingGroupName(),EnumToString(InpSignalTimeframe),
                                 gauge_text,value_text,
                                 ma_text,g_rating_ma_votes,osc_text,g_rating_osc_votes,
                                 (g_rating_bar_time > 0 ? TimeToString(g_rating_bar_time,TIME_DATE|TIME_MINUTES) : "-"));
     }

   string entry_mode = "";
   if(InpUseMacdSignalEntries)
      entry_mode = StringFormat("Giriş modu: MACD güçlü sinyal (%s) | macd %s / sinyal %s | son sinyal: %s%s\n",
                                EnumToString(InpMacdTimeframe),
                                RatingValueText(g_macd_line),RatingValueText(g_macd_signal),
                                (g_macd_side != 0 ? SideName(g_macd_side) : "yok"),
                                (g_macd_bar_time > 0
                                 ? StringFormat(" (%s)",TimeToString(g_macd_bar_time,TIME_DATE|TIME_MINUTES)) : ""));
   string direction_policy = "";
   switch(InpOnDirectionFlip)
     {
      case DIRECTION_CLOSE_ALL:      direction_policy = "yön değişince tümü kapanır"; break;
      case DIRECTION_KEEP_OPEN:      direction_policy = "yön değişince pozisyonlar korunur"; break;
      default:                       direction_policy = "yön değişince ters pozisyonlar kapanır"; break;
     }
   string neutral_policy = (InpOnNeutral == NEUTRAL_CLOSE_ALL
                            ? "nötrde tümü kapanır"
                            : "nötrde yeni giriş yok, pozisyonlar korunur");

   string target_status = "Özsermaye hedefi: kapalı";
   if(InpCloseAllAtEquityGain > 0.0)
     {
      double equity_gain = AccountInfoDouble(ACCOUNT_EQUITY) - g_profit_target_start_equity;
      string rebound_text = "";
      if(InpEquityTargetRebaseOnLow)
         rebound_text = " | dip takibi açık";
      target_status = StringFormat("Özsermaye hedefi: %.2f / %.2f %s | taban %.2f%s%s",
                                   equity_gain,InpCloseAllAtEquityGain,
                                   AccountInfoString(ACCOUNT_CURRENCY),
                                   g_profit_target_start_equity,
                                   rebound_text,
                                   (g_profit_target_liquidating ? " (pozisyonlar kapatılıyor)" : ""));
     }

   string rotation_status = (InpRotateOldestAtLimit ? "açık (en eski pozisyon yenilenir)" : "kapalı (sınırda giriş atlanır)");
   Comment("Dipli Tepeli Auto Grid v1.11 — TradingView Teknik Özet\n",
           "Sembol: ",_Symbol,"\n",
           signal_line,"\n",
           entry_mode,
           "Grid yönü / işlem yönü: ",SideName(g_signal_side)," / ",SideName(TradeSideForSignal(g_signal_side)),
           (InpReverseTradeDirection ? " (ters yön açık)" : ""),"\n",
           "Kural: ",direction_policy," | ",neutral_policy,"\n",
           "Grid base: ",DoubleToString(g_grid_base,_Digits)," | anlık: ",DoubleToString(current_price,_Digits),"\n",
           "Sabit adım: ",DoubleToString(g_grid_step,_Digits)," (",DoubleToString(step_points,1)," point / ",
           DoubleToString(step_pips,2)," pip) | TP ",
           IntegerToString(InpTakeProfitGrids)," grid / SL ",IntegerToString(InpStopLossGrids)," grid\n",
           "Pozisyon LONG/SHORT: ",IntegerToString(long_count)," / ",IntegerToString(short_count),
           " | Sınır/yan: ",IntegerToString(InpMaxLayersPerSide),
           " | Toplam sınır: ",IntegerToString(InpMaxTotalPositions),"\n",
           "Sınır rotasyonu: ",rotation_status,"\n",
           target_status,"\n",
           "Durum: ",g_last_action);
  }

double OnTester()
  {
   double profit = TesterStatistics(STAT_PROFIT);
   double equity_drawdown = TesterStatistics(STAT_EQUITY_DD);
   double initial_deposit = TesterStatistics(STAT_INITIAL_DEPOSIT);
   double trades = TesterStatistics(STAT_TRADES);
   double fitness = profit;

   if(InpUseRiskAdjustedTesterScore)
     {
      if(InpOptimizationMinTrades > 0 && trades < InpOptimizationMinTrades)
         fitness = -1000000.0 + trades; // Reject small samples so a few lucky trades do not win.
      else
        {
         double drawdown_floor = MathMax(initial_deposit * 0.005,0.01);
         fitness = profit / MathMax(equity_drawdown,drawdown_floor);
        }
     }

   // In optimization mode, use the Optimization Results table to rank passes.
   // Print one detailed line for a single backtest run (not once per optimizer pass).
   if(!MQLInfoInteger(MQL_OPTIMIZATION))
      PrintFormat("Tester fitness=%.6f netProfit=%.2f equityDD=%.2f trades=%.0f; gridMultiplier=%.2f TP=%d SL=%d reverse=%s signal=%s/%s flip=%s neutral=%s",
                  fitness,profit,equity_drawdown,trades,InpGridStepMultiplier,
                  InpTakeProfitGrids,InpStopLossGrids,
                  (InpReverseTradeDirection ? "true" : "false"),
                  SignalModeName(),EnumToString(InpSignalTimeframe),
                  EnumToString(InpOnDirectionFlip),EnumToString(InpOnNeutral));
   return fitness;
  }

int OnInit()
  {
   if(InpGridRangeLookbackBars < 5 || InpGridStepMultiplier <= 0.0 ||
      InpMinSpreadMultiple < 0.0 || InpInitialGridLevels < 1 ||
      InpMaxGridLevels < InpInitialGridLevels || InpTakeProfitGrids < 1 ||
      InpStopLossGrids < 1 || InpMaxLayersPerSide < 0 ||
      InpMaxTotalPositions < 0 || InpMaxSpreadPoints < 0 || InpMaxSpreadGridFraction < 0.0 || InpSignalHistoryBars < 2 ||
      InpDeviationPoints < 0 || InpOptimizationMinTrades < 0 || InpCloseAllAtEquityGain < 0.0 ||
      InpRatingNeutralBound <= 0.0 || InpRatingNeutralBound > 1.0 ||
      InpRatingStrongBound < InpRatingNeutralBound || InpRatingStrongBound > 1.0 ||
      InpRatingConfirmBars < 1 || InpRatingLiveRefreshSeconds < 1 ||
      InpMacdFastLength < 1 || InpMacdSlowLength <= InpMacdFastLength ||
      InpMacdSignalLength < 1 || InpMacdHistoryBars < 10)
     {
      Print("Hatalı girdiler: grid/sinyal/MACD/TP/SL sınırlarını kontrol edin (MACD hızlı EMA < yavaş EMA olmalı).");
      return INIT_PARAMETERS_INCORRECT;
     }

   // Teknik özet için yeterli mum şart; az istenirse otomatik yükseltilir.
   if(InpSignalMode == SIGNAL_TECHNICAL_SUMMARY && InpRatingHistoryBars < TV_MIN_BARS)
      PrintFormat("Teknik özet mum sayısı %d -> %d olarak yükseltildi (EMA200 + Ichimoku yakınsaması için).",
                  InpRatingHistoryBars,TV_MIN_BARS);

   TvInitComponentNames();

   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      Print("EA başlatılamadı: ayrı katman TP/SL ve aynı anda LONG+SHORT için hedging hesap gerekir.");
      return INIT_FAILED;
     }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetAsyncMode(false);
   trade.SetTypeFillingBySymbol(_Symbol);

   string object_tag = StringFormat("M1AG_%I64u_%I64u_%s_",InpMagicNumber,(ulong)HashSymbol(_Symbol),RunModeTag());
   g_grid_object_prefix = object_tag;
   if(InpResetGridOnInit)
      DeleteOwnGridObjects();

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick))
     {
      Print("EA başlatılamadı: sembol için fiyat tiki alınamıyor.");
      return INIT_FAILED;
     }
   double startup_price = MidPrice(tick);
   if(startup_price <= 0.0)
     {
      Print("EA başlatılamadı: geçersiz başlangıç fiyatı.");
      return INIT_FAILED;
     }

   if(!LoadOrCreateGrid(startup_price))
      return INIT_FAILED;
   if(!InitializeGridState(startup_price))
     {
      Print("Grid hafızası oluşturulamadı.");
      return INIT_FAILED;
     }

   LoadProfitTargetState();
   RefreshSignal(true);
   EventSetTimer(1);

   if(InpSignalMode == SIGNAL_TECHNICAL_SUMMARY)
      PrintFormat("EA hazır: %s base=%.*f step=%.*f | TradingView Teknik Özet %s (%s): %s puan=%s | sinyal yonu=%s islem yonu=%s; TP=%d SL=%d hedging",
                  _Symbol,_Digits,g_grid_base,_Digits,g_grid_step,
                  EnumToString(InpSignalTimeframe),RatingGroupName(),
                  RatingStatusName(g_rating_status),RatingValueText(RatingValueForGroup()),
                  SideName(g_signal_side),SideName(TradeSideForSignal(g_signal_side)),
                  InpTakeProfitGrids,InpStopLossGrids);
   else
      PrintFormat("EA hazır: %s base=%.*f step=%.*f signal=%s %s trade=%s; TP=%d SL=%d hedging",
                  _Symbol,_Digits,g_grid_base,_Digits,g_grid_step,
                  SignalModeName(),SideName(g_signal_side),SideName(TradeSideForSignal(g_signal_side)),
                  InpTakeProfitGrids,InpStopLossGrids);

   if(InpSignalMode == SIGNAL_TECHNICAL_SUMMARY)
     {
      PrintFormat("Teknik özet ayarları: %s | %s | %s | geçmiş=%d mum | onay mumu=%d | nötr bandı=%.2f güçlü bandı=%.2f",
                  (InpRatingUseClosedBar ? "kapanmış mum (repaint yok)" : "oluşan mum (canlı ibre)"),
                  (InpRatingVolumeSource == RATING_VOLUME_REAL ? "gerçek hacim" : "tick hacmi"),
                  RatingGroupName(),InpRatingHistoryBars,InpRatingConfirmBars,
                  InpRatingNeutralBound,InpRatingStrongBound);
      Print("Teknik özet NÖTR iken yeni giriş açılmaz; ibre AL/GÜÇLÜ AL ise LONG yönlü, SAT/GÜÇLÜ SAT ise SHORT yönlü grid kurulur (ters yön girdisi açıksa yönler tersine döner).");
      switch(InpOnDirectionFlip)
        {
         case DIRECTION_CLOSE_ALL:
            Print("Yön değişimi: ibre ters yöne dönünce bu EA'nın TÜM pozisyonları kapatılır, grid yeni yönde kurulur.");
            break;
         case DIRECTION_KEEP_OPEN:
            Print("Yön değişimi: açık pozisyonlar KORUNUR (kapatma yok); yalnız yeni girişler yeni yönde açılır.");
            break;
         default:
            Print("Yön değişimi: ibre ters yöne dönünce yeni yönün TERSİNDEKİ pozisyonlar kapatılır, grid yeni yönde kurulur.");
            break;
        }
      if(InpOnNeutral == NEUTRAL_CLOSE_ALL)
         Print("Nötr: ibre NÖTR'e geçince bu EA'nın tüm pozisyonları kapatılır ve nötr boyunca yeni giriş açılmaz.");
      else
         Print("Nötr: açık pozisyonlar korunur, yalnız yeni giriş açılmaz.");
      if(InpRebaseGridOnDirectionChange)
         Print("Yön değişiminde grid anlık fiyattan yeniden kurulur (base + taze adım + çizgiler).");
     }
   else
      Print("Grid koordinatları ve hesaplanan adım sabit kalır. Çizgi rengi mum yönünü gösterir; ters yön girdisi işlem yönünü tersine çevirir.");
   if(InpUseMacdSignalEntries)
      PrintFormat("MACD giriş modu AÇIK (%s %d/%d/%d): girişler YALNIZ güçlü sinyallerden (kapanmış mumda crossover+macd>0 / crossunder+macd<0); grid geçiş girişleri ve ibre kaynaklı kapatmalar kapalı, çıkışlar grid TP/SL ile.",
                  EnumToString(InpMacdTimeframe),InpMacdFastLength,InpMacdSlowLength,InpMacdSignalLength);
   if(InpRotateOldestAtLimit)
      PrintFormat("Pozisyon sınırı rotasyonu etkin: yan sınırı=%d toplam sınırı=%d. Sınır dolduğunda aynı yöndeki en eski pozisyon kapatılıp yeni seviyeden taze giriş açılacak.",
                  InpMaxLayersPerSide,InpMaxTotalPositions);
   else
      Print("Pozisyon sınırı rotasyonu kapalı: sınır dolduğunda yeni giriş atlanır.");
   if(InpCloseAllAtEquityGain > 0.0)
      PrintFormat("Özsermaye kâr hedefi etkin: başlangıç=%.2f hedef=%.2f %s",
                  g_profit_target_start_equity,InpCloseAllAtEquityGain,
                  AccountInfoString(ACCOUNT_CURRENCY));
   if(InpEquityTargetRebaseOnLow)
      Print("Dip takibi etkin: her yeni özsermaye dibinde hedef tabanı dibe çekilir; dipten hedef tutarı kadar yükselişte tüm pozisyonlar kapanıp döngü sıfırdan başlar.");
   UpdateChartStatus();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   DeleteOwnGridObjects();
   Comment("");
  }

void OnTimer()
  {
   RefreshSignal(false);
   ProcessMacdEntries();
   HandleEquityProfitTarget();
   UpdateChartStatus();
   // Touch saved grid globals while the EA is active so MT5 keeps them current.
   if(g_grid_base > 0.0 && g_grid_step > 0.0)
     {
      GlobalVariableSet(GridStateKey("BASE"),g_grid_base);
      GlobalVariableSet(GridStateKey("STEP"),g_grid_step);
      if(!MQLInfoInteger(MQL_TESTER) && g_profit_target_start_equity > 0.0)
        {
         GlobalVariableSet(GridStateKey("PTBASE"),g_profit_target_start_equity);
         GlobalVariableSet(GridStateKey("PTAMT"),InpCloseAllAtEquityGain);
         GlobalVariableSet(GridStateKey("PTLIQ"),(g_profit_target_liquidating ? 1.0 : 0.0));
         GlobalVariableSet(GridStateKey("PTLOW"),(InpEquityTargetRebaseOnLow ? 1.0 : 0.0));
        }
      datetime now = TimeCurrent();
      if(g_last_state_flush == 0 || now - g_last_state_flush >= 30)
        {
         GlobalVariablesFlush();
         g_last_state_flush = now;
        }
     }
  }

void OnTick()
  {
   MqlTick tick;
   if(!SymbolInfoTick(_Symbol,tick) || tick.bid <= 0.0 || tick.ask <= 0.0)
      return;

   RefreshSignal(false);
   if(HandleEquityProfitTarget())
     {
      UpdateChartStatus();
      return;
     }
   ProcessMacdEntries();
   ManageOpenPositions(tick);
   double grid_price = MidPrice(tick);
   if(grid_price > 0.0)
      ProcessGridCrosses(grid_price);
   UpdateChartStatus();
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;
   if(HistoryDealGetString(trans.deal,DEAL_SYMBOL) != _Symbol ||
      (ulong)HistoryDealGetInteger(trans.deal,DEAL_MAGIC) != InpMagicNumber)
      return;

   long entry_kind = HistoryDealGetInteger(trans.deal,DEAL_ENTRY);
   if(entry_kind != DEAL_ENTRY_OUT && entry_kind != DEAL_ENTRY_OUT_BY && entry_kind != DEAL_ENTRY_INOUT)
      return;

   ulong identifier = (ulong)HistoryDealGetInteger(trans.deal,DEAL_POSITION_ID);
   bool still_open = false;
   for(int i=PositionsTotal()-1; i>=0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket > 0 && PositionSelectByTicket(ticket) &&
         (ulong)PositionGetInteger(POSITION_IDENTIFIER) == identifier)
        {
         still_open = true;
         break;
        }
     }
   if(!still_open && identifier > 0)
      DeletePositionSettings(identifier);
  }

//+------------------------------------------------------------------+
//|                                           SqueezeMomentum_LB_EA.mq5 |
//|        Squeeze Momentum Indicator [LazyBear] -> MT5 Expert Advisor  |
//|                                                                  |
//|  RENK KODLARI: 0=Herhangi bir renk, 1=Açık yeşil (lime),         |
//|  2=Koyu yeşil (green), 3=Açık kırmızı (red), 4=Bordo (maroon).   |
//|                                                                  |
//|  GİRİŞ: BUY ve SELL için ayrı "önceki renk -> yeni renk" geçişi  |
//|  seçilir. Örn. BUY: kırmızı -> yeşil, SELL: yeşil -> açık kırmızı.|
//|  ÇIKIŞ: BUY/SELL pozisyonların TP ve SL kuralları da ayrı renk   |
//|  geçişi, geçiş adedi ve giriş fiyatına göre koşulla seçilir.     |
//|  Varsayılanlar önceki sürümle aynıdır: BUY girişi red->maroon,   |
//|  SELL girişi lime->green; TP aynı yönlü geçiş, SL ters geçiş.    |
//|                                                                  |
//|  OTOMATİK SEÇİM açıkken her dakika başı, belirlenen geriye       |
//|  dönük pencerede renk geçişi çiftleri sanal olarak test edilir;  |
//|  en iyi skora sahip BUY/SELL çifti girişlerde ve (bağlı olarak)  |
//|  çıkış geçişlerinde yeni işlemler için otomatik uygulanır.       |
//|                                                                  |
//|  NOT: TP/SL sinyal sayımıyla çalıştığı için bunlar sabit fiyat   |
//|  emri olarak brokera gönderilmez; sayım dolunca EA pozisyonu     |
//|  piyasadan kapatır. Bu yüzden EA'nın açık kalması gerekir.       |
//|  İsterseniz ek güvenlik için sabit TP/SL (point) de tanımlanabilir.  |
//+------------------------------------------------------------------+
#property copyright "Squeeze Momentum [LazyBear] - MT5 EA"
#property version   "1.10"
#property strict
#property description "Squeeze Momentum [LazyBear]: giriş/çıkış renk geçişi kuralları tamamen özelleştirilebilir"
#property description "Otomatik mod: her dakika geriye dönük pencerede en iyi BUY/SELL renk geçişi çiftini seçer"
#property description "Ters işlem ayarı: BUY geçişi SELL, SELL geçişi BUY açar (açık/kapalı seçilebilir)"

#include <Trade/Trade.mqh>

CTrade trade;

//+------------------------------------------------------------------+
//| Tipler                                                           |
//+------------------------------------------------------------------+
enum ENUM_SQZ_BAR_COLOR
  {
   SQZ_COLOR_NONE   = 0, // Hesaplanamadı / veri yetersiz
   SQZ_COLOR_LIME   = 1, // Açık yeşil : val > 0 ve yükseliyor
   SQZ_COLOR_GREEN  = 2, // Koyu yeşil : val > 0 ve düşüyor
   SQZ_COLOR_RED    = 3, // Kırmızı    : val < 0 ve düşüyor
   SQZ_COLOR_MAROON = 4  // Bordo      : val < 0 ve yükseliyor
  };

enum ENUM_SQZ_STATE
  {
   SQZ_STATE_UNKNOWN = 0, // Bilinmiyor (veri yetersiz)
   SQZ_STATE_ON      = 1, // sqzOn  : sıkışma var
   SQZ_STATE_OFF     = 2, // sqzOff : sıkışma çözülmüş
   SQZ_STATE_NONE    = 3  // noSqz  : ikisi de değil
  };

enum ENUM_SQZ_COLOR_SELECT
  {
   SQZ_SELECT_ANY    = 0, // Herhangi bir renk
   SQZ_SELECT_LIME   = 1, // Açık yeşil (lime)
   SQZ_SELECT_GREEN  = 2, // Koyu yeşil (green)
   SQZ_SELECT_RED    = 3, // Açık kırmızı (red)
   SQZ_SELECT_MAROON = 4  // Bordo / koyu kırmızı (maroon)
  };

enum ENUM_SQZ_EXIT_PRICE
  {
   SQZ_EXIT_PRICE_ANY          = 0, // Fiyat koşulu yok
   SQZ_EXIT_PRICE_ABOVE_ENTRY  = 1, // Sinyal fiyatı girişin üstünde
   SQZ_EXIT_PRICE_BELOW_ENTRY  = 2  // Sinyal fiyatı girişin altında
  };

enum ENUM_SQZ_AUTO_SCORE
  {
   AUTO_SCORE_NET_POINTS        = 0, // Net puan (point)
   AUTO_SCORE_PROFIT_FACTOR     = 1, // Kâr faktörü
   AUTO_SCORE_WIN_RATE          = 2, // Kazanma oranı (%)
   AUTO_SCORE_AVG_POINTS        = 3, // İşlem başına ortalama puan
   AUTO_SCORE_NET_PER_DRAWDOWN  = 4  // Net puan / maksimum düşüş
  };

struct SQZEntryRule
  {
   bool                  enabled;
   ENUM_SQZ_COLOR_SELECT from_color;
   ENUM_SQZ_COLOR_SELECT to_color;
  };

struct SQZExitRule
  {
   bool                  enabled;
   ENUM_SQZ_COLOR_SELECT from_color;
   ENUM_SQZ_COLOR_SELECT to_color;
   int                   signal_count;
   ENUM_SQZ_EXIT_PRICE   price_condition;
  };

struct SQZStrategyConfig
  {
   SQZEntryRule buy_entry;
   SQZEntryRule sell_entry;
   SQZExitRule  buy_take_profit;
   SQZExitRule  buy_stop_loss;
   SQZExitRule  sell_take_profit;
   SQZExitRule  sell_stop_loss;
  };

struct SQZPositionConfigSnapshot
  {
   ulong             identifier;
   SQZStrategyConfig config;
  };

//+------------------------------------------------------------------+
//| Giriş parametreleri                                              |
//+------------------------------------------------------------------+
input group "1) Squeeze Momentum [LazyBear] ayarları"
input ENUM_TIMEFRAMES InpTimeframe          = PERIOD_CURRENT; // İşlem zaman dilimi (PERIOD_CURRENT = grafik TF)
input int             InpBBLength           = 20;             // BB Length
input double          InpBBMultFactor       = 2.0;            // BB MultFactor
input int             InpKCLength           = 20;             // KC Length
input double          InpKCMultFactor       = 1.5;            // KC MultFactor
input bool            InpUseTrueRange       = true;           // Use TrueRange (KC)
input int             InpHistoryBars        = 5000;           // Taranacak maksimum mum sayısı (sinyal + çıkış sayımı)

input group "2) Giriş renk geçişleri (0=Herhangi, 1=Açık Yeşil, 2=Koyu Yeşil, 3=Açık Kırmızı, 4=Bordo)"
input bool                  InpReverseTrading     = false; // TERS İŞLEM: true = BUY geçişi SELL, SELL geçişi BUY açar
input bool                  InpBuyEntryEnabled    = true;  // BUY giriş kuralı açık
input ENUM_SQZ_COLOR_SELECT InpBuyEntryFromColor  = SQZ_SELECT_RED;    // BUY girişi: önceki çubuk rengi
input ENUM_SQZ_COLOR_SELECT InpBuyEntryToColor    = SQZ_SELECT_MAROON; // BUY girişi: yeni çubuk rengi
input bool                  InpSellEntryEnabled   = true;  // SELL giriş kuralı açık
input ENUM_SQZ_COLOR_SELECT InpSellEntryFromColor = SQZ_SELECT_LIME;   // SELL girişi: önceki çubuk rengi
input ENUM_SQZ_COLOR_SELECT InpSellEntryToColor   = SQZ_SELECT_GREEN;  // SELL girişi: yeni çubuk rengi
input bool                  InpAllowLongTrades    = true;  // BUY pozisyon açmaya izin ver
input bool                  InpAllowShortTrades   = true;  // SELL pozisyon açmaya izin ver
input bool                  InpDrawSignalArrows   = true;  // Grafikte sinyal okları çiz
input bool                  InpShowChartInfo      = true;  // Grafikte bilgi paneli göster

input group "3) BUY pozisyon çıkışları - renk geçişi (adet 0 ise kural kapalı)"
input bool                  InpBuyTakeProfitEnabled       = true; // BUY TP kuralı açık
input ENUM_SQZ_COLOR_SELECT InpBuyTakeProfitFromColor     = SQZ_SELECT_RED;    // BUY TP: önceki renk
input ENUM_SQZ_COLOR_SELECT InpBuyTakeProfitToColor       = SQZ_SELECT_MAROON; // BUY TP: yeni renk
input int                   InpBuyTakeProfitSignalCount   = 3;    // BUY TP: kaçıncı uygun geçişte kapat?
input ENUM_SQZ_EXIT_PRICE   InpBuyTakeProfitPriceCondition = SQZ_EXIT_PRICE_ABOVE_ENTRY; // BUY TP fiyat koşulu
input bool                  InpBuyStopLossEnabled         = true; // BUY SL kuralı açık
input ENUM_SQZ_COLOR_SELECT InpBuyStopLossFromColor       = SQZ_SELECT_LIME;   // BUY SL: önceki renk
input ENUM_SQZ_COLOR_SELECT InpBuyStopLossToColor         = SQZ_SELECT_GREEN;  // BUY SL: yeni renk
input int                   InpBuyStopLossSignalCount     = 3;    // BUY SL: kaçıncı uygun geçişte kapat?
input ENUM_SQZ_EXIT_PRICE   InpBuyStopLossPriceCondition  = SQZ_EXIT_PRICE_BELOW_ENTRY; // BUY SL fiyat koşulu

input group "4) SELL pozisyon çıkışları - renk geçişi (adet 0 ise kural kapalı)"
input bool                  InpSellTakeProfitEnabled       = true; // SELL TP kuralı açık
input ENUM_SQZ_COLOR_SELECT InpSellTakeProfitFromColor     = SQZ_SELECT_LIME;   // SELL TP: önceki renk
input ENUM_SQZ_COLOR_SELECT InpSellTakeProfitToColor       = SQZ_SELECT_GREEN;  // SELL TP: yeni renk
input int                   InpSellTakeProfitSignalCount   = 3;    // SELL TP: kaçıncı uygun geçişte kapat?
input ENUM_SQZ_EXIT_PRICE   InpSellTakeProfitPriceCondition = SQZ_EXIT_PRICE_BELOW_ENTRY; // SELL TP fiyat koşulu
input bool                  InpSellStopLossEnabled         = true; // SELL SL kuralı açık
input ENUM_SQZ_COLOR_SELECT InpSellStopLossFromColor       = SQZ_SELECT_RED;    // SELL SL: önceki renk
input ENUM_SQZ_COLOR_SELECT InpSellStopLossToColor         = SQZ_SELECT_MAROON; // SELL SL: yeni renk
input int                   InpSellStopLossSignalCount     = 3;    // SELL SL: kaçıncı uygun geçişte kapat?
input ENUM_SQZ_EXIT_PRICE   InpSellStopLossPriceCondition  = SQZ_EXIT_PRICE_ABOVE_ENTRY; // SELL SL fiyat koşulu

input group "5) Otomatik ayar seçimi (her dakika geriye dönük sanal test)"
input bool                  InpAutoSelectSettings          = false; // OTOMATİK SEÇİM: true = en iyi renk geçişi çiftini uygula
input int                   InpAutoLookbackMinutes         = 60;    // Geriye dönük test süresi (dakika) - örn. 60 = son 1 saat
input ENUM_SQZ_AUTO_SCORE   InpAutoScoreMode               = AUTO_SCORE_NET_PER_DRAWDOWN; // Başarı ölçütü
input int                   InpAutoMinTrades               = 3;     // Seçim için testte minimum işlem sayısı
input int                   InpAutoMinBars                 = 20;    // Test için minimum kapalı mum sayısı
input bool                  InpAutoRequirePositiveResult   = true;  // true: net sonucu pozitif olmayan aday seçilmez
input bool                  InpAutoOptimizeExitCounts      = true;  // TP/SL geçiş adetlerini de test et
input bool                  InpAutoOptimizeIndependentExits = true;  // 4 çıkış geçişini de ayrıca optimize et (koordinat arama)
input int                   InpAutoMaxExitCount            = 3;     // Test edilecek maksimum TP/SL adedi (1..bu değer)
input double                InpAutoCostPointsPerRoundTrip  = 0.0;   // Sanal testte işlem başına toplam maliyet (point)
input bool                  InpAutoApplyToOpenPositions    = false; // true: otomatik ayar açık pozisyonlara da uygulanır; false: pozisyon açılış ayarlarıyla devam eder

input group "6) Pozisyon ve emir"
input int                   InpFixedTakeProfitPoints = 0;  // Ekstra sabit TP (point) - 0 = kapalı
input int                   InpFixedStopLossPoints   = 0;  // Ekstra sabit SL (point) - 0 = kapalı
input double                InpLotSize               = 0.01;      // Lot
input ulong                 InpMagicNumber           = 20261019;  // Magic Number
input int                   InpDeviationPoints       = 20;        // Maksimum sapma (point)
input int                   InpMaxSpreadPoints       = 0;         // Maksimum spread (point) - 0 = kapalı
input int                   InpMaxOpenPositions      = 0;         // Aynı anda maks. pozisyon - 0 = sınırsız
input bool                  InpRequireHedgingAccount = true;     // Hedging hesap zorunlu olsun mu?
input bool                  InpDeleteArrowsOnExit    = true;     // EA kapanırken sinyal oklarını sil

//+------------------------------------------------------------------+
//| Global durum                                                     |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES g_timeframe           = PERIOD_CURRENT;
datetime        g_last_bar_time       = 0;
int             g_last_raw_signal     = 0;      // +1 BUY sinyali, -1 SELL sinyali
datetime        g_last_signal_time    = 0;
double          g_last_signal_price   = 0.0;
double          g_last_momentum       = 0.0;
ENUM_SQZ_BAR_COLOR g_last_bar_color   = SQZ_COLOR_NONE;
ENUM_SQZ_BAR_COLOR g_prev_bar_color   = SQZ_COLOR_NONE;
ENUM_SQZ_STATE     g_last_sqz_state   = SQZ_STATE_UNKNOWN;
string          g_last_action         = "Başlatılıyor";
string          g_object_prefix       = "";
SQZStrategyConfig g_manual_config;
SQZStrategyConfig g_active_config;
SQZPositionConfigSnapshot g_position_configs[];
bool            g_auto_selection_ready = false;
datetime        g_auto_last_test_minute = 0;
datetime        g_auto_attempt_minute = 0;
datetime        g_auto_retry_after = 0;
datetime        g_auto_window_start = 0;
datetime        g_auto_window_end = 0;
string          g_auto_status = "Kapalı";
double          g_auto_best_score = 0.0;
double          g_auto_best_net_points = 0.0;
int             g_auto_best_trades = 0;

//+------------------------------------------------------------------+
//| Yardımcılar                                                      |
//+------------------------------------------------------------------+
ENUM_TIMEFRAMES WorkingTimeframe()
  {
   if(InpTimeframe == PERIOD_CURRENT)
      return (ENUM_TIMEFRAMES)Period();
   return InpTimeframe;
  }

double TickSize()
  {
   double size = SymbolInfoDouble(_Symbol, SYMBOL_TRADE_TICK_SIZE);
   if(size <= 0.0)
      size = _Point;
   return size;
  }

double NormalizePriceToTick(const double price, const int round_direction)
  {
   // round_direction: +1 yukarı, -1 aşağı, 0 en yakına yuvarla
   double tick = TickSize();
   if(price <= 0.0 || tick <= 0.0)
      return NormalizeDouble(price, _Digits);
   double units = price / tick;
   if(round_direction > 0)
      units = MathCeil(units - 1.0e-10);
   else if(round_direction < 0)
      units = MathFloor(units + 1.0e-10);
   else
      units = MathRound(units);
   return NormalizeDouble(units * tick, _Digits);
  }

double NormalizeVolume(const double requested)
  {
   double min_volume  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MIN);
   double max_volume  = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_MAX);
   double volume_step = SymbolInfoDouble(_Symbol, SYMBOL_VOLUME_STEP);
   if(min_volume <= 0.0 || volume_step <= 0.0)
      return 0.0;

   double volume = requested;
   if(max_volume > 0.0 && volume > max_volume)
      volume = max_volume;
   volume = MathFloor(volume / volume_step + 1.0e-10) * volume_step;
   volume = NormalizeDouble(volume, 8);
   if(volume < min_volume - 1.0e-10)
     {
      PrintFormat("Lot atlandı: istenen %.8f broker minimumu %.8f altında.", requested, min_volume);
      return 0.0;
     }
   return volume;
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

int SideFromPositionType(const long type)
  {
   if(type == POSITION_TYPE_BUY)
      return 1;
   if(type == POSITION_TYPE_SELL)
      return -1;
   return 0;
  }

string SideName(const int side)
  {
   if(side > 0)
      return "BUY";
   if(side < 0)
      return "SELL";
   return "YOK";
  }

string ColorName(const ENUM_SQZ_BAR_COLOR clr);

ENUM_SQZ_BAR_COLOR ColorFromSelect(const ENUM_SQZ_COLOR_SELECT selected)
  {
   switch(selected)
     {
      case SQZ_SELECT_LIME:   return SQZ_COLOR_LIME;
      case SQZ_SELECT_GREEN:  return SQZ_COLOR_GREEN;
      case SQZ_SELECT_RED:    return SQZ_COLOR_RED;
      case SQZ_SELECT_MAROON: return SQZ_COLOR_MAROON;
      default:                return SQZ_COLOR_NONE;
     }
  }

string ColorSelectName(const ENUM_SQZ_COLOR_SELECT selected)
  {
   if(selected == SQZ_SELECT_ANY)
      return "Herhangi bir renk";
   return ColorName(ColorFromSelect(selected));
  }

string TransitionText(const ENUM_SQZ_COLOR_SELECT from_color,
                      const ENUM_SQZ_COLOR_SELECT to_color)
  {
   return ColorSelectName(from_color) + " -> " + ColorSelectName(to_color);
  }

string EntryRuleText(const SQZEntryRule &rule)
  {
   if(!rule.enabled)
      return "kapalı";
   return TransitionText(rule.from_color, rule.to_color);
  }

string PriceConditionName(const ENUM_SQZ_EXIT_PRICE condition)
  {
   switch(condition)
     {
      case SQZ_EXIT_PRICE_ABOVE_ENTRY: return "sinyal fiyatı girişin üstünde";
      case SQZ_EXIT_PRICE_BELOW_ENTRY: return "sinyal fiyatı girişin altında";
      default:                         return "fiyat koşulu yok";
     }
  }

string ExitRuleText(const SQZExitRule &rule)
  {
   if(!rule.enabled || rule.signal_count <= 0)
      return "kapalı";
   return StringFormat("%s (adet: %d, %s)",
                       TransitionText(rule.from_color, rule.to_color),
                       rule.signal_count, PriceConditionName(rule.price_condition));
  }

// Ayar yapısının alanlarını tek listeden okumak/yazmak; pozisyon
// anlık ayarlarını saklamak ve iki ayarı karşılaştırmak için kullanılır.
double ConfigFieldValue(const SQZStrategyConfig &config, const int field)
  {
   switch(field)
     {
      case 0:  return config.buy_entry.enabled ? 1.0 : 0.0;
      case 1:  return (double)config.buy_entry.from_color;
      case 2:  return (double)config.buy_entry.to_color;
      case 3:  return config.sell_entry.enabled ? 1.0 : 0.0;
      case 4:  return (double)config.sell_entry.from_color;
      case 5:  return (double)config.sell_entry.to_color;
      case 6:  return config.buy_take_profit.enabled ? 1.0 : 0.0;
      case 7:  return (double)config.buy_take_profit.from_color;
      case 8:  return (double)config.buy_take_profit.to_color;
      case 9:  return (double)config.buy_take_profit.signal_count;
      case 10: return (double)config.buy_take_profit.price_condition;
      case 11: return config.buy_stop_loss.enabled ? 1.0 : 0.0;
      case 12: return (double)config.buy_stop_loss.from_color;
      case 13: return (double)config.buy_stop_loss.to_color;
      case 14: return (double)config.buy_stop_loss.signal_count;
      case 15: return (double)config.buy_stop_loss.price_condition;
      case 16: return config.sell_take_profit.enabled ? 1.0 : 0.0;
      case 17: return (double)config.sell_take_profit.from_color;
      case 18: return (double)config.sell_take_profit.to_color;
      case 19: return (double)config.sell_take_profit.signal_count;
      case 20: return (double)config.sell_take_profit.price_condition;
      case 21: return config.sell_stop_loss.enabled ? 1.0 : 0.0;
      case 22: return (double)config.sell_stop_loss.from_color;
      case 23: return (double)config.sell_stop_loss.to_color;
      case 24: return (double)config.sell_stop_loss.signal_count;
      case 25: return (double)config.sell_stop_loss.price_condition;
      default: return 0.0;
     }
  }

void SetConfigFieldValue(SQZStrategyConfig &config, const int field, const double value)
  {
   int int_value = (int)MathRound(value);
   switch(field)
     {
      case 0:  config.buy_entry.enabled = (value > 0.5); break;
      case 1:  config.buy_entry.from_color = (ENUM_SQZ_COLOR_SELECT)int_value; break;
      case 2:  config.buy_entry.to_color = (ENUM_SQZ_COLOR_SELECT)int_value; break;
      case 3:  config.sell_entry.enabled = (value > 0.5); break;
      case 4:  config.sell_entry.from_color = (ENUM_SQZ_COLOR_SELECT)int_value; break;
      case 5:  config.sell_entry.to_color = (ENUM_SQZ_COLOR_SELECT)int_value; break;
      case 6:  config.buy_take_profit.enabled = (value > 0.5); break;
      case 7:  config.buy_take_profit.from_color = (ENUM_SQZ_COLOR_SELECT)int_value; break;
      case 8:  config.buy_take_profit.to_color = (ENUM_SQZ_COLOR_SELECT)int_value; break;
      case 9:  config.buy_take_profit.signal_count = int_value; break;
      case 10: config.buy_take_profit.price_condition = (ENUM_SQZ_EXIT_PRICE)int_value; break;
      case 11: config.buy_stop_loss.enabled = (value > 0.5); break;
      case 12: config.buy_stop_loss.from_color = (ENUM_SQZ_COLOR_SELECT)int_value; break;
      case 13: config.buy_stop_loss.to_color = (ENUM_SQZ_COLOR_SELECT)int_value; break;
      case 14: config.buy_stop_loss.signal_count = int_value; break;
      case 15: config.buy_stop_loss.price_condition = (ENUM_SQZ_EXIT_PRICE)int_value; break;
      case 16: config.sell_take_profit.enabled = (value > 0.5); break;
      case 17: config.sell_take_profit.from_color = (ENUM_SQZ_COLOR_SELECT)int_value; break;
      case 18: config.sell_take_profit.to_color = (ENUM_SQZ_COLOR_SELECT)int_value; break;
      case 19: config.sell_take_profit.signal_count = int_value; break;
      case 20: config.sell_take_profit.price_condition = (ENUM_SQZ_EXIT_PRICE)int_value; break;
      case 21: config.sell_stop_loss.enabled = (value > 0.5); break;
      case 22: config.sell_stop_loss.from_color = (ENUM_SQZ_COLOR_SELECT)int_value; break;
      case 23: config.sell_stop_loss.to_color = (ENUM_SQZ_COLOR_SELECT)int_value; break;
      case 24: config.sell_stop_loss.signal_count = int_value; break;
      case 25: config.sell_stop_loss.price_condition = (ENUM_SQZ_EXIT_PRICE)int_value; break;
      default: break;
     }
  }

bool ConfigEquals(const SQZStrategyConfig &left, const SQZStrategyConfig &right)
  {
   for(int field = 0; field < 26; field++)
     {
      if(ConfigFieldValue(left, field) != ConfigFieldValue(right, field))
         return false;
     }
   return true;
  }

SQZStrategyConfig BuildManualConfig()
  {
   SQZStrategyConfig config;
   config.buy_entry.enabled = InpBuyEntryEnabled;
   config.buy_entry.from_color = InpBuyEntryFromColor;
   config.buy_entry.to_color = InpBuyEntryToColor;
   config.sell_entry.enabled = InpSellEntryEnabled;
   config.sell_entry.from_color = InpSellEntryFromColor;
   config.sell_entry.to_color = InpSellEntryToColor;

   config.buy_take_profit.enabled = InpBuyTakeProfitEnabled;
   config.buy_take_profit.from_color = InpBuyTakeProfitFromColor;
   config.buy_take_profit.to_color = InpBuyTakeProfitToColor;
   config.buy_take_profit.signal_count = InpBuyTakeProfitSignalCount;
   config.buy_take_profit.price_condition = InpBuyTakeProfitPriceCondition;
   config.buy_stop_loss.enabled = InpBuyStopLossEnabled;
   config.buy_stop_loss.from_color = InpBuyStopLossFromColor;
   config.buy_stop_loss.to_color = InpBuyStopLossToColor;
   config.buy_stop_loss.signal_count = InpBuyStopLossSignalCount;
   config.buy_stop_loss.price_condition = InpBuyStopLossPriceCondition;

   config.sell_take_profit.enabled = InpSellTakeProfitEnabled;
   config.sell_take_profit.from_color = InpSellTakeProfitFromColor;
   config.sell_take_profit.to_color = InpSellTakeProfitToColor;
   config.sell_take_profit.signal_count = InpSellTakeProfitSignalCount;
   config.sell_take_profit.price_condition = InpSellTakeProfitPriceCondition;
   config.sell_stop_loss.enabled = InpSellStopLossEnabled;
   config.sell_stop_loss.from_color = InpSellStopLossFromColor;
   config.sell_stop_loss.to_color = InpSellStopLossToColor;
   config.sell_stop_loss.signal_count = InpSellStopLossSignalCount;
   config.sell_stop_loss.price_condition = InpSellStopLossPriceCondition;
   return config;
  }

bool IsImpossibleExactTransition(const ENUM_SQZ_COLOR_SELECT from_color,
                                 const ENUM_SQZ_COLOR_SELECT to_color)
  {
   // Momentum renkleri işaret + yönle tanımlıdır. Negatif taraftan pozitif
   // tarafa geçişte değer yükseldiği için hedef lime olur, green olamaz;
   // pozitiften negatife geçişte değer düştüğü için hedef red olur,
   // maroon olamaz. Bu dört sıralı geçiş doğrudan oluşamaz.
   return (((from_color == SQZ_SELECT_RED || from_color == SQZ_SELECT_MAROON) &&
            to_color == SQZ_SELECT_GREEN) ||
           ((from_color == SQZ_SELECT_LIME || from_color == SQZ_SELECT_GREEN) &&
            to_color == SQZ_SELECT_MAROON));
  }

void ValidateTransitionRule(const bool enabled,
                            const ENUM_SQZ_COLOR_SELECT from_color,
                            const ENUM_SQZ_COLOR_SELECT to_color,
                            const string rule_name)
  {
   if(!enabled)
      return;
   if(from_color != SQZ_SELECT_ANY && from_color == to_color)
      PrintFormat("UYARI: %s için aynı renk seçilmiş (%s). Renk değişimi oluşmayacağı için bu kural tetiklenmez.",
                  rule_name, ColorSelectName(from_color));
   else if(from_color != SQZ_SELECT_ANY && to_color != SQZ_SELECT_ANY &&
           IsImpossibleExactTransition(from_color, to_color))
      PrintFormat("UYARI: %s için seçilen %s geçişi momentum renk tanımı gereği doğrudan oluşamaz. Sıfır çizgisini geçen geçişlerde hedef, yönden dolayı lime/red olur.",
                  rule_name, TransitionText(from_color, to_color));
  }

void ValidateStrategyConfig(const SQZStrategyConfig &config)
  {
   ValidateTransitionRule(config.buy_entry.enabled, config.buy_entry.from_color,
                          config.buy_entry.to_color, "BUY girişi");
   ValidateTransitionRule(config.sell_entry.enabled, config.sell_entry.from_color,
                          config.sell_entry.to_color, "SELL girişi");
   ValidateTransitionRule(config.buy_take_profit.enabled, config.buy_take_profit.from_color,
                          config.buy_take_profit.to_color, "BUY TP");
   ValidateTransitionRule(config.buy_stop_loss.enabled, config.buy_stop_loss.from_color,
                          config.buy_stop_loss.to_color, "BUY SL");
   ValidateTransitionRule(config.sell_take_profit.enabled, config.sell_take_profit.from_color,
                          config.sell_take_profit.to_color, "SELL TP");
   ValidateTransitionRule(config.sell_stop_loss.enabled, config.sell_stop_loss.from_color,
                          config.sell_stop_loss.to_color, "SELL SL");
   if(config.buy_entry.enabled && config.sell_entry.enabled &&
      config.buy_entry.from_color == config.sell_entry.from_color &&
      config.buy_entry.to_color == config.sell_entry.to_color)
      Print("UYARI: BUY ve SELL girişine aynı renk geçişi atanmış. Geçiş oluşursa çakışma nedeniyle giriş atlanır.");
  }

bool EffectiveReverseTrading()
  {
   // Otomatik seçimde seçilen geçişler doğrudan BUY/SELL açılışını temsil
   // eder; bu yüzden manuel ters işlem otomatik seçimden sonra uygulanmaz.
   if(InpAutoSelectSettings && g_auto_selection_ready)
      return false;
   return InpReverseTrading;
  }

bool AnyExitRuleEnabled(const SQZStrategyConfig &config)
  {
   return ((config.buy_take_profit.enabled && config.buy_take_profit.signal_count > 0) ||
           (config.buy_stop_loss.enabled && config.buy_stop_loss.signal_count > 0) ||
           (config.sell_take_profit.enabled && config.sell_take_profit.signal_count > 0) ||
           (config.sell_stop_loss.enabled && config.sell_stop_loss.signal_count > 0));
  }

string ColorName(const ENUM_SQZ_BAR_COLOR clr)
  {
   switch(clr)
     {
      case SQZ_COLOR_LIME:   return "Açık yeşil (lime)";
      case SQZ_COLOR_GREEN:  return "Koyu yeşil (green)";
      case SQZ_COLOR_RED:    return "Açık kırmızı (red)";
      case SQZ_COLOR_MAROON: return "Koyu kırmızı / bordo (maroon)";
      default:               return "hesaplanamadı";
     }
  }

string SqueezeStateName(const ENUM_SQZ_STATE state)
  {
   switch(state)
     {
      case SQZ_STATE_ON:   return "sqzOn (sıkışma var)";
      case SQZ_STATE_OFF:  return "sqzOff (sıkışma yok)";
      case SQZ_STATE_NONE: return "noSqz";
      default:             return "bilinmiyor";
     }
  }

//+------------------------------------------------------------------+
//| Squeeze Momentum hesaplamaları                                   |
//|                                                                  |
//| PineScript karşılığı:                                            |
//|  val = linreg(close - avg(avg(highest(high,KC),lowest(low,KC)),  |
//|                             sma(close,KC)), KC, 0)               |
//+------------------------------------------------------------------+
double LinearRegressionEnd(const double &series[], const int end_index, const int period)
  {
   int start = end_index - period + 1;
   if(start < 0 || period < 2)
      return 0.0;

   double sum_x  = period * (period - 1) / 2.0;
   double sum_x2 = (period - 1) * period * (2 * period - 1) / 6.0;
   double sum_y  = 0.0;
   double sum_xy = 0.0;
   for(int k = 0; k < period; k++)
     {
      double y = series[start + k];
      sum_y  += y;
      sum_xy += k * y;
     }

   double denominator = period * sum_x2 - sum_x * sum_x;
   if(MathAbs(denominator) < 1.0e-12)
      return sum_y / period;

   double slope     = (period * sum_xy - sum_x * sum_y) / denominator;
   double intercept = (sum_y - slope * sum_x) / period;
   // linreg(..., offset=0): doğrunun en son mumdaki değeri
   return intercept + slope * (period - 1);
  }

ENUM_SQZ_BAR_COLOR BarColor(const double value, const double previous_value)
  {
   // PineScript:
   //   bcolor = iff(val > 0, iff(val > nz(val[1]), lime, green),
   //                         iff(val < nz(val[1]), red,  maroon))
   if(value > 0.0)
      return (value > previous_value) ? SQZ_COLOR_LIME : SQZ_COLOR_GREEN;
   return (value < previous_value) ? SQZ_COLOR_RED : SQZ_COLOR_MAROON;
  }

// Mum serisi için momentum değerlerini ve çubuk renklerini hesaplar.
// rates kronolojik sıradadır (0 = en eski). Son index oluşan mumdur.
bool ComputeMomentum(const MqlRates &rates[],
                     double &values[],
                     ENUM_SQZ_BAR_COLOR &colors[],
                     bool &valid[])
  {
   int total = ArraySize(rates);
   if(total <= 0)
      return false;
   if(ArrayResize(values, total) < total ||
      ArrayResize(colors, total) < total ||
      ArrayResize(valid,  total) < total)
      return false;

   ArrayInitialize(values, 0.0);
   for(int i = 0; i < total; i++)
     {
      colors[i] = SQZ_COLOR_NONE;
      valid[i]  = false;
     }

   // 1) x = close - avg(avg(highest(high,KC), lowest(low,KC)), sma(close,KC))
   double detrend[];
   bool   detrend_valid[];
   if(ArrayResize(detrend, total) < total || ArrayResize(detrend_valid, total) < total)
      return false;
   ArrayInitialize(detrend, 0.0);
   for(int i = 0; i < total; i++)
      detrend_valid[i] = false;

   for(int i = InpKCLength - 1; i < total; i++)
     {
      double highest = rates[i].high;
      double lowest  = rates[i].low;
      double sum_close = 0.0;
      for(int j = i - InpKCLength + 1; j <= i; j++)
        {
         highest    = MathMax(highest, rates[j].high);
         lowest     = MathMin(lowest,  rates[j].low);
         sum_close += rates[j].close;
        }
      double sma_close = sum_close / InpKCLength;
      double hl_mid    = (highest + lowest) * 0.5;   // avg(highest, lowest)
      double mid       = (hl_mid + sma_close) * 0.5; // avg(avg(...), sma)
      detrend[i]       = rates[i].close - mid;
      detrend_valid[i] = true;
     }

   // 2) val = linreg(x, KC, 0)
   for(int i = 2 * InpKCLength - 2; i < total; i++)
     {
      bool ready = true;
      for(int j = i - InpKCLength + 1; j <= i; j++)
        {
         if(!detrend_valid[j])
           {
            ready = false;
            break;
           }
        }
      if(!ready)
         continue;
      values[i] = LinearRegressionEnd(detrend, i, InpKCLength);
      valid[i]  = true;
     }

   // 3) Çubuk renkleri (önceki mum yoksa nz(val[1]) = 0 kabul edilir)
   for(int i = 0; i < total; i++)
     {
      if(!valid[i])
         continue;
      double previous_value = (i > 0 && valid[i - 1]) ? values[i - 1] : 0.0;
      colors[i] = BarColor(values[i], previous_value);
     }
   return true;
  }

// Seçilen "önceki renk -> yeni renk" kuralının iki komşu mumda oluşup
// oluşmadığını kontrol eder. ANY (herhangi) yalnız hedef/çıkış rengiyle
// birlikte anlamlıdır; aynı renkte kalmak geçiş sayılmaz.
bool TransitionMatches(const ENUM_SQZ_COLOR_SELECT from_select,
                       const ENUM_SQZ_COLOR_SELECT to_select,
                       const ENUM_SQZ_BAR_COLOR previous_color,
                       const ENUM_SQZ_BAR_COLOR current_color)
  {
   if(previous_color == SQZ_COLOR_NONE || current_color == SQZ_COLOR_NONE)
      return false;

   bool from_any = (from_select == SQZ_SELECT_ANY);
   bool to_any = (to_select == SQZ_SELECT_ANY);
   ENUM_SQZ_BAR_COLOR from_color = ColorFromSelect(from_select);
   ENUM_SQZ_BAR_COLOR to_color = ColorFromSelect(to_select);

   if(!from_any && !to_any)
     {
      if(from_color == to_color)
         return false; // Aynı renk seçimi bir renk değişimi değildir
      return (previous_color == from_color && current_color == to_color);
     }
   if(from_any && !to_any)
      return (current_color == to_color && previous_color != current_color);
   if(!from_any && to_any)
      return (previous_color == from_color && current_color != previous_color);
   return false; // ANY -> ANY geçiş sayılmaz
  }

bool EntryRuleMatches(const SQZEntryRule &rule,
                      const ENUM_SQZ_BAR_COLOR previous_color,
                      const ENUM_SQZ_BAR_COLOR current_color)
  {
   return (rule.enabled &&
           TransitionMatches(rule.from_color, rule.to_color, previous_color, current_color));
  }

bool ExitPriceMatches(const ENUM_SQZ_EXIT_PRICE condition,
                      const double signal_price,
                      const double entry_price)
  {
   if(condition == SQZ_EXIT_PRICE_ABOVE_ENTRY)
      return (signal_price > entry_price);
   if(condition == SQZ_EXIT_PRICE_BELOW_ENTRY)
      return (signal_price < entry_price);
   return true;
  }

bool ExitRuleMatches(const SQZExitRule &rule,
                     const ENUM_SQZ_BAR_COLOR previous_color,
                     const ENUM_SQZ_BAR_COLOR current_color,
                     const double signal_price,
                     const double entry_price)
  {
   return (rule.enabled && rule.signal_count > 0 &&
           TransitionMatches(rule.from_color, rule.to_color, previous_color, current_color) &&
           ExitPriceMatches(rule.price_condition, signal_price, entry_price));
  }

// Kapanmış mumdaki giriş olayını bulur.
// Dönüş: +1 BUY giriş geçişi, -1 SELL giriş geçişi, 0 yok/çakışma.
int EntryEventFromColors(const ENUM_SQZ_BAR_COLOR previous_color,
                         const ENUM_SQZ_BAR_COLOR current_color,
                         const SQZStrategyConfig &config,
                         bool &ambiguous)
  {
   ambiguous = false;
   bool buy_match = EntryRuleMatches(config.buy_entry, previous_color, current_color);
   bool sell_match = EntryRuleMatches(config.sell_entry, previous_color, current_color);
   if(buy_match && sell_match)
     {
      ambiguous = true;
      return 0;
     }
   if(buy_match)
      return 1;
   if(sell_match)
      return -1;
   return 0;
  }

// BB/KC sıkışma durumu (sqzOn/sqzOff/noSqz). Sinyal şartı DEĞİLDİR;
// sadece bilgi panelinde gösterilir (Pine'daki 0 çizgisi noktaları).
ENUM_SQZ_STATE ComputeSqueezeState(const MqlRates &rates[], const int index)
  {
   int needed = (int)MathMax(InpBBLength, InpKCLength);
   if(index < needed - 1)
      return SQZ_STATE_UNKNOWN;

   // Bollinger: basis = sma(close, BB), dev = BB_Mult * stdev(close, BB)
   // NOT: Gönderilen kodda dev satırında multKC yazıyordu; orijinal
   // LazyBear kodunda BB sapması BB MultFactor ile hesaplanır. Bu
   // fark sadece sıkışma durumunu etkiler, momentum çubuklarını ve
   // dolayısıyla sinyalleri etkilemez.
   double basis = 0.0;
   for(int j = index - InpBBLength + 1; j <= index; j++)
      basis += rates[j].close;
   basis /= InpBBLength;

   double variance = 0.0;
   for(int j = index - InpBBLength + 1; j <= index; j++)
     {
      double diff = rates[j].close - basis;
      variance += diff * diff;
     }
   double dev = InpBBMultFactor * MathSqrt(variance / InpBBLength);
   double upper_bb = basis + dev;
   double lower_bb = basis - dev;

   // Keltner: ma = sma(close, KC), rangema = sma(range, KC)
   double ma = 0.0;
   double range_sum = 0.0;
   for(int j = index - InpKCLength + 1; j <= index; j++)
     {
      ma += rates[j].close;
      double range = rates[j].high - rates[j].low;
      if(InpUseTrueRange && j > 0)
        {
         double prev_close = rates[j - 1].close;
         range = MathMax(range, MathMax(MathAbs(rates[j].high - prev_close),
                                        MathAbs(rates[j].low  - prev_close)));
        }
      range_sum += range;
     }
   ma /= InpKCLength;
   double range_ma = range_sum / InpKCLength;
   double upper_kc = ma + range_ma * InpKCMultFactor;
   double lower_kc = ma - range_ma * InpKCMultFactor;

   bool sqz_on  = (lower_bb > lower_kc) && (upper_bb < upper_kc);
   bool sqz_off = (lower_bb < lower_kc) && (upper_bb > upper_kc);
   if(sqz_on)
      return SQZ_STATE_ON;
   if(sqz_off)
      return SQZ_STATE_OFF;
   return SQZ_STATE_NONE;
  }

int LoadRates(MqlRates &rates[])
  {
   int needed = (int)MathMax(InpHistoryBars, (InpKCLength * 4) + 10);
   ArraySetAsSeries(rates, false); // 0 = en eski mum
   int copied = CopyRates(_Symbol, g_timeframe, 0, needed, rates);
   if(copied > 0)
      ArrayResize(rates, copied);
   return copied;
  }

//+------------------------------------------------------------------+
//| Pozisyon yardımcıları                                            |
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

int CountOurPositions(const int side_filter = 0)
  {
   int count = 0;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
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

uint HashText(const string text)
  {
   uint hash = 2166136261;
   for(int i = 0; i < StringLen(text); i++)
     {
      hash ^= (uint)StringGetCharacter(text, i);
      hash *= 16777619;
     }
   return hash;
  }

string PositionConfigKey(const ulong position_id)
  {
   string seed = StringFormat("%I64d_%I64u_%s_%d",
                              AccountInfoInteger(ACCOUNT_LOGIN), InpMagicNumber,
                              _Symbol, (int)g_timeframe);
   return "SQZCFG_" + IntegerToString((long)HashText(seed)) + "_" +
          StringFormat("%I64u", position_id);
  }

void SavePositionConfigGlobals(const ulong position_id, const SQZStrategyConfig &config)
  {
   if(MQLInfoInteger(MQL_TESTER))
      return; // Test çalıştırmalarında bellek içi anlık ayar yeterlidir
   string key = PositionConfigKey(position_id);
   for(int field = 0; field < 26; field++)
      GlobalVariableSet(key + "_F" + IntegerToString(field), ConfigFieldValue(config, field));
   GlobalVariablesFlush();
  }

bool LoadPositionConfigGlobals(const ulong position_id, SQZStrategyConfig &config)
  {
   if(MQLInfoInteger(MQL_TESTER))
      return false;
   string key = PositionConfigKey(position_id);
   for(int field = 0; field < 26; field++)
     {
      if(!GlobalVariableCheck(key + "_F" + IntegerToString(field)))
         return false;
     }
   config = g_active_config;
   for(int field = 0; field < 26; field++)
      SetConfigFieldValue(config, field, GlobalVariableGet(key + "_F" + IntegerToString(field)));
   return true;
  }

void DeletePositionConfigGlobals(const ulong position_id)
  {
   if(MQLInfoInteger(MQL_TESTER))
      return;
   string key = PositionConfigKey(position_id);
   for(int field = 0; field < 26; field++)
      GlobalVariableDel(key + "_F" + IntegerToString(field));
   GlobalVariablesFlush();
  }

int FindPositionConfigIndex(const ulong position_id)
  {
   for(int i = 0; i < ArraySize(g_position_configs); i++)
     {
      if(g_position_configs[i].identifier == position_id)
         return i;
     }
   return -1;
  }

void RegisterPositionConfig(const ulong position_id,
                            const SQZStrategyConfig &config,
                            const bool save_globals = true)
  {
   if(position_id == 0)
      return;
   int index = FindPositionConfigIndex(position_id);
   if(index < 0)
     {
      index = ArraySize(g_position_configs);
      if(ArrayResize(g_position_configs, index + 1) < index + 1)
         return;
     }
   g_position_configs[index].identifier = position_id;
   g_position_configs[index].config = config;
   if(save_globals)
      SavePositionConfigGlobals(position_id, config);
  }

void RemovePositionConfig(const ulong position_id)
  {
   int index = FindPositionConfigIndex(position_id);
   if(index >= 0)
     {
      int last = ArraySize(g_position_configs) - 1;
      if(index != last)
         g_position_configs[index] = g_position_configs[last];
      ArrayResize(g_position_configs, last);
     }
   DeletePositionConfigGlobals(position_id);
  }

// Pozisyonun çıkışlarında kullanılacak ayarı döndürür. Otomatik modda
// InpAutoApplyToOpenPositions=false ise pozisyon, açıldığı andaki ayar
// anlık görüntüsüyle devam eder.
bool GetPositionExitConfig(const ulong ticket, SQZStrategyConfig &config)
  {
   config = g_active_config;
   if(InpAutoSelectSettings && InpAutoApplyToOpenPositions)
      return true;
   if(!SelectOurPosition(ticket))
      return false;

   ulong position_id = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   int index = FindPositionConfigIndex(position_id);
   if(index >= 0)
     {
      config = g_position_configs[index].config;
      return true;
     }
   if(LoadPositionConfigGlobals(position_id, config))
     {
      RegisterPositionConfig(position_id, config, false);
      return true;
     }
   config = g_active_config;
   RegisterPositionConfig(position_id, config);
   return true;
  }

void LoadExistingPositionConfigs()
  {
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      ulong position_id = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      if(FindPositionConfigIndex(position_id) >= 0)
         continue;
      SQZStrategyConfig config;
      if(LoadPositionConfigGlobals(position_id, config))
         RegisterPositionConfig(position_id, config, false);
      else
         RegisterPositionConfig(position_id, g_active_config);
     }
  }

bool CloseOurPosition(const ulong ticket, const string reason)
  {
   if(!SelectOurPosition(ticket))
      return true; // Zaten kapanmis
   int side = SideFromPositionType(PositionGetInteger(POSITION_TYPE));
   ulong position_id = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
   bool sent = trade.PositionClose(ticket, InpDeviationPoints);
   if(!TradeRetcodeOK(sent))
     {
      PrintFormat("Kapatma başarısız ticket=%I64u neden=%s retcode=%u (%s)",
                  ticket, reason, trade.ResultRetcode(), trade.ResultRetcodeDescription());
      return false;
     }
   if(PositionSelectByTicket(ticket))
     {
      PrintFormat("Pozisyon tamamen kapanmadı ticket=%I64u kalan hacim=%.8f",
                  ticket, PositionGetDouble(POSITION_VOLUME));
      return false;
     }
   RemovePositionConfig(position_id);
   PrintFormat("Pozisyon kapandı: ticket=%I64u side=%s neden=%s", ticket, SideName(side), reason);
   g_last_action = StringFormat("%s pozisyon kapatıldı (%s)", SideName(side), reason);
   return true;
  }

//+------------------------------------------------------------------+
//| Renk geçişi sayımına dayalı çıkış kontrolü                       |
//|                                                                  |
//| Pozisyon açıldıktan SONRA gelen mumlar kronolojik sırayla        |
//| taranır. Pozisyon BUY ise BUY TP/SL kuralları, SELL ise SELL     |
//| TP/SL kuralları kullanılır. Her kuralın renk geçişi, adedi ve    |
//| giriş fiyatına göre koşulu ayrı seçilir. Sayacı önce dolduran    |
//| kural çıkışı gerçekleştirir. Pozisyonun açılış ayarı anlık       |
//| görüntüsü kullanıldığı için otomatik seçim sonradan değişse de   |
//| (InpAutoApplyToOpenPositions=false iken) açık pozisyonun çıkışı  |
//| açılıştaki kurallarla devam eder.                                |
//+------------------------------------------------------------------+
int EvaluatePositionExit(const ulong ticket,
                         const MqlRates &rates[],
                         const ENUM_SQZ_BAR_COLOR &colors[],
                         const bool &valid[],
                         string &reason,
                         int &tp_count_out,
                         int &sl_count_out)
  {
   reason       = "";
   tp_count_out = 0;
   sl_count_out = 0;
   if(!SelectOurPosition(ticket))
      return 0;

   int      side       = SideFromPositionType(PositionGetInteger(POSITION_TYPE));
   double   entry      = PositionGetDouble(POSITION_PRICE_OPEN);
   datetime open_time  = (datetime)PositionGetInteger(POSITION_TIME);
   if(side == 0 || entry <= 0.0)
      return 0;

   SQZStrategyConfig position_config;
   GetPositionExitConfig(ticket, position_config);
   SQZExitRule tp_rule;
   SQZExitRule sl_rule;
   if(side > 0)
     {
      tp_rule = position_config.buy_take_profit;
      sl_rule = position_config.buy_stop_loss;
     }
   else
     {
      tp_rule = position_config.sell_take_profit;
      sl_rule = position_config.sell_stop_loss;
     }
   if(!tp_rule.enabled && !sl_rule.enabled)
      return 0;

   int last_closed = ArraySize(rates) - 2; // Son index oluşan mumdur
   int period_seconds = PeriodSeconds(g_timeframe);
   if(period_seconds <= 0)
      period_seconds = 60;

   for(int i = 1; i <= last_closed; i++)
     {
      if(!valid[i] || !valid[i - 1])
         continue;

      // Sinyal, mum kapandığında oluşur. Pozisyonu açan geçişin kendisi
      // sayılmaz; sadece açılıştan sonra kapanan mumların geçişleri sayılır.
      datetime signal_close_time = rates[i].time + period_seconds;
      if(signal_close_time <= open_time)
         continue;

      double signal_price = rates[i].close;
      bool tp_match = ExitRuleMatches(tp_rule, colors[i - 1], colors[i], signal_price, entry);
      bool sl_match = ExitRuleMatches(sl_rule, colors[i - 1], colors[i], signal_price, entry);

      if(tp_match)
        {
         tp_count_out++;
         if(tp_count_out >= tp_rule.signal_count)
           {
            reason = StringFormat("TP (renk geçişi): %s | %d. uygun geçiş, giriş=%.*f sinyal fiyatı=%.*f",
                                  TransitionText(tp_rule.from_color, tp_rule.to_color),
                                  tp_count_out, _Digits, entry, _Digits, signal_price);
            return 1;
           }
        }
      if(sl_match)
        {
         sl_count_out++;
         if(sl_count_out >= sl_rule.signal_count)
           {
            reason = StringFormat("SL (renk geçişi): %s | %d. uygun geçiş, giriş=%.*f sinyal fiyatı=%.*f",
                                  TransitionText(sl_rule.from_color, sl_rule.to_color),
                                  sl_count_out, _Digits, entry, _Digits, signal_price);
            return -1;
           }
        }
     }
   return 0;
  }

void ManageSignalExits(const MqlRates &rates[],
                       const ENUM_SQZ_BAR_COLOR &colors[],
                       const bool &valid[])
  {
   ulong tickets[];
   ArrayResize(tickets, 0);
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      int n = ArraySize(tickets);
      if(ArrayResize(tickets, n + 1) >= n + 1)
         tickets[n] = ticket;
     }

   for(int i = 0; i < ArraySize(tickets); i++)
     {
      string reason = "";
      int tp_count = 0;
      int sl_count = 0;
      int result = EvaluatePositionExit(tickets[i], rates, colors, valid, reason, tp_count, sl_count);
      if(result != 0)
         CloseOurPosition(tickets[i], reason);
     }
  }

//+------------------------------------------------------------------+
//| Otomatik ayar seçimi: geriye dönük sanal test                    |
//|                                                                  |
//| Adaylar, dört rengin birbirinden farklı renklerine olan bütün    |
//| sıralı geçişlerdir (4x3 BUY x 4x3 SELL). Aynı geçiş hem BUY hem  |
//| SELL olamaz. Otomatik adayın çıkış geçişleri seçilen giriş       |
//| çiftine bağlanır: BUY TP/SELL SL = BUY girişi, SELL TP/BUY SL =  |
//| SELL girişi. TP/SL adetleri istenirse 1..InpAutoMaxExitCount     |
//| arasında ayrıca test edilir; istenirse dört çıkış kuralı da      |
//| sonrasında tek tek yeniden denenerek (koordinat arama) seçilir.  |
//| Sanal test kapanış fiyatlarıyla ve  |
//| yalnızca sinyal çıkışlarıyla yapılır; sabit point TP/SL varsa    |
//| canlıda daha erken çıkış olabileceği için teste dahil edilmez.   |
//+------------------------------------------------------------------+
struct SQZAutoSimPosition
  {
   int    side;
   double entry;
   int    tp_count;
   int    sl_count;
  };

struct SQZAutoTestResult
  {
   double score;
   double net_points;
   double gross_profit;
   double gross_loss;
   double max_drawdown;
   double profit_factor;
   double win_rate;
   int    trades;
   int    wins;
  };

void InitializeAutoTestResult(SQZAutoTestResult &result)
  {
   result.score = -1.0e100;
   result.net_points = 0.0;
   result.gross_profit = 0.0;
   result.gross_loss = 0.0;
   result.max_drawdown = 0.0;
   result.profit_factor = 0.0;
   result.win_rate = 0.0;
   result.trades = 0;
   result.wins = 0;
  }

void AddAutoSimTrade(SQZAutoTestResult &result, double &equity, double &peak,
                     const int side, const double entry, const double exit_price)
  {
   if(_Point <= 0.0)
      return;
   double profit_points = side * (exit_price - entry) / _Point -
                          InpAutoCostPointsPerRoundTrip;
   result.net_points += profit_points;
   result.trades++;
   if(profit_points > 0.0)
     {
      result.wins++;
      result.gross_profit += profit_points;
     }
   else if(profit_points < 0.0)
      result.gross_loss += -profit_points;

   equity += profit_points;
   if(equity > peak)
      peak = equity;
   result.max_drawdown = MathMax(result.max_drawdown, peak - equity);
  }

void RemoveAutoSimPosition(SQZAutoSimPosition &positions[], const int index)
  {
   int size = ArraySize(positions);
   for(int i = index; i < size - 1; i++)
      positions[i] = positions[i + 1];
   ArrayResize(positions, size - 1);
  }

bool SimulateAutoCandidate(const MqlRates &rates[],
                           const ENUM_SQZ_BAR_COLOR &colors[],
                           const bool &valid[],
                           const int start_index,
                           const int end_index,
                           const SQZStrategyConfig &candidate,
                           SQZAutoTestResult &result)
  {
   InitializeAutoTestResult(result);
   if(start_index < 1 || end_index < start_index || end_index >= ArraySize(rates))
      return false;

   SQZAutoSimPosition positions[];
   ArrayResize(positions, 0);
   double equity = 0.0;
   double peak = 0.0;

   for(int i = start_index; i <= end_index; i++)
     {
      if(!valid[i] || !valid[i - 1])
         continue;

      // Önce bu mumun kapanışındaki geçişle mevcut sanal pozisyonlar çıkar
      for(int pos = ArraySize(positions) - 1; pos >= 0; pos--)
        {
         SQZExitRule tp_rule;
         SQZExitRule sl_rule;
         if(positions[pos].side > 0)
           {
            tp_rule = candidate.buy_take_profit;
            sl_rule = candidate.buy_stop_loss;
           }
         else
           {
            tp_rule = candidate.sell_take_profit;
            sl_rule = candidate.sell_stop_loss;
           }

         bool closed = false;
         if(ExitRuleMatches(tp_rule, colors[i - 1], colors[i], rates[i].close, positions[pos].entry))
           {
            positions[pos].tp_count++;
            if(positions[pos].tp_count >= tp_rule.signal_count)
              {
               AddAutoSimTrade(result, equity, peak, positions[pos].side,
                               positions[pos].entry, rates[i].close);
               RemoveAutoSimPosition(positions, pos);
               closed = true;
              }
           }
         if(!closed && ExitRuleMatches(sl_rule, colors[i - 1], colors[i], rates[i].close, positions[pos].entry))
           {
            positions[pos].sl_count++;
            if(positions[pos].sl_count >= sl_rule.signal_count)
              {
               AddAutoSimTrade(result, equity, peak, positions[pos].side,
                               positions[pos].entry, rates[i].close);
               RemoveAutoSimPosition(positions, pos);
              }
           }
        }

      // Sonra aynı kapanışta yeni sanal girişler açılır (giriş geçişi kendisi
      // o pozisyonun çıkış sayımına dahil edilmez)
      bool buy_event = EntryRuleMatches(candidate.buy_entry, colors[i - 1], colors[i]);
      bool sell_event = EntryRuleMatches(candidate.sell_entry, colors[i - 1], colors[i]);
      int entry_side = 0;
      if(buy_event && !sell_event)
         entry_side = 1;
      else if(sell_event && !buy_event)
         entry_side = -1;

      if(entry_side != 0 &&
         (InpMaxOpenPositions <= 0 || ArraySize(positions) < InpMaxOpenPositions))
        {
         int index = ArraySize(positions);
         if(ArrayResize(positions, index + 1) >= index + 1)
           {
            positions[index].side = entry_side;
            positions[index].entry = rates[i].close;
            positions[index].tp_count = 0;
            positions[index].sl_count = 0;
           }
        }
     }

   // Pencere sonunda açık kalanlar son kapanıştan tasfiye edilmiş sayılır;
   // böylece bir aday kârı/zararı açık pozisyonda saklayarak kazanamaz.
   double final_price = rates[end_index].close;
   while(ArraySize(positions) > 0)
     {
      int last = ArraySize(positions) - 1;
      AddAutoSimTrade(result, equity, peak, positions[last].side,
                      positions[last].entry, final_price);
      ArrayResize(positions, last);
     }

   if(result.trades > 0)
     {
      result.profit_factor = (result.gross_loss > 0.0
                              ? result.gross_profit / result.gross_loss
                              : (result.gross_profit > 0.0 ? 100.0 : 0.0));
      result.win_rate = 100.0 * result.wins / result.trades;
     }

   switch(InpAutoScoreMode)
     {
      case AUTO_SCORE_NET_POINTS:
         result.score = result.net_points;
         break;
      case AUTO_SCORE_PROFIT_FACTOR:
         result.score = result.profit_factor;
         break;
      case AUTO_SCORE_WIN_RATE:
         result.score = result.win_rate;
         break;
      case AUTO_SCORE_AVG_POINTS:
         result.score = (result.trades > 0 ? result.net_points / result.trades : -1.0e100);
         break;
      default: // AUTO_SCORE_NET_PER_DRAWDOWN
         result.score = result.net_points / MathMax(result.max_drawdown, 1.0);
         break;
     }
   return true;
  }

SQZStrategyConfig BuildAutoCandidate(const ENUM_SQZ_COLOR_SELECT buy_from,
                                     const ENUM_SQZ_COLOR_SELECT buy_to,
                                     const ENUM_SQZ_COLOR_SELECT sell_from,
                                     const ENUM_SQZ_COLOR_SELECT sell_to,
                                     const int take_profit_count,
                                     const int stop_loss_count)
  {
   SQZStrategyConfig candidate = g_manual_config;
   candidate.buy_entry.enabled = (g_manual_config.buy_entry.enabled && InpAllowLongTrades);
   candidate.buy_entry.from_color = buy_from;
   candidate.buy_entry.to_color = buy_to;
   candidate.sell_entry.enabled = (g_manual_config.sell_entry.enabled && InpAllowShortTrades);
   candidate.sell_entry.from_color = sell_from;
   candidate.sell_entry.to_color = sell_to;

   // Çıkış geçişleri seçilen BUY/SELL giriş çiftine bağlanır; kuralların
   // açık/kapalı durumu ve fiyat koşulları manuel ayarlardan alınır.
   candidate.buy_take_profit.from_color = buy_from;
   candidate.buy_take_profit.to_color = buy_to;
   candidate.sell_stop_loss.from_color = buy_from;
   candidate.sell_stop_loss.to_color = buy_to;
   candidate.sell_take_profit.from_color = sell_from;
   candidate.sell_take_profit.to_color = sell_to;
   candidate.buy_stop_loss.from_color = sell_from;
   candidate.buy_stop_loss.to_color = sell_to;

   if(InpAutoOptimizeExitCounts)
     {
      candidate.buy_take_profit.signal_count = take_profit_count;
      candidate.sell_take_profit.signal_count = take_profit_count;
      candidate.buy_stop_loss.signal_count = stop_loss_count;
      candidate.sell_stop_loss.signal_count = stop_loss_count;
     }
   return candidate;
  }

string AutoScoreModeName()
  {
   switch(InpAutoScoreMode)
     {
      case AUTO_SCORE_NET_POINTS:       return "Net puan";
      case AUTO_SCORE_PROFIT_FACTOR:    return "Kâr faktörü";
      case AUTO_SCORE_WIN_RATE:         return "Kazanma oranı";
      case AUTO_SCORE_AVG_POINTS:       return "İşlem başına puan";
      default:                          return "Net/maks. düşüş";
     }
  }

void SetAutoExitRule(SQZStrategyConfig &config, const int rule_index,
                     const ENUM_SQZ_COLOR_SELECT from_color,
                     const ENUM_SQZ_COLOR_SELECT to_color,
                     const int signal_count)
  {
   int base_field = 6 + rule_index * 5; // 0=BUY TP, 1=BUY SL, 2=SELL TP, 3=SELL SL
   SetConfigFieldValue(config, base_field + 1, (double)from_color);
   SetConfigFieldValue(config, base_field + 2, (double)to_color);
   SetConfigFieldValue(config, base_field + 3, (double)signal_count);
  }

bool RefreshAutoSettings(const bool force)
  {
   if(!InpAutoSelectSettings)
     {
      g_auto_status = "Kapalı";
      return false;
     }

   datetime now = TimeCurrent();
   if(now <= 0)
      return false;
   datetime minute = (datetime)(((long)now / 60) * 60);
   if(minute < InpAutoLookbackMinutes * 60)
      return false;
   if(!force && g_auto_last_test_minute == minute)
      return g_auto_selection_ready;

   bool first_attempt = (g_auto_attempt_minute != minute);
   if(!force && !first_attempt && now < g_auto_retry_after)
      return g_auto_selection_ready;
   g_auto_attempt_minute = minute;
   g_auto_retry_after = now + 10;

   MqlRates rates[];
   int copied = LoadRates(rates);
   int min_bars = (2 * InpKCLength) + 5;
   if(copied < min_bars)
     {
      g_auto_status = "Seçim korundu; test için mum geçmişi hazır değil";
      if(first_attempt || force)
         Print("Otomatik seçim: ", g_auto_status, ". 10 saniye sonra yeniden denenecek.");
      return false;
     }

   double values[];
   ENUM_SQZ_BAR_COLOR colors[];
   bool valid[];
   if(!ComputeMomentum(rates, values, colors, valid))
     {
      g_auto_status = "Seçim korundu; momentum hesaplanamadı";
      return false;
     }

   datetime window_end = minute;
   datetime window_start = minute - InpAutoLookbackMinutes * 60;
   int end_index = copied - 2; // Son index oluşan mumdur; test kapalı mumlarla yapılır
   int start_index = -1;
   for(int i = 0; i <= end_index; i++)
     {
      if(rates[i].time >= window_start)
        {
         start_index = i;
         break;
        }
     }
   int window_bars = (start_index >= 0 ? end_index - start_index + 1 : 0);
   if(start_index < 1 || window_bars < InpAutoMinBars)
     {
      g_auto_status = StringFormat("Seçim korundu; test penceresinde yeterli kapalı mum yok (%d/%d). Süreyi artırın veya daha küçük TF seçin.",
                                   window_bars, InpAutoMinBars);
      g_auto_last_test_minute = minute; // Aynı dakika içinde tekrar tekrar deneme
      if(first_attempt || force)
         Print("Otomatik seçim: ", g_auto_status);
      return false;
     }

   ENUM_SQZ_COLOR_SELECT test_colors[4] = {SQZ_SELECT_LIME, SQZ_SELECT_GREEN,
                                           SQZ_SELECT_RED, SQZ_SELECT_MAROON};
   SQZStrategyConfig best_config = g_active_config;
   SQZAutoTestResult best_result;
   InitializeAutoTestResult(best_result);
   bool have_best = false;
   int max_exit_count = InpAutoOptimizeExitCounts ? InpAutoMaxExitCount : 1;

   for(int buy_from_index = 0; buy_from_index < 4; buy_from_index++)
     {
      for(int buy_to_index = 0; buy_to_index < 4; buy_to_index++)
        {
         if(buy_from_index == buy_to_index)
            continue;
         for(int sell_from_index = 0; sell_from_index < 4; sell_from_index++)
           {
            for(int sell_to_index = 0; sell_to_index < 4; sell_to_index++)
              {
               if(sell_from_index == sell_to_index)
                  continue;
               if(test_colors[sell_from_index] == test_colors[buy_from_index] &&
                  test_colors[sell_to_index] == test_colors[buy_to_index])
                  continue; // Aynı geçiş hem BUY hem SELL olamaz

               for(int tp_count = 1; tp_count <= max_exit_count; tp_count++)
                 {
                  for(int sl_count = 1; sl_count <= max_exit_count; sl_count++)
                    {
                     SQZStrategyConfig candidate = BuildAutoCandidate(
                        test_colors[buy_from_index], test_colors[buy_to_index],
                        test_colors[sell_from_index], test_colors[sell_to_index],
                        tp_count, sl_count);
                     SQZAutoTestResult result;
                     if(!SimulateAutoCandidate(rates, colors, valid, start_index, end_index,
                                               candidate, result))
                        continue;
                     if(result.trades < MathMax(1, InpAutoMinTrades))
                        continue;
                     if(InpAutoRequirePositiveResult && result.net_points <= 0.0)
                        continue;

                     bool better = (!have_best || result.score > best_result.score + 1.0e-9);
                     bool keep_active_on_tie = (have_best &&
                                                MathAbs(result.score - best_result.score) <= 1.0e-9 &&
                                                ConfigEquals(candidate, g_active_config));
                     if(better || keep_active_on_tie)
                       {
                        best_config = candidate;
                        best_result = result;
                        have_best = true;
                       }
                    }
                 }
              }
           }
        }
     }

   // İstenirse dört çıkış kuralı, bulunan giriş çiftinden bağımsız olarak
   // tek tek yeniden denenir. Dört kuralın bütün kombinasyonları milyonları
   // bulduğu için bu, her dakika çalışabilecek koordinat aramasıdır.
   if(have_best && InpAutoOptimizeIndependentExits)
     {
      SQZStrategyConfig tuned_config = best_config;
      SQZAutoTestResult tuned_result = best_result;
      for(int rule_index = 0; rule_index < 4; rule_index++)
        {
         int base_field = 6 + rule_index * 5;
         int current_count = (int)ConfigFieldValue(tuned_config, base_field + 3);
         for(int from_index = 0; from_index < 4; from_index++)
           {
            for(int to_index = 0; to_index < 4; to_index++)
              {
               if(from_index == to_index)
                  continue;
               for(int count = 1; count <= max_exit_count; count++)
                 {
                  SQZStrategyConfig candidate = tuned_config;
                  int rule_count = InpAutoOptimizeExitCounts ? count : current_count;
                  SetAutoExitRule(candidate, rule_index, test_colors[from_index],
                                  test_colors[to_index], rule_count);
                  SQZAutoTestResult result;
                  if(!SimulateAutoCandidate(rates, colors, valid, start_index, end_index,
                                            candidate, result))
                     continue;
                  if(result.trades < MathMax(1, InpAutoMinTrades))
                     continue;
                  if(InpAutoRequirePositiveResult && result.net_points <= 0.0)
                     continue;
                  if(result.score > tuned_result.score + 1.0e-9)
                    {
                     tuned_config = candidate;
                     tuned_result = result;
                    }
                 }
              }
           }
        }
      best_config = tuned_config;
      best_result = tuned_result;
     }

   g_auto_last_test_minute = minute;
   if(!have_best)
     {
      g_auto_status = "Uygun aday bulunamadı; mevcut seçim korundu";
      PrintFormat("Otomatik seçim [%s - %s): uygun aday yok (min işlem=%d, pozitif zorunlu=%s). Mevcut ayar korundu.",
                  TimeToString(window_start, TIME_DATE|TIME_MINUTES),
                  TimeToString(window_end, TIME_DATE|TIME_MINUTES),
                  InpAutoMinTrades, (InpAutoRequirePositiveResult ? "true" : "false"));
      return false;
     }

   bool changed = (!g_auto_selection_ready || !ConfigEquals(best_config, g_active_config));
   g_active_config = best_config;
   g_auto_selection_ready = true;
   g_auto_window_start = window_start;
   g_auto_window_end = window_end;
   g_auto_best_score = best_result.score;
   g_auto_best_net_points = best_result.net_points;
   g_auto_best_trades = best_result.trades;
   g_auto_status = "Test tamamlandı";
   if(changed)
      g_last_action = "Otomatik ayar seçimi güncellendi";
   PrintFormat("Otomatik seçim [%s - %s): BUY=%s | SELL=%s | BUY TP=%s | BUY SL=%s | SELL TP=%s | SELL SL=%s | %s=%.4f net=%.1f point işlem=%d%s",
               TimeToString(window_start, TIME_DATE|TIME_MINUTES),
               TimeToString(window_end, TIME_DATE|TIME_MINUTES),
               EntryRuleText(best_config.buy_entry), EntryRuleText(best_config.sell_entry),
               ExitRuleText(best_config.buy_take_profit), ExitRuleText(best_config.buy_stop_loss),
               ExitRuleText(best_config.sell_take_profit), ExitRuleText(best_config.sell_stop_loss),
               AutoScoreModeName(), best_result.score, best_result.net_points, best_result.trades,
               (changed ? " [değişti]" : " [korundu]"));
   return true;
  }

//+------------------------------------------------------------------+
//| Sinyalde pozisyon açma                                           |
//+------------------------------------------------------------------+
bool BuildFixedExits(const int side, const double entry, double &sl, double &tp)
  {
   sl = 0.0;
   tp = 0.0;
   long stops_level  = (long)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_STOPS_LEVEL);
   long freeze_level = (long)SymbolInfoInteger(_Symbol, SYMBOL_TRADE_FREEZE_LEVEL);
   double min_distance = MathMax(stops_level, freeze_level) * _Point;

   if(InpFixedTakeProfitPoints > 0)
     {
      double distance = MathMax(InpFixedTakeProfitPoints * _Point, min_distance + TickSize());
      tp = NormalizePriceToTick(entry + side * distance, (side > 0 ? 1 : -1));
     }
   if(InpFixedStopLossPoints > 0)
     {
      double distance = MathMax(InpFixedStopLossPoints * _Point, min_distance + TickSize());
      sl = NormalizePriceToTick(entry - side * distance, (side > 0 ? -1 : 1));
     }
   return (tp > 0.0 || InpFixedTakeProfitPoints <= 0) &&
          (sl > 0.0 || InpFixedStopLossPoints <= 0);
  }

void DrawSignalArrow(const datetime bar_time, const double high, const double low, const int raw_signal)
  {
   if(!InpDrawSignalArrows)
      return;
   string name = g_object_prefix + IntegerToString((long)bar_time);
   if(ObjectFind(0, name) >= 0)
      return;
   double offset = MathMax((high - low) * 0.25, _Point * 20.0);
   if(raw_signal > 0)
     {
      if(!ObjectCreate(0, name, OBJ_ARROW_BUY, 0, bar_time, low - offset))
         return;
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrLimeGreen);
     }
   else
     {
      if(!ObjectCreate(0, name, OBJ_ARROW_SELL, 0, bar_time, high + offset))
         return;
      ObjectSetInteger(0, name, OBJPROP_COLOR, clrTomato);
     }
   ObjectSetInteger(0, name, OBJPROP_WIDTH, 2);
   ObjectSetInteger(0, name, OBJPROP_SELECTABLE, false);
   ObjectSetInteger(0, name, OBJPROP_HIDDEN, true);
  }

bool FindOpenedPositionTicket(const ulong deal, const int expected_side,
                              const long earliest_time_msc, ulong &ticket_out)
  {
   ticket_out = 0;
   if(deal > 0 && HistoryDealSelect(deal))
     {
      ulong position_id = (ulong)HistoryDealGetInteger(deal, DEAL_POSITION_ID);
      if(position_id > 0)
        {
         for(int i = PositionsTotal() - 1; i >= 0; i--)
           {
            ulong ticket = PositionGetTicket(i);
            if(ticket == 0 || !PositionSelectByTicket(ticket))
               continue;
            if((ulong)PositionGetInteger(POSITION_IDENTIFIER) == position_id)
              {
               ticket_out = ticket;
               return true;
              }
           }
        }
     }

   long newest_time = -1;
   for(int i = PositionsTotal() - 1; i >= 0; i--)
     {
      ulong ticket = PositionGetTicket(i);
      if(ticket == 0 || !SelectOurPosition(ticket))
         continue;
      if(SideFromPositionType(PositionGetInteger(POSITION_TYPE)) != expected_side)
         continue;
      long time_msc = PositionGetInteger(POSITION_TIME_MSC);
      if(time_msc + 1000 < earliest_time_msc)
         continue;
      if(time_msc >= newest_time)
        {
         newest_time = time_msc;
         ticket_out = ticket;
        }
     }
   return (ticket_out > 0);
  }

bool OpenPositionBySignal(const int raw_signal, const datetime signal_bar_time, const double signal_price)
  {
   if(raw_signal > 0 && !g_active_config.buy_entry.enabled)
     {
      g_last_action = "BUY giriş kuralı kapalı";
      return false;
     }
   if(raw_signal < 0 && !g_active_config.sell_entry.enabled)
     {
      g_last_action = "SELL giriş kuralı kapalı";
      return false;
     }

   // Ters işlem ayarı yalnızca AÇILIŞ yönünü değiştirir. Otomatik seçim
   // aktifken seçilen geçişler doğrudan BUY/SELL açılışını temsil eder.
   bool reverse_trading = EffectiveReverseTrading();
   int trade_side = reverse_trading ? -raw_signal : raw_signal;
   string event_text = (raw_signal > 0
                        ? "BUY giriş geçişi (" + EntryRuleText(g_active_config.buy_entry) + ")"
                        : "SELL giriş geçişi (" + EntryRuleText(g_active_config.sell_entry) + ")");

   if(trade_side > 0 && !InpAllowLongTrades)
     {
      g_last_action = "BUY pozisyon açma ayarlardan kapalı";
      return false;
     }
   if(trade_side < 0 && !InpAllowShortTrades)
     {
      g_last_action = "SELL pozisyon açma ayarlardan kapalı";
      return false;
     }

   if(InpMaxOpenPositions > 0 && CountOurPositions(0) >= InpMaxOpenPositions)
     {
      g_last_action = "Maksimum pozisyon sayısına ulaşıldı";
      return false;
     }

   MqlTick tick;
   if(!SymbolInfoTick(_Symbol, tick) || tick.ask <= 0.0 || tick.bid <= 0.0)
      return false;

   long request_time_msc = (long)tick.time_msc;
   double spread_points = (tick.ask - tick.bid) / _Point;
   if(InpMaxSpreadPoints > 0 && spread_points > InpMaxSpreadPoints)
     {
      g_last_action = StringFormat("Spread yüksek: %.1f point", spread_points);
      return false;
     }

   double volume = NormalizeVolume(InpLotSize);
   if(volume <= 0.0)
     {
      g_last_action = "Lot hacmi broker sınırlarına uymuyor";
      return false;
     }

   double expected_entry = (trade_side > 0 ? tick.ask : tick.bid);
   double fixed_sl = 0.0;
   double fixed_tp = 0.0;
   if(!BuildFixedExits(trade_side, expected_entry, fixed_sl, fixed_tp))
     {
      g_last_action = "Sabit TP/SL fiyatı hesaplanamadı";
      return false;
     }

   string comment = (trade_side > 0 ? "SQZLB BUY" : "SQZLB SELL");
   bool sent = false;
   if(trade_side > 0)
      sent = trade.Buy(volume, _Symbol, 0.0, fixed_sl, fixed_tp, comment);
   else
      sent = trade.Sell(volume, _Symbol, 0.0, fixed_sl, fixed_tp, comment);

   if(!TradeRetcodeOK(sent))
     {
      PrintFormat("Giriş başarısız: %s işlem yönü=%s lot=%.8f retcode=%u (%s)",
                  event_text, SideName(trade_side), volume,
                  trade.ResultRetcode(), trade.ResultRetcodeDescription());
      g_last_action = "Emir broker tarafından reddedildi";
      return false;
     }

   ulong opened_ticket = 0;
   if(FindOpenedPositionTicket(trade.ResultDeal(), trade_side, request_time_msc, opened_ticket) &&
      PositionSelectByTicket(opened_ticket))
     {
      ulong position_id = (ulong)PositionGetInteger(POSITION_IDENTIFIER);
      RegisterPositionConfig(position_id, g_active_config);
     }

   PrintFormat("Giriş: %s | işlem=%s%s | sinyal mumu=%s sinyal fiyatı=%.*f | lot=%.8f",
               event_text, SideName(trade_side),
               (reverse_trading ? " (ters işlem)" : ""),
               TimeToString(signal_bar_time), _Digits, signal_price, volume);
   g_last_action = StringFormat("Yeni %s pozisyon açıldı (%s%s)",
                                SideName(trade_side), event_text,
                                (reverse_trading ? ", ters işlem" : ""));
   return true;
  }

//+------------------------------------------------------------------+
//| Kapanmış mum işleme                                              |
//+------------------------------------------------------------------+
void ProcessClosedBar()
  {
   MqlRates rates[];
   int copied = LoadRates(rates);
   int min_bars = (2 * InpKCLength) + 5;
   if(copied < min_bars)
     {
      g_last_action = StringFormat("Yetersiz mum verisi: %d/%d", copied, min_bars);
      return;
     }

   double values[];
   ENUM_SQZ_BAR_COLOR colors[];
   bool valid[];
   if(!ComputeMomentum(rates, values, colors, valid))
     {
      g_last_action = "Momentum hesaplanamadı";
      return;
     }

   int last_closed = copied - 2; // Son index oluşan (canlı) mumdur
   if(last_closed < 1 || !valid[last_closed] || !valid[last_closed - 1])
     {
      g_last_action = "Momentum için yeterli kapalı mum yok";
      return;
     }

   g_last_momentum  = values[last_closed];
   g_last_bar_color = colors[last_closed];
   g_prev_bar_color = colors[last_closed - 1];
   g_last_sqz_state = ComputeSqueezeState(rates, last_closed);

   // Önce mevcut pozisyonların sinyal sayımlı çıkışları kontrol edilir;
   // böylece bu mumda oluşan sinyal önce eski pozisyonlara işletilir,
   // ardından aynı sinyal yeni pozisyon açabilir.
   ManageSignalExits(rates, colors, valid);

   bool ambiguous_transition = false;
   int raw_signal = EntryEventFromColors(colors[last_closed - 1], colors[last_closed],
                                         g_active_config, ambiguous_transition);
   if(raw_signal == 0)
     {
      g_last_action = (ambiguous_transition
                       ? "BUY ve SELL giriş geçişleri çakıştı; giriş atlandı"
                       : "Yeni giriş geçişi yok");
      return;
     }

   g_last_raw_signal   = raw_signal;
   g_last_signal_time  = rates[last_closed].time;
   g_last_signal_price = rates[last_closed].close;

   DrawSignalArrow(rates[last_closed].time, rates[last_closed].high,
                   rates[last_closed].low, raw_signal);
   OpenPositionBySignal(raw_signal, rates[last_closed].time, rates[last_closed].close);
  }

void CheckNewBar()
  {
   datetime current_bar_time = iTime(_Symbol, g_timeframe, 0);
   if(current_bar_time <= 0)
      return;
   if(g_last_bar_time == 0)
     {
      // EA açıldığında geçmiş sinyalden geriye dönük işlem açma.
      g_last_bar_time = current_bar_time;
      return;
     }
   if(current_bar_time == g_last_bar_time)
      return;
   g_last_bar_time = current_bar_time;
   ProcessClosedBar();
  }

//+------------------------------------------------------------------+
//| Bilgi paneli / nesneler                                          |
//+------------------------------------------------------------------+
void UpdateChartInfo()
  {
   if(!InpShowChartInfo)
     {
      Comment("");
      return;
     }

   string source_text = "Manuel ayarlar";
   if(InpAutoSelectSettings)
      source_text = (g_auto_selection_ready ? "Otomatik seçim" : "Otomatik seçim bekleniyor (manuel ayar aktif)");
   string reverse_text = EffectiveReverseTrading()
                         ? "AÇIK (BUY geçişi -> SELL, SELL geçişi -> BUY)"
                         : "kapalı (geçiş yönünde işlem)";
   if(InpAutoSelectSettings && g_auto_selection_ready && InpReverseTrading)
      reverse_text = "Otomatik seçim nedeniyle uygulanmıyor";

   string last_signal_text = "henüz yok";
   if(g_last_raw_signal != 0 && g_last_signal_time > 0)
     {
      string event_text = (g_last_raw_signal > 0
                           ? "BUY giriş geçişi (" + EntryRuleText(g_active_config.buy_entry) + ")"
                           : "SELL giriş geçişi (" + EntryRuleText(g_active_config.sell_entry) + ")");
      last_signal_text = StringFormat("%s | %s | fiyat %.*f",
                                      event_text, TimeToString(g_last_signal_time),
                                      _Digits, g_last_signal_price);
     }

   string auto_text = "kapalı";
   if(InpAutoSelectSettings)
     {
      auto_text = g_auto_status;
      if(g_auto_selection_ready)
         auto_text += StringFormat(" | %s - %s | %s=%.2f, net=%.1f point, işlem=%d",
                                   TimeToString(g_auto_window_start, TIME_MINUTES),
                                   TimeToString(g_auto_window_end, TIME_MINUTES),
                                   AutoScoreModeName(), g_auto_best_score,
                                   g_auto_best_net_points, g_auto_best_trades);
     }

   Comment("Squeeze Momentum [LazyBear] EA v1.10\n",
           "Sembol: ", _Symbol, " | TF: ", EnumToString(g_timeframe),
           " | Ayar kaynağı: ", source_text, "\n",
           "Son kapalı mum momentum: ", DoubleToString(g_last_momentum, _Digits + 2), "\n",
           "Renk geçişi: ", ColorName(g_prev_bar_color), " -> ", ColorName(g_last_bar_color), "\n",
           "Squeeze durumu (bilgi): ", SqueezeStateName(g_last_sqz_state), "\n",
           "Son giriş olayı: ", last_signal_text, "\n",
           "BUY girişi: ", EntryRuleText(g_active_config.buy_entry),
           " | SELL girişi: ", EntryRuleText(g_active_config.sell_entry), "\n",
           "BUY çıkış TP: ", ExitRuleText(g_active_config.buy_take_profit),
           " | SL: ", ExitRuleText(g_active_config.buy_stop_loss), "\n",
           "SELL çıkış TP: ", ExitRuleText(g_active_config.sell_take_profit),
           " | SL: ", ExitRuleText(g_active_config.sell_stop_loss), "\n",
           "Ters işlem: ", reverse_text, "\n",
           "Otomatik seçim: ", auto_text, "\n",
           (InpFixedTakeProfitPoints > 0 || InpFixedStopLossPoints > 0
              ? StringFormat("Sabit TP/SL: %d / %d point\n", InpFixedTakeProfitPoints, InpFixedStopLossPoints)
              : "Sabit TP/SL: kapalı\n"),
           "Açık pozisyon BUY/SELL: ", IntegerToString(CountOurPositions(1)), " / ",
           IntegerToString(CountOurPositions(-1)), "\n",
           "Durum: ", g_last_action);
  }

void DeleteOwnObjects()
  {
   if(g_object_prefix == "")
      return;
   int total = ObjectsTotal(0, -1, -1);
   for(int i = total - 1; i >= 0; i--)
     {
      string name = ObjectName(0, i, -1, -1);
      if(StringFind(name, g_object_prefix) == 0)
         ObjectDelete(0, name);
     }
  }

//+------------------------------------------------------------------+
//| Standart olaylar                                                 |
//+------------------------------------------------------------------+
int OnInit()
  {
   if(InpBBLength < 2 || InpKCLength < 2 ||
      InpBBMultFactor <= 0.0 || InpKCMultFactor <= 0.0 ||
      InpHistoryBars < 100 || InpLotSize <= 0.0 ||
      InpBuyTakeProfitSignalCount < 0 || InpBuyStopLossSignalCount < 0 ||
      InpSellTakeProfitSignalCount < 0 || InpSellStopLossSignalCount < 0 ||
      InpFixedTakeProfitPoints < 0 || InpFixedStopLossPoints < 0 ||
      InpDeviationPoints < 0 || InpMaxSpreadPoints < 0 ||
      InpMaxOpenPositions < 0 ||
      InpAutoLookbackMinutes < 10 || InpAutoLookbackMinutes > 525600 || InpAutoMinTrades < 0 ||
      InpAutoMinBars < 10 || InpAutoMaxExitCount < 1 || InpAutoMaxExitCount > 10 ||
      InpAutoCostPointsPerRoundTrip < 0.0 ||
      !MathIsValidNumber(InpBBMultFactor) || !MathIsValidNumber(InpKCMultFactor) ||
      !MathIsValidNumber(InpLotSize) || !MathIsValidNumber(InpAutoCostPointsPerRoundTrip))
     {
      Print("Hatalı girdiler: BB/KC uzunluk ve çarpımları, lot, sinyal sayıları ve emir ayarlarını kontrol edin.");
      return INIT_PARAMETERS_INCORRECT;
     }

   if(InpRequireHedgingAccount &&
      AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
     {
      Print("EA başlatılamadı: sinyal bazlı TP/SL sayımı her pozisyon için ayrı takip gerektirir; hedging hesap gerekir. "
            "Netting hesapta kullanmak isterseniz InpRequireHedgingAccount=false yapın (pozisyonlar netleşebilir).");
      return INIT_FAILED;
     }
   if(AccountInfoInteger(ACCOUNT_MARGIN_MODE) != ACCOUNT_MARGIN_MODE_RETAIL_HEDGING)
      Print("UYARI: Hesap hedging değil. Aynı sembolde pozisyonlar netleşebilir; çıkış sayımı tek net pozisyon üzerinden takip edilir.");

   g_timeframe = WorkingTimeframe();
   if(PeriodSeconds(g_timeframe) <= 0)
     {
      Print("EA başlatılamadı: geçersiz zaman dilimi.");
      return INIT_FAILED;
     }
   if(!SymbolSelect(_Symbol, true))
     {
      Print("EA başlatılamadı: sembol seçilemiyor.");
      return INIT_FAILED;
     }

   trade.SetExpertMagicNumber(InpMagicNumber);
   trade.SetDeviationInPoints(InpDeviationPoints);
   trade.SetAsyncMode(false);
   trade.SetTypeFillingBySymbol(_Symbol);

   g_manual_config = BuildManualConfig();
   g_active_config = g_manual_config;
   ValidateStrategyConfig(g_manual_config);
   if(!AnyExitRuleEnabled(g_manual_config) &&
      InpFixedTakeProfitPoints == 0 && InpFixedStopLossPoints == 0)
      Print("UYARI: Tüm çıkışlar kapalı. Pozisyonlar yalnızca elle kapatılabilir.");
   if(InpAutoSelectSettings)
     {
      g_auto_status = "İlk test bekleniyor";
      if(InpFixedTakeProfitPoints > 0 || InpFixedStopLossPoints > 0)
         Print("UYARI: Otomatik sanal test sabit point TP/SL çıkışlarını içermez; canlıda bu çıkışlar daha erken gerçekleşebilir.");
     }

   g_object_prefix = StringFormat("SQZLB_%I64u_%s_%s_",
                                  InpMagicNumber, _Symbol, EnumToString(g_timeframe));
   g_last_bar_time = iTime(_Symbol, g_timeframe, 0);

   LoadExistingPositionConfigs();
   RefreshAutoSettings(true);
   EventSetTimer(1);
   PrintFormat("EA hazır: %s TF=%s BB=%d/%.2f KC=%d/%.2f TrueRange=%s | BUY giriş=%s | SELL giriş=%s | ters işlem=%s | otomatik seçim=%s",
               _Symbol, EnumToString(g_timeframe),
               InpBBLength, InpBBMultFactor, InpKCLength, InpKCMultFactor,
               (InpUseTrueRange ? "true" : "false"),
               EntryRuleText(g_active_config.buy_entry), EntryRuleText(g_active_config.sell_entry),
               (EffectiveReverseTrading() ? "true" : "false"),
               (InpAutoSelectSettings ? "true" : "false"));
   Print("Sinyaller yalnızca kapanmış mumlarda değerlendirilir. Açılışta geçmişe dönük sinyal işlenmez.");
   UpdateChartInfo();
   return INIT_SUCCEEDED;
  }

void OnDeinit(const int reason)
  {
   EventKillTimer();
   if(InpDeleteArrowsOnExit)
      DeleteOwnObjects();
   Comment("");
  }

void OnTick()
  {
   CheckNewBar();
   RefreshAutoSettings(false);
   UpdateChartInfo();
  }

void OnTimer()
  {
   CheckNewBar();
   RefreshAutoSettings(false);
   UpdateChartInfo();
  }

void OnTradeTransaction(const MqlTradeTransaction &trans,
                        const MqlTradeRequest &request,
                        const MqlTradeResult &result)
  {
   if(trans.type != TRADE_TRANSACTION_DEAL_ADD || trans.deal == 0)
      return;
   if(!HistoryDealSelect(trans.deal))
      return;

   ulong position_id = (ulong)HistoryDealGetInteger(trans.deal, DEAL_POSITION_ID);
   if(position_id == 0)
      return;
   long deal_entry = HistoryDealGetInteger(trans.deal, DEAL_ENTRY);
   if(deal_entry == DEAL_ENTRY_IN)
     {
      if(HistoryDealGetString(trans.deal, DEAL_SYMBOL) != _Symbol ||
         (ulong)HistoryDealGetInteger(trans.deal, DEAL_MAGIC) != InpMagicNumber)
         return;
      if(FindPositionConfigIndex(position_id) < 0)
         RegisterPositionConfig(position_id, g_active_config);
     }
   else if(deal_entry == DEAL_ENTRY_OUT || deal_entry == DEAL_ENTRY_OUT_BY)
      RemovePositionConfig(position_id);
  }

double OnTester()
  {
   // Strategy Tester optimizasyonunda net kârı sırala.
   return TesterStatistics(STAT_PROFIT);
  }
//+------------------------------------------------------------------+

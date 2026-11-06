# Forex Dynamic Engine — tasarım ve kullanım

Bu, `SqueezeMomentum_LB_EA.mq5` temel alınarak hazırlanmış **deneysel bir EA taslağıdır**; orijinal dosya değiştirilmemiştir. `Forex_Dynamic_Engine.mq5` özgün EA'daki LazyBear momentum, renk geçişi ve BB/KC sıkışma hesaplarını korur. Ancak orijinal sinyal-sayımıyla çıkış, ters işlem, ok ve panel özellikleri yeni stratejinin parçası değildir. Bu bir yapay zekâ modeli, gerçek HFT sistemi veya kâr garantisi değildir. Grid ve kaldıraç tüm sermayenin kaybına yol açabilir; canlıya geçmeden önce derleme, gerçekçi backtest, ileriye dönük demo testleri ve bağımsız risk incelemesi gerekir.

## Akış

```text
Her tick
  ├─ Hesap (bakiye - özsermaye) / bakiye ≥ acil eşik?
  │    └─ Kalıcı STOP + FLATTEN: sadece bu EA'nın emir/pozisyonlarını iptal/kapat; tekrar dene
  ├─ FLATTEN sürüyorsa tamamlanana kadar yeni giriş yok
  ├─ Sepet kâr hedefi dolduysa FLATTEN
  ├─ Yeni kapanmış mum veya ilk veri yüklemesi
  │    └─ Squeeze + ATR/ADX/EMA oku → rejim → mod
  │       Veriler eksikse yeni girişleri dondur; veri gelince tekrar dene
  ├─ Her tick: grid yoksa yetim scalp/hedge'i kapat;
  │    DD/panik varsa hedge hedefini hesapla; sakinleşme varsa hedge'i kapat
  ├─ Sadece yeni kapanmış mumda: renk geçişi varsa scalp dene
  └─ Grid: rejime göre ilk giriş veya ATR adımıyla yeni katman
```

İlk bağlanmada son kapanmış mum hesaplanır ama eski sinyalden **ilk grid veya scalp açılmaz**. Açık grid varsa tick üzerinde yönetimi devam eder. Sinyaller yalnızca kapanmış mumlardan, fiyat tetikleri ise güncel Bid/Ask'tan gelir. Rejim değişikliği kapanmış mumla teyit edilir; intrabar koruma yalnızca sepet DD'si ve hesap stopudur.

### Rejim önceliği ve belirli kurallar

1. `REGIME_VOLATILE`: son kapanmış mum ATR'si, önceki `InpATRBaselineBars` kapanmış mumun ortalama ATR'sine göre `InpVolatileATRRatio` veya üstünde **ve** squeeze OFF. Defence: yeni grid/scalp yok, hedge açıksa devreye girer. Bu tanım her yüksek ATR olayını yakalamaz.
2. `REGIME_FAKEOUT`: önceki squeeze OFF iken yeniden ON olması veya momentum zayıflarken momentum yönünün kapanış/EMA ile çelişmesi. Defence.
3. `REGIME_TREND`: squeeze OFF, ADX ≥ trend eşiği, momentum aynı işarette güçleniyor ve kapanış/EMA yönü momentumla uyumlu. Hunter.
4. `REGIME_RANGE`: squeeze ON **veya** ADX ve ATR oranı kendi düşük eşiklerinin altında. Normal.
5. Diğer kombinasyonlar `REGIME_UNKNOWN`: Defence, yeni giriş yok. Bu kurallar istatistiksel olarak kanıtlanmış bir piyasa sınıflandırıcısı değildir.

## Katmanlar ve tasarım tipleri

- `MarketSnapshot`: kapanmış mum verileri, Squeeze, momentum, ADX, ATR, EMA, sinyal, rejim ve mod. `DetectMarketRegime()` öncelikli karar ağacıdır.
- `GridPlan`: `CalculateDynamicGrid()` tarafından hesaplanan yön, adım, lot ve dondurma durumu. Adım `ATR × InpGridATR × mod faktörü`; defence faktörü hesaplanır ama defence'de emir açılmaz. Hunter'da daha sık adım kullanılır. Lot `base × isteğe bağlı sınırlı bakiye faktörü × rejim çarpanı^(açık grid sayısı)` ve broker lot adımına aşağı yuvarlanır.
- `Exposure`: yalnızca aynı sembol ve ayrılmış magic numaralarına ait açık pozisyonları tarar. Yön, son grid giriş fiyatı, brüt lot ve yüzen P/L bu anlık taramadan yeniden kurulur. Grid `magic`, scalp `magic+1`, hedge `magic+2`. Aynı semboldeki her EA örneğine çakışmayan **en az 3 aralıklı** magic verin; aynı magic'leri başka EA veya elle açılan işlemlerde kullanmayın. Netting hesap reddedilir.
- Range'de ilk giriş orijinal renk dönüşüyle olur: kırmızı→bordo BUY, lime→green SELL. Mevcut grid yalnızca ters fiyat hareketinde katman ekler. Trendde ilk giriş EMA uyumlu ivmelenen momentum yönünde, eklemeler kâra giden yöndedir (piramitleme). Mevcut basket yönüne ters trendde ekleme durur; sistem açık basketi tersine çevirmek için otomatik kapatmaz veya karşı yönlü grid açmaz. Basket kapandıktan sonra uygun yeni mumda diğer yöne geçebilir.
- `ManageHedgingAndScalp()`: grid yüzen kaybı / hesap bakiyesi eşiği veya volatile rejimle hedge hedefi = grid net lotu × ters yön × oran. Açık hedge hedefe dahil edilir; grid SL/manuel kapanış sonucu hedge fazla kalırsa hedge kapatılıp sonraki tick'te yeniden hedeflenir. Grid kalmazsa tüm yetim katmanlar kapatılır. Hedge kilidinin çözülmesi için volatile olmaması, DD'nin alt eşiğe inmesi ve ardışık sakin kapanmış mum sayısı gerekir. Scalp, açık grid + yeni mumdaki orijinal renk dönüşüyle ve ATR bazlı broker SL/TP ile açılır; hedge veya defence sırasında açılmaz.

## Risk kontrolleri ve sınırlar

- `InpAllowTrading=false` varsayılanı **tüm gönderme/kapatma/iptal işlemlerini engeller**. Koruma sadece emir izni verilmişse çalışabilir; false, mevcut pozisyonları güvenli biçimde yönetme garantisi değildir.
- `InpMaxGridPositions`, `InpMaxScalps`, toplam **brüt** `InpMaxGrossLots` (grid+scalp+hedge), spread, broker lot/tick adımı, broker stop mesafesi, cooldown ve `OrderCalcMargin`/serbest marj kontrolü vardır. Brüt lot limiti hedge için rezerv ayırmaz: limit, minimum lot, spread, marj veya ret hedge'i kısmi ya da imkânsız kılabilir. Kilit garanti değildir. Hedge, scalp lotlarını değil grid net lotunu hedefler; gridin SL'si tetiklenince geçici aşırı hedge oluşabilir. Hedge'e sunucu tarafı SL konmaz; EA/terminal/bağlantı kesilirse veya kotasyon gelmezse açık kalabilir.
- Grid katmanlarında sunucu tarafı ATR-SL, scalpta ATR-SL/TP bulunur. Sepet hedefi grid+scalp+hedge `POSITION_PROFIT + POSITION_SWAP` toplamıdır; giriş/çıkış komisyonları ve son gerçekleşen kayma dahil değildir. Broker minimum stop mesafesi nedeniyle gerçek SL/TP uzaklığı istenenden büyük olabilir. Stoplar, boşluk veya kaymada fiyat garantisi vermez.
- Hesap devre kesici formülü **tüm hesap** için `(ACCOUNT_BALANCE - ACCOUNT_EQUITY) / ACCOUNT_BALANCE × 100`; başka EA/manuel işlemler de tetikleyebilir. Tetiklenince yalnızca bu sembol ve üç magic'e ait işlemler kapatılmaya çalışılır; diğer işlemler açık kalır. Bu bir maksimum gerçekleşen kayıp garantisi veya geçmiş tepe özsermaye takibi değildir. Piyasa kapalıyken/bağlantı kesildiğinde çalışmaz.
- `FLATTEN` ve acil `STOP` MetaTrader terminal global değişkenlerinde hesap+sembol+magic ile tutulur; kapanışlar reddedilir/kısmi gerçekleşirse sonraki tick'lerde tekrar denenir. Bu değişkenler terminale özeldir, başka terminale taşınmaz ve MT5 kullanılmayan global değişkenleri zamanla silebilir. Her işlemin kapandığını ve bekleyen emir kalmadığını terminalden doğrulayın. STOP, EA yeniden başlasa da otomatik sıfırlanmaz. Bilinçli sıfırlama: EA'yı kaldırın, risk durumunu ve tüm açık emirleri kontrol edin; terminalin F3 Global Variables ekranından ilgili `FDE.<hesap>.<sembol>.<magic>.S` değişkenini silin; `F` değerini yalnızca tüm işlemlerin kapandığı doğrulandıysa temizleyin. Eşik hâlâ aşılmışsa yeniden tetiklenir.
- İşlemler asenkron değildir, ancak sunucu kabulü gerçekleşme garantisi değildir; kısmi dolumlar ve aktif emirler sonraki tick'te yeniden taranır. Kapatma ardışık olduğundan atomik değildir. Marj, broker hedging politikası, freeze level, bağlantı, spread, requote, piyasa boşluğu ve yeniden başlatma korumaları bozabilir. Aynı magic ile iki eşzamanlı örnek çalıştırmayın.

## Başlıca yeni girdiler

| Grup | Girdiler | Anlam |
|---|---|---|
| Rejim | `InpATRPeriod`, `InpATRBaselineBars`, `InpADXPeriod`, `InpEMAPeriod`, `InpRangeADX`, `InpTrendADX`, `InpRangeATRRatio`, `InpVolatileATRRatio`, `InpReleaseConfirmBars` | Göstergeler, eşikler ve hedge çözülme teyidi |
| Grid | `InpBaseLot`, `InpGridATR`, `InpDefenseStepFactor`, `InpHunterStepFactor`, `InpRangeMultiplier`, `InpTrendMultiplier`, `InpMaxGridPositions`, `InpMaxGrossLots`, `InpBasketTargetMoney` | Mesafe, pozisyon ve brüt maruziyet sınırları; hedef hesap para birimindedir |
| Bileşik | `InpCompound`, `InpCompoundReferenceBalance`, `InpMaxCompoundFactor` | Bakiye bazlı, en az 1 ve en fazla belirlenen faktörle sınırlı büyütme; varsayılan kapalı |
| Kalkan/scalp | `InpEnableHedge`, `InpHedgeDrawdownPercent`, `InpHedgeReleasePercent`, `InpHedgeRatio`, `InpEnableScalp`, `InpScalpLot`, `InpMaxScalps`, `InpScalpSLATR`, `InpScalpTPATR`, `InpGridSLATR` | Hedge tetik/çözme ve broker tarafı fiyat seviyeleri |
| Güvenlik | `InpMagicNumber`, `InpDeviationPoints`, `InpMaxSpreadPoints`, `InpCooldownSeconds`, `InpMinFreeMarginPercent`, `InpAccountLossStopPercent`, `InpAllowTrading` | Emir ve kalıcı devre kesici sınırları |

Varsayılan sayılar örnektir, yatırım tavsiyesi veya optimize edilmiş değer değildir. Spread point cinsindendir; 0 filtreyi kapatır. `InpMinFreeMarginPercent=200` için serbest marj, yeni emrin hesaplanan marjının en az iki katı olmalıdır; bu hesap gelecekteki marjı veya stop-out'u garanti etmez.

## Kurulum ve doğrulama planı

1. `.mq5` dosyasını `MQL5/Experts` altına kopyalayın, MetaEditor'da derleyin ve tüm derleyici mesajlarını kontrol edin. MT5'te ayrı pozisyonlara izin veren hedging demo hesabı seçin. Algo Trading izinlerini ve sembol işlem koşullarını kontrol edin.
2. Strategy Tester'da `InpAllowTrading=true` ile gerçek tick, gerçekçi spread/komisyon/swap, gecikme ve farklı piyasa rejimleri kullanın; farklı dönemler ve örneklem dışı verilerde ölçün. Her testin terminal global STOP/FLATTEN durumunu kontrol edin.
3. Özellikle sınayın: squeeze ON→OFF ve fakeout; eksik geçmiş/gösterge verisi; grid yön değişiminde freeze; azami lot/adım; spread/marj reddi; kısmi dolum; hedge açılamaması; grid SL sonrası fazla/yetim hedge; hedge çözme teyidi; basket TP ve tüm katmanların kapanması; hesap DD stopu; restart ve kalıcı kilit; false→true izin değişimi; broker kapalı ve bağlantı kaybı. Netting hesapta başlatma başarısız olmalıdır.
4. Demo ileriye dönük testlerde broker journal ve tüm açık emirleri izleyin. Herhangi bir gerçek para kullanımı öncesi bağımsız MQL5 derlemesi, test ve risk kontrolü zorunludur.

Bu depoda `python3 -m unittest discover -s tests -v` yalnızca Squeeze çekirdeğinin değişmediğini ve birkaç statik yapı kontrolünü sınar; MQL derlemesi, emir simülasyonu veya işlem stratejisi doğrulaması değildir.

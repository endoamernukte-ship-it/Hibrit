# AlphaTrend Strategy — MT5

KivancOzbilgic'in kullanıcı tarafından verilen Pine Script v5 stratejisinin MT5 uyarlamasıdır. Orijinal kod ve uyarlama [MPL 2.0](https://mozilla.org/MPL/2.0/) kapsamındadır.

## Kurulum

1. MT5'te **Dosya → Veri Klasörünü Aç** seçeneğine girin. Yalnızca `AlphaTrend_EA.mq5` dosyasını `MQL5/Experts/` içine kopyalayın. EA, MT5 ile gelen standart kütüphane dışında başka dosyaya ihtiyaç duymaz.
2. MetaEditor'da `Experts/AlphaTrend_EA.mq5` dosyasını derleyin. İsteğe bağlı görsel indikatör için `AlphaTrend_Indicator.mq5` ve `AlphaTrendCore.mqh` dosyalarını birlikte `MQL5/Indicators/` içine kopyalayıp indikatörü ayrıca derleyin.
3. EA'yı istenen sembol ve zaman dilimindeki grafiğe ekleyin, lot miktarını kontrol edin ve algoritmik işlemlere izin verin. Görsel çizim isteniyorsa derlenmiş indikatörü aynı grafiğe ekleyin; indikatörün ayarlarını EA ile eşleştirin. **Show Signals** varsayılan olarak kapalıdır.
4. Önce Strategy Tester'da ve demo hesapta test edin. EA yalnızca çalışırken yeni mumlarda sinyal değerlendirir; geçmişteki sinyallere geriye dönük işlem açmaz.

## Strateji ve ayarlar

- Varsayılan periyot 14, çarpan 1, kaynak close, hacimsiz hesaplama kapalıdır. Pine'daki gibi `ATR = SMA(ta.tr, periyot)` kullanılır; Wilder ATR değildir.
- Hacimli modda HLC3 ve seçilen hacimle MFI, hacimsiz modda seçilen kaynakla Wilder RSI kullanılır. Pine'daki `src`, MFI'yi etkilemez. MT5'te seçilebilen kaynaklar OHLC, HL2, HLC3 ve OHLC4'tür; Pine'da başka bir indikatörün çıktısını kaynak seçme özelliği bu sürümde yoktur.
- AlphaTrend ile iki mum önceki AlphaTrend kesişimleri **filtrelenmeden** emir üretir. Pine kodundaki `O1 > K2` / `O2 > K1` yalnızca gösterilen işaretleri filtreler, işlemleri filtrelemez. MT5 indikatöründeki oklar Pine'daki metinli etiketlerin yerine geçer; açık mumdaki görsel sinyal mum kapanana kadar değişebilir.
- Bir mum kapanınca ilk yeni mum tick'inde piyasa emri gönderilir. Aynı yönde pozisyon varsa yeni pozisyon açılmaz; ters yöndeki EA pozisyonu kapatılıp yeni yönde belirtilen lot açılır. SL, TP veya başka filtre eklenmemiştir. Pozisyon kapatma başarısız/eksikse ters işlem açılmaz; reddedilen emir aynı sinyal için tekrar denenmez.
- Pine'ın varsayılan miktarı sembolün kendi birimindedir; MT5 `InpLots` ise broker lotudur. Sözleşme büyüklüğüne göre uygun dönüşümü kendiniz yapın. Varsayılan 0.01 lot otomatik olarak Pine'ın bir birimine eşit değildir.
- EA yalnızca aynı sembol ve magic numaralı pozisyonlarını yönetir. Netting hesapta aynı sembolde farklı magic numaralı pozisyon varsa, onu değiştirmemek için sinyal atlanır. Aynı sembolde birden fazla EA veya manuel işlem kullanılması önerilmez. Pozisyon açma ve kapama iki ayrı broker işlemi olduğu için Pine'ın tek simüle edilmiş ters emriyle bire bir aynı dolum değildir.

## Eşleşme sınırları

TradingView ve MT5'in OHLC verisi, seans/zaman dilimi, geçmişin başlangıcı, hacim, spread, komisyon, kayma ve emir dolumları farklı olabilir. MT5'te varsayılan tick hacmidir; borsanın gerçek hacmi varsa `AT_REAL_VOLUME` seçilebilir. Veri sağlayıcısı hacim sunmuyorsa RSI modunu seçin; bu, orijinaldeki hacimsiz seçeneği açmakla aynıdır ve MFI ile aynı sonuç değildir. MFI'de sıfır hacim penceresi `na` kabul edilir.

Hesaplama en son `InpHistoryBars` mum üzerinden yeniden başlatılır (varsayılan 20000, açık mum dahil). Pine'ın geçmiş başlangıcı ve mevcut veriler farklıysa RSI ve AlphaTrend'in özyinelemeli başlangıcı nedeniyle sonuçlar farklı olabilir; EA ve indikatörde aynı geçmiş miktarını kullanın ve yeterli geçmiş yükleyin. Bu nedenle platformlar arası bire bir sonuç garanti edilemez. TradingView'in varsayılan sonraki mum açılışı simülasyonu ile canlı MT5'in ilk işlem yapılabilir Bid/Ask fiyatı da farklıdır.

Bu ortamda MetaEditor/MT5 bulunmadığından derleme ve TradingView ile gerçek veri üzerinde karşılaştırma ayrıca yapılmalıdır.

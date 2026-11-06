# Chameleon Hybrid EA — kurulum ve sınırlar

`Chameleon_Hybrid_EA.mq5` tek sembolde çalışan bir MT5 Expert Advisor kaynak dosyasıdır. Üretim veya yatırım tavsiyesi değildir; önce MetaEditor ile derleyin, Strategy Tester ve demo hesapta doğrulayın. Bu ortamda MetaEditor bulunmadığından derleme ve MT5 testleri yapılmamıştır.

## Kurulum

1. MT5'te **Dosya → Veri Klasörünü Aç → MQL5 → Experts** klasörüne `.mq5` dosyasını kopyalayın.
2. MetaEditor'da açıp **F7** ile derleyin; hataları ve uyarıları inceleyin. MT5 Navigator'ı yenileyin.
3. Önce Strategy Tester'da mümkünse gerçek tick, broker spread, komisyon, swap ve gecikmeyle test edin. Ardından demo grafiğine ekleyin ve algoritmik işlemlere izin verin.
4. Gerçek hesapta giriş varsayılan olarak kapalıdır (`InpAllowLive=false`); bu ayarın açılması güvenlik veya kârlılık garantisi vermez.
5. Aynı hesap/sembol/magic kombinasyonunda yalnızca tek instance çalıştırın. Her instance için ayrı magic kullanın. Netting hesabında aynı sembol başka EA veya manuel işlemlerle paylaşılmamalıdır.

## Uygulanan davranış

- Kapanmış barlardan ATR/ADX/EMA, yön verimliliği ve önceki aralığa göre dört rejim: yatay, yönlü trend, panik ve sahte kırılım. Parametreler araştırma amaçlı başlangıç değerleridir; algoritma önceki kavramsal ağırlıklı skor formülünün birebir uygulaması değildir. Fakeout diğer normal rejimler gibi bar bazlı teyit ister; bu nedenle tek barlık olaylar kaçırılabilir.
- Grid bekleyen emirlerden değil, mevcut fiyata göre aralıklı **piyasa emirlerinden** oluşur. Trend modunda trend yönünde, fiyat son girişe karşı ATR mesafesi kadar geri çekildiğinde yeni kademe değerlendirilir. Yatay modda aralık kenarı ve momentum koşulu aranır. Kademeler katlanmaz. Trend pozisyonlarında trailing uygulanır. Kapanan kademelerden sonraki yeni işlem riski güncel özsermayeden hesaplanır; gerçekleşmemiş kârla sınırsız piramitleme yapılmaz.
- Range scalp, aralık kenarında küçük ayrı piyasa işlemi olarak çalışır ve grid ile aynı pozisyon/risk/işlem sıklığı limitlerini paylaşır. Bar başına en fazla bir başarılı scalp gönderimi hedeflenir. Fakeout bir aktivasyonda en fazla bir başarılı giriş yapar.
- Rejim değişiminde mevcut EA emirleri iptal edilir ve EA pozisyonları kapatılır; sunucudaki emir/pozisyon listesi boşalana kadar yeni plana geçilmez. Her tick/timer'da tekrar denenir. Başarılı gönderim, tüm piyasa riskinin sona erdiğinin garantisi değildir.
- Panik rejiminde pozisyonlar kapatılmaya çalışılır ve yeni giriş durdurulur. İsteğe bağlı intrabar şok hedge'i (`InpEnableHedge=true`), yalnızca hedging hesaplarda, kayıptaki sepet ve şok eşiği birlikte oluştuğunda, net hacmin en fazla belirlenen yüzdesi kadar ters işlem açmayı dener. İşlem aynı risk, marjin, spread, pozisyon ve sıklık limitlerine tabidir; açılamazsa kapatma denenir. Başarılı hedge panik durumunda sonraki teyitli rejim geçişinde kapatılır. Stopların farklı zamanlarda tetiklenmesi hedge'i ters net pozisyona çevirebilir. Netting hesapta hedge yerine kapatma denenir.
- Her işlem için stop ve hedef, ATR bazlıdır. Risk hesabı açık pozisyonlarda mevcut fiyattan stopa kalan tahmini kayıp ve maliyet tamponunu kullanır. Bu yalnızca mevcut sembol/magic pozisyonlarını kapsar; diğer EA'lar veya semboller hesaba katılmaz. Bu nedenle gerçek portföy düzeyinde toplam risk limiti değildir.
- Günlük limit, broker sunucu gününde bu instance'ın o gün ilk gözlediği hesap özsermayesine göre **hesap genelindeki** değişimi ölçer. Sepet limiti ise bu EA'nın sembol/magic açık pozisyonlarının anlık kâr/zarar ve swap toplamıdır; komisyon dahil değildir. Para yatırma/çekme ve terminal kapalıyken gerçekleşen değişimler ölçümü bozabilir.
- HALT terminal global değişkeninde kalıcıdır; gün değişince otomatik sıfırlanmaz. HALT sürekli kapatma/iptal dener. İnceleme sonrasında EA'yı durdurup MT5 **Araçlar → Global Değişkenler** üzerinden `CHM.<hesap>.<sembol>.<magic>.halt` anahtarını silerek manuel sıfırlayın. Günlük kayıp eşiği hâlâ ihlal edilmişse yeniden HALT olur; günlük day/equity anahtarlarını silmek korumayı sıfırlar ve dikkatli değerlendirilmelidir. Terminal global değişkenleri terminale özgüdür; başka terminalle paylaşılmaz.
- EA yeniden başlatıldığında kendi mevcut pozisyon/emirlerini önce kapatmaya çalışır. EA kaldırıldığında pozisyonlar otomatik kapanmaz. Bağlantı yoksa, piyasa kapalıysa, işlem izni yoksa veya broker reddederse kapatma gerçekleşmeyebilir.

## Bilinen sınırlar ve canlı öncesi yapılması gerekenler

Ekonomik takvim/haber filtresi, gerçek order-book likidite analizi, korelasyon kümeleri, portföy genelinde açık risk, tam işlem maliyeti ve kurumsal düzeyde kalıcı emir olay günlüğü **uygulanmamıştır**. Spread/ATR kontrolleri haber riskinin yerine geçmez. Bu, ML/AI eğitimi içeren bir sistem veya gerçek HFT değildir.

Timer bayat veriyi tespit etmeye çalışır; bağlantı kesintisinde broker sunucu zamanı, fiyat ve kapatma işlemleri güvenilir olmayabilir. Stop ve maliyet hesabı gap/kayma/komisyonu tam garanti etmez. Pozisyon açılışı ve kapatılması broker kurallarına bağlıdır; ret mesajlarını Experts günlüğünden inceleyin. Hesabın margin modeli, sembol işlem modu, hacim adımı, minimum stop/freeze mesafeleri ve test sonuçları broker bazında doğrulanmalıdır. Optimizasyonu ayrılmış örneklem ve walk-forward ile sınayın; aşırı uyumdan kaçının.

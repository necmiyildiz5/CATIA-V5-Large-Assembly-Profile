# CATIA V5 Büyük Montaj Profili

`CATIA-LargeAssembly-Profile.ps1`, mevcut CATIA environment dosyasını klonlayarak büyük montaj için ayrı bir çalışma profili üretir. Mevcut environment dosyasını veya mevcut `CATUserSettingPath` değerini değiştirmez.

## Çalıştırma

PowerShell veya komut yazmanıza gerek yoktur. `CATIA-Buyuk-Montaj-Profilini-Baslat.cmd` dosyasına çift tıklayın.

Başlatıcı ve `.ps1` dosyası aynı klasörde kalmalıdır. Başlatıcı yalnız bu yanındaki betiği çalıştırır ve Windows'un `RemoteSigned` politikasıyla başlatır; genel yürütme politikasını değiştirmez.

Uygulamada **Profili oluştur** düğmesine basın. Varsayılan hedefler kullanıcı profilindeki `DassaultSystemes\CATEnv` ve `CATSettings_LargeAssembly` klasörleridir. "Hızlı açılış" seçeneği başlangıç dokümanını, açılış ekranını ve arka planı yalnızca bu profile kapatır.

İleri seviyede `CATSTART.exe` dosyası seçilebilir. Araç, yeni environment adıyla CATIA'yı açan bir masaüstü kısayolu oluşturur. Kısayol simgesi doğrulanan CATIA `CATSTART.exe` dosyasından alınır.

## Sonraki CATIA ayarları

Araç yeni CATSettings klasöründe `CATIA_Settings_Plan.json` ve bir CATIA makrosu oluşturur. Masaüstü kısayoluyla ilk CATIA açılışında makro aşağıdaki ayarları uygular. Cache etkinliği için CATIA'nın kapatılıp bu kısayolla yeniden başlatılması gerekir.

Araç, kaynak environment'ın aktif CATSettings klasöründe bulunan `licenses.CATSettings` dosyasını da yeni profile kopyalar. Yeni profilde bir lisans dosyası zaten varsa üzerine yazmaz.

- Product Structure → Cache Management: cache sistemi açık; cache kapasitesi araçta seçilen değer (varsayılan 10 GB).
- Display → Performance: 3D Fixed `0.10`, Curves ratio `0.10`, 2D Fixed `0.02`, LOD Static `0.5`, LOD While Moving `13.5`, Pixel Culling Static `2`, While Moving `14`, Transparency `Low`.
- Part Infrastructure → Part Document: Hybrid Design kapalı.

## Güvenlik

Araç ağ bağlantısı kurmaz, telemetri veya indirme yapmaz. Yalnızca Dassault `CATEnv` klasörlerinden kaynak dosya kabul eder; yeni environment'ı kullanıcı `CATEnv` klasörüne, ayarları ise kullanıcı `DassaultSystemes\CATSettings_...` klasörüne yazar. Ayrıntılar için [SECURITY.md](SECURITY.md) belgesine bakın.

GitHub'a yüklerken oluşturulmuş `CATSettings`, lisans dosyaları, environment kopyaları, günlükler ve masaüstü kısayollarını paylaşmayın.

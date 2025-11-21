# Yolbil iOS Örnek Şablon

Bu proje, Yolbil SDK'sını kullanarak iOS uygulaması geliştirmek için bir başlangıç şablonudur.

## Kurulum

### 1. Swift Package Manager (SPM) ile Paket Ekleme

1. Xcode'da projenizi açın
2. **File** → **Add Package Dependencies** menüsüne gidin
3. Aşağıdaki repository URL'sini girin:
   ```
   https://github.com/basarsoft-arge/basarsoft-pod-repo.git
   ```
4. İstediğiniz paketleri seçin ve projenize ekleyin
5. Xcode otomatik olarak paketleri indirecek ve projenize entegre edecektir

### 2. Secrets.swift Dosyası Oluşturma

Projeyi çalıştırmak için API kimlik bilgilerinizi içeren bir `Secrets.swift` dosyası oluşturmanız gerekiyor:

1. `Secrets.swift.template` dosyasını kopyalayın
2. Kopyalanan dosyayı `Secrets.swift` olarak yeniden adlandırın
3. `Secrets.swift` dosyasını açın ve aşağıdaki değerleri kendi bilgilerinizle değiştirin:
   - `YOUR_APP_CODE_HERE` → Yolbil dashboard'unuzdan aldığınız App Code
   - `YOUR_ACCOUNT_ID_HERE` → Yolbil dashboard'unuzdan aldığınız Account ID

**Önemli:** `Secrets.swift` dosyası hassas bilgiler içerdiği için Git'e commit edilmemelidir. `.gitignore` dosyasına eklenmiştir.

### 3. MapView.swift - Render Ayarları

`MapView.swift` dosyasının 152-154 satırlarında harita render ayarı bulunmaktadır:

```swift
// Render KAPATMA
// Çizimi geçici olarak devre dışı bırak
newMapView.setRenderDisabled(false)
```

**Açıklama:**
- `setRenderDisabled(false)` → Harita render'ı **aktif** eder (harita görüntülenir)
- `setRenderDisabled(true)` → Harita render'ı **devre dışı** bırakır (harita görüntülenmez)
- Varsayılan olarak `false` ayarlanmıştır, yani harita normal şekilde çalışır
- Eğer harita görüntülenmiyorsa veya performans sorunları yaşıyorsanız, bu ayarı kontrol edin

## Kullanım

1. Tüm paketler yüklendikten sonra projeyi build edin
2. `Secrets.swift` dosyasını oluşturduğunuzdan emin olun
3. Uygulamayı çalıştırın

## Destek

Teknik destek ve dokümantasyon için:
- Email: arge@basarsoft.com.tr
- Website: https://www.basarsoft.com.tr


import Foundation
import Combine
import YolbilMobileSDK

/// Turn-by-turn navigasyon servisi
/// Gerçek zamanlı navigasyon bilgilerini yönetir ve UI'a iletir
///
/// ## Kullanım Örneği:
/// ```swift
/// let navigationService = NavigationService()
/// 
/// // Navigasyonu başlat
/// navigationService.startNavigation(
///     mapView: mapView,
///     from: startLocation,
///     to: endLocation,
///     routeType: .car,
///     locationSource: gpsSource
/// )
/// 
/// // Navigasyon bilgilerini dinle
/// navigationService.$navigationInfo
///     .sink { info in
///         print("Kalan: \(info?.remainingDistance ?? "")")
///     }
///     .store(in: &cancellables)
/// 
/// // Navigasyonu durdur
/// navigationService.stopNavigation()
/// ```
class NavigationService: ObservableObject {
    
    // MARK: - Published Properties
    
    /// Mevcut navigasyon bilgisi (kalan süre, mesafe, komut)
    @Published var navigationInfo: NavigationInfo?
    
    /// Navigasyon aktif mi?
    @Published var isNavigating: Bool = false
    
    /// Hata mesajı (varsa)
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    
    /// Navigasyon bundle'ı
    private var navigationBundle: YBYolbilNavigationBundle?
    
    /// Navigasyon katmanı referansı
    private var navigationLayer: YBLayer?
    
    /// Komut dinleyici
    private var commandListener: NavigationCommandListener?
    
    /// BlueDot veri kaynağı
    private var blueDotDataSource: YBBlueDotDataSource?
    
    /// BlueDot katmanı
    private var blueDotLayer: YBVectorLayer?
    
    /// MapView referansı
    private weak var mapView: YBMapView?
    
    // MARK: - Initialization
    
    init() {
        print("[NavigationService] Başlatıldı")
    }
    
    // MARK: - Public Methods
    
    /// Turn-by-turn navigasyonu başlatır
    /// - Parameters:
    ///   - mapView: Harita görünümü
    ///   - from: Başlangıç konumu
    ///   - to: Bitiş konumu
    ///   - routeType: Rota tipi (.car, .truck, .pedestrian)
    ///   - locationSource: GPS konum kaynağı
    func startNavigation(
        mapView: YBMapView,
        from start: LocationData,
        to end: LocationData,
        routeType: RouteRequest.RouteType,
        locationSource: GPSLocationSource
    ) {
        self.mapView = mapView
        
        // Önceki navigasyonu durdur
        stopNavigation()
        
        print("[NavigationService] Navigasyon başlatılıyor...")
        print("[NavigationService] Başlangıç: \(start.latitude),\(start.longitude)")
        print("[NavigationService] Bitiş: \(end.latitude),\(end.longitude)")
        
        // Projeksiyon kontrolü
        guard let projection = mapView.getOptions()?.getBaseProjection() else {
            errorMessage = "Projeksiyon alınamadı"
            return
        }
        
        // Koordinatları dönüştür
        guard let startPos = start.mapPosition(with: projection),
              let endPos = end.mapPosition(with: projection) else {
            errorMessage = "Koordinatlar dönüştürülemedi"
            return
        }
        
        // Navigation bundle oluştur
        let builder = YBYolbilNavigationBundleBuilder(
            baseUrl: "https://services.basarsoft.com.tr",
            apiKey: Secrets.apiKey,
            locationSource: locationSource
        )
        
        // Rota tipini ayarla
        switch routeType {
        case .car:
            builder?.setIsCar(true)
        case .truck:
            builder?.setIsTruck(true)
        case .pedestrian:
            builder?.setIsPedestrian(true)
        }
        
        builder?.setAlternativeRoute(false)
        
        // Kendi BlueDot katmanımızı kullanıyoruz, bundle'ın BlueDot'unu devre dışı bırak
        // Bu sayede navigasyon başlatıldığında BlueDot kaybolmaz
        builder?.setBlueDotDataSourceEnabled(false)
        
        // Komut dinleyiciyi oluştur ve bağla
        let listener = NavigationCommandListener()
        listener?.owner = self
        builder?.setCommandListener(listener)
        self.commandListener = listener
        
        // Bundle'ı oluştur (Kotlin'deki gibi hata yakalama)
        // iOS'ta build() optional döndürüyor, bu yüzden guard kullanıyoruz
        guard let bundle = builder?.build() else {
            errorMessage = "Navigasyon bundle'ı oluşturulamadı"
            print("[NavigationService] getNavigationBundle build failed")
            return
        }
        self.navigationBundle = bundle
        
        // Navigasyon katmanını haritaya ekle
        if let navLayer = bundle.getNavigationLayer(),
           let layers = mapView.getLayers() {
            layers.add(navLayer)
            self.navigationLayer = navLayer
            
            // BlueDot'un en üstte kalmasını sağla (navigasyon katmanından sonra tekrar ekle)
            if let blueDot = blueDotLayer {
                layers.remove(blueDot)
                layers.add(blueDot)
                print("[NavigationService] BlueDot en üste taşındı")
            }
        }
        
        // Arka planda rota hesapla ve navigasyonu başlat
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            
            // Rota hesaplama (Kotlin'deki gibi hata yakalama)
            // iOS'ta startNavigation NSException throw edebilir, bu yüzden optional olarak kontrol ediyoruz
            guard let results = bundle.startNavigation(startPos, to: endPos),
                  results.size() > 0,
                  let firstRaw = results.get(0),
                  let navResult = YBNavigationResult.swigCreatePolymorphicInstance(firstRaw.getCptr(), swigOwnCObject: false) else {
                DispatchQueue.main.async {
                    self.errorMessage = "Rota hesaplanamadı"
                    self.isNavigating = false
                }
                print("[NavigationService] Navigation calculation returned no results")
                return
            }
            
            // Rota noktaları kontrolü (Kotlin'deki gibi: pointCount == 0 kontrolü)
            let pointCount = navResult.getPoints()?.size() ?? 0
            if pointCount == 0 {
                DispatchQueue.main.async {
                    self.errorMessage = "Rota noktası boş döndü"
                    self.isNavigating = false
                }
                print("[NavigationService] Navigation points empty; skipping beginNavigation")
                return
            }
            
            // Navigasyonu başlat (Kotlin'deki gibi beginNavigation hata yakalama)
            // iOS'ta beginNavigation void döndürüyor, hata durumunda nil dönebilir veya exception throw edebilir
            // Güvenli çağrı için kontrol ediyoruz
            bundle.beginNavigation(navResult)
            
            // İlk bilgileri güncelle
            let initialInfo = NavigationInfo.from(
                totalDistance: navResult.getTotalDistance(),
                totalTime: navResult.getTotalTime()
            )
            
            DispatchQueue.main.async {
                self.isNavigating = true
                self.navigationInfo = initialInfo
            }
        }
    }
    
    /// Navigasyonu durdurur ve kaynakları temizler
    /// Kotlin'deki gibi hata yakalama ile güvenli temizleme
    func stopNavigation() {
        // Bundle'ı durdur
        navigationBundle?.stopNavigation()
        
        // Sadece navigasyon katmanını kaldır (BlueDot'u koru)
        // Kotlin'deki gibi runCatching ile hata yakalama
        if let mapView = mapView, let layers = mapView.getLayers() {
            // Navigasyon katmanını güvenli şekilde kaldır
            if let navLayer = navigationLayer {
                do {
                    try layers.remove(navLayer)
                } catch {
                    print("[NavigationService] Navigation layer remove failed: \(error.localizedDescription)")
                }
            }
            
            // BlueDot katmanını kaldırma - navigasyon durduğunda da görünür kalmalı
        }
        
        // Referansları temizle
        navigationBundle = nil
        navigationLayer = nil
        commandListener = nil
        navigationInfo = nil
        isNavigating = false
        errorMessage = nil
        
        print("[NavigationService] Navigasyon durduruldu ve temizlendi (BlueDot korundu)")
    }
    
    // MARK: - BlueDot Methods
    
    /// BlueDot katmanını haritaya ekler
    /// - Parameters:
    ///   - mapView: Harita görünümü
    ///   - locationSource: GPS konum kaynağı
    ///   - initialLocation: İlk konum (opsiyonel)
    func addBlueDotLayer(to mapView: YBMapView, locationSource: GPSLocationSource, initialLocation: LocationData? = nil) {
        guard let projection = YBEPSG4326() else {
            print("[NavigationService] BlueDot için projeksiyon oluşturulamadı")
            return
        }
        
        // BlueDot veri kaynağı oluştur
        guard let dataSource = YBBlueDotDataSource(projection: projection, locationSource: locationSource) else {
            print("[NavigationService] BlueDot veri kaynağı oluşturulamadı")
            return
        }
        
        // BlueDot'u başlat
        dataSource.init()
        
        // Varsayılan marker'ı kullan (mavi nokta)
        dataSource.useDefaultCenterBitmapMarker(25.0) // 25 piksel boyut
        
        // İlk konum varsa BlueDot'u güncelle
        if let initialLocation = initialLocation,
           let mapPos = initialLocation.mapPosition(with: projection) {
            let locationBuilder = YBLocationBuilder()
            locationBuilder?.setCoordinate(mapPos)
            
            if let location = locationBuilder?.build() {
                dataSource.updateBlueDot(location)
                print("[NavigationService] BlueDot ilk konumla güncellendi: \(initialLocation.latitude), \(initialLocation.longitude)")
            }
        }
        
        self.blueDotDataSource = dataSource
        
        // BlueDot katmanı oluştur
        guard let layer = YBVectorLayer(dataSource: dataSource) else {
            print("[NavigationService] BlueDot katmanı oluşturulamadı")
            return
        }
        
        // Haritaya ekle (en üste ekle ki diğer katmanların üstünde görünsün)
        guard let layers = mapView.getLayers() else {
            print("[NavigationService] Harita katmanları alınamadı")
            return
        }
        
        // Önce varsa kaldır (tekrar eklemeyi önlemek için)
        if let existingLayer = blueDotLayer {
            layers.remove(existingLayer)
        }
        
        // En üste ekle
        layers.add(layer)
        self.blueDotLayer = layer
        self.mapView = mapView
        
        // Haritanın render'ını aktif et (eğer kapalıysa)
        mapView.setRenderDisabled(false)
        
        print("[NavigationService] BlueDot katmanı eklendi ve en üste yerleştirildi")
    }
    
    /// BlueDot katmanını kaldırır
    func removeBlueDotLayer() {
        guard let mapView = mapView,
              let layers = mapView.getLayers(),
              let layer = blueDotLayer else { return }
        
        layers.remove(layer)
        blueDotLayer = nil
        blueDotDataSource = nil
        
        print("[NavigationService] BlueDot katmanı kaldırıldı")
    }
    
    // MARK: - Mock GPS Methods
    
    /// Mock GPS konumu gönderir (test/development amaçlı)
    /// - Parameters:
    ///   - locationSource: GPS konum kaynağı
    ///   - latitude: Enlem (WGS84)
    ///   - longitude: Boylam (WGS84)
    func sendMockLocation(locationSource: GPSLocationSource, latitude: Double, longitude: Double) {
        guard let projection = YBEPSG4326() else {
            print("[NavigationService] Mock location için projeksiyon oluşturulamadı")
            return
        }
        
        // WGS84 koordinatlarını MapPos'a çevir
        let wgs84Pos = YBMapPos(x: longitude, y: latitude)
        guard let mapPos = projection.fromWgs84(wgs84Pos) else {
            print("[NavigationService] Mock location koordinatları dönüştürülemedi")
            return
        }
        
        // Mock location'ı gönder
        locationSource.sendMockLocation(mapPos)
        
        // BlueDot'u manuel olarak güncelle (eğer varsa)
        if let blueDotDataSource = blueDotDataSource {
            let locationBuilder = YBLocationBuilder()
            locationBuilder?.setCoordinate(mapPos)
            
            if let location = locationBuilder?.build() {
                blueDotDataSource.updateBlueDot(location)
                print("[NavigationService] BlueDot mock location ile güncellendi")
            }
        }
        
        print("[NavigationService] Mock location gönderildi: \(latitude), \(longitude)")
    }
    
    /// Mock GPS konumu gönderir (MapPos ile)
    /// - Parameters:
    ///   - locationSource: GPS konum kaynağı
    ///   - mapPos: Harita koordinatları
    func sendMockLocation(locationSource: GPSLocationSource, mapPos: YBMapPos) {
        // Mock location'ı gönder
        locationSource.sendMockLocation(mapPos)
        
        // BlueDot'u manuel olarak güncelle (eğer varsa)
        if let blueDotDataSource = blueDotDataSource {
            let locationBuilder = YBLocationBuilder()
            locationBuilder?.setCoordinate(mapPos)
            
            if let location = locationBuilder?.build() {
                blueDotDataSource.updateBlueDot(location)
                print("[NavigationService] BlueDot mock location ile güncellendi")
            }
        }
        
        print("[NavigationService] Mock location gönderildi: \(mapPos.getX()), \(mapPos.getY())")
    }
    
    deinit {
        stopNavigation()
    }
}

// MARK: - Navigation Command Listener

/// Navigasyon komutlarını dinleyen sınıf
/// SDK'dan gelen komutları alır ve NavigationInfo'ya dönüştürür
private class NavigationCommandListener: YBCommandListener {
    
    /// Owner referansı (weak)
    weak var owner: NavigationService?
    
    // MARK: - YBCommandListener Methods
    
    /// Yeni bir navigasyon komutu hazır olduğunda çağrılır
    override func onCommandReady(_ command: YBNavigationCommand!) -> Bool {
        guard let command = command else { return false }
        DispatchQueue.main.async { [weak self] in
            self?.owner?.handleNavCommand(command)
        }
        return false // Diğer listener'ların da almasına izin ver
    }
    
    /// Navigasyon başladığında çağrılır
    override func onNavigationStarted() -> Bool {
        DispatchQueue.main.async { [weak self] in
            self?.owner?.handleNavStarted()
        }
        return false
    }
    
    /// Navigasyon durduğunda çağrılır
    override func onNavigationStopped() -> Bool {
        DispatchQueue.main.async { [weak self] in
            self?.owner?.handleNavStopped()
        }
        return false
    }
    
    /// Konum değiştiğinde çağrılır
    override func onLocationChanged(_ command: YBNavigationCommand!) -> Bool {
        guard let command = command else { return false }
        DispatchQueue.main.async { [weak self] in
            self?.owner?.handleNavCommand(command)
        }
        return false
    }
    
    /// Rota yeniden hesaplandığında çağrılır
    override func onNavigationRecalculated(_ navigationResult: YBNavigationResult!) -> Bool {
        guard let result = navigationResult else { return false }
        DispatchQueue.main.async { [weak self] in
            self?.owner?.handleNavRecalculated(result)
        }
        return false
    }
}

// MARK: - NavigationService Command Handlers

extension NavigationService {
    
    /// Navigasyon komutunu işler (Kotlin'deki gibi totalDistanceToCommand ve remainingTimeInSec kullanarak)
    fileprivate func handleNavCommand(_ command: YBNavigationCommand) {
        // Kotlin'deki gibi: command.totalDistanceToCommand ve command.remainingTimeInSec kullan
        if let info = NavigationInfo.fromRemaining(
            distanceMeters: command.getTotalDistanceToCommand(),
            timeSeconds: command.getRemainingTimeInSec(),
            command: localizedCommand(from: command),
            distanceToCommand: command.getDistanceToCommand()
        ) {
            navigationInfo = info
        }
    }
    
    /// Navigasyon başladığında çağrılır
    fileprivate func handleNavStarted() {
        isNavigating = true
        print("[NavigationService] Navigasyon başladı")
    }
    
    /// Navigasyon durduğunda çağrılır
    fileprivate func handleNavStopped() {
        isNavigating = false
        navigationInfo = nil
        print("[NavigationService] Navigasyon durdu")
    }
    
    /// Rota yeniden hesaplandığında çağrılır
    fileprivate func handleNavRecalculated(_ navigationResult: YBNavigationResult) {
        // Kotlin'deki gibi: NavigationResult'tan NavigationInfo oluştur
        let info = NavigationInfo.from(
            totalDistance: navigationResult.getTotalDistance(),
            totalTime: navigationResult.getTotalTime(),
            command: "Rota güncellendi"
        )
        navigationInfo = info
        print("[NavigationService] Rota yeniden hesaplandı")
    }
    
    /// Komutu Türkçe'ye çevirir (yolbilTest'teki yaklaşımı kullanarak)
    private func localizedCommand(from command: YBNavigationCommand) -> String {
        let raw = (command.description() ?? "").uppercased()
        
        // Dönel kavşak çıkışları
        if raw.contains("TAKE_FIRST_EXIT_ON_ROUNDABOUT") { return "Dönel kavşaktan birinci çıkıştan çık" }
        if raw.contains("TAKE_SECOND_EXIT_ON_ROUNDABOUT") { return "Dönel kavşaktan ikinci çıkıştan çık" }
        if raw.contains("TAKE_THIRD_EXIT_ON_ROUNDABOUT") { return "Dönel kavşaktan üçüncü çıkıştan çık" }
        if raw.contains("TAKE_FOURTH_EXIT_ON_ROUNDABOUT") { return "Dönel kavşaktan dördüncü çıkıştan çık" }
        if raw.contains("TAKE_FIFTH_EXIT_ON_ROUNDABOUT") { return "Dönel kavşaktan beşinci çıkıştan çık" }
        if raw.contains("TAKE_SIXTH_EXIT_ON_ROUNDABOUT") { return "Dönel kavşaktan altıncı çıkıştan çık" }
        
        // Sağ dönüşler
        if raw.contains("TURN_RIGHT_SHARP") { return "Keskin sağa dön" }
        if raw.contains("TURN_FAR_RIGHT") { return "Uzak sağa dön" }
        if raw.contains("TURN_SECOND_RIGHT") { return "İkinci sağa dön" }
        if raw.contains("TURN_THIRD_RIGHT") { return "Üçüncü sağa dön" }
        if raw.contains("TURN_RIGHT_AT_THE_END_OF_ROAD") { return "Yolun sonunda sağa dön" }
        if raw.contains("TURN_RIGHT_ONTO_ACCOMODATION") { return "Konaklama noktasına doğru sağa dön" }
        if raw.contains("TURN_RIGHT") { return "Sağa dön" }
        
        // Sol dönüşler
        if raw.contains("TURN_LEFT_SHARP") { return "Keskin sola dön" }
        if raw.contains("TURN_FAR_LEFT") { return "Uzak sola dön" }
        if raw.contains("TURN_SECOND_LEFT") { return "İkinci sola dön" }
        if raw.contains("TURN_THIRD_LEFT") { return "Üçüncü sola dön" }
        if raw.contains("TURN_LEFT_AT_THE_END_OF_ROAD") { return "Yolun sonunda sola dön" }
        if raw.contains("TURN_LEFT_ONTO_ACCOMODATION") { return "Konaklama noktasına doğru sola dön" }
        if raw.contains("TURN_LEFT") { return "Sola dön" }
        
        // Kal/Devam et
        if raw.contains("STAY_RIGHT") { return "Sağda kal" }
        if raw.contains("CONTINUE_RIGHT") { return "Sağa devam et" }
        if raw.contains("STAY_LEFT") { return "Solda kal" }
        if raw.contains("CONTINUE_LEFT") { return "Sola devam et" }
        if raw.contains("CONTINUE_MIDDLE") { return "Ortadan devam et" }
        
        // U dönüşü
        if raw.contains("UTURN") { return "U dönüşü yap" }
        
        // Tünel ve geçitler
        if raw.contains("ABOUT_THE_ENTER_TUNNEL") { return "Tünele girmek üzeresiniz" }
        if raw.contains("IN_TUNNEL") { return "Tünelin içindesiniz" }
        if raw.contains("AFTER_TUNNEL") { return "Tünelden sonra devam et" }
        if raw.contains("UNDERPASS") { return "Alt geçitten geç" }
        if raw.contains("OVERPASS") { return "Üst geçitten geç" }
        
        // Diğer
        if raw.contains("PEDESTRIAN_ROAD") { return "Yaya yoluna dikkat et" }
        if raw.contains("SERVICE_ROAD") { return "Hizmet yoluna gir" }
        if raw.contains("EXCEEDED_THE_SPEED_LIMIT") { return "Hız sınırını aştınız" }
        if raw.contains("WILL_REACH_YOUR_DESTINATION") { return "Hedefinize ulaşmak üzeresiniz" }
        if raw.contains("REACHED_YOUR_DESTINATION") { return "Hedefinize ulaştınız" }
        if raw.contains("GO_STRAIGHT") { return "Düz devam et" }
        
        // Fallback
        return formatCommandText(command.description() ?? "")
    }
    
    /// Komut metnini temizler ve formatlar
    private func formatCommandText(_ text: String) -> String {
        let collapsed = text.components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        if collapsed.count > 120 {
            let idx = collapsed.index(collapsed.startIndex, offsetBy: 120)
            return String(collapsed[..<idx]) + "…"
        }
        return collapsed
    }
}


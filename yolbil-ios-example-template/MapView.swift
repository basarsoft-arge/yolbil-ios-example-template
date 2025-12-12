import SwiftUI
import YolbilMobileSDK

/// Tile katmanı ekleme helper sınıfı
/// Haritaya farklı tile kaynaklarından katman eklemek için kullanılır
class TileLayerHelper {
    /// Haritaya tile katmanı ekler
    /// - Parameters:
    ///   - mapView: Harita görünümü
    ///   - source: Tile kaynağı tipi
    static func addTileLayer(to mapView: YBMapView, source: TileSource) {
        switch source {
        case .yolbilVector:
            addVectorTileLayer(to: mapView)
        case .yolbilRaster:
            addRasterTileLayer(to: mapView)
        case .googleRoadmap:
            addGoogleRoadmapLayer(to: mapView)
        case .googleSatellite:
            addGoogleSatelliteLayer(to: mapView)
        }
    }
    
    private static func addVectorTileLayer(to mapView: YBMapView) {
        let theme: String
        if #available(iOS 13.0, *) {
            theme = UITraitCollection.current.userInterfaceStyle == .dark ? "dark" : "light"
        } else {
            theme = "light"
        }
        
        let styleFileName = "transport_style_final_package_latest_\(theme).zip"
        guard let styleAsset = YBAssetUtils.loadAsset(styleFileName) else {
            print("Stil dosyası bulunamadı, raster tile kullanılacak")
            addRasterTileLayer(to: mapView)
            return
        }
        
        let vectorTileBaseURL = "https://bms.basarsoft.com.tr/Service/api/v1/VectorMap/Pbf"
        let vectorTileURL = "\(vectorTileBaseURL)?appcode=\(Secrets.appCode)&accid=\(Secrets.accountId)&x={x}&y={y}&z={zoom}"
        
        guard let httpTileDataSource = YBHTTPTileDataSource(
            minZoom: 0,
            maxZoom: 15,
            baseURL: vectorTileURL
        ) else {
            addRasterTileLayer(to: mapView)
            return
        }
        
        guard let assetPackage = YBZippedAssetPackage(zip: styleAsset),
              let compiledStyleSet = YBCompiledStyleSet(
                assetPackage: assetPackage,
                styleName: "transport_style"
              ),
              let tileDecoder = YBMBVectorTileDecoder(compiledStyleSet: compiledStyleSet),
              let vectorTileLayer = YBVectorTileLayer(
                dataSource: httpTileDataSource,
                decoder: tileDecoder
              ) else {
            addRasterTileLayer(to: mapView)
            return
        }
        
        tileDecoder.setStyleParameter("selectedTheme", value: theme)
        mapView.getLayers()?.add(vectorTileLayer)
        print("Vector tile katmanı eklendi")
    }
    
    private static func addRasterTileLayer(to mapView: YBMapView) {
        let rasterTileURL = "https://bms.basarsoft.com.tr/service/api/v1/map/Default?appcode=\(Secrets.appCode)&accid=\(Secrets.accountId)&x={x}&y={y}&z={zoom}"
        
        guard let tileDataSource = YBHTTPTileDataSource(
            minZoom: 1,
            maxZoom: 18,
            baseURL: rasterTileURL
        ) else { return }
        
        guard let tileLayer = YBRasterTileLayer(dataSource: tileDataSource) else { return }
        mapView.getLayers()?.add(tileLayer)
        print("Yolbil Raster tile katmanı eklendi")
    }
    
    private static func addGoogleRoadmapLayer(to mapView: YBMapView) {
        let googleRoadmapURL = "https://mt0.google.com/vt/lyrs=m&x={x}&y={y}&z={zoom}"
        
        guard let tileDataSource = YBHTTPTileDataSource(
            minZoom: 1,
            maxZoom: 20,
            baseURL: googleRoadmapURL
        ) else { return }
        
        guard let tileLayer = YBRasterTileLayer(dataSource: tileDataSource) else { return }
        mapView.getLayers()?.add(tileLayer)
        print("Google Roadmap katmanı eklendi")
    }
    
    private static func addGoogleSatelliteLayer(to mapView: YBMapView) {
        let googleSatelliteURL = "https://mt0.google.com/vt/lyrs=s&x={x}&y={y}&z={zoom}"
        
        guard let tileDataSource = YBHTTPTileDataSource(
            minZoom: 1,
            maxZoom: 20,
            baseURL: googleSatelliteURL
        ) else { return }
        
        guard let tileLayer = YBRasterTileLayer(dataSource: tileDataSource) else { return }
        mapView.getLayers()?.add(tileLayer)
        print("Google Satellite katmanı eklendi")
    }
    
}

/// Harita altlık kaynağı seçenekleri
enum TileSource: String, CaseIterable {
    case yolbilVector = "Yolbil Vector"
    case yolbilRaster = "Yolbil Raster"
    case googleRoadmap = "Google Roadmap"
    case googleSatellite = "Google Satellite"
    
    var displayName: String {
        return self.rawValue
    }
}

/// YBMapView için SwiftUI wrapper
/// UIKit tabanlı YBMapView'i SwiftUI'da kullanmak için UIViewRepresentable protokolünü kullanır
struct YolbilMapView: UIViewRepresentable {
    /// Harita görünümü referansı (dışarıdan erişim için)
    @Binding var mapView: YBMapView?
    
    /// Seçili tile kaynağı
    var tileSource: TileSource = .yolbilVector
    
    /// Mock GPS gönderme callback'i (haritaya uzun basınca çağrılır)
    var onLongPress: ((YBMapPos) -> Void)?
    
    /// UIKit görünümü oluşturur (SwiftUI tarafından çağrılır)
    func makeUIView(context: Context) -> YBMapView {
        // Harita görünümünü oluştur (SwiftUI boyutlandıracak)
        guard let newMapView = YBMapView(frame: CGRect(x: 0, y: 0, width: 100, height: 100)) as YBMapView? else {
            fatalError("YBMapView oluşturulamadı")
        }
        
        
        // Harita ayarlarını al
        guard let options = newMapView.getOptions() else {
            fatalError("Harita ayarları alınamadı")
        }

        // Temel projeksiyonu EPSG:4326 (WGS84) olarak ayarla
        // Bu projeksiyon standart GPS koordinatları için kullanılır
        options.setBaseProjection(YBEPSG4326())
        
        // Render KAPATMA
        // Çizimi geçici olarak devre dışı bırak
        newMapView.setRenderDisabled(false)
        
        // Seçili tile kaynağına göre katman ekle
        addTileLayer(to: newMapView, source: tileSource)
        
        // Başlangıç harita konumunu ayarla (İstanbul merkez örneği)
        // Not: EPSG:4326'da x = boylam (longitude), y = enlem (latitude)
        let mapPos = YBMapPos(x: 28.9784, y: 41.0082) // İstanbul koordinatları (boylam, enlem)
        newMapView.setFocus(mapPos, durationSeconds: 0)
        newMapView.setZoom(10, durationSeconds: 0)
        
        // Referansı sakla (dışarıdan erişim için)
        DispatchQueue.main.async {
            self.mapView = newMapView
        }
        
        // Uzun basınca mock GPS gönderme gesture'ı ekle
        let longPressGesture = UILongPressGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleLongPress(_:)))
        longPressGesture.minimumPressDuration = 1.0 // 1 saniye basılı tutma
        newMapView.addGestureRecognizer(longPressGesture)
        
        // Coordinator'ı sakla
        context.coordinator.mapView = newMapView
        context.coordinator.onLongPress = onLongPress
        
        return newMapView
    }
    
    /// Coordinator sınıfı (gesture recognizer için)
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    /// Coordinator sınıfı
    class Coordinator {
        var mapView: YBMapView?
        var onLongPress: ((YBMapPos) -> Void)?
        
        @objc func handleLongPress(_ gesture: UILongPressGestureRecognizer) {
            guard gesture.state == .began,
                  let mapView = mapView else { return }
            
            let point = gesture.location(in: mapView)
            let scale = UIScreen.main.scale
            let scaledPoint = CGPoint(x: point.x * scale, y: point.y * scale)
            let screenPos = YBScreenPos(x: Float(scaledPoint.x), y: Float(scaledPoint.y))
            
            guard let mapPos = mapView.screen(toMap: screenPos) else { return }
            
            // Callback'i çağır
            onLongPress?(mapPos)
        }
    }
    
    /// Seçili tile kaynağına göre katman ekler
    /// - Parameters:
    ///   - mapView: Harita görünümü
    ///   - source: Tile kaynağı tipi
    private func addTileLayer(to mapView: YBMapView, source: TileSource) {
        switch source {
        case .yolbilVector:
            addVectorTileLayer(to: mapView)
        case .yolbilRaster:
            addRasterTileLayer(to: mapView)
        case .googleRoadmap:
            addGoogleRoadmapLayer(to: mapView)
        case .googleSatellite:
            addGoogleSatelliteLayer(to: mapView)
        }
    }
    
    /// Haritaya vector tile katmanı ekler
    /// Vector tile'lar daha detaylı ve özelleştirilebilir harita görünümü sağlar
    private func addVectorTileLayer(to mapView: YBMapView) {
        print("Vector tile layer ekleniyor...")
        
        // Sistem temasını belirle (açık/koyu)
        // iOS 13+ için sistem temasını kontrol et, yoksa açık tema kullan
        let theme: String
        if #available(iOS 13.0, *) {
            theme = UITraitCollection.current.userInterfaceStyle == .dark ? "dark" : "light"
        } else {
            theme = "light"
        }
        
        // Assets klasöründen stil dosyasını yükle
        // Stil dosyaları: transport_style_final_package_latest_light.zip veya dark.zip
        let styleFileName = "transport_style_final_package_latest_\(theme).zip"
        
        guard let styleAsset = YBAssetUtils.loadAsset(styleFileName) else {
            print("Stil dosyası bulunamadı: \(styleFileName)")
            print("Raster tile layer kullanılacak...")
            addRasterTileLayer(to: mapView)
            return
        }
        
        // Vector tile URL'ini kimlik bilgileriyle oluştur
        // {x}, {y}, {zoom} parametreleri SDK tarafından otomatik doldurulur
        let vectorTileBaseURL = "https://bms.basarsoft.com.tr/Service/api/v1/VectorMap/Pbf"
        let vectorTileURL = "\(vectorTileBaseURL)?appcode=\(Secrets.appCode)&accid=\(Secrets.accountId)&x={x}&y={y}&z={zoom}"
        
        // HTTP tile veri kaynağı oluştur
        // minZoom: 0, maxZoom: 15 - haritanın zoom seviyeleri
        guard let httpTileDataSource = YBHTTPTileDataSource(
            minZoom: 0,
            maxZoom: 15,
            baseURL: vectorTileURL
        ) else {
            print("Tile veri kaynağı oluşturulamadı")
            addRasterTileLayer(to: mapView)
            return
        }
        
        // ZIP dosyasından asset paketi oluştur
        guard let assetPackage = YBZippedAssetPackage(zip: styleAsset) else {
            print("Asset paketi oluşturulamadı")
            addRasterTileLayer(to: mapView)
            return
        }
        
        // Derlenmiş stil seti oluştur
        // "transport_style" stil dosyası içindeki stil adıdır
        guard let compiledStyleSet = YBCompiledStyleSet(
            assetPackage: assetPackage,
            styleName: "transport_style"
        ) else {
            print("Derlenmiş stil seti oluşturulamadı")
            addRasterTileLayer(to: mapView)
            return
        }
        
        // Tile decoder oluştur (stil seti ile)
        guard let tileDecoder = YBMBVectorTileDecoder(compiledStyleSet: compiledStyleSet) else {
            print("Vector tile decoder oluşturulamadı")
            addRasterTileLayer(to: mapView)
            return
        }
        
        // Tema parametresini ayarla (light/dark)
        tileDecoder.setStyleParameter("selectedTheme", value: theme)
        
        // Vector tile katmanı oluştur
        guard let vectorTileLayer = YBVectorTileLayer(
            dataSource: httpTileDataSource,
            decoder: tileDecoder
        ) else {
            print("Vector tile katmanı oluşturulamadı")
            addRasterTileLayer(to: mapView)
            return
        }
        
        // Katmanı haritaya ekle
        guard let layers = mapView.getLayers() else {
            print("Harita katmanları alınamadı")
            addRasterTileLayer(to: mapView)
            return
        }
        
        layers.add(vectorTileLayer)
        print("Vector tile katmanı başarıyla eklendi (Tema: \(theme))")
    }
    
    /// Yedek: Vector tile başarısız olursa raster tile katmanı ekler
    /// Raster tile'lar görüntü tabanlıdır ve daha basit bir alternatiftir
    private func addRasterTileLayer(to mapView: YBMapView) {
        let rasterTileURL = "https://bms.basarsoft.com.tr/service/api/v1/map/Default?appcode=\(Secrets.appCode)&accid=\(Secrets.accountId)&x={x}&y={y}&z={zoom}"
        
        // Raster tile veri kaynağı oluştur
        guard let tileDataSource = YBHTTPTileDataSource(
            minZoom: 1,
            maxZoom: 18,
            baseURL: rasterTileURL
        ) else {
            print("Raster tile veri kaynağı oluşturulamadı")
            return
        }
                
        // Raster tile katmanı oluştur
        guard let tileLayer = YBRasterTileLayer(dataSource: tileDataSource) else {
            print("Raster tile katmanı oluşturulamadı")
            return
        }
        
        // Katmanı haritaya ekle
        mapView.getLayers()?.add(tileLayer)
        print("Raster tile katmanı eklendi (yedek)")
    }
    
    /// Google Maps Roadmap katmanı ekler
    private func addGoogleRoadmapLayer(to mapView: YBMapView) {
        // Google Maps Roadmap tile URL
        // Not: Google Maps API key gerektirir, bu örnekte API key olmadan çalışmayabilir
        let googleRoadmapURL = "https://mt0.google.com/vt/lyrs=m&x={x}&y={y}&z={zoom}"
        
        guard let tileDataSource = YBHTTPTileDataSource(
            minZoom: 1,
            maxZoom: 20,
            baseURL: googleRoadmapURL
        ) else {
            print("Google Roadmap tile veri kaynağı oluşturulamadı")
            addRasterTileLayer(to: mapView) // Fallback
            return
        }
        
        guard let tileLayer = YBRasterTileLayer(dataSource: tileDataSource) else {
            print("Google Roadmap tile katmanı oluşturulamadı")
            addRasterTileLayer(to: mapView) // Fallback
            return
        }
        
        mapView.getLayers()?.add(tileLayer)
        print("Google Roadmap katmanı eklendi")
    }
    
    /// Google Maps Satellite katmanı ekler
    private func addGoogleSatelliteLayer(to mapView: YBMapView) {
        // Google Maps Satellite tile URL
        // Not: Google Maps API key gerektirir, bu örnekte API key olmadan çalışmayabilir
        let googleSatelliteURL = "https://mt0.google.com/vt/lyrs=s&x={x}&y={y}&z={zoom}"
        
        guard let tileDataSource = YBHTTPTileDataSource(
            minZoom: 1,
            maxZoom: 20,
            baseURL: googleSatelliteURL
        ) else {
            print("Google Satellite tile veri kaynağı oluşturulamadı")
            addRasterTileLayer(to: mapView) // Fallback
            return
        }
        
        guard let tileLayer = YBRasterTileLayer(dataSource: tileDataSource) else {
            print("Google Satellite tile katmanı oluşturulamadı")
            addRasterTileLayer(to: mapView) // Fallback
            return
        }
        
        mapView.getLayers()?.add(tileLayer)
        print("Google Satellite katmanı eklendi")
    }
    
    /// SwiftUI görünümü güncellendiğinde çağrılır
    func updateUIView(_ uiView: YBMapView, context: Context) {
        // Callback'i güncelle
        context.coordinator.onLongPress = onLongPress
    }
}

/// Ana harita ekranı
/// Harita görünümü ve rota çizme butonunu içerir
struct MapViewScreen: View {
    /// Harita görünümü referansı
    @State private var mapView: YBMapView?
    
    /// Rota hesaplama servisi
    @StateObject private var routingService = RoutingService()
    
    /// Turn-by-turn navigasyon servisi
    @StateObject private var navigationService = NavigationService()
    
    /// GPS konum kaynağı
    @State private var locationSource: GPSLocationSource?
    
    /// Haritadaki rota katmanı referansı (silme için)
    @State private var routeLayer: YBVectorLayer?
    
    /// Seçili tile kaynağı
    @State private var selectedTileSource: TileSource = .yolbilVector
    
    // Örnek rota noktaları
    // Bu değerleri değiştirerek farklı rotalar çizebilirsiniz
    private let startLocation = LocationData(latitude: 40.989532, longitude: 29.096925)
    private let endLocation = LocationData(latitude: 40.906199, longitude: 29.156320)
    
    var body: some View {
        ZStack {
            // Harita görünümü (arka plan)
            YolbilMapView(
                mapView: $mapView,
                tileSource: selectedTileSource,
                onLongPress: { mapPos in
                    sendMockLocationAt(mapPos: mapPos)
                }
            )
            .edgesIgnoringSafeArea(.all)
            
            VStack {
                // Navigasyon bilgi kartı (aktif navigasyon varsa)
                if navigationService.isNavigating, let navInfo = navigationService.navigationInfo {
                    NavigationInfoCard(navigationInfo: navInfo)
                        .padding(.top, 10)
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                // Rota bilgisi kartı (üstte, küçük) - navigasyon yoksa göster
                else if let routeInfo = routingService.routeInfo {
                    RouteInfoCard(routeInfo: routeInfo)
                        .padding(.top, 10)
                        .padding(.horizontal, 16)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                
                Spacer()
                
                // Alt butonlar (sol ve sağ alt köşe)
                HStack {
                    // Tile kaynağı seçici (sol alt köşe)
                    Picker("Harita Altlığı", selection: $selectedTileSource) {
                        ForEach(TileSource.allCases, id: \.self) { source in
                            Text(source.displayName).tag(source)
                        }
                    }
                    .pickerStyle(.menu)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemBackground))
                    .cornerRadius(8)
                    .shadow(radius: 4)
                    .padding(.leading, 20)
                    .padding(.bottom, 20)
                    .onChange(of: selectedTileSource) { newSource in
                        changeTileSource(to: newSource)
                    }
                    
                    Spacer()
                    
                    // Navigasyon butonları (sağ alt köşe)
                    VStack(spacing: 8) {
                        // Navigasyon aktifse durdur butonu göster
                        if navigationService.isNavigating {
                            Button(action: {
                                stopNavigation()
                            }) {
                                HStack {
                                    Image(systemName: "stop.fill")
                                    Text("Navigasyonu Durdur")
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .frame(minWidth: 160) // Diğer butonlarla aynı genişlik
                                .background(Color.red)
                                .cornerRadius(10)
                                .shadow(radius: 5)
                            }
                        } else {
                            // Rota varsa navigasyon başlat butonu
                            if routingService.routeInfo != nil {
                                Button(action: {
                                    startNavigation()
                                }) {
                                    HStack {
                                        Image(systemName: "location.fill")
                                        Text("Navigasyonu Başlat")
                                            .fontWeight(.semibold)
                                    }
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 20)
                                    .padding(.vertical, 12)
                                    .frame(minWidth: 160) // Rota çiz butonu ile aynı genişlik
                                    .background(Color.green)
                                    .cornerRadius(10)
                                    .shadow(radius: 5)
                                }
                            }
                            
                            // Rota çizme butonu
                            Button(action: {
                                calculateAndDrawRoute()
                            }) {
                                HStack {
                                    if routingService.isCalculating {
                                        ProgressView()
                                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                            .scaleEffect(0.8)
                                    } else {
                                        Image(systemName: "map.fill")
                                    }
                                    Text(routingService.isCalculating ? "Hesaplanıyor..." : "Rota Çiz")
                                        .fontWeight(.semibold)
                                }
                                .foregroundColor(.white)
                                .padding(.horizontal, 20)
                                .padding(.vertical, 12)
                                .frame(minWidth: 160) // Navigasyon başlat butonu ile aynı genişlik
                                .background(routingService.isCalculating ? Color.gray : Color.blue)
                                .cornerRadius(10)
                                .shadow(radius: 5)
                            }
                            .disabled(routingService.isCalculating)
                        }
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 20)
                }
            }
        }
        .navigationTitle("Harita")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            setupLocationSource()
        }
        // Hata durumunda alert göster
        .alert("Rota Hatası", isPresented: .constant(routingService.errorMessage != nil)) {
            Button("Tamam", role: .cancel) {
                routingService.errorMessage = nil
            }
        } message: {
            if let error = routingService.errorMessage {
                Text(error)
            }
        }
    }
    
    // MARK: - Setup Methods
    
    /// GPS konum kaynağını oluşturur ve BlueDot'u ekler
    private func setupLocationSource() {
        guard locationSource == nil else { return }
        
        if let source = GPSLocationSource() {
            self.locationSource = source
            source.startLocationUpdates()
            
            // BlueDot katmanını ekle (harita hazır olduğunda)
            // İlk konum olarak varsayılan konumu kullan
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                if let mapView = self.mapView {
                    let initialLocation = LocationData(
                        latitude: 40.989532,
                        longitude: 29.096925
                    )
                    self.navigationService.addBlueDotLayer(
                        to: mapView,
                        locationSource: source,
                        initialLocation: initialLocation
                    )
                    
                    // Haritayı ilk konuma odakla
                    let mapPos = YBMapPos(x: 29.096925, y: 40.989532)
                    mapView.setFocus(mapPos, durationSeconds: 0)
                    mapView.setZoom(15, durationSeconds: 0)
                }
            }
        }
    }
    
    // MARK: - Navigation Methods
    
    /// Turn-by-turn navigasyonu başlatır
    private func startNavigation() {
        guard let mapView = mapView,
              let source = locationSource else {
            print("Navigasyon başlatılamadı: MapView veya LocationSource yok")
            return
        }
        
        // Mevcut rota katmanını kaldır
        if let existingLayer = routeLayer,
           let layers = mapView.getLayers() {
            layers.remove(existingLayer)
            routeLayer = nil
        }
        
        // Navigasyonu başlat
        navigationService.startNavigation(
            mapView: mapView,
            from: startLocation,
            to: endLocation,
            routeType: .car,
            locationSource: source
        )
    }
    
    /// Navigasyonu durdurur
    private func stopNavigation() {
        navigationService.stopNavigation()
    }
    
    // MARK: - Mock GPS Methods
    
    /// Mock GPS konumu gönderir (test amaçlı)
    /// Haritaya tıklanan noktaya mock location gönderir
    /// - Parameter location: Gönderilecek konum
    func sendMockLocation(_ location: LocationData) {
        guard let source = locationSource else {
            print("Mock location gönderilemedi: LocationSource yok")
            return
        }
        
        navigationService.sendMockLocation(
            locationSource: source,
            latitude: location.latitude,
            longitude: location.longitude
        )
        
        print("Mock location gönderildi: \(location.latitude), \(location.longitude)")
    }
    
    /// Haritaya tıklanan noktaya mock GPS gönderir
    /// - Parameter mapPos: Harita koordinatları
    func sendMockLocationAt(mapPos: YBMapPos) {
        guard let source = locationSource,
              let projection = mapView?.getOptions()?.getBaseProjection() else {
            print("Mock location gönderilemedi: LocationSource veya projection yok")
            return
        }
        
        // WGS84'e çevir (opsiyonel - log için)
        if let wgs84 = projection.toWgs84(mapPos) {
            print("Mock location gönderiliyor: Lat=\(wgs84.getY()), Lon=\(wgs84.getX())")
        }
        
        navigationService.sendMockLocation(locationSource: source, mapPos: mapPos)
    }
    
    /// Rota hesaplar ve haritaya çizer
    /// Başlangıç ve bitiş noktaları arasında araç rotası hesaplar
    private func calculateAndDrawRoute() {
        guard let mapView = mapView else {
            print("Harita görünümü mevcut değil")
            return
        }
        
        // Mevcut rota katmanını kaldır (varsa)
        if let existingLayer = routeLayer,
           let layers = mapView.getLayers() {
            layers.remove(existingLayer)
            routeLayer = nil
        }
        
        // Rota hesapla (araç rotası)
        routingService.calculateRoute(from: startLocation, to: endLocation, routeType: .car) { result in
            switch result {
            case .success(let routeInfo):
                print("Rota hesaplandı: \(routeInfo.distanceText), \(routeInfo.durationText)")
                
                // Rota katmanı oluştur ve haritaya ekle
                if let routeLayer = routingService.createRouteLayer(route: routeInfo),
                   let layers = mapView.getLayers() {
                    layers.add(routeLayer)
                    self.routeLayer = routeLayer
                    
                    // Haritayı rotaya göre odakla (zoom/pan)
                    fitMapToRoute(route: routeInfo, mapView: mapView)
                }
                
            case .failure(let error):
                print("Rota hesaplama hatası: \(error.localizedDescription)")
            }
        }
    }
    
    /// Haritayı rotaya göre odaklar ve ortalar
    /// Rotanın tüm noktalarını görünür alanda gösterir
    private func fitMapToRoute(route: RouteInfo, mapView: YBMapView) {
        // En az 2 nokta olmalı (başlangıç ve bitiş)
        guard route.routeGeometry.count >= 2,
              let projection = YBEPSG4326() else {
            return
        }
        
        // Rotanın sınırlarını bul (min/max koordinatlar)
        var minX = Double.greatestFiniteMagnitude
        var maxX = -Double.greatestFiniteMagnitude
        var minY = Double.greatestFiniteMagnitude
        var maxY = -Double.greatestFiniteMagnitude
        
        // Tüm rota noktalarını dolaşarak sınırları hesapla
        for location in route.routeGeometry {
            if let mapPos = location.mapPosition(with: projection) {
                minX = min(minX, Double(mapPos.getX()))
                maxX = max(maxX, Double(mapPos.getX()))
                minY = min(minY, Double(mapPos.getY()))
                maxY = max(maxY, Double(mapPos.getY()))
            }
        }
        
        // Geçerli sınırlar kontrolü
        guard minX.isFinite, minY.isFinite, maxX.isFinite, maxY.isFinite else { return }
        
        // Harita sınırlarını oluştur (min ve max noktalar)
        let minPos = YBMapPos(x: minX, y: minY)
        let maxPos = YBMapPos(x: maxX, y: maxY)
        
        guard let mapBounds = YBMapBounds(min: minPos, max: maxPos) else {
            return
        }
        
        // Ekran sınırlarını hesapla (scale ve padding ile)
        // Retina ekranlar için doğru piksel değerleri
        let scale = UIScreen.main.scale
        let screenSize = UIScreen.main.bounds.size
        let widthPx = Double(screenSize.width * scale)
        let heightPx = Double(screenSize.height * scale)
        
        // Rotayı ortalamak için padding ekle
        // Yanlar: 24px, Üst: 96px (navigation bar için), Alt: 32px
        let sidePaddingPx = Double(24.0 * scale)
        let topPaddingPx = Double(96.0 * scale)
        let bottomPaddingPx = Double(32.0 * scale)
        
        // Ekran sınırlarını oluştur (padding ile)
        let minScreen = YBScreenPos(
            x: Float(max(0, sidePaddingPx)),
            y: Float(max(0, topPaddingPx))
        )
        let maxScreen = YBScreenPos(
            x: Float(max(0, widthPx - sidePaddingPx)),
            y: Float(max(0, heightPx - bottomPaddingPx))
        )
        
        let screenBounds = YBScreenBounds(min: minScreen, max: maxScreen)
        
        // Haritayı rotaya göre odakla ve ortala
        // integerZoom: true - tam sayı zoom seviyeleri kullan
        // durationSeconds: 0.5 - animasyon süresi
        mapView.move(toFit: mapBounds, screenBounds: screenBounds, integerZoom: true, durationSeconds: 0.5)
    }
    
    /// Tile kaynağını değiştirir
    /// - Parameter source: Yeni tile kaynağı
    private func changeTileSource(to source: TileSource) {
        guard let mapView = mapView,
              let layers = mapView.getLayers() else {
            return
        }
        
        // Mevcut tile katmanlarını kaldır
        // Not: Rota katmanını korumak için önce rotayı sakla
        let savedRouteLayer = routeLayer
        
        // Tüm katmanları kaldır (clear metodu parametresizdir)
        layers.clear()
        

        
        // Yeni tile katmanını ekle
        TileLayerHelper.addTileLayer(to: mapView, source: source)

        // Rota katmanını tekrar ekle (varsa)
        if let routeLayer = savedRouteLayer {
            layers.add(routeLayer)
            self.routeLayer = routeLayer
        }
    }
}

/// Küçük rota bilgisi kartı
/// Mesafe, süre ve araç tipini kompakt şekilde gösterir
struct RouteInfoCard: View {
    let routeInfo: RouteInfo
    
    var body: some View {
        HStack(spacing: 12) {
            // Araç tipi ikonu
            Image(systemName: routeIcon(for: routeInfo.routeType))
                .foregroundColor(.blue)
                .font(.system(size: 14))
                .frame(width: 20)
            
            // Mesafe
            HStack(spacing: 4) {
                Image(systemName: "ruler.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                Text(routeInfo.distanceText)
                    .font(.system(size: 13, weight: .semibold))
            }
            
            Divider()
                .frame(height: 16)
            
            // Süre
            HStack(spacing: 4) {
                Image(systemName: "clock.fill")
                    .foregroundColor(.secondary)
                    .font(.system(size: 12))
                Text(routeInfo.durationText)
                    .font(.system(size: 13, weight: .semibold))
            }
            
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(.systemBackground))
        .cornerRadius(8)
        .shadow(color: Color.black.opacity(0.1), radius: 4, x: 0, y: 2)
    }
    
    /// Rota tipine göre ikon döndürür
    private func routeIcon(for routeType: RouteRequest.RouteType) -> String {
        switch routeType {
        case .car:
            return "car.fill"
        case .truck:
            if #available(iOS 17.0, *) {
                return "truck.box.fill"
            } else {
                return "bus.fill"
            }
        case .pedestrian:
            return "figure.walk"
        }
    }
}

/// Navigasyon bilgi kartı
/// Turn-by-turn navigasyon sırasında kalan süre, mesafe ve komut gösterir
struct NavigationInfoCard: View {
    let navigationInfo: NavigationInfo
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Mevcut komut (varsa)
            if let command = navigationInfo.currentCommand {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.turn.up.right")
                        .foregroundColor(.white)
                        .font(.system(size: 18, weight: .bold))
                    
                    Text(command)
                        .foregroundColor(.white)
                        .font(.system(size: 16, weight: .semibold))
                    
                    Spacer()
                    
                    // Sonraki komuta mesafe
                    if navigationInfo.distanceToNextCommand > 0 {
                        Text("\(Int(navigationInfo.distanceToNextCommand)) m")
                            .foregroundColor(.white.opacity(0.9))
                            .font(.system(size: 14, weight: .medium))
                    }
                }
            }
            
            Divider()
                .background(Color.white.opacity(0.3))
            
            // Kalan süre ve mesafe
            HStack(spacing: 16) {
                // Kalan süre
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .foregroundColor(.white.opacity(0.8))
                        .font(.system(size: 14))
                    Text(navigationInfo.remainingTime)
                        .foregroundColor(.white)
                        .font(.system(size: 15, weight: .semibold))
                }
                
                // Kalan mesafe
                HStack(spacing: 6) {
                    Image(systemName: "ruler.fill")
                        .foregroundColor(.white.opacity(0.8))
                        .font(.system(size: 14))
                    Text(navigationInfo.remainingDistance)
                        .foregroundColor(.white)
                        .font(.system(size: 15, weight: .semibold))
                }
                
                Spacer()
                
                // ETA (Tahmini Varış Saati)
                if !navigationInfo.eta.isEmpty {
                    HStack(spacing: 6) {
                        Image(systemName: "clock.badge.checkmark.fill")
                            .foregroundColor(.white.opacity(0.8))
                            .font(.system(size: 14))
                        Text("Varış: \(navigationInfo.eta)")
                            .foregroundColor(.white)
                            .font(.system(size: 15, weight: .semibold))
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color(red: 0.12, green: 0.23, blue: 0.34)) // Koyu mavi arka plan
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.2), radius: 6, x: 0, y: 3)
    }
}

#Preview {
    MapViewScreen()
}

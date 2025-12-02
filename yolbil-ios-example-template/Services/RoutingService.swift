import Foundation
import Combine
import YolbilMobileSDK

/// Rota hesaplama servisi
/// İki nokta arasında rota hesaplar ve haritada görüntülemek için katman oluşturur
class RoutingService: ObservableObject {
    /// Rota hesaplama durumu (yükleniyor mu?)
    @Published var isCalculating = false
    
    /// Hesaplanan rota bilgisi
    @Published var routeInfo: RouteInfo?
    
    /// Hata mesajı (varsa)
    @Published var errorMessage: String?
    
    
    /// İki nokta arasında rota hesaplar
    /// - Parameters:
    ///   - start: Başlangıç konumu
    ///   - end: Bitiş konumu
    ///   - routeType: Rota tipi (.car, .truck, .pedestrian) - varsayılan: .car
    ///   - completion: Tamamlandığında çağrılacak closure (başarı/hata durumu ile)
    func calculateRoute(from start: LocationData, to end: LocationData, routeType: RouteRequest.RouteType = .car, completion: @escaping (Result<RouteInfo, Error>) -> Void) {
        // Hesaplama başladı
        isCalculating = true
        errorMessage = nil
        
        // Arka plan thread'inde çalıştır (UI'ı bloklamamak için)
        DispatchQueue.global(qos: .userInitiated).async {
            do {
                // EPSG:4326 projeksiyonunu oluştur
                guard let projection = YBEPSG4326() else {
                    throw NSError(domain: "RoutingService", code: -1, userInfo: [NSLocalizedDescriptionKey: "Projeksiyon oluşturulamadı"])
                }
                
                // Başlangıç ve bitiş noktalarını harita koordinatlarına çevir
                guard let startPos = start.mapPosition(with: projection),
                      let endPos = end.mapPosition(with: projection) else {
                    throw NSError(domain: "RoutingService", code: -2, userInfo: [NSLocalizedDescriptionKey: "Geçersiz rota noktaları"])
                }
                
                print("[RoutingRequest] Başlangıç: \(start.latitude),\(start.longitude) -> Bitiş: \(end.latitude),\(end.longitude) Tip: \(routeType.rawValue)")
                
                /*
                //APP CODE ACC ID ile yapılan routing
                // Navigasyon bundle'ı oluştur
                // Bu bundle rota hesaplama için gerekli servisleri içerir
                let gpsSource = GPSLocationSource()
                let builder = YBYolbilNavigationBundleBuilder(
                    baseUrl: "https://bms.basarsoft.com.tr",
                    accountId: Secrets.accountId,
                    applicationCode: Secrets.appCode,
                    locationSource: gpsSource
                )
                builder?.setRequestEndpoint("/service/api/v1/Routing/BasarRouting")
                 
                */
                
                //API KEY ile yapılan routing
                // Navigasyon bundle'ı oluştur
                // Bu bundle rota hesaplama için gerekli servisleri içerir
                let gpsSource = GPSLocationSource()
                let builder = YBYolbilNavigationBundleBuilder(
                    baseUrl: "https://services.basarsoft.com.tr",
                    apiKey: Secrets.apiKey,
                    locationSource: gpsSource
                )
                
                // Rota tipini yapılandır (araç, kamyon, yaya)
                switch routeType {
                case .car:
                    builder?.setIsCar(true)
                case .truck:
                    builder?.setIsTruck(true)
                case .pedestrian:
                    builder?.setIsPedestrian(true)
                }
                builder?.setAlternativeRoute(false) // Alternatif rota istemiyoruz
                
                // Bundle'ı oluştur
                guard let bundle = builder?.build() else {
                    throw NSError(domain: "RoutingService", code: -3, userInfo: [NSLocalizedDescriptionKey: "Navigasyon bundle'ı oluşturulamadı"])
                }
                
                // Rotayı hesapla
                guard let results = bundle.startNavigation(startPos, to: endPos),
                      results.size() > 0,
                      let navShared = results.get(0),
                      let navResult = YBNavigationResult.swigCreatePolymorphicInstance(navShared.getCptr(), swigOwnCObject: false) else {
                    throw NSError(domain: "RoutingService", code: -4, userInfo: [NSLocalizedDescriptionKey: "Rota sonucu alınamadı"])
                }

                // NavigationResult'tan GeoJSON, EncodedPolyline ve LineString verilerini al
                let geoJSON = navResult.getPointsGeoJSON()
                let encodedPolyline = navResult.getPointsEncodedPolyline()
                let lineString = navResult.getPointsLineString()
                
                /*
                // Console'a yazdır (debug için)
                if let geoJSON = geoJSON {
                    print("GeoJSON: \(geoJSON)")
                }
                if let encodedPolyline = encodedPolyline {
                    print("EncodedPolyline: \(encodedPolyline)")
                }
                if let lineString = lineString {
                    print("LineString: \(lineString)")
                }
                */
                
                // Navigasyon sonucunu RouteInfo'ya çevir
                let routeInfo = self.convertToRouteInfo(navResult, start: start, end: end, routeType: routeType, geoJSON: geoJSON, encodedPolyline: encodedPolyline, lineString: lineString)
                
                // Navigasyonu durdur
                bundle.stopNavigation()
                
                // Ana thread'de sonucu bildir
                DispatchQueue.main.async {
                    self.isCalculating = false
                    self.routeInfo = routeInfo
                    completion(.success(routeInfo))
                }
                
            } catch {
                // Hata durumunda ana thread'de bildir
                DispatchQueue.main.async {
                    self.isCalculating = false
                    self.errorMessage = error.localizedDescription
                    completion(.failure(error))
                }
            }
        }
    }
    
    /// Navigasyon sonucunu RouteInfo modeline çevirir
    /// - Parameters:
    ///   - navResult: Yolbil navigasyon sonucu
    ///   - start: Başlangıç konumu
    ///   - end: Bitiş konumu
    ///   - routeType: Rota tipi
    ///   - geoJSON: GeoJSON formatında rota geometrisi
    ///   - encodedPolyline: Encoded polyline formatında rota geometrisi
    ///   - lineString: WKT LINESTRING formatında rota geometrisi
    /// - Returns: RouteInfo modeli
    private func convertToRouteInfo(_ navResult: YBNavigationResult, start: LocationData, end: LocationData, routeType: RouteRequest.RouteType, geoJSON: String?, encodedPolyline: String?, lineString: String?) -> RouteInfo {
        var routeGeometry: [LocationData] = []
        
        // Rota noktalarını al ve WGS84 koordinatlarına çevir
        if let points = navResult.getPoints() {
            guard let projection = YBEPSG4326() else {
                // Projeksiyon yoksa sadece başlangıç ve bitiş noktalarını kullan
                return RouteInfo(
                    distance: navResult.getTotalDistance(),
                    duration: navResult.getTotalTime(),
                    routeType: routeType,
                    routeGeometry: [start, end],
                    instructions: [],
                    geoJSON: geoJSON,
                    encodedPolyline: encodedPolyline,
                    lineString: lineString
                )
            }
            
            // Her rota noktasını WGS84 koordinatlarına çevir
            for i in 0..<points.size() {
                if let point = points.get(Int32(i)),
                   let wgs84Point = projection.toWgs84(point) {
                    let location = LocationData(
                        latitude: Double(wgs84Point.getY()),
                        longitude: Double(wgs84Point.getX())
                    )
                    routeGeometry.append(location)
                }
            }
        }
        
        // Yön talimatlarını Ekle
        var instructions: [RouteInstruction] = []
        if let navInstructions = navResult.getInstructions() {
            for i in 0..<navInstructions.size() {
                if let instruction = navInstructions.get(Int32(i)) {
                    let routeInstruction = RouteInstruction(
                        text: instruction.getInstruction() ?? "Devam et",
                        distance: Double(instruction.getDistance()),
                        duration: Double(instruction.getTime()),
                        location: routeGeometry.isEmpty ? start : routeGeometry.first!,
                        icon: "arrow.forward"
                    )
                    instructions.append(routeInstruction)
                }
            }
        }
        
        // RouteInfo modelini oluştur ve döndür
        return RouteInfo(
            distance: navResult.getTotalDistance(),
            duration: navResult.getTotalTime(),
            routeType: routeType,
            routeGeometry: routeGeometry.isEmpty ? [start, end] : routeGeometry,
            instructions: instructions,
            geoJSON: geoJSON,
            encodedPolyline: encodedPolyline,
            lineString: lineString
        )
    }
    
    /// Haritada görüntülemek için rota katmanı oluşturur
    /// - Parameter route: Görüntülenecek rota bilgisi
    /// - Returns: YBVectorLayer (haritaya eklenebilir) veya nil (hata durumunda)
    func createRouteLayer(route: RouteInfo) -> YBVectorLayer? {
        // Projeksiyon oluştur
        guard let projection = YBEPSG4326() else {
            print("Rota katmanı için projeksiyon oluşturulamadı")
            return nil
        }
        
        // Yerel vektör veri kaynağı oluştur
        guard let dataSource = YBLocalVectorDataSource(projection: projection) else {
            print("Rota katmanı için veri kaynağı oluşturulamadı")
            return nil
        }
        
        // Rota çizgi stilini oluştur (mavi, yumuşak yuvarlatılmış çizgi)
        let lineStyleBuilder = YBLineStyleBuilder()
        lineStyleBuilder?.setWidth(5.0) // Çizgi kalınlığı: 5 piksel
        lineStyleBuilder?.setColor(YBColor(r: 0, g: 150, b: 255, a: 255)) // Mavi renk
        
        // Yuvarlatılmış köşeler için line join tipini ayarla
        if let roundJoin = YBLineJoinType(rawValue: 3) { // 3 = ROUND
            lineStyleBuilder?.setLineJoinType(roundJoin)
        }
        // Yuvarlatılmış uçlar için line end tipini ayarla
        if let roundEnd = YBLineEndType(rawValue: 2) { // 2 = ROUND
            lineStyleBuilder?.setLineEndType(roundEnd)
        }
        
        // Stili oluştur
        guard let lineStyle = lineStyleBuilder?.buildStyle() else {
            print("Rota çizgi stili oluşturulamadı")
            return nil
        }
        
        // Rota noktalarını oluştur
        let routePoints = YBMapPosVector()
        for location in route.routeGeometry {
            if let mapPos = location.mapPosition(with: projection) {
                routePoints?.add(mapPos)
            }
        }
        
        // En az 2 nokta varsa çizgiyi oluştur ve ekle
        if let points = routePoints, points.size() >= 2 {
            let routeLine = YBLine(poses: points, style: lineStyle)
            dataSource.add(routeLine)
        }
        
        // Vektör katmanını oluştur ve döndür
        return YBVectorLayer(dataSource: dataSource)
    }
    
    /// Rotayı temizler (rota bilgisi ve hata mesajını sıfırlar)
    func clearRoute() {
        routeInfo = nil
        errorMessage = nil
    }
}


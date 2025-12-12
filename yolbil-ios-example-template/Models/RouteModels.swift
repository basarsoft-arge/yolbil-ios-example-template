import Foundation

// MARK: - Route Request Models
struct RouteRequest {
    let startLocation: LocationData
    let endLocation: LocationData
    let routeType: RouteType
    
    enum RouteType: String, CaseIterable {
        case car = "car"
        case truck = "truck"
        case pedestrian = "pedestrian"
        
        var displayName: String {
            switch self {
            case .car:
                return "Araç"
            case .truck:
                return "Kamyon"
            case .pedestrian:
                return "Yaya"
            }
        }
    }
}

// MARK: - Route Response Models
struct RouteInfo: Equatable {
    let distance: Double // meters
    let duration: Double // seconds
    let routeType: RouteRequest.RouteType
    let routeGeometry: [LocationData] // Route points
    let instructions: [RouteInstruction]
    
    // Rota geometrisi formatları (NavigationResult'tan alınan)
    let geoJSON: String? // GeoJSON LineString formatında rota
    let encodedPolyline: String? // Encoded polyline formatında rota
    let lineString: String? // WKT LINESTRING formatında rota
    
    // Equatable için özel karşılaştırma (yeni alanları dahil et)
    static func == (lhs: RouteInfo, rhs: RouteInfo) -> Bool {
        return lhs.distance == rhs.distance &&
               lhs.duration == rhs.duration &&
               lhs.routeType == rhs.routeType &&
               lhs.routeGeometry == rhs.routeGeometry &&
               lhs.instructions == rhs.instructions &&
               lhs.geoJSON == rhs.geoJSON &&
               lhs.encodedPolyline == rhs.encodedPolyline &&
               lhs.lineString == rhs.lineString
    }
    
    var distanceText: String {
        if distance >= 1000 {
            return String(format: "%.1f km", distance / 1000)
        } else {
            return String(format: "%.0f m", distance)
        }
    }
    
    var durationText: String {
        let hours = Int(duration) / 3600
        let minutes = (Int(duration) % 3600) / 60
        
        if hours > 0 {
            return "\(hours)sa \(minutes)dk"
        } else {
            return "\(minutes)dk"
        }
    }
}

struct RouteInstruction: Equatable {
    let text: String
    let distance: Double
    let duration: Double
    let location: LocationData
    let icon: String
}

// MARK: - Navigation Info (Turn-by-Turn Navigasyon Bilgisi)
/// Gerçek zamanlı navigasyon bilgilerini tutar
/// Kalan süre, mesafe ve mevcut komut bilgilerini içerir
struct NavigationInfo: Equatable {
    /// Kalan süre (formatlanmış: "5 dk", "1 sa 20 dk")
    let remainingTime: String
    
    /// Kalan mesafe (formatlanmış: "500 m", "2.5 km")
    let remainingDistance: String
    
    /// Tahmini varış saati (formatlanmış: "14:30")
    /// Not: Şimdilik boş gelecek, alt yapı hazır
    let eta: String
    
    /// Mevcut navigasyon komutu (ör: "Sağa dön", "Düz devam et")
    let currentCommand: String?
    
    /// Bir sonraki komuta olan mesafe (metre)
    let distanceToNextCommand: Double
    
    /// NavigationResult'tan NavigationInfo oluşturur
    /// - Parameters:
    ///   - totalDistance: Toplam kalan mesafe (metre)
    ///   - totalTime: Toplam kalan süre (saniye)
    ///   - command: Mevcut navigasyon komutu (opsiyonel)
    /// - Returns: Formatlanmış NavigationInfo
    static func from(totalDistance: Double, totalTime: Double, command: String? = nil, distanceToCommand: Double = 0) -> NavigationInfo {
        return NavigationInfo(
            remainingTime: formatDuration(totalTime),
            remainingDistance: formatDistance(totalDistance),
            eta: calculateETA(from: totalTime),
            currentCommand: command,
            distanceToNextCommand: distanceToCommand
        )
    }
    
    /// Kalan mesafe ve süreden NavigationInfo oluşturur
    /// - Parameters:
    ///   - distanceMeters: Kalan mesafe (metre)
    ///   - timeSeconds: Kalan süre (saniye)
    ///   - command: Mevcut navigasyon komutu (opsiyonel)
    ///   - distanceToCommand: Bir sonraki komuta olan mesafe (metre)
    /// - Returns: Formatlanmış NavigationInfo veya nil (geçersiz veri varsa)
    static func fromRemaining(distanceMeters: Double?, timeSeconds: Double?, command: String? = nil, distanceToCommand: Double = 0) -> NavigationInfo? {
        guard let distance = distanceMeters,
              let time = timeSeconds else {
            return nil
        }
        
        return NavigationInfo(
            remainingTime: formatDuration(time),
            remainingDistance: formatDistance(distance),
            eta: calculateETA(from: time),
            currentCommand: command,
            distanceToNextCommand: distanceToCommand
        )
    }
    
    /// ETA (Tahmini Varış Saati) hesaplar
    /// - Parameter timeSeconds: Kalan süre (saniye)
    /// - Returns: Formatlanmış saat (HH:mm)
    private static func calculateETA(from timeSeconds: Double) -> String {
        let totalMinutes = Int(ceil(timeSeconds / 60.0))
        let calendar = Calendar.current
        let now = Date()
        
        if let etaDate = calendar.date(byAdding: .minute, value: totalMinutes, to: now) {
            let formatter = DateFormatter()
            formatter.dateFormat = "HH:mm"
            formatter.locale = Locale(identifier: "tr_TR")
            return formatter.string(from: etaDate)
        }
        
        return ""
    }
    
    /// Saniyeyi okunabilir süreye çevirir
    /// - Parameter seconds: Süre (saniye)
    /// - Returns: Formatlanmış süre ("5 dk", "1 sa", "1 sa 20 dk")
    private static func formatDuration(_ seconds: Double) -> String {
        let totalMinutes = Int(ceil(seconds / 60.0))
        
        if totalMinutes < 60 {
            return "\(totalMinutes) dk"
        } else {
            let hours = totalMinutes / 60
            let minutes = totalMinutes % 60
            
            if minutes == 0 {
                return "\(hours) sa"
            } else {
                return "\(hours) sa \(minutes) dk"
            }
        }
    }
    
    /// Metreyi okunabilir mesafeye çevirir
    /// - Parameter meters: Mesafe (metre)
    /// - Returns: Formatlanmış mesafe ("500 m", "2.5 km", "100 km")
    private static func formatDistance(_ meters: Double) -> String {
        if meters < 1000 {
            return "\(Int(meters)) m"
        } else {
            let km = meters / 1000.0
            
            if km >= 100 {
                return String(format: "%.0f km", km)
            } else {
                return String(format: "%.1f km", km)
            }
        }
    }
}


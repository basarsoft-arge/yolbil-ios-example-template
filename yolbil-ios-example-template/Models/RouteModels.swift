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


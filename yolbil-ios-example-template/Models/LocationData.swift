import Foundation
import YolbilMobileSDK

/// Model for location data
struct LocationData: Equatable {
    let latitude: Double
    let longitude: Double
    let headingDegrees: Double?
    let speedMps: Double?
    let timestamp: Date
    
    /// Converts to map coordinates using the given projection
    func mapPosition(with projection: YBProjection) -> YBMapPos? {
        let wgs84Pos = YBMapPos(x: longitude, y: latitude)
        return projection.fromWgs84(wgs84Pos)
    }
    
    init(latitude: Double, longitude: Double, headingDegrees: Double? = nil, speedMps: Double? = nil, timestamp: Date = Date()) {
        self.latitude = latitude
        self.longitude = longitude
        self.headingDegrees = headingDegrees
        self.speedMps = speedMps
        self.timestamp = timestamp
    }
}


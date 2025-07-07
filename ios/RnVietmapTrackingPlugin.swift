import Foundation
import CoreLocation
import React

@objc(RnVietmapTrackingPlugin)
class RnVietmapTrackingPlugin: RCTEventEmitter {
    
    private var locationManager: CLLocationManager!
    private var isTracking: Bool = false
    private var trackingStartTime: TimeInterval = 0
    private var lastLocationUpdate: TimeInterval = 0
    
    override init() {
        super.init()
        locationManager = CLLocationManager()
        locationManager.delegate = self
        isTracking = false
        trackingStartTime = 0
        lastLocationUpdate = 0
    }
    
    @objc
    override static func requiresMainQueueSetup() -> Bool {
        return true
    }
    
    @objc
    override func supportedEvents() -> [String] {
        return ["onLocationUpdate", "onTrackingStatusChanged"]
    }
    
    @objc
    func multiply(_ a: Double, b: Double) -> NSNumber {
        return NSNumber(value: a * b)
    }
    
    @objc
    func startLocationTracking(_ config: NSDictionary, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        
        // Check location permissions
        let status = CLLocationManager.authorizationStatus()
        if status == .denied || status == .restricted {
            reject("PERMISSION_DENIED", "Location permissions are required", nil)
            return
        }
        
        // Request permissions if not granted
        if status == .notDetermined {
            locationManager.requestWhenInUseAuthorization()
            // Will be handled in delegate method
            reject("PERMISSION_PENDING", "Location permission request pending", nil)
            return
        }
        
        // Extract configuration values
        let accuracy = config["accuracy"] as? String ?? "high"
        let distanceFilter = config["distanceFilter"] as? Double ?? 10.0
        let backgroundMode = config["backgroundMode"] as? Bool ?? false
        
        // Configure location manager
        locationManager.desiredAccuracy = getAccuracyFromString(accuracy)
        locationManager.distanceFilter = distanceFilter
        
        // Start location updates
        locationManager.startUpdatingLocation()
        
        // Request background location if needed
        if backgroundMode && status != .authorizedAlways {
            locationManager.requestAlwaysAuthorization()
        }
        
        if backgroundMode {
            locationManager.startMonitoringSignificantLocationChanges()
        }
        
        isTracking = true
        trackingStartTime = Date().timeIntervalSince1970
        
        sendTrackingStatusUpdate()
        resolve(true)
    }
    
    @objc
    func stopLocationTracking(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        
        isTracking = false
        sendTrackingStatusUpdate()
        
        resolve(true)
    }
    
    @objc
    func getCurrentLocation(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        
        let status = CLLocationManager.authorizationStatus()
        if status == .denied || status == .restricted {
            reject("PERMISSION_DENIED", "Location permissions are required", nil)
            return
        }
        
        if let location = locationManager.location {
            let locationDict = locationToDictionary(location)
            resolve(locationDict)
        } else {
            reject("LOCATION_UNAVAILABLE", "Unable to get current location", nil)
        }
    }
    
    @objc
    func isTrackingActive(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        resolve(isTracking)
    }
    
    @objc
    func getTrackingStatus(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        
        let currentTime = Date().timeIntervalSince1970
        let duration = isTracking ? (currentTime - trackingStartTime) : 0
        
        let status: [String: Any] = [
            "isTracking": isTracking,
            "trackingDuration": duration * 1000, // Convert to milliseconds
            "lastLocationUpdate": lastLocationUpdate > 0 ? lastLocationUpdate * 1000 : NSNull()
        ]
        
        resolve(status)
    }
    
    @objc
    func updateTrackingConfig(_ config: NSDictionary, resolver resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        
        if !isTracking {
            reject("NOT_TRACKING", "Location tracking is not active", nil)
            return
        }
        
        // Extract configuration values
        let accuracy = config["accuracy"] as? String ?? "high"
        let distanceFilter = config["distanceFilter"] as? Double ?? 10.0
        
        // Update configuration
        locationManager.desiredAccuracy = getAccuracyFromString(accuracy)
        locationManager.distanceFilter = distanceFilter
        
        resolve(true)
    }
    
    @objc
    func requestLocationPermissions(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        
        let status = CLLocationManager.authorizationStatus()
        
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            resolve("granted")
        case .denied, .restricted:
            resolve("denied")
        case .notDetermined:
            locationManager.requestWhenInUseAuthorization()
            resolve("pending")
        @unknown default:
            resolve("unknown")
        }
    }
    
    @objc
    func hasLocationPermissions(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {
        
        let status = CLLocationManager.authorizationStatus()
        let hasPermission = (status == .authorizedWhenInUse || status == .authorizedAlways)
        
        resolve(hasPermission)
    }
    
    // MARK: - Helper Methods
    
    private func getAccuracyFromString(_ accuracy: String) -> CLLocationAccuracy {
        switch accuracy {
        case "high":
            return kCLLocationAccuracyBest
        case "medium":
            return kCLLocationAccuracyHundredMeters
        case "low":
            return kCLLocationAccuracyKilometer
        default:
            return kCLLocationAccuracyBest
        }
    }
    
    private func locationToDictionary(_ location: CLLocation) -> [String: Any] {
        return [
            "latitude": location.coordinate.latitude,
            "longitude": location.coordinate.longitude,
            "altitude": location.altitude,
            "accuracy": location.horizontalAccuracy,
            "speed": location.speed,
            "bearing": location.course,
            "timestamp": location.timestamp.timeIntervalSince1970 * 1000
        ]
    }
    
    private func sendTrackingStatusUpdate() {
        let currentTime = Date().timeIntervalSince1970
        let duration = isTracking ? (currentTime - trackingStartTime) : 0
        
        let status: [String: Any] = [
            "isTracking": isTracking,
            "trackingDuration": duration * 1000,
            "lastLocationUpdate": lastLocationUpdate > 0 ? lastLocationUpdate * 1000 : NSNull()
        ]
        
        sendEvent(withName: "onTrackingStatusChanged", body: status)
    }
}

// MARK: - CLLocationManagerDelegate

extension RnVietmapTrackingPlugin: CLLocationManagerDelegate {
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        
        lastLocationUpdate = Date().timeIntervalSince1970
        
        let locationDict = locationToDictionary(location)
        sendEvent(withName: "onLocationUpdate", body: locationDict)
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location manager failed with error: \(error.localizedDescription)")
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("Location authorization status changed to: \(status.rawValue)")
    }
}

// MARK: - React Native Spec Compatibility

extension RnVietmapTrackingPlugin: NativeRnVietmapTrackingPluginSpec {
    
    func multiply(_ a: Double, b: Double) -> NSNumber {
        return NSNumber(value: a * b)
    }
    
    func startLocationTracking(_ config: [String : Any], resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        let nsConfig = NSDictionary(dictionary: config)
        startLocationTracking(nsConfig, resolver: resolve, rejecter: reject)
    }
    
    func stopLocationTracking(_ resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        stopLocationTracking(resolve, rejecter: reject)
    }
    
    func getCurrentLocation(_ resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        getCurrentLocation(resolve, rejecter: reject)
    }
    
    func isTrackingActive(_ resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        isTrackingActive(resolve, rejecter: reject)
    }
    
    func getTrackingStatus(_ resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        getTrackingStatus(resolve, rejecter: reject)
    }
    
    func updateTrackingConfig(_ config: [String : Any], resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        let nsConfig = NSDictionary(dictionary: config)
        updateTrackingConfig(nsConfig, resolver: resolve, rejecter: reject)
    }
    
    func requestLocationPermissions(_ resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        requestLocationPermissions(resolve, rejecter: reject)
    }
    
    func hasLocationPermissions(_ resolve: @escaping RCTPromiseResolveBlock, reject: @escaping RCTPromiseRejectBlock) {
        hasLocationPermissions(resolve, rejecter: reject)
    }
}

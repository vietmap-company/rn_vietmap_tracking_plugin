import Foundation
import CoreLocation
import React

@objc(RnVietmapTrackingPlugin)
class RnVietmapTrackingPlugin: RCTEventEmitter {

    private var locationManager: CLLocationManager!
    private var isTracking: Bool = false
    private var trackingStartTime: TimeInterval = 0
    private var lastLocationUpdate: TimeInterval = 0
    private var locationTimer: Timer?
    private var intervalMs: Int = 5000 // Default 5 seconds
    private var backgroundMode: Bool = false
    private var currentConfig: NSDictionary?

    override init() {
        super.init()
        locationManager = CLLocationManager()
        locationManager.delegate = self
        isTracking = false
        trackingStartTime = 0
        lastLocationUpdate = 0
        intervalMs = 5000
        backgroundMode = false

        // Configure location manager for better battery life
        locationManager.pausesLocationUpdatesAutomatically = false
        // Don't set allowsBackgroundLocationUpdates here - only when we have permission
    }

    @objc
    override static func requiresMainQueueSetup() -> Bool {
        return true
    }

    @objc
    override func supportedEvents() -> [String] {
        return [
            "onLocationUpdate",
            "onTrackingStatusChanged",
            "onLocationError",
            "onPermissionChanged"
        ]
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

        // Store configuration
        currentConfig = config

        // Extract configuration values
        let accuracy = config["accuracy"] as? String ?? "high"
        let distanceFilter = config["distanceFilter"] as? Double ?? 10.0
        backgroundMode = config["backgroundMode"] as? Bool ?? false
        intervalMs = config["intervalMs"] as? Int ?? 5000

        // Configure location manager
        locationManager.desiredAccuracy = getAccuracyFromString(accuracy)
        locationManager.distanceFilter = distanceFilter

        // Request background location if needed
        if backgroundMode {
            if status != .authorizedAlways {
                locationManager.requestAlwaysAuthorization()
                // Don't enable background updates until we have always permission
                reject("PERMISSION_PENDING", "Always location permission required for background mode", nil)
                return
            }

            // Only enable background location updates if we have always permission
            if status == .authorizedAlways {
                do {
                    locationManager.allowsBackgroundLocationUpdates = true
                    locationManager.startMonitoringSignificantLocationChanges()
                } catch {
                    print("Error enabling background location updates: \(error)")
                    // Fall back to foreground-only tracking
                    backgroundMode = false
                }
            }
        }

        // Set tracking state first
        isTracking = true
        trackingStartTime = Date().timeIntervalSince1970

        // Then start timer-based location tracking
        startLocationTimer()

        sendTrackingStatusUpdate()
        resolve(true)
    }

    @objc
    func stopLocationTracking(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {

        // Stop timer
        stopLocationTimer()

        // Stop location updates
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()

        // Disable background location updates safely
        if backgroundMode && CLLocationManager.authorizationStatus() == .authorizedAlways {
            locationManager.allowsBackgroundLocationUpdates = false
        }

        isTracking = false
        backgroundMode = false
        currentConfig = nil
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

    private func startLocationTimer() {
        print("Starting location timer with interval: \(intervalMs)ms")
        stopLocationTimer() // Stop any existing timer

        let timeInterval = TimeInterval(intervalMs) / 1000.0 // Convert ms to seconds
        print("Timer interval: \(timeInterval) seconds")

        // Ensure timer is created on main thread
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            self.locationTimer = Timer.scheduledTimer(withTimeInterval: timeInterval, repeats: true) { [weak self] timer in
                print("⏰ Timer fired - requesting location update")
                self?.requestLocationUpdate()
            }

            // Add timer to run loop to ensure it fires
            if let timer = self.locationTimer {
                RunLoop.current.add(timer, forMode: .common)
                print("✅ Timer added to run loop")
            }
        }

        // Request immediate location update
        print("🚀 Requesting immediate location update")
        requestLocationUpdate()
    }

    private func stopLocationTimer() {
        DispatchQueue.main.async { [weak self] in
            self?.locationTimer?.invalidate()
            self?.locationTimer = nil
            print("🛑 Location timer stopped")
        }
        locationManager.stopUpdatingLocation()
    }

    private func requestLocationUpdate() {
        print("📝 requestLocationUpdate called - isTracking: \(isTracking)")

        guard isTracking else {
            print("⚠️ Not tracking, skipping location request")
            return
        }

        print("🔄 Requesting fresh location update")
        print("📍 Current location manager state:")
        print("  - Authorization: \(CLLocationManager.authorizationStatus().rawValue)")
        print("  - Desired accuracy: \(locationManager.desiredAccuracy)")
        print("  - Distance filter: \(locationManager.distanceFilter)")

        // For timer-based updates, we use requestLocation() which gives us a one-time location
        // This is more battery efficient than continuous updates
        locationManager.requestLocation()
        print("🚀 Location request sent")
    }

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
        guard let location = locations.last else {
            print("No location received in didUpdateLocations")
            return
        }

        print("✅ Location received: lat=\(location.coordinate.latitude), lon=\(location.coordinate.longitude)")
        lastLocationUpdate = Date().timeIntervalSince1970

        let locationDict = locationToDictionary(location)
        sendEvent(withName: "onLocationUpdate", body: locationDict)

        print("📡 Location event sent to React Native")
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("❌ Location manager failed with error: \(error.localizedDescription)")

        // Send error event to React Native
        let errorInfo: [String: Any] = [
            "error": error.localizedDescription,
            "code": (error as NSError).code,
            "timestamp": Date().timeIntervalSince1970 * 1000
        ]
        sendEvent(withName: "onLocationError", body: errorInfo)
    }

    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        print("Location authorization status changed to: \(status.rawValue)")

        // Handle authorization changes
        if status == .authorizedAlways {
            // If we have a stored config with background mode and tracking was requested, enable background features
            if let config = currentConfig, backgroundMode {
                do {
                    locationManager.allowsBackgroundLocationUpdates = true
                    locationManager.startMonitoringSignificantLocationChanges()
                } catch {
                    print("Error enabling background location updates after permission granted: \(error)")
                }
            }
        } else if status == .authorizedWhenInUse {
            // If we only have when-in-use permission, disable background mode
            if backgroundMode {
                backgroundMode = false
                locationManager.allowsBackgroundLocationUpdates = false
                locationManager.stopMonitoringSignificantLocationChanges()
            }
        } else if status == .denied || status == .restricted {
            // Stop tracking if permission is revoked
            if isTracking {
                stopLocationTracking({ _ in }, rejecter: { _, _, _ in })
            }
        }

        // Notify React Native about permission changes
        let permissionInfo: [String: Any] = [
            "status": authorizationStatusToString(status),
            "timestamp": Date().timeIntervalSince1970 * 1000
        ]
        sendEvent(withName: "onPermissionChanged", body: permissionInfo)
    }

    private func authorizationStatusToString(_ status: CLAuthorizationStatus) -> String {
        switch status {
        case .notDetermined:
            return "not_determined"
        case .denied:
            return "denied"
        case .restricted:
            return "restricted"
        case .authorizedWhenInUse:
            return "when_in_use"
        case .authorizedAlways:
            return "always"
        @unknown default:
            return "unknown"
        }
    }
}

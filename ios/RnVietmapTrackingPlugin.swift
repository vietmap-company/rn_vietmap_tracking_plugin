import Foundation
import CoreLocation
import React
import UIKit
import BackgroundTasks
import AVFoundation
import VietmapTrackingSDK

@objc(RnVietmapTrackingPlugin)
class RnVietmapTrackingPlugin: RCTEventEmitter {

    // MARK: - VietmapTrackingSDK Integration
    private var trackingManager: VietmapTrackingManager

    // MARK: - Configuration State (minimal, for React Native bridge reference only)
    private var isInitialized: Bool = false
    private var currentTrackingConfig: [String: Any]?
    private var currentAlertConfig: [String: Any]?

    override init() {
        // Initialize VietmapTrackingManager using shared singleton
        trackingManager = VietmapTrackingManager.shared

        super.init()

        // Setup SDK callbacks to forward events to React Native
        setupSDKCallbacks()

        print("✅ RnVietmapTrackingPlugin initialized with VietmapTrackingSDK")
    }

    deinit {
        // Clean up callbacks
        trackingManager.onLocationUpdate = nil
        trackingManager.onTrackingStatusChanged = nil
        trackingManager.onError = nil
        trackingManager.onPermissionChanged = nil
        trackingManager.onRouteUpdate = nil
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
            "onPermissionChanged",
            "onRouteUpdate"
        ]
    }

    // MARK: - SDK Callback Setup
    private func setupSDKCallbacks() {
        // Forward all SDK events to React Native
        trackingManager.onLocationUpdate = { [weak self] locationDict in
            DispatchQueue.main.async {
                self?.sendEvent(withName: "onLocationUpdate", body: locationDict as? [String: Any])
            }
        }

        trackingManager.onTrackingStatusChanged = { [weak self] statusDict in
            DispatchQueue.main.async {
                self?.sendEvent(withName: "onTrackingStatusChanged", body: statusDict as? [String: Any])
            }
        }

        trackingManager.onError = { [weak self] error in
            DispatchQueue.main.async {
                let errorInfo: [String: Any] = [
                    "error": error,
                    "timestamp": Date().timeIntervalSince1970 * 1000
                ]
                self?.sendEvent(withName: "onLocationError", body: errorInfo)
            }
        }

        trackingManager.onPermissionChanged = { [weak self] status in
            DispatchQueue.main.async {
                let permissionInfo: [String: Any] = [
                    "status": status,
                    "timestamp": Date().timeIntervalSince1970 * 1000
                ]
                self?.sendEvent(withName: "onPermissionChanged", body: permissionInfo)
            }
        }

        trackingManager.onRouteUpdate = { [weak self] success, routeData in
            DispatchQueue.main.async {
                let routeInfo: [String: Any] = [
                    "success": success,
                    "routeData": routeData as Any,
                    "timestamp": Date().timeIntervalSince1970 * 1000
                ]
                self?.sendEvent(withName: "onRouteUpdate", body: routeInfo)
            }
        }
    }

    // MARK: - React Native Bridge Methods

    @objc
    func multiply(_ a: Double, b: Double) -> NSNumber {
        return NSNumber(value: a * b)
    }

    // MARK: - SDK Configuration Methods

    @objc
    func configure(
        _ apiKey: String,
        baseURL: String?,
        autoUpload: Bool,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        print("🔧 Configuring VietmapTrackingSDK with apiKey: \(apiKey)")

        // Configure the SDK using proper methods
        trackingManager.configure(apiKey: apiKey)

        if let baseURL = baseURL {
            trackingManager.configure(baseURL: baseURL)
        }

        trackingManager.setAutoUpload(enabled: autoUpload)

        isInitialized = true

        print("✅ VietmapTrackingSDK configured successfully")
        resolver(true)
    }

    @objc
    func configureAlertAPI(
        _ url: String,
        apiKey: String,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        print("🚨 Configuring Alert API: \(url)")

        trackingManager.configureAlertAPI(url: url, apiKey: apiKey)

        currentAlertConfig = [
            "url": url,
            "apiKey": apiKey,
            "timestamp": Date().timeIntervalSince1970 * 1000
        ]

        print("✅ Alert API configured successfully")
        resolver(true)
    }

    // MARK: - Location and Tracking Methods

    @objc
    func getCurrentLocation(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        guard isInitialized else {
            reject("SDK_NOT_INITIALIZED", "VietmapTrackingSDK not initialized", nil)
            return
        }

        if let location = trackingManager.getCurrentLocation() {
            resolve(location)
        } else {
            reject("LOCATION_UNAVAILABLE", "Unable to get current location", nil)
        }
    }

    @objc
    func isTrackingActive(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        let isActive = trackingManager.isTrackingActive()
        resolve(isActive)
    }

    @objc
    func getTrackingStatus(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        let status = trackingManager.getTrackingStatus()
        resolve(status)
    }

    @objc
    func getTrackingHealthStatus(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        let healthStatus = trackingManager.getTrackingHealthStatus()
        resolve(healthStatus)
    }

    // MARK: - Permission Methods

    @objc
    func requestLocationPermissions(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        trackingManager.requestLocationPermissions { status in
            DispatchQueue.main.async {
                resolve(status)
            }
        }
    }

    @objc
    func hasLocationPermissions(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        let hasPermission = trackingManager.hasLocationPermissions()
        resolve(hasPermission)
    }

    @objc
    func requestAlwaysLocationPermissions(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        let locationManager = CLLocationManager()
        let currentStatus = locationManager.authorizationStatus

        print("🔐 Current location authorization status: \(currentStatus.rawValue)")

        // Check current authorization status
        switch currentStatus {
        case .authorizedAlways:
            print("✅ Always location permission already granted")
            resolve("granted")
            return

        case .authorizedWhenInUse:
            print("🔄 Requesting upgrade from WhenInUse to Always permission")
            // Request always permission when currently has when-in-use
            locationManager.requestAlwaysAuthorization()

            // Wait a bit and check the result
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                let newStatus = CLLocationManager().authorizationStatus
                switch newStatus {
                case .authorizedAlways:
                    print("✅ Successfully upgraded to Always permission")
                    resolve("granted")
                case .authorizedWhenInUse:
                    print("⚠️ User chose to keep WhenInUse permission")
                    resolve("when_in_use")
                case .denied:
                    print("❌ Permission denied")
                    resolve("denied")
                default:
                    print("🤔 Permission status: \(newStatus.rawValue)")
                    resolve("denied")
                }
            }

        case .notDetermined:
            print("🔄 Requesting Always location permission for the first time")
            // Request always permission directly
            locationManager.requestAlwaysAuthorization()

            // Wait a bit and check the result
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                let newStatus = CLLocationManager().authorizationStatus
                switch newStatus {
                case .authorizedAlways:
                    print("✅ Always permission granted")
                    resolve("granted")
                case .authorizedWhenInUse:
                    print("⚠️ User granted WhenInUse instead of Always")
                    resolve("when_in_use")
                case .denied:
                    print("❌ Permission denied")
                    resolve("denied")
                default:
                    print("🤔 Permission status: \(newStatus.rawValue)")
                    resolve("denied")
                }
            }

        case .denied, .restricted:
            print("❌ Location permission denied or restricted")
            resolve("denied")

        @unknown default:
            print("🤔 Unknown authorization status: \(currentStatus.rawValue)")
            resolve("denied")
        }
    }

    // MARK: - Tracking Control Methods

    @objc(startTracking:intervalMs:forceUpdateBackground:distanceFilter:resolver:rejecter:)
    func startTracking(
        backgroundMode: Bool,
        intervalMs: Int,
        forceUpdateBackground: Bool,
        distanceFilter: Double,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        guard isInitialized else {
            rejecter("SDK_NOT_INITIALIZED", "VietmapTrackingSDK not initialized", nil)
            return
        }

        print("🚀 Starting tracking via VietmapTrackingSDK")
        print("  - Background mode: \(backgroundMode)")
        print("  - Interval: \(intervalMs)ms")
        print("  - Force update: \(forceUpdateBackground)")
        print("  - Distance filter: \(distanceFilter)m")

        // Store tracking config for reference
        currentTrackingConfig = [
            "backgroundMode": backgroundMode,
            "intervalMs": intervalMs,
            "forceUpdateBackground": forceUpdateBackground,
            "distanceFilter": distanceFilter,
            "timestamp": Date().timeIntervalSince1970 * 1000
        ]

        // Use the appropriate SDK method based on parameters
        if forceUpdateBackground {
            trackingManager.startTracking(
                backgroundMode: backgroundMode,
                intervalMs: intervalMs,
                forceUpdateBackground: forceUpdateBackground,
                distanceFilter: distanceFilter
            ) { success, message in
                DispatchQueue.main.async {
                    if success {
                        resolver("Tracking started with forced background updates")
                    } else {
                        rejecter("TRACKING_START_FAILED", message ?? "Failed to start tracking", nil)
                    }
                }
            }
        } else {
            trackingManager.startTracking(
                enhancedBackgroundMode: backgroundMode,
                intervalMs: intervalMs,
                distanceFilter: distanceFilter
            ) { success, message in
                DispatchQueue.main.async {
                    if success {
                        resolver("Tracking started with enhanced background mode")
                    } else {
                        rejecter("TRACKING_START_FAILED", message ?? "Failed to start tracking", nil)
                    }
                }
            }
        }
    }

    @objc(stopTracking:rejecter:)
    func stopTracking(
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        print("🛑 Stopping tracking via VietmapTrackingSDK")

        trackingManager.stopTracking { success, message in
            DispatchQueue.main.async {
                if success {
                    resolver("Tracking stopped successfully")
                } else {
                    rejecter("TRACKING_STOP_FAILED", message ?? "Failed to stop tracking", nil)
                }
            }
        }
    }

    // MARK: - Alert Management Methods

    @objc(turnOnAlert:rejecter:)
    func turnOnAlert(
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        print("🚨 Turning on speed alert via VietmapTrackingSDK")

        trackingManager.turnOnAlert { success in
            DispatchQueue.main.async {
                if success {
                    print("✅ Speed alert turned on successfully")
                    resolver(true)
                } else {
                    print("❌ Failed to turn on speed alert")
                    resolver(false)
                }
            }
        }
    }

    @objc(turnOffAlert:rejecter:)
    func turnOffAlert(
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        print("🛑 Turning off speed alert via VietmapTrackingSDK")

        trackingManager.turnOffAlert { success in
            DispatchQueue.main.async {
                if success {
                    print("✅ Speed alert turned off successfully")
                    resolver(true)
                } else {
                    print("❌ Failed to turn off speed alert")
                    resolver(false)
                }
            }
        }
    }

    // MARK: - Route Management Methods

    @objc(getCurrentRouteInfo:rejecter:)
    func getCurrentRouteInfo(
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        if let routeInfo = trackingManager.getCurrentRouteInfo() {
            resolver(routeInfo)
        } else {
            rejecter("NO_ROUTE_DATA", "No route data available", nil)
        }
    }

    @objc(setRouteAPIEndpoint:resolver:rejecter:)
    func setRouteAPIEndpoint(
        endpoint: String,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        print("🗺️ Setting route API endpoint: \(endpoint)")

        trackingManager.setRouteAPIEndpoint(endpoint) { success in
            DispatchQueue.main.async {
                if success {
                    print("✅ Route API endpoint set successfully")
                    resolver(true)
                } else {
                    print("❌ Failed to set route API endpoint")
                    rejecter("ENDPOINT_SET_FAILED", "Failed to set route API endpoint", nil)
                }
            }
        }
    }

    @objc(enableRouteBoundaryDetection:resolver:rejecter:)
    func enableRouteBoundaryDetection(
        threshold: Double,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        print("🎯 Enabling route boundary detection with threshold: \(threshold)m")

        trackingManager.enableRouteBoundaryDetection(threshold: threshold) { success in
            DispatchQueue.main.async {
                if success {
                    print("✅ Route boundary detection enabled")
                    resolver(true)
                } else {
                    print("❌ Failed to enable route boundary detection")
                    rejecter("BOUNDARY_DETECTION_FAILED", "Failed to enable route boundary detection", nil)
                }
            }
        }
    }

    // MARK: - Data Management Methods

    @objc(encodeLocationData:resolver:rejecter:)
    func encodeLocationData(
        locationDict: NSDictionary,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        if let encodedData = trackingManager.encodeLocationData(locationDict) {
            // Convert Data to base64 string for React Native
            let base64String = encodedData.base64EncodedString()
            resolver(base64String)
        } else {
            rejecter("ENCODING_FAILED", "Failed to encode location data", nil)
        }
    }

    @objc(decodeLocationData:resolver:rejecter:)
    func decodeLocationData(
        base64String: String,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        guard let data = Data(base64Encoded: base64String) else {
            rejecter("INVALID_DATA", "Invalid base64 string", nil)
            return
        }

        if let decodedDict = trackingManager.decodeLocationData(data) {
            resolver(decodedDict)
        } else {
            rejecter("DECODING_FAILED", "Failed to decode location data", nil)
        }
    }

    @objc(getCachedLocationsCount:rejecter:)
    func getCachedLocationsCount(
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        let count = trackingManager.getCachedLocationsCount()
        resolver(count)
    }

    @objc(uploadCachedLocationsManually:rejecter:)
    func uploadCachedLocationsManually(
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        print("📤 Manually uploading cached locations")

        trackingManager.uploadCachedLocationsManually { success, message in
            DispatchQueue.main.async {
                if success {
                    print("✅ Cached locations uploaded successfully")
                    resolver(true)
                } else {
                    print("❌ Failed to upload cached locations: \(message ?? "Unknown error")")
                    rejecter("UPLOAD_FAILED", message ?? "Failed to upload cached locations", nil)
                }
            }
        }
    }

    @objc(clearCachedLocations:rejecter:)
    func clearCachedLocations(
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        print("🗑️ Clearing cached locations")

        trackingManager.clearCachedLocations()

        print("✅ Cached locations cleared")
        resolver(true)
    }

    // MARK: - Network and System Methods

    @objc(isNetworkConnected:rejecter:)
    func isNetworkConnected(
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        let isConnected = trackingManager.isNetworkConnected()
        resolver(isConnected)
    }

    // MARK: - Utility Methods

    @objc(setTrackingStatus:resolver:rejecter:)
    func setTrackingStatus(
        status: String,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        print("📝 Setting tracking status: \(status)")

        trackingManager.setTrackingStatus(status)

        print("✅ Tracking status set successfully")
        resolver(true)
    }

    @objc(setAutoUpload:resolver:rejecter:)
    func setAutoUpload(
        enabled: Bool,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        print("🔄 Setting auto upload: \(enabled)")

        trackingManager.setAutoUpload(enabled: enabled)

        print("✅ Auto upload setting updated")
        resolver(true)
    }
}

// MARK: - Legacy Support Methods (kept for backward compatibility)

extension RnVietmapTrackingPlugin {

    @objc(findNearestAlert:longitude:resolver:rejecter:)
    func findNearestAlert(
        latitude: Double,
        longitude: Double,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        // This method is now handled internally by VietmapTrackingSDK
        // We delegate to getCurrentRouteInfo for route-related data
        if let routeInfo = trackingManager.getCurrentRouteInfo() {
            // Extract relevant alert information
            let alertInfo: [String: Any] = [
                "latitude": latitude,
                "longitude": longitude,
                "routeInfo": routeInfo,
                "timestamp": Date().timeIntervalSince1970 * 1000
            ]
            resolver(alertInfo)
        } else {
            rejecter("NO_ROUTE_DATA", "No route data available for alert calculation", nil)
        }
    }

    @objc(updateTrackingConfig:resolver:rejecter:)
    func updateTrackingConfig(
        config: NSDictionary,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        // Configuration updates are now handled by VietmapTrackingSDK internally
        // This method is kept for backward compatibility
        print("⚙️ Tracking config update request received (handled by SDK)")

        // Store config for reference but don't actually change SDK configuration
        // during active tracking (SDK handles this internally)
        if var currentConfig = currentTrackingConfig {
            if let accuracy = config["accuracy"] as? String {
                currentConfig["accuracy"] = accuracy
            }
            if let distanceFilter = config["distanceFilter"] as? Double {
                currentConfig["distanceFilter"] = distanceFilter
            }
            if let enableBackgroundMode = config["enableBackgroundMode"] as? Bool {
                currentConfig["enableBackgroundMode"] = enableBackgroundMode
            }

            currentTrackingConfig = currentConfig
        }

        print("✅ Config stored for reference (actual changes handled by SDK)")
        resolver(true)
    }
}

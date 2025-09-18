import Foundation
import CoreLocation
import React
import UIKit
import BackgroundTasks
import AVFoundation
import VietmapTrackingSDK

#if RCT_NEW_ARCH_ENABLED
import RnVietmapTrackingPluginSpec
#endif

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

    // MARK: - TurboModule Support
    override static func moduleName() -> String! {
        return "RnVietmapTrackingPlugin"
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
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {

        // Configure the SDK using proper methods
        trackingManager.configure(apiKey: apiKey)

        if let baseURL = baseURL {
            trackingManager.configure(baseURL: baseURL)
        }

        trackingManager.setAutoUpload(enabled: true)

        isInitialized = true
        resolver(true)
    }

    @objc
    func configureAlertAPI(
        _ apiKey: String,
        apiID: String,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        trackingManager.configureAlertAPI(apiKey: apiKey, apiID: apiID)

        currentAlertConfig = [
            "apiKey": apiKey,
            "timestamp": Date().timeIntervalSince1970 * 1000
        ]
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
                // Convert status string to PermissionResult object to match Android implementation
                let permissionResult: [String: Any] = [
                    "granted": status == "granted",
                    "status": status,
                    "fineLocation": status == "granted",
                    "coarseLocation": status == "granted",
                    "backgroundLocation": status == "granted" // iOS manages this differently
                ]
                resolve(permissionResult)
            }
        }
    }

    @objc
    func hasLocationPermissions(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        let hasPermission = trackingManager.hasLocationPermissions()

        // Convert boolean to PermissionResult object to match Android implementation
        let permissionResult: [String: Any] = [
            "granted": hasPermission,
            "status": hasPermission ? "granted" : "not_granted",
            "fineLocation": hasPermission,
            "coarseLocation": hasPermission,
            "backgroundLocation": hasPermission
        ]

        resolve(permissionResult)
    }

    @objc
    func requestAlwaysLocationPermissions(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        let locationManager = CLLocationManager()
        let currentStatus = locationManager.authorizationStatus

        // Check current authorization status
        switch currentStatus {
        case .authorizedAlways:
            resolve("granted")
            return

        case .authorizedWhenInUse:
            // Request always permission when currently has when-in-use
            locationManager.requestAlwaysAuthorization()

            // Wait a bit and check the result
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                let newStatus = CLLocationManager().authorizationStatus
                switch newStatus {
                case .authorizedAlways:
                    resolve("granted")
                case .authorizedWhenInUse:
                    resolve("when_in_use")
                case .denied:
                    resolve("denied")
                default:
                    resolve("denied")
                }
            }

        case .notDetermined:
            // Request always permission directly
            locationManager.requestAlwaysAuthorization()

            // Wait a bit and check the result
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                let newStatus = CLLocationManager().authorizationStatus
                switch newStatus {
                case .authorizedAlways:
                    resolve("granted")
                case .authorizedWhenInUse:
                    resolve("when_in_use")
                case .denied:
                    resolve("denied")
                default:
                    resolve("denied")
                }
            }

        case .denied, .restricted:
            resolve("denied")

        @unknown default:
            resolve("denied")
        }
    }

    // MARK: - Tracking Control Methods

    @objc(startTracking:intervalMs:distanceFilter:notificationTitle:notificationMessage:resolver:rejecter:)
    func startTracking(
        backgroundMode: Bool,
        intervalMs: Int,
        distanceFilter: Double,
        notificationTitle: String?,
        notificationMessage: String?,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        guard isInitialized else {
            rejecter("SDK_NOT_INITIALIZED", "VietmapTrackingSDK not initialized", nil)
            return
        }

        // Store tracking config for reference
        currentTrackingConfig = [
            "backgroundMode": backgroundMode,
            "intervalMs": intervalMs,
            "distanceFilter": distanceFilter,
            "notificationTitle": notificationTitle ?? "",
            "notificationMessage": notificationMessage ?? "",
            "timestamp": Date().timeIntervalSince1970 * 1000
        ]

        trackingManager.startTracking(
            enhancedBackgroundMode: backgroundMode,
            intervalMs: intervalMs,
            distanceFilter: distanceFilter
        ) { success, message in
            DispatchQueue.main.async {
                if success {
                    resolver(true)
                } else {
                    resolver(false)
                }
            }
        }
    }

    @objc(stopTracking:rejecter:)
    func stopTracking(
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        guard isInitialized else {
            rejecter("SDK_NOT_INITIALIZED", "VietmapTrackingSDK not initialized", nil)
            return
        }

        trackingManager.stopTracking { success, message in
            DispatchQueue.main.async {
                if success {
                    resolver(true)
                } else {
                    resolver(false)
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

        trackingManager.turnOnAlert { success in
            DispatchQueue.main.async {
                if success {
                    resolver(true)
                } else {
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

        trackingManager.turnOffAlert { success in
            DispatchQueue.main.async {
                if success {
                    resolver(true)
                } else {
                    resolver(false)
                }
            }
        }
    }
}

// MARK: - Legacy Support Methods (kept for backward compatibility)

extension RnVietmapTrackingPlugin {
    @objc(updateTrackingConfig:resolver:rejecter:)
    func updateTrackingConfig(
        config: NSDictionary,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {

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
        resolver(true)
    }
}

#if RCT_NEW_ARCH_ENABLED
// MARK: - TurboModule Protocol Implementation
extension RnVietmapTrackingPlugin: NativeRnVietmapTrackingPluginSpec {
    func getTypedExportedConstants() -> [String: Any] {
        return [:]
    }
}
#endif

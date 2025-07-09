import Foundation
import CoreLocation
import React
import UIKit
import BackgroundTasks // Add for iOS 13+ background task scheduling

@objc(RnVietmapTrackingPlugin)
class RnVietmapTrackingPlugin: RCTEventEmitter {

    private var locationManager: CLLocationManager!
    private var isTracking: Bool = false
    private var trackingStartTime: TimeInterval = 0
    private var lastLocationUpdate: TimeInterval = 0
    // private var locationTimer: Timer? // DEPRECATED: No longer needed with continuous updates
    private var intervalMs: Int = 5000 // Default 5 seconds
    private var backgroundMode: Bool = false
    private var currentConfig: NSDictionary?
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
    private var isInBackground: Bool = false

    // Enhanced background processing support (iOS 13+)
    private var backgroundLocationTaskId = "com.rnvietmaptrackingplugin.background-location"
    private var locationSyncTaskId = "com.rnvietmaptrackingplugin.location-sync"

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

        // Register background tasks for iOS 13+
        registerBackgroundTasks()

        // Add observers for app state changes
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
        endBackgroundTask()
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
    func getCurrentLocation(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {

        let status = locationManager.authorizationStatus
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

        let status = locationManager.authorizationStatus

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

        let status = locationManager.authorizationStatus
        let hasPermission = (status == .authorizedWhenInUse || status == .authorizedAlways)

        resolve(hasPermission)
    }

    @objc
    func requestAlwaysLocationPermissions(_ resolve: @escaping RCTPromiseResolveBlock, rejecter reject: @escaping RCTPromiseRejectBlock) {

        let status = locationManager.authorizationStatus

        switch status {
        case .authorizedAlways:
            resolve("granted")
        case .authorizedWhenInUse:
            print("🔑 Upgrading from 'when in use' to 'always' permission")
            locationManager.requestAlwaysAuthorization()
            resolve("pending")
        case .denied, .restricted:
            resolve("denied")
        case .notDetermined:
            print("🔑 Requesting 'always' location permission")
            locationManager.requestAlwaysAuthorization()
            resolve("pending")
        @unknown default:
            resolve("unknown")
        }
    }

    @objc private func appDidEnterBackground() {
        print("📱 App entered background")
        isInBackground = true

        if isTracking {
            print("🌙 Starting background location tracking with continuous updates")
            startBackgroundLocationTracking()
        }
    }

    @objc private func appWillEnterForeground() {
        print("📱 App entering foreground")
        isInBackground = false

        // End background task
        endBackgroundTask()

        if isTracking {
            print("🔄 Continuing tracking in foreground mode")
            // Keep continuous updates but no need for background tasks
        }
    }

    private func startBackgroundLocationTracking() {
        // Always use continuous location updates for background
        locationManager.startUpdatingLocation()

        // Start background task chaining
        startBackgroundTaskChain()

        // Schedule modern background tasks for iOS 13+
        if #available(iOS 13.0, *) {
            scheduleBackgroundLocationTask()
            scheduleLocationSyncTask()
        }

        // Enable deferred location updates for battery optimization
        if backgroundMode && locationManager.authorizationStatus == .authorizedAlways {
            enableDeferredLocationUpdates()
        }
    }

    private func startBackgroundTaskChain() {
        guard backgroundTaskId == .invalid else {
            print("⚠️ Background task already running")
            return
        }

        print("🔄 Starting background task chain...")

        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "LocationTracking") { [weak self] in
            print("⏰ Background task expiring - chaining to new task")
            self?.chainBackgroundTask()
        }

        if backgroundTaskId != .invalid {
            print("✅ Background task started with ID: \(backgroundTaskId.rawValue)")

            // Schedule task renewal before expiration (25 seconds instead of 30)
            DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
                guard let self = self, self.isInBackground && self.isTracking else { return }
                print("🔄 Proactively renewing background task")
                self.chainBackgroundTask()
            }
        } else {
            print("❌ Failed to start background task")
        }
    }

    private func chainBackgroundTask() {
        print("🔗 Chaining background task...")

        let oldTaskId = backgroundTaskId
        backgroundTaskId = .invalid

        // Start new background task
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "LocationTracking") { [weak self] in
            print("⏰ Chained background task expiring - creating new chain")
            self?.chainBackgroundTask()
        }

        // End old task
        if oldTaskId != .invalid {
            UIApplication.shared.endBackgroundTask(oldTaskId)
            print("🛑 Ended old background task: \(oldTaskId.rawValue)")
        }

        if backgroundTaskId != .invalid {
            print("✅ New background task chained with ID: \(backgroundTaskId.rawValue)")

            // Schedule next renewal
            DispatchQueue.main.asyncAfter(deadline: .now() + 25) { [weak self] in
                guard let self = self, self.isInBackground && self.isTracking else { return }
                self.chainBackgroundTask()
            }
        } else {
            print("❌ Failed to chain background task")
        }
    }

    private func enableDeferredLocationUpdates() {
        print("🔋 Enabling deferred location updates for battery optimization")

        // Defer updates by distance or time to save battery
        let deferredDistance: CLLocationDistance = 500 // 500 meters
        let deferredTimeout: TimeInterval = TimeInterval(intervalMs * 2) / 1000.0 // 2x interval

        locationManager.allowDeferredLocationUpdates(untilTraveled: deferredDistance, timeout: deferredTimeout)
        print("🔋 Deferred updates: \(deferredDistance)m or \(deferredTimeout)s")
    }

    private func endBackgroundTask() {
        if backgroundTaskId != .invalid {
            print("🛑 Ending background task: \(backgroundTaskId.rawValue)")
            UIApplication.shared.endBackgroundTask(backgroundTaskId)
            backgroundTaskId = .invalid
        }

        // Disable deferred updates
        locationManager.disallowDeferredLocationUpdates()
    }

    @objc(startTracking:intervalMs:resolver:rejecter:)
    func startTracking(backgroundMode: Bool, intervalMs: Int, resolver: @escaping RCTPromiseResolveBlock, rejecter: @escaping RCTPromiseRejectBlock) {
        print("🚀 Starting tracking - Background mode: \(backgroundMode), Interval: \(intervalMs)ms")

        guard !isTracking else {
            print("⚠️ Already tracking")
            resolver("Already tracking")
            return
        }

        self.backgroundMode = backgroundMode
        self.intervalMs = intervalMs

        // Validate location permissions
        let status = locationManager.authorizationStatus
        print("📍 Current location authorization: \(status.rawValue)")

        if backgroundMode && status != .authorizedAlways {
            rejecter("PERMISSION_ERROR", "Background tracking requires 'Always' location permission", nil)
            return
        }

        if !backgroundMode && (status == .denied || status == .restricted) {
            rejecter("PERMISSION_ERROR", "Location permission denied", nil)
            return
        }

        // Configure location manager for continuous updates
        configureLocationManagerForContinuousUpdates()

        isTracking = true
        trackingStartTime = Date().timeIntervalSince1970

        // Always use continuous location updates
        print("🔄 Starting continuous location updates")
        locationManager.startUpdatingLocation()

        // If already in background, start background task chain
        if isInBackground {
            startBackgroundLocationTracking()
        }

        sendTrackingStatusUpdate()
        resolver("Tracking started with continuous updates")
    }

    private func configureLocationManagerForContinuousUpdates() {
        // Configure accuracy based on tracking mode
        if backgroundMode {
            // Background mode - optimize for battery
            locationManager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            locationManager.distanceFilter = 10 // Larger distance filter to save battery

            // Enable significant location changes as fallback
            if CLLocationManager.significantLocationChangeMonitoringAvailable() {
                locationManager.startMonitoringSignificantLocationChanges()
                print("✅ Significant location change monitoring enabled")
            }

            // Enable background location updates
            if locationManager.authorizationStatus == .authorizedAlways {
                locationManager.allowsBackgroundLocationUpdates = true
                locationManager.pausesLocationUpdatesAutomatically = false
                print("✅ Background location updates enabled")
            }
        } else {
            // Foreground mode - high accuracy
            locationManager.desiredAccuracy = kCLLocationAccuracyBest
            locationManager.distanceFilter = 5 // 5 meters minimum distance
        }

        print("⚙️ Location manager configured for enhanced tracking")
        print("📍 Desired accuracy: \(locationManager.desiredAccuracy)")
        print("📏 Distance filter: \(locationManager.distanceFilter)")
        print("🌙 Background mode: \(backgroundMode)")
        print("⏰ Update interval: \(intervalMs)ms")
    }

    @objc(stopTracking:rejecter:)
    func stopTracking(resolver: @escaping RCTPromiseResolveBlock, rejecter: @escaping RCTPromiseRejectBlock) {
        print("🛑 Stopping tracking")

        guard isTracking else {
            print("⚠️ Not currently tracking")
            resolver("Not tracking")
            return
        }

        isTracking = false

        // Stop all location services
        locationManager.stopUpdatingLocation()
        locationManager.stopMonitoringSignificantLocationChanges()
        locationManager.disallowDeferredLocationUpdates()

        // Disable background location updates safely
        if backgroundMode && locationManager.authorizationStatus == .authorizedAlways {
            locationManager.allowsBackgroundLocationUpdates = false
        }

        // End background task
        endBackgroundTask()

        backgroundMode = false
        sendTrackingStatusUpdate()
        print("✅ Tracking stopped")
        resolver("Tracking stopped")
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

    // MARK: - Enhanced Background Task Registration (iOS 13+)

    private func registerBackgroundTasks() {
        if #available(iOS 13.0, *) {
            // Register background location task
            BGTaskScheduler.shared.register(forTaskWithIdentifier: backgroundLocationTaskId, using: nil) { task in
                self.handleBackgroundLocationTask(task: task as! BGAppRefreshTask)
            }

            // Register location sync task
            BGTaskScheduler.shared.register(forTaskWithIdentifier: locationSyncTaskId, using: nil) { task in
                self.handleLocationSyncTask(task: task as! BGProcessingTask)
            }

            print("✅ Background tasks registered for iOS 13+")
        } else {
            print("ℹ️ Using legacy background task management (iOS < 13)")
        }
    }

    @available(iOS 13.0, *)
    private func handleBackgroundLocationTask(task: BGAppRefreshTask) {
        print("🔄 Handling background location task")

        // Schedule the next background location task
        scheduleBackgroundLocationTask()

        task.expirationHandler = {
            print("⏰ Background location task expired")
            task.setTaskCompleted(success: false)
        }

        // Perform location update if tracking is active
        if isTracking && backgroundMode {
            print("📍 Performing background location update")
            locationManager.requestLocation()

            // Complete task after brief delay
            DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
                print("✅ Background location task completed")
                task.setTaskCompleted(success: true)
            }
        } else {
            print("⏭️ Skipping background location task - tracking not active")
            task.setTaskCompleted(success: true)
        }
    }

    @available(iOS 13.0, *)
    private func handleLocationSyncTask(task: BGProcessingTask) {
        print("🔄 Handling location sync task")

        task.expirationHandler = {
            print("⏰ Location sync task expired")
            task.setTaskCompleted(success: false)
        }

        // Perform any location data sync or processing
        if isTracking {
            print("💾 Syncing location data in background")
            // Here you could sync data to server, process accumulated locations, etc.

            DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
                print("✅ Location sync task completed")
                task.setTaskCompleted(success: true)
            }
        } else {
            task.setTaskCompleted(success: true)
        }
    }

    @available(iOS 13.0, *)
    private func scheduleBackgroundLocationTask() {
        let request = BGAppRefreshTaskRequest(identifier: backgroundLocationTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: TimeInterval(intervalMs) / 1000.0)

        do {
            try BGTaskScheduler.shared.submit(request)
            print("✅ Background location task scheduled")
        } catch {
            print("❌ Failed to schedule background location task: \(error)")
        }
    }

    @available(iOS 13.0, *)
    private func scheduleLocationSyncTask() {
        let request = BGProcessingTaskRequest(identifier: locationSyncTaskId)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 300) // 5 minutes
        request.requiresNetworkConnectivity = true
        request.requiresExternalPower = false

        do {
            try BGTaskScheduler.shared.submit(request)
            print("✅ Location sync task scheduled")
        } catch {
            print("❌ Failed to schedule location sync task: \(error)")
        }
    }
}

// MARK: - CLLocationManagerDelegate

extension RnVietmapTrackingPlugin: CLLocationManagerDelegate {

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            print("No location received in didUpdateLocations")
            return
        }

        let currentTime = Date().timeIntervalSince1970

        // Enhanced throttling based on intervalMs for both foreground and background
        let timeSinceLastUpdate = currentTime - lastLocationUpdate
        let minimumInterval = Double(intervalMs) / 1000.0

        // Apply throttling for all modes to respect intervalMs parameter
        if timeSinceLastUpdate < minimumInterval {
            print("⏭️ Skipping location update - respecting intervalMs throttling")
            print("  - Time since last: \(String(format: "%.1f", timeSinceLastUpdate))s")
            print("  - Required interval: \(String(format: "%.1f", minimumInterval))s")
            print("  - Background mode: \(backgroundMode), In background: \(isInBackground)")
            return
        }

        print("✅ Location received: lat=\(location.coordinate.latitude), lon=\(location.coordinate.longitude)")
        print("📊 Update info (continuous mode):")
        print("  - Background mode: \(backgroundMode)")
        print("  - Is in background: \(isInBackground)")
        print("  - Configured interval: \(intervalMs)ms")
        print("  - Actual interval: \(Int(timeSinceLastUpdate * 1000))ms")
        print("  - Accuracy: \(location.horizontalAccuracy)m")
        print("  - Speed: \(location.speed)m/s")

        lastLocationUpdate = currentTime

        let locationDict = locationToDictionary(location)
        sendEvent(withName: "onLocationUpdate", body: locationDict)

        print("📡 Location event sent to React Native (continuous updates)")
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
            if currentConfig != nil && backgroundMode {
                print("✅ Always permission granted - enabling background location updates")
                locationManager.allowsBackgroundLocationUpdates = true
                locationManager.pausesLocationUpdatesAutomatically = false
                locationManager.startMonitoringSignificantLocationChanges()
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
                stopTracking(resolver: { _ in }, rejecter: { _, _, _ in })
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

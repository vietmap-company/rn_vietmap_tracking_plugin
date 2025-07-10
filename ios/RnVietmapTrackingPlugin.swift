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
    private var forceUpdateBackground: Bool = false // New option for forced updates
    private var currentConfig: NSDictionary?
    private var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
    private var isInBackground: Bool = false
    private var locationTimer: Timer? // Timer for forced updates

    // Enhanced background processing support (iOS 13+)
    private var backgroundLocationTaskId = "com.rnvietmaptrackingplugin.background-location"
    private var locationSyncTaskId = "com.rnvietmaptrackingplugin.location-sync"

    // Store pending resolvers for permission callback
    private var pendingAlertResolver: RCTPromiseResolveBlock?
    private var pendingAlertRejecter: RCTPromiseRejectBlock?
    private var isSpeedAlertActive: Bool = false

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

        // ✅ Also handle speed alert background tracking
        if isSpeedAlertActive {
            print("🚨 Starting background location tracking for speed alert")
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

        if isSpeedAlertActive {
            print("🚨 Continuing speed alert in foreground mode")
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
        if (backgroundMode || isSpeedAlertActive) && locationManager.authorizationStatus == .authorizedAlways {
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
                guard let self = self, self.isInBackground && (self.isTracking || self.isSpeedAlertActive) else { return }
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
                guard let self = self, self.isInBackground && (self.isTracking || self.isSpeedAlertActive) else { return }
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

    @objc(startTracking:intervalMs:forceUpdateBackground:distanceFilter:resolver:rejecter:)
    func startTracking(backgroundMode: Bool, intervalMs: Int, forceUpdateBackground: Bool, distanceFilter: Double, resolver: @escaping RCTPromiseResolveBlock, rejecter: @escaping RCTPromiseRejectBlock) {
        print("🚀 Starting tracking - Background mode: \(backgroundMode), Interval: \(intervalMs)ms, Force update: \(forceUpdateBackground), Distance filter: \(distanceFilter)m")

        guard !isTracking else {
            print("⚠️ Already tracking")
            resolver("Already tracking")
            return
        }

        self.backgroundMode = backgroundMode
        self.intervalMs = intervalMs
        self.forceUpdateBackground = forceUpdateBackground

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

        // Configure location manager based on force update mode
        if forceUpdateBackground {
            configureLocationManagerForForcedUpdates()
        } else {
            configureLocationManagerForContinuousUpdates()
            // Set distance filter only for standard mode
            locationManager.distanceFilter = distanceFilter
            print("📏 Distance filter set to: \(distanceFilter)m")
        }

        isTracking = true
        trackingStartTime = Date().timeIntervalSince1970

        if forceUpdateBackground {
            print("🔄 Starting forced location updates with timer")
            startLocationTimer()
        } else {
            print("🔄 Starting continuous location updates")
            locationManager.startUpdatingLocation()
        }

        // If already in background, start background task chain
        if isInBackground {
            startBackgroundLocationTracking()
        }

        sendTrackingStatusUpdate()
        let trackingMode = forceUpdateBackground ? "forced timer" : "continuous updates"
        resolver("Tracking started with \(trackingMode)")
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

    private func configureLocationManagerForForcedUpdates() {
        // Force update mode - request location on timer regardless of distance
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = kCLDistanceFilterNone // No distance filter

        // Enable background location updates if needed
        if backgroundMode && locationManager.authorizationStatus == .authorizedAlways {
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.pausesLocationUpdatesAutomatically = false
            print("✅ Background location updates enabled for forced mode")
        }

        print("⚙️ Location manager configured for forced updates")
        print("📍 Desired accuracy: \(locationManager.desiredAccuracy)")
        print("📏 Distance filter: NONE (forced mode)")
        print("🌙 Background mode: \(backgroundMode)")
        print("⏰ Timer interval: \(intervalMs)ms")
    }

    private func startLocationTimer() {
        // Stop existing timer
        stopLocationTimer()

        let interval = TimeInterval(intervalMs) / 1000.0
        locationTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.requestLocationUpdate()
        }

        print("⏰ Location timer started with interval: \(interval)s")
    }

    private func stopLocationTimer() {
        locationTimer?.invalidate()
        locationTimer = nil
        print("⏰ Location timer stopped")
    }

    private func requestLocationUpdate() {
        guard isTracking else {
            print("⚠️ Not tracking - stopping timer")
            stopLocationTimer()
            return
        }

        print("🔄 Requesting forced location update (timer-based)")
        locationManager.requestLocation()
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

        // Stop timer if in forced mode
        if forceUpdateBackground {
            stopLocationTimer()
        }

        // Disable background location updates safely
        if backgroundMode && locationManager.authorizationStatus == .authorizedAlways {
            locationManager.allowsBackgroundLocationUpdates = false
        }

        // End background task
        endBackgroundTask()

        backgroundMode = false
        forceUpdateBackground = false
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
        if (isTracking && backgroundMode) || isSpeedAlertActive {
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
        if isTracking || isSpeedAlertActive {
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

        // Print detailed location info if speed alert is active
        if isSpeedAlertActive {
            print("🚨 [SPEED ALERT] Location Update:")
            print("  📍 Coordinates: \(location.coordinate.latitude), \(location.coordinate.longitude)")
            print("  🚗 Speed: \(location.speed) m/s (\(String(format: "%.1f", location.speed * 3.6)) km/h)")
            print("  📏 Accuracy: \(location.horizontalAccuracy)m")
            print("  🧭 Bearing: \(location.course)°")
            print("  ⏰ Time: \(DateFormatter.localizedString(from: location.timestamp, dateStyle: .none, timeStyle: .medium))")
            print("  🌍 Altitude: \(location.altitude)m")
        }

        if forceUpdateBackground {
            // Force update mode - always send location, no throttling
            print("✅ Location received (forced mode): lat=\(location.coordinate.latitude), lon=\(location.coordinate.longitude)")
            print("📊 Update info (forced timer mode):")
            print("  - Background mode: \(backgroundMode)")
            print("  - Is in background: \(isInBackground)")
            print("  - Force update: \(forceUpdateBackground)")
            print("  - Accuracy: \(location.horizontalAccuracy)m")
            print("  - Speed: \(location.speed)m/s")

            lastLocationUpdate = currentTime
            let locationDict = locationToDictionary(location)
            sendEvent(withName: "onLocationUpdate", body: locationDict)
            print("📡 Location event sent to React Native (forced mode)")
        } else {
            // Enhanced throttling based on intervalMs for both foreground and background
            let timeSinceLastUpdate = currentTime - lastLocationUpdate
            let minimumInterval = Double(intervalMs) / 1000.0

            // Apply throttling for all modes to respect intervalMs parameter
            if timeSinceLastUpdate < minimumInterval {
                if !isSpeedAlertActive {
                    print("⏭️ Skipping location update - respecting intervalMs throttling")
                    print("  - Time since last: \(String(format: "%.1f", timeSinceLastUpdate))s")
                    print("  - Required interval: \(String(format: "%.1f", minimumInterval))s")
                    print("  - Background mode: \(backgroundMode), In background: \(isInBackground)")
                }
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

        // Handle pending alert resolver if exists
        if let resolver = pendingAlertResolver {
            switch status {
            case .authorizedAlways:
                print("✅ Location permission granted (Always) for speed alert - enabling background monitoring")
                startSpeedAlertLocationMonitoring()
                resolver(true)
            case .authorizedWhenInUse:
                print("⚠️ Only When In Use permission granted - background monitoring may be limited")
                startSpeedAlertLocationMonitoring()
                resolver(true)
            case .denied, .restricted:
                print("❌ Location permission denied for speed alert")
                resolver(false)
            case .notDetermined:
                print("📱 Location permission still not determined")
                // Keep waiting for user decision
                return
            @unknown default:
                print("❓ Unknown permission status for speed alert")
                resolver(false)
            }

            // Clear pending resolvers
            pendingAlertResolver = nil
            pendingAlertRejecter = nil
        }

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

    // MARK: - Speed Alert Methods

    @objc(turnOnAlert:rejecter:)
    func turnOnAlert(resolver: @escaping RCTPromiseResolveBlock, rejecter: @escaping RCTPromiseRejectBlock) {
        print("🚨 Turning on speed alert")

        // Check current location permission status
        let authorizationStatus = locationManager.authorizationStatus
        print("🔒 Current location permission status: \(authorizationStatus.rawValue)")

        switch authorizationStatus {
        case .notDetermined:
            print("📱 Location permission not determined, requesting Always permission for background...")
            // Store the resolver to call it after permission is granted/denied
            self.pendingAlertResolver = resolver
            self.pendingAlertRejecter = rejecter
            // Request Always permission for background location
            locationManager.requestAlwaysAuthorization()
            return

        case .authorizedWhenInUse:
            print("📱 Have When In Use permission, requesting Always permission for background...")
            // Store the resolver to call it after permission is granted/denied
            self.pendingAlertResolver = resolver
            self.pendingAlertRejecter = rejecter
            // Upgrade to Always permission for background location
            locationManager.requestAlwaysAuthorization()
            return

        case .denied, .restricted:
            print("❌ Location permission denied or restricted")
            resolver(false)
            return

        case .authorizedAlways:
            print("✅ Location permission granted (Always), starting background monitoring for speed alert")
            startSpeedAlertLocationMonitoring()
            resolver(true)
            return

        @unknown default:
            print("❓ Unknown permission status")
            resolver(false)
            return
        }
    }

    private func startSpeedAlertLocationMonitoring() {
        print("🎯 Starting continuous location monitoring for speed alert")

        isSpeedAlertActive = true

        // Configure for high sensitivity to get frequent updates
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.distanceFilter = 5.0 // Updated to 5 meters as requested

        let currentAuth = locationManager.authorizationStatus
        print("🔒 Current authorization for speed alert: \(currentAuth.rawValue)")

        // Enable background location if we have always permission
        if currentAuth == .authorizedAlways {
            locationManager.allowsBackgroundLocationUpdates = true
            locationManager.pausesLocationUpdatesAutomatically = false
            print("✅ Background location monitoring enabled for speed alert (Always permission)")

            // Start significant location changes for background efficiency
            if CLLocationManager.significantLocationChangeMonitoringAvailable() {
                locationManager.startMonitoringSignificantLocationChanges()
                print("✅ Significant location change monitoring enabled")
            }

            // ✅ Use same background infrastructure as tracking
            if isInBackground {
                print("🌙 Starting background location tracking for speed alert")
                startBackgroundLocationTracking()
            }

            // ✅ Enable deferred location updates for battery optimization
            enableDeferredLocationUpdates()

            // ✅ Schedule modern background tasks for iOS 13+
            if #available(iOS 13.0, *) {
                scheduleBackgroundLocationTask()
                scheduleLocationSyncTask()
            }
        } else {
            print("⚠️ Background location limited - only When In Use permission")
            locationManager.allowsBackgroundLocationUpdates = false
            locationManager.pausesLocationUpdatesAutomatically = true
        }

        // Start continuous location updates
        locationManager.startUpdatingLocation()

        print("🔄 Continuous location monitoring started for speed alert")
        print("📏 Distance filter: 5.0m (updated)")
        print("📍 Accuracy: Best available")
        print("🌙 Background support: \(currentAuth == .authorizedAlways ? "Enabled with background tasks" : "Limited")")
    }

    private func stopSpeedAlertLocationMonitoring() {
        print("🛑 Stopping speed alert location monitoring")

        isSpeedAlertActive = false

        // Only stop if we're not doing regular tracking
        if !isTracking {
            locationManager.stopUpdatingLocation()
            locationManager.stopMonitoringSignificantLocationChanges()
            locationManager.disallowDeferredLocationUpdates()

            // Disable background location updates
            if locationManager.authorizationStatus == .authorizedAlways {
                locationManager.allowsBackgroundLocationUpdates = false
            }

            // End background task if no tracking is active
            endBackgroundTask()

            print("✅ Speed alert location monitoring stopped")
        } else {
            print("ℹ️ Regular tracking is active, keeping location monitoring")
        }
    }

    @objc(turnOffAlert:rejecter:)
    func turnOffAlert(resolver: @escaping RCTPromiseResolveBlock, rejecter: @escaping RCTPromiseRejectBlock) {
        print("🛑 Turning off speed alert")
        stopSpeedAlertLocationMonitoring()
        resolver(true)
    }
}

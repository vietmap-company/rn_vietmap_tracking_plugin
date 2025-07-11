import Foundation
import CoreLocation
import React
import UIKit
import BackgroundTasks // Add for iOS 13+ background task scheduling
import AVFoundation // Add for speech synthesis

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

    // MARK: - Speech Synthesis for Speed Alerts
    private var speechSynthesizer: AVSpeechSynthesizer!
    private var lastSpeedAlertTime: TimeInterval = 0
    private let speedAlertCooldown: TimeInterval = 5.0 // 5 seconds cooldown between alerts

    // MARK: - Route and Alert Data Structures
    private var currentRouteData: [String: Any]?
    private var currentAlerts: [[Any]]?
    private var routeOffset: [Any]?

    // MARK: - Route Boundary Detection & API Management
    private var currentLinkIndex: Int?
    private var previousLinkSpeedLimit: Int? // Track previous link's speed limit
    private var routeBoundaryThreshold: Double = 50.0 // meters
    private var lastAPIRequestLocation: CLLocation?
    private var apiRequestInProgress: Bool = false
    private var routeAPIEndpoint: String?

    // Callback for route API updates
    private var onRouteUpdateCallback: ((Bool, [String: Any]?) -> Void)?

    override init() {
        super.init()
        locationManager = CLLocationManager()
        locationManager.delegate = self
        isTracking = false
        trackingStartTime = 0
        lastLocationUpdate = 0
        intervalMs = 5000
        backgroundMode = false

        // Initialize Speech Synthesizer
        speechSynthesizer = AVSpeechSynthesizer()
        speechSynthesizer.delegate = self

        // Configure audio session for background speech synthesis
        configureAudioSessionForSpeech()

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
            // onSpeedAlert removed - handled natively with speech
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

        // Reconfigure audio session for foreground
        configureAudioSessionForSpeech()

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

        // OPTION 1: Completely separate speed alert and tracking logic
        // Process location for speed alert if active (independent processing)
        if isSpeedAlertActive {
            processLocationForSpeedAlert(location: location, currentTime: currentTime)
        }

        // Process location for tracking if active (independent processing)
        if isTracking {
            processLocationForTracking(location: location, currentTime: currentTime)
        }
    }

    // MARK: - Speed Alert Location Processing
    private func processLocationForSpeedAlert(location: CLLocation, currentTime: TimeInterval) {
        // ✅ OPTION 1: Independent Speed Alert Processing
        // This function processes location updates ONLY for speed alert functionality
        // - Route boundary detection for speed limit monitoring
        // - API requests for route data
        // - Speed limit change detection and announcements
        // - NO tracking location events to React Native

        print("🚨 [SPEED ALERT] Location Update:")
        print("  📍 Coordinates: \(location.coordinate.latitude), \(location.coordinate.longitude)")
        print("  🚗 Speed: \(location.speed) m/s (\(String(format: "%.1f", location.speed * 3.6)) km/h)")
        print("  📏 Accuracy: \(location.horizontalAccuracy)m")
        print("  🧭 Bearing: \(location.course)°")
        print("  ⏰ Time: \(DateFormatter.localizedString(from: location.timestamp, dateStyle: .none, timeStyle: .medium))")
        print("  🌍 Altitude: \(location.altitude)m")

        // Process route boundary detection for speed alert mode
        print("🚨 [SPEED ALERT] Processing route boundary detection...")

        // Update current link index based on location
        updateCurrentLinkIndex(for: location)

        // Check if we need to request new route data from the server
        if shouldRequestNewRouteData(for: location) {
            requestRouteDataFromAPI(for: location)
        }

        // Note: Speed limit checking is now only done when new route data is received
        // This prevents continuous speech alerts on every location update
    }

    // MARK: - Tracking Location Processing
    private func processLocationForTracking(location: CLLocation, currentTime: TimeInterval) {
        // ✅ OPTION 1: Independent Tracking Processing
        // This function processes location updates ONLY for tracking functionality
        // - Sends location updates to React Native
        // - Handles throttling and forced update modes
        // - NO speed alert or route boundary detection

        // Handle location updates for React Native based on tracking mode (keep existing logic)
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

    // MARK: - Speech Synthesis for Speed Alerts

    // Configure audio session for background speech synthesis
    private func configureAudioSessionForSpeech() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playback,
                                       mode: .spokenAudio,
                                       options: [.duckOthers, .allowBluetoothA2DP, .interruptSpokenAudioAndMixWithOthers])
            try audioSession.setActive(true)
            print("✅ Audio session configured for background speech synthesis")
        } catch {
            print("❌ Failed to configure audio session for speech: \(error)")
        }
    }

    private func speakSpeedLimitAnnouncement(speedLimit: Int) {
        // Check cooldown to avoid too frequent announcements
        let currentTime = Date().timeIntervalSince1970
        if currentTime - lastSpeedAlertTime < speedAlertCooldown {
            return // Skip if within cooldown period
        }

        lastSpeedAlertTime = currentTime

        // Configure audio session for background speech (ensure it works in background)
        configureAudioSessionForSpeech()

        // Stop any current speech
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
        }

        // Create speed limit announcement message
        let message = "Tốc độ cho phép \(speedLimit) ki-lô-mét trên giờ"

        let utterance = AVSpeechUtterance(string: message)
        utterance.voice = AVSpeechSynthesisVoice(language: "vi-VN") ?? AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = 0.5 // Slower speech rate for clarity
        utterance.volume = 1.0
        utterance.pitchMultiplier = 1.0 // Normal pitch for informational announcements

        print("🔊 Speaking speed limit announcement: \(message)")
        print("🌙 Background mode: \(isInBackground ? "YES" : "NO")")

        // Start background task to ensure speech completes even in background
        var backgroundTaskId: UIBackgroundTaskIdentifier = .invalid
        backgroundTaskId = UIApplication.shared.beginBackgroundTask(withName: "SpeechAnnouncement") {
            print("⏰ Speech background task expiring")
            if backgroundTaskId != .invalid {
                UIApplication.shared.endBackgroundTask(backgroundTaskId)
                backgroundTaskId = .invalid
            }
        }

        // Store background task ID for cleanup in delegate
        speechSynthesizer.speak(utterance)

        // End background task after speech duration (estimated)
        let estimatedSpeechDuration = TimeInterval(message.count) * 0.1 + 2.0 // Rough estimate
        DispatchQueue.main.asyncAfter(deadline: .now() + estimatedSpeechDuration) {
            if backgroundTaskId != .invalid {
                print("✅ Ending speech background task")
                UIApplication.shared.endBackgroundTask(backgroundTaskId)
                backgroundTaskId = .invalid
            }
        }
    }

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

    // MARK: - Route and Alert Processing Methods

    private func processRouteLinks(links: [[Any]], alerts: [[Any]], offset: [Any]) -> [String: Any] {
        var processedLinks: [[String: Any]] = []
        var processedAlerts: [[String: Any]] = []

        // Process links
        for link in links {
            if link.count >= 5,
               let linkId = link[0] as? Int,
               let direction = link[1] as? Int,
               let coordinates = link[2] as? [Double],
               let distance = link[3] as? Int,
               let speedLimits = link[4] as? [[Int]] {

                let processedLink: [String: Any] = [
                    "id": linkId,
                    "direction": direction,
                    "startLat": coordinates.count > 1 ? coordinates[1] : 0.0,
                    "startLon": coordinates.count > 0 ? coordinates[0] : 0.0,
                    "endLat": coordinates.count > 3 ? coordinates[3] : 0.0,
                    "endLon": coordinates.count > 2 ? coordinates[2] : 0.0,
                    "distance": distance,
                    "speedLimits": speedLimits
                ]
                processedLinks.append(processedLink)
            }
        }

        // Process alerts
        for alert in alerts {
            if alert.count >= 4 {
                let processedAlert: [String: Any] = [
                    "type": alert[0],
                    "subtype": alert[1],
                    "speedLimit": alert[2] ?? NSNull(),
                    "distance": alert[3]
                ]
                processedAlerts.append(processedAlert)
            }
        }

        return [
            "links": processedLinks,
            "alerts": processedAlerts,
            "offset": offset,
            "totalLinks": processedLinks.count,
            "totalAlerts": processedAlerts.count
        ]
    }

    @objc(getCurrentRouteInfo:rejecter:)
    func getCurrentRouteInfo(resolver: @escaping RCTPromiseResolveBlock, rejecter: @escaping RCTPromiseRejectBlock) {
        if let routeData = currentRouteData {
            resolver(routeData)
        } else {
            rejecter("NO_ROUTE_DATA", "No route data available", nil)
        }
    }

    @objc(findNearestAlert:longitude:resolver:rejecter:)
    func findNearestAlert(latitude: Double, longitude: Double, resolver: @escaping RCTPromiseResolveBlock, rejecter: @escaping RCTPromiseRejectBlock) {
        guard let routeData = currentRouteData,
              let links = routeData["links"] as? [[String: Any]],
              let alerts = currentAlerts else {
            rejecter("NO_ROUTE_DATA", "No route data available", nil)
            return
        }

        // Find nearest link based on current location
        var nearestLinkIndex: Int?
        var minDistance = Double.infinity

        for (index, link) in links.enumerated() {
            if let startLat = link["startLat"] as? Double,
               let startLon = link["startLon"] as? Double,
               let endLat = link["endLat"] as? Double,
               let endLon = link["endLon"] as? Double {

                // Calculate distance to link segment
                let distance = distanceToLineSegment(
                    pointLat: latitude, pointLon: longitude,
                    startLat: startLat, startLon: startLon,
                    endLat: endLat, endLon: endLon
                )

                if distance < minDistance {
                    minDistance = distance
                    nearestLinkIndex = index
                }
            }
        }

        // Find alerts for the nearest link
        if let linkIndex = nearestLinkIndex {
            let relevantAlerts = findAlertsForLink(linkIndex: linkIndex, alerts: alerts)

            let result: [String: Any] = [
                "nearestLinkIndex": linkIndex,
                "distanceToLink": minDistance,
                "alerts": relevantAlerts
            ]

            resolver(result)
        } else {
            rejecter("NO_LINK_FOUND", "No nearby link found", nil)
        }
    }

    private func distanceToLineSegment(pointLat: Double, pointLon: Double,
                                     startLat: Double, startLon: Double,
                                     endLat: Double, endLon: Double) -> Double {

        // First, find the closest point on the line segment
        let A = pointLat - startLat
        let B = pointLon - startLon
        let C = endLat - startLat
        let D = endLon - startLon

        let dot = A * C + B * D
        let lenSq = C * C + D * D

        if lenSq == 0 {
            // Degenerate segment (start == end point)
            return calculateDistance(lat1: pointLat, lon1: pointLon, lat2: startLat, lon2: startLon)
        }

        let param = dot / lenSq
        let clampedParam = max(0, min(1, param))

        let closestLat = startLat + clampedParam * C
        let closestLon = startLon + clampedParam * D

        // Use Haversine formula for accurate distance calculation
        return calculateDistance(lat1: pointLat, lon1: pointLon, lat2: closestLat, lon2: closestLon)
    }

    private func findAlertsForLink(linkIndex: Int, alerts: [[Any]]) -> [[String: Any]] {
        var relevantAlerts: [[String: Any]] = []

        for alert in alerts {
            if alert.count >= 4,
               let distance = alert[3] as? Int {

                // Simple logic: alerts within reasonable distance of current link
                // In real implementation, you'd use proper route distance calculation
                let alertInfo: [String: Any] = [
                    "type": alert[0],
                    "subtype": alert[1],
                    "speedLimit": alert[2] ?? NSNull(),
                    "distance": distance,
                    "linkIndex": linkIndex
                ]
                relevantAlerts.append(alertInfo)
            }
        }

        return relevantAlerts
    }

    // REMOVED: checkSpeedViolation - replaced by native speed limit processing
    // REMOVED: findNearestAlertInternal - no longer needed
    // REMOVED: sendSpeedAlertEvent - replaced by direct speech synthesis

    // MARK: - Route Boundary Detection & API Management

    // REMOVED: Old updateCurrentLinkIndex implementation - replaced by enhanced map matching version below

    // Check speed limit changes only when currentLinkIndex changes
    private func checkSpeedLimitChanges() {
        guard let currentIndex = currentLinkIndex,
              let routeData = currentRouteData,
              let links = routeData["links"] as? [[String: Any]],
              currentIndex < links.count else {
            return
        }

        let currentLink = links[currentIndex]

        // Get speed limits for current link
        if let speedLimits = currentLink["speedLimits"] as? [[Int]] {
            for speedLimitData in speedLimits {
                if speedLimitData.count >= 2 {
                    let currentSpeedLimit = speedLimitData[1] // Speed limit value

                    // Only announce if speed limit is different from previous link
                    if currentSpeedLimit != previousLinkSpeedLimit && currentSpeedLimit > 0 {
                        print("🚨 SPEED LIMIT CHANGED: Previous: \(previousLinkSpeedLimit ?? 0) → Current: \(currentSpeedLimit) km/h")

                        // Announce the new speed limit (not violation, just information)
                        speakSpeedLimitAnnouncement(speedLimit: currentSpeedLimit)

                        // Update previous speed limit
                        previousLinkSpeedLimit = currentSpeedLimit
                    }

                    // Break after first speed limit (assuming one speed limit per link)
                    break
                }
            }
        } else {
            // No speed limit for current link
            if previousLinkSpeedLimit != nil {
                print("🚨 SPEED LIMIT REMOVED: Previous: \(previousLinkSpeedLimit ?? 0) → Current: No limit")
                previousLinkSpeedLimit = nil
                // Optionally announce that speed limit has been removed
                // speakSpeedLimitRemoved()
            }
        }
    }

    private func shouldRequestRouteData(location: CLLocation) -> Bool {
        // Don't request new data if there's an ongoing request
        if apiRequestInProgress {
            return false
        }

        // Request new data if the location is significantly different from the last request
        if let lastLocation = lastAPIRequestLocation {
            let distance = lastLocation.distance(from: location)
            return distance > routeBoundaryThreshold
        }

        return true
    }

    private func requestRouteData(location: CLLocation) {
        // Mark the request as in progress
        apiRequestInProgress = true

        // Update the last requested location
        lastAPIRequestLocation = location

        // Here you would perform the actual API request to fetch new route data
        // For demonstration, we'll just simulate a successful response after a delay

        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            // Simulate a successful response with dummy data
            let dummyResponse: [String: Any] = [
                "links": [],
                "alerts": [],
                "offset": [],
                "timestamp": Date().timeIntervalSince1970 * 1000
            ]

            // Update the route data with the new response
            self.currentRouteData = dummyResponse

            // Call the callback if set
            self.onRouteUpdateCallback?(true, dummyResponse)

            // Mark the request as not in progress
            self.apiRequestInProgress = false

            print("✅ Route data updated via API")
        }
    }

    // MARK: - API Management

    @objc(setRouteAPIEndpoint:resolver:rejecter:)
    func setRouteAPIEndpoint(endpoint: String, resolver: @escaping RCTPromiseResolveBlock, rejecter: @escaping RCTPromiseRejectBlock) {
        routeAPIEndpoint = endpoint
        print("🗺️ Route API endpoint set: \(endpoint)")
        resolver(true)
    }

    @objc(enableRouteBoundaryDetection:resolver:rejecter:)
    func enableRouteBoundaryDetection(threshold: Double, resolver: @escaping RCTPromiseResolveBlock, rejecter: @escaping RCTPromiseRejectBlock) {
        routeBoundaryThreshold = threshold
        print("🎯 Route boundary detection enabled with threshold: \(threshold)m")
        resolver(true)
    }

    private func isLocationWithinCurrentRoute(location: CLLocation) -> Bool {
        guard let routeData = currentRouteData,
              let links = routeData["links"] as? [[String: Any]] else {
            return false
        }

        // Enhanced route matching with map-matching algorithm
        let matchingResult = findBestRouteMatch(location: location, links: links)

        return matchingResult.isWithinRoute
    }

    private func shouldRequestNewRouteData(for location: CLLocation) -> Bool {
        // Don't request if API call is already in progress
        if apiRequestInProgress {
            return false
        }

        // Request if no route data exists
        guard currentRouteData != nil else {
            return true
        }

        // Request if location is outside current route
        if !isLocationWithinCurrentRoute(location: location) {
            print("📍 Location outside current route - requesting new route data")
            return true
        }

        // Request if significantly moved from last API request location
        if let lastAPILocation = lastAPIRequestLocation {
            let distance = location.distance(from: lastAPILocation)
            if distance > 1000 { // 1km threshold
                print("📍 Moved 1km from last API request - requesting updated route data")
                return true
            }
        }

        return false
    }

    private func requestRouteDataFromAPI(for location: CLLocation) {
        guard !apiRequestInProgress else {
            print("❌ API request already in progress")
            return
        }

        apiRequestInProgress = true
        lastAPIRequestLocation = location

        print("🌐 Requesting route data for location: \(location.coordinate.latitude), \(location.coordinate.longitude)")

        // Simulate API call with mock data - replace with real API call when endpoint is available
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.apiRequestInProgress = false

            // Mock response data based on your provided sample
            let mockRouteData: [String: Any] = [
                "links": [],
                "alerts": [],
                "offset": []
            ]

            print("✅ Mock route data received - Processing...")
            self?.handleNewRouteData(mockRouteData, for: location)
        }
    }

    private func handleNewRouteData(_ data: [String: Any], for location: CLLocation) {
        print("✅ Received new route data from API")

        // Process the new route data
        if let links = data["links"] as? [[Any]],
           let alerts = data["alerts"] as? [[Any]],
           let offset = data["offset"] as? [Any] {

            let processedData = processRouteLinks(links: links, alerts: alerts, offset: offset)

            // Store new route data
            currentRouteData = processedData
            currentAlerts = alerts
            routeOffset = offset

            // Reset previous speed limit when new route data is received
            previousLinkSpeedLimit = nil

            // Set initial currentLinkIndex to first link when new route data is received from API
            if !links.isEmpty {
                currentLinkIndex = 0
                print("🎯 Initial currentLinkIndex set to: 0 (first link from API)")
            } else {
                currentLinkIndex = nil
                print("⚠️ No links available from API, currentLinkIndex set to nil")
            }

            // Find current link index based on location
            updateCurrentLinkIndex(for: location)

            // Read current speed limit immediately when new route data is received (if currentLinkIndex exists)
            if isSpeedAlertActive && currentLinkIndex != nil {
                print("🔊 Reading current speed limit immediately after receiving new route data")
                readCurrentSpeedLimitImmediately()
            }

            print("📊 Route data updated - Links: \(links.count), Alerts: \(alerts.count)")

            onRouteUpdateCallback?(true, processedData)
        }
    }

    // Read current speed limit immediately when new route data is received
    private func readCurrentSpeedLimitImmediately() {
        guard let currentIndex = currentLinkIndex,
              let routeData = currentRouteData,
              let links = routeData["links"] as? [[String: Any]],
              currentIndex < links.count else {
            print("⚠️ Cannot read speed limit - no valid currentLinkIndex")
            return
        }

        let currentLink = links[currentIndex]

        // Get speed limits for current link
        if let speedLimits = currentLink["speedLimits"] as? [[Int]] {
            for speedLimitData in speedLimits {
                if speedLimitData.count >= 2 {
                    let currentSpeedLimit = speedLimitData[1] // Speed limit value

                    if currentSpeedLimit > 0 {
                        print("🔊 IMMEDIATE SPEED LIMIT READ: \(currentSpeedLimit) km/h (new route data)")

                        // Always announce speed limit when new route data is received
                        speakSpeedLimitAnnouncement(speedLimit: currentSpeedLimit)

                        // Update previous speed limit for future comparisons
                        previousLinkSpeedLimit = currentSpeedLimit
                    }

                    // Break after first speed limit (assuming one speed limit per link)
                    break
                }
            }
        } else {
            print("⚠️ No speed limit found for current link")
        }
    }

    private func updateCurrentLinkIndex(for location: CLLocation) {
        guard let routeData = currentRouteData,
              let links = routeData["links"] as? [[String: Any]] else {
            print("🔍 [DEBUG] updateCurrentLinkIndex - No route data available")
            return
        }

        print("🔍 [DEBUG] updateCurrentLinkIndex - Starting update for location: (\(location.coordinate.latitude), \(location.coordinate.longitude))")

        let matchingResult = findBestRouteMatch(location: location, links: links)

        // Lower confidence threshold for initial matching
        let confidenceThreshold = currentLinkIndex == nil ? 0.3 : 0.5 // Lowered threshold if no current link

        if let newLinkIndex = matchingResult.linkIndex,
           matchingResult.confidence > confidenceThreshold { // Lowered confidence requirement

            if newLinkIndex != currentLinkIndex {
                print("🎯 Link index updated: \(currentLinkIndex ?? -1) → \(newLinkIndex)")
                print("📍 Snap distance: \(String(format: "%.1f", matchingResult.distanceToRoute))m")
                print("📊 Progress on link: \(String(format: "%.1f", matchingResult.progressOnLink * 100))%")
                print("🎯 Confidence: \(String(format: "%.1f", matchingResult.confidence * 100))%")

                currentLinkIndex = newLinkIndex

                // Store snapped location for better tracking
                if let snappedLocation = matchingResult.snappedLocation {
                    print("🧭 GPS: (\(location.coordinate.latitude), \(location.coordinate.longitude))")
                    print("📍 Snapped: (\(snappedLocation.latitude), \(snappedLocation.longitude))")
                }

                // Check speed limits when link changes (only for speed alert mode)
                if isSpeedAlertActive {
                    checkSpeedLimitChanges()
                }
            } else {
                print("🔍 [DEBUG] Same link index maintained: \(newLinkIndex)")
            }
        } else {
            print("🔍 [DEBUG] No confident match found:")
            print("  - Link index: \(matchingResult.linkIndex ?? -1)")
            print("  - Confidence: \(String(format: "%.1f", matchingResult.confidence * 100))% (threshold: \(String(format: "%.1f", confidenceThreshold * 100))%)")
            print("  - Distance: \(String(format: "%.1f", matchingResult.distanceToRoute))m")
        }
    }

    // MARK: - Enhanced Map Matching for Route Following

    private struct RouteMatchingResult {
        let isWithinRoute: Bool
        let snappedLocation: CLLocationCoordinate2D?
        let linkIndex: Int?
        let distanceToRoute: Double
        let progressOnLink: Double // 0.0 to 1.0
        let confidence: Double     // 0.0 to 1.0
    }

    private func findBestRouteMatch(location: CLLocation, links: [[String: Any]]) -> RouteMatchingResult {
        // Handle empty links gracefully
        if links.isEmpty {
            print("🔍 [DEBUG] findBestRouteMatch - No links available")
            return RouteMatchingResult(
                isWithinRoute: false,
                snappedLocation: nil,
                linkIndex: nil,
                distanceToRoute: Double.infinity,
                progressOnLink: 0.0,
                confidence: 0.0
            )
        }

        var bestMatch: RouteMatchingResult?
        var bestScore = Double.infinity

        print("🔍 [DEBUG] findBestRouteMatch - Starting search for location: (\(location.coordinate.latitude), \(location.coordinate.longitude))")
        print("🔍 [DEBUG] Current link index: \(currentLinkIndex ?? -1), Total links: \(links.count)")

        // Check current link first (higher priority) if exists
        if let currentIndex = currentLinkIndex,
           currentIndex < links.count {
            let currentLinkMatch = evaluateLinkMatch(location: location, link: links[currentIndex], linkIndex: currentIndex, isCurrentLink: true)

            print("🔍 [DEBUG] Current link evaluation:")
            print("  - Distance: \(String(format: "%.1f", currentLinkMatch.distanceToRoute))m")
            print("  - Confidence: \(String(format: "%.1f", currentLinkMatch.confidence * 100))%")

            if currentLinkMatch.distanceToRoute <= routeBoundaryThreshold * 1.5 { // More lenient for current link
                bestMatch = currentLinkMatch
                bestScore = currentLinkMatch.distanceToRoute
                print("🔍 [DEBUG] Current link accepted as candidate")
            }
        }

        // Determine search strategy
        let searchAll = currentLinkIndex == nil || bestMatch == nil
        let searchRange = searchAll ? links.count : min(5, links.count) // Search more links if no current link

        let startIndex: Int
        let endIndex: Int

        if searchAll {
            // Search all links if no current link or no good match
            startIndex = 0
            endIndex = links.count - 1
            print("🔍 [DEBUG] Searching ALL links (no current link or poor match)")
        } else {
            // Search adjacent links only
            startIndex = max(0, (currentLinkIndex ?? 0) - searchRange)
            endIndex = min(links.count - 1, (currentLinkIndex ?? 0) + searchRange)
            print("🔍 [DEBUG] Searching adjacent links: \(startIndex) to \(endIndex)")
        }

        // Ensure valid range before using it
        guard startIndex <= endIndex && startIndex < links.count && endIndex >= 0 else {
            print("🔍 [DEBUG] Invalid range: startIndex=\(startIndex), endIndex=\(endIndex), links.count=\(links.count)")
            if bestMatch != nil {
                return bestMatch!
            } else {
                return RouteMatchingResult(
                    isWithinRoute: false,
                    snappedLocation: nil,
                    linkIndex: nil,
                    distanceToRoute: Double.infinity,
                    progressOnLink: 0.0,
                    confidence: 0.0
                )
            }
        }

        for i in startIndex...endIndex {
            if i == currentLinkIndex { continue } // Already checked

            let linkMatch = evaluateLinkMatch(location: location, link: links[i], linkIndex: i, isCurrentLink: false)

            print("🔍 [DEBUG] Link \(i) evaluation:")
            print("  - Distance: \(String(format: "%.1f", linkMatch.distanceToRoute))m")
            print("  - Confidence: \(String(format: "%.1f", linkMatch.confidence * 100))%")

            // Scoring: distance + direction consistency + sequence penalty
            let sequencePenalty = searchAll ? 0.0 : Double(abs(i - (currentLinkIndex ?? i))) * 5.0 // Reduced penalty
            let totalScore = linkMatch.distanceToRoute + sequencePenalty

            let isAcceptable = linkMatch.distanceToRoute <= routeBoundaryThreshold * 2.0 // More lenient threshold

            if totalScore < bestScore && isAcceptable {
                bestMatch = linkMatch
                bestScore = totalScore
                print("🔍 [DEBUG] Link \(i) accepted as new best candidate (score: \(String(format: "%.1f", totalScore)))")
            }
        }

        // If still no good match found, return default
        if bestMatch == nil {
            print("🔍 [DEBUG] No match found - returning nil result")
            return RouteMatchingResult(
                isWithinRoute: false,
                snappedLocation: nil,
                linkIndex: nil,
                distanceToRoute: Double.infinity,
                progressOnLink: 0.0,
                confidence: 0.0
            )
        }

        print("🔍 [DEBUG] Best match found:")
        print("  - Link index: \(bestMatch!.linkIndex ?? -1)")
        print("  - Distance: \(String(format: "%.1f", bestMatch!.distanceToRoute))m")
        print("  - Confidence: \(String(format: "%.1f", bestMatch!.confidence * 100))%")

        return bestMatch!
    }

    private func evaluateLinkMatch(location: CLLocation, link: [String: Any], linkIndex: Int, isCurrentLink: Bool) -> RouteMatchingResult {
        guard let startLat = link["startLat"] as? Double,
              let startLon = link["startLon"] as? Double,
              let endLat = link["endLat"] as? Double,
              let endLon = link["endLon"] as? Double else {
            print("🔍 [DEBUG] evaluateLinkMatch - Invalid link coordinates for link \(linkIndex)")
            return RouteMatchingResult(isWithinRoute: false, snappedLocation: nil, linkIndex: nil, distanceToRoute: Double.infinity, progressOnLink: 0.0, confidence: 0.0)
        }

        let currentLat = location.coordinate.latitude
        let currentLon = location.coordinate.longitude

        print("🔍 [DEBUG] evaluateLinkMatch - Link \(linkIndex):")
        print("  - GPS: (\(currentLat), \(currentLon))")
        print("  - Link Start: (\(startLat), \(startLon))")
        print("  - Link End: (\(endLat), \(endLon))")

        // Calculate closest point on link segment (snap-to-route)
        let snappedPoint = snapToLineSegment(
            pointLat: currentLat, pointLon: currentLon,
            startLat: startLat, startLon: startLon,
            endLat: endLat, endLon: endLon
        )

        print("  - Snapped point: (\(snappedPoint.latitude), \(snappedPoint.longitude))")

        // Calculate distance from GPS point to snapped point
        let distanceToRoute = calculateDistance(
            lat1: currentLat, lon1: currentLon,
            lat2: snappedPoint.latitude, lon2: snappedPoint.longitude
        )

        print("  - Distance to route: \(String(format: "%.1f", distanceToRoute))m")

        // Calculate progress along the link (0.0 to 1.0)
        let progressOnLink = calculateProgressOnLink(
            snappedLat: snappedPoint.latitude, snappedLon: snappedPoint.longitude,
            startLat: startLat, startLon: startLon,
            endLat: endLat, endLon: endLon
        )

        print("  - Progress on link: \(String(format: "%.2f", progressOnLink))")

        // Calculate confidence based on multiple factors
        let confidence = calculateMatchingConfidence(
            distanceToRoute: distanceToRoute,
            progressOnLink: progressOnLink,
            isCurrentLink: isCurrentLink,
            location: location
        )

        // Enhanced threshold based on movement direction and speed
        let dynamicThreshold = calculateDynamicThreshold(location: location, isCurrentLink: isCurrentLink)
        let isWithinRoute = distanceToRoute <= dynamicThreshold

        print("  - Dynamic threshold: \(String(format: "%.1f", dynamicThreshold))m")
        print("  - Is within route: \(isWithinRoute)")
        print("  - Final confidence: \(String(format: "%.1f", confidence * 100))%")

        return RouteMatchingResult(
            isWithinRoute: isWithinRoute,
            snappedLocation: snappedPoint,
            linkIndex: linkIndex,
            distanceToRoute: distanceToRoute,
            progressOnLink: progressOnLink,
            confidence: confidence
        )
    }

    private func snapToLineSegment(pointLat: Double, pointLon: Double,
                                  startLat: Double, startLon: Double,
                                  endLat: Double, endLon: Double) -> CLLocationCoordinate2D {

        // Vector from start to end of segment
        let segmentLat = endLat - startLat
        let segmentLon = endLon - startLon

        // Vector from start to point
        let pointLat_rel = pointLat - startLat
        let pointLon_rel = pointLon - startLon

        // Calculate parameter t for closest point on line segment
        let segmentLengthSquared = segmentLat * segmentLat + segmentLon * segmentLon

        if segmentLengthSquared == 0 {
            // Degenerate segment (start == end)
            return CLLocationCoordinate2D(latitude: startLat, longitude: startLon)
        }

        // Project point onto line segment
        let t = (pointLat_rel * segmentLat + pointLon_rel * segmentLon) / segmentLengthSquared

        // Clamp t to [0, 1] to stay within segment
        let clampedT = max(0.0, min(1.0, t))

        // Calculate snapped coordinates
        let snappedLat = startLat + clampedT * segmentLat
        let snappedLon = startLon + clampedT * segmentLon

        return CLLocationCoordinate2D(latitude: snappedLat, longitude: snappedLon)
    }

    private func calculateProgressOnLink(snappedLat: Double, snappedLon: Double,
                                       startLat: Double, startLon: Double,
                                       endLat: Double, endLon: Double) -> Double {

        let totalDistance = calculateDistance(lat1: startLat, lon1: startLon, lat2: endLat, lon2: endLon)

        if totalDistance == 0 { return 0.0 }

        let progressDistance = calculateDistance(lat1: startLat, lon1: startLon, lat2: snappedLat, lon2: snappedLon)

        return min(1.0, progressDistance / totalDistance)
    }

    private func calculateMatchingConfidence(distanceToRoute: Double, progressOnLink: Double,
                                           isCurrentLink: Bool, location: CLLocation) -> Double {
        print("🔍 [DEBUG] calculateMatchingConfidence:")
        print("  - Distance to route: \(String(format: "%.1f", distanceToRoute))m")
        print("  - Is current link: \(isCurrentLink)")
        print("  - GPS accuracy: \(String(format: "%.1f", location.horizontalAccuracy))m")

        var confidence = 1.0

        // Distance factor (closer = higher confidence) - more generous scoring
        let maxDistance = routeBoundaryThreshold * 3.0 // Allow for wider matching
        let distanceFactor = max(0.1, 1.0 - (distanceToRoute / maxDistance)) // Minimum 10% confidence
        confidence *= distanceFactor
        print("  - Distance factor: \(String(format: "%.2f", distanceFactor))")

        // GPS accuracy factor - more lenient
        let accuracyFactor: Double
        if location.horizontalAccuracy < 10 {
            accuracyFactor = 1.0
        } else if location.horizontalAccuracy < 50 {
            accuracyFactor = max(0.6, 1.0 - (location.horizontalAccuracy - 10) / 40)
        } else {
            accuracyFactor = 0.5 // Still give some confidence for poor GPS
        }
        confidence *= accuracyFactor
        print("  - Accuracy factor: \(String(format: "%.2f", accuracyFactor))")

        // Current link bonus
        if isCurrentLink {
            confidence *= 1.3 // Increased bonus for current link
            print("  - Current link bonus applied")
        }

        // Speed consistency (if moving, prefer links in direction of movement)
        if location.speed > 1.0 && location.course >= 0 { // Moving with valid course
            confidence *= 1.15
            print("  - Movement bonus applied")
        }

        // Ensure minimum confidence for close matches
        if distanceToRoute <= routeBoundaryThreshold {
            confidence = max(confidence, 0.4) // Minimum 40% confidence for close matches
        }

        let finalConfidence = max(0.0, min(1.0, confidence))
        print("  - Final confidence: \(String(format: "%.2f", finalConfidence))")

        return finalConfidence
    }

    private func calculateDynamicThreshold(location: CLLocation, isCurrentLink: Bool) -> Double {
        var threshold = routeBoundaryThreshold

        // Increase threshold based on GPS accuracy
        if location.horizontalAccuracy > 10 {
            threshold += location.horizontalAccuracy * 0.5
        }

        // Increase threshold for current link (more lenient)
        if isCurrentLink {
            threshold *= 1.5
        }

        // Increase threshold based on speed (faster = more GPS drift)
        if location.speed > 10 { // > 36 km/h
            let speedFactor = 1.0 + (location.speed - 10) * 0.1
            threshold *= speedFactor
        }

        // Cap maximum threshold
        return min(threshold, 150.0) // Max 150m threshold
    }

    private func calculateDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        // Haversine formula for more accurate distance calculation
        let R = 6371000.0 // Earth radius in meters

        let lat1Rad = lat1 * .pi / 180
        let lat2Rad = lat2 * .pi / 180
        let deltaLatRad = (lat2 - lat1) * .pi / 180
        let deltaLonRad = (lon2 - lon1) * .pi / 180

        let a = sin(deltaLatRad/2) * sin(deltaLatRad/2) +
                cos(lat1Rad) * cos(lat2Rad) *
                sin(deltaLonRad/2) * sin(deltaLonRad/2)

        let c = 2 * atan2(sqrt(a), sqrt(1-a))

        return R * c
    }
}

// MARK: - AVSpeechSynthesizerDelegate

extension RnVietmapTrackingPlugin: AVSpeechSynthesizerDelegate {

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("🔊 Speech started: \(utterance.speechString)")
        print("🌙 Background mode: \(isInBackground ? "YES" : "NO")")

        // Ensure audio session remains active during speech
        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("❌ Failed to keep audio session active: \(error)")
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        print("✅ Speech finished: \(utterance.speechString)")

        // Keep audio session active for potential future announcements
        // Don't deactivate immediately to avoid audio interruptions
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        print("❌ Speech cancelled: \(utterance.speechString)")
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, willSpeakRangeOfSpeechString characterRange: NSRange, utterance: AVSpeechUtterance) {
        // Optional: Could be used for visual feedback or word-by-word highlighting
    }
}

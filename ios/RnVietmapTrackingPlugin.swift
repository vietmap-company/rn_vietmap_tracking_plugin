import Foundation
import CoreLocation
import React
import UIKit
import UserNotifications
import VietmapTrackingSDK

#if RCT_NEW_ARCH_ENABLED
import RnVietmapTrackingPluginSpec
#endif

@objc(RnVietmapTrackingPlugin)
class RnVietmapTrackingPlugin: RCTEventEmitter {

    // MARK: - SDK

    private var trackingManager: VietmapTrackingManager

    // MARK: - Bridge state

    private var isInitialized: Bool = false
    private var currentTrackingConfig: [String: Any]?
    private var currentAlertConfig: [String: Any]?

    /// Policy applied when the SDK detects a fake fix: "skip" | "warn" |
    /// "stopTracking" | "logToServer". Only consulted while allowMockLocation is
    /// false. "skip" — detect and report, change nothing — is the SDK's default.
    private var fakeGPSPolicy: String = "skip"

    /// Smart battery state. Neither SDK exposes this, so the module holds it.
    private var smartBatteryEnabled: Bool = false
    private var smartBatteryPreset: String = "general"

    /// Never log a full API key; the prefix is enough to tell keys apart.
    private static func maskKey(_ key: String) -> String {
        guard key.count > 10 else { return "\(key.count) chars" }
        return "\(key.prefix(8))...(\(key.count) chars)"
    }

    /// Same fallback the Flutter plugin uses when no baseURL is supplied.
    private static let defaultBaseURL = "https://live.fleetwork.vn/api/v1"

    /// Intervals each smart battery preset maps to, in milliseconds. These must
    /// stay in step with SMART_BATTERY_INTERVALS_MS in src/constants.ts.
    private static let smartBatteryIntervalsMs: [String: Int] = [
        "navigation": 5000,
        "general": 30000,
        "batterySaver": 300000
    ]

    // MARK: - Diagnostics

    private var hasJSListeners: Bool = false
    private var locationEventCount: Int = 0

    /// Sequence number for a lifecycle transition, assigned by the native
    /// observer and carried through every later line for that transition.
    /// Without it two quick background/foreground cycles interleave unreadably.
    private var lifecycleSeq: Int = 0

    /// Monotonic milliseconds. Wall clock is unusable here: it jumps, and the
    /// whole point is comparing hops a few milliseconds apart.
    private static func uptimeMs() -> Double {
        return ProcessInfo.processInfo.systemUptime * 1000
    }

    /// Diagnostics for the event pipeline. Every hop between the SDK and JS
    /// prints, so a missing event can be traced to the hop that dropped it
    /// instead of guessing. Prefixed [VMBridge] to grep for.
    private func trace(_ message: String) {
        #if DEBUG
        NSLog("[VMBridge] %@", message)
        #endif
    }

    /// Lifecycle timeline, tagged separately so one grep gets the whole
    /// transition across native and JS. See IMPLEMENTATION_PLAN.md step 0.
    private func traceLife(_ message: String) {
        #if DEBUG
        NSLog("[VMLife] %@", message)
        #endif
    }

    // MARK: - Lifecycle

    override init() {
        trackingManager = VietmapTrackingManager.shared
        super.init()
        setupSDKCallbacks()
        setupLifecycleObservers()
    }

    deinit {
        // trackingManager is a shared singleton, so this nils out whatever
        // closures are installed - including a newer instance's, if React
        // Native ever creates a second module instance. Logged so that case
        // is visible rather than silent.
        NSLog("[VMBridge] deinit - clearing SDK callbacks on the shared manager")
        trackingManager.onLocationUpdate = nil
        trackingManager.onTrackingStatusChanged = nil
        trackingManager.onError = nil
        trackingManager.onPermissionChanged = nil
        trackingManager.onFakeGPSDetected = nil
        trackingManager.onTrackingInterrupted = nil
        NotificationCenter.default.removeObserver(self)
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
            "onFakeGPSDetected",
            "onTrackingInterrupted"
        ]
    }

    override static func moduleName() -> String! {
        return "RnVietmapTrackingPlugin"
    }

    @objc
    static func getName() -> String {
        return "RnVietmapTrackingPlugin"
    }

    @objc
    override func constantsToExport() -> [AnyHashable: Any]! {
        return [:]
    }

    // MARK: - App lifecycle, observed natively
    //
    // React Native's AppState is itself an NSNotificationCenter observer on
    // these same notifications (RCTAppState.mm) that then sends an event across
    // the bridge. Routing app state through it would cost three hops — native,
    // bridge, JS, bridge, here — and put the JS thread in the middle of the one
    // signal that matters most as the app is being suspended. Observing here is
    // one hop and needs no JS at all.
    //
    // Do not also wire AppState to onAppBackground from JS: every transition
    // would then arrive twice.

    private func setupLifecycleObservers() {
        let center = NotificationCenter.default
        center.addObserver(
            self,
            selector: #selector(appDidEnterBackground),
            name: UIApplication.didEnterBackgroundNotification,
            object: nil
        )
        center.addObserver(
            self,
            selector: #selector(appWillEnterForeground),
            name: UIApplication.willEnterForegroundNotification,
            object: nil
        )

        // Seed the state rather than waiting for the next transition. A module
        // created while the app is already backgrounded — a background launch,
        // a restart — would otherwise leave the SDK believing it is in the
        // foreground until the user next brings the app up.
        // requiresMainQueueSetup is true, so reading UIApplication here is safe.
        let state = UIApplication.shared.applicationState
        traceLife("init | applicationState=\(Self.describe(state)) t=\(Self.uptimeMs())")
        if state == .background {
            traceLife("init | seeding background state into the SDK")
            trackingManager.onAppBackground()
        }
    }

    private static func describe(_ state: UIApplication.State) -> String {
        switch state {
        case .active: return "active"
        case .inactive: return "inactive"
        case .background: return "background"
        @unknown default: return "unknown"
        }
    }

    @objc private func appDidEnterBackground() {
        lifecycleSeq += 1
        traceLife("#\(lifecycleSeq) native-observer didEnterBackground t=\(Self.uptimeMs())")
        trackingManager.onAppBackground()
        traceLife("#\(lifecycleSeq) sdk.onAppBackground returned t=\(Self.uptimeMs())")
    }

    @objc private func appWillEnterForeground() {
        lifecycleSeq += 1
        let seq = lifecycleSeq
        traceLife("#\(seq) native-observer willEnterForeground t=\(Self.uptimeMs())")
        trackingManager.onAppForeground()
        traceLife("#\(seq) sdk.onAppForeground returned t=\(Self.uptimeMs())")

        // Post-foreground drain. The SDK restarts its own network monitor inside
        // onAppForeground, so this waits for that to settle before deciding
        // whether anything is still stuck. The delay is Flutter's; step 0.7
        // measures the drain curve and may move it.
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
            guard let self = self else { return }
            let pending = self.trackingManager.getCachedLocationsCount()
            let online = self.trackingManager.isNetworkConnected()
            self.traceLife("#\(seq) post-foreground | pending=\(pending) sdkNetwork=\(online) t=\(Self.uptimeMs())")
            guard online, pending > 0 else { return }
            self.traceLife("#\(seq) post-foreground | draining \(pending) pending")
            self.trackingManager.uploadCachedLocationsManually { success, message in
                self.traceLife("#\(seq) post-foreground drain | success=\(success) message=\(message ?? "nil")")
            }
        }
    }

    // MARK: - SDK callbacks

    /// Map the SDK's raw location dictionary onto the LocationData shape
    /// declared in src/types.ts, so JS sees the same keys on both platforms.
    ///
    /// The SDK reports `lat` / `lng` / `heading`, while the TypeScript contract
    /// and the example app use `latitude` / `longitude` / `bearing`. Reading
    /// `location.bearing` on iOS therefore returned undefined.
    ///
    /// Both spellings are accepted on input, mirroring the Flutter plugin's
    /// LocationData.fromJson, so this keeps working if the SDK renames a key.
    /// Unknown extra keys pass through untouched.
    private func normalizeLocation(_ raw: NSDictionary) -> [String: Any] {
        var out = (raw as? [String: Any]) ?? [:]

        func number(_ keys: [String]) -> Double? {
            for key in keys {
                if let value = raw[key] as? NSNumber { return value.doubleValue }
                if let text = raw[key] as? String, let value = Double(text) { return value }
            }
            return nil
        }

        out["latitude"] = number(["latitude", "lat"]) ?? 0
        out["longitude"] = number(["longitude", "lng", "lon"]) ?? 0
        out["altitude"] = number(["altitude"]) ?? 0
        out["accuracy"] = number(["accuracy"]) ?? 0
        out["speed"] = number(["speed"]) ?? 0
        out["bearing"] = number(["bearing", "heading"]) ?? 0

        // The SDK may report seconds or milliseconds; JS expects milliseconds.
        // The threshold is the epoch in milliseconds, so anything smaller is
        // seconds. Same rule as the Flutter plugin's _readTimestampMillis.
        if let timestamp = number(["timestamp", "time"]) {
            out["timestamp"] = timestamp < 1_000_000_000_000 ? timestamp * 1000 : timestamp
        } else {
            out["timestamp"] = Date().timeIntervalSince1970 * 1000
        }

        return out
    }

    /// RCTEventEmitter drops sendEvent when no JS listener is attached, so the
    /// count matters when an event seems to vanish.
    override func startObserving() {
        hasJSListeners = true
        trace("startObserving - JS attached its listeners")
    }

    override func stopObserving() {
        hasJSListeners = false
        trace("stopObserving - JS detached its listeners")
    }

    private func setupSDKCallbacks() {
        trace("setupSDKCallbacks - installing closures on VietmapTrackingManager.shared")

        trackingManager.onLocationUpdate = { [weak self] locationDict in
            guard let self = self else { return }
            let payload = self.normalizeLocation(locationDict)
            self.locationEventCount += 1
            self.trace(
                "onLocationUpdate #\(self.locationEventCount) from SDK | raw=\(locationDict) "
                + "| normalized lat=\(payload["latitude"] ?? "?") lng=\(payload["longitude"] ?? "?") "
                + "| hasJSListeners=\(self.hasJSListeners)"
            )
            DispatchQueue.main.async {
                self.sendEvent(withName: "onLocationUpdate", body: payload)
            }
        }

        trackingManager.onTrackingStatusChanged = { [weak self] statusDict in
            DispatchQueue.main.async {
                self?.sendEvent(withName: "onTrackingStatusChanged", body: statusDict as? [String: Any])
            }
        }

        trackingManager.onError = { [weak self] error in
            DispatchQueue.main.async {
                self?.sendEvent(withName: "onLocationError", body: [
                    "message": error,
                    "timestamp": Date().timeIntervalSince1970 * 1000
                ])
            }
        }

        trackingManager.onPermissionChanged = { [weak self] status in
            DispatchQueue.main.async {
                self?.sendEvent(withName: "onPermissionChanged", body: [
                    "status": status,
                    "timestamp": Date().timeIntervalSince1970 * 1000
                ])
            }
        }

        trackingManager.onFakeGPSDetected = { [weak self] payload in
            guard let self = self else { return }
            var dict = (payload as? [String: Any]) ?? [:]

            // The SDK reports this one in SECONDS (location.timestamp
            // .timeIntervalSince1970), while every other timestamp this plugin
            // hands JS is milliseconds — normalizeLocation() already converts
            // LocationData the same way. Passing it through unconverted made
            // `new Date(event.timestamp)` render 1970 on iOS while Android, which
            // sends milliseconds, happened to be right.
            //
            // The Flutter plugin resolves this the other way, normalising both
            // platforms to seconds. Either is fine as long as one plugin is
            // consistent with itself; milliseconds is what the rest of this API
            // uses, so that is the side to be consistent with.
            if let seconds = (dict["timestamp"] as? NSNumber)?.doubleValue {
                dict["timestamp"] = seconds < 1_000_000_000_000 ? seconds * 1000 : seconds
            } else {
                dict["timestamp"] = Date().timeIntervalSince1970 * 1000
            }

            self.trace("onFakeGPSDetected from SDK | \(dict)")
            DispatchQueue.main.async {
                self.sendEvent(withName: "onFakeGPSDetected", body: dict)
            }
        }

        // Apps must NOT stop and restart tracking in response to this. The SDK
        // raises it from GPS silence, so a restart only costs a fresh first fix
        // and can loop.
        trackingManager.onTrackingInterrupted = { [weak self] payload in
            guard let self = self else { return }
            var dict = (payload as? [String: Any]) ?? [:]

            // Drop the SDK's `timestamp`. It is iOS-only — the Android callback
            // signature has no such field — and it is in SECONDS, while every
            // timestamp this plugin hands JS is milliseconds. Forwarding it gave
            // the event a field on one platform and not the other, in a unit
            // that matched nothing else.
            //
            // Removed rather than converted: nothing reads it,
            // `secondsSinceLastFix` already carries the timing, and the Flutter
            // plugin's TrackingInterruptedEvent has the same four fields without
            // it. Keeping the two plugins the same shape is worth more than a
            // field nobody asked for.
            dict.removeValue(forKey: "timestamp")

            self.trace("onTrackingInterrupted from SDK | \(dict)")
            DispatchQueue.main.async {
                self.sendEvent(withName: "onTrackingInterrupted", body: dict)
            }
        }
    }

    // MARK: - Helpers

    /// Resolve `false` with a trace rather than rejecting, for calls that make
    /// no sense before configure() but should not crash a screen either.
    private func guardInitialized(_ rejecter: RCTPromiseRejectBlock) -> Bool {
        if !isInitialized {
            rejecter("SDK_NOT_INITIALIZED", "VietmapTrackingSDK not initialized", nil)
            return false
        }
        return true
    }

    // MARK: - Configuration

    @objc(getPlatformVersion:rejecter:)
    func getPlatformVersion(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve("iOS \(UIDevice.current.systemVersion)")
    }

    @objc(configure:baseURL:resolver:rejecter:)
    func configure(
        _ apiKey: String,
        baseURL: String?,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        // Pass apiKey and baseURL together.
        //
        // The single-argument variants must not be used in sequence here:
        // configure(apiKey:) ends with fetchAppConfig(force: true) while baseURL
        // is still the SDK's hardcoded production default, so it pulls that
        // host's SSL pins. configure(baseURL:) then fetches again for the real
        // host, but if that second fetch does not complete the production pins
        // stay installed and every upload is rejected with
        // NSURLErrorCancelled (-999) at the pinning check.
        //
        // configure(apiKey:baseURL:autoUpload:) assigns baseURL first and
        // fetches once. It also applies autoUpload, so no separate call.
        let trimmedBaseURL = baseURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        trace("-> SDK configure | apiKey=\(Self.maskKey(apiKey)) baseURL=\(trimmedBaseURL.isEmpty ? "(SDK default)" : trimmedBaseURL)")
        if trimmedBaseURL.isEmpty {
            trackingManager.configure(apiKey: apiKey)
            trackingManager.setAutoUpload(enabled: true)
        } else {
            trackingManager.configure(apiKey: apiKey, baseURL: trimmedBaseURL, autoUpload: true)
        }

        isInitialized = true
        resolver(true)
    }

    /// Validate the API key server-side, then configure. Mirrors the Flutter
    /// plugin's initializeTracking. isInitialized is only set once validation
    /// succeeds, so a bad key cannot leave the module half-configured.
    @objc(initializeTracking:baseURL:authMode:autoUpload:resolver:rejecter:)
    func initializeTracking(
        _ apiKey: String,
        baseURL: String?,
        authMode: String?,
        autoUpload: Bool,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        guard !apiKey.isEmpty else {
            rejecter("INVALID_ARGUMENTS", "apiKey is required", nil)
            return
        }
        let trimmed = baseURL?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let url = trimmed.isEmpty ? Self.defaultBaseURL : trimmed

        // How the API key travels. The SDK reads this on every upload path, so
        // a mismatch with the gateway turns every upload into a 401 while
        // tracking still looks healthy. Anything but "queryParam" means header,
        // which is the SDK's own default.
        let mode: VMAuthMode = (authMode?.lowercased() == "queryparam") ? .queryParam : .header
        trace("-> SDK configure(authMode:) | \(mode == .header ? "header" : "queryParam")")
        trackingManager.configure(authMode: mode)

        trace("-> SDK setAutoUpload | \(autoUpload)")
        trackingManager.setAutoUpload(enabled: autoUpload)

        trace("-> SDK initializeWithValidation | apiKey=\(Self.maskKey(apiKey)) baseURL=\(url)")
        trackingManager.initializeWithValidation(apiKey: apiKey, baseURL: url) { [weak self] error in
            guard let self = self else { return }
            if let error = error {
                self.isInitialized = false
                let nsError = error as NSError
                self.trace("initializeTracking failed: \(nsError.localizedDescription)")
                rejecter("INVALID_API_KEY", nsError.localizedDescription, error)
            } else {
                self.isInitialized = true
                self.trace("initializeTracking success")
                resolver(nil)
            }
        }
    }

    @objc(configureAlertAPI:apiID:resolver:rejecter:)
    func configureAlertAPI(
        _ apiKey: String,
        apiID: String,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        guard guardInitialized(rejecter) else { return }
        trackingManager.configureAlertAPI(apiKey: apiKey, apiID: apiID)
        currentAlertConfig = [
            "apiKey": Self.maskKey(apiKey),
            "timestamp": Date().timeIntervalSince1970 * 1000
        ]
        resolver(true)
    }

    // MARK: - Identity

    @objc(setDriverId:resolver:rejecter:)
    func setDriverId(
        _ driverId: String,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        guard guardInitialized(rejecter) else { return }
        trace("-> SDK setDriverId | \"\(driverId)\" (len=\(driverId.count))")
        trackingManager.setDriverId(driverId)
        resolver(true)
    }

    @objc(getDriverId:rejecter:)
    func getDriverId(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(trackingManager.getDriverId() ?? "")
    }

    @objc(setVehicleId:resolver:rejecter:)
    func setVehicleId(
        _ vehicleId: String,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        guard guardInitialized(rejecter) else { return }
        trace("-> SDK setVehicleId | \"\(vehicleId)\" (len=\(vehicleId.count))")
        trackingManager.setVehicleId(vehicleId)
        resolver(true)
    }

    @objc(getVehicleId:rejecter:)
    func getVehicleId(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(trackingManager.getVehicleId() ?? "")
    }

    @objc(setMetadata:resolver:rejecter:)
    func setMetadata(
        _ metadata: NSDictionary,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        guard guardInitialized(rejecter) else { return }
        trace("-> SDK setMetadata | \(metadata.count) keys")
        trackingManager.setMetadata(metadata)
        resolver(true)
    }

    @objc(setPackages:resolver:rejecter:)
    func setPackages(
        _ packages: NSArray,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        guard guardInitialized(rejecter) else { return }
        // Reject a non-string entry rather than coercing it: a package code
        // that silently became "1" would be accepted by the server and be
        // wrong in the data.
        guard let list = packages as? [String] else {
            rejecter("INVALID_ARGUMENTS", "packages must be an array of strings", nil)
            return
        }
        trace("-> SDK setPackages | \(list)")
        trackingManager.setPackages(list)
        resolver(true)
    }

    @objc(setAppSignature:resolver:rejecter:)
    func setAppSignature(
        _ signature: String,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        guard guardInitialized(rejecter) else { return }
        trace("-> SDK setAppSignature | (len=\(signature.count))")
        trackingManager.setAppSignature(signature)
        resolver(true)
    }

    @objc(configureVehicle:vehicleType:seats:weight:maxProvision:resolver:rejecter:)
    func configureVehicle(
        _ vehicleId: String,
        vehicleType: Int,
        seats: Int,
        weight: Double,
        maxProvision: Int,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        guard guardInitialized(rejecter) else { return }
        trace("-> SDK configureVehicle | id=\(vehicleId) type=\(vehicleType) seats=\(seats) weight=\(weight) maxProvision=\(maxProvision)")
        trackingManager.configureVehicle(
            vehicleId: vehicleId,
            vehicleType: vehicleType,
            seats: seats,
            weight: weight,
            maxProvision: maxProvision
        )
        resolver(true)
    }

    // MARK: - Tracking

    @objc(startTracking:resolver:rejecter:)
    func startTracking(
        _ config: NSDictionary,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        guard guardInitialized(rejecter) else { return }

        let backgroundMode = (config["backgroundMode"] as? Bool) ?? true
        let allowMockLocation = (config["allowMockLocation"] as? Bool) ?? true
        let enableSpeedFallback = (config["enableSpeedFallback"] as? Bool) ?? true
        let notificationTitle = config["notificationTitle"] as? String
        let notificationMessage = config["notificationMessage"] as? String
        let userId = (config["userId"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""
        let vehicleId = (config["vehicleId"] as? String)?.trimmingCharacters(in: .whitespaces) ?? ""

        guard !userId.isEmpty else {
            rejecter("MISSING_USER_ID", "userId is required to start tracking", nil)
            return
        }

        // Absent means absent. nil tells the SDK to use its own default for that
        // trigger, which is how distance-only and SDK-default modes are reached;
        // substituting a number here would pin every start to "both", where the
        // SDK favours the timer and ignores the distance gate.
        let intervalMs = (config["intervalMs"] as? NSNumber)
        let distanceFilter = (config["distanceFilter"] as? NSNumber)

        // Identity first: the SDK refuses to start without a userId and reports
        // it only on the status listener, where it is easy to miss.
        trace("-> SDK setDriverId | \"\(userId)\" (len=\(userId.count))")
        trackingManager.setDriverId(userId)
        if !vehicleId.isEmpty {
            trace("-> SDK setVehicleId | \"\(vehicleId)\" (len=\(vehicleId.count))")
            trackingManager.setVehicleId(vehicleId)
        }

        // Fake GPS gate. The SDK's didUpdateLocations drops any fix whose
        // CLLocationSourceInformation reports isSimulatedBySoftware or
        // isProducedByAccessory while allowMockLocation is false — which is the
        // SDK default. Every fix on a simulator is simulated, so leaving this
        // unset makes the SDK discard all of them: CoreLocation delivers
        // locations, onLocationUpdate never fires, and the upload batch goes out
        // empty.
        trackingManager.setAllowMockLocation(allowMockLocation)
        if !allowMockLocation {
            trackingManager.setFakeGPSPolicy(fakeGPSPolicy)
        }
        trace("-> SDK setAllowMockLocation | \(allowMockLocation)"
              + (allowMockLocation ? " (pass-through)" : " policy='\(fakeGPSPolicy)'"))

        // Derive speed from distance over time when the OS reports -1.
        trackingManager.setEnableSpeedFallback(enableSpeedFallback)
        trace("-> SDK setEnableSpeedFallback | \(enableSpeedFallback)")

        // Smart battery, opt-in. Left on by default it would immediately push
        // its own preset over whatever cadence tracking just started with.
        let enableSmartBattery = (config["enableSmartBattery"] as? Bool) ?? false
        if enableSmartBattery {
            let preset = (config["smartBatteryPreset"] as? String) ?? "general"
            applySmartBattery(enabled: true, preset: preset)
        }

        // notificationTitle and notificationMessage are Android-only: they label
        // the foreground service notification, which iOS has no equivalent of.
        // They are accepted in the config for a single cross-platform call site
        // and recorded below, but there is nothing to hand the iOS SDK.

        currentTrackingConfig = [
            "backgroundMode": backgroundMode,
            "intervalMs": intervalMs ?? NSNull(),
            "distanceFilter": distanceFilter ?? NSNull(),
            "allowMockLocation": allowMockLocation,
            "timestamp": Date().timeIntervalSince1970 * 1000
        ]

        let mode: String
        switch (intervalMs, distanceFilter) {
        case (.some(let i), .none): mode = "TIMER ONLY (\(i)ms)"
        case (.none, .some(let d)): mode = "DISTANCE ONLY (\(d)m)"
        case (.some(let i), .some(let d)): mode = "BOTH (\(i)ms + \(d)m) - SDK favours the timer"
        case (.none, .none): mode = "SDK DEFAULTS"
        }

        trace(
            "-> SDK startTracking | enhancedBackgroundMode=\(backgroundMode) mode=\(mode) "
            + "| driverId=\(trackingManager.getDriverId() ?? "nil") "
            + "vehicleId=\(trackingManager.getVehicleId() ?? "nil") "
            + "| notificationTitle=\(notificationTitle ?? "nil") "
            + "notificationMessage=\(notificationMessage ?? "nil")"
        )

        trackingManager.startTracking(
            enhancedBackgroundMode: backgroundMode,
            intervalMs: intervalMs,
            distanceFilter: distanceFilter
        ) { [weak self] success, message in
            self?.trace("<- SDK startTracking result | success=\(success) message=\(message ?? "nil")")
            DispatchQueue.main.async {
                resolver(success)
            }
        }
    }

    @objc(stopTracking:rejecter:)
    func stopTracking(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        trace("-> SDK stopTracking")
        trackingManager.stopTracking { [weak self] success, message in
            self?.trace("<- SDK stopTracking result | success=\(success) message=\(message ?? "nil")")
            DispatchQueue.main.async {
                resolve(success)
            }
        }
    }

    /// Change the cadence while tracking runs.
    ///
    /// This used to only write into a local dictionary and resolve true — the
    /// SDK was never told anything, so the call was a no-op that reported
    /// success. `configure(config:)` assigns the SDK's fields without
    /// restarting anything, so it is safe to call mid-session.
    ///
    /// `backgroundMode` cannot be changed this way: the SDK reads it at start.
    @objc(updateTrackingConfig:resolver:rejecter:)
    func updateTrackingConfig(
        _ config: NSDictionary,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        guard guardInitialized(rejecter) else { return }

        let trackingConfig = TrackingConfig()
        // updateInterval is typed TimeInterval but carries MILLISECONDS — the
        // SDK's own default assigns 10000 and calls it "10 seconds".
        if let intervalMs = config["intervalMs"] as? NSNumber {
            trackingConfig.updateInterval = intervalMs.doubleValue
        }
        if let distanceFilter = config["distanceFilter"] as? NSNumber {
            trackingConfig.minDistanceFilter = distanceFilter.doubleValue
        }
        if let accuracy = config["accuracy"] as? String {
            trackingConfig.accuracy = accuracy
        }
        if let allowMock = config["allowMockLocation"] as? Bool {
            trackingConfig.allowMockLocation = allowMock
        }
        if let speedFallback = config["enableSpeedFallback"] as? Bool {
            trackingConfig.enableSpeedFallback = speedFallback
        }

        trace(
            "-> SDK configure(config:) | updateInterval=\(trackingConfig.updateInterval)ms "
            + "minDistanceFilter=\(trackingConfig.minDistanceFilter)m "
            + "accuracy=\(trackingConfig.accuracy) "
            + "allowMockLocation=\(trackingConfig.allowMockLocation)"
        )
        trackingManager.configure(config: trackingConfig)

        if var stored = currentTrackingConfig {
            for (key, value) in (config as? [String: Any]) ?? [:] { stored[key] = value }
            currentTrackingConfig = stored
        }
        resolver(true)
    }

    // MARK: - Location and status

    @objc(getCurrentLocation:rejecter:)
    func getCurrentLocation(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        guard guardInitialized(reject) else { return }
        if let location = trackingManager.getCurrentLocation() {
            resolve(normalizeLocation(location))
        } else {
            reject("LOCATION_UNAVAILABLE", "Unable to get current location", nil)
        }
    }

    @objc(isTrackingActive:rejecter:)
    func isTrackingActive(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(trackingManager.isTrackingActive())
    }

    @objc(getTrackingStatus:rejecter:)
    func getTrackingStatus(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(trackingManager.getTrackingStatus())
    }

    /// Assemble the TrackingHealthStatus shape declared in src/types.ts.
    ///
    /// This used to forward the SDK's dictionary straight through. That looked
    /// reasonable and was wrong: the SDK returns 17 CoreLocation-specific fields
    /// and only one of them, `timeSinceLastUpdate`, shares a name with the eight
    /// this API promises — in seconds where the type says milliseconds. Six of
    /// the eight were simply absent, so the health card rendered almost empty on
    /// iOS while Android, which assembles its own, was fine.
    ///
    /// Android is the side that had it right, so iOS is brought to match rather
    /// than the type being widened to whatever each platform happens to return.
    /// The SDK's own dictionary is kept under `raw`: its CoreLocation diagnostics
    /// are genuinely useful and there is no reason to lose them.
    @objc(getTrackingHealthStatus:rejecter:)
    func getTrackingHealthStatus(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        let raw = trackingManager.getTrackingHealthStatus()
        let status = trackingManager.getTrackingStatus()
        let nowMs = Date().timeIntervalSince1970 * 1000

        // getTrackingStatus already reports milliseconds, and NSNull when no fix
        // has arrived - so this is the reliable source for both.
        let lastLocationUpdateMs = (status["lastLocationUpdate"] as? NSNumber)?.doubleValue
        let trackingDurationMs = (status["trackingDuration"] as? NSNumber)?.doubleValue ?? 0

        // Derived here rather than taken from the SDK's health dictionary. That
        // one computes `currentTime - lastLocationUpdate` with no guard, so
        // before the first fix it reports the whole epoch - about 56 years -
        // instead of "no fix yet". -1 is the "none yet" convention Android uses.
        let timeSinceLastUpdateMs = lastLocationUpdateMs.map { nowMs - $0 } ?? -1

        var out: [String: Any] = [
            "isTracking": trackingManager.isTrackingActive(),
            "hasLocationPermission": trackingManager.hasLocationPermissions(),
            // iOS has no separate background grant; always-on authorization is
            // what lets tracking continue in the background.
            "hasBackgroundPermission": CLLocationManager().authorizationStatus == .authorizedAlways,
            "trackingDuration": trackingDurationMs,
            "timeSinceLastUpdate": timeSinceLastUpdateMs,
            "isInitialized": isInitialized,
            "timestamp": nowMs,
            // Platform-specific CoreLocation diagnostics, documented as iOS-only.
            "raw": raw
        ]
        if let lastLocationUpdateMs = lastLocationUpdateMs {
            out["lastLocationUpdate"] = lastLocationUpdateMs
        }

        resolve(out)
    }

    /// Server-side history. The SDK answers with (json, errorCode, message);
    /// exactly one side is populated.
    ///
    /// Timestamps arrive as Double because the bridge has no 64-bit integer,
    /// and are in milliseconds — the Android SDK treats a value under 10 billion
    /// as seconds and converts it, so seconds would shift the window by decades.
    @objc(getTrackingHistory:fromTimestamp:toTimestamp:pageNumber:pageSize:sortBy:sortDescending:resolver:rejecter:)
    func getTrackingHistory(
        _ userId: String,
        fromTimestamp: Double,
        toTimestamp: Double,
        pageNumber: Int,
        pageSize: Int,
        sortBy: String?,
        sortDescending: Bool,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        guard guardInitialized(rejecter) else { return }
        guard !userId.trimmingCharacters(in: .whitespaces).isEmpty else {
            rejecter("INVALID_ARGUMENTS", "userId is required", nil)
            return
        }

        trace(
            "-> SDK getHistory | userId=\(userId) from=\(Int64(fromTimestamp)) to=\(Int64(toTimestamp)) "
            + "page=\(pageNumber) size=\(pageSize) sortBy=\(sortBy ?? "") desc=\(sortDescending)"
        )
        trackingManager.getHistory(
            userId: userId,
            fromTime: Int64(fromTimestamp),
            toTime: Int64(toTimestamp),
            pageNumber: pageNumber,
            pageSize: pageSize,
            sortBy: sortBy ?? "",
            sortDescending: sortDescending
        ) { [weak self] json, errorCode, message in
            self?.trace("<- SDK getHistory | bytes=\(json?.count ?? 0) errorCode=\(errorCode ?? "nil")")
            DispatchQueue.main.async {
                if let errorCode = errorCode {
                    rejecter(errorCode, message ?? "Failed to fetch history", nil)
                } else {
                    resolver(json ?? "")
                }
            }
        }
    }

    // MARK: - Permissions

    @objc(requestLocationPermissions:rejecter:)
    func requestLocationPermissions(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        trackingManager.requestLocationPermissions { status in
            DispatchQueue.main.async {
                // Shaped as PermissionResult so both platforms answer alike.
                resolve([
                    "granted": status == "granted",
                    "status": status,
                    "fineLocation": status == "granted",
                    "coarseLocation": status == "granted",
                    // iOS has no separate background grant; always-on is a
                    // distinct authorization, requested on its own.
                    "backgroundLocation": status == "granted"
                ])
            }
        }
    }

    @objc(hasLocationPermissions:rejecter:)
    func hasLocationPermissions(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        let hasPermission = trackingManager.hasLocationPermissions()
        resolve([
            "granted": hasPermission,
            "status": hasPermission ? "granted" : "not_granted",
            "fineLocation": hasPermission,
            "coarseLocation": hasPermission,
            "backgroundLocation": hasPermission
        ])
    }

    @objc(requestAlwaysLocationPermissions:rejecter:)
    func requestAlwaysLocationPermissions(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        trackingManager.requestAlwaysLocationPermissions { status in
            DispatchQueue.main.async {
                resolve(status)
            }
        }
    }

    // MARK: - Offline cache and upload

    @objc(isNetworkConnected:rejecter:)
    func isNetworkConnected(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(trackingManager.isNetworkConnected())
    }

    @objc(getCachedLocationsCount:rejecter:)
    func getCachedLocationsCount(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        resolve(trackingManager.getCachedLocationsCount())
    }

    @objc(uploadCachedLocationsManually:rejecter:)
    func uploadCachedLocationsManually(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        guard guardInitialized(reject) else { return }
        let pending = trackingManager.getCachedLocationsCount()
        trace("-> SDK uploadCachedLocationsManually | pending=\(pending)")
        trackingManager.uploadCachedLocationsManually { [weak self] success, message in
            self?.trace("<- SDK uploadCachedLocationsManually | success=\(success) message=\(message ?? "nil")")
            DispatchQueue.main.async {
                resolve(success)
            }
        }
    }

    @objc(clearCachedLocations:rejecter:)
    func clearCachedLocations(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        guard guardInitialized(reject) else { return }
        trace("-> SDK clearCachedLocations | discarding \(trackingManager.getCachedLocationsCount()) pending")
        trackingManager.clearCachedLocations()
        resolve(true)
    }

    /// A zero keeps the SDK's own value for that field. maxDbSizeBytes crosses
    /// the bridge as a Double because it exceeds 2^31 and the bridge has no
    /// 64-bit integer type.
    @objc(configureCacheLimits:maxDbSizeBytes:batchSize:resolver:rejecter:)
    func configureCacheLimits(
        _ maxRecords: Int,
        maxDbSizeBytes: Double,
        batchSize: Int,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        guard guardInitialized(rejecter) else { return }
        trace("-> SDK configureCacheLimits | maxRecords=\(maxRecords) maxDbSizeBytes=\(Int64(maxDbSizeBytes)) batchSize=\(batchSize)")
        trackingManager.configureCacheLimits(
            maxRecords: maxRecords,
            maxDbSizeBytes: Int64(maxDbSizeBytes),
            batchSize: batchSize
        )
        resolver(true)
    }

    @objc(getDatabaseSizeBytes:rejecter:)
    func getDatabaseSizeBytes(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        // Int64 -> Double for the bridge. A 50MB cap is far inside the range a
        // double represents exactly, so nothing is lost.
        resolve(Double(trackingManager.getDatabaseSizeBytes()))
    }

    // MARK: - Lifecycle, exposed for a host that manages app state itself

    @objc(onAppBackground:rejecter:)
    func onAppBackground(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        traceLife("onAppBackground called from JS t=\(Self.uptimeMs())")
        trackingManager.onAppBackground()
        resolve(true)
    }

    @objc(onAppForeground:rejecter:)
    func onAppForeground(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        traceLife("onAppForeground called from JS t=\(Self.uptimeMs())")
        trackingManager.onAppForeground()
        resolve(true)
    }

    @objc(setAutoUpload:resolver:rejecter:)
    func setAutoUpload(
        _ enabled: Bool,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        guard guardInitialized(rejecter) else { return }
        trace("-> SDK setAutoUpload | \(enabled)")
        trackingManager.setAutoUpload(enabled: enabled)
        resolver(true)
    }

    // MARK: - Notification permission
    //
    // The SDK posts the fake-GPS and tracking-interrupted notifications through
    // UNUserNotificationCenter and documents that the host must already hold
    // authorization. iOS does not prompt when a notification is posted: with
    // authorization .notDetermined the post is simply dropped, and the SDK only
    // print()s the failure. So nothing appears until something calls this.
    //
    // This covers permission only, not display. A notification posted while the
    // app is in the foreground is delivered but not shown unless the app sets a
    // UNUserNotificationCenterDelegate. That delegate is app-wide state and a
    // library seizing it would break any host app that has its own, so it is
    // deliberately left to the app.

    @objc(requestNotificationPermission:rejecter:)
    func requestNotificationPermission(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { [weak self] granted, error in
            self?.trace("<- notification authorization | granted=\(granted) error=\(error?.localizedDescription ?? "nil")")
            DispatchQueue.main.async {
                resolve(granted)
            }
        }
    }

    @objc(hasNotificationPermission:rejecter:)
    func hasNotificationPermission(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            // .provisional delivers quietly to the notification centre, which is
            // still a delivery, so it counts as authorized here.
            let granted = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
            DispatchQueue.main.async {
                resolve(granted)
            }
        }
    }

    // MARK: - Fake GPS

    /// Choose what the SDK does when it detects a fake fix. Takes effect only
    /// while allowMockLocation is false; startTracking pushes it to the SDK.
    @objc(setFakeGPSPolicy:resolver:rejecter:)
    func setFakeGPSPolicy(
        _ policy: String,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        let allowed = ["skip", "warn", "stopTracking", "logToServer"]
        guard allowed.contains(policy) else {
            rejecter("INVALID_ARGUMENTS",
                     "policy must be one of \(allowed.joined(separator: ", "))", nil)
            return
        }
        fakeGPSPolicy = policy
        trace("-> SDK setFakeGPSPolicy | \"\(policy)\"")
        trackingManager.setFakeGPSPolicy(policy)
        resolver(true)
    }

    /// Title and body of the notification raised by the "warn" policy. The
    /// native parameter is `body`; the JS name stays `message` to match the rest
    /// of this surface.
    @objc(setFakeGpsNotificationConfig:message:resolver:rejecter:)
    func setFakeGpsNotificationConfig(
        _ title: String,
        message: String,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        trace("-> SDK setFakeGPSNotificationConfig | title=\"\(title)\" body=\"\(message)\"")
        trackingManager.setFakeGPSNotificationConfig(title: title, body: message)
        resolver(true)
    }

    // MARK: - Tracking interrupted

    /// Show or hide the interruption notification. This does NOT silence the
    /// onTrackingInterrupted event; the callback channel fires either way.
    @objc(setTrackingInterruptedNotificationEnabled:resolver:rejecter:)
    func setTrackingInterruptedNotificationEnabled(
        _ enabled: Bool,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        trace("-> SDK setTrackingInterruptedNotificationEnabled | \(enabled)")
        trackingManager.setTrackingInterruptedNotificationEnabled(enabled)
        resolver(true)
    }

    @objc(setTrackingInterruptedNotificationConfig:message:resolver:rejecter:)
    func setTrackingInterruptedNotificationConfig(
        _ title: String,
        message: String,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        trace("-> SDK setTrackingInterruptedNotificationConfig | title=\"\(title)\" body=\"\(message)\"")
        trackingManager.setTrackingInterruptedNotificationConfig(title: title, body: message)
        resolver(true)
    }

    // MARK: - Smart battery

    /// Neither SDK exposes a smart battery setting, so it is assembled here.
    ///
    /// On iOS the lever is CoreLocation's activity type: with
    /// .automotiveNavigation and pausesLocationUpdatesAutomatically the OS
    /// adjusts sampling to speed and cornering and pauses updates when the
    /// vehicle is parked. The preset also sets the interval, so the cadence
    /// matches what Android does through safeUpdateTrackingConfig.
    private func applySmartBattery(enabled: Bool, preset: String) {
        smartBatteryEnabled = enabled
        smartBatteryPreset = preset

        let manager = CLLocationManager()
        if enabled {
            manager.activityType = .automotiveNavigation
            manager.pausesLocationUpdatesAutomatically = true
        } else {
            manager.activityType = .other
            manager.pausesLocationUpdatesAutomatically = false
        }

        guard enabled, let intervalMs = Self.smartBatteryIntervalsMs[preset] else {
            trace("-> smart battery | enabled=\(enabled) preset=\(preset) (no interval change)")
            return
        }

        // Interval-only, matching Android: a displacement filter alongside the
        // timer would be ignored by the SDK anyway.
        let config = TrackingConfig()
        config.updateInterval = Double(intervalMs)
        config.minDistanceFilter = 0
        trace("-> SDK configure(config:) smart battery | preset=\(preset) interval=\(intervalMs)ms")
        trackingManager.configure(config: config)
    }

    @objc(setSmartBatteryConfig:preset:resolver:rejecter:)
    func setSmartBatteryConfig(
        _ enabled: Bool,
        preset: String,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        guard guardInitialized(rejecter) else { return }
        guard Self.smartBatteryIntervalsMs[preset] != nil else {
            rejecter("INVALID_ARGUMENTS",
                     "preset must be one of \(Self.smartBatteryIntervalsMs.keys.sorted().joined(separator: ", "))",
                     nil)
            return
        }
        applySmartBattery(enabled: enabled, preset: preset)
        resolver(true)
    }

    // MARK: - External GPS injection

    /// speed at or below 30 is read by the SDK as m/s and converted once;
    /// above that it is taken as km/h.
    @objc(processExternalLocation:lng:speed:heading:resolver:rejecter:)
    func processExternalLocation(
        _ lat: Double,
        lng: Double,
        speed: Double,
        heading: Double,
        resolver: @escaping RCTPromiseResolveBlock,
        rejecter: @escaping RCTPromiseRejectBlock
    ) {
        guard guardInitialized(rejecter) else { return }
        trace("-> SDK processExternalLocation | lat=\(lat) lng=\(lng) speed=\(speed) heading=\(heading)")
        trackingManager.processExternalLocation(lat: lat, lng: lng, speed: speed, heading: heading)
        resolver(true)
    }

    // MARK: - Speed alert

    @objc(turnOnAlert:rejecter:)
    func turnOnAlert(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        guard guardInitialized(reject) else { return }
        trackingManager.turnOnAlert { success in
            DispatchQueue.main.async { resolve(success) }
        }
    }

    @objc(turnOffAlert:rejecter:)
    func turnOffAlert(
        _ resolve: @escaping RCTPromiseResolveBlock,
        rejecter reject: @escaping RCTPromiseRejectBlock
    ) {
        guard guardInitialized(reject) else { return }
        trackingManager.turnOffAlert { success in
            DispatchQueue.main.async { resolve(success) }
        }
    }

    // MARK: - NativeEventEmitter conformance
    //
    // RCTEventEmitter implements both, and its implementations maintain the
    // listener count that drives startObserving / stopObserving — so these
    // override only to make the methods visible to the parity check and to the
    // TurboModule spec, and must call super to keep that bookkeeping intact.

    @objc(addListener:)
    override func addListener(_ eventName: String) {
        super.addListener(eventName)
    }

    @objc(removeListeners:)
    override func removeListeners(_ count: Double) {
        super.removeListeners(count)
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

// MARK: - Alias for backwards compatibility
@objc(RNVietmapTrackingPlugin)
class RNVietmapTrackingPlugin: RnVietmapTrackingPlugin {
    // Inherits all functionality from RnVietmapTrackingPlugin
}

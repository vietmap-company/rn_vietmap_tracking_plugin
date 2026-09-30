package com.rnvietmaptrackingplugin

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.core.app.ActivityCompat
import com.facebook.react.bridge.*
import com.facebook.react.common.LifecycleState
import com.facebook.react.modules.core.DeviceEventManagerModule
import com.facebook.react.modules.core.PermissionAwareActivity
import com.facebook.react.modules.core.PermissionListener
import com.google.gson.Gson
import com.vietmap.trackingsdk.VietmapTrackingSDK
import com.vietmap.trackingsdk.TrackingConfig
import com.vietmap.trackingsdk.VMLocation
import com.vietmap.trackingsdk.RouteData

/**
 * RnVietmapTrackingPluginModule
 *
 * This module provides a bridge between React Native and VietmapTrackingSDK.
 * Integrated with actual VietmapTrackingSDK APIs following the sample implementation.
 *
 * Features:
 * - VietmapTrackingSDK integration with basic methods
 * - Real-time location tracking capabilities
 * - Configuration and cache management
 * - Proper permission handling
 */
class RnVietmapTrackingPluginModule(reactContext: ReactApplicationContext) :
  NativeRnVietmapTrackingPluginSpec(reactContext), LifecycleEventListener {

  companion object {
    const val LOCATION_PERMISSION_REQUEST_CODE = 1001
    const val BACKGROUND_LOCATION_PERMISSION_REQUEST_CODE = 1002
    const val NOTIFICATION_PERMISSION_REQUEST_CODE = 1003

    private const val TAG = "RnVietmapTracking"

    /** Defaults for getCurrentLocation(), mirroring the Flutter plugin. */
    private const val DEFAULT_LOCATION_MAX_AGE_MS = 10_000L
    private const val DEFAULT_LOCATION_TIMEOUT_MS = 5_000

    /** Same fallback the Flutter plugin uses when no baseURL is supplied. */
    private const val DEFAULT_BASE_URL = "https://live.fleetwork.vn/api/v1"

    /**
     * Sampling interval used in distance mode, in both the bootstrap and the
     * final config. It stays small on purpose: the engine has to poll often
     * enough to notice the displacement threshold being crossed. A large
     * interval makes it sample sparsely and miss the crossings entirely.
     */
    private const val DISTANCE_MODE_INTERVAL_MS = 1000L

    /** Lifecycle timeline, tagged separately so one grep gets a transition. */
    private const val LIFECYCLE_TAG = "VMLife"

    /**
     * Debug-only logging.
     *
     * These lines carry driver ids and coordinates, so they must not reach a
     * consumer's release build. Android does not strip Log.d on its own and a
     * library cannot rely on the host app's R8 rules, so the gate is explicit.
     * iOS gets the same guarantee from `#if DEBUG` around trace().
     */
    private fun logDebug(tag: String, message: String) {
      if (BuildConfig.DEBUG) {
        Log.d(tag, message)
      }
    }

    /**
     * How long to wait after foreground before checking for a stuck queue. The
     * SDK restarts its network monitor inside onAppForeground, so checking
     * immediately would read a state that is about to change.
     */
    private const val POST_FOREGROUND_DRAIN_DELAY_MS = 1500L

    /**
     * Intervals each smart battery preset maps to, in milliseconds. These must
     * stay in step with SMART_BATTERY_INTERVALS_MS in src/constants.ts.
     */
    private val SMART_BATTERY_INTERVALS_MS = mapOf(
      "navigation" to 5_000L,
      "general" to 30_000L,
      "batterySaver" to 300_000L
    )

    /** Never log a full API key; the prefix is enough to tell keys apart. */
    private fun maskKey(key: String): String =
      if (key.length > 10) "${key.take(8)}...(${key.length} chars)" else "${key.length} chars"
  }

  override fun getConstants(): MutableMap<String, Any> {
    return hashMapOf(
      "screenWidth" to reactApplicationContext.resources.displayMetrics.widthPixels,
      "screenHeight" to reactApplicationContext.resources.displayMetrics.heightPixels
    )
  }

  // MARK: - VietmapTrackingSDK Integration
  private lateinit var vietmapSDK: VietmapTrackingSDK
  private val gson = Gson()
  private var isInitialized: Boolean = false
  private var currentTrackingConfig: WritableMap? = null
  private var pendingNotificationPermissionPromise: Promise? = null
  private var pendingLocationPermissionPromise: Promise? = null
  private var pendingBackgroundPermissionPromise: Promise? = null

  // SDK callbacks, held so they can be unregistered on teardown.
  private val mainHandler = Handler(Looper.getMainLooper())
  private var locationCallback: VietmapTrackingSDK.LocationUpdateCallback? = null
  private var statusCallback: VietmapTrackingSDK.TrackingStatusCallback? = null
  private var fakeGPSCallback: VietmapTrackingSDK.FakeGPSCallback? = null
  private var trackingInterruptedCallback: VietmapTrackingSDK.TrackingInterruptedCallback? = null

  // Diagnostics consumed by getTrackingHealthStatus() in Phase 2. The Android
  // SDK has no getTrackingHealthStatus() of its own, unlike iOS.
  private var lastLocationTimestamp: Long = 0L
  private var trackingStartTime: Long = 0L

  /** One-shot callback that applies the real distance filter on the first fix. */
  private var distanceBootstrapCallback: VietmapTrackingSDK.LocationUpdateCallback? = null

  /** Smart battery state. Neither SDK exposes this, so the module holds it. */
  private var smartBatteryEnabled: Boolean = false
  private var smartBatteryPreset: String = "general"

  /**
   * Sequence number for a lifecycle transition, assigned by the native
   * listener and carried through every later line for that transition. Without
   * it two quick background/foreground cycles interleave unreadably.
   */
  private var lifecycleSeq: Int = 0

  init {
    initializeSDK()
    setupLifecycleListener()
  }

  // MARK: - App lifecycle, observed natively
  //
  // Flutter's Android plugin has no native observer and relies on the Dart
  // layer calling onAppBackground / onAppForeground. React Native gives the
  // module a first-class one, so app state never has to cross the bridge -
  // which matters because the JS thread is exactly what stops being dependable
  // as the app is being backgrounded.
  //
  // Do not also wire AppState to onAppBackground from JS: every transition
  // would then arrive twice.

  private fun setupLifecycleListener() {
    reactApplicationContext.addLifecycleEventListener(this)

    // Seed the state rather than waiting for the next transition. A module
    // created while the app is already in the background - a background restart,
    // a headless task - would otherwise leave the SDK believing it is in the
    // foreground until the user next brings the app up.
    val state = reactApplicationContext.lifecycleState
    logDebug(LIFECYCLE_TAG, "init | lifecycleState=$state t=${SystemClock.elapsedRealtime()}")
    if (state == LifecycleState.BEFORE_RESUME || state == LifecycleState.BEFORE_CREATE) {
      logDebug(LIFECYCLE_TAG, "init | seeding background state into the SDK")
      if (isInitialized) {
        try {
          vietmapSDK.onAppBackground()
        } catch (e: Exception) {
        }
      }
    }
  }

  override fun onHostResume() {
    lifecycleSeq += 1
    val seq = lifecycleSeq
    logDebug(LIFECYCLE_TAG, "#$seq native-listener onHostResume t=${SystemClock.elapsedRealtime()}")
    if (!isInitialized) return
    try {
      vietmapSDK.onAppForeground()
      logDebug(LIFECYCLE_TAG, "#$seq sdk.onAppForeground returned t=${SystemClock.elapsedRealtime()}")
    } catch (e: Exception) {
      Log.w(LIFECYCLE_TAG, "#$seq onAppForeground failed: ${e.message}")
      return
    }

    // Post-foreground drain, which the Flutter plugin does on iOS only. The SDK
    // restarts its own network monitor inside onAppForeground, so this waits for
    // that to settle before deciding whether anything is still stuck.
    mainHandler.postDelayed({
      try {
        val pending = vietmapSDK.getCachedLocationsCount()
        val online = vietmapSDK.isNetworkAvailable()
        logDebug(LIFECYCLE_TAG, "#$seq post-foreground | pending=$pending network=$online")
        if (online && pending > 0) {
          logDebug(LIFECYCLE_TAG, "#$seq post-foreground | draining $pending pending")
          vietmapSDK.uploadCachedLocationsManually()
        }
      } catch (e: Exception) {
      }
    }, POST_FOREGROUND_DRAIN_DELAY_MS)
  }

  override fun onHostPause() {
    lifecycleSeq += 1
    val seq = lifecycleSeq
    logDebug(LIFECYCLE_TAG, "#$seq native-listener onHostPause t=${SystemClock.elapsedRealtime()}")
    if (!isInitialized) return
    try {
      vietmapSDK.onAppBackground()
      logDebug(LIFECYCLE_TAG, "#$seq sdk.onAppBackground returned t=${SystemClock.elapsedRealtime()}")
    } catch (e: Exception) {
      Log.w(LIFECYCLE_TAG, "#$seq onAppBackground failed: ${e.message}")
    }
  }

  override fun onHostDestroy() {
    logDebug(LIFECYCLE_TAG, "onHostDestroy t=${SystemClock.elapsedRealtime()}")
    // Nothing to tell the SDK here; invalidate() does the teardown.
  }

  // MARK: - VietmapTrackingSDK Initialization
  private fun initializeSDK() {
    try {
      // Initialize VietmapTrackingSDK instance (but not initialized until configure() is called)
      vietmapSDK = VietmapTrackingSDK.getInstance(reactApplicationContext)
    } catch (e: Exception) {
      isInitialized = false
    }
  }

  // MARK: - ReadableMap Helpers
  //
  // A missing key and a supplied value mean different things here - the
  // tracking trigger mode is chosen by which keys are present - so every reader
  // checks hasKey() and isNull() before it reads.

  private fun ReadableMap.optBoolean(key: String, fallback: Boolean): Boolean =
    if (hasKey(key) && !isNull(key)) getBoolean(key) else fallback

  private fun ReadableMap.optString(key: String, fallback: String?): String? =
    if (hasKey(key) && !isNull(key)) getString(key) else fallback

  /** Null means the key was absent, which is not the same as zero. */
  private fun ReadableMap.optLong(key: String): Long? =
    if (hasKey(key) && !isNull(key)) getDouble(key).toLong() else null

  /** Null means the key was absent, which is not the same as zero. */
  private fun ReadableMap.optDouble(key: String): Double? =
    if (hasKey(key) && !isNull(key)) getDouble(key) else null

  private fun ReadableMap.optInt(key: String, fallback: Int): Int =
    if (hasKey(key) && !isNull(key)) getDouble(key).toInt() else fallback

  // MARK: - Permission Helper Methods
  private fun hasLocationPermission(): Boolean {
    val fineLocationPermission = ContextCompat.checkSelfPermission(
      reactApplicationContext,
      Manifest.permission.ACCESS_FINE_LOCATION
    ) == PackageManager.PERMISSION_GRANTED

    val coarseLocationPermission = ContextCompat.checkSelfPermission(
      reactApplicationContext,
      Manifest.permission.ACCESS_COARSE_LOCATION
    ) == PackageManager.PERMISSION_GRANTED

    return fineLocationPermission && coarseLocationPermission
  }

  /**
   * Background location is a separate grant from Android 10 onwards. Below
   * that, foreground access already covers background use, so this reports
   * whatever the foreground check says rather than false.
   */
  private fun hasBackgroundLocationPermission(): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
      return hasLocationPermission()
    }
    return ContextCompat.checkSelfPermission(
      reactApplicationContext,
      Manifest.permission.ACCESS_BACKGROUND_LOCATION
    ) == PackageManager.PERMISSION_GRANTED
  }

  // MARK: - React Native Event Emission
  private fun sendEvent(eventName: String, params: WritableMap?) {
    try {
      reactApplicationContext
        .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
        .emit(eventName, params)
    } catch (e: Exception) {
    }
  }

  // MARK: - SDK Callback Wiring
  /**
   * Forward the SDK's location and status callbacks to React Native.
   *
   * Without this the module never called addLocationCallback() /
   * addStatusCallback(), so onLocationUpdate and onTrackingStatusChanged were
   * never emitted on Android and addLocationUpdateListener() was dead. iOS has
   * always wired the equivalent closures in setupSDKCallbacks().
   *
   * The payload matches the LocationData type declared in src/types.ts so the
   * JS contract is unchanged.
   */
  private fun setupSDKCallbacks() {
    clearSDKCallbacks()

    locationCallback = VietmapTrackingSDK.LocationUpdateCallback { location: VMLocation ->
      lastLocationTimestamp = System.currentTimeMillis()

      mainHandler.post {
        val payload = Arguments.createMap().apply {
          putDouble("latitude", location.lat)
          putDouble("longitude", location.lng)
          putDouble("altitude", location.altitude)
          putDouble("accuracy", location.accuracy)
          putDouble("speed", location.speed)
          putDouble("bearing", location.bearing)
          putDouble("timestamp", location.timestamp.toDouble())
        }
        sendEvent("onLocationUpdate", payload)
      }
    }
    vietmapSDK.addLocationCallback(locationCallback!!)

    statusCallback = VietmapTrackingSDK.TrackingStatusCallback { isTracking, message ->
      mainHandler.post {
        val payload = Arguments.createMap().apply {
          putBoolean("isTracking", isTracking)
          putString("message", message)
          putDouble("timestamp", System.currentTimeMillis().toDouble())
        }
        sendEvent("onTrackingStatusChanged", payload)
      }
    }
    vietmapSDK.addStatusCallback(statusCallback!!)

    // Fake GPS. The Android SDK reports position only - no `reason` - so the
    // event carries fewer fields here than on iOS. Documented rather than
    // filled with an invented value.
    fakeGPSCallback = VietmapTrackingSDK.FakeGPSCallback { lat, lng ->
      mainHandler.post {
        val payload = Arguments.createMap().apply {
          putDouble("lat", lat)
          putDouble("lng", lng)
          // Milliseconds, matching every other timestamp this module emits. The
          // iOS bridge converts the SDK's seconds to match.
          putDouble("timestamp", System.currentTimeMillis().toDouble())
          // Always true: the SDK only invokes this callback on a first detection
          // within its 30s window. Sent so the event has the same shape on both
          // platforms - iOS gets it from the SDK payload. The Flutter plugin
          // hardcodes it here for the same reason.
          putBoolean("isFirstDetection", true)
        }
        logDebug(TAG, "onFakeGPSDetected from SDK | lat=$lat lng=$lng")
        sendEvent("onFakeGPSDetected", payload)
      }
    }
    vietmapSDK.addFakeGPSCallback(fakeGPSCallback!!)

    // Apps must NOT stop and restart tracking in response to this. The SDK
    // raises it from GPS silence, so a restart only costs a fresh first fix and
    // can loop.
    trackingInterruptedCallback =
      VietmapTrackingSDK.TrackingInterruptedCallback { reason, recovered, isInBackground, secondsSinceLastFix ->
        mainHandler.post {
          val payload = Arguments.createMap().apply {
            putString("reason", reason)
            putBoolean("recovered", recovered)
            putBoolean("isInBackground", isInBackground)
            putDouble("secondsSinceLastFix", secondsSinceLastFix.toDouble())
          }
          logDebug(TAG, "onTrackingInterrupted from SDK | reason=$reason recovered=$recovered")
          sendEvent("onTrackingInterrupted", payload)
        }
      }
    vietmapSDK.addTrackingInterruptedCallback(trackingInterruptedCallback!!)
  }

  /**
   * Emit onLocationError.
   *
   * The Android SDK has no error callback of its own - iOS exposes onError, and
   * nothing here corresponds to it - so this module raises the errors it can
   * actually see: a failed getCurrentLocation, a refused start. Without this the
   * event was declared in supportedEvents and never emitted, so a listener
   * attached on Android stayed silent forever while the same code worked on iOS.
   */
  private fun emitLocationError(message: String) {
    mainHandler.post {
      val payload = Arguments.createMap().apply {
        putString("message", message)
        putDouble("timestamp", System.currentTimeMillis().toDouble())
      }
      sendEvent("onLocationError", payload)
    }
  }

  private fun clearSDKCallbacks() {
    try {
      locationCallback?.let { vietmapSDK.removeLocationCallback(it) }
      statusCallback?.let { vietmapSDK.removeStatusCallback(it) }
      fakeGPSCallback?.let { vietmapSDK.removeFakeGPSCallback(it) }
      trackingInterruptedCallback?.let { vietmapSDK.removeTrackingInterruptedCallback(it) }
    } catch (e: Exception) {
    }
    locationCallback = null
    statusCallback = null
    fakeGPSCallback = null
    trackingInterruptedCallback = null
  }

  // MARK: - Configuration
  @ReactMethod
  override fun configure(apiKey: String, baseURL: String?, promise: Promise) {
    try {
      // Validate API key
      if (apiKey.isEmpty()) {
        promise.reject("INVALID_API_KEY", "API key is required")
        return
      }

      logDebug(TAG,
        "-> SDK initialize | apiKey=${maskKey(apiKey)} " +
          "baseURL=${if (baseURL.isNullOrEmpty()) "(SDK default)" else baseURL}"
      )

      // Initialize VietmapTrackingSDK with API key
      if (baseURL != null && baseURL.isNotEmpty()) {
          vietmapSDK.initialize(apiKey, baseURL)
      } else {
          vietmapSDK.initialize(apiKey)
      }

      // Set isInitialized to true only after successful initialization
      isInitialized = true

      // Register the SDK callbacks that back onLocationUpdate /
      // onTrackingStatusChanged. Safe to call again - it clears first.
      setupSDKCallbacks()

      // Store current configuration
      currentTrackingConfig = Arguments.createMap().apply {
        putString("apiKey", "***")  // Don't expose API key
        putString("baseURL", baseURL ?: "")
        putDouble("updateInterval", 20000.0)
        putDouble("minDistanceFilter", 10.0)
        putBoolean("enableBackgroundMode", true)
        putDouble("timestamp", System.currentTimeMillis().toDouble())
      }

      promise.resolve(true)

    } catch (e: Exception) {
      isInitialized = false
      promise.reject("CONFIGURE_FAILED", "Failed to configure VietmapTrackingSDK: ${e.message}")
    }
  }

  /**
   * Validate the API key server-side, then configure. Mirrors the Flutter
   * plugin's initializeTracking. isInitialized and the SDK callbacks are only
   * set up once validation succeeds, so a bad key cannot leave the module
   * half-configured.
   */
  @ReactMethod
  override fun initializeTracking(
    apiKey: String,
    baseURL: String?,
    authMode: String?,
    autoUpload: Boolean?,
    promise: Promise
  ) {
    if (apiKey.isEmpty()) {
      promise.reject("INVALID_ARGUMENTS", "apiKey is required")
      return
    }
    val url = if (!baseURL.isNullOrEmpty()) baseURL else DEFAULT_BASE_URL

    // How the API key travels. The SDK reads this on every upload path, so a
    // mismatch with the gateway turns every upload into a 401 while tracking
    // still looks healthy. Anything but "queryParam" means header, the SDK's
    // own default. Named setAuthMode(isHeader) here against
    // configure(authMode:) on iOS.
    val useHeaderAuth = !authMode.equals("queryParam", ignoreCase = true)
    logDebug(TAG, "-> SDK setAuthMode | ${if (useHeaderAuth) "header" else "queryParam"}")
    try {
      vietmapSDK.setAuthMode(useHeaderAuth)
    } catch (e: Exception) {
      Log.w(TAG, "setAuthMode failed: ${e.message}")
    }

    // autoUpload has no Android equivalent - uploads are always automatic - so
    // it is logged and otherwise ignored, matching setAutoUpload() below.
    if (autoUpload == false) {
      Log.w(TAG, "autoUpload=false has no effect on Android; uploads are always automatic")
    }

    logDebug(TAG, "-> SDK initializeWithValidation | apiKey=${maskKey(apiKey)} baseURL=$url")
    try {
      vietmapSDK.initializeWithValidation(apiKey, url, object : VietmapTrackingSDK.ValidationCallback {
        override fun onSuccess() {
          isInitialized = true
          setupSDKCallbacks()
          logDebug(TAG, "initializeTracking success | baseURL=$url")
          promise.resolve(null)
        }

        override fun onError(message: String?) {
          isInitialized = false
          promise.reject("INVALID_API_KEY", message ?: "API key validation failed")
        }
      })
    } catch (e: Exception) {
      isInitialized = false
      promise.reject("INITIALIZE_FAILED", e.message)
    }
  }

  // MARK: - Identity
  // The SDK exposes setters only, so the module caches the values to answer the
  // getters. Mirrors how the Flutter plugin does it.
  private var cachedDriverId: String = ""
  private var cachedVehicleId: String = ""

  @ReactMethod
  override fun setDriverId(driverId: String, promise: Promise) {
    if (!isInitialized) {
      promise.reject("SDK_NOT_INITIALIZED", "VietmapTrackingSDK not initialized")
      return
    }
    try {
      logDebug(TAG, "-> SDK setDriverId | \"$driverId\" (len=${driverId.length})")
      vietmapSDK.setDriverId(driverId)
      cachedDriverId = driverId
      promise.resolve(true)
    } catch (e: Exception) {
      promise.reject("SET_DRIVER_ID_ERROR", e.message)
    }
  }

  @ReactMethod
  override fun getDriverId(promise: Promise) {
    promise.resolve(cachedDriverId)
  }

  @ReactMethod
  override fun setVehicleId(vehicleId: String, promise: Promise) {
    if (!isInitialized) {
      promise.reject("SDK_NOT_INITIALIZED", "VietmapTrackingSDK not initialized")
      return
    }
    try {
      logDebug(TAG, "-> SDK setVehicleId | \"$vehicleId\" (len=${vehicleId.length})")
      vietmapSDK.setVehicleId(vehicleId)
      cachedVehicleId = vehicleId
      promise.resolve(true)
    } catch (e: Exception) {
      promise.reject("SET_VEHICLE_ID_ERROR", e.message)
    }
  }

  @ReactMethod
  override fun getVehicleId(promise: Promise) {
    promise.resolve(cachedVehicleId)
  }

  /**
   * What the SDK does once it detects a fake fix: "skip" | "warn" |
   * "stopTracking" | "logToServer". Only consulted while allowMockLocation is
   * false. "skip" - detect and report, change nothing - matches the Flutter
   * plugin's default.
   */
  private var fakeGPSPolicy: String = "skip"

  @ReactMethod
  override fun setFakeGPSPolicy(policy: String, promise: Promise) {
    val allowed = listOf("skip", "warn", "stopTracking", "logToServer")
    if (policy !in allowed) {
      promise.reject("INVALID_ARGUMENTS", "policy must be one of ${allowed.joinToString(", ")}")
      return
    }
    fakeGPSPolicy = policy
    logDebug(TAG, "-> SDK setFakeGPSPolicy | \"$policy\"")
    try {
      vietmapSDK.setFakeGPSPolicy(policy)
      promise.resolve(true)
    } catch (e: Exception) {
      promise.reject("SET_FAKE_GPS_POLICY_ERROR", e.message)
    }
  }

  @ReactMethod
  override fun configureAlertAPI(apiKey: String, apiID: String, promise: Promise) {
    if (!isInitialized) {
      promise.reject("SDK_NOT_INITIALIZED", "VietmapTrackingSDK not initialized")
      return
    }

    try {
      // Configure alert API with VietmapTrackingSDK
      vietmapSDK.configureAlertAPI(apiKey, apiID)

      promise.resolve(true)

    } catch (e: Exception) {
      promise.reject("ALERT_CONFIG_FAILED", "Failed to configure Alert API: ${e.message}")
    }
  }

  @ReactMethod
  override fun requestLocationPermissions(promise: Promise) {
    try {
      // Check if we already have location permissions
      if (hasLocationPermission()) {
        val result = Arguments.createMap().apply {
          putBoolean("granted", true)
          putString("status", "granted")
        }
        promise.resolve(result)
        return
      }

      // Store the promise for callback when permission result comes back
      pendingLocationPermissionPromise = promise

      // Get current activity
      val activity = currentActivity
      if (activity == null) {
        promise.reject("NO_ACTIVITY", "No current activity available for permission request")
        return
      }

      // Check if activity implements PermissionAwareActivity
      if (activity !is PermissionAwareActivity) {
        promise.reject("INVALID_ACTIVITY", "Activity does not implement PermissionAwareActivity")
        return
      }

      // Foreground only. ACCESS_BACKGROUND_LOCATION must NOT be in this array.
      //
      // From Android 10 (API 29) the system refuses a request that asks for
      // background location alongside foreground, and it discards the WHOLE
      // request rather than the background part — the dialog is created and
      // dismissed within about 70ms, so the user sees nothing at all and every
      // permission comes back denied. Android says so itself:
      //
      //   E GrantPermissionsViewModel: For R+ apps, background permissions must
      //   be requested after foreground permissions are already granted
      //
      // Background is a second, separate request, which is what
      // requestAlwaysLocationPermissions() is for.
      val permissions = arrayOf(
        Manifest.permission.ACCESS_FINE_LOCATION,
        Manifest.permission.ACCESS_COARSE_LOCATION
      )

      logDebug(TAG, "-> requestPermissions | foreground only: ${permissions.joinToString()}")
      activity.requestPermissions(
        permissions,
        LOCATION_PERMISSION_REQUEST_CODE,
        createPermissionListener()
      )

    } catch (e: Exception) {
      promise.reject("PERMISSION_REQUEST_FAILED", "Failed to request location permissions: ${e.message}")
    }
  }

  // Create permission listener for handling permission results
  private fun createPermissionListener(): PermissionListener {
    return object : PermissionListener {
      override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<String>,
        grantResults: IntArray
      ): Boolean {
        when (requestCode) {
          LOCATION_PERMISSION_REQUEST_CODE -> {
            handleLocationPermissionResult(permissions, grantResults)
            return true
          }
          BACKGROUND_LOCATION_PERMISSION_REQUEST_CODE -> {
            handleBackgroundLocationPermissionResult(permissions, grantResults)
            return true
          }
          NOTIFICATION_PERMISSION_REQUEST_CODE -> {
            val granted = grantResults.isNotEmpty() &&
              grantResults[0] == PackageManager.PERMISSION_GRANTED
            pendingNotificationPermissionPromise?.resolve(granted)
            pendingNotificationPermissionPromise = null
            return true
          }
        }
        return false
      }
    }
  }

  private fun handleLocationPermissionResult(permissions: Array<String>, grantResults: IntArray) {
    // Check if this is from requestAlwaysLocationPermissions flow
    val isAlwaysPermissionFlow = pendingBackgroundPermissionPromise != null
    val promise = pendingLocationPermissionPromise ?: pendingBackgroundPermissionPromise

    if (promise == null) {
      return
    }

    try {
      var fineLocationGranted = false
      var coarseLocationGranted = false
      var backgroundLocationGranted = true // Default true for older Android versions

      // Check each permission result
      for (i in permissions.indices) {
        when (permissions[i]) {
          Manifest.permission.ACCESS_FINE_LOCATION -> {
            fineLocationGranted = grantResults[i] == PackageManager.PERMISSION_GRANTED
          }
          Manifest.permission.ACCESS_COARSE_LOCATION -> {
            coarseLocationGranted = grantResults[i] == PackageManager.PERMISSION_GRANTED
          }
          Manifest.permission.ACCESS_BACKGROUND_LOCATION -> {
            backgroundLocationGranted = grantResults[i] == PackageManager.PERMISSION_GRANTED
          }
        }
      }

      val allPermissionsGranted = fineLocationGranted && coarseLocationGranted

      // If this is from requestAlwaysLocationPermissions and basic permissions are granted
      if (isAlwaysPermissionFlow && allPermissionsGranted) {
        // Check if we need background permission for Android 10+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
          val currentBackgroundGranted = ContextCompat.checkSelfPermission(
            reactApplicationContext,
            Manifest.permission.ACCESS_BACKGROUND_LOCATION
          ) == PackageManager.PERMISSION_GRANTED

          if (!currentBackgroundGranted) {
            val activity = currentActivity
            if (activity != null) {
              ActivityCompat.requestPermissions(
                activity,
                arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION),
                BACKGROUND_LOCATION_PERMISSION_REQUEST_CODE
              )
              // Don't resolve promise yet, wait for background permission result
              return
            } else {
              promise.resolve("denied")
            }
          } else {
            // Background permission already granted
            promise.resolve("granted")
          }
        } else {
          // Android < 10, background permission not needed
          promise.resolve("granted")
        }
      } else if (isAlwaysPermissionFlow && !allPermissionsGranted) {
        // Basic permissions denied for always permission request
        promise.resolve("denied")
      } else {
        // Regular permission request, return PermissionResult
        val result = Arguments.createMap().apply {
          putBoolean("granted", allPermissionsGranted)
          putString("status", if (allPermissionsGranted) "granted" else "denied")
          putBoolean("fineLocation", fineLocationGranted)
          putBoolean("coarseLocation", coarseLocationGranted)
          putBoolean("backgroundLocation", backgroundLocationGranted)
        }

        if (allPermissionsGranted) {

          // Send permission granted event
          sendEvent("onPermissionChanged", Arguments.createMap().apply {
            putBoolean("granted", true)
            putString("type", "location")
          })
        } else {

          // Send permission denied event
          sendEvent("onPermissionChanged", Arguments.createMap().apply {
            putBoolean("granted", false)
            putString("type", "location")
          })
        }

        promise.resolve(result)
      }

    } catch (e: Exception) {
      if (isAlwaysPermissionFlow) {
        promise.resolve("denied")
      } else {
        promise.reject("PERMISSION_RESULT_ERROR", "Error handling permission result: ${e.message}")
      }
    } finally {
      // Only clear the regular permission promise, not the background one if in always flow
      if (!isAlwaysPermissionFlow || pendingLocationPermissionPromise != null) {
        pendingLocationPermissionPromise = null
      }
    }
  }

  private fun handleBackgroundLocationPermissionResult(permissions: Array<String>, grantResults: IntArray) {
    val promise = pendingBackgroundPermissionPromise
    if (promise == null) {
      return
    }

    try {
      var backgroundLocationGranted = false

      // Check background location permission result
      for (i in permissions.indices) {
        if (permissions[i] == Manifest.permission.ACCESS_BACKGROUND_LOCATION) {
          backgroundLocationGranted = grantResults[i] == PackageManager.PERMISSION_GRANTED
          break
        }
      }

      if (backgroundLocationGranted) {
        promise.resolve("granted")

        // Send permission granted event
        sendEvent("onPermissionChanged", Arguments.createMap().apply {
          putBoolean("granted", true)
          putString("type", "background_location")
        })
      } else {
        promise.resolve("denied")

        // Send permission denied event
        sendEvent("onPermissionChanged", Arguments.createMap().apply {
          putBoolean("granted", false)
          putString("type", "background_location")
        })
      }

    } catch (e: Exception) {
      promise.resolve("denied")
    } finally {
      pendingBackgroundPermissionPromise = null
    }
  }

  @ReactMethod
  override fun hasLocationPermissions(promise: Promise) {
    try {
      val hasPermissions = hasLocationPermission()

      val result = Arguments.createMap().apply {
        putBoolean("granted", hasPermissions)
        putString("status", if (hasPermissions) "granted" else "not_granted")
      }

      promise.resolve(result)
    } catch (e: Exception) {
      promise.reject("PERMISSION_CHECK_FAILED", "Failed to check location permissions: ${e.message}")
    }
  }

  @ReactMethod
  override fun requestAlwaysLocationPermissions(promise: Promise) {
    try {
      val activity = currentActivity
      if (activity == null) {
        promise.resolve("denied")
        return
      }

      // Check current permission status
      val hasFineLocation = ContextCompat.checkSelfPermission(
        reactApplicationContext,
        Manifest.permission.ACCESS_FINE_LOCATION
      ) == PackageManager.PERMISSION_GRANTED

      val hasCoarseLocation = ContextCompat.checkSelfPermission(
        reactApplicationContext,
        Manifest.permission.ACCESS_COARSE_LOCATION
      ) == PackageManager.PERMISSION_GRANTED

      // For Android 10+ (API 29+), check background location permission
      val hasBackgroundLocation = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        ContextCompat.checkSelfPermission(
          reactApplicationContext,
          Manifest.permission.ACCESS_BACKGROUND_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
      } else {
        true // Background location is automatically granted on older versions
      }

      // If we already have all permissions, return granted
      if (hasFineLocation && hasCoarseLocation && hasBackgroundLocation) {
        promise.resolve("granted")
        return
      }

      // Check if we need to request basic location permissions first
      if (!hasFineLocation || !hasCoarseLocation) {
        // Store the original promise to resolve later
        pendingBackgroundPermissionPromise = promise

        // Request basic location permissions first
        val permissionsToRequest = mutableListOf<String>()
        if (!hasFineLocation) {
          permissionsToRequest.add(Manifest.permission.ACCESS_FINE_LOCATION)
        }
        if (!hasCoarseLocation) {
          permissionsToRequest.add(Manifest.permission.ACCESS_COARSE_LOCATION)
        }

        ActivityCompat.requestPermissions(
          activity,
          permissionsToRequest.toTypedArray(),
          LOCATION_PERMISSION_REQUEST_CODE
        )
        return
      }

      // If basic permissions are granted but background is not (Android 10+)
      if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q && !hasBackgroundLocation) {

        // Store promise for background permission request
        pendingBackgroundPermissionPromise = promise

        ActivityCompat.requestPermissions(
          activity,
          arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION),
          BACKGROUND_LOCATION_PERMISSION_REQUEST_CODE
        )
        return
      }

      // All permissions are already granted
      promise.resolve("granted")

    } catch (e: Exception) {
      promise.resolve("denied")
    }
  }

  // MARK: - Tracking Methods

  /**
   * Start tracking from a config map.
   *
   * intervalMs and distanceFilter pick the SDK's trigger mode between them, and
   * a key that is absent means absent - it is not replaced with a number. The
   * three modes behave differently enough that collapsing them loses a feature:
   *
   *  - interval only   timer; a fix every intervalMs whether moving or not
   *  - distance only   displacement; a fix per distanceFilter metres
   *  - both            the SDK favours the timer and IGNORES the distance gate
   *  - neither         the SDK's own defaults, currently 10s / 25m
   *
   * The previous signature took both as required positional arguments, so every
   * start landed in the third case and distance-driven tracking was unreachable.
   */
  @ReactMethod
  override fun startTracking(config: ReadableMap, promise: Promise) {
    if (!isInitialized) {
      promise.reject("SDK_NOT_INITIALIZED", "VietmapTrackingSDK not initialized")
      return
    }

    try {
      val backgroundMode = config.optBoolean("backgroundMode", true)
      val allowMockLocation = config.optBoolean("allowMockLocation", true)
      val enableSpeedFallback = config.optBoolean("enableSpeedFallback", true)
      val accuracy = config.optString("accuracy", "high")
      val notificationTitle = config.optString("notificationTitle", null)
      val notificationMessage = config.optString("notificationMessage", null)
      val userId = config.optString("userId", "")?.trim().orEmpty()
      val vehicleId = config.optString("vehicleId", "")?.trim().orEmpty()

      if (userId.isEmpty()) {
        promise.reject("MISSING_USER_ID", "userId is required to start tracking")
        return
      }

      // Absent stays absent; these are the trigger selectors.
      val intervalMs = config.optLong("intervalMs")
      val distanceFilter = config.optDouble("distanceFilter")

      // Identity first: the SDK refuses to start without a userId and reports
      // it only through the status callback, where it is easy to miss.
      logDebug(TAG, "-> SDK setDriverId | \"$userId\" (len=${userId.length})")
      vietmapSDK.setDriverId(userId)
      cachedDriverId = userId
      if (vehicleId.isNotEmpty()) {
        logDebug(TAG, "-> SDK setVehicleId | \"$vehicleId\" (len=${vehicleId.length})")
        vietmapSDK.setVehicleId(vehicleId)
        cachedVehicleId = vehicleId
      }

      if (!notificationTitle.isNullOrEmpty()) {
        vietmapSDK.setNotificationTitle(notificationTitle)
      }
      if (!notificationMessage.isNullOrEmpty()) {
        vietmapSDK.setNotificationText(notificationMessage)
      }

      if (!allowMockLocation) {
        vietmapSDK.setFakeGPSPolicy(fakeGPSPolicy)
      }

      // Smart battery is opt-in. Left on by default it would immediately push
      // its own preset over whatever cadence tracking just started with.
      if (config.optBoolean("enableSmartBattery", false)) {
        applySmartBattery(true, config.optString("smartBatteryPreset", "general") ?: "general")
      }

      fun baseConfig(interval: Long, distance: Double) = TrackingConfig().apply {
        updateInterval = interval
        minDistanceFilter = distance
        enableBackgroundMode = backgroundMode
        this.accuracy = accuracy ?: "high"
        // Fake GPS gate. The SDK drops every fix flagged as a mock provider
        // while this is false - which is the TrackingConfig default - so on an
        // emulator, where every fix is mocked, nothing reaches tracking and the
        // upload batch goes out empty.
        this.allowMockLocation = allowMockLocation
        this.enableSpeedFallback = enableSpeedFallback
      }

      var bootstrapDistance: Double? = null
      val trackingConfig: TrackingConfig
      val mode: String

      when {
        intervalMs != null && distanceFilter == null -> {
          trackingConfig = baseConfig(intervalMs, 0.0)
          mode = "TIMER ONLY (${intervalMs}ms)"
        }
        distanceFilter != null && intervalMs == null -> {
          // Distance mode starts on a bootstrap config and switches to the real
          // filter once the first fix lands.
          //
          // Starting straight at the distance filter means smallestDisplacement
          // blocks the first fix while the device is still, the Foreground
          // Service misses its 5s promotion window, and tracking never starts at
          // all. The interval stays small in BOTH phases; only the distance
          // filter changes.
          trackingConfig = baseConfig(DISTANCE_MODE_INTERVAL_MS, 0.0)
          bootstrapDistance = distanceFilter
          mode = "DISTANCE ONLY (${distanceFilter}m, bootstrapping)"
        }
        intervalMs != null && distanceFilter != null -> {
          trackingConfig = baseConfig(intervalMs, distanceFilter)
          mode = "BOTH (${intervalMs}ms + ${distanceFilter}m) - SDK favours the timer"
        }
        else -> {
          // Neither supplied: do not touch the SDK's config at all, so its own
          // defaults stand. Pushing a TrackingConfig here would overwrite them
          // with this module's idea of a default.
          trackingConfig = TrackingConfig().apply {
            enableBackgroundMode = backgroundMode
            this.accuracy = accuracy ?: "high"
            this.allowMockLocation = allowMockLocation
            this.enableSpeedFallback = enableSpeedFallback
          }
          mode = "SDK DEFAULTS (${trackingConfig.updateInterval}ms / ${trackingConfig.minDistanceFilter}m)"
        }
      }

      logDebug(TAG,
        "-> SDK setTrackingConfig | mode=$mode " +
          "updateInterval=${trackingConfig.updateInterval} " +
          "minDistanceFilter=${trackingConfig.minDistanceFilter} " +
          "backgroundMode=${trackingConfig.enableBackgroundMode} " +
          "accuracy=${trackingConfig.accuracy} " +
          "allowMockLocation=${trackingConfig.allowMockLocation} " +
          "enableSpeedFallback=${trackingConfig.enableSpeedFallback} " +
          "| driverId=\"$cachedDriverId\" vehicleId=\"$cachedVehicleId\""
      )

      // Safe here: tracking is not running yet, so setTrackingConfig() cannot
      // trigger the Foreground Service restart described in
      // safeUpdateTrackingConfig().
      vietmapSDK.setTrackingConfig(trackingConfig)

      // Report what the SDK actually did. This used to discard the return value
      // and always resolve true, so a refused start still looked like success.
      val started = vietmapSDK.startTracking()
      logDebug(TAG, "<- SDK startTracking result | started=$started")
      if (started) {
        trackingStartTime = System.currentTimeMillis()
        bootstrapDistance?.let { registerDistanceBootstrapSwitch(it) }
      }
      promise.resolve(started)
    } catch (e: Exception) {
      Log.e(TAG, "startTracking failed", e)
      emitLocationError("startTracking failed: ${e.message}")
      promise.reject("START_TRACKING_ERROR", e.message, e)
    }
  }

  /**
   * One-shot: apply the real distance filter once the first fix proves the
   * Foreground Service is alive. safeUpdateTrackingConfig does not restart the
   * service, so this cannot trigger the crash that a plain setTrackingConfig
   * would.
   */
  private fun registerDistanceBootstrapSwitch(distanceFilter: Double) {
    clearDistanceBootstrapCallback()
    val callback = VietmapTrackingSDK.LocationUpdateCallback { _ ->
      // On the main thread, so several fixes arriving together cannot each
      // apply the switch.
      mainHandler.post {
        val current = distanceBootstrapCallback ?: return@post
        distanceBootstrapCallback = null
        try {
          vietmapSDK.removeLocationCallback(current)
        } catch (e: Exception) {
        }
        logDebug(TAG, "Distance bootstrap: first fix -> applying distanceFilter=${distanceFilter}m")
        safeUpdateTrackingConfig(DISTANCE_MODE_INTERVAL_MS, distanceFilter)
      }
    }
    distanceBootstrapCallback = callback
    vietmapSDK.addLocationCallback(callback)
  }

  /** Drop the one-shot callback if tracking stops before the first fix. */
  private fun clearDistanceBootstrapCallback() {
    distanceBootstrapCallback?.let {
      try {
        vietmapSDK.removeLocationCallback(it)
      } catch (e: Exception) {
      }
    }
    distanceBootstrapCallback = null
  }

  @ReactMethod
  override fun stopTracking(promise: Promise) {
    if (!isInitialized) {
      promise.resolve(false)
      return
    }

    try {
      // Stop tracking with VietmapTrackingSDK
      vietmapSDK.stopTracking()
      trackingStartTime = 0L
      promise.resolve(true)

    } catch (e: Exception) {
      promise.resolve(false)
    }
  }

  /**
   * Resolve an on-demand fix. Works before startTracking(): the SDK falls back
   * through in-memory cache, system last-known, then a fresh active fix.
   *
   * This used to return a hardcoded 0,0 on the assumption that the SDK had no
   * getCurrentLocation(). It has had one since 1.4.7.
   *
   * maxAgeMs / timeoutMs are not exposed to JS yet - see Phase 3.
   */
  @ReactMethod
  override fun getCurrentLocation(promise: Promise) {
    if (!isInitialized) {
      promise.reject("NOT_INITIALIZED", "VietmapTrackingSDK not initialized")
      return
    }

    try {
      vietmapSDK.getCurrentLocation(
        DEFAULT_LOCATION_MAX_AGE_MS,
        DEFAULT_LOCATION_TIMEOUT_MS,
        object : VietmapTrackingSDK.LocationResultCallback {
          override fun onResult(location: VMLocation, source: String, ageMs: Long) {
            val payload = Arguments.createMap().apply {
              putDouble("latitude", location.lat)
              putDouble("longitude", location.lng)
              putDouble("altitude", location.altitude)
              putDouble("accuracy", location.accuracy)
              putDouble("speed", location.speed)
              putDouble("bearing", location.bearing)
              putDouble("timestamp", location.timestamp.toDouble())
              putString("source", source)
              putDouble("ageMs", ageMs.toDouble())
            }
            promise.resolve(payload)
          }

          override fun onError(code: String, message: String) {
            emitLocationError("$code: $message")
            // SDK error codes: LOCATION_PERMISSION_DENIED, LOCATION_DISABLED,
            // LOCATION_TIMEOUT. Passed through untouched.
            promise.reject(code, message)
          }
        }
      )
    } catch (e: Exception) {
      promise.reject("LOCATION_ERROR", "Failed to get current location: ${e.message}")
    }
  }

  @ReactMethod
  override fun isTrackingActive(promise: Promise) {
    if (!isInitialized) {
      promise.reject("SDK_NOT_INITIALIZED", "VietmapTrackingSDK not initialized")
      return
    }

    try {
      // Check tracking status with VietmapTrackingSDK
      val isActive = vietmapSDK.isTracking()
      promise.resolve(isActive)

    } catch (e: Exception) {
      promise.reject("STATUS_ERROR", "Failed to check tracking status: ${e.message}")
    }
  }

  @ReactMethod
  override fun getTrackingStatus(promise: Promise) {
    if (!isInitialized) {
      promise.reject("SDK_NOT_INITIALIZED", "VietmapTrackingSDK not initialized")
      return
    }

    try {
      // The Android SDK has no getTrackingStatus() of its own, so the module
      // assembles the TrackingStatus shape from state it already keeps. iOS gets
      // the same three fields from the SDK, already in milliseconds.
      //
      // This used to return isTracking, a "status" string and a timestamp, and
      // none of the fields the type declares - so `status.trackingDuration` was
      // undefined on Android while the type marked it required, and any caller
      // doing arithmetic on it got NaN. The Flutter plugin has assembled these
      // correctly all along; this brings React Native level with it.
      val isActive = vietmapSDK.isTracking()
      val now = System.currentTimeMillis()

      val status = Arguments.createMap().apply {
        putBoolean("isTracking", isActive)
        putDouble(
          "trackingDuration",
          if (isActive && trackingStartTime > 0L) (now - trackingStartTime).toDouble() else 0.0
        )
        // Left out entirely when no fix has arrived, which is what makes it
        // optional in the type. iOS answers NSNull() in the same case.
        if (lastLocationTimestamp > 0L) {
          putDouble("lastLocationUpdate", lastLocationTimestamp.toDouble())
        }
      }

      promise.resolve(status)

    } catch (e: Exception) {
      promise.reject("STATUS_ERROR", "Failed to get tracking status: ${e.message}")
    }
  }

  @ReactMethod
  override fun updateTrackingConfig(config: ReadableMap, promise: Promise) {
    if (!isInitialized) {
      promise.reject("SDK_NOT_INITIALIZED", "VietmapTrackingSDK not initialized")
      return
    }

    try {
      // Update configuration if tracking is active
      val isActive = vietmapSDK.isTracking()
      if (isActive) {
        val intervalMs = if (config.hasKey("intervalMs") && !config.isNull("intervalMs")) {
          config.getDouble("intervalMs").toLong()
        } else {
          0L
        }
        val distanceFilter = if (config.hasKey("distanceFilter") && !config.isNull("distanceFilter")) {
          config.getDouble("distanceFilter")
        } else {
          0.0
        }

        // backgroundMode is deliberately ignored while tracking: applying it
        // calls setEnhancedBackgroundMode(), which starts the background
        // service a second time. It is fixed at startTracking().
        safeUpdateTrackingConfig(intervalMs, distanceFilter)
        promise.resolve(true)
      } else {
        promise.resolve(false)
      }
    } catch (e: Exception) {
      promise.reject("CONFIG_UPDATE_ERROR", "Failed to update tracking config: ${e.message}")
    }
  }

  /**
   * Change interval and distance filter WITHOUT restarting the Foreground
   * Service.
   *
   * setTrackingConfig() internally runs:
   *   1. setTrackingInterval()        - safe, only re-registers FusedLocation
   *   2. setDistanceFilter()          - UNSAFE: does stopTracking() +
   *      startTracking(), which destroys and re-creates the Foreground Service
   *      and throws ForegroundServiceDidNotStartInTimeException on rapid
   *      config changes
   *   3. setEnhancedBackgroundMode()  - UNSAFE while isTracking: calls
   *      startBackgroundService() again
   *
   * So this reaches past the public API: call the safe setTrackingInterval(),
   * write the distanceFilter field directly, then apply it with
   * updateLocationRequest(). enhancedBackgroundMode is left alone.
   *
   * If reflection fails (renamed fields in a future SDK), log and return. Do
   * NOT fall back to setTrackingConfig() - that is the crash being avoided.
   */
  private fun safeUpdateTrackingConfig(intervalMs: Long, distanceFilter: Double) {
    try {
      val tmField = vietmapSDK.javaClass.getDeclaredField("trackingManager")
      tmField.isAccessible = true
      val trackingManager = tmField.get(vietmapSDK)
        ?: throw IllegalStateException("trackingManager is null")

      if (intervalMs > 0L) {
        trackingManager.javaClass
          .getMethod("setTrackingInterval", Long::class.java)
          .invoke(trackingManager, intervalMs)
      }

      val dfField = trackingManager.javaClass.getDeclaredField("distanceFilter")
      dfField.isAccessible = true
      dfField.setFloat(trackingManager, distanceFilter.toFloat())

      val updateMethod = trackingManager.javaClass.getDeclaredMethod("updateLocationRequest")
      updateMethod.isAccessible = true
      updateMethod.invoke(trackingManager)

      logDebug(TAG, "safeUpdateTrackingConfig | interval=${intervalMs}ms distance=${distanceFilter}m")
    } catch (e: Exception) {
      Log.e(TAG, "safeUpdateTrackingConfig reflection failed: ${e.message}", e)
    }
  }

  // MARK: - Alert Management Methods
  @ReactMethod
  override fun turnOnAlert(promise: Promise) {
    if (!isInitialized) {
      promise.reject("SDK_NOT_INITIALIZED", "VietmapTrackingSDK not initialized")
      return
    }


    try {
      // Turn on alert with VietmapTrackingSDK
      val success = vietmapSDK.startAlert()

      if (success) {
        promise.resolve(true)
      } else {
        promise.resolve(false)
      }

    } catch (e: Exception) {
      promise.resolve(false)
    }
  }

  @ReactMethod
  override fun turnOffAlert(promise: Promise) {
    if (!isInitialized) {
      promise.reject("SDK_NOT_INITIALIZED", "VietmapTrackingSDK not initialized")
      return
    }

    try {
      // Turn off alert with VietmapTrackingSDK
      val success = vietmapSDK.stopAlert()

      if (success) {
        promise.resolve(true)
      } else {
        promise.resolve(false)
      }

    } catch (e: Exception) {
      promise.resolve(false)
    }
  }


  // MARK: - Identity payload

  @ReactMethod
  override fun setMetadata(metadata: ReadableMap, promise: Promise) {
    if (!isInitialized) {
      promise.reject("SDK_NOT_INITIALIZED", "VietmapTrackingSDK not initialized")
      return
    }
    try {
      val map = metadata.toHashMap()
      logDebug(TAG, "-> SDK setMetadata | ${map.size} keys")
      vietmapSDK.setMetadata(map)
      promise.resolve(true)
    } catch (e: Exception) {
      promise.reject("SET_METADATA_ERROR", e.message, e)
    }
  }

  @ReactMethod
  override fun setPackages(packages: ReadableArray, promise: Promise) {
    if (!isInitialized) {
      promise.reject("SDK_NOT_INITIALIZED", "VietmapTrackingSDK not initialized")
      return
    }
    try {
      // Reject a non-string entry rather than coercing it: a package code that
      // silently became "1" would be accepted by the server and be wrong in the
      // data.
      val list = ArrayList<String>(packages.size())
      for (i in 0 until packages.size()) {
        val value = packages.getString(i)
        if (value == null) {
          promise.reject("INVALID_ARGUMENTS", "packages must be an array of strings")
          return
        }
        list.add(value)
      }
      logDebug(TAG, "-> SDK setPackages | $list")
      vietmapSDK.setPackages(list)
      promise.resolve(true)
    } catch (e: Exception) {
      promise.reject("SET_PACKAGES_ERROR", e.message, e)
    }
  }

  @ReactMethod
  override fun setAppSignature(signature: String, promise: Promise) {
    if (!isInitialized) {
      promise.reject("SDK_NOT_INITIALIZED", "VietmapTrackingSDK not initialized")
      return
    }
    try {
      logDebug(TAG, "-> SDK setAppSignature | (len=${signature.length})")
      vietmapSDK.setAppSignature(signature)
      promise.resolve(true)
    } catch (e: Exception) {
      promise.reject("SET_APP_SIGNATURE_ERROR", e.message, e)
    }
  }

  @ReactMethod
  override fun configureVehicle(
    vehicleId: String,
    vehicleType: Double,
    seats: Double,
    weight: Double,
    maxProvision: Double?,
    promise: Promise
  ) {
    if (!isInitialized) {
      promise.reject("SDK_NOT_INITIALIZED", "VietmapTrackingSDK not initialized")
      return
    }
    try {
      val provision = maxProvision?.toInt() ?: 0
      logDebug(TAG,
        "-> SDK configureVehicle | id=$vehicleId type=${vehicleType.toInt()} " +
          "seats=${seats.toInt()} weight=$weight maxProvision=$provision"
      )
      vietmapSDK.configureVehicle(vehicleId, vehicleType.toInt(), seats.toInt(), weight, provision)
      promise.resolve(true)
    } catch (e: Exception) {
      promise.reject("CONFIGURE_VEHICLE_ERROR", e.message, e)
    }
  }

  // MARK: - Offline cache and upload

  @ReactMethod
  override fun isNetworkConnected(promise: Promise) {
    try {
      // Named isNetworkAvailable on Android, isNetworkConnected on iOS.
      promise.resolve(vietmapSDK.isNetworkAvailable())
    } catch (e: Exception) {
      promise.resolve(false)
    }
  }

  @ReactMethod
  override fun getCachedLocationsCount(promise: Promise) {
    try {
      promise.resolve(vietmapSDK.getCachedLocationsCount())
    } catch (e: Exception) {
      promise.resolve(0)
    }
  }

  /**
   * Drain the cache now.
   *
   * The Android SDK method returns void and takes no callback, unlike iOS which
   * reports success through a completion. So this resolves true once the call
   * returns, which means the upload was started, not that it landed. Callers
   * check getCachedLocationsCount() afterwards to see what actually drained.
   */
  @ReactMethod
  override fun uploadCachedLocationsManually(promise: Promise) {
    if (!isInitialized) {
      promise.reject("SDK_NOT_INITIALIZED", "VietmapTrackingSDK not initialized")
      return
    }
    try {
      logDebug(TAG, "-> SDK uploadCachedLocationsManually | pending=${vietmapSDK.getCachedLocationsCount()}")
      vietmapSDK.uploadCachedLocationsManually()
      promise.resolve(true)
    } catch (e: Exception) {
      promise.reject("UPLOAD_CACHE_ERROR", e.message, e)
    }
  }

  @ReactMethod
  override fun clearCachedLocations(promise: Promise) {
    if (!isInitialized) {
      promise.reject("SDK_NOT_INITIALIZED", "VietmapTrackingSDK not initialized")
      return
    }
    try {
      logDebug(TAG, "-> SDK clearCachedLocations | discarding ${vietmapSDK.getCachedLocationsCount()} pending")
      vietmapSDK.clearCachedLocations()
      promise.resolve(true)
    } catch (e: Exception) {
      promise.reject("CLEAR_CACHE_ERROR", e.message, e)
    }
  }

  /**
   * A zero keeps the SDK's own value for that field, and those differ per
   * platform: maxRecords is 5000 here and 10000 on iOS, while maxDbSizeBytes
   * (50MB) and batchSize (50) match.
   *
   * maxDbSizeBytes crosses the bridge as a Double because it exceeds 2^31 and
   * the bridge has no 64-bit integer type.
   */
  @ReactMethod
  override fun configureCacheLimits(
    maxRecords: Double,
    maxDbSizeBytes: Double,
    batchSize: Double,
    promise: Promise
  ) {
    if (!isInitialized) {
      promise.reject("SDK_NOT_INITIALIZED", "VietmapTrackingSDK not initialized")
      return
    }
    try {
      logDebug(TAG,
        "-> SDK configureCacheLimits | maxRecords=${maxRecords.toInt()} " +
          "maxDbSizeBytes=${maxDbSizeBytes.toLong()} batchSize=${batchSize.toInt()}"
      )
      vietmapSDK.configureCacheLimits(maxRecords.toInt(), maxDbSizeBytes.toLong(), batchSize.toInt())
      promise.resolve(true)
    } catch (e: Exception) {
      promise.reject("CONFIGURE_CACHE_LIMITS_ERROR", e.message, e)
    }
  }

  @ReactMethod
  override fun getDatabaseSizeBytes(promise: Promise) {
    try {
      // Long -> Double for the bridge. A 50MB cap is far inside the range a
      // double represents exactly, so nothing is lost.
      promise.resolve(vietmapSDK.getDatabaseSizeBytes().toDouble())
    } catch (e: Exception) {
      promise.resolve(0.0)
    }
  }

  // MARK: - Lifecycle, exposed for a host that manages app state itself

  @ReactMethod
  override fun onAppBackground(promise: Promise) {
    logDebug(LIFECYCLE_TAG, "onAppBackground called from JS t=${SystemClock.elapsedRealtime()}")
    try {
      if (isInitialized) vietmapSDK.onAppBackground()
      promise.resolve(true)
    } catch (e: Exception) {
      promise.resolve(false)
    }
  }

  @ReactMethod
  override fun onAppForeground(promise: Promise) {
    logDebug(LIFECYCLE_TAG, "onAppForeground called from JS t=${SystemClock.elapsedRealtime()}")
    try {
      if (isInitialized) vietmapSDK.onAppForeground()
      promise.resolve(true)
    } catch (e: Exception) {
      promise.resolve(false)
    }
  }

  /**
   * iOS has a native setting for this. The Android SDK has none - uploads are
   * always automatic there - so this acknowledges the call and changes nothing,
   * keeping cross-platform code identical. Same choice the Flutter plugin makes.
   */
  @ReactMethod
  override fun setAutoUpload(enabled: Boolean, promise: Promise) {
    logDebug(TAG, "setAutoUpload($enabled) is a no-op on Android; uploads are always automatic")
    promise.resolve(true)
  }

  // MARK: - Notification permission
  //
  // The SDK posts the fake-GPS and tracking-interrupted notifications itself and
  // creates its own channel, so the only thing missing on Android is the runtime
  // grant. POST_NOTIFICATIONS became a runtime permission in API 33; below that
  // the manifest declaration is enough and there is nothing to ask for.

  @ReactMethod
  override fun requestNotificationPermission(promise: Promise) {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
      // Nothing to request below API 33 - granted by installing the app.
      promise.resolve(true)
      return
    }
    if (hasNotificationPermissionGranted()) {
      promise.resolve(true)
      return
    }

    val activity = currentActivity
    if (activity == null) {
      promise.reject("ACTIVITY_UNAVAILABLE", "Cannot request permissions without an Activity")
      return
    }
    if (activity !is PermissionAwareActivity) {
      promise.reject("INVALID_ACTIVITY", "Activity does not implement PermissionAwareActivity")
      return
    }

    // A second request while one is in flight would strand the first promise,
    // which never settles and leaves the caller awaiting forever.
    pendingNotificationPermissionPromise?.let {
      promise.reject("REQUEST_IN_FLIGHT", "A notification permission request is already running")
      return
    }
    pendingNotificationPermissionPromise = promise

    try {
      activity.requestPermissions(
        arrayOf(Manifest.permission.POST_NOTIFICATIONS),
        NOTIFICATION_PERMISSION_REQUEST_CODE,
        createPermissionListener()
      )
    } catch (e: Exception) {
      pendingNotificationPermissionPromise = null
      promise.reject("PERMISSION_REQUEST_ERROR", e.message, e)
    }
  }

  @ReactMethod
  override fun hasNotificationPermission(promise: Promise) {
    promise.resolve(hasNotificationPermissionGranted())
  }

  private fun hasNotificationPermissionGranted(): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
      return true
    }
    return ContextCompat.checkSelfPermission(
      reactApplicationContext,
      Manifest.permission.POST_NOTIFICATIONS
    ) == PackageManager.PERMISSION_GRANTED
  }

  // MARK: - Fake GPS notification

  @ReactMethod
  override fun setFakeGpsNotificationConfig(title: String, message: String, promise: Promise) {
    try {
      // The native parameter is `body`; the JS name stays `message` to match
      // the rest of this surface.
      logDebug(TAG, "-> SDK setFakeGPSNotificationConfig | title=\"$title\" body=\"$message\"")
      vietmapSDK.setFakeGPSNotificationConfig(title, message)
      promise.resolve(true)
    } catch (e: Exception) {
      promise.reject("SET_FAKE_GPS_NOTIFICATION_ERROR", e.message, e)
    }
  }

  // MARK: - Tracking interrupted

  /**
   * Show or hide the interruption notification. This does NOT silence the
   * onTrackingInterrupted event; the callback channel fires either way.
   */
  @ReactMethod
  override fun setTrackingInterruptedNotificationEnabled(enabled: Boolean, promise: Promise) {
    try {
      logDebug(TAG, "-> SDK setTrackingInterruptedNotificationEnabled | $enabled")
      vietmapSDK.setTrackingInterruptedNotificationEnabled(enabled)
      promise.resolve(true)
    } catch (e: Exception) {
      promise.reject("SET_INTERRUPTED_NOTIFICATION_ERROR", e.message, e)
    }
  }

  @ReactMethod
  override fun setTrackingInterruptedNotificationConfig(
    title: String,
    message: String,
    promise: Promise
  ) {
    try {
      logDebug(TAG, "-> SDK setTrackingInterruptedNotificationConfig | title=\"$title\" body=\"$message\"")
      vietmapSDK.setTrackingInterruptedNotificationConfig(title, message)
      promise.resolve(true)
    } catch (e: Exception) {
      promise.reject("SET_INTERRUPTED_NOTIFICATION_CONFIG_ERROR", e.message, e)
    }
  }

  // MARK: - Smart battery

  /**
   * Neither SDK exposes a smart battery setting, so it is assembled here.
   *
   * The preset only changes the interval, and it goes through
   * safeUpdateTrackingConfig rather than setTrackingConfig: the SDK's own
   * setter stops and restarts tracking, which restarts the Foreground Service
   * and crashes with ForegroundServiceDidNotStartInTimeException.
   *
   * Always interval-only - a displacement filter alongside the timer would be
   * ignored by the SDK anyway.
   */
  private fun applySmartBattery(enabled: Boolean, preset: String) {
    smartBatteryEnabled = enabled
    smartBatteryPreset = preset

    val intervalMs = SMART_BATTERY_INTERVALS_MS[preset]
    if (!enabled || intervalMs == null) {
      logDebug(TAG, "-> smart battery | enabled=$enabled preset=$preset (no interval change)")
      return
    }
    if (!vietmapSDK.isTracking()) {
      logDebug(TAG, "-> smart battery | preset=$preset stored; applies on the next start")
      return
    }
    logDebug(TAG, "-> smart battery | preset=$preset interval=${intervalMs}ms")
    safeUpdateTrackingConfig(intervalMs, 0.0)
  }

  @ReactMethod
  override fun setSmartBatteryConfig(enabled: Boolean, preset: String, promise: Promise) {
    if (!isInitialized) {
      promise.reject("SDK_NOT_INITIALIZED", "VietmapTrackingSDK not initialized")
      return
    }
    if (!SMART_BATTERY_INTERVALS_MS.containsKey(preset)) {
      promise.reject(
        "INVALID_ARGUMENTS",
        "preset must be one of ${SMART_BATTERY_INTERVALS_MS.keys.sorted().joinToString(", ")}"
      )
      return
    }
    try {
      applySmartBattery(enabled, preset)
      promise.resolve(true)
    } catch (e: Exception) {
      promise.reject("SET_SMART_BATTERY_ERROR", e.message, e)
    }
  }

  // MARK: - External GPS injection

  /**
   * The Android SDK has no processExternalLocation; it exposes the same
   * behaviour as processLocationWithVehicleParams, which is what the Flutter
   * plugin calls here too.
   *
   * speed at or below 30 is read by the SDK as m/s and converted once; above
   * that it is taken as km/h.
   */
  @ReactMethod
  override fun processExternalLocation(
    lat: Double,
    lng: Double,
    speed: Double,
    heading: Double,
    promise: Promise
  ) {
    if (!isInitialized) {
      promise.reject("SDK_NOT_INITIALIZED", "VietmapTrackingSDK not initialized")
      return
    }
    try {
      logDebug(TAG, "-> SDK processLocationWithVehicleParams | lat=$lat lng=$lng speed=$speed heading=$heading")
      vietmapSDK.processLocationWithVehicleParams(lat, lng, speed, heading)
      promise.resolve(true)
    } catch (e: Exception) {
      promise.reject("EXTERNAL_LOCATION_ERROR", e.message, e)
    }
  }

  // MARK: - History and health

  /**
   * Server-side history. Resolves the SDK's raw JSON; the wrapper in index.tsx
   * parses it.
   *
   * Timestamps arrive as Double because the bridge has no 64-bit integer, and
   * are in milliseconds - the SDK treats a value under 10 billion as seconds
   * and converts it, so seconds would shift the window by decades.
   */
  @ReactMethod
  override fun getTrackingHistory(
    userId: String,
    fromTimestamp: Double?,
    toTimestamp: Double?,
    pageNumber: Double?,
    pageSize: Double?,
    sortBy: String?,
    sortDescending: Boolean?,
    promise: Promise
  ) {
    if (!isInitialized) {
      promise.reject("SDK_NOT_INITIALIZED", "VietmapTrackingSDK not initialized")
      return
    }
    if (userId.isBlank()) {
      promise.reject("INVALID_ARGUMENTS", "userId is required")
      return
    }
    try {
      val from = fromTimestamp?.toLong() ?: 0L
      val to = toTimestamp?.toLong() ?: System.currentTimeMillis()
      val page = pageNumber?.toInt() ?: 1
      val size = pageSize?.toInt() ?: 100
      logDebug(TAG,
        "-> SDK getHistory | userId=$userId from=$from to=$to page=$page size=$size " +
          "sortBy=${sortBy ?: ""} desc=${sortDescending ?: false}"
      )
      vietmapSDK.getHistory(
        userId, from, to, page, size, sortBy ?: "", sortDescending ?: false,
        object : VietmapTrackingSDK.HistoryCallback {
          override fun onHistorySuccess(historyJson: String?) {
            logDebug(TAG, "<- SDK getHistory | bytes=${historyJson?.length ?: 0}")
            promise.resolve(historyJson ?: "")
          }

          override fun onHistoryError(errorCode: String?, message: String?) {
            Log.w(TAG, "<- SDK getHistory error | $errorCode: $message")
            promise.reject(errorCode ?: "HISTORY_ERROR", message ?: "Failed to fetch history")
          }
        }
      )
    } catch (e: Exception) {
      promise.reject("HISTORY_ERROR", e.message, e)
    }
  }

  /**
   * The Android SDK has no getTrackingHealthStatus, unlike iOS, so the module
   * assembles it from state it already keeps. -1 for timeSinceLastUpdate means
   * no fix has arrived yet, matching the Flutter plugin.
   */
  @ReactMethod
  override fun getTrackingHealthStatus(promise: Promise) {
    try {
      val now = System.currentTimeMillis()
      val isActive = isInitialized && vietmapSDK.isTracking()
      val result = Arguments.createMap().apply {
        putBoolean("isTracking", isActive)
        putBoolean("hasLocationPermission", hasLocationPermission())
        putBoolean("hasBackgroundPermission", hasBackgroundLocationPermission())
        putDouble(
          "trackingDuration",
          if (isActive && trackingStartTime > 0L) (now - trackingStartTime).toDouble() else 0.0
        )
        putDouble(
          "timeSinceLastUpdate",
          if (lastLocationTimestamp > 0L) (now - lastLocationTimestamp).toDouble() else -1.0
        )
        putBoolean("isInitialized", isInitialized)
        if (lastLocationTimestamp > 0L) {
          putDouble("lastLocationUpdate", lastLocationTimestamp.toDouble())
        }
        putDouble("timestamp", now.toDouble())
      }
      promise.resolve(result)
    } catch (e: Exception) {
      promise.reject("HEALTH_STATUS_ERROR", e.message, e)
    }
  }

  @ReactMethod
  override fun getPlatformVersion(promise: Promise) {
    promise.resolve("Android ${Build.VERSION.RELEASE}")
  }

  // MARK: - NativeEventEmitter conformance
  //
  // NativeEventEmitter requires these on the module it wraps and warns on every
  // launch when they are missing:
  //
  //   `new NativeEventEmitter()` was called with a non-null argument without
  //   the required `addListener` method.
  //
  // Events themselves go out through DeviceEventManagerModule, which needs no
  // registration, so these carry no logic. They exist so the emitter has the
  // interface it checks for.

  @ReactMethod
  override fun addListener(eventName: String) {
    // Required by NativeEventEmitter; DeviceEventManagerModule needs no setup.
  }

  @ReactMethod
  override fun removeListeners(count: Double) {
    // Required by NativeEventEmitter; DeviceEventManagerModule needs no setup.
  }

  // MARK: - Cleanup
  override fun invalidate() {
    super.invalidate()
    // Unregister callbacks before stopping so no event fires into a dead bridge.
    clearSDKCallbacks()
    clearDistanceBootstrapCallback()
    try {
      reactApplicationContext.removeLifecycleEventListener(this)
    } catch (e: Exception) {
    }
    if (isInitialized) {
      try {
        vietmapSDK.stopTracking()
      } catch (e: Exception) {
      }
    }
    trackingStartTime = 0L
  }

  // ============================================================
  // [ALERT-HIDDEN] findNearestAlert
  //
  // Hidden, not removed. It never queried the alert engine - it echoed the
  // input coordinates back with a placeholder string, so every caller got fake
  // data. It also sits outside the tracking surface the Flutter plugin exposes.
  // Restore this block if the alert surface is brought back, and implement it
  // against VietmapSpeedAlertManager rather than returning a literal.
  // ============================================================

  // @ReactMethod
  // fun findNearestAlert(latitude: Double, longitude: Double, promise: Promise) {
  //   if (!isInitialized) {
  //     promise.reject("SDK_NOT_INITIALIZED", "VietmapTrackingSDK not initialized")
  //     return
  //   }
  //
  //   try {
  //     val alertInfo = Arguments.createMap().apply {
  //       putDouble("latitude", latitude)
  //       putDouble("longitude", longitude)
  //       putString("routeInfo", "Alert data handled by VietmapTrackingSDK")
  //       putDouble("timestamp", System.currentTimeMillis().toDouble())
  //     }
  //     promise.resolve(alertInfo)
  //   } catch (e: Exception) {
  //     promise.reject("NO_ROUTE_DATA", "No route data available for alert calculation")
  //   }
  // }
}

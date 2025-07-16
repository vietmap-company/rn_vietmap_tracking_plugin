package com.rnvietmaptrackingplugin

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.speech.tts.TextToSpeech
import android.util.Log
import androidx.annotation.RequiresApi
import androidx.annotation.RequiresPermission
import androidx.core.content.ContextCompat
import androidx.core.app.ActivityCompat
import com.facebook.react.bridge.*
import com.facebook.react.modules.core.DeviceEventManagerModule
import com.facebook.react.modules.core.PermissionAwareActivity
import com.facebook.react.modules.core.PermissionListener
import com.google.android.gms.location.*
import com.google.android.gms.location.LocationServices
import com.google.android.gms.tasks.OnCompleteListener
import java.util.Timer
import java.util.TimerTask
import java.util.Locale
import okhttp3.*
import org.json.JSONObject
import org.json.JSONArray
import kotlin.math.*

class RnVietmapTrackingPluginModule(reactContext: ReactApplicationContext) :
  ReactContextBaseJavaModule(reactContext) {

  override fun getName(): String {
    return NAME
  }

  private var fusedLocationClient: FusedLocationProviderClient? = null
  private var locationRequest: LocationRequest? = null
  private var locationCallback: LocationCallback? = null
  private var isTracking = false
  private var trackingStartTime: Long = 0
  private var lastLocationUpdate: Long = 0
  private var backgroundLocationService: Intent? = null
  private var intervalMs: Long = 5000 // Default 5 seconds
  private var backgroundMode = false
  private var forceUpdateBackground = false // New option for forced updates
  private var distanceFilter = 10.0 // Default 10 meters
  private var locationTimer: Timer? = null // Timer for forced updates
  private var currentConfig: ReadableMap? = null

  // Permission request handling
  private var permissionPromise: Promise? = null
  private var pendingAlertPromise: Promise? = null
  private var isSpeedAlertActive = false

  // MARK: - Text-to-Speech for Speed Alerts
  private var textToSpeech: TextToSpeech? = null
  private var lastSpeedAlertTime: Long = 0
  private val speedAlertCooldown: Long = 5000 // 5 seconds cooldown between alerts

  // Route and Alert Data
  private var currentRouteData: ReadableMap? = null
  private var currentAlerts: ReadableArray? = null
  private var routeOffset: ReadableArray? = null

  // Route Boundary Detection & API Management
  private var currentLinkIndex: Int? = null
  private var previousLinkSpeedLimit: Int? = null // Track previous link's speed limit
  private var routeBoundaryThreshold: Double = 50.0 // meters
  private var lastAPIRequestLocation: Location? = null
  private var apiRequestInProgress: Boolean = false
  private var routeAPIEndpoint: String? = null

  init {
    fusedLocationClient = LocationServices.getFusedLocationProviderClient(reactContext)

    // Initialize Text-to-Speech
    textToSpeech = TextToSpeech(reactContext) { status ->
      if (status == TextToSpeech.SUCCESS) {
        // Set language to Vietnamese (fallback to English if not available)
        val result = textToSpeech?.setLanguage(Locale("vi", "VN"))
        if (result == TextToSpeech.LANG_MISSING_DATA || result == TextToSpeech.LANG_NOT_SUPPORTED) {
          Log.w(NAME, "Vietnamese language not supported, using English")
          textToSpeech?.setLanguage(Locale.ENGLISH)
        }
        Log.d(NAME, "✅ Text-to-Speech initialized successfully")
      } else {
        Log.e(NAME, "❌ Text-to-Speech initialization failed")
      }
    }
  }

  override fun onCatalystInstanceDestroy() {
    super.onCatalystInstanceDestroy()
    // Clean up Text-to-Speech
    textToSpeech?.stop()
    textToSpeech?.shutdown()
    textToSpeech = null
    Log.d(NAME, "🔄 Text-to-Speech cleaned up")
  }

  // Example method
  @ReactMethod
  fun multiply(a: Double, b: Double): Double {
    return a * b
  }

  @ReactMethod
  fun getCurrentLocation(promise: Promise) {
    if (!hasLocationPermissions()) {
      promise.reject("PERMISSION_DENIED", "Location permissions are required")
      return
    }

    if (ContextCompat.checkSelfPermission(reactApplicationContext, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
      fusedLocationClient?.lastLocation?.addOnCompleteListener { task ->
        if (task.isSuccessful && task.result != null) {
          val location = task.result
          promise.resolve(createLocationMap(location))
        } else {
          promise.reject("LOCATION_UNAVAILABLE", "Unable to get current location")
        }
      }
    } else {
      promise.reject("PERMISSION_DENIED", "Location permissions are required")
    }
  }

  @ReactMethod
  fun isTrackingActive(): Boolean {
    return isTracking
  }

  @ReactMethod
  fun getTrackingStatus(promise: Promise) {
    val status = Arguments.createMap().apply {
      putBoolean("isTracking", isTracking)
      if (lastLocationUpdate > 0) {
        putDouble("lastLocationUpdate", lastLocationUpdate.toDouble())
      }
      putDouble("trackingDuration", if (isTracking) (System.currentTimeMillis() - trackingStartTime).toDouble() else 0.0)
    }
    promise.resolve(status)
  }

  @ReactMethod
  fun updateTrackingConfig(config: ReadableMap, promise: Promise) {
    if (!isTracking) {
      promise.reject("NOT_TRACKING", "Location tracking is not active")
      return
    }

    try {
      // Update interval if provided
      if (config.hasKey("intervalMs")) {
        intervalMs = config.getInt("intervalMs").toLong()
        println("🔄 Updated tracking interval to: ${intervalMs}ms")
      }

      // Update background mode if provided
      if (config.hasKey("backgroundMode")) {
        backgroundMode = config.getBoolean("backgroundMode")
        println("🔄 Updated background mode to: $backgroundMode")
      }

      promise.resolve(true)
    } catch (e: Exception) {
      promise.reject("ERROR", e.message)
    }
  }

  @ReactMethod
  fun requestLocationPermissions(promise: Promise) {
    println("🔐 Requesting location permissions...")

    if (hasLocationPermissions()) {
      println("✅ Permissions already granted")
      promise.resolve("granted")
      return
    }

    // Store promise for callback
    permissionPromise = promise

    val activity = reactApplicationContext.currentActivity
    if (activity == null) {
      println("❌ No current activity available")
      promise.reject("NO_ACTIVITY", "No current activity available for permission request")
      permissionPromise = null
      return
    }

    if (activity is PermissionAwareActivity) {
      val permissionAwareActivity = activity as PermissionAwareActivity

      val permissions = arrayOf(
        Manifest.permission.ACCESS_FINE_LOCATION,
        Manifest.permission.ACCESS_COARSE_LOCATION
      )

      val permissionListener = object : PermissionListener {
        override fun onRequestPermissionsResult(
          requestCode: Int,
          permissions: Array<String>,
          grantResults: IntArray
        ): Boolean {
          if (requestCode == LOCATION_PERMISSION_REQUEST_CODE) {
            val granted = grantResults.isNotEmpty() &&
                         grantResults[0] == PackageManager.PERMISSION_GRANTED

            permissionPromise?.let { promise ->
              if (granted) {
                println("✅ Location permissions granted by user")
                promise.resolve("granted")
              } else {
                println("❌ Location permissions denied by user")
                promise.resolve("denied")
              }
            }
            permissionPromise = null
            return true
          }
          return false
        }
      }

      permissionAwareActivity.requestPermissions(
        permissions,
        LOCATION_PERMISSION_REQUEST_CODE,
        permissionListener
      )
    } else {
      println("❌ Activity is not PermissionAware")
      promise.reject("ACTIVITY_NOT_PERMISSION_AWARE", "Current activity does not support permission requests")
      permissionPromise = null
    }
  }

  @ReactMethod
  fun hasLocationPermissions(promise: Promise) {
    promise.resolve(hasLocationPermissions())
  }

  private fun hasLocationPermissions(): Boolean {
    val fineLocationGranted = ContextCompat.checkSelfPermission(
      reactApplicationContext,
      Manifest.permission.ACCESS_FINE_LOCATION
    ) == PackageManager.PERMISSION_GRANTED

    val coarseLocationGranted = ContextCompat.checkSelfPermission(
      reactApplicationContext,
      Manifest.permission.ACCESS_COARSE_LOCATION
    ) == PackageManager.PERMISSION_GRANTED

    val hasPermissions = fineLocationGranted || coarseLocationGranted

    println("📋 Permission status check:")
    println("  - Fine location: $fineLocationGranted")
    println("  - Coarse location: $coarseLocationGranted")
    println("  - Has permissions: $hasPermissions")

    return hasPermissions
  }

  @ReactMethod
  fun requestAlwaysLocationPermissions(promise: Promise) {
    // On Android, "Always" permission is handled by ACCESS_BACKGROUND_LOCATION for Android 10+
    println("🔐 Requesting always location permissions...")

    if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
      // For Android 10+, need background location permission
      if (hasBackgroundLocationPermission()) {
        println("✅ Always permissions already granted")
        promise.resolve("granted")
        return
      }

      val activity = reactApplicationContext.currentActivity
      if (activity == null) {
        println("❌ No current activity available")
        promise.reject("NO_ACTIVITY", "No current activity available for permission request")
        return
      }

      if (activity is PermissionAwareActivity) {
        val permissionAwareActivity = activity as PermissionAwareActivity
        val permissions = arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION)

        val permissionListener = object : PermissionListener {
          override fun onRequestPermissionsResult(
            requestCode: Int,
            permissions: Array<String>,
            grantResults: IntArray
          ): Boolean {
            if (requestCode == LOCATION_PERMISSION_REQUEST_CODE + 2) { // Different code for always permission
              val granted = grantResults.isNotEmpty() &&
                           grantResults[0] == PackageManager.PERMISSION_GRANTED
              promise.resolve(if (granted) "granted" else "denied")
              return true
            }
            return false
          }
        }

        permissionAwareActivity.requestPermissions(
          permissions,
          LOCATION_PERMISSION_REQUEST_CODE + 2,
          permissionListener
        )
      } else {
        promise.reject("PERMISSION_ERROR", "Activity is not PermissionAware")
      }
    } else {
      // For Android 9 and below, regular location permission is sufficient
      requestLocationPermissions(promise)
    }
  }

  private fun createLocationMap(location: Location): WritableMap {
    return Arguments.createMap().apply {
      putDouble("latitude", location.latitude)
      putDouble("longitude", location.longitude)
      putDouble("altitude", location.altitude)
      putDouble("accuracy", location.accuracy.toDouble())
      putDouble("speed", location.speed.toDouble())
      putDouble("bearing", location.bearing.toDouble())
      putDouble("timestamp", location.time.toDouble())
    }
  }

  private fun sendLocationUpdate(location: Location) {
    val locationMap = createLocationMap(location)
    reactApplicationContext
      .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
      .emit("onLocationUpdate", locationMap)
  }

  private fun sendTrackingStatusUpdate() {
    val status = Arguments.createMap().apply {
      putBoolean("isTracking", isTracking)
      if (lastLocationUpdate > 0) {
        putDouble("lastLocationUpdate", lastLocationUpdate.toDouble())
      }
      putDouble("trackingDuration", if (isTracking) (System.currentTimeMillis() - trackingStartTime).toDouble() else 0.0)
    }

    reactApplicationContext
      .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
      .emit("onTrackingStatusChanged", status)
  }

  @RequiresApi(Build.VERSION_CODES.O)
  private fun startBackgroundLocationService(config: ReadableMap) {
    backgroundLocationService = Intent(reactApplicationContext, LocationTrackingService::class.java).apply {
      putExtra("config", Arguments.toBundle(config))
    }
    reactApplicationContext.startForegroundService(backgroundLocationService)
  }

  // Enhanced tracking methods for background_location_2 strategy
  @RequiresPermission(allOf = [Manifest.permission.ACCESS_FINE_LOCATION, Manifest.permission.ACCESS_COARSE_LOCATION])
  @ReactMethod
  fun startTracking(backgroundMode: Boolean, intervalMs: Double, forceUpdateBackground: Boolean?, distanceFilter: Double?, promise: Promise) {
    val actualForceUpdate = forceUpdateBackground ?: false
    val actualDistanceFilter = distanceFilter ?: 10.0
    val actualIntervalMs = intervalMs.toLong()

    println("🚀 Starting enhanced tracking - Background mode: $backgroundMode, Interval: ${actualIntervalMs}ms, Force update: $actualForceUpdate, Distance filter: ${actualDistanceFilter}m")

    if (isTracking) {
      println("⚠️ Already tracking")
      promise.resolve("Already tracking")
      return
    }

    this.backgroundMode = backgroundMode
    this.intervalMs = actualIntervalMs
    this.forceUpdateBackground = actualForceUpdate
    this.distanceFilter = actualDistanceFilter

    // Check permissions
    if (!hasLocationPermission()) {
      promise.reject("PERMISSION_ERROR", "Location permission required")
      return
    }

    if (backgroundMode && !hasBackgroundLocationPermission()) {
      promise.reject("PERMISSION_ERROR", "Background location permission required for background mode")
      return
    }

    try {
      // Configure location request based on force update mode
      if (actualForceUpdate) {
        configureLocationRequestForForcedUpdates()
      } else {
        configureLocationRequestForContinuousUpdates()
      }

      isTracking = true
      trackingStartTime = System.currentTimeMillis()

      if (actualForceUpdate) {
        println("🔄 Starting forced location updates with timer")
        startLocationTimer()
      } else {
        println("🔄 Starting continuous location updates")
        fusedLocationClient?.requestLocationUpdates(locationRequest!!, locationCallback!!, Looper.getMainLooper())
      }

      if (backgroundMode) {
        startBackgroundLocationService()
      }

      sendTrackingStatusUpdate()
      val trackingMode = if (actualForceUpdate) "forced timer" else "continuous updates"
      promise.resolve("Enhanced tracking started with $trackingMode")
    } catch (e: Exception) {
      println("❌ Failed to start enhanced tracking: ${e.message}")
      promise.reject("START_ERROR", "Failed to start tracking: ${e.message}")
    }
  }

  @ReactMethod
  fun stopTracking(promise: Promise) {
    println("🛑 Stopping enhanced tracking")

    if (!isTracking) {
      println("⚠️ Not currently tracking")
      promise.resolve("Not tracking")
      return
    }

    try {
      isTracking = false

      // Stop location services based on mode
      if (forceUpdateBackground) {
        stopLocationTimer()
      } else {
        fusedLocationClient?.removeLocationUpdates(locationCallback!!)
      }

      // Stop background service
      backgroundLocationService?.let {
        reactApplicationContext.stopService(it)
        backgroundLocationService = null
      }

      // Reset flags
      backgroundMode = false
      forceUpdateBackground = false

      sendTrackingStatusUpdate()
      promise.resolve("Enhanced tracking stopped")
    } catch (e: Exception) {
      println("❌ Failed to stop enhanced tracking: ${e.message}")
      promise.reject("STOP_ERROR", "Failed to stop tracking: ${e.message}")
    }
  }

  private fun configureLocationRequestForContinuousUpdates() {
    locationRequest = LocationRequest.create().apply {
      // Use continuous updates with throttling in callback
      interval = 1000L // 1 second for continuous updates
      fastestInterval = 500L // 0.5 seconds minimum
      smallestDisplacement = distanceFilter.toFloat() // Set distance filter
      priority = if (backgroundMode) {
        LocationRequest.PRIORITY_BALANCED_POWER_ACCURACY
      } else {
        LocationRequest.PRIORITY_HIGH_ACCURACY
      }
    }

    locationCallback = object : LocationCallback() {
      override fun onLocationResult(locationResult: LocationResult) {
        val location = locationResult.lastLocation ?: return
        handleLocationUpdate(location)
      }
    }

    println("⚙️ Location request configured for continuous updates")
    println("📍 Priority: ${locationRequest?.priority}")
    println("⏰ Update interval: ${locationRequest?.interval}ms")
    println("📏 Distance filter: ${distanceFilter}m")
  }

  private fun handleLocationUpdate(location: Location) {
    val currentTime = System.currentTimeMillis()

    // Enhanced throttling based on intervalMs for both foreground and background
    val timeSinceLastUpdate = currentTime - lastLocationUpdate

    if (timeSinceLastUpdate < intervalMs) {
      println("⏭️ Skipping location update - respecting intervalMs throttling")
      println("  - Time since last: ${timeSinceLastUpdate}ms")
      println("  - Required interval: ${intervalMs}ms")
      return
    }

    println("✅ Location received: lat=${location.latitude}, lon=${location.longitude}")
    println("📊 Update info (continuous mode):")
    println("  - Background mode: $backgroundMode")
    println("  - Configured interval: ${intervalMs}ms")
    println("  - Actual interval: ${timeSinceLastUpdate}ms")
    println("  - Accuracy: ${location.accuracy}m")

    lastLocationUpdate = currentTime

    val locationData = WritableNativeMap().apply {
      putDouble("latitude", location.latitude)
      putDouble("longitude", location.longitude)
      putDouble("altitude", location.altitude)
      putDouble("accuracy", location.accuracy.toDouble())
      putDouble("speed", location.speed.toDouble())
      putDouble("bearing", location.bearing.toDouble())
      putDouble("timestamp", location.time.toDouble())
    }

    sendEvent("onLocationUpdate", locationData)
    println("📡 Location event sent to React Native (continuous updates)")

    // MARK: - Route Boundary Detection & API Management
    // Only process if not already handled by speed alert callback
    if (!isSpeedAlertActive) {
      // Update current link index based on location
      updateCurrentLinkIndex(location)

      // Check if we need to request new route data from the server
      if (shouldRequestNewRouteData(location)) {
        requestRouteDataFromAPI(location)
      }

      // Note: Speed limit checking is now only done when link index changes
      // This prevents continuous speech alerts on every location update
    } else {
      println("🚨 Route boundary detection already handled by speed alert callback - skipping duplicate processing")
    }
  }

  // Permission helper methods for enhanced tracking
  private fun hasLocationPermission(): Boolean {
    return ContextCompat.checkSelfPermission(
      reactApplicationContext,
      Manifest.permission.ACCESS_FINE_LOCATION
    ) == PackageManager.PERMISSION_GRANTED
  }

  private fun hasBackgroundLocationPermission(): Boolean {
    return if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q) {
      ContextCompat.checkSelfPermission(
        reactApplicationContext,
        Manifest.permission.ACCESS_BACKGROUND_LOCATION
      ) == PackageManager.PERMISSION_GRANTED
    } else {
      // Background location permission is not required before Android 10
      hasLocationPermission()
    }
  }

  private fun startBackgroundLocationService() {
    if (backgroundMode && hasBackgroundLocationPermission()) {
      println("🌙 Starting background location service")
      // Implementation for background service if needed
    }
  }

  private fun configureLocationRequestForForcedUpdates() {
    // Force update mode - request location on timer regardless of distance
    locationRequest = LocationRequest.create().apply {
      interval = intervalMs // Use configured interval
      fastestInterval = intervalMs / 2 // Half the interval for fastest
      priority = LocationRequest.PRIORITY_HIGH_ACCURACY // High accuracy for forced mode
      smallestDisplacement = 0f // No distance filter
    }

    locationCallback = object : LocationCallback() {
      override fun onLocationResult(locationResult: LocationResult) {
        val location = locationResult.lastLocation ?: return
        handleLocationUpdateForced(location)
      }
    }

    println("⚙️ Location request configured for forced updates")
    println("📍 Priority: HIGH_ACCURACY")
    println("📏 Distance filter: NONE (forced mode)")
    println("⏰ Timer interval: ${intervalMs}ms")
  }

  private fun startLocationTimer() {
    // Stop existing timer
    stopLocationTimer()

    val timer = Timer()
    locationTimer = timer

    val interval = intervalMs
    timer.scheduleAtFixedRate(object : TimerTask() {
      override fun run() {
        requestLocationUpdate()
      }
    }, 0, interval)

    println("⏰ Location timer started with interval: ${interval}ms")
  }

  private fun stopLocationTimer() {
    locationTimer?.cancel()
    locationTimer = null
    println("⏰ Location timer stopped")
  }

  private fun requestLocationUpdate() {
    if (!isTracking) {
      println("⚠️ Not tracking - stopping timer")
      stopLocationTimer()
      return
    }

    println("🔄 Requesting forced location update (timer-based)")
    try {
      if (ActivityCompat.checkSelfPermission(
          reactApplicationContext,
          Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
      ) {
        fusedLocationClient?.lastLocation?.addOnSuccessListener { location ->
          if (location != null) {
            handleLocationUpdateForced(location)
          }
        }
      }
    } catch (e: Exception) {
      println("❌ Error requesting forced location update: ${e.message}")
    }
  }

  private fun handleLocationUpdateForced(location: Location) {
    val currentTime = System.currentTimeMillis()

    println("✅ Location received (forced mode): lat=${location.latitude}, lon=${location.longitude}")
    println("📊 Update info (forced timer mode):")
    println("  - Background mode: $backgroundMode")
    println("  - Force update: $forceUpdateBackground")
    println("  - Accuracy: ${location.accuracy}m")
    println("  - Speed: ${location.speed}m/s")

    lastLocationUpdate = currentTime

    val locationData = WritableNativeMap().apply {
      putDouble("latitude", location.latitude)
      putDouble("longitude", location.longitude)
      putDouble("altitude", location.altitude)
      putDouble("accuracy", location.accuracy.toDouble())
      putDouble("speed", location.speed.toDouble())
      putDouble("bearing", location.bearing.toDouble())
      putDouble("timestamp", location.time.toDouble())
    }

    sendEvent("onLocationUpdate", locationData)
    println("📡 Location event sent to React Native (forced mode)")

    // MARK: - Route Boundary Detection & API Management
    // Only process if not already handled by speed alert callback
    if (!isSpeedAlertActive) {
      // Update current link index based on location
      updateCurrentLinkIndex(location)

      // Check if we need to request new route data from the server
      if (shouldRequestNewRouteData(location)) {
        requestRouteDataFromAPI(location)
      }

      // Note: Speed limit checking is now only done when link index changes
      // This prevents continuous speech alerts on every location update
    } else {
      println("🚨 Route boundary detection already handled by speed alert callback - skipping duplicate processing")
    }
  }

  // MARK: - Speed Alert Methods

  // MARK: - Text-to-Speech for Speed Alerts

  private fun speakSpeedLimitAnnouncement(speedLimit: Int) {
    // Check cooldown to avoid too frequent announcements
    val currentTime = System.currentTimeMillis()
    if (currentTime - lastSpeedAlertTime < speedAlertCooldown) {
      return // Skip if within cooldown period
    }

    lastSpeedAlertTime = currentTime

    // Stop any current speech
    textToSpeech?.stop()

    // Create speed limit announcement message in Vietnamese
    val message = "Giới hạn tốc độ $speedLimit ki-lô-mét trên giờ"

    // Configure speech parameters for informational announcements
    textToSpeech?.setSpeechRate(0.6f) // Slower speech rate for clarity
    textToSpeech?.setPitch(1.0f) // Normal pitch for informational announcements

    Log.d(NAME, "🔊 Speaking speed limit announcement: $message")
    textToSpeech?.speak(message, TextToSpeech.QUEUE_FLUSH, null, "SPEED_LIMIT_INFO")
  }

  private fun speakSpeedAlert(currentSpeed: Double, speedLimit: Int, severity: String) {
    // Check cooldown to avoid too frequent alerts
    val currentTime = System.currentTimeMillis()
    if (currentTime - lastSpeedAlertTime < speedAlertCooldown) {
      return // Skip if within cooldown period
    }

    lastSpeedAlertTime = currentTime

    // Stop any current speech
    textToSpeech?.stop()

    // Create speech message in Vietnamese
    val speedText = String.format("%.0f", currentSpeed)
    val message = "Cảnh báo tốc độ! Tốc độ hiện tại $speedText km/h, vượt giới hạn $speedLimit km/h"

    // Configure speech parameters based on severity
    val speechRate = if (severity == "critical") 0.8f else 0.6f // Slower for critical
    val pitch = if (severity == "critical") 1.2f else 1.0f // Higher pitch for critical

    textToSpeech?.setSpeechRate(speechRate)
    textToSpeech?.setPitch(pitch)

    Log.d(NAME, "🔊 Speaking speed alert: $message")
    textToSpeech?.speak(message, TextToSpeech.QUEUE_FLUSH, null, "SPEED_ALERT")
  }

  @ReactMethod
  fun turnOnAlert(promise: Promise) {
    Log.d(NAME, "🚨 Turning on speed alert")

    // Check if location permissions are granted
    if (hasLocationPermissions()) {
      // Check if we need background location permission for Android 10+
      if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q && !hasBackgroundLocationPermission()) {
        Log.d(NAME, "📱 Need background location permission for Android 10+, requesting...")
        requestBackgroundLocationPermissionForAlert(promise)
        return
      }

      Log.d(NAME, "✅ Location permissions already granted, starting location monitoring for speed alert")
      startSpeedAlertLocationMonitoring()
      promise.resolve(true)
      return
    }

    Log.d(NAME, "📱 Location permissions not granted, requesting permissions...")

    // Store the promise to resolve after permission is granted/denied
    pendingAlertPromise = promise

    val activity = reactApplicationContext.currentActivity
    if (activity == null) {
      Log.e(NAME, "❌ No current activity available for permission request")
      promise.resolve(false)
      pendingAlertPromise = null
      return
    }

    if (activity is PermissionAwareActivity) {
      val permissionAwareActivity = activity as PermissionAwareActivity

      val permissions = arrayOf(
        Manifest.permission.ACCESS_FINE_LOCATION,
        Manifest.permission.ACCESS_COARSE_LOCATION
      )

      val permissionListener = object : PermissionListener {
        override fun onRequestPermissionsResult(
          requestCode: Int,
          permissions: Array<String>,
          grantResults: IntArray
        ): Boolean {
          if (requestCode == LOCATION_PERMISSION_REQUEST_CODE + 1) { // Use different code for alert
            val granted = grantResults.isNotEmpty() &&
                         grantResults[0] == PackageManager.PERMISSION_GRANTED

            pendingAlertPromise?.let { alertPromise ->
              if (granted) {
                Log.d(NAME, "✅ Location permissions granted for speed alert")
                // Check if we need background location permission for Android 10+
                if (android.os.Build.VERSION.SDK_INT >= android.os.Build.VERSION_CODES.Q && !hasBackgroundLocationPermission()) {
                  Log.d(NAME, "📱 Now requesting background location permission for Android 10+...")
                  requestBackgroundLocationPermissionForAlert(alertPromise)
                } else {
                  startSpeedAlertLocationMonitoring()
                  alertPromise.resolve(true)
                }
              } else {
                Log.d(NAME, "❌ Location permissions denied for speed alert")
                alertPromise.resolve(false)
              }
            }
            pendingAlertPromise = null
            return true
          }
          return false
        }
      }

      permissionAwareActivity.requestPermissions(
        permissions,
        LOCATION_PERMISSION_REQUEST_CODE + 1, // Use different code for alert
        permissionListener
      )
    } else {
      Log.e(NAME, "❌ Activity is not PermissionAware")
      promise.resolve(false)
      pendingAlertPromise = null
    }
  }

  private fun requestBackgroundLocationPermissionForAlert(promise: Promise) {
    if (android.os.Build.VERSION.SDK_INT < android.os.Build.VERSION_CODES.Q) {
      // Background location permission not needed before Android 10
      startSpeedAlertLocationMonitoring()
      promise.resolve(true)
      return
    }

    val activity = reactApplicationContext.currentActivity
    if (activity == null) {
      Log.e(NAME, "❌ No current activity available for background permission request")
      promise.resolve(false)
      return
    }

    if (activity is PermissionAwareActivity) {
      val permissionAwareActivity = activity as PermissionAwareActivity

      val backgroundPermissionListener = object : PermissionListener {
        override fun onRequestPermissionsResult(
          requestCode: Int,
          permissions: Array<String>,
          grantResults: IntArray
        ): Boolean {
          if (requestCode == LOCATION_PERMISSION_REQUEST_CODE + 2) { // Different code for background
            val granted = grantResults.isNotEmpty() &&
                         grantResults[0] == PackageManager.PERMISSION_GRANTED

            if (granted) {
              Log.d(NAME, "✅ Background location permission granted for speed alert")
            } else {
              Log.d(NAME, "⚠️ Background location permission denied - will work in foreground only")
            }

            startSpeedAlertLocationMonitoring()
            promise.resolve(true)
            return true
          }
          return false
        }
      }

      permissionAwareActivity.requestPermissions(
        arrayOf(Manifest.permission.ACCESS_BACKGROUND_LOCATION),
        LOCATION_PERMISSION_REQUEST_CODE + 2, // Different code for background
        backgroundPermissionListener
      )
    } else {
      Log.e(NAME, "❌ Activity is not PermissionAware for background permission")
      startSpeedAlertLocationMonitoring()
      promise.resolve(true)
    }
  }

  private fun startSpeedAlertLocationMonitoring() {
    Log.d(NAME, "🎯 Starting continuous location monitoring for speed alert")

    isSpeedAlertActive = true

    try {
      // Configure for high sensitivity to get frequent updates
      val locationRequest = LocationRequest.Builder(Priority.PRIORITY_HIGH_ACCURACY, 1000) // 1 second interval
        .setMinUpdateDistanceMeters(5.0f) // 5 meter distance filter for high sensitivity as requested
        .setWaitForAccurateLocation(false)
        .build()

      Log.d(NAME, "🔄 Starting location updates for speed alert")
      Log.d(NAME, "📏 Distance filter: 5.0m (high sensitivity - updated from 1m)")
      Log.d(NAME, "📍 Accuracy: High accuracy")
      Log.d(NAME, "⏰ Update interval: 1000ms")

      if (ActivityCompat.checkSelfPermission(
          reactApplicationContext,
          Manifest.permission.ACCESS_FINE_LOCATION
        ) == PackageManager.PERMISSION_GRANTED
      ) {
        fusedLocationClient?.requestLocationUpdates(
          locationRequest,
          speedAlertLocationCallback,
          Looper.getMainLooper()
        )
        Log.d(NAME, "✅ Speed alert location monitoring started")
      } else {
        Log.e(NAME, "❌ Location permission not available for speed alert")
      }
    } catch (e: Exception) {
      Log.e(NAME, "❌ Error starting speed alert location monitoring: ${e.message}")
    }
  }

  private fun stopSpeedAlertLocationMonitoring() {
    Log.d(NAME, "🛑 Stopping speed alert location monitoring")

    isSpeedAlertActive = false

    try {
      // Only stop if we're not doing regular tracking
      if (!isTracking) {
        fusedLocationClient?.removeLocationUpdates(speedAlertLocationCallback)
        Log.d(NAME, "✅ Speed alert location monitoring stopped")
      } else {
        Log.d(NAME, "ℹ️ Regular tracking is active, keeping location monitoring")
      }
    } catch (e: Exception) {
      Log.e(NAME, "❌ Error stopping speed alert location monitoring: ${e.message}")
    }
  }

  private val speedAlertLocationCallback = object : LocationCallback() {
    override fun onLocationResult(locationResult: LocationResult) {
      if (!isSpeedAlertActive) return

      locationResult.lastLocation?.let { location ->
        // Print detailed location info for speed alert
        Log.d(NAME, "🚨 [SPEED ALERT] Location Update:")
        Log.d(NAME, "  📍 Coordinates: ${location.latitude}, ${location.longitude}")
        Log.d(NAME, "  🚗 Speed: ${location.speed} m/s (${String.format("%.1f", location.speed * 3.6)} km/h)")
        Log.d(NAME, "  📏 Accuracy: ${location.accuracy}m")
        Log.d(NAME, "  🧭 Bearing: ${location.bearing}°")
        Log.d(NAME, "  ⏰ Time: ${java.text.SimpleDateFormat("HH:mm:ss", java.util.Locale.getDefault()).format(java.util.Date(location.time))}")
        Log.d(NAME, "  🌍 Altitude: ${location.altitude}m")

        // Process route boundary detection for speed alert mode
        Log.d(NAME, "🚨 [SPEED ALERT] Processing route boundary detection...")

        // Update current link index based on location
        updateCurrentLinkIndex(location)

        // Check if we need to request new route data from the server
        if (shouldRequestNewRouteData(location)) {
          requestRouteDataFromAPI(location)
        }

        // Note: Speed limit checking is now only done when new route data is received
        // This prevents continuous speech alerts on every location update
      }
    }

    override fun onLocationAvailability(locationAvailability: LocationAvailability) {
      if (isSpeedAlertActive) {
        Log.d(NAME, "🚨 [SPEED ALERT] Location availability: ${locationAvailability.isLocationAvailable}")
      }
    }
  }

  @ReactMethod
  fun turnOffAlert(promise: Promise) {
    Log.d(NAME, "🛑 Turning off speed alert")
    stopSpeedAlertLocationMonitoring()
    promise.resolve(true)
  }

  // MARK: - Route and Alert Processing Methods
  private fun processRouteLinks(links: ReadableArray, alerts: ReadableArray, offset: ReadableArray): WritableMap {
    val processedLinks = Arguments.createArray()
    val processedAlerts = Arguments.createArray()

    // Process links
    for (i in 0 until links.size()) {
      val link = links.getArray(i)
      if (link != null && link.size() >= 5) {
        val linkId = link.getInt(0)
        val direction = link.getInt(1)
        val coordinates = link.getArray(2)
        val distance = link.getInt(3)
        val speedLimits = link.getArray(4)

        val processedLink = Arguments.createMap().apply {
          putInt("id", linkId)
          putInt("direction", direction)
          if (coordinates != null && coordinates.size() >= 4) {
            putDouble("startLat", coordinates.getDouble(1))
            putDouble("startLon", coordinates.getDouble(0))
            putDouble("endLat", coordinates.getDouble(3))
            putDouble("endLon", coordinates.getDouble(2))
          }
          putInt("distance", distance)
          putArray("speedLimits", speedLimits)
        }
        processedLinks.pushMap(processedLink)
      }
    }

    // Process alerts
    for (i in 0 until alerts.size()) {
      val alert = alerts.getArray(i)
      if (alert != null && alert.size() >= 4) {
        val processedAlert = Arguments.createMap().apply {
          putInt("type", alert.getInt(0))
          if (!alert.isNull(1)) putInt("subtype", alert.getInt(1))
          if (!alert.isNull(2)) putInt("speedLimit", alert.getInt(2))
          putInt("distance", alert.getInt(3))
        }
        processedAlerts.pushMap(processedAlert)
      }
    }

    return Arguments.createMap().apply {
      putArray("links", processedLinks)
      putArray("alerts", processedAlerts)
      putArray("offset", offset)
      putInt("totalLinks", processedLinks.size())
      putInt("totalAlerts", processedAlerts.size())
    }
  }

  @ReactMethod
  fun getCurrentRouteInfo(promise: Promise) {
    if (currentRouteData != null) {
      promise.resolve(currentRouteData)
    } else {
      promise.reject("NO_ROUTE_DATA", "No route data available")
    }
  }

  @ReactMethod
  fun findNearestAlert(latitude: Double, longitude: Double, promise: Promise) {
    if (currentRouteData == null || currentAlerts == null) {
      promise.reject("NO_ROUTE_DATA", "No route data available")
      return
    }

    try {
      val links = currentRouteData!!.getArray("links")
      if (links == null) {
        promise.reject("NO_LINKS", "No links data available")
        return
      }

      // Find nearest link based on current location
      var nearestLinkIndex: Int? = null
      var minDistance = Double.MAX_VALUE

      for (i in 0 until links.size()) {
        val link = links.getMap(i)
        if (link != null) {
          val startLat = link.getDouble("startLat")
          val startLon = link.getDouble("startLon")
          val endLat = link.getDouble("endLat")
          val endLon = link.getDouble("endLon")

          // Calculate distance to link segment
          val distance = distanceToLineSegment(
            latitude, longitude,
            startLat, startLon,
            endLat, endLon
          )

          if (distance < minDistance) {
            minDistance = distance
            nearestLinkIndex = i
          }
        }
      }

      // Find alerts for the nearest link
      if (nearestLinkIndex != null) {
        val relevantAlerts = findAlertsForLink(nearestLinkIndex, currentAlerts!!)

        val result = Arguments.createMap().apply {
          putInt("nearestLinkIndex", nearestLinkIndex)
          putDouble("distanceToLink", minDistance)
          putArray("alerts", relevantAlerts)
        }

        promise.resolve(result)
      } else {
        promise.reject("NO_LINK_FOUND", "No nearby link found")
      }
    } catch (e: Exception) {
      Log.e(NAME, "❌ Error finding nearest alert: ${e.message}")
      promise.reject("SEARCH_ERROR", "Error finding nearest alert: ${e.message}")
    }
  }

  private fun distanceToLineSegment(
    pointLat: Double, pointLon: Double,
    startLat: Double, startLon: Double,
    endLat: Double, endLon: Double
  ): Double {
    // Use proper geodesic distance calculation via Haversine formula
    val snappedLocation = snapToLineSegment(pointLat, pointLon, startLat, startLon, endLat, endLon)
    return calculateDistance(pointLat, pointLon, snappedLocation.latitude, snappedLocation.longitude)
  }

  private fun findAlertsForLink(linkIndex: Int, alerts: ReadableArray): WritableArray {
    val relevantAlerts = Arguments.createArray()

    for (i in 0 until alerts.size()) {
      val alert = alerts.getArray(i)
      if (alert != null && alert.size() >= 4) {
        val distance = alert.getInt(3)

        // Simple logic: alerts within reasonable distance of current link
        // In real implementation, you'd use proper route distance calculation
        val alertInfo = Arguments.createMap().apply {
          putInt("type", alert.getInt(0))
          if (!alert.isNull(1)) putInt("subtype", alert.getInt(1))
          if (!alert.isNull(2)) putInt("speedLimit", alert.getInt(2))
          putInt("distance", distance)
          putInt("linkIndex", linkIndex)
        }
        relevantAlerts.pushMap(alertInfo)
      }
    }

    return relevantAlerts
  }

  private fun sendEvent(eventName: String, data: Any?) {
    reactApplicationContext
      .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
      .emit(eventName, data)
  }

  // MARK: - Route Boundary Detection Methods

  @ReactMethod
  fun setRouteAPIEndpoint(endpoint: String, promise: Promise) {
    routeAPIEndpoint = endpoint
    Log.d(NAME, "🗺️ Route API endpoint set: $endpoint")
    promise.resolve(true)
  }

  @ReactMethod
  fun enableRouteBoundaryDetection(threshold: Double, promise: Promise) {
    routeBoundaryThreshold = threshold
    Log.d(NAME, "🎯 Route boundary detection enabled with threshold: ${threshold}m")
    promise.resolve(true)
  }

  private fun isLocationWithinCurrentRoute(location: Location): Boolean {
    val routeData = currentRouteData ?: return false
    val links = routeData.getArray("links") ?: return false

    // Enhanced route matching with map-matching algorithm
    val matchingResult = findBestRouteMatch(location, links)

    return matchingResult.isWithinRoute
  }

  private fun shouldRequestNewRouteData(location: Location): Boolean {
    // Don't request if API call is already in progress
    if (apiRequestInProgress) {
      return false
    }

    // Request if no route data exists
    if (currentRouteData == null) {
      return true
    }

    // Request if location is outside current route
    if (!isLocationWithinCurrentRoute(location)) {
      Log.d(NAME, "📍 Location outside current route - requesting new route data")
      return true
    }

    // Request if significantly moved from last API request location
    lastAPIRequestLocation?.let { lastLocation ->
      val distance = location.distanceTo(lastLocation)
      if (distance > 1000) { // 1km threshold
        Log.d(NAME, "📍 Moved 1km from last API request - requesting updated route data")
        return true
      }
    }

    return false
  }

  private fun requestRouteDataFromAPI(location: Location) {
    val apiEndpoint = routeAPIEndpoint
    if (apiEndpoint == null || apiRequestInProgress) {
      Log.e(NAME, "❌ No API endpoint set or request in progress")
      return
    }

    apiRequestInProgress = true
    lastAPIRequestLocation = location

    Log.d(NAME, "🌐 Requesting route data from API for location: ${location.latitude}, ${location.longitude}")

    // Create API request using OkHttp or similar
    Thread {
      try {
        val url = "$apiEndpoint?lat=${location.latitude}&lon=${location.longitude}"
        val client = okhttp3.OkHttpClient()
        val request = okhttp3.Request.Builder().url(url).build()

        client.newCall(request).execute().use { response ->
          if (response.isSuccessful) {
            val jsonData = response.body?.string()
            if (jsonData != null) {
              // Parse and handle new route data
              handleNewRouteDataFromAPI(jsonData, location)
            } else {
              Log.e(NAME, "❌ Route API response is empty")
            }
          } else {
            Log.e(NAME, "❌ Route API request failed: ${response.code}")
          }
        }
      } catch (e: Exception) {
        Log.e(NAME, "❌ Route API request error: ${e.message}")
      } finally {
        apiRequestInProgress = false
      }
    }.start()
  }

  private fun handleNewRouteDataFromAPI(jsonData: String, location: Location) {
    try {
      val jsonObject = org.json.JSONObject(jsonData)

      // Convert JSON to ReadableMap format
      val routeMap = Arguments.createMap()

      // Parse links
      val linksArray = jsonObject.getJSONArray("links")
      val linksReadable = Arguments.createArray()
      for (i in 0 until linksArray.length()) {
        val linkArray = linksArray.getJSONArray(i)
        val linkReadable = Arguments.createArray()
        for (j in 0 until linkArray.length()) {
          when (val value = linkArray.get(j)) {
            is Int -> linkReadable.pushInt(value)
            is Double -> linkReadable.pushDouble(value)
            is String -> linkReadable.pushString(value)
            is org.json.JSONArray -> {
              val subArray = Arguments.createArray()
              for (k in 0 until value.length()) {
                subArray.pushDouble(value.getDouble(k))
              }
              linkReadable.pushArray(subArray)
            }
          }
        }
        linksReadable.pushArray(linkReadable)
      }

      // Parse alerts
      val alertsArray = jsonObject.getJSONArray("alerts")
      val alertsReadable = Arguments.createArray()
      for (i in 0 until alertsArray.length()) {
        val alertArray = alertsArray.getJSONArray(i)
        val alertReadable = Arguments.createArray()
        for (j in 0 until alertArray.length()) {
          val value = alertArray.get(j)
          if (value == null || value == org.json.JSONObject.NULL) {
            alertReadable.pushNull()
          } else {
            alertReadable.pushInt(value as Int)
          }
        }
        alertsReadable.pushArray(alertReadable)
      }

      // Parse offset
      val offsetArray = jsonObject.getJSONArray("offset")
      val offsetReadable = Arguments.createArray()
      for (i in 0 until offsetArray.length()) {
        offsetReadable.pushInt(offsetArray.getInt(i))
      }

      routeMap.putArray("links", linksReadable)
      routeMap.putArray("alerts", alertsReadable)
      routeMap.putArray("offset", offsetReadable)

      // Process the new route data
      val processedData = processRouteLinks(linksReadable, alertsReadable, offsetReadable)

      // Store new route data
      currentRouteData = processedData
      currentAlerts = alertsReadable
      routeOffset = offsetReadable

      // Reset previous speed limit when new route data is received
      previousLinkSpeedLimit = null

      // Set initial currentLinkIndex to first link when new route data is received from API
      if (linksReadable.size() > 0) {
        currentLinkIndex = 0
        Log.d(NAME, "🎯 Initial currentLinkIndex set to: 0 (first link from API)")
      } else {
        currentLinkIndex = null
        Log.d(NAME, "⚠️ No links available from API, currentLinkIndex set to null")
      }

      // Find current link index based on location after setting initial value
      updateCurrentLinkIndex(location)

      Log.d(NAME, "✅ Route data updated from API - Links: ${linksReadable.size()}, Alerts: ${alertsReadable.size()}")

    } catch (e: Exception) {
      Log.e(NAME, "❌ Failed to parse route API response: ${e.message}")
    }
  }

  private fun updateCurrentLinkIndex(location: Location) {
    val routeData = currentRouteData ?: return
    val links = routeData.getArray("links") ?: return

    val matchingResult = findBestRouteMatch(location, links)

    if (matchingResult.linkIndex != null && matchingResult.confidence > 0.7) { // Only update if confident
      val newLinkIndex = matchingResult.linkIndex

      if (newLinkIndex != currentLinkIndex) {
        Log.d(NAME, "🎯 Link index updated: ${currentLinkIndex ?: -1} → $newLinkIndex")
        Log.d(NAME, "📍 Snap distance: ${"%.1f".format(matchingResult.distanceToRoute)}m")
        Log.d(NAME, "📊 Progress on link: ${"%.1f".format(matchingResult.progressOnLink * 100)}%")
        Log.d(NAME, "🎯 Confidence: ${"%.1f".format(matchingResult.confidence * 100)}%")

        currentLinkIndex = newLinkIndex

        // Store snapped location for better tracking
        matchingResult.snappedLocation?.let { snapped ->
          Log.d(NAME, "🧭 GPS: (${location.latitude}, ${location.longitude})")
          Log.d(NAME, "📍 Snapped: (${snapped.latitude}, ${snapped.longitude})")
        }

        // Check speed limits when link changes (only for speed alert mode)
        if (isSpeedAlertActive) {
          checkSpeedLimitsForCurrentLocation(location)
        }
      }
    }
  }

  private fun checkSpeedLimitsForCurrentLocation(location: Location) {
    val currentIndex = currentLinkIndex ?: return
    val routeData = currentRouteData ?: return
    val links = routeData.getArray("links") ?: return

    if (currentIndex >= links.size()) return

    val currentLink = links.getMap(currentIndex) ?: return

    // Get speed limits for current link
    val speedLimits = currentLink.getArray("speedLimits")
    speedLimits?.let { limits ->
      for (i in 0 until limits.size()) {
        val speedLimitData = limits.getArray(i) ?: continue
        if (speedLimitData.size() >= 2) {
          val currentSpeedLimit = speedLimitData.getInt(1) // Speed limit value

          // Only announce if speed limit is different from previous link
          if (currentSpeedLimit != previousLinkSpeedLimit && currentSpeedLimit > 0) {
            Log.d(NAME, "🚨 SPEED LIMIT CHANGED: Previous: ${previousLinkSpeedLimit ?: 0} → Current: $currentSpeedLimit km/h")

            // Announce the new speed limit (not violation, just information)
            speakSpeedLimitAnnouncement(currentSpeedLimit)

            // Update previous speed limit
            previousLinkSpeedLimit = currentSpeedLimit
          }

          // Break after first speed limit (assuming one speed limit per link)
          break
        }
      }
    } ?: run {
      // No speed limit for current link
      if (previousLinkSpeedLimit != null) {
        Log.d(NAME, "🚨 SPEED LIMIT REMOVED: Previous: ${previousLinkSpeedLimit ?: 0} → Current: No limit")
        previousLinkSpeedLimit = null
        // Optionally announce that speed limit has been removed
        // speakSpeedLimitRemoved()
      }
    }
  }

  // MARK: - Enhanced Map Matching for Route Following

  data class SnappedLocation(
    val latitude: Double,
    val longitude: Double
  )

  data class RouteMatchingResult(
    val isWithinRoute: Boolean,
    val snappedLocation: SnappedLocation?,
    val linkIndex: Int?,
    val distanceToRoute: Double,
    val progressOnLink: Double, // 0.0 to 1.0
    val confidence: Double      // 0.0 to 1.0
  )

  private fun findBestRouteMatch(location: Location, links: ReadableArray): RouteMatchingResult {
    // Handle empty links gracefully
    if (links.size() == 0) {
      Log.d(NAME, "🔍 [DEBUG] findBestRouteMatch - No links available")
      return RouteMatchingResult(
        isWithinRoute = false,
        snappedLocation = null,
        linkIndex = null,
        distanceToRoute = Double.MAX_VALUE,
        progressOnLink = 0.0,
        confidence = 0.0
      )
    }

    var bestMatch: RouteMatchingResult? = null
    var bestScore = Double.MAX_VALUE

    Log.d(NAME, "🔍 [DEBUG] findBestRouteMatch - Starting search for location: (${location.latitude}, ${location.longitude})")
    Log.d(NAME, "🔍 [DEBUG] Current link index: ${currentLinkIndex ?: -1}, Total links: ${links.size()}")

    // Check current link first (higher priority) if exists
    currentLinkIndex?.let { currentIndex ->
      if (currentIndex < links.size()) {
        val currentLink = links.getMap(currentIndex)
        if (currentLink != null) {
          val currentLinkMatch = evaluateLinkMatch(location, currentLink, currentIndex, true)

          Log.d(NAME, "🔍 [DEBUG] Current link evaluation:")
          Log.d(NAME, "  - Distance: ${"%.1f".format(currentLinkMatch.distanceToRoute)}m")
          Log.d(NAME, "  - Confidence: ${"%.1f".format(currentLinkMatch.confidence * 100)}%")

          if (currentLinkMatch.distanceToRoute <= routeBoundaryThreshold * 1.5) { // More lenient for current link
            bestMatch = currentLinkMatch
            bestScore = currentLinkMatch.distanceToRoute
            Log.d(NAME, "🔍 [DEBUG] Current link accepted as candidate")
          }
        }
      }
    }

    // Determine search strategy
    val searchAll = currentLinkIndex == null || bestMatch == null
    val searchRange = if (searchAll) links.size() else minOf(5, links.size()) // Search more links if no current link

    val startIndex: Int
    val endIndex: Int

    if (searchAll) {
      // Search all links if no current link or no good match
      startIndex = 0
      endIndex = links.size() - 1
      Log.d(NAME, "🔍 [DEBUG] Searching ALL links (no current link or poor match)")
    } else {
      // Search adjacent links only
      startIndex = maxOf(0, (currentLinkIndex ?: 0) - searchRange)
      endIndex = minOf(links.size() - 1, (currentLinkIndex ?: 0) + searchRange)
      Log.d(NAME, "🔍 [DEBUG] Searching adjacent links: $startIndex to $endIndex")
    }

    // Ensure valid range before using it
    if (startIndex > endIndex || startIndex >= links.size() || endIndex < 0) {
      Log.d(NAME, "🔍 [DEBUG] Invalid range: startIndex=$startIndex, endIndex=$endIndex, links.size=${links.size()}")
      return bestMatch ?: RouteMatchingResult(
        isWithinRoute = false,
        snappedLocation = null,
        linkIndex = null,
        distanceToRoute = Double.MAX_VALUE,
        progressOnLink = 0.0,
        confidence = 0.0
      )
    }

    for (i in startIndex..endIndex) {
      if (i == currentLinkIndex) continue // Already checked

      val link = links.getMap(i) ?: continue
      val linkMatch = evaluateLinkMatch(location, link, i, false)

      Log.d(NAME, "🔍 [DEBUG] Link $i evaluation:")
      Log.d(NAME, "  - Distance: ${"%.1f".format(linkMatch.distanceToRoute)}m")
      Log.d(NAME, "  - Confidence: ${"%.1f".format(linkMatch.confidence * 100)}%")

      // Scoring: distance + direction consistency + sequence penalty
      val sequencePenalty = if (searchAll) 0.0 else kotlin.math.abs(i - (currentLinkIndex ?: i)) * 5.0 // Reduced penalty
      val totalScore = linkMatch.distanceToRoute + sequencePenalty

      val isAcceptable = linkMatch.distanceToRoute <= routeBoundaryThreshold * 2.0 // More lenient threshold

      if (totalScore < bestScore && isAcceptable) {
        bestMatch = linkMatch
        bestScore = totalScore
        Log.d(NAME, "🔍 [DEBUG] Link $i accepted as new best candidate (score: ${"%.1f".format(totalScore)})")
      }
    }

    // If still no good match found, return default
    if (bestMatch == null) {
      Log.d(NAME, "🔍 [DEBUG] No match found - returning nil result")
      return RouteMatchingResult(
        isWithinRoute = false,
        snappedLocation = null,
        linkIndex = null,
        distanceToRoute = Double.MAX_VALUE,
        progressOnLink = 0.0,
        confidence = 0.0
      )
    }

    Log.d(NAME, "🔍 [DEBUG] Best match found:")
    Log.d(NAME, "  - Link index: ${bestMatch?.linkIndex}")
    Log.d(NAME, "  - Distance: ${"%.1f".format(bestMatch?.distanceToRoute)}m")
    Log.d(NAME, "  - Confidence: ${"%.1f".format(bestMatch!!.confidence * 100)}%")

    return bestMatch as RouteMatchingResult
  }

  private fun evaluateLinkMatch(location: Location, link: ReadableMap, linkIndex: Int, isCurrentLink: Boolean): RouteMatchingResult {
    val startLat = link.getDouble("startLat")
    val startLon = link.getDouble("startLon")
    val endLat = link.getDouble("endLat")
    val endLon = link.getDouble("endLon")

    val currentLat = location.latitude
    val currentLon = location.longitude

    Log.d(NAME, "🔍 [DEBUG] evaluateLinkMatch - Link $linkIndex:")
    Log.d(NAME, "  - GPS: ($currentLat, $currentLon)")
    Log.d(NAME, "  - Link Start: ($startLat, $startLon)")
    Log.d(NAME, "  - Link End: ($endLat, $endLon)")

    // Calculate closest point on link segment (snap-to-route)
    val snappedPoint = snapToLineSegment(
      currentLat, currentLon,
      startLat, startLon,
      endLat, endLon
    )

    Log.d(NAME, "  - Snapped point: (${snappedPoint.latitude}, ${snappedPoint.longitude})")

    // Calculate distance from GPS point to snapped point
    val distanceToRoute = calculateDistance(
      currentLat, currentLon,
      snappedPoint.latitude, snappedPoint.longitude
    )

    Log.d(NAME, "  - Distance to route: ${"%.1f".format(distanceToRoute)}m")

    // Calculate progress along the link (0.0 to 1.0)
    val progressOnLink = calculateProgressOnLink(
      snappedPoint.latitude, snappedPoint.longitude,
      startLat, startLon,
      endLat, endLon
    )

    Log.d(NAME, "  - Progress on link: ${"%.2f".format(progressOnLink)}")

    // Calculate confidence based on multiple factors
    val confidence = calculateMatchingConfidence(
      distanceToRoute,
      progressOnLink,
      isCurrentLink,
      location
    )

    // Enhanced threshold based on movement direction and speed
    val dynamicThreshold = calculateDynamicThreshold(location, isCurrentLink)
    val isWithinRoute = distanceToRoute <= dynamicThreshold

    Log.d(NAME, "  - Dynamic threshold: ${"%.1f".format(dynamicThreshold)}m")
    Log.d(NAME, "  - Is within route: $isWithinRoute")
    Log.d(NAME, "  - Final confidence: ${"%.1f".format(confidence * 100)}%")

    return RouteMatchingResult(
      isWithinRoute = isWithinRoute,
      snappedLocation = snappedPoint,
      linkIndex = linkIndex,
      distanceToRoute = distanceToRoute,
      progressOnLink = progressOnLink,
      confidence = confidence
    )
  }

  private fun snapToLineSegment(
    pointLat: Double, pointLon: Double,
    startLat: Double, startLon: Double,
    endLat: Double, endLon: Double
  ): SnappedLocation {

    // Vector from start to end of segment
    val segmentLat = endLat - startLat
    val segmentLon = endLon - startLon

    // Vector from start to point
    val pointLatRel = pointLat - startLat
    val pointLonRel = pointLon - startLon

    // Calculate parameter t for closest point on line segment
    val segmentLengthSquared = segmentLat * segmentLat + segmentLon * segmentLon

    if (segmentLengthSquared == 0.0) {
      // Degenerate segment (start == end)
      return SnappedLocation(startLat, startLon)
    }

    // Project point onto line segment
    val t = (pointLatRel * segmentLat + pointLonRel * segmentLon) / segmentLengthSquared

    // Clamp t to [0, 1] to stay within segment
    val clampedT = maxOf(0.0, minOf(1.0, t))

    // Calculate snapped coordinates
    val snappedLat = startLat + clampedT * segmentLat
    val snappedLon = startLon + clampedT * segmentLon

    return SnappedLocation(snappedLat, snappedLon)
  }

  private fun calculateProgressOnLink(
    snappedLat: Double, snappedLon: Double,
    startLat: Double, startLon: Double,
    endLat: Double, endLon: Double
  ): Double {

    val totalDistance = calculateDistance(startLat, startLon, endLat, endLon)

    if (totalDistance == 0.0) return 0.0

    val progressDistance = calculateDistance(startLat, startLon, snappedLat, snappedLon)

    return minOf(1.0, progressDistance / totalDistance)
  }

  private fun calculateMatchingConfidence(
    distanceToRoute: Double,
    progressOnLink: Double,
    isCurrentLink: Boolean,
    location: Location
  ): Double {
    Log.d(NAME, "🔍 [DEBUG] calculateMatchingConfidence:")
    Log.d(NAME, "  - Distance to route: ${"%.1f".format(distanceToRoute)}m")
    Log.d(NAME, "  - Is current link: $isCurrentLink")
    Log.d(NAME, "  - GPS accuracy: ${"%.1f".format(location.accuracy)}m")

    var confidence = 1.0

    // Distance factor (closer = higher confidence) - more generous scoring
    val maxDistance = routeBoundaryThreshold * 3.0 // Allow for wider matching
    val distanceFactor = maxOf(0.1, 1.0 - (distanceToRoute / maxDistance)) // Minimum 10% confidence
    confidence *= distanceFactor
    Log.d(NAME, "  - Distance factor: ${"%.2f".format(distanceFactor)}")

    // GPS accuracy factor - more lenient
    val accuracyFactor: Double = if (location.accuracy < 10) {
      1.0
    } else if (location.accuracy < 50) {
      maxOf(0.6, 1.0 - (location.accuracy - 10) / 40)
    } else {
      0.5 // Still give some confidence for poor GPS
    }
    confidence *= accuracyFactor
    Log.d(NAME, "  - Accuracy factor: ${"%.2f".format(accuracyFactor)}")

    // Current link bonus
    if (isCurrentLink) {
      confidence *= 1.3 // Increased bonus for current link
      Log.d(NAME, "  - Current link bonus applied")
    }

    // Speed consistency (if moving, prefer links in direction of movement)
    if (location.speed > 1.0 && location.bearing >= 0) { // Moving with valid course
      confidence *= 1.15
      Log.d(NAME, "  - Movement bonus applied")
    }

    // Ensure minimum confidence for close matches
    if (distanceToRoute <= routeBoundaryThreshold) {
      confidence = maxOf(confidence, 0.4) // Minimum 40% confidence for close matches
    }

    val finalConfidence = maxOf(0.0, minOf(1.0, confidence))
    Log.d(NAME, "  - Final confidence: ${"%.2f".format(finalConfidence)}")

    return finalConfidence
  }

  private fun calculateDynamicThreshold(location: Location, isCurrentLink: Boolean): Double {
    var threshold = routeBoundaryThreshold

    // Increase threshold based on GPS accuracy
    if (location.accuracy > 10) {
      threshold += location.accuracy * 0.5
    }

    // Increase threshold for current link (more lenient)
    if (isCurrentLink) {
      threshold *= 1.5
    }

    // Increase threshold based on speed (faster = more GPS drift)
    if (location.speed > 10) { // > 36 km/h
      val speedFactor = 1.0 + (location.speed - 10) * 0.1
      threshold *= speedFactor
    }

    // Cap maximum threshold
    return minOf(threshold, 150.0) // Max 150m threshold
  }

  private fun calculateDistance(lat1: Double, lon1: Double, lat2: Double, lon2: Double): Double {
    // Haversine formula for more accurate distance calculation
    val R = 6371000.0 // Earth radius in meters

    val lat1Rad = Math.toRadians(lat1)
    val lat2Rad = Math.toRadians(lat2)
    val deltaLatRad = Math.toRadians(lat2 - lat1)
    val deltaLonRad = Math.toRadians(lon2 - lon1)

    val a = kotlin.math.sin(deltaLatRad / 2) * kotlin.math.sin(deltaLatRad / 2) +
            kotlin.math.cos(lat1Rad) * kotlin.math.cos(lat2Rad) *
            kotlin.math.sin(deltaLonRad / 2) * kotlin.math.sin(deltaLonRad / 2)

    val c = 2 * kotlin.math.atan2(kotlin.math.sqrt(a), kotlin.math.sqrt(1 - a))

    return R * c
  }

  companion object {
    const val NAME = "RnVietmapTrackingPlugin"
    const val LOCATION_PERMISSION_REQUEST_CODE = 1001
  }
}

package com.rnvietmaptrackingplugin

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.location.Location
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.core.app.ActivityCompat
import com.facebook.react.bridge.*
import com.facebook.react.modules.core.DeviceEventManagerModule
import com.facebook.react.modules.core.PermissionAwareActivity
import com.facebook.react.modules.core.PermissionListener
import com.google.android.gms.location.*
import com.google.android.gms.tasks.OnCompleteListener
import com.facebook.fbreact.specs.NativeRnVietmapTrackingPluginSpec
import java.util.Timer
import java.util.TimerTask

class RnVietmapTrackingPluginModule(reactContext: ReactApplicationContext) :
  NativeRnVietmapTrackingPluginSpec(reactContext) {

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

  companion object {
    const val NAME = "RnVietmapTrackingPlugin"
    const val LOCATION_PERMISSION_REQUEST_CODE = 1001
  }

  init {
    fusedLocationClient = LocationServices.getFusedLocationProviderClient(reactContext)
  }

  override fun getName(): String {
    return NAME
  }

  // Example method
  override fun multiply(a: Double, b: Double): Double {
    return a * b
  }

  override fun getCurrentLocation(promise: Promise) {
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

  override fun isTrackingActive(): Boolean {
    return isTracking
  }

  override fun getTrackingStatus(promise: Promise) {
    val status = Arguments.createMap().apply {
      putBoolean("isTracking", isTracking)
      if (lastLocationUpdate > 0) {
        putDouble("lastLocationUpdate", lastLocationUpdate.toDouble())
      }
      putDouble("trackingDuration", if (isTracking) (System.currentTimeMillis() - trackingStartTime).toDouble() else 0.0)
    }
    promise.resolve(status)
  }

  override fun updateTrackingConfig(config: ReadableMap, promise: Promise) {
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

  override fun requestLocationPermissions(promise: Promise) {
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

  override fun hasLocationPermissions(promise: Promise) {
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

  override fun requestAlwaysLocationPermissions(promise: Promise) {
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

  private fun startBackgroundLocationService(config: ReadableMap) {
    backgroundLocationService = Intent(reactApplicationContext, LocationTrackingService::class.java).apply {
      putExtra("config", Arguments.toBundle(config))
    }
    reactApplicationContext.startForegroundService(backgroundLocationService)
  }

  // Enhanced tracking methods for background_location_2 strategy
  override fun startTracking(backgroundMode: Boolean, intervalMs: Double, forceUpdateBackground: Boolean?, distanceFilter: Double?, promise: Promise) {
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
      if (forceUpdateBackground) {
        configureLocationRequestForForcedUpdates()
      } else {
        configureLocationRequestForContinuousUpdates()
      }

      isTracking = true
      trackingStartTime = System.currentTimeMillis()

      if (forceUpdateBackground) {
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
      val trackingMode = if (forceUpdateBackground) "forced timer" else "continuous updates"
      promise.resolve("Enhanced tracking started with $trackingMode")
    } catch (e: Exception) {
      println("❌ Failed to start enhanced tracking: ${e.message}")
      promise.reject("START_ERROR", "Failed to start tracking: ${e.message}")
    }
  }

  override fun stopTracking(promise: Promise) {
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
  }

  // MARK: - Speed Alert Methods

  override fun multiply(a: Double, b: Double): Double {
    return a * b
  }

  @ReactMethod
  override fun turnOnAlert(promise: Promise) {
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
        fusedLocationClient.requestLocationUpdates(
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
        fusedLocationClient.removeLocationUpdates(speedAlertLocationCallback)
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
      }
    }

    override fun onLocationAvailability(locationAvailability: LocationAvailability) {
      if (isSpeedAlertActive) {
        Log.d(NAME, "🚨 [SPEED ALERT] Location availability: ${locationAvailability.isLocationAvailable}")
      }
    }
  }

  @ReactMethod
  override fun turnOffAlert(promise: Promise) {
    Log.d(NAME, "🛑 Turning off speed alert")
    stopSpeedAlertLocationMonitoring()
    promise.resolve(true)
  }
}

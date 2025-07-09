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
import com.facebook.react.module.annotations.ReactModule
import com.facebook.react.modules.core.DeviceEventManagerModule
import com.facebook.react.modules.core.PermissionAwareActivity
import com.facebook.react.modules.core.PermissionListener
import com.google.android.gms.location.*
import com.google.android.gms.tasks.OnCompleteListener
import java.util.Timer
import java.util.TimerTask

@ReactModule(name = RnVietmapTrackingPluginModule.NAME)
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
    // On Android, there's no separate "Always" permission like iOS
    // Background location access is controlled by targetSdkVersion and manifest permissions
    // For API consistency, we'll just return the same as regular permission request
    Log.d("VietmapTracking", "🔐 Android: Always permission request - delegating to regular permission check")

    if (hasLocationPermissions()) {
      promise.resolve("granted")
    } else {
      // Delegate to regular permission request
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
  @ReactMethod
  fun startTracking(backgroundMode: Boolean, intervalMs: Int, forceUpdateBackground: Boolean = false, distanceFilter: Double = 10.0, promise: Promise) {
    println("🚀 Starting enhanced tracking - Background mode: $backgroundMode, Interval: ${intervalMs}ms, Force update: $forceUpdateBackground, Distance filter: ${distanceFilter}m")

    if (isTracking) {
      println("⚠️ Already tracking")
      promise.resolve("Already tracking")
      return
    }

    this.backgroundMode = backgroundMode
    this.intervalMs = intervalMs.toLong()
    this.forceUpdateBackground = forceUpdateBackground
    this.distanceFilter = distanceFilter

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

  @ReactMethod
  override fun listenerAlert(promise: Promise) {
    Log.d(NAME, "🚨 Speed alert listener initialized")
    
    // TODO: Implement speed alert logic here
    // For now, just resolve the promise to indicate the listener is active
    // In a real implementation, you would:
    // 1. Set up speed monitoring
    // 2. Configure speed limit detection  
    // 3. Monitor current speed vs speed limits
    // 4. Send speed alert events via sendEvent("onSpeedAlert", alertData)
    
    promise.resolve(null)
  }
}

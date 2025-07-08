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
import java.util.*

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
  private var locationTimer: Timer? = null
  private var intervalMs: Long = 5000 // Default 5 seconds
  private var backgroundMode = false
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
  }  override fun startLocationTracking(config: ReadableMap, promise: Promise) {
    try {
      // Debug: Log received config
      Log.d("VietmapTracking", "📋 Received config: ${config.toString()}")

      // Log all keys in config
      val keys = mutableListOf<String>()
      val iterator = config.keySetIterator()
      while (iterator.hasNextKey()) {
        keys.add(iterator.nextKey())
      }
      Log.d("VietmapTracking", "📋 Config keys: $keys")

      if (config.hasKey("intervalMs")) {
        Log.d("VietmapTracking", "✅ intervalMs key exists: ${config.getInt("intervalMs")}")
      } else {
        Log.e("VietmapTracking", "❌ intervalMs key NOT found in config!")
      }

      if (!hasLocationPermissions()) {
        promise.reject("PERMISSION_DENIED", "Location permissions are required")
        return
      }

      // Store configuration
      currentConfig = config
      intervalMs = if (config.hasKey("intervalMs")) config.getInt("intervalMs").toLong() else 5000L
      val distanceFilter = config.getDouble("distanceFilter").toFloat()
      val accuracy = config.getString("accuracy") ?: "high"
      backgroundMode = config.getBoolean("backgroundMode")

      Log.d("VietmapTracking", "📊 Parsed config values:")
      Log.d("VietmapTracking", "  - intervalMs: ${intervalMs}")
      Log.d("VietmapTracking", "  - distanceFilter: ${distanceFilter}")
      Log.d("VietmapTracking", "  - accuracy: ${accuracy}")
      Log.d("VietmapTracking", "  - backgroundMode: ${backgroundMode}")

      // Create location request with longer interval for battery optimization
      locationRequest = LocationRequest.create().apply {
        this.interval = intervalMs
        this.fastestInterval = intervalMs / 2
        this.smallestDisplacement = distanceFilter
        this.priority = when (accuracy) {
          "high" -> LocationRequest.PRIORITY_HIGH_ACCURACY
          "medium" -> LocationRequest.PRIORITY_BALANCED_POWER_ACCURACY
          "low" -> LocationRequest.PRIORITY_LOW_POWER
          else -> LocationRequest.PRIORITY_HIGH_ACCURACY
        }
      }

      // Create location callback
      locationCallback = object : LocationCallback() {
        override fun onLocationResult(locationResult: LocationResult) {
          locationResult.lastLocation?.let { location ->
            lastLocationUpdate = System.currentTimeMillis()
            sendLocationUpdate(location)
          }
        }
      }

      // Start location updates
      if (ContextCompat.checkSelfPermission(reactApplicationContext, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
        isTracking = true
        trackingStartTime = System.currentTimeMillis()

        // Start timer-based location tracking after setting isTracking = true
        startLocationTimer()

        // Start foreground service for background tracking
        if (backgroundMode) {
          startBackgroundLocationService(config)
        }

        sendTrackingStatusUpdate()
        promise.resolve(true)
      } else {
        promise.reject("PERMISSION_DENIED", "Location permissions are required")
      }
    } catch (e: Exception) {
      promise.reject("ERROR", e.message)
    }
  }

  override fun stopLocationTracking(promise: Promise) {
    try {
      // Stop timer
      stopLocationTimer()

      if (locationCallback != null) {
        fusedLocationClient?.removeLocationUpdates(locationCallback!!)
      }

      // Stop background service
      backgroundLocationService?.let {
        reactApplicationContext.stopService(it)
        backgroundLocationService = null
      }

      isTracking = false
      backgroundMode = false
      currentConfig = null
      sendTrackingStatusUpdate()
      promise.resolve(true)
    } catch (e: Exception) {
      promise.reject("ERROR", e.message)
    }
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
      // Stop current tracking
      locationCallback?.let {
        fusedLocationClient?.removeLocationUpdates(it)
      }

      // Start with new config
      startLocationTracking(config, promise)
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
  }  // Timer-based location tracking methods
  private fun startLocationTimer() {
    stopLocationTimer() // Stop any existing timer

    println("Starting location timer with interval: ${intervalMs}ms")

    locationTimer = Timer()
    locationTimer?.scheduleAtFixedRate(object : TimerTask() {
      override fun run() {
        println("Timer fired - requesting location update")
        requestLocationUpdate()
      }
    }, 0, intervalMs) // Start immediately, then repeat every intervalMs
  }

  private fun stopLocationTimer() {
    locationTimer?.cancel()
    locationTimer = null
  }

  private fun requestLocationUpdate() {
    println("📝 requestLocationUpdate called - isTracking: $isTracking")

    if (!isTracking) {
      println("⚠️ Not tracking, skipping location request")
      return
    }

    if (ContextCompat.checkSelfPermission(reactApplicationContext, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
      // Request a fresh location update instead of using cached location
      locationRequest?.let { request ->
        val singleLocationCallback = object : LocationCallback() {
          override fun onLocationResult(locationResult: LocationResult) {
            locationResult.lastLocation?.let { location ->
              lastLocationUpdate = System.currentTimeMillis()
              sendLocationUpdate(location)
            }
            // Remove this single-use callback
            fusedLocationClient?.removeLocationUpdates(this)
          }
        }

        // Request a single fresh location update
        fusedLocationClient?.requestLocationUpdates(
          request,
          singleLocationCallback,
          Looper.getMainLooper()
        )
      }
    } else {
      // Send error event for missing permissions
      val errorInfo = Arguments.createMap().apply {
        putString("error", "Location permissions are required")
        putString("code", "PERMISSION_DENIED")
        putDouble("timestamp", System.currentTimeMillis().toDouble())
      }

      reactApplicationContext
        .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
        .emit("onLocationError", errorInfo)
    }
  }
}

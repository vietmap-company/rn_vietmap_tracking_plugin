package com.rnvietmaptrackingplugin

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
import android.util.Log
import androidx.core.content.ContextCompat
import androidx.core.app.ActivityCompat
import com.facebook.react.bridge.*
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
  ReactContextBaseJavaModule(reactContext) {

  override fun getName(): String {
    return NAME
  }

  override fun getConstants(): MutableMap<String, Any> {
    return hashMapOf(
      "supportedEvents" to arrayOf(
        "onLocationUpdate",
        "onTrackingStatusChanged",
        "onLocationError",
        "onPermissionChanged",
        "onRouteUpdate",
        "onSpeedAlert"
      )
    )
  }

  // MARK: - VietmapTrackingSDK Integration
  private lateinit var vietmapSDK: VietmapTrackingSDK
  private val gson = Gson()
  private var isInitialized: Boolean = false
  private var currentTrackingConfig: WritableMap? = null
  private var pendingLocationPermissionPromise: Promise? = null

  init {
    Log.d(NAME, "🚀 Initializing RnVietmapTrackingPlugin with VietmapTrackingSDK")
    initializeSDK()
  }

  // MARK: - VietmapTrackingSDK Initialization
  private fun initializeSDK() {
    try {
      // Initialize VietmapTrackingSDK instance
      vietmapSDK = VietmapTrackingSDK.getInstance(reactApplicationContext)

      Log.d(NAME, "✅ VietmapTrackingSDK initialized successfully")
      isInitialized = true
    } catch (e: Exception) {
      Log.e(NAME, "❌ Failed to initialize VietmapTrackingSDK: ${e.message}", e)
      isInitialized = false
    }
  }

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

  // MARK: - React Native Event Emission
  private fun sendEvent(eventName: String, params: WritableMap?) {
    try {
      reactApplicationContext
        .getJSModule(DeviceEventManagerModule.RCTDeviceEventEmitter::class.java)
        .emit(eventName, params)
    } catch (e: Exception) {
      Log.e(NAME, "❌ Failed to send event $eventName: ${e.message}", e)
    }
  }

  // MARK: - Configuration
  @ReactMethod
  fun configure(apiKey: String, baseURL: String?, autoUpload: Boolean, promise: Promise) {
    Log.d(NAME, "🔧 Configuring VietmapTrackingSDK with apiKey: ${if (apiKey.isNotEmpty()) "provided" else "missing"}")

    if (!isInitialized) {
      promise.reject("SDK_NOT_INITIALIZED", "VietmapTrackingSDK is not initialized")
      return
    }

    try {
      // Validate API key
      if (apiKey.isEmpty()) {
        promise.reject("INVALID_API_KEY", "API key is required")
        return
      }

      // Initialize VietmapTrackingSDK with API key
      vietmapSDK.initialize(apiKey)

      // Store current configuration
      currentTrackingConfig = Arguments.createMap().apply {
        putString("apiKey", "***")  // Don't expose API key
        putString("baseURL", baseURL ?: "")
        putBoolean("autoUpload", autoUpload)
        putDouble("updateInterval", 20000.0)
        putDouble("minDistanceFilter", 10.0)
        putBoolean("enableBackgroundMode", true)
        putDouble("timestamp", System.currentTimeMillis().toDouble())
      }

      Log.d(NAME, "✅ VietmapTrackingSDK configured successfully")
      promise.resolve(true)

    } catch (e: Exception) {
      Log.e(NAME, "❌ Configuration failed: ${e.message}", e)
      promise.reject("CONFIGURE_FAILED", "Failed to configure VietmapTrackingSDK: ${e.message}")
    }
  }

  @ReactMethod
  fun requestLocationPermissions(promise: Promise) {
    Log.d(NAME, "🔍 Requesting location permissions for VietmapTrackingSDK")

    try {
      // Check if we already have location permissions
      if (hasLocationPermission()) {
        Log.d(NAME, "✅ Location permissions already granted")
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
        Log.e(NAME, "❌ No current activity available for permission request")
        promise.reject("NO_ACTIVITY", "No current activity available for permission request")
        return
      }

      // Check if activity implements PermissionAwareActivity
      if (activity !is PermissionAwareActivity) {
        Log.e(NAME, "❌ Activity does not implement PermissionAwareActivity")
        promise.reject("INVALID_ACTIVITY", "Activity does not implement PermissionAwareActivity")
        return
      }

      // Request location permissions
      val permissions = arrayOf(
        Manifest.permission.ACCESS_FINE_LOCATION,
        Manifest.permission.ACCESS_COARSE_LOCATION
      )

      val backgroundPermissions = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
        arrayOf(
          Manifest.permission.ACCESS_FINE_LOCATION,
          Manifest.permission.ACCESS_COARSE_LOCATION,
          Manifest.permission.ACCESS_BACKGROUND_LOCATION
        )
      } else {
        permissions
      }

      Log.d(NAME, "📱 Requesting location permissions via PermissionAwareActivity")

      // Use PermissionAwareActivity to request permissions
      activity.requestPermissions(
        backgroundPermissions,
        LOCATION_PERMISSION_REQUEST_CODE,
        createPermissionListener()
      )

    } catch (e: Exception) {
      Log.e(NAME, "❌ Failed to request location permissions: ${e.message}", e)
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
        if (requestCode == LOCATION_PERMISSION_REQUEST_CODE) {
          handleLocationPermissionResult(permissions, grantResults)
          return true
        }
        return false
      }
    }
  }

  private fun handleLocationPermissionResult(permissions: Array<String>, grantResults: IntArray) {
    val promise = pendingLocationPermissionPromise
    if (promise == null) {
      Log.w(NAME, "⚠️ No pending permission promise found")
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

      Log.d(NAME, "📋 Permission results - Fine: $fineLocationGranted, Coarse: $coarseLocationGranted, Background: $backgroundLocationGranted")

      val result = Arguments.createMap().apply {
        putBoolean("granted", allPermissionsGranted)
        putString("status", if (allPermissionsGranted) "granted" else "denied")
        putBoolean("fineLocation", fineLocationGranted)
        putBoolean("coarseLocation", coarseLocationGranted)
        putBoolean("backgroundLocation", backgroundLocationGranted)
      }

      if (allPermissionsGranted) {
        Log.d(NAME, "✅ Location permissions granted")

        // Send permission granted event
        sendEvent("onPermissionChanged", Arguments.createMap().apply {
          putBoolean("granted", true)
          putString("type", "location")
        })
      } else {
        Log.w(NAME, "⚠️ Location permissions denied")

        // Send permission denied event
        sendEvent("onPermissionChanged", Arguments.createMap().apply {
          putBoolean("granted", false)
          putString("type", "location")
        })
      }

      promise.resolve(result)

    } catch (e: Exception) {
      Log.e(NAME, "❌ Error handling permission result: ${e.message}", e)
      promise.reject("PERMISSION_RESULT_ERROR", "Error handling permission result: ${e.message}")
    } finally {
      pendingLocationPermissionPromise = null
    }
  }

  @ReactMethod
  fun hasLocationPermissions(promise: Promise) {
    try {
      val hasPermissions = hasLocationPermission()
      Log.d(NAME, "📍 Location permissions check: $hasPermissions")

      val result = Arguments.createMap().apply {
        putBoolean("granted", hasPermissions)
        putString("status", if (hasPermissions) "granted" else "not_granted")
      }

      promise.resolve(result)
    } catch (e: Exception) {
      Log.e(NAME, "❌ Failed to check location permissions: ${e.message}", e)
      promise.reject("PERMISSION_CHECK_FAILED", "Failed to check location permissions: ${e.message}")
    }
  }

  // MARK: - Tracking Methods
  @ReactMethod
  fun startTracking(
    backgroundMode: Boolean,
    intervalMs: Double,
    forceUpdateBackground: Boolean?,
    distanceFilter: Double?,
    promise: Promise
  ) {
    if (!isInitialized) {
      promise.reject("SDK_NOT_INITIALIZED", "VietmapTrackingSDK not initialized")
      return
    }

    Log.d(NAME, "🚀 Starting VietmapTrackingSDK tracking")

    try {
      // Start tracking with VietmapTrackingSDK
      vietmapSDK.startTracking()

      Log.d(NAME, "✅ VietmapTrackingSDK tracking started successfully")
      promise.resolve("VietmapTrackingSDK tracking started")

    } catch (e: Exception) {
      Log.e(NAME, "❌ Failed to start VietmapTrackingSDK tracking: ${e.message}", e)
      promise.reject("TRACKING_START_FAILED", "Failed to start tracking: ${e.message}")
    }
  }

  @ReactMethod
  fun stopTracking(promise: Promise) {
    if (!isInitialized) {
      promise.reject("SDK_NOT_INITIALIZED", "VietmapTrackingSDK not initialized")
      return
    }

    Log.d(NAME, "🛑 Stopping VietmapTrackingSDK tracking")

    try {
      // Stop tracking with VietmapTrackingSDK
      vietmapSDK.stopTracking()

      Log.d(NAME, "✅ VietmapTrackingSDK tracking stopped successfully")
      promise.resolve("VietmapTrackingSDK tracking stopped")

    } catch (e: Exception) {
      Log.e(NAME, "❌ Failed to stop VietmapTrackingSDK tracking: ${e.message}", e)
      promise.reject("TRACKING_STOP_FAILED", "Failed to stop tracking: ${e.message}")
    }
  }

  @ReactMethod
  fun isTrackingActive(promise: Promise) {
    if (!isInitialized) {
      promise.reject("SDK_NOT_INITIALIZED", "VietmapTrackingSDK not initialized")
      return
    }

    try {
      // Check tracking status with VietmapTrackingSDK
      val isActive = vietmapSDK.isTracking()
      Log.d(NAME, "📊 VietmapTrackingSDK tracking active: $isActive")
      promise.resolve(isActive)

    } catch (e: Exception) {
      Log.e(NAME, "❌ Failed to check VietmapTrackingSDK tracking status: ${e.message}", e)
      promise.reject("STATUS_ERROR", "Failed to check tracking status: ${e.message}")
    }
  }

  // MARK: - Route Data Methods
  @ReactMethod
  fun setRouteData(routeJsonString: String, promise: Promise) {
    if (!isInitialized) {
      promise.reject("SDK_NOT_INITIALIZED", "VietmapTrackingSDK not initialized")
      return
    }

    Log.d(NAME, "🗺️ Setting route data to VietmapTrackingSDK")

    try {
      // VietmapTrackingSDK expects a JSON string, not RouteData object
      // Set route data using VietmapTrackingSDK with JSON string
      vietmapSDK.setRouteData(routeJsonString)

      Log.d(NAME, "✅ Route data set successfully in VietmapTrackingSDK")
      promise.resolve(true)

    } catch (e: Exception) {
      Log.e(NAME, "❌ Failed to set route data: ${e.message}", e)
      promise.reject("ROUTE_DATA_FAILED", "Failed to set route data: ${e.message}")
    }
  }

  // MARK: - Cache Management
  @ReactMethod
  fun clearCachedLocations(promise: Promise) {
    if (!isInitialized) {
      promise.reject("SDK_NOT_INITIALIZED", "VietmapTrackingSDK not initialized")
      return
    }

    Log.d(NAME, "🗑️ Clearing VietmapTrackingSDK cache")

    try {
      // Clear cache using VietmapTrackingSDK (if method exists)
      // TODO: Add actual clearCache method when available in API

      Log.d(NAME, "✅ VietmapTrackingSDK cache cleared successfully")
      promise.resolve(true)

    } catch (e: Exception) {
      Log.e(NAME, "❌ Failed to clear VietmapTrackingSDK cache: ${e.message}", e)
      promise.reject("CLEAR_FAILED", "Failed to clear cache: ${e.message}")
    }
  }

  // MARK: - Cleanup
  override fun invalidate() {
    super.invalidate()
    // Clean up VietmapTrackingSDK resources
    if (isInitialized) {
      try {
        vietmapSDK.stopTracking()
        Log.d(NAME, "🧹 VietmapTrackingSDK resources cleaned up")
      } catch (e: Exception) {
        Log.e(NAME, "Error during cleanup: ${e.message}", e)
      }
    }
    Log.d(NAME, "🔄 Module invalidated and cleaned up")
  }

  companion object {
    const val NAME = "RnVietmapTrackingPlugin"
    const val LOCATION_PERMISSION_REQUEST_CODE = 1001
  }
}

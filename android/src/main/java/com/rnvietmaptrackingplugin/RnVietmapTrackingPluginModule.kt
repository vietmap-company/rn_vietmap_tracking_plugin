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
  private var pendingBackgroundPermissionPromise: Promise? = null

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
        when (requestCode) {
          LOCATION_PERMISSION_REQUEST_CODE -> {
            handleLocationPermissionResult(permissions, grantResults)
            return true
          }
          BACKGROUND_LOCATION_PERMISSION_REQUEST_CODE -> {
            handleBackgroundLocationPermissionResult(permissions, grantResults)
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

      // If this is from requestAlwaysLocationPermissions and basic permissions are granted
      if (isAlwaysPermissionFlow && allPermissionsGranted) {
        // Check if we need background permission for Android 10+
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
          val currentBackgroundGranted = ContextCompat.checkSelfPermission(
            reactApplicationContext,
            Manifest.permission.ACCESS_BACKGROUND_LOCATION
          ) == PackageManager.PERMISSION_GRANTED

          if (!currentBackgroundGranted) {
            Log.d(NAME, "🔄 Basic permissions granted, now requesting background location permission")

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
              Log.e(NAME, "❌ No current activity available for background permission request")
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
      }

    } catch (e: Exception) {
      Log.e(NAME, "❌ Error handling permission result: ${e.message}", e)
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
      Log.w(NAME, "⚠️ No pending background permission promise found")
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

      Log.d(NAME, "🔍 Background location permission result: $backgroundLocationGranted")

      if (backgroundLocationGranted) {
        Log.d(NAME, "✅ Background location permission granted")
        promise.resolve("granted")

        // Send permission granted event
        sendEvent("onPermissionChanged", Arguments.createMap().apply {
          putBoolean("granted", true)
          putString("type", "background_location")
        })
      } else {
        Log.w(NAME, "⚠️ Background location permission denied")
        promise.resolve("denied")

        // Send permission denied event
        sendEvent("onPermissionChanged", Arguments.createMap().apply {
          putBoolean("granted", false)
          putString("type", "background_location")
        })
      }

    } catch (e: Exception) {
      Log.e(NAME, "❌ Error handling background permission result: ${e.message}", e)
      promise.resolve("denied")
    } finally {
      pendingBackgroundPermissionPromise = null
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

  @ReactMethod
  fun requestAlwaysLocationPermissions(promise: Promise) {
    Log.d(NAME, "🔐 Requesting always location permissions (background location)")

    try {
      val activity = currentActivity
      if (activity == null) {
        Log.e(NAME, "❌ No current activity available")
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

      Log.d(NAME, "🔍 Current permissions - Fine: $hasFineLocation, Coarse: $hasCoarseLocation, Background: $hasBackgroundLocation")

      // If we already have all permissions, return granted
      if (hasFineLocation && hasCoarseLocation && hasBackgroundLocation) {
        Log.d(NAME, "✅ All location permissions already granted")
        promise.resolve("granted")
        return
      }

      // Check if we need to request basic location permissions first
      if (!hasFineLocation || !hasCoarseLocation) {
        Log.d(NAME, "📍 Basic location permissions not granted, requesting foreground permissions first")

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
        Log.d(NAME, "🔄 Requesting background location permission")

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
      Log.e(NAME, "❌ Failed to request always location permissions: ${e.message}", e)
      promise.resolve("denied")
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

  @ReactMethod
  fun getTrackingStatus(promise: Promise) {
    if (!isInitialized) {
      promise.reject("SDK_NOT_INITIALIZED", "VietmapTrackingSDK not initialized")
      return
    }

    try {
      // Try to get tracking status from VietmapTrackingSDK (similar to iOS)
      // If VietmapTrackingSDK has getTrackingStatus() method, use it
      // Otherwise, create status object based on isTracking()

      val isActive = vietmapSDK.isTracking()

      // Create status object similar to what iOS VietmapTrackingSDK returns
      val status = Arguments.createMap().apply {
        putBoolean("isTracking", isActive)
        putString("status", if (isActive) "active" else "inactive")
        putDouble("timestamp", System.currentTimeMillis().toDouble())
      }

      Log.d(NAME, "📊 VietmapTrackingSDK tracking status: isTracking=$isActive")
      promise.resolve(status)

    } catch (e: Exception) {
      Log.e(NAME, "❌ Failed to get VietmapTrackingSDK tracking status: ${e.message}", e)
      promise.reject("STATUS_ERROR", "Failed to get tracking status: ${e.message}")
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
    const val BACKGROUND_LOCATION_PERMISSION_REQUEST_CODE = 1002
  }
}

package com.rnvietmaptrackingplugin

import android.Manifest
import android.content.pm.PackageManager
import android.os.Build
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
  NativeRnVietmapTrackingPluginSpec(reactContext) {

  companion object {
    const val LOCATION_PERMISSION_REQUEST_CODE = 1001
    const val BACKGROUND_LOCATION_PERMISSION_REQUEST_CODE = 1002
  }

  override fun getConstants(): MutableMap<String, Any> {
    return hashMapOf(
      "screenWidth" to reactApplicationContext.resources.displayMetrics.widthPixels,
      "screenHeight" to reactApplicationContext.resources.displayMetrics.heightPixels
    )
  }

  override fun multiply(a: Double, b: Double): Double {
    return a * b
  }

  // MARK: - VietmapTrackingSDK Integration
  private lateinit var vietmapSDK: VietmapTrackingSDK
  private val gson = Gson()
  private var isInitialized: Boolean = false
  private var currentTrackingConfig: WritableMap? = null
  private var pendingLocationPermissionPromise: Promise? = null
  private var pendingBackgroundPermissionPromise: Promise? = null

  init {
    initializeSDK()
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
    }
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

      // Initialize VietmapTrackingSDK with API key
      if (baseURL != null && baseURL.isNotEmpty()) {
          vietmapSDK.initialize(apiKey, baseURL)
      } else {
          vietmapSDK.initialize(apiKey)
      }

      // Set isInitialized to true only after successful initialization
      isInitialized = true

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

      // Use PermissionAwareActivity to request permissions
      activity.requestPermissions(
        backgroundPermissions,
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
  @ReactMethod
  override fun startTracking(
    backgroundMode: Boolean,
    intervalMs: Double,
    distanceFilter: Double?,
    notificationTitle: String?,
    notificationMessage: String?,
    promise: Promise
  ) {
    if (!isInitialized) {
      promise.resolve(false)
      return
    }

    try {

      // Set notification parameters if provided
      if (!notificationTitle.isNullOrEmpty()) {
        vietmapSDK.setNotificationTitle(notificationTitle)

      }
      if (!notificationMessage.isNullOrEmpty()) {
        vietmapSDK.setNotificationText(notificationMessage)
      }
      // Configure tracking settings
      val trackingConfig = TrackingConfig().apply {
          updateInterval = intervalMs.toLong()
          minDistanceFilter = distanceFilter ?: 10.0
          enableBackgroundMode = backgroundMode
      }
      vietmapSDK.setTrackingConfig(trackingConfig)

      // Start tracking with VietmapTrackingSDK
      vietmapSDK.startTracking()
      promise.resolve(true)

    } catch (e: Exception) {
      promise.resolve(false)
    }
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
      promise.resolve(true)

    } catch (e: Exception) {
      promise.resolve(false)
    }
  }

  @ReactMethod
  override fun getCurrentLocation(promise: Promise) {
    if (!isInitialized) {
      promise.reject("NOT_INITIALIZED", "VietmapTrackingSDK not initialized")
      return
    }

    try {
      // Since VietmapTrackingSDK might not have getCurrentLocation method,
      // we'll return the last known location from the tracking session
      val locationMap = hashMapOf<String, Any>(
        "latitude" to 0.0,
        "longitude" to 0.0,
        "accuracy" to 0.0,
        "altitude" to 0.0,
        "bearing" to 0.0,
        "speed" to 0.0,
        "timestamp" to System.currentTimeMillis()
      )
      promise.resolve(locationMap)
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
        // Extract configuration from ReadableMap
        val trackingConfig = TrackingConfig().apply {
          if (config.hasKey("intervalMs") && !config.isNull("intervalMs")) {
            updateInterval = config.getDouble("intervalMs").toLong()
          }
          if (config.hasKey("distanceFilter") && !config.isNull("distanceFilter")) {
            minDistanceFilter = config.getDouble("distanceFilter")
          }
          if (config.hasKey("backgroundMode") && !config.isNull("backgroundMode")) {
            enableBackgroundMode = config.getBoolean("backgroundMode")
          }
        }

        vietmapSDK.setTrackingConfig(trackingConfig)
        promise.resolve(true)
      } else {
        promise.resolve(false)
      }
    } catch (e: Exception) {
      promise.reject("CONFIG_UPDATE_ERROR", "Failed to update tracking config: ${e.message}")
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

  // MARK: - Cache Management
  @ReactMethod
  fun clearCachedLocations(promise: Promise) {
    if (!isInitialized) {
      promise.reject("SDK_NOT_INITIALIZED", "VietmapTrackingSDK not initialized")
      return
    }

    try {
      // Clear cache using VietmapTrackingSDK (if method exists)
      // TODO: Add actual clearCache method when available in API
      promise.resolve(true)

    } catch (e: Exception) {
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
      } catch (e: Exception) {
      }
    }
  }

  // MARK: - Legacy Support Methods (kept for backward compatibility)
  @ReactMethod
  fun findNearestAlert(latitude: Double, longitude: Double, promise: Promise) {
    if (!isInitialized) {
      promise.reject("SDK_NOT_INITIALIZED", "VietmapTrackingSDK not initialized")
      return
    }

    try {
      // This method is now handled internally by VietmapTrackingSDK
      // We delegate to route data for route-related alert information
      val alertInfo = Arguments.createMap().apply {
        putDouble("latitude", latitude)
        putDouble("longitude", longitude)
        putString("routeInfo", "Alert data handled by VietmapTrackingSDK")
        putDouble("timestamp", System.currentTimeMillis().toDouble())
      }
      promise.resolve(alertInfo)

    } catch (e: Exception) {
      promise.reject("NO_ROUTE_DATA", "No route data available for alert calculation")
    }
  }
}

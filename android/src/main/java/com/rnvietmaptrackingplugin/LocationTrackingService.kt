package com.rnvietmaptrackingplugin

import android.app.*
import android.content.Context
import android.content.Intent
import android.location.Location
import android.os.*
import androidx.core.app.NotificationCompat
import com.google.android.gms.location.*
import android.Manifest
import android.content.pm.PackageManager
import androidx.core.content.ContextCompat

class LocationTrackingService : Service() {

    private var fusedLocationClient: FusedLocationProviderClient? = null
    private var locationRequest: LocationRequest? = null
    private var locationCallback: LocationCallback? = null
    private val binder = LocationBinder()

    companion object {
        private const val NOTIFICATION_ID = 12345
        private const val CHANNEL_ID = "location_tracking_channel"
        private const val CHANNEL_NAME = "GPS Tracking"
    }

    inner class LocationBinder : Binder() {
        fun getService(): LocationTrackingService = this@LocationTrackingService
    }

    override fun onCreate() {
        super.onCreate()
        fusedLocationClient = LocationServices.getFusedLocationProviderClient(this)
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val config = intent?.getBundleExtra("config")

        val notificationTitle = config?.getString("notificationTitle") ?: "GPS Tracking Active"
        val notificationMessage = config?.getString("notificationMessage") ?: "Your location is being tracked"

        val notification = createNotification(notificationTitle, notificationMessage)
        startForeground(NOTIFICATION_ID, notification)

        config?.let { setupLocationTracking(it) }

        return START_STICKY
    }

    override fun onBind(intent: Intent): IBinder {
        return binder
    }

    override fun onDestroy() {
        super.onDestroy()
        stopLocationTracking()
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val serviceChannel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            )
            val manager = getSystemService(NotificationManager::class.java)
            manager?.createNotificationChannel(serviceChannel)
        }
    }

    private fun createNotification(title: String, message: String): Notification {
        val notificationIntent = packageManager.getLaunchIntentForPackage(packageName)
        val pendingIntent = PendingIntent.getActivity(
            this, 0, notificationIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(message)
            .setSmallIcon(android.R.drawable.ic_menu_mylocation)
            .setContentIntent(pendingIntent)
            .setOngoing(true)
            .build()
    }

    private fun setupLocationTracking(config: Bundle) {
        val intervalMs = config.getLong("intervalMs", 5000)
        val distanceFilter = config.getDouble("distanceFilter", 10.0).toFloat()
        val accuracy = config.getString("accuracy", "high")

        locationRequest = LocationRequest.create().apply {
            interval = intervalMs
            fastestInterval = intervalMs / 2
            smallestDisplacement = distanceFilter
            priority = when (accuracy) {
                "high" -> LocationRequest.PRIORITY_HIGH_ACCURACY
                "medium" -> LocationRequest.PRIORITY_BALANCED_POWER_ACCURACY
                "low" -> LocationRequest.PRIORITY_LOW_POWER
                else -> LocationRequest.PRIORITY_HIGH_ACCURACY
            }
        }

        locationCallback = object : LocationCallback() {
            override fun onLocationResult(locationResult: LocationResult) {
                locationResult.lastLocation?.let { location ->
                    handleLocationUpdate(location)
                }
            }
        }

        startLocationUpdates()
    }

    private fun startLocationUpdates() {
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.ACCESS_FINE_LOCATION) == PackageManager.PERMISSION_GRANTED) {
            locationRequest?.let { request ->
                locationCallback?.let { callback ->
                    fusedLocationClient?.requestLocationUpdates(
                        request,
                        callback,
                        Looper.getMainLooper()
                    )
                }
            }
        }
    }

    private fun stopLocationTracking() {
        locationCallback?.let {
            fusedLocationClient?.removeLocationUpdates(it)
        }
    }

    private fun handleLocationUpdate(location: Location) {
        // Send location update via broadcast or save to local storage
        val intent = Intent("com.rnvietmaptrackingplugin.LOCATION_UPDATE")
        intent.putExtra("latitude", location.latitude)
        intent.putExtra("longitude", location.longitude)
        intent.putExtra("altitude", location.altitude)
        intent.putExtra("accuracy", location.accuracy)
        intent.putExtra("speed", location.speed)
        intent.putExtra("bearing", location.bearing)
        intent.putExtra("timestamp", location.time)
        sendBroadcast(intent)
    }
}

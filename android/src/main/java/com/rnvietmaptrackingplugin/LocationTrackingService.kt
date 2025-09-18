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
import com.vietmap.trackingsdk.*

/**
 * LocationTrackingService - Wrapper service that integrates with VietmapTrackingSDK
 * This service primarily serves as a bridge between React Native and the VietmapTrackingSDK's internal services
 */
class LocationTrackingService : Service() {

    private var trackingManager: VietmapTrackingManager? = null
    private val binder = LocationBinder()

    companion object {
        private const val NOTIFICATION_ID = 12345
        private const val CHANNEL_ID = "location_tracking_channel"
        private const val CHANNEL_NAME = "GPS Tracking"
        private const val TAG = "LocationTrackingService"
    }

    inner class LocationBinder : Binder() {
        fun getService(): LocationTrackingService = this@LocationTrackingService
    }

    override fun onCreate() {
        super.onCreate()

        // Initialize VietmapTrackingManager
        trackingManager = VietmapTrackingManager.getInstance(this)

        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {

        val config = intent?.getBundleExtra("config")

        val notificationTitle = config?.getString("notificationTitle") ?: "GPS Tracking Active"
        val notificationMessage = config?.getString("notificationMessage") ?: "Your location is being tracked"

        val notification = createNotification(notificationTitle, notificationMessage)
        startForeground(NOTIFICATION_ID, notification)

        // Let VietmapTrackingSDK handle the actual location tracking

        return START_STICKY
    }

    override fun onBind(intent: Intent): IBinder {
        return binder
    }

    override fun onDestroy() {
        super.onDestroy()

        // VietmapTrackingSDK will handle cleanup of its own services
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

    /**
     * Get the tracking manager instance for direct access if needed
     */
    fun getTrackingManager(): VietmapTrackingManager? {
        return trackingManager
    }
}

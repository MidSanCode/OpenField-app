package com.midsancode.openfield

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder

/**
 * Keeps an in-progress call alive while the app is in the background.
 *
 * Without a foreground service Android revokes microphone access for a
 * backgrounded app and eventually kills the process, which drops a call the
 * moment the user switches away from it. The `microphone` service type is what
 * declares the ongoing audio capture as intentional; the persistent
 * notification is the price the platform charges for that.
 *
 * Deliberately built on the framework notification APIs rather than
 * androidx.core, so it adds no dependency to the Android build.
 */
class CallForegroundService : Service() {

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val title = intent?.getStringExtra(EXTRA_TITLE).orEmpty()
        val notification = buildNotification(title)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
        // Not sticky: restarting without a live call would leave an orphan
        // notification and a microphone claim the app cannot justify.
        return START_NOT_STICKY
    }

    private fun buildNotification(title: String): Notification {
        val channelId = ensureChannel()
        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or immutableFlag(),
        )
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, channelId)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle(if (title.isNotEmpty()) title else "OpenField")
            .setContentText(NOTIFICATION_TEXT)
            .setSmallIcon(notificationIcon())
            .setOngoing(true)
            .setContentIntent(openApp)
            .setCategory(Notification.CATEGORY_CALL)
            .apply {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
                    @Suppress("DEPRECATION")
                    setPriority(Notification.PRIORITY_LOW)
                }
            }
            .build()
    }

    /** Creates the notification channel once (API 26+) and returns its id. */
    private fun ensureChannel(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return CHANNEL_ID
        val manager = getSystemService(NotificationManager::class.java) ?: return CHANNEL_ID
        val existing = manager.getNotificationChannel(CHANNEL_ID)
        if (existing == null) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                // LOW: the notification must be visible, not audible — the call
                // audio itself already owns the audio focus.
                NotificationManager.IMPORTANCE_LOW,
            )
            channel.setShowBadge(false)
            manager.createNotificationChannel(channel)
        }
        return CHANNEL_ID
    }

    /**
     * Prefers the app's launcher icon and falls back to a public framework
     * drawable, so the service never depends on a resource that may be renamed.
     */
    private fun notificationIcon(): Int {
        val id = resources.getIdentifier("ic_launcher", "mipmap", packageName)
        return if (id != 0) id else android.R.drawable.ic_menu_call
    }

    private fun immutableFlag(): Int =
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) PendingIntent.FLAG_IMMUTABLE else 0

    companion object {
        const val EXTRA_TITLE = "title"

        private const val CHANNEL_ID = "openfield_calls"
        private const val CHANNEL_NAME = "Ongoing calls"
        private const val NOTIFICATION_ID = 0x0F1E1D
        private const val NOTIFICATION_TEXT = "Ongoing call"
    }
}

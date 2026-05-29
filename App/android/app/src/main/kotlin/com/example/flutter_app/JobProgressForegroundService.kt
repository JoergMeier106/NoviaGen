package com.example.flutter_app

import android.app.Service
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationManagerCompat

class JobProgressForegroundService : Service() {
    override fun onCreate() {
        super.onCreate()
        JobNotificationSupport.createNotificationChannels(this)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        when (intent?.action) {
            ACTION_STOP -> stopProgressNotification()
            else -> startOrUpdateProgressNotification(intent)
        }
        return START_NOT_STICKY
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onDestroy() {
        NotificationManagerCompat.from(this).cancel(JobNotificationSupport.PROGRESS_NOTIFICATION_ID)
        super.onDestroy()
    }

    private fun startOrUpdateProgressNotification(intent: Intent?) {
        val title = intent?.getStringExtra(EXTRA_TITLE)?.takeIf { it.isNotBlank() } ?: "Job running"
        val statusText = intent?.getStringExtra(EXTRA_STATUS_TEXT).orEmpty()
        val progressText = intent?.getStringExtra(EXTRA_PROGRESS_TEXT).orEmpty()
        val progress = intent?.getIntExtra(EXTRA_PROGRESS, 0) ?: 0
        val startedAtMillis = intent?.getLongExtra(EXTRA_STARTED_AT_MILLIS, 0L)?.takeIf { it > 0L }
        val notification = JobNotificationSupport.buildProgressNotification(
            context = this,
            title = title,
            statusText = statusText,
            progressText = progressText,
            progress = progress,
            startedAtMillis = startedAtMillis,
        )
        startForeground(JobNotificationSupport.PROGRESS_NOTIFICATION_ID, notification)
        NotificationManagerCompat.from(this).notify(
            JobNotificationSupport.PROGRESS_NOTIFICATION_ID,
            notification,
        )
    }

    private fun stopProgressNotification() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        } else {
            @Suppress("DEPRECATION")
            stopForeground(true)
        }
        NotificationManagerCompat.from(this).cancel(JobNotificationSupport.PROGRESS_NOTIFICATION_ID)
        stopSelf()
    }

    companion object {
        const val ACTION_START_OR_UPDATE = "com.example.flutter_app.action.START_OR_UPDATE_JOB_PROGRESS"
        const val ACTION_STOP = "com.example.flutter_app.action.STOP_JOB_PROGRESS"
        const val EXTRA_TITLE = "title"
        const val EXTRA_STATUS_TEXT = "status_text"
        const val EXTRA_PROGRESS_TEXT = "progress_text"
        const val EXTRA_PROGRESS = "progress"
        const val EXTRA_STARTED_AT_MILLIS = "started_at_millis"
    }
}

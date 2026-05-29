package com.example.flutter_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat

object JobNotificationSupport {
    const val PROGRESS_CHANNEL_ID = "noviagen_job_progress"
    const val COMPLETION_CHANNEL_ID = "noviagen_job_completion"
    const val PROGRESS_NOTIFICATION_ID = 30101
    const val COMPLETION_NOTIFICATION_ID = 30102
    const val OPEN_GENERATE_REQUEST_CODE = 30104
    const val OPEN_MEDIA_DETAIL_REQUEST_CODE = 30105
    const val EXTRA_OPEN_GENERATE = "open_generate_page"
    const val EXTRA_OPEN_MEDIA_DETAIL_ID = "open_media_detail_id"
    const val ACTION_OPEN_GENERATE = "com.example.flutter_app.OPEN_GENERATE"
    const val ACTION_OPEN_MEDIA_DETAIL = "com.example.flutter_app.OPEN_MEDIA_DETAIL"

    fun createNotificationChannels(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val progressChannel = NotificationChannel(
            PROGRESS_CHANNEL_ID,
            "Running jobs",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Shows progress while generation jobs are running."
        }
        val completionChannel = NotificationChannel(
            COMPLETION_CHANNEL_ID,
            "Completed jobs",
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply {
            description = "Shows a summary when a generation job finishes."
        }
        manager.createNotificationChannel(progressChannel)
        manager.createNotificationChannel(completionChannel)
    }

    fun buildProgressNotification(
        context: Context,
        title: String,
        statusText: String,
        progressText: String,
        progress: Int,
        startedAtMillis: Long? = null,
    ) = NotificationCompat.Builder(context, PROGRESS_CHANNEL_ID)
        .setSmallIcon(android.R.drawable.stat_sys_download)
        .setContentTitle(title)
        .setContentText(progressText)
        .setSubText(statusText)
        .setStyle(
            NotificationCompat.BigTextStyle().bigText(
                listOf(statusText, progressText).filter { it.isNotBlank() }.joinToString("\n"),
            ),
        )
        .setProgress(100, progress.coerceIn(0, 100), false)
        .setOnlyAlertOnce(true)
        .setOngoing(true)
        .setAutoCancel(false)
        .setSilent(true)
        .setContentIntent(createOpenGeneratePendingIntent(context))
        .setCategory(NotificationCompat.CATEGORY_PROGRESS)
        .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
        .setPriority(NotificationCompat.PRIORITY_LOW)
        .apply {
            if (startedAtMillis != null && startedAtMillis > 0L) {
                setShowWhen(true)
                setWhen(startedAtMillis)
                setUsesChronometer(true)
            } else {
                setShowWhen(false)
                setUsesChronometer(false)
            }
        }
        .build()

    fun showCompletionNotification(
        context: Context,
        title: String,
        body: String,
        mediaId: String? = null,
    ) {
        val notification = NotificationCompat.Builder(context, COMPLETION_CHANNEL_ID)
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentTitle(title)
            .setContentText(body.lineSequence().firstOrNull()?.trim().orEmpty())
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setAutoCancel(true)
            .setContentIntent(createCompletionPendingIntent(context, mediaId))
            .setCategory(NotificationCompat.CATEGORY_STATUS)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setPriority(NotificationCompat.PRIORITY_DEFAULT)
            .build()
        NotificationManagerCompat.from(context).notify(COMPLETION_NOTIFICATION_ID, notification)
    }

    private fun createCompletionPendingIntent(context: Context, mediaId: String?): PendingIntent {
        val trimmedMediaId = mediaId?.trim()?.takeIf { it.isNotEmpty() }
        if (trimmedMediaId == null) {
            return createOpenGeneratePendingIntent(context)
        }
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            action = ACTION_OPEN_MEDIA_DETAIL
            putExtra(EXTRA_OPEN_MEDIA_DETAIL_ID, trimmedMediaId)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        return PendingIntent.getActivity(
            context,
            OPEN_MEDIA_DETAIL_REQUEST_CODE,
            intent,
            flags,
        )
    }

    private fun createOpenGeneratePendingIntent(context: Context): PendingIntent {
        val intent = Intent(context, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            action = ACTION_OPEN_GENERATE
            putExtra(EXTRA_OPEN_GENERATE, true)
        }
        val flags = PendingIntent.FLAG_UPDATE_CURRENT or
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                PendingIntent.FLAG_IMMUTABLE
            } else {
                0
            }
        return PendingIntent.getActivity(
            context,
            OPEN_GENERATE_REQUEST_CODE,
            intent,
            flags,
        )
    }
}

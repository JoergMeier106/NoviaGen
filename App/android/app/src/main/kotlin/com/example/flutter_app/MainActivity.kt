package com.example.flutter_app

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import android.os.Bundle
import androidx.core.app.ActivityCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private var notificationChannel: MethodChannel? = null
    private var pendingGenerateOpen = false
    private var pendingMediaDetailOpenId: String? = null
    private var notificationPermissionResult: MethodChannel.Result? = null
    private var progressServiceStarted = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleNotificationIntent(intent, deliverToFlutter = false)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleNotificationIntent(intent, deliverToFlutter = true)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        JobNotificationSupport.createNotificationChannels(this)
        notificationChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL_NAME,
        ).also { channel ->
            channel.setMethodCallHandler { call, result ->
                when (call.method) {
                    "requestNotificationPermission" -> requestNotificationPermission(result)
                    "showJobProgress" -> {
                        showJobProgress(call)
                        result.success(null)
                    }
                    "showJobCompletion" -> {
                        showJobCompletion(call)
                        result.success(null)
                    }
                    "cancelJobProgress" -> {
                        cancelJobProgress()
                        result.success(null)
                    }
                    "consumePendingGenerateOpen" -> {
                        val shouldOpen = pendingGenerateOpen
                        pendingGenerateOpen = false
                        result.success(shouldOpen)
                    }
                    "consumePendingMediaDetailOpen" -> {
                        val mediaId = pendingMediaDetailOpenId
                        pendingMediaDetailOpenId = null
                        result.success(mediaId)
                    }
                    else -> result.notImplemented()
                }
            }
        }
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        if (requestCode != REQUEST_POST_NOTIFICATIONS) {
            return
        }
        val granted = grantResults.isNotEmpty() &&
            grantResults[0] == PackageManager.PERMISSION_GRANTED
        notificationPermissionResult?.success(granted)
        notificationPermissionResult = null
    }

    private fun handleNotificationIntent(intent: Intent?, deliverToFlutter: Boolean) {
        val mediaId = intent
            ?.getStringExtra(JobNotificationSupport.EXTRA_OPEN_MEDIA_DETAIL_ID)
            ?.trim()
            ?.takeIf { it.isNotEmpty() }
        if (mediaId != null) {
            pendingGenerateOpen = false
            if (deliverToFlutter) {
                val channel = notificationChannel
                if (channel != null) {
                    channel.invokeMethod("openMediaDetail", mapOf("media_id" to mediaId))
                } else {
                    pendingMediaDetailOpenId = mediaId
                }
            } else {
                pendingMediaDetailOpenId = mediaId
            }
            return
        }

        val shouldOpenGenerate =
            intent?.getBooleanExtra(JobNotificationSupport.EXTRA_OPEN_GENERATE, false) == true
        if (!shouldOpenGenerate) {
            return
        }
        if (deliverToFlutter) {
            val channel = notificationChannel
            if (channel != null) {
                channel.invokeMethod("openGenerate", null)
            } else {
                pendingGenerateOpen = true
            }
        } else {
            pendingGenerateOpen = true
        }
    }

    private fun requestNotificationPermission(result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) {
            result.success(true)
            return
        }
        if (ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
        ) {
            result.success(true)
            return
        }
        if (notificationPermissionResult != null) {
            result.error(
                "permission_request_in_progress",
                "A notification permission request is already in progress.",
                null,
            )
            return
        }
        notificationPermissionResult = result
        ActivityCompat.requestPermissions(
            this,
            arrayOf(Manifest.permission.POST_NOTIFICATIONS),
            REQUEST_POST_NOTIFICATIONS,
        )
    }

    private fun showJobProgress(call: MethodCall) {
        if (!canPostNotifications()) {
            return
        }
        val arguments = call.arguments as? Map<*, *> ?: return
        val title = arguments["title"] as? String ?: "Job running"
        val statusText = arguments["status_text"] as? String ?: ""
        val progressText = arguments["progress_text"] as? String ?: ""
        val progress = (arguments["progress"] as? Number)?.toInt()?.coerceIn(0, 100) ?: 0
        val startedAtMillis = (arguments["started_at_millis"] as? Number)?.toLong()
        val intent = Intent(this, JobProgressForegroundService::class.java).apply {
            action = JobProgressForegroundService.ACTION_START_OR_UPDATE
            putExtra(JobProgressForegroundService.EXTRA_TITLE, title)
            putExtra(JobProgressForegroundService.EXTRA_STATUS_TEXT, statusText)
            putExtra(JobProgressForegroundService.EXTRA_PROGRESS_TEXT, progressText)
            putExtra(JobProgressForegroundService.EXTRA_PROGRESS, progress)
            if (startedAtMillis != null && startedAtMillis > 0L) {
                putExtra(JobProgressForegroundService.EXTRA_STARTED_AT_MILLIS, startedAtMillis)
            }
        }
        if (progressServiceStarted) {
            startService(intent)
        } else {
            ContextCompat.startForegroundService(this, intent)
            progressServiceStarted = true
        }
    }

    private fun showJobCompletion(call: MethodCall) {
        if (!canPostNotifications()) {
            return
        }
        cancelJobProgress()
        val arguments = call.arguments as? Map<*, *> ?: return
        val title = arguments["title"] as? String ?: "Job completed"
        val body = arguments["body"] as? String ?: ""
        val mediaId = (arguments["media_id"] as? String)?.trim()?.takeIf { it.isNotEmpty() }
        JobNotificationSupport.showCompletionNotification(this, title, body, mediaId)
    }

    private fun cancelJobProgress() {
        val intent = Intent(this, JobProgressForegroundService::class.java).apply {
            action = JobProgressForegroundService.ACTION_STOP
        }
        progressServiceStarted = false
        stopService(intent)
        NotificationManagerCompat.from(this).cancel(JobNotificationSupport.PROGRESS_NOTIFICATION_ID)
    }

    private fun canPostNotifications(): Boolean {
        return Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU ||
            ContextCompat.checkSelfPermission(
                this,
                Manifest.permission.POST_NOTIFICATIONS,
            ) == PackageManager.PERMISSION_GRANTED
    }

    companion object {
        private const val CHANNEL_NAME = "noviagen/job_notifications"
        private const val REQUEST_POST_NOTIFICATIONS = 30103
    }
}

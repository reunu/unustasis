package de.freal.unustasis.tasker

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.os.PowerManager
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import de.freal.unustasis.R
import java.util.concurrent.atomic.AtomicInteger

/**
 * Runs a Tasker action to completion and reports it back to the host.
 *
 * A broadcast receiver is the wrong place for this: once its PendingResult is
 * finished Android has no lifecycle reason to keep the process alive, and
 * connecting to the scooter and waiting for it to confirm outlasts the
 * broadcast. A foreground service does have that claim, so the action and its
 * answer survive.
 */
class TaskerActionService : Service() {

    private val inFlight = AtomicInteger(0)

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = TaskerAction.fromKey(intent?.getStringExtra(EXTRA_ACTION))
        @Suppress("DEPRECATION")
        val completionIntent = intent?.getParcelableExtra<Intent>(EXTRA_COMPLETION_INTENT)

        if (action == null) {
            stopIfIdle()
        } else if (!goForeground(action)) {
            // Android 12+ turns down a background foreground-start without an
            // exemption; the battery optimisation setting is what earns one.
            Log.w(TAG, "Not allowed to run ${action.key} in the foreground")
            reply(this, completionIntent, TaskerActionRunner.RESULT_SERVICE_BLOCKED)
            stopIfIdle()
        } else {
            inFlight.incrementAndGet()
            run(action, completionIntent)
        }
        return START_NOT_STICKY
    }

    /**
     * Runs the action on a worker thread, holding a wake lock so a dozing
     * device can't park us mid-connect.
     */
    private fun run(action: TaskerAction, completionIntent: Intent?) = Thread {
        val timeoutMs = TaskerActionRunner.DEFAULT_TIMEOUT_MS
        val wakeLock = (getSystemService(Context.POWER_SERVICE) as? PowerManager)
            ?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG)
            ?.apply { acquire(timeoutMs + WAKE_LOCK_GRACE_MS) }
        val result = try {
            TaskerActionRunner.runBlocking(applicationContext, action, timeoutMs)
        } catch (e: Exception) {
            Log.e(TAG, "${action.key} blew up", e)
            "failed:${e.message}"
        } finally {
            if (wakeLock?.isHeld == true) wakeLock.release()
        }
        Log.i(TAG, "${action.key} finished: $result")
        reply(this, completionIntent, result)
        inFlight.decrementAndGet()
        stopIfIdle()
    }.apply { name = "unustasis-tasker-${action.key}" }.start()

    private fun stopIfIdle() {
        if (inFlight.get() > 0) return
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    /** False when Android refuses the foreground start, leaving us no claim. */
    private fun goForeground(action: TaskerAction): Boolean = try {
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            notification(action),
            ServiceInfo.FOREGROUND_SERVICE_TYPE_CONNECTED_DEVICE,
        )
        true
    } catch (e: Exception) {
        false
    }

    private fun notification(action: TaskerAction): Notification {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            getSystemService(NotificationManager::class.java).createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    getString(R.string.tasker_plugin_label),
                    NotificationManager.IMPORTANCE_LOW,
                )
            )
        }
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_bg_service_small)
            .setContentTitle(getString(R.string.tasker_plugin_label))
            .setContentText(getString(action.labelRes))
            .setOngoing(true)
            .build()
    }

    companion object {
        private const val TAG = "TaskerActionService"
        private const val CHANNEL_ID = "tasker_actions"
        private const val NOTIFICATION_ID = 7317
        private const val WAKE_LOCK_TAG = "unustasis:tasker-action"
        private const val WAKE_LOCK_GRACE_MS = 5_000L
        private const val EXTRA_ACTION = "de.freal.unustasis.tasker.ACTION_KEY"
        private const val EXTRA_COMPLETION_INTENT = "de.freal.unustasis.tasker.COMPLETION_INTENT"

        /** Starts the service, returning whether Android let us. */
        fun start(context: Context, action: TaskerAction, completionIntent: Intent?): Boolean = try {
            ContextCompat.startForegroundService(
                context,
                Intent(context, TaskerActionService::class.java)
                    .putExtra(EXTRA_ACTION, action.key)
                    .putExtra(EXTRA_COMPLETION_INTENT, completionIntent),
            )
            true
        } catch (e: Exception) {
            Log.e(TAG, "Couldn't start the service for ${action.key}", e)
            false
        }

        /** Hands [result] back to the host. Only a clean "ok" counts as success. */
        fun reply(context: Context, completionIntent: Intent?, result: String) {
            if (completionIntent == null) return
            val ok = result == TaskerActionRunner.RESULT_OK
            completionIntent
                .putExtra(
                    TaskerPluginProtocol.EXTRA_RESULT_CODE,
                    if (ok) TaskerPluginProtocol.RESULT_CODE_OK else TaskerPluginProtocol.RESULT_CODE_FAILED,
                )
                .putExtra(TaskerPluginProtocol.EXTRA_VARIABLES_BUNDLE, Bundle().apply {
                    putString(TaskerPluginProtocol.VARIABLE_RESULT, result)
                    if (!ok) putString(TaskerPluginProtocol.VARIABLE_ERROR_MESSAGE, result)
                })
            try {
                context.applicationContext.sendBroadcast(completionIntent)
            } catch (e: Exception) {
                Log.e(TAG, "Couldn't report back to the host", e)
            }
        }
    }
}

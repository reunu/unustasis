package de.freal.unustasis.tasker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Bundle
import android.os.PowerManager
import android.os.SystemClock
import android.util.Log

/**
 * Fires a scooter action on Tasker's behalf and keeps the task waiting until
 * the scooter has actually done it.
 *
 * Waiting relies on the host supplying a completion intent: the broadcast is
 * released immediately and the outcome sent on once it's known. Holding the
 * broadcast open instead would deadlock, since waking the Dart side means
 * sending a broadcast of our own and the system queues that behind the one
 * still in flight.
 */
class TaskerActionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action != TaskerPluginProtocol.ACTION_FIRE_SETTING) return

        val settings = intent.getBundleExtra(TaskerPluginProtocol.EXTRA_BUNDLE)
        val action = TaskerAction.fromKey(settings?.getString(TaskerPluginProtocol.BUNDLE_KEY_ACTION))
        if (action == null) {
            Log.w(TAG, "Fired without a known action, ignoring")
            reportFailureInline()
            return
        }

        val appContext = context.applicationContext
        val completionIntent = completionIntentOf(intent)
        val pendingResult = goAsync()

        if (completionIntent != null) {
            pendingResult.setResultCodeSafely(TaskerPluginProtocol.RESULT_CODE_PENDING)
            pendingResult.finish()
            runOffThread(appContext, action) { result ->
                completionIntent
                    .putExtra(TaskerPluginProtocol.EXTRA_RESULT_CODE, resultCodeFor(result))
                    .putExtra(TaskerPluginProtocol.EXTRA_VARIABLES_BUNDLE, variablesFor(result))
                try {
                    appContext.sendBroadcast(completionIntent)
                } catch (e: Exception) {
                    Log.e(TAG, "Couldn't report ${action.key} back to the host", e)
                }
            }
        } else {
            Log.w(TAG, "No completion intent; ${action.key} can't be waited on")
            pendingResult.setResultCodeSafely(TaskerPluginProtocol.RESULT_CODE_OK)
            pendingResult.finish()
            runOffThread(appContext, action) {}
        }
    }

    /**
     * Runs the action on a worker thread, holding a wake lock so a dozing
     * device can't park us mid-connect.
     */
    private fun runOffThread(context: Context, action: TaskerAction, report: (String) -> Unit) {
        Thread {
            val timeoutMs = TaskerActionRunner.DEFAULT_TIMEOUT_MS
            val wakeLock = (context.getSystemService(Context.POWER_SERVICE) as? PowerManager)
                ?.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG)
                ?.apply { acquire(timeoutMs + WAKE_LOCK_GRACE_MS) }
            val startedAt = SystemClock.elapsedRealtime()
            try {
                val result = TaskerActionRunner.runBlocking(context, action, timeoutMs)
                Log.i(TAG, "${action.key} finished: $result after ${SystemClock.elapsedRealtime() - startedAt}ms")
                report(result)
            } catch (e: Exception) {
                Log.e(TAG, "${action.key} blew up", e)
                report("failed:${e.message}")
            } finally {
                if (wakeLock?.isHeld == true) wakeLock.release()
            }
        }.apply { name = "unustasis-tasker-${action.key}" }.start()
    }

    /** Only a clean "ok" from the scooter counts as success. */
    private fun resultCodeFor(result: String): Int =
        if (result == TaskerActionRunner.RESULT_OK) TaskerPluginProtocol.RESULT_CODE_OK
        else TaskerPluginProtocol.RESULT_CODE_FAILED

    private fun variablesFor(result: String): Bundle = Bundle().apply {
        putString(TaskerPluginProtocol.VARIABLE_RESULT, result)
        if (result != TaskerActionRunner.RESULT_OK) {
            putString(TaskerPluginProtocol.VARIABLE_ERROR_MESSAGE, result)
        }
    }

    /**
     * Tasker sends the completion intent URI-encoded as a String rather than
     * as a parcelled Intent. Other hosts may parcel it, so take either.
     */
    @Suppress("DEPRECATION")
    private fun completionIntentOf(intent: Intent): Intent? = try {
        when (val raw = intent.extras?.get(TaskerPluginProtocol.EXTRA_COMPLETION_INTENT)) {
            is Intent -> raw
            is String -> Intent.parseUri(raw, Intent.URI_INTENT_SCHEME)
            else -> null
        }
    } catch (e: Exception) {
        Log.w(TAG, "Host sent an unreadable completion intent", e)
        null
    }

    /** Result codes only mean anything on an ordered broadcast. */
    private fun reportFailureInline() {
        if (!isOrderedBroadcast) return
        runCatching { resultCode = TaskerPluginProtocol.RESULT_CODE_FAILED }
    }

    private fun PendingResult.setResultCodeSafely(code: Int) {
        runCatching { resultCode = code }
    }

    companion object {
        private const val TAG = "TaskerActionReceiver"
        private const val WAKE_LOCK_TAG = "unustasis:tasker-action"
        private const val WAKE_LOCK_GRACE_MS = 5_000L
    }
}

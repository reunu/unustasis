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
 * Tasker can be told an action is still running ([RESULT_CODE_PENDING]) and
 * given the answer later through the completion intent it supplies. That's the
 * path that lets a lock or unlock take as long as a BLE connect needs. Hosts
 * that don't supply one only get what fits inside the ordered broadcast, which
 * Android will not let us hold for long.
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
            // Release the broadcast straight away and answer once the scooter
            // has reported back, however long that takes.
            pendingResult.setResultCodeSafely(TaskerPluginProtocol.RESULT_CODE_PENDING)
            pendingResult.finish()
            runOffThread(appContext, action, TaskerActionRunner.DEFAULT_TIMEOUT_MS) { result ->
                completionIntent
                    .putExtra(TaskerPluginProtocol.EXTRA_RESULT_CODE, resultCodeFor(result))
                    .putExtra(TaskerPluginProtocol.EXTRA_VARIABLES_REPORT, variablesFor(result))
                try {
                    appContext.sendBroadcast(completionIntent)
                } catch (e: Exception) {
                    Log.e(TAG, "Couldn't report ${action.key} back to the host", e)
                }
            }
        } else {
            // Holding the broadcast open to make the host wait sounds right and
            // is a deadlock: waking the Dart side means sending a broadcast of
            // our own, and the system queues that behind the one still in
            // flight, so the action can't start until we stop waiting for it.
            // Without a completion intent there's nothing left to do but let
            // go and run it.
            Log.w(TAG, "No completion intent; ${action.key} can't be waited on")
            pendingResult.setResultCodeSafely(TaskerPluginProtocol.RESULT_CODE_OK)
            pendingResult.finish()
            runOffThread(appContext, action, TaskerActionRunner.DEFAULT_TIMEOUT_MS) {
                // runOffThread logs the outcome; nobody is waiting for it.
            }
        }
    }

    /**
     * Runs the action on a worker thread, holding a wake lock so a dozing
     * device can't park us mid-connect.
     */
    private fun runOffThread(
        context: Context,
        action: TaskerAction,
        timeoutMs: Long,
        report: (String) -> Unit,
    ) {
        Thread {
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

    /**
     * Only a clean "ok" from the scooter counts as success; everything else
     * gets its own code.
     *
     * The protocol only spells out success and a generic failure, but the
     * result code is the one channel that demonstrably reaches a task — it
     * lands in %err — while the variables report does not. So each failure
     * takes a number of its own, well above the reserved range, rather than
     * arriving as an indistinguishable 2.
     */
    private fun resultCodeFor(result: String): Int = when (result) {
        TaskerActionRunner.RESULT_OK -> TaskerPluginProtocol.RESULT_CODE_OK
        TaskerActionRunner.RESULT_NOT_CONNECTED -> 10
        TaskerActionRunner.RESULT_NO_SCOOTER_SAVED -> 11
        TaskerActionRunner.RESULT_NOT_CONFIRMED -> 12
        TaskerActionRunner.RESULT_BUSY -> 13
        TaskerActionRunner.RESULT_SERVICE_BLOCKED -> 14
        TaskerActionRunner.RESULT_TIMEOUT -> 15
        TaskerActionRunner.RESULT_DISPATCH_FAILED -> 16
        // Anything else is a thrown error carrying its own message.
        else -> TaskerPluginProtocol.RESULT_CODE_FAILED
    }

    private fun variablesFor(result: String): Bundle = Bundle().apply {
        putString(TaskerPluginProtocol.VARIABLE_RESULT, result)
        // A failing action shows only its result code in Tasker's log; handing
        // over an error message is what makes that line say why.
        if (result != TaskerActionRunner.RESULT_OK) {
            putString(TaskerPluginProtocol.VARIABLE_ERROR_MESSAGE, result)
        }
    }


    /**
     * Tasker sends the completion intent URI-encoded as a String rather than as
     * a parcelled Intent, so reading it as a Parcelable silently yields null
     * and costs the ability to answer late. Other hosts may well parcel it, so
     * take either.
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

    /**
     * Fails the action without going async. Result codes only mean anything on
     * an ordered broadcast, and setting one otherwise throws.
     */
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

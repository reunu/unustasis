package de.freal.unustasis.tasker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Hands a scooter action to [TaskerActionService] and keeps the Tasker task
 * waiting until the scooter has actually done it.
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
        if (action == null || !TaskerActionAuthorization.accepts(context, action, settings)) {
            Log.w(TAG, "Fired without an authorized action")
            reportFailureInline()
            return
        }

        val appContext = context.applicationContext
        val completionIntent = completionIntentOf(intent)
        if (completionIntent == null) {
            Log.w(TAG, "No completion intent; ${action.key} can't be waited on")
            reportFailureInline()
            return
        }

        val pendingResult = goAsync()
        // Started while we're still inside onReceive, where Android still lets
        // a receiver start a service; the action itself outlives this call.
        val started = TaskerActionService.start(appContext, action, completionIntent)
        pendingResult.setResultCodeSafely(TaskerPluginProtocol.RESULT_CODE_PENDING)
        pendingResult.finish()
        if (!started) {
            TaskerActionService.reply(appContext, completionIntent, TaskerActionRunner.RESULT_SERVICE_BLOCKED)
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
    }
}

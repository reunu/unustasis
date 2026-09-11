package de.freal.unustasis.tasker

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.content.SharedPreferences
import android.net.Uri
import android.os.SystemClock
import android.util.Log
import androidx.annotation.StringRes
import de.freal.unustasis.R
import es.antonborri.home_widget.HomeWidgetBackgroundReceiver
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

/**
 * Constants of the Locale Developer Platform plugin protocol, plus the extras
 * Tasker layers on top of it.
 *
 * The base protocol (edit activity, fire receiver, config bundle) is all that's
 * needed for the action to show up and run. Tasker's completion intent is what
 * makes it *wait*: if the host puts one in the fire intent, the plugin may
 * answer late, and Tasker blocks the task until it does or its timeout runs
 * out. Hosts without it fall back to the ordered broadcast, which can only be
 * held for a few seconds.
 */
object TaskerPluginProtocol {
    const val ACTION_EDIT_SETTING = "com.twofortyfouram.locale.intent.action.EDIT_SETTING"
    const val ACTION_FIRE_SETTING = "com.twofortyfouram.locale.intent.action.FIRE_SETTING"
    const val EXTRA_BUNDLE = "com.twofortyfouram.locale.intent.extra.BUNDLE"
    const val EXTRA_STRING_BLURB = "com.twofortyfouram.locale.intent.extra.BLURB"

    private const val TASKER_EXTRAS = "net.dinglisch.android.tasker.extras."
    const val EXTRA_COMPLETION_INTENT = TASKER_EXTRAS + "COMPLETION_INTENT"
    const val EXTRA_RESULT_CODE = TASKER_EXTRAS + "RESULT_CODE"
    const val EXTRA_VARIABLES_REPORT = TASKER_EXTRAS + "VARIABLES_REPORT"
    const val EXTRA_REQUESTED_TIMEOUT = TASKER_EXTRAS + "REQUESTED_TIMEOUT"
    const val EXTRA_RELEVANT_VARIABLES = TASKER_EXTRAS + "RELEVANT_VARIABLES"

    const val RESULT_CODE_OK = Activity.RESULT_OK
    const val RESULT_CODE_FAILED = Activity.RESULT_FIRST_USER + 1
    const val RESULT_CODE_PENDING = Activity.RESULT_FIRST_USER + 2

    /** Key of the chosen action inside our own config bundle. */
    const val BUNDLE_KEY_ACTION = "de.freal.unustasis.tasker.ACTION"

    /** Variable the plugin reports back, holding [TaskerAction] result strings. */
    const val VARIABLE_RESULT = "%unu_result"

    /**
     * Tasker's own error variable. Setting it is what puts readable text next
     * to the bare result code in Tasker's error log, instead of just "2".
     */
    const val VARIABLE_ERROR_MESSAGE = "%errmsg"
}

/**
 * The actions the Tasker plugin offers, mirroring the buttons on the home
 * screen widget. [key] is what gets stored in the Tasker config bundle and
 * handed to the background service, so it must match the action names
 * `backgroundCallback` understands in widget_handler.dart.
 */
enum class TaskerAction(val key: String, @StringRes val labelRes: Int) {
    UNLOCK("unlock", R.string.tasker_action_unlock),
    LOCK("lock", R.string.tasker_action_lock),
    OPEN_SEAT("openseat", R.string.tasker_action_open_seat);

    companion object {
        fun fromKey(key: String?): TaskerAction? = entries.firstOrNull { it.key == key }
    }
}

/**
 * Runs a widget action through the Flutter background service and waits for it
 * to report back.
 *
 * There's no direct call into the service: the same broadcast a widget button
 * press uses wakes the Dart side, which connects if needed, sends the command
 * and then waits for the scooter to report the state it was asked for. The
 * answer comes back through the SharedPreferences file Flutter already uses to
 * pass widget actions between its isolates — same process, so the write is
 * visible here as soon as it happens.
 */
object TaskerActionRunner {
    private const val TAG = "TaskerActionRunner"

    /** The file shared_preferences writes to on Android, and the prefix it adds to keys. */
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private const val FLUTTER_KEY_PREFIX = "flutter."

    /** Must match `taskerResultPrefix` in lib/background/tasker_bridge.dart. */
    private const val RESULT_PREFIX = "actionResult."

    /** Sent by HomeWidgetBackgroundIntent; the receiver only looks at the data URI. */
    private const val HOME_WIDGET_BACKGROUND_ACTION = "es.antonborri.home_widget.action.BACKGROUND"

    /**
     * A backstop for the Dart side never answering at all, not a judgement on
     * how long the scooter may take. It has to sit well above the worst case
     * the background service can spend: a cold start, a 30s BLE connect
     * timeout, and then the scooter confirming the new state. The service
     * reports its own outcome for anything it can see, so hitting this means
     * the engine or the service died on the way.
     */
    const val DEFAULT_TIMEOUT_MS = 120_000L

    private const val POLL_INTERVAL_MS = 250L

    /** Returned when the scooter never reported back in time. */
    const val RESULT_TIMEOUT = "timeout"

    /** Returned when the request couldn't even be handed to the background service. */
    const val RESULT_DISPATCH_FAILED = "dispatch_failed"

    /**
     * The outcomes the background service publishes. These must stay in step
     * with the `taskerResult*` constants in lib/background/tasker_bridge.dart.
     */
    const val RESULT_OK = "ok"
    const val RESULT_NOT_CONNECTED = "not_connected"
    const val RESULT_NO_SCOOTER_SAVED = "no_scooter_saved"
    const val RESULT_NOT_CONFIRMED = "not_confirmed"
    const val RESULT_BUSY = "busy"
    const val RESULT_SERVICE_BLOCKED = "service_blocked"

    /**
     * Triggers [action] and blocks until it finishes, [timeoutMs] elapses, or
     * the thread is interrupted. Returns one of the result strings written by
     * tasker_bridge.dart, or [RESULT_TIMEOUT] / [RESULT_DISPATCH_FAILED].
     *
     * Never call this on the main thread.
     */
    fun runBlocking(context: Context, action: TaskerAction, timeoutMs: Long = DEFAULT_TIMEOUT_MS): String {
        val requestId = UUID.randomUUID().toString()
        val prefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
        val resultKey = FLUTTER_KEY_PREFIX + RESULT_PREFIX + requestId

        val latch = CountDownLatch(1)
        val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, changedKey ->
            if (changedKey == resultKey) latch.countDown()
        }
        // Registered before the request goes out so a fast answer can't slip
        // through between dispatching and starting to wait.
        prefs.registerOnSharedPreferenceChangeListener(listener)

        try {
            if (!dispatch(context, action, requestId)) return RESULT_DISPATCH_FAILED

            val deadline = SystemClock.elapsedRealtime() + timeoutMs
            while (true) {
                if (prefs.contains(resultKey)) return readAndClear(prefs, resultKey)
                val remaining = deadline - SystemClock.elapsedRealtime()
                if (remaining <= 0) break
                val wait = minOf(remaining, POLL_INTERVAL_MS)
                // The listener wakes this the moment the result lands; the
                // short poll is a backstop in case the change never reaches us.
                // Once the latch has fired, await() stops blocking, so sleep
                // instead of spinning through what's left of the deadline.
                if (latch.count > 0L) latch.await(wait, TimeUnit.MILLISECONDS) else Thread.sleep(wait)
            }
            // One last look, in case the result landed as the deadline passed.
            if (prefs.contains(resultKey)) return readAndClear(prefs, resultKey)

            Log.w(TAG, "No result for ${action.key} after ${timeoutMs}ms")
            return RESULT_TIMEOUT
        } catch (interrupted: InterruptedException) {
            Thread.currentThread().interrupt()
            return RESULT_TIMEOUT
        } finally {
            prefs.unregisterOnSharedPreferenceChangeListener(listener)
        }
    }

    /**
     * Wakes the Dart side the same way a widget button press does. The request
     * id rides along in the URI so the background service knows to report the
     * outcome back.
     */
    private fun dispatch(context: Context, action: TaskerAction, requestId: String): Boolean =
        try {
            context.sendBroadcast(
                Intent(context, HomeWidgetBackgroundReceiver::class.java).apply {
                    this.action = HOME_WIDGET_BACKGROUND_ACTION
                    data = Uri.parse("unustasis://${action.key}?requestId=$requestId")
                }
            )
            true
        } catch (e: Exception) {
            Log.e(TAG, "Couldn't dispatch ${action.key}", e)
            false
        }

    /**
     * Results are stored as `<epochMillis>:<result>`; the timestamp is only
     * there so Dart can age out results nobody collected.
     */
    private fun readAndClear(prefs: SharedPreferences, key: String): String {
        val raw = prefs.getString(key, null)
        prefs.edit().remove(key).apply()
        return raw?.substringAfter(':', RESULT_TIMEOUT) ?: RESULT_TIMEOUT
    }
}

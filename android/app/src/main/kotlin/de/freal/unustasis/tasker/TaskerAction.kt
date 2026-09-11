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

/** Locale Developer Platform plugin protocol, plus the extras Tasker adds. */
object TaskerPluginProtocol {
    const val ACTION_FIRE_SETTING = "com.twofortyfouram.locale.intent.action.FIRE_SETTING"
    const val EXTRA_BUNDLE = "com.twofortyfouram.locale.intent.extra.BUNDLE"
    const val EXTRA_STRING_BLURB = "com.twofortyfouram.locale.intent.extra.BLURB"

    private const val TASKER_EXTRAS = "net.dinglisch.android.tasker.extras."
    const val EXTRA_COMPLETION_INTENT = TASKER_EXTRAS + "COMPLETION_INTENT"
    const val EXTRA_RESULT_CODE = TASKER_EXTRAS + "RESULT_CODE"
    const val EXTRA_VARIABLES_BUNDLE = TASKER_EXTRAS + "VARIABLES"
    const val EXTRA_REQUESTED_TIMEOUT = TASKER_EXTRAS + "REQUESTED_TIMEOUT"
    const val EXTRA_RELEVANT_VARIABLES = TASKER_EXTRAS + "RELEVANT_VARIABLES"

    const val RESULT_CODE_OK = Activity.RESULT_OK
    const val RESULT_CODE_FAILED = Activity.RESULT_FIRST_USER + 1
    const val RESULT_CODE_PENDING = Activity.RESULT_FIRST_USER + 2

    /** Key of the chosen action inside our own config bundle. */
    const val BUNDLE_KEY_ACTION = "de.freal.unustasis.tasker.ACTION"

    /** Variable the plugin reports back, holding the action's outcome. */
    const val VARIABLE_RESULT = "%unu_result"

    /** Tasker's own error variable, which its error log renders as text. */
    const val VARIABLE_ERROR_MESSAGE = "%errmsg"
}

/**
 * The actions the plugin offers, mirroring the home screen widget's buttons.
 *
 * [key] must match the action names `backgroundCallback` understands in
 * widget_handler.dart, since it's handed straight to the background service.
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
 * Runs an action through the Flutter background service and waits for it.
 *
 * There's no direct call into the service: the same broadcast a widget button
 * press uses wakes the Dart side, which connects if needed, sends the command
 * and waits for the scooter to report the state it was asked for. The answer
 * comes back through the SharedPreferences file Flutter already uses to pass
 * widget actions between its isolates — same process, so the write is visible
 * here as soon as it happens.
 */
object TaskerActionRunner {
    private const val TAG = "TaskerActionRunner"

    /** The file shared_preferences writes to, and the prefix it adds to keys. */
    private const val FLUTTER_PREFS = "FlutterSharedPreferences"
    private const val FLUTTER_KEY_PREFIX = "flutter."

    /** Must match `taskerResultPrefix` in lib/background/tasker_bridge.dart. */
    private const val RESULT_PREFIX = "actionResult."

    private const val HOME_WIDGET_BACKGROUND_ACTION = "es.antonborri.home_widget.action.BACKGROUND"
    private const val POLL_INTERVAL_MS = 250L

    /**
     * A backstop for the Dart side never answering at all, not a judgement on
     * how long the scooter may take: it sits above a cold start plus a 30s BLE
     * connect timeout plus confirmation. The service reports its own outcome
     * for anything it can see, so reaching this means it died on the way.
     */
    const val DEFAULT_TIMEOUT_MS = 120_000L

    const val RESULT_OK = "ok"
    const val RESULT_TIMEOUT = "timeout"
    const val RESULT_DISPATCH_FAILED = "dispatch_failed"

    /**
     * Triggers [action] and blocks until it finishes, [timeoutMs] elapses, or
     * the thread is interrupted. Never call this on the main thread.
     */
    fun runBlocking(context: Context, action: TaskerAction, timeoutMs: Long = DEFAULT_TIMEOUT_MS): String =
        awaitResult(context, UUID.randomUUID().toString(), timeoutMs) { dispatch(context, action, it) }

    /**
     * Waits for the background service's answer to [requestId].
     *
     * [onWatching] runs once the watch is in place and reports whether the
     * request went out, so an answer can't land before anyone is listening.
     */
    private fun awaitResult(
        context: Context,
        requestId: String,
        timeoutMs: Long,
        onWatching: (String) -> Boolean,
    ): String {
        val prefs = context.getSharedPreferences(FLUTTER_PREFS, Context.MODE_PRIVATE)
        val resultKey = FLUTTER_KEY_PREFIX + RESULT_PREFIX + requestId

        val latch = CountDownLatch(1)
        val listener = SharedPreferences.OnSharedPreferenceChangeListener { _, changedKey ->
            if (changedKey == resultKey) latch.countDown()
        }
        prefs.registerOnSharedPreferenceChangeListener(listener)

        try {
            if (!onWatching(requestId)) return RESULT_DISPATCH_FAILED

            val deadline = SystemClock.elapsedRealtime() + timeoutMs
            while (true) {
                if (prefs.contains(resultKey)) return readAndClear(prefs, resultKey)
                val remaining = deadline - SystemClock.elapsedRealtime()
                if (remaining <= 0) break
                val wait = minOf(remaining, POLL_INTERVAL_MS)
                // The listener wakes this the moment the result lands and the
                // poll is the backstop. Once the latch has fired await() stops
                // blocking, so sleep rather than spin out the deadline.
                if (latch.count > 0L) latch.await(wait, TimeUnit.MILLISECONDS) else Thread.sleep(wait)
            }
            if (prefs.contains(resultKey)) return readAndClear(prefs, resultKey)

            Log.w(TAG, "No result for $requestId after ${timeoutMs}ms")
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
     * id rides along in the URI so the service knows to report the outcome.
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

    /** Results are stored as `<epochMillis>:<result>`; Dart ages them out. */
    private fun readAndClear(prefs: SharedPreferences, key: String): String {
        val raw = prefs.getString(key, null)
        prefs.edit().remove(key).apply()
        return raw?.substringAfter(':', RESULT_TIMEOUT) ?: RESULT_TIMEOUT
    }
}

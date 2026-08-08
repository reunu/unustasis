package de.freal.unustasis.wear

import android.content.Context
import android.util.Log
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import com.google.android.gms.wearable.PutDataMapRequest
import com.google.android.gms.wearable.Wearable
import es.antonborri.home_widget.HomeWidgetPlugin
import kotlinx.coroutines.tasks.await

/**
 * Bridges the home widget's state store to a paired Wear OS device.
 *
 * The watch is not paired with the scooter, so it can't talk BLE itself. Instead it mirrors
 * whatever the phone already publishes for the home screen widget, and sends commands back
 * through the exact same entry point the widget's buttons use.
 *
 * State is published on the DataClient rather than sent as messages: DataItems are persisted
 * by the Data Layer, so a watch that reconnects (or a tile that renders while the watch app is
 * closed) still sees the last known values.
 */
object WearBridge {
    private const val TAG = "WearBridge"

    const val PATH_STATE = "/unustasis/state"
    const val PATH_ACTION = "/unustasis/action"
    const val PATH_REQUEST_STATE = "/unustasis/request-state"

    /** Actions the watch is allowed to trigger. Mirrors the widget's Glance buttons. */
    val ALLOWED_ACTIONS = setOf("lock", "unlock", "openseat")

    private const val SYNC_WORK_NAME = "wear-state-sync"

    /**
     * Schedules a state push. Called from [de.freal.unustasis.HomeWidgetReceiver] on every
     * widget update broadcast, which is also every time Dart's passToWidget() finds a change.
     *
     * This goes through WorkManager rather than goAsync() because GlanceAppWidgetReceiver
     * already claims the receiver's single PendingResult. REPLACE also coalesces the bursts
     * of updates that happen around a lock/unlock.
     */
    fun enqueueStateSync(context: Context) {
        try {
            WorkManager.getInstance(context).enqueueUniqueWork(
                SYNC_WORK_NAME,
                ExistingWorkPolicy.REPLACE,
                OneTimeWorkRequestBuilder<WearStateSyncWorker>().build(),
            )
        } catch (e: Exception) {
            Log.w(TAG, "Could not enqueue wear state sync", e)
        }
    }

    /**
     * Reads the current widget state and publishes it to the Data Layer.
     *
     * Reads [HomeWidgetPlugin.getData], i.e. the same "HomeWidgetPreferences" store that
     * HomeWidgetGlanceStateDefinition reads - deliberately not the app's own shared
     * preferences, which hold different (and for our purposes staler) data.
     */
    suspend fun pushState(context: Context) {
        val data: Map<String, Any?> = HomeWidgetPlugin.getData(context).all

        val request = PutDataMapRequest.create(PATH_STATE).apply {
            dataMap.putBoolean("connected", data.bool("connected", false))
            dataMap.putBoolean("locked", data.bool("locked", true))
            dataMap.putBoolean("seatOpenable", data.bool("seatOpenable", false))
            dataMap.putBoolean("seatClosed", data.bool("seatClosed", false))
            dataMap.putBoolean("scanning", data.bool("scanning", false))
            dataMap.putString("stateName", data.str("stateName") ?: "Unknown")
            dataMap.putString("lastPingDifference", data.str("lastPingDifference") ?: "")
            dataMap.putLong("lastPing", data.num("lastPing")?.toLong() ?: 0L)
            dataMap.putInt("soc1", data.num("soc1")?.toInt() ?: 0)
            dataMap.putInt("soc2", data.num("soc2")?.toInt() ?: 0)
            dataMap.putString("scooterName", data.str("scooterName") ?: "Unu Scooter")
            dataMap.putInt("scooterColor", data.num("scooterColor")?.toInt() ?: 1)
        }.asPutDataRequest().setUrgent()

        try {
            Wearable.getDataClient(context).putDataItem(request).await()
        } catch (e: Exception) {
            // No paired watch, no Play services, or the Data Layer is unavailable. Nothing to
            // do about it here - the watch re-requests state whenever it comes back.
            Log.d(TAG, "Wear state push failed: ${e.message}")
        }
    }
}

// The widget store is written from Dart, where an int arrives as an Integer or a Long
// depending on its magnitude (lastPing is epoch millis, so it's always a Long; soc1 isn't).
// Reading through SharedPreferences.getInt/getLong would throw on the wrong one, so go
// through the untyped map instead.
private fun Map<String, Any?>.num(key: String): Number? = this[key] as? Number

private fun Map<String, Any?>.str(key: String): String? =
    (this[key] as? String)?.takeIf { it.isNotEmpty() }

private fun Map<String, Any?>.bool(key: String, default: Boolean): Boolean =
    this[key] as? Boolean ?: default


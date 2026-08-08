package de.freal.unustasis.wear

import android.content.Context
import android.util.Log
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.tasks.await

/**
 * The watch's view of the scooter, shared by the app UI, the tile and the Data Layer listener.
 *
 * Seeded from local storage so nothing ever renders blank, then kept current by
 * [WearStateListenerService] and by explicit [refresh] calls.
 */
object WearStateRepository {
    private const val TAG = "WearStateRepository"

    private val _state = MutableStateFlow(ScooterSnapshot())
    val state: StateFlow<ScooterSnapshot> = _state.asStateFlow()

    @Volatile
    private var loadedCache = false

    /** Loads the cached snapshot once per process. Cheap to call repeatedly. */
    @Synchronized
    fun ensureInitialized(context: Context) {
        if (loadedCache) return
        loadedCache = true
        _state.value = ScooterSnapshot.load(context)
    }

    fun update(context: Context, snapshot: ScooterSnapshot) {
        _state.value = snapshot
        snapshot.save(context)
    }

    /**
     * Pulls the current DataItem directly. The listener service normally gets there first, but
     * this covers the case where the item was published while this app wasn't running.
     */
    suspend fun refresh(context: Context) {
        ensureInitialized(context)
        try {
            val items = Wearable.getDataClient(context).dataItems.await()
            try {
                items.firstOrNull { it.uri.path == WearPaths.STATE }?.let { item ->
                    update(context, ScooterSnapshot.fromDataMap(DataMapItem.fromDataItem(item).dataMap))
                }
            } finally {
                items.release()
            }
        } catch (e: Exception) {
            Log.d(TAG, "Could not read state from the Data Layer: ${e.message}")
        }
    }
}

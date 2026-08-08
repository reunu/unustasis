package de.freal.unustasis.wear

import androidx.wear.tiles.TileService
import com.google.android.gms.wearable.DataEvent
import com.google.android.gms.wearable.DataEventBuffer
import com.google.android.gms.wearable.DataMapItem
import com.google.android.gms.wearable.WearableListenerService

/**
 * Receives state pushed by the phone.
 *
 * Play services starts this even when the watch app isn't open, which is what lets the tile
 * stay current on the watch face carousel.
 */
class WearStateListenerService : WearableListenerService() {

    override fun onDataChanged(events: DataEventBuffer) {
        var changed = false
        for (event in events) {
            if (event.type != DataEvent.TYPE_CHANGED) continue
            if (event.dataItem.uri.path != WearPaths.STATE) continue

            val snapshot = ScooterSnapshot.fromDataMap(
                DataMapItem.fromDataItem(event.dataItem).dataMap
            )
            WearStateRepository.ensureInitialized(this)
            WearStateRepository.update(this, snapshot)
            changed = true
        }

        if (changed) {
            TileService.getUpdater(this).requestUpdate(ScooterTileService::class.java)
        }
    }
}

package de.freal.unustasis.wear

import android.net.Uri
import android.util.Log
import com.google.android.gms.wearable.CapabilityInfo
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.Node
import com.google.android.gms.wearable.WearableListenerService
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import kotlinx.coroutines.runBlocking

/**
 * Receives commands from the watch.
 *
 * Actions are forwarded through [HomeWidgetBackgroundIntent] - the very same broadcast the
 * Glance widget's buttons fire. That hands us Dart's backgroundCallback, which persists the
 * pending action, starts the background service if it isn't running, and reports progress back
 * through the widget state (which we then relay onwards to the watch). Nothing about the
 * command path is Wear-specific.
 *
 * Play services starts this service on demand, so it works from a cold app process.
 */
class WearMessageService : WearableListenerService() {

    override fun onMessageReceived(event: MessageEvent) {
        when (event.path) {
            WearBridge.PATH_ACTION -> {
                val action = String(event.data, Charsets.UTF_8)
                if (action !in WearBridge.ALLOWED_ACTIONS) {
                    Log.w(TAG, "Ignoring unknown action from watch: $action")
                    return
                }
                Log.d(TAG, "Watch requested action: $action")
                HomeWidgetBackgroundIntent
                    .getBroadcast(this, Uri.parse("unustasis://$action"))
                    .send()
            }

            WearBridge.PATH_REQUEST_STATE -> runBlocking { WearBridge.pushState(this@WearMessageService) }

            else -> Log.d(TAG, "Ignoring message on ${event.path}")
        }
    }

    /** A watch just showed up - make sure it starts out with current data. */
    override fun onCapabilityChanged(info: CapabilityInfo) {
        runBlocking { WearBridge.pushState(this@WearMessageService) }
    }

    override fun onPeerConnected(node: Node) {
        runBlocking { WearBridge.pushState(this@WearMessageService) }
    }

    companion object {
        private const val TAG = "WearMessageService"
    }
}

package de.freal.unustasis.wear

import android.content.Context
import android.util.Log
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.Wearable
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.tasks.await

/**
 * Finds the phone running unustasis and sends commands to it.
 *
 * The phone declares the `unustasis_phone` capability (see `app/src/main/res/values/wear.xml`),
 * which is how we tell a phone that has the app from one that merely happens to be paired.
 */
object PhoneLink {
    private const val TAG = "PhoneLink"

    private val _reachable = MutableStateFlow(true)

    /** Whether a phone with the app installed was reachable the last time we looked. */
    val reachable: StateFlow<Boolean> = _reachable.asStateFlow()

    private suspend fun phoneNodeId(context: Context): String? = try {
        Wearable.getCapabilityClient(context)
            .getCapability(WearPaths.CAPABILITY_PHONE, CapabilityClient.FILTER_REACHABLE)
            .await()
            .nodes
            .firstOrNull { it.isNearby }
            ?.id
    } catch (e: Exception) {
        Log.d(TAG, "Capability lookup failed: ${e.message}")
        null
    }

    /** Refreshes [reachable] without sending anything. */
    suspend fun refreshReachability(context: Context) {
        _reachable.value = phoneNodeId(context) != null
    }

    /**
     * Asks the phone to run one of the widget actions ("lock", "unlock", "openseat").
     *
     * Returns false when there is no phone to talk to. Success only means the message was
     * handed to the phone - the actual result comes back later as a state update, exactly like
     * it does for the home screen widget.
     */
    suspend fun sendAction(context: Context, action: String): Boolean {
        val node = phoneNodeId(context)
        if (node == null) {
            _reachable.value = false
            return false
        }
        return try {
            Wearable.getMessageClient(context)
                .sendMessage(node, WearPaths.ACTION, action.toByteArray(Charsets.UTF_8))
                .await()
            _reachable.value = true
            true
        } catch (e: Exception) {
            Log.w(TAG, "Could not send '$action' to the phone", e)
            _reachable.value = false
            false
        }
    }

    /** Nudges the phone to republish its current state (used when the app comes to the front). */
    suspend fun requestState(context: Context) {
        val node = phoneNodeId(context)
        if (node == null) {
            _reachable.value = false
            return
        }
        try {
            Wearable.getMessageClient(context)
                .sendMessage(node, WearPaths.REQUEST_STATE, ByteArray(0))
                .await()
            _reachable.value = true
        } catch (e: Exception) {
            Log.d(TAG, "State request failed: ${e.message}")
            _reachable.value = false
        }
    }
}

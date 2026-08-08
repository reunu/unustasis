package de.freal.unustasis.wear

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.lifecycleScope
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.PositionIndicator
import androidx.wear.compose.material.Scaffold
import androidx.wear.compose.material.TimeText
import androidx.wear.compose.material.Vignette
import androidx.wear.compose.material.VignettePosition
import de.freal.unustasis.wear.ui.ScooterScreen
import de.freal.unustasis.wear.ui.UnustasisWearTheme
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

class MainActivity : ComponentActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        WearStateRepository.ensureInitialized(this)
        setContent {
            UnustasisWearTheme {
                ScooterApp()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        // Opening the app should always show current data, even if we missed a push while the
        // watch was disconnected.
        lifecycleScope.launch {
            PhoneLink.refreshReachability(this@MainActivity)
            WearStateRepository.refresh(this@MainActivity)
            PhoneLink.requestState(this@MainActivity)
        }
    }
}

/** How long to keep showing a spinner before assuming the phone isn't going to answer. */
private const val PENDING_TIMEOUT_MS = 30_000L

@Composable
private fun ScooterApp() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val listState = rememberScalingLazyListState()

    val state by WearStateRepository.state.collectAsStateWithLifecycle()
    val reachable by PhoneLink.reachable.collectAsStateWithLifecycle()

    // The phone's own `scanning` flag takes a moment to come back over the Data Layer, so the
    // button spins optimistically from the tap until real state moves.
    var pendingBaseline by remember { mutableStateOf<ScooterSnapshot?>(null) }

    LaunchedEffect(pendingBaseline) {
        if (pendingBaseline != null) {
            delay(PENDING_TIMEOUT_MS)
            pendingBaseline = null
        }
    }

    LaunchedEffect(state) {
        val baseline = pendingBaseline ?: return@LaunchedEffect
        val moved = state.locked != baseline.locked ||
            state.connected != baseline.connected ||
            state.seatClosed != baseline.seatClosed ||
            state.stateName != baseline.stateName
        if (moved && !state.scanning) pendingBaseline = null
    }

    Scaffold(
        timeText = { TimeText() },
        vignette = { Vignette(vignettePosition = VignettePosition.TopAndBottom) },
        positionIndicator = { PositionIndicator(scalingLazyListState = listState) },
    ) {
        ScooterScreen(
            state = state,
            phoneReachable = reachable,
            busy = state.scanning || pendingBaseline != null,
            listState = listState,
            onAction = { action ->
                pendingBaseline = state
                scope.launch {
                    if (!PhoneLink.sendAction(context, action)) {
                        pendingBaseline = null
                    }
                }
            },
        )
    }
}

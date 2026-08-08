package de.freal.unustasis.wear.ui

import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.colorResource
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.tooling.preview.Preview
import androidx.compose.ui.unit.dp
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.ScalingLazyListState
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.Button
import androidx.wear.compose.material.ButtonDefaults
import androidx.wear.compose.material.CircularProgressIndicator
import androidx.wear.compose.material.Icon
import androidx.wear.compose.material.MaterialTheme
import androidx.wear.compose.material.Text
import de.freal.unustasis.wear.R
import de.freal.unustasis.wear.ScooterActions
import de.freal.unustasis.wear.ScooterSnapshot

/**
 * The watch app: the same information and the same two actions as the Android home screen
 * widget's large layout, minus the map button (there is nothing useful to open on a watch).
 */
@Composable
fun ScooterScreen(
    state: ScooterSnapshot,
    phoneReachable: Boolean,
    busy: Boolean,
    listState: ScalingLazyListState,
    onAction: (String) -> Unit,
) {
    ScalingLazyColumn(
        state = listState,
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        item { Header(state) }

        item {
            Text(
                text = if (state.hasData) state.stateName else stringResource(R.string.no_data),
                style = MaterialTheme.typography.title2,
                textAlign = TextAlign.Center,
                maxLines = 2,
                modifier = Modifier.padding(horizontal = 8.dp, vertical = 2.dp),
            )
        }

        if (state.hasData && (state.soc1 > 0 || state.hasSecondBattery)) {
            item { BatteryRow(state) }
        }

        item {
            ActionRow(
                state = state,
                busy = busy,
                enabled = phoneReachable,
                onAction = onAction,
            )
        }

        if (!phoneReachable) {
            item {
                Text(
                    text = stringResource(R.string.phone_unreachable),
                    style = MaterialTheme.typography.caption2,
                    color = MaterialTheme.colors.onSurfaceVariant,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp),
                )
            }
        }

        if (state.hasData) {
            item {
                Image(
                    painter = painterResource(ScooterActions.scooterBody(state.scooterColor)),
                    contentDescription = null,
                    contentScale = ContentScale.Fit,
                    modifier = Modifier
                        .fillMaxWidth()
                        .height(56.dp)
                        .padding(top = 4.dp),
                )
            }
        }
    }
}

@Composable
private fun Header(state: ScooterSnapshot) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
        modifier = Modifier.fillMaxWidth(),
    ) {
        Text(
            text = state.scooterName.ifEmpty { stringResource(R.string.app_name) },
            style = MaterialTheme.typography.caption1,
            color = MaterialTheme.colors.onSurfaceVariant,
            maxLines = 1,
        )
        if (state.lastPingDifference.isNotEmpty()) {
            Text(
                text = " · ${state.lastPingDifference}",
                style = MaterialTheme.typography.caption2,
                color = MaterialTheme.colors.onSurfaceVariant,
                maxLines = 1,
            )
        }
    }
}

@Composable
private fun BatteryRow(state: ScooterSnapshot) {
    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
        modifier = Modifier.fillMaxWidth().padding(vertical = 2.dp),
    ) {
        SingleBattery(state.soc1, stringResource(R.string.battery_primary))
        if (state.hasSecondBattery) {
            Spacer(Modifier.width(10.dp))
            SingleBattery(state.soc2, stringResource(R.string.battery_secondary))
        }
    }
}

@Composable
private fun SingleBattery(soc: Int, contentDescription: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(
            painter = painterResource(ScooterActions.batteryIcon(soc)),
            contentDescription = contentDescription,
            tint = if (ScooterActions.batteryIsLow(soc)) {
                colorResource(R.color.unu_seat_open)
            } else {
                MaterialTheme.colors.primary
            },
            modifier = Modifier.size(16.dp),
        )
        Text(
            text = stringResource(R.string.soc_percent, soc),
            style = MaterialTheme.typography.caption2,
            color = MaterialTheme.colors.onSurfaceVariant,
        )
    }
}

@Composable
private fun ActionRow(
    state: ScooterSnapshot,
    busy: Boolean,
    enabled: Boolean,
    onAction: (String) -> Unit,
) {
    val seatAvailable = ScooterActions.seatEnabled(state)
    val seatOpen = !state.seatClosed

    Row(
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.Center,
        modifier = Modifier.fillMaxWidth().padding(top = 6.dp),
    ) {
        // Seat
        Button(
            onClick = { ScooterActions.seatAction(state)?.let(onAction) },
            enabled = enabled && ScooterActions.seatAction(state) != null,
            colors = ButtonDefaults.secondaryButtonColors(),
            modifier = Modifier.size(ButtonDefaults.SmallButtonSize),
        ) {
            Icon(
                painter = painterResource(
                    when {
                        !seatAvailable -> R.drawable.ic_seatbox_disabled
                        seatOpen -> R.drawable.ic_seatbox_open
                        else -> R.drawable.ic_seatbox
                    }
                ),
                contentDescription = if (seatOpen) {
                    stringResource(R.string.seat_open)
                } else {
                    stringResource(R.string.action_seat)
                },
                tint = when {
                    !seatAvailable -> MaterialTheme.colors.onSurfaceVariant
                    seatOpen -> colorResource(R.color.unu_seat_open)
                    else -> MaterialTheme.colors.primary
                },
                modifier = Modifier.size(22.dp),
            )
        }

        Spacer(Modifier.width(12.dp))

        // Lock / unlock. Disabled while busy, but deliberately still enabled when we aren't
        // connected: the widget attempts anyway, which wakes the phone's background service.
        Button(
            onClick = { onAction(ScooterActions.powerAction(state)) },
            enabled = enabled && !busy,
            colors = ButtonDefaults.primaryButtonColors(),
            modifier = Modifier
                .size(ButtonDefaults.LargeButtonSize)
                .alpha(if (enabled) 1f else 0.5f),
        ) {
            if (busy) {
                CircularProgressIndicator(
                    indicatorColor = MaterialTheme.colors.onPrimary,
                    trackColor = Color.Transparent,
                    strokeWidth = 3.dp,
                    modifier = Modifier.size(26.dp),
                )
            } else {
                Icon(
                    painter = painterResource(
                        when {
                            !state.connected -> R.drawable.ic_lock_disabled
                            state.locked -> R.drawable.ic_lock
                            else -> R.drawable.ic_unlock
                        }
                    ),
                    contentDescription = stringResource(
                        when {
                            !state.connected -> R.string.action_connect
                            state.locked -> R.string.action_unlock
                            else -> R.string.action_lock
                        }
                    ),
                    tint = MaterialTheme.colors.onPrimary,
                    modifier = Modifier.size(28.dp),
                )
            }
        }
    }
}

@Preview(widthDp = 227, heightDp = 227, showBackground = true, backgroundColor = 0xFF000000)
@Composable
private fun ScooterScreenParkedPreview() {
    UnustasisWearTheme {
        ScooterScreen(
            state = ScooterSnapshot(
                connected = true,
                locked = true,
                seatOpenable = true,
                seatClosed = true,
                stateName = "Parked",
                lastPingDifference = "3h",
                soc1 = 82,
                soc2 = 64,
                scooterName = "Nova",
                hasData = true,
            ),
            phoneReachable = true,
            busy = false,
            listState = rememberScalingLazyListState(),
            onAction = {},
        )
    }
}

@Preview(widthDp = 227, heightDp = 227, showBackground = true, backgroundColor = 0xFF000000)
@Composable
private fun ScooterScreenDisconnectedPreview() {
    UnustasisWearTheme {
        ScooterScreen(
            state = ScooterSnapshot(
                stateName = "Disconnected",
                lastPingDifference = "2d",
                soc1 = 12,
                scooterName = "Nova",
                hasData = true,
            ),
            phoneReachable = false,
            busy = false,
            listState = rememberScalingLazyListState(),
            onAction = {},
        )
    }
}

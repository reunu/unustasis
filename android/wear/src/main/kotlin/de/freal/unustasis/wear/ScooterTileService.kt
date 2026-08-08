package de.freal.unustasis.wear

import android.content.Context
import androidx.concurrent.futures.ResolvableFuture
import androidx.core.content.ContextCompat
import androidx.wear.protolayout.ColorBuilders.argb
import androidx.wear.protolayout.DeviceParametersBuilders.DeviceParameters
import androidx.wear.protolayout.DimensionBuilders.dp
import androidx.wear.protolayout.LayoutElementBuilders
import androidx.wear.protolayout.ModifiersBuilders
import androidx.wear.protolayout.ResourceBuilders
import androidx.wear.protolayout.TimelineBuilders
import androidx.wear.protolayout.ActionBuilders
import androidx.wear.protolayout.material.Button
import androidx.wear.protolayout.material.ButtonColors
import androidx.wear.protolayout.material.Text
import androidx.wear.protolayout.material.Typography
import androidx.wear.protolayout.material.layouts.PrimaryLayout
import androidx.wear.tiles.EventBuilders
import androidx.wear.tiles.RequestBuilders
import androidx.wear.tiles.TileBuilders
import androidx.wear.tiles.TileService
import com.google.common.util.concurrent.ListenableFuture
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

/**
 * The watch-face-carousel equivalent of the phone's home screen widget: current state, battery,
 * and the seat and lock/unlock buttons.
 *
 * Renders entirely from [WearStateRepository]'s cached snapshot so it never blocks on the Data
 * Layer, and is re-rendered by [WearStateListenerService] whenever the phone pushes new state.
 *
 * Tiles can't run arbitrary click handlers, so each button carries a [ActionBuilders.LoadAction]
 * with its own id; tapping one re-enters [onTileRequest], which dispatches the command and
 * returns a layout that already shows the pending state.
 */
class ScooterTileService : TileService() {

    /** The tile just scrolled into view - a good moment to make sure it isn't showing stale data. */
    override fun onTileEnterEvent(requestParams: EventBuilders.TileEnterEvent) {
        val context = applicationContext
        scope.launch { PhoneLink.requestState(context) }
    }

    override fun onTileRequest(
        requestParams: RequestBuilders.TileRequest,
    ): ListenableFuture<TileBuilders.Tile> {
        WearStateRepository.ensureInitialized(this)

        requestParams.currentState.lastClickableId
            .takeIf { it.isNotEmpty() }
            ?.let { dispatch(it) }

        val state = WearStateRepository.state.value
        // Nothing cached yet (fresh install, or the phone hasn't published since we were
        // paired) - ask for it, and we'll be re-rendered when it lands.
        if (!state.hasData) {
            val context = applicationContext
            scope.launch { PhoneLink.requestState(context) }
        }
        val busy = state.scanning || System.currentTimeMillis() < pendingUntil

        val tile = TileBuilders.Tile.Builder()
            .setResourcesVersion(RESOURCES_VERSION)
            .setFreshnessIntervalMillis(if (busy) BUSY_REFRESH_MS else IDLE_REFRESH_MS)
            .setTileTimeline(
                TimelineBuilders.Timeline.fromLayoutElement(
                    layout(this, state, busy, requestParams.deviceConfiguration)
                )
            )
            .build()

        return ResolvableFuture.create<TileBuilders.Tile>().apply { set(tile) }
    }

    override fun onTileResourcesRequest(
        requestParams: RequestBuilders.ResourcesRequest,
    ): ListenableFuture<ResourceBuilders.Resources> {
        val resources = ResourceBuilders.Resources.Builder()
            .setVersion(RESOURCES_VERSION)
            .addImage(ID_LOCK, R.drawable.ic_lock)
            .addImage(ID_UNLOCK, R.drawable.ic_unlock)
            .addImage(ID_LOCK_DISABLED, R.drawable.ic_lock_disabled)
            .addImage(ID_SEAT, R.drawable.ic_seatbox)
            .addImage(ID_SEAT_OPEN, R.drawable.ic_seatbox_open)
            .addImage(ID_SEAT_DISABLED, R.drawable.ic_seatbox_disabled)
            .build()

        return ResolvableFuture.create<ResourceBuilders.Resources>().apply { set(resources) }
    }

    private fun dispatch(clickableId: String) {
        val state = WearStateRepository.state.value
        val action = when (clickableId) {
            ID_CLICK_POWER -> ScooterActions.powerAction(state)
            ID_CLICK_SEAT -> ScooterActions.seatAction(state)
            else -> null
        } ?: return

        pendingUntil = System.currentTimeMillis() + PENDING_TIMEOUT_MS
        val context = applicationContext
        scope.launch {
            if (!PhoneLink.sendAction(context, action)) {
                pendingUntil = 0L
                getUpdater(context).requestUpdate(ScooterTileService::class.java)
                return@launch
            }
            // The phone normally answers by pushing state, which triggers its own update. This
            // only covers the case where it never does, so we don't stay stuck on "Sending".
            delay(PENDING_TIMEOUT_MS)
            if (System.currentTimeMillis() >= pendingUntil) {
                getUpdater(context).requestUpdate(ScooterTileService::class.java)
            }
        }
    }

    companion object {
        private const val RESOURCES_VERSION = "1"

        // Deliberately process-scoped rather than tied to the service: a TileService is
        // unbound almost as soon as onTileRequest returns, which would cancel the message
        // we just sent.
        private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

        private const val ID_CLICK_POWER = "power"
        private const val ID_CLICK_SEAT = "seat"

        private const val ID_LOCK = "lock"
        private const val ID_UNLOCK = "unlock"
        private const val ID_LOCK_DISABLED = "lock_disabled"
        private const val ID_SEAT = "seat_closed"
        private const val ID_SEAT_OPEN = "seat_open"
        private const val ID_SEAT_DISABLED = "seat_disabled"

        private const val PENDING_TIMEOUT_MS = 30_000L
        private const val BUSY_REFRESH_MS = 10_000L
        private const val IDLE_REFRESH_MS = 15 * 60 * 1000L

        @Volatile
        private var pendingUntil: Long = 0L

        private fun ResourceBuilders.Resources.Builder.addImage(id: String, resId: Int) =
            addIdToImageMapping(
                id,
                ResourceBuilders.ImageResource.Builder()
                    .setAndroidResourceByResId(
                        ResourceBuilders.AndroidImageResourceByResId.Builder()
                            .setResourceId(resId)
                            .build()
                    )
                    .build()
            )

        private fun layout(
            context: Context,
            state: ScooterSnapshot,
            busy: Boolean,
            device: DeviceParameters,
        ): LayoutElementBuilders.LayoutElement {
            val onSurface = ContextCompat.getColor(context, R.color.unu_on_surface)
            val onSurfaceVariant = ContextCompat.getColor(context, R.color.unu_on_surface_variant)

            val body = LayoutElementBuilders.Column.Builder()
                .setHorizontalAlignment(LayoutElementBuilders.HORIZONTAL_ALIGN_CENTER)
                .addContent(
                    Text.Builder(
                        context,
                        if (state.hasData) state.stateName else context.getString(R.string.no_data),
                    )
                        .setTypography(Typography.TYPOGRAPHY_TITLE3)
                        .setColor(argb(onSurface))
                        .setMaxLines(2)
                        .build()
                )
                .apply {
                    batterySummary(state)?.let { summary ->
                        addContent(
                            Text.Builder(context, summary)
                                .setTypography(Typography.TYPOGRAPHY_CAPTION2)
                                .setColor(argb(onSurfaceVariant))
                                .setMaxLines(1)
                                .build()
                        )
                    }
                }
                .addContent(
                    LayoutElementBuilders.Spacer.Builder().setHeight(dp(8f)).build()
                )
                .addContent(
                    if (busy) {
                        Text.Builder(context, context.getString(R.string.sending))
                            .setTypography(Typography.TYPOGRAPHY_CAPTION1)
                            .setColor(argb(onSurfaceVariant))
                            .build()
                    } else {
                        buttonRow(context, state)
                    }
                )
                .build()

            return PrimaryLayout.Builder(device)
                .setResponsiveContentInsetEnabled(true)
                .setPrimaryLabelTextContent(
                    Text.Builder(context, primaryLabel(context, state))
                        .setTypography(Typography.TYPOGRAPHY_CAPTION2)
                        .setColor(argb(onSurfaceVariant))
                        .setMaxLines(1)
                        .build()
                )
                .setContent(body)
                .build()
        }

        private fun primaryLabel(context: Context, state: ScooterSnapshot): String {
            val name = state.scooterName.ifEmpty { context.getString(R.string.app_name) }
            return if (state.lastPingDifference.isNotEmpty()) {
                "$name · ${state.lastPingDifference}"
            } else {
                name
            }
        }

        private fun batterySummary(state: ScooterSnapshot): String? = when {
            !state.hasData -> null
            state.hasSecondBattery -> "${state.soc1}% · ${state.soc2}%"
            state.soc1 > 0 -> "${state.soc1}%"
            else -> null
        }

        private fun buttonRow(
            context: Context,
            state: ScooterSnapshot,
        ): LayoutElementBuilders.LayoutElement {
            val primary = ContextCompat.getColor(context, R.color.unu_primary)
            val onPrimary = ContextCompat.getColor(context, R.color.unu_on_primary)
            val surfaceVariant = ContextCompat.getColor(context, R.color.unu_surface_variant)
            val onSurfaceVariant = ContextCompat.getColor(context, R.color.unu_on_surface_variant)
            val seatOpenColor = ContextCompat.getColor(context, R.color.unu_seat_open)

            val seatAvailable = ScooterActions.seatEnabled(state)
            val seatOpen = !state.seatClosed

            val seatButton = Button.Builder(context, clickable(ID_CLICK_SEAT))
                .setContentDescription(
                    context.getString(if (seatOpen) R.string.seat_open else R.string.action_seat)
                )
                .setIconContent(
                    when {
                        !seatAvailable -> ID_SEAT_DISABLED
                        seatOpen -> ID_SEAT_OPEN
                        else -> ID_SEAT
                    }
                )
                .setButtonColors(
                    ButtonColors(
                        surfaceVariant,
                        when {
                            !seatAvailable -> onSurfaceVariant
                            seatOpen -> seatOpenColor
                            else -> primary
                        },
                    )
                )
                .build()

            val powerButton = Button.Builder(context, clickable(ID_CLICK_POWER))
                .setContentDescription(
                    context.getString(
                        when {
                            !state.connected -> R.string.action_connect
                            state.locked -> R.string.action_unlock
                            else -> R.string.action_lock
                        }
                    )
                )
                .setIconContent(
                    when {
                        !state.connected -> ID_LOCK_DISABLED
                        state.locked -> ID_LOCK
                        else -> ID_UNLOCK
                    }
                )
                .setButtonColors(ButtonColors(primary, onPrimary))
                .build()

            return LayoutElementBuilders.Row.Builder()
                .setVerticalAlignment(LayoutElementBuilders.VERTICAL_ALIGN_CENTER)
                .addContent(seatButton)
                .addContent(LayoutElementBuilders.Spacer.Builder().setWidth(dp(8f)).build())
                .addContent(powerButton)
                .build()
        }

        private fun clickable(id: String) = ModifiersBuilders.Clickable.Builder()
            .setId(id)
            .setOnClick(ActionBuilders.LoadAction.Builder().build())
            .build()
    }
}

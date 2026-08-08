package de.freal.unustasis.wear

/**
 * The button behaviour of the Android home screen widget, in one place, so the watch app and
 * the tile can't drift apart from it or from each other.
 *
 * Mirrors `HomeWidgetGlanceAppWidget.SinglePowerButton` and the seat segment of
 * `AdvancedPowerButton` in the `:app` module.
 */
object ScooterActions {

    /**
     * What the lock/unlock button does. When we aren't connected the widget still fires
     * "unlock" - that wakes the background service, which connects and then acts - so the watch
     * does the same rather than sitting there disabled.
     */
    fun powerAction(state: ScooterSnapshot): String =
        if (state.connected && !state.locked) WearPaths.ACTION_LOCK else WearPaths.ACTION_UNLOCK

    /**
     * What the seat button does, or null when it should do nothing. Connected-but-not-ready is
     * the only case the widget treats as a no-op; while disconnected it attempts anyway.
     */
    fun seatAction(state: ScooterSnapshot): String? = when {
        state.connected && state.seatOpenable -> WearPaths.ACTION_OPEN_SEAT
        !state.connected -> WearPaths.ACTION_OPEN_SEAT
        else -> null
    }

    fun seatEnabled(state: ScooterSnapshot): Boolean =
        state.connected && state.seatOpenable

    /** The widget's battery icon buckets. */
    fun batteryIcon(soc: Int): Int = when {
        soc > 85 -> R.drawable.ic_battery_100
        soc > 75 -> R.drawable.ic_battery_85
        soc > 60 -> R.drawable.ic_battery_75
        soc > 40 -> R.drawable.ic_battery_60
        soc > 25 -> R.drawable.ic_battery_40
        soc > 10 -> R.drawable.ic_battery_25
        soc > 0 -> R.drawable.ic_battery_10
        else -> R.drawable.ic_battery_0
    }

    /** The widget turns the battery red below 15%. */
    fun batteryIsLow(soc: Int): Boolean = soc <= 15

    private val scooterBodies = intArrayOf(
        R.drawable.base_0, R.drawable.base_1, R.drawable.base_2, R.drawable.base_3,
        R.drawable.base_4, R.drawable.base_5, R.drawable.base_6, R.drawable.base_7,
        R.drawable.base_8, R.drawable.base_9,
    )

    fun scooterBody(colorIndex: Int): Int =
        scooterBodies[colorIndex.coerceIn(0, scooterBodies.lastIndex)]
}

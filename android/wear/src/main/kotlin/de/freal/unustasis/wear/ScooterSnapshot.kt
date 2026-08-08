package de.freal.unustasis.wear

import android.content.Context
import androidx.core.content.edit
import com.google.android.gms.wearable.DataMap

/**
 * Everything the watch knows about the scooter.
 *
 * These are the same values the Android home screen widget renders from - the phone reads its
 * widget store and republishes it here, so watch and widget can never disagree.
 */
data class ScooterSnapshot(
    val connected: Boolean = false,
    val locked: Boolean = true,
    val seatOpenable: Boolean = false,
    // Defaults match the Glance widget's reads so the two surfaces can't disagree.
    val seatClosed: Boolean = false,
    val scanning: Boolean = false,
    val stateName: String = "",
    val lastPingDifference: String = "",
    val lastPing: Long = 0L,
    val soc1: Int = 0,
    val soc2: Int = 0,
    val scooterName: String = "",
    val scooterColor: Int = 1,
    /** False until the phone has sent us anything at all. */
    val hasData: Boolean = false,
) {
    /** Only draw a second battery when the scooter actually reports one, like the widget does. */
    val hasSecondBattery: Boolean get() = soc2 > 0

    companion object {
        private const val PREFS = "wear_scooter_state"

        fun fromDataMap(map: DataMap): ScooterSnapshot = ScooterSnapshot(
            connected = map.getBoolean("connected", false),
            locked = map.getBoolean("locked", true),
            seatOpenable = map.getBoolean("seatOpenable", false),
            seatClosed = map.getBoolean("seatClosed", false),
            scanning = map.getBoolean("scanning", false),
            stateName = map.getString("stateName", ""),
            lastPingDifference = map.getString("lastPingDifference", ""),
            lastPing = map.getLong("lastPing", 0L),
            soc1 = map.getInt("soc1", 0),
            soc2 = map.getInt("soc2", 0),
            scooterName = map.getString("scooterName", ""),
            scooterColor = map.getInt("scooterColor", 1),
            hasData = true,
        )

        /**
         * The tile and a freshly launched app both need something to draw before the Data Layer
         * hands anything over, so every snapshot is mirrored into local storage.
         */
        fun load(context: Context): ScooterSnapshot {
            val p = context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            if (!p.getBoolean("hasData", false)) return ScooterSnapshot()
            return ScooterSnapshot(
                connected = p.getBoolean("connected", false),
                locked = p.getBoolean("locked", true),
                seatOpenable = p.getBoolean("seatOpenable", false),
                seatClosed = p.getBoolean("seatClosed", false),
                // Never restore a spinner from cache: if the process died mid-action it would
                // spin forever with nothing left to clear it.
                scanning = false,
                stateName = p.getString("stateName", "") ?: "",
                lastPingDifference = p.getString("lastPingDifference", "") ?: "",
                lastPing = p.getLong("lastPing", 0L),
                soc1 = p.getInt("soc1", 0),
                soc2 = p.getInt("soc2", 0),
                scooterName = p.getString("scooterName", "") ?: "",
                scooterColor = p.getInt("scooterColor", 1),
                hasData = true,
            )
        }
    }

    fun save(context: Context) {
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE).edit {
            putBoolean("connected", connected)
            putBoolean("locked", locked)
            putBoolean("seatOpenable", seatOpenable)
            putBoolean("seatClosed", seatClosed)
            putBoolean("scanning", scanning)
            putString("stateName", stateName)
            putString("lastPingDifference", lastPingDifference)
            putLong("lastPing", lastPing)
            putInt("soc1", soc1)
            putInt("soc2", soc2)
            putString("scooterName", scooterName)
            putInt("scooterColor", scooterColor)
            putBoolean("hasData", hasData)
        }
    }
}

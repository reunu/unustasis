package de.freal.unustasis

import HomeWidgetGlanceState
import HomeWidgetGlanceStateDefinition
import android.content.Context
import android.content.Intent
import android.icu.text.CaseMap.Title
import android.net.Uri
import android.os.Build
import androidx.compose.runtime.Composable
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.graphics.Color
import androidx.glance.*
import androidx.glance.action.*
import androidx.glance.appwidget.*
import androidx.glance.appwidget.action.*
import androidx.glance.appwidget.components.SquareIconButton
import androidx.glance.color.ColorProvider
import androidx.glance.layout.*
import androidx.glance.layout.padding
import androidx.glance.text.*
import de.freal.unustasis.R.drawable.ic_lock
import de.freal.unustasis.R.drawable.ic_unlock
import de.freal.unustasis.R.drawable.ic_lock_disabled
import de.freal.unustasis.R.drawable.ic_battery_0
import de.freal.unustasis.R.drawable.ic_battery_10
import de.freal.unustasis.R.drawable.ic_battery_25
import de.freal.unustasis.R.drawable.ic_battery_40
import de.freal.unustasis.R.drawable.ic_battery_60
import de.freal.unustasis.R.drawable.ic_battery_75
import de.freal.unustasis.R.drawable.ic_battery_85
import de.freal.unustasis.R.drawable.ic_battery_100
import de.freal.unustasis.R.drawable.ic_location
import de.freal.unustasis.R.drawable.ic_location_disabled
import de.freal.unustasis.R.drawable.ic_seatbox
import de.freal.unustasis.R.drawable.ic_seatbox_open
import de.freal.unustasis.R.drawable.ic_seatbox_disabled
import de.freal.unustasis.R.drawable.base_0
import de.freal.unustasis.R.drawable.base_1
import de.freal.unustasis.R.drawable.base_2
import de.freal.unustasis.R.drawable.base_3
import de.freal.unustasis.R.drawable.base_4
import de.freal.unustasis.R.drawable.base_5
import de.freal.unustasis.R.drawable.base_6
import de.freal.unustasis.R.drawable.base_7
import de.freal.unustasis.R.drawable.base_8
import de.freal.unustasis.R.drawable.base_9

import es.antonborri.home_widget.HomeWidgetBackgroundIntent

class HomeWidgetGlanceAppWidget : GlanceAppWidget() {

    private val SCOOTER_BASE_IMAGES = intArrayOf(
        R.drawable.base_0,
        R.drawable.base_1,
        R.drawable.base_2,
        R.drawable.base_3,
        R.drawable.base_4,
        R.drawable.base_5,
        R.drawable.base_6,
        R.drawable.base_7,
        R.drawable.base_8,
        R.drawable.base_9
    )

    companion object {
        private val TINY = DpSize(100.dp, 90.dp)
        private val FLAT_BAR = DpSize(200.dp, 40.dp)
        private val REGULAR_BAR = DpSize(200.dp, 90.dp)
        private val LONG_BAR = DpSize(300.dp, 90.dp)
        private val REGULAR_PILLAR = DpSize(100.dp, 180.dp)
        private val LONG_PILLAR = DpSize(100.dp, 270.dp)
        private val FULL_RECTANGLE = DpSize(250.dp, 225.dp)
    }

    override val sizeMode = SizeMode.Responsive(
        setOf(
            TINY,
            FLAT_BAR,
            REGULAR_BAR,
            LONG_BAR,
            REGULAR_PILLAR,
            LONG_PILLAR,
            FULL_RECTANGLE
        )
    )

    /** Needed for Updating */
    override val stateDefinition = HomeWidgetGlanceStateDefinition()

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent { GlanceContent(context, currentState()) }
    }

    object UnuDefaultColorScheme {
        // TODO
    }

    val actionUriStringKey = ActionParameters.Key<String>(
        "actionUriString"
    )

    @Composable
    private fun GlanceContent(context: Context, currentState: HomeWidgetGlanceState) {
        val size = LocalSize.current
        val data = currentState.preferences

        val locked : Boolean = data.getBoolean("locked", true)
        val seatOpenable : Boolean = data.getBoolean("seatOpenable", false)
        val seatClosed: Boolean = data.getBoolean("seatClosed", false)
        val stateName : String = data.getString("stateName", "Unknown")!!
        val connected : Boolean = data.getBoolean("connected", false)
        val scanning : Boolean = data.getBoolean("scanning", false)
        val lastPing : String? = data.getString("lastPingDifference", null)
        val soc1: Int = data.getInt("soc1", 0)
        val soc2 : Int = data.getInt("soc2", 0)
        val scooterName : String = data.getString("scooterName", "Unu Scooter")!!
        val scooterColor : Int = data.getInt("scooterColor", 1)
        val lastLat : String? = data.getString("lastLat", null)
        val lastLon : String? = data.getString("lastLon", null)
        val debugText : String = size.width.toString() + "x" + size.height.toString()

        GlanceTheme(
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S)
                GlanceTheme.colors
            else
            // TODO default theme
                GlanceTheme.colors
        ) {
            Box(
                modifier =
                GlanceModifier.background(GlanceTheme.colors.widgetBackground)
                    .cornerRadius(24.dp)
                    .padding(16.dp, 12.dp)
                    .clickable(actionStartActivity<MainActivity>())
            ) {
                if (size.width <= TINY.width && size.height < REGULAR_PILLAR.height) {
                    // teeny tiny square option
                    Column(
                        verticalAlignment = Alignment.Vertical.CenterVertically,
                        horizontalAlignment = Alignment.Horizontal.CenterHorizontally,
                        modifier = GlanceModifier.fillMaxSize()
                    ) {
                        SinglePowerButton(
                            scanning = scanning,
                            enabled = connected,
                            locked = locked
                        )
                        Text(
                            text = stateName,
                            maxLines = 1,
                            style = TextStyle(
                                fontSize = 16.sp,
                                fontWeight = FontWeight.Medium,
                                color = GlanceTheme.colors.onBackground,
                            ),
                            modifier = GlanceModifier.padding(top = 8.dp),
                        )
                    }
                } else if (size.height <= REGULAR_BAR.height) {
                    // wide enough, but not tall enough
                    Row(
                        modifier = GlanceModifier.fillMaxSize(),
                        verticalAlignment = Alignment.Vertical.CenterVertically,
                    ) {
                        Column(
                            horizontalAlignment = Alignment.Horizontal.Start,
                            modifier = GlanceModifier
                                .padding(0.dp, 0.dp, 16.dp, 0.dp)
                                .defaultWeight()
                        ) {
                            if(size.height > FLAT_BAR.height) Header(
                                scooterName = scooterName,
                                lastPing = lastPing,
                                center = false,
                            )
                            StateText(
                                stateName = stateName,
                                centerText = false,
                                singleLine = size.width < LONG_BAR.width,
                            )
                            if (size.width >= LONG_BAR.width)
                                BatteryWidget(soc1, soc2)

                        }
                        SinglePowerButton(
                            scanning = scanning,
                            enabled = connected,
                            locked = locked
                        )
                    }

                } else if (size.width <= TINY.width && size.height >= REGULAR_PILLAR.height){
                    // tall and thin pillar
                    Column(
                        horizontalAlignment = Alignment.Horizontal.CenterHorizontally,
                        modifier = GlanceModifier.fillMaxSize().padding(vertical = 16.dp),
                    ) {
                        if(size.height >= LONG_PILLAR.height){
                            Header(
                                scooterName = scooterName,
                                lastPing = lastPing,
                                center = true,
                                modifier = GlanceModifier.padding(bottom = 4.dp)
                            )
                        }
                        Spacer(GlanceModifier.defaultWeight())
                        StateText(
                            stateName = stateName,
                            centerText = true,
                            singleLine = false,
                            modifier = GlanceModifier.padding(bottom = 4.dp)
                        )
                        BatteryWidget(soc1, soc2, true)
                        Spacer(GlanceModifier.defaultWeight())
                        SinglePowerButton(
                            scanning = scanning,
                            enabled = connected,
                            locked = locked
                        )
                    }
                } else {
                    // big, full version
                Column(
                        modifier = GlanceModifier.fillMaxSize().padding(vertical = 8.dp),
                        horizontalAlignment = Alignment.Horizontal.Start,
                    ) {
                        Header(
                            scooterName = scooterName,
                            lastPing = lastPing,
                            center = false,
                            modifier = GlanceModifier.fillMaxWidth()
                        )
                        Row(
                            horizontalAlignment = Alignment.Horizontal.Start,
                            verticalAlignment = Alignment.Vertical.CenterVertically,
                            modifier = GlanceModifier.defaultWeight().fillMaxWidth()
                        ) {
                            Column(
                                horizontalAlignment = Alignment.Horizontal.Start,
                                verticalAlignment = Alignment.Vertical.CenterVertically,
                            ) {
                                Spacer(GlanceModifier.defaultWeight())
                                StateText(
                                    stateName = stateName,
                                    centerText = false,
                                    singleLine = false,
                                    modifier = GlanceModifier.padding(bottom = 4.dp)
                                )
                                BatteryWidget(soc1, soc2)
                                Spacer(GlanceModifier.defaultWeight())
                            }
                            Spacer(GlanceModifier.defaultWeight())
                            Image(
                                provider = ImageProvider(SCOOTER_BASE_IMAGES[scooterColor]),
                                contentDescription = "Scooter",
                                modifier = GlanceModifier.padding(bottom = 4.dp).width(80.dp),
                                contentScale = ContentScale.Fit
                            )
                        }
                        AdvancedPowerButton(
                            scanning = scanning,
                            enabled = connected,
                            locked = locked,
                            seatClosed = seatClosed,
                            lastLat = lastLat,
                            lastLon = lastLon,
                            scooterName = scooterName,
                            seatOpenable = seatOpenable,
                        )
                    }
                }
            }
        }
    }

    @Composable
    fun Header(
        scooterName: String = "Unu Scooter Pro",
        lastPing: String? = null,
        center: Boolean = false,
        modifier: GlanceModifier = GlanceModifier,
    ) {
        Row(
            verticalAlignment = Alignment.Vertical.CenterVertically,
            modifier = modifier,
        ) {
            Text(
                scooterName,
                style = TextStyle(
                    color = GlanceTheme.colors.secondary,
                    textAlign = if (center) TextAlign.Center else TextAlign.Start,
                )
            )
            Spacer(modifier = GlanceModifier.width(4.dp))
            if (lastPing != null)
                Text(
                    "($lastPing)",
                    style = TextStyle(
                        color = GlanceTheme.colors.secondary,
                        textAlign = if (center) TextAlign.Center else TextAlign.Start,
                    )
                )
        }
    }
    
    @Composable
    fun StateText(
        stateName: String,
        centerText: Boolean = false,
        singleLine: Boolean = false,
        modifier: GlanceModifier = GlanceModifier,
    ) {
        Text(
            text = stateName,
            style = TextStyle(
                fontSize = 20.sp,
                fontWeight = FontWeight.Bold,
                color = GlanceTheme.colors.onBackground,
                textAlign = if (centerText) TextAlign.Center else TextAlign.Start,

                ),
            maxLines = if (singleLine) 1 else 2,
            modifier = modifier.padding(bottom = 4.dp)
        )
    }

    @Composable
    fun BatteryWidget(
        soc1: Int,
        soc2: Int,
        center: Boolean? = false,
        modifier: GlanceModifier = GlanceModifier,
    ) {
        Row (
            horizontalAlignment = if(center == true) Alignment.Horizontal.CenterHorizontally else Alignment.Horizontal.Start,
            verticalAlignment = Alignment.Vertical.CenterVertically,
            modifier = modifier.width(160.dp)
        ){
            SingleBattery(soc1)
            if(soc2 > 0) Spacer(GlanceModifier.width(8.dp))
            if(soc2 > 0) SingleBattery(soc2)
        }
    }


    @Composable
    fun SingleBattery(
        soc: Int,
        modifier: GlanceModifier = GlanceModifier
    ) {
        Row(
            verticalAlignment = Alignment.Vertical.CenterVertically,
            modifier = modifier
        ){
            Image(
                provider = ImageProvider(
                    if (soc > 85) ic_battery_100
                    else if (soc > 75) ic_battery_85
                    else if (soc > 60) ic_battery_75
                    else if (soc > 40) ic_battery_60
                    else if (soc > 25) ic_battery_40
                    else if (soc > 10) ic_battery_25
                    else if (soc > 0) ic_battery_10
                    else ic_battery_0),
                colorFilter = ColorFilter.tint(
                    if (soc>15)
                        GlanceTheme.colors.primary
                    else androidx.glance.unit.ColorProvider(
                        Color.Red
                    )
                ),
                contentDescription = "Battery icon",
                modifier = GlanceModifier
                    .size(20.dp)
            )
            Text("$soc%", style = TextStyle(color = GlanceTheme.colors.secondary))
        }
    }

    @Composable
    fun SinglePowerButton(
        scanning: Boolean,
        enabled: Boolean,
        locked: Boolean?)
    {

        if(scanning)
            Box(
                modifier = GlanceModifier
                    .size(64.dp)
                    .background(if(enabled) GlanceTheme.colors.primary else GlanceTheme.colors.surfaceVariant)
                    .cornerRadius(16.dp),
                contentAlignment = Alignment.Center
            ) {
                CircularProgressIndicator(
                    color = if(enabled) GlanceTheme.colors.onPrimary else GlanceTheme.colors.primary,
                    modifier = GlanceModifier
                        .size(32.dp)
                )
            }
        else
            SquareIconButton(
                imageProvider = ImageProvider(if(enabled) {
                    if(locked == true) ic_lock else ic_unlock
                } else ic_lock_disabled),
                contentDescription = if(enabled) {
                    if(locked == true) "Unlock" else "Lock"
                } else "Scan",
                onClick =
                if(locked == false && enabled){
                    actionRunCallback<LockAction>()
                } else if (locked == true && enabled){
                    actionRunCallback<UnlockAction>()
                } else {
                    // not connected, attempt anyways
                    actionRunCallback<UnlockAction>()
                },
                backgroundColor = if(enabled) GlanceTheme.colors.primary else GlanceTheme.colors.surfaceVariant,
                modifier = GlanceModifier
                    .size(64.dp)
                    .cornerRadius(16.dp),
                contentColor = if(enabled) GlanceTheme.colors.onPrimary else GlanceTheme.colors.secondary,
            )
    }

    @Composable
    fun AdvancedPowerButton(
        scanning: Boolean,
        enabled: Boolean,
        locked: Boolean?,
        seatClosed: Boolean?,
        seatOpenable: Boolean,
        lastLat: String?,
        lastLon: String?,
        scooterName: String,
        modifier: GlanceModifier = GlanceModifier,
    ){

        val hasLocation: Boolean = lastLat != null &&
                lastLat != "0.0" &&
                lastLon != null &&
                lastLon != "0.0"


        // Create the Intent for opening the map
        val openMapIntent = Intent(Intent.ACTION_VIEW).apply {
            data = Uri.parse("geo:0,0?q=$lastLat,$lastLon($scooterName)")
        }

                Row (
                    horizontalAlignment = Alignment.Horizontal.CenterHorizontally,
                    verticalAlignment = Alignment.Vertical.CenterVertically,
                    modifier = modifier
                        .fillMaxWidth()
                        .height(64.dp)
                        .cornerRadius(16.dp)
                ){
                    Box (
                        contentAlignment = Alignment.Center,
                        modifier = GlanceModifier
                            .fillMaxHeight()
                            .background(
                                if (hasLocation) {
                                    GlanceTheme.colors.primaryContainer
                                } else {
                                    GlanceTheme.colors.surfaceVariant
                                }
                            )
                            .defaultWeight()
                    ){
                        SquareIconButton(
                            imageProvider = if(hasLocation) ImageProvider(ic_location) else ImageProvider(ic_location_disabled),
                            contentDescription = "Last known location",
                            backgroundColor = if (hasLocation) {
                                GlanceTheme.colors.primaryContainer
                            } else {
                                GlanceTheme.colors.surfaceVariant
                            },
                            contentColor = if(hasLocation){
                                GlanceTheme.colors.primary
                            } else {
                                GlanceTheme.colors.secondary
                            },
                            onClick = actionStartActivity(openMapIntent),
                            modifier = GlanceModifier
                                    .fillMaxSize(),
                        )
                    }
                    Box(
                        GlanceModifier
                            .fillMaxHeight()
                            .background(GlanceTheme.colors.widgetBackground)
                            .width(4.dp)
                    ) {}
                    Box(
                        contentAlignment = Alignment.Center,
                        modifier = GlanceModifier
                            .fillMaxHeight()
                            .background(if (enabled && seatOpenable) {
                                GlanceTheme.colors.primaryContainer
                            } else {
                                GlanceTheme.colors.surfaceVariant
                            })
                            .defaultWeight()
                    ) {
                        SquareIconButton(
                            imageProvider = ImageProvider(if(enabled && seatOpenable) if (seatClosed == false) ic_seatbox_open else ic_seatbox else ic_seatbox_disabled),
                            contentDescription = "Seatbox ${if (seatClosed == false) "open" else "closed"}",
                            backgroundColor = if (enabled && seatOpenable) {
                                GlanceTheme.colors.primaryContainer
                            } else {
                                GlanceTheme.colors.surfaceVariant
                            },
                            contentColor =
                            if (!enabled || !seatOpenable) {
                                GlanceTheme.colors.secondary
                            } else if (seatClosed == false) {
                                androidx.glance.unit.ColorProvider(Color.Red)
                            } else {
                                GlanceTheme.colors.primary
                            },
                            onClick = if(enabled && seatOpenable){
                                actionRunCallback<OpenSeatAction>()
                            } else if (!enabled){
                                actionRunCallback<OpenSeatAction>()
                            } else {
                               actionRunCallback<VoidAction>()
                            },
                            enabled = enabled,
                            modifier = GlanceModifier
                                    .fillMaxSize(),
                        )
                    }
                    Box(
                        GlanceModifier
                            .fillMaxHeight()
                            .background(GlanceTheme.colors.widgetBackground)
                            .width(4.dp)

                    ) {}
                    Box (
                        contentAlignment = Alignment.Center,
                        modifier = GlanceModifier
                            .fillMaxHeight()
                            .defaultWeight()
                            .background(if(enabled){
                                GlanceTheme.colors.primary
                            } else {
                                GlanceTheme.colors.surfaceVariant
                            })
                    ){
                        if(scanning){
                            CircularProgressIndicator(
                                color = if(enabled) GlanceTheme.colors.onPrimary else GlanceTheme.colors.primary,
                                modifier = GlanceModifier
                                    .size(32.dp)

                            )
                        } else {
                            SquareIconButton(
                                imageProvider = ImageProvider(if(enabled) if (locked == false && enabled) ic_unlock else ic_lock else ic_lock_disabled),
                                contentDescription = " ${if (locked == false) "Unlock" else "Lock"} scooter",
                                contentColor = if(enabled) GlanceTheme.colors.onPrimary else GlanceTheme.colors.secondary,
                                backgroundColor = if(enabled){
                                    GlanceTheme.colors.primary
                                } else {
                                    GlanceTheme.colors.surfaceVariant
                                },
                                onClick =
                                if(locked == false && enabled){
                                    actionRunCallback<LockAction>()
                                } else if (locked == true && enabled){
                                    actionRunCallback<UnlockAction>()
                                } else {
                                    actionRunCallback<UnlockAction>()
                                },
                                modifier = GlanceModifier
                                    .fillMaxSize(),
                           )
                        }
                    }
                }

        }



}

class LockAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val backgroundIntent = HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("unustasis://lock"))
        backgroundIntent.send()
    }
}

class UnlockAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val backgroundIntent = HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("unustasis://unlock"))
        backgroundIntent.send()
    }
}

class OpenSeatAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val backgroundIntent = HomeWidgetBackgroundIntent.getBroadcast(context, Uri.parse("unustasis://openseat"))
        backgroundIntent.send()
    }
}

class VoidAction : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        // Do nothing
    }
}




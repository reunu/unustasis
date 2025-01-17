package de.freal.unustasis

import HomeWidgetGlanceState
import HomeWidgetGlanceStateDefinition
import android.content.Context
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
import de.freal.unustasis.R.drawable.ic_battery_0
import de.freal.unustasis.R.drawable.ic_battery_10
import de.freal.unustasis.R.drawable.ic_battery_25
import de.freal.unustasis.R.drawable.ic_battery_40
import de.freal.unustasis.R.drawable.ic_battery_60
import de.freal.unustasis.R.drawable.ic_battery_75
import de.freal.unustasis.R.drawable.ic_battery_85
import de.freal.unustasis.R.drawable.ic_battery_100
import de.freal.unustasis.R.drawable.ic_location
import de.freal.unustasis.R.drawable.ic_seatbox
import de.freal.unustasis.R.drawable.ic_seatbox_open
import es.antonborri.home_widget.HomeWidgetBackgroundIntent

class HomeWidgetGlanceAppWidget : GlanceAppWidget() {

    companion object {
        private val TINY = DpSize(100.dp, 100.dp)
        private val REGULAR_BAR = DpSize(200.dp, 100.dp)
        private val LONG_BAR = DpSize(300.dp, 100.dp)
        private val REGULAR_PILLAR = DpSize(100.dp, 200.dp)
        private val LONG_PILLAR = DpSize(100.dp, 300.dp)
        private val FLAT_RECTANGLE = DpSize(200.dp, 200.dp)
        private val FULL_RECTANGLE = DpSize(250.dp, 250.dp)
    }

    override val sizeMode = SizeMode.Responsive(
        setOf(
            TINY,
            REGULAR_BAR,
            LONG_BAR,
            REGULAR_PILLAR,
            LONG_PILLAR,
            FLAT_RECTANGLE,
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

    val actionKey = ActionParameters.Key<String>(
    "actionUriString"
    )

    fun getStateName(state: Int): String {
        when (state) {
            0 -> return "Stand-by"
            1 -> return "Off"
            2 -> return "Parked"
            3 -> return "Shutting down"
            4 -> return "Ready"
            5 -> return "Hibernating"
            6 -> return "Hibernating soon"
            7 -> return "Booting"
            8 -> return "Unknown"
            9 -> return "Linking"
            10 -> return "Disconnected"
            else -> {
                return "Unknown"
            }
        }
    }

    @Composable
    private fun GlanceContent(context: Context, currentState: HomeWidgetGlanceState) {
        val size = LocalSize.current
        val data = currentState.preferences

        val state = data.getInt("state", 8)
        val connected = data.getBoolean("connected", false)
        val scanning = data.getBoolean("scanning", false)
        val lastPing = data.getString("lastPing", "")
        val soc1 = data.getInt("soc1", 0)
        val soc2 = data.getInt("soc2", 0)
        val scooterName = data.getString("scooterName", "Unu Scooter")!!

        val title =
            if (scanning) "Scanning..." else getStateName(state)

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
            ) {
                if (size.width <= TINY.width && size.height < REGULAR_PILLAR.height) {
                    Column(
                        verticalAlignment = Alignment.Vertical.CenterVertically,
                        horizontalAlignment = Alignment.Horizontal.CenterHorizontally,
                        modifier = GlanceModifier.fillMaxSize()
                    ) {
                        SinglePowerButton(
                            scanning = scanning,
                            enabled = connected,
                            locked = state == 2
                        )
                        Text(
                            text = title,
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
                            Header(
                                scooterName = scooterName,
                                lastPing = lastPing,
                                showPing = false,
                                center = false,
                            )
                            StateText(
                                state = state,
                                centerText = false,
                                singleLine = size.width < LONG_BAR.width,
                            )
                            if (size.width >= LONG_BAR.width)
                                BatteryWidget(soc1, soc2, compact = false)

                        }
                        SinglePowerButton(
                            scanning = scanning,
                            enabled = connected,
                            locked = state == 2
                        )
                    }

                } else if (size.width <= TINY.width && size.height >= REGULAR_PILLAR.height){
                    Column(
                        horizontalAlignment = Alignment.Horizontal.CenterHorizontally,
                        modifier = GlanceModifier.fillMaxSize().padding(vertical = 16.dp),
                    ) {
                        if(size.height >= LONG_PILLAR.height){
                            Header(
                                scooterName = scooterName,
                                showPing = false,
                                lastPing = lastPing,
                                center = true,
                                modifier = GlanceModifier.padding(bottom = 4.dp)
                            )
                        }
                        Spacer(GlanceModifier.defaultWeight())
                        StateText(
                            state = state,
                            centerText = true,
                            singleLine = false,
                            modifier = GlanceModifier.padding(bottom = 4.dp)
                        )
                        if(size.height >= LONG_PILLAR.height) BatteryWidget(soc1, soc2, stacked = true)
                        else BatteryWidget(soc1, soc2, compact = true)
                        Spacer(GlanceModifier.defaultWeight())
                        SinglePowerButton(
                            scanning = scanning,
                            enabled = connected,
                            locked = state == 2
                        )
                    }
                } else {
                Column(
                        modifier = GlanceModifier.fillMaxSize().padding(vertical = 8.dp),
                        horizontalAlignment = Alignment.Horizontal.Start,
                    ) {
                        Header(
                            scooterName = scooterName,
                            showPing = true,
                            lastPing = lastPing,
                            center = false,
                            modifier = GlanceModifier.fillMaxWidth()
                        )
                        Spacer(GlanceModifier.defaultWeight())
                        StateText(
                            state = state,
                            centerText = false,
                            singleLine = false,
                            modifier = GlanceModifier.padding(bottom = 4.dp)
                        )
                        BatteryWidget(soc1, soc2, compact = false, stacked = size.height > FLAT_RECTANGLE.height)
                        Spacer(GlanceModifier.defaultWeight())
                        AdvancedPowerButton(
                            scanning = scanning,
                            enabled = connected,
                            locked = state == 2,
                            seatOpen = null,
                            lastLat = null,
                            lastLon = null,
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
        showPing: Boolean = false,
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
            Spacer(modifier = GlanceModifier.defaultWeight())
            if (showPing && lastPing != null)
                Text(
                    lastPing,
                    style = TextStyle(
                        color = GlanceTheme.colors.secondary,
                        textAlign = if (center) TextAlign.Center else TextAlign.Start,
                    )
                )
        }
    }
    
    @Composable
    fun StateText(
        state: Int,
        centerText: Boolean = false,
        singleLine: Boolean = false,
        modifier: GlanceModifier = GlanceModifier,
    ) {
        Text(
            text = getStateName(state),
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
        stacked: Boolean = false,
        compact: Boolean = false,
        modifier: GlanceModifier = GlanceModifier,
    ) {
       if(stacked)
           Column (
               modifier = modifier
           ){
               SingleBattery(soc1, compact, modifier = GlanceModifier.defaultWeight())
               if(soc2 > 0) Spacer(GlanceModifier.height(4.dp))
               if(soc2 > 0) SingleBattery(soc2, compact, modifier = GlanceModifier.defaultWeight())
           }
        else
            Row (
                modifier = modifier
            ){
                SingleBattery(soc1, compact, modifier = GlanceModifier.defaultWeight())
                if(soc2 > 0) Spacer(GlanceModifier.width(8.dp))
                if(soc2 > 0) SingleBattery(soc2, compact, modifier = GlanceModifier.defaultWeight())
            }
    }


    @Composable
    fun SingleBattery(
        soc: Int,
        compact: Boolean = false,
        modifier: GlanceModifier = GlanceModifier
    ) {
        Row(
            verticalAlignment = Alignment.Vertical.CenterVertically,
            modifier = modifier
        ){
            if(compact) {
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
                        .size(24.dp)
                )
            } else {
                LinearProgressIndicator(
                    progress = soc / 100f,
                    color = GlanceTheme.colors.primary,
                    backgroundColor = GlanceTheme.colors.secondaryContainer,
                    modifier = GlanceModifier
                        .height(8.dp)
                        .width(80.dp)
                        .padding(0.dp, 0.dp, 4.dp, 0.dp),
                )
            }
            Text("$soc%", style = TextStyle(color = GlanceTheme.colors.secondary))
        }
    }

    @Composable
    fun SinglePowerButton(
        scanning: Boolean,
        enabled: Boolean,
        locked: Boolean?)
    {
        val powerActionUriString = if (locked == true) "unustasis://unlock" else if (locked == false) "unustasis://lock" else "unustasis://scan";
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
                } else ic_lock),
                contentDescription = if(enabled) {
                    if(locked == true) "Unlock" else "Lock"
                } else "Scan",
                onClick =
                    actionRunCallback<InteractiveAction>(
                        actionParametersOf(actionKey to powerActionUriString)
                    ),
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
        seatOpen: Boolean?,
        lastLat: Double?,
        lastLon: Double?,
        modifier: GlanceModifier = GlanceModifier,
    ){
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
                            .background(GlanceTheme.colors.primaryContainer)
                            .defaultWeight()
                    ){
                        SquareIconButton(
                            imageProvider = ImageProvider(ic_location),
                            contentDescription = "Last known location",
                            backgroundColor = GlanceTheme.colors.primaryContainer,
                            contentColor = GlanceTheme.colors.primary,
                            onClick =
                            actionRunCallback<OpenLocation>(),
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
                            .background(if (enabled) GlanceTheme.colors.primaryContainer else GlanceTheme.colors.surfaceVariant)
                            .defaultWeight()
                    ) {
                        SquareIconButton(
                            imageProvider = ImageProvider(if (seatOpen == true) ic_seatbox_open else ic_seatbox),
                            contentDescription = "Seatbox ${if (seatOpen == true) "open" else "closed"}",
                            backgroundColor = GlanceTheme.colors.surfaceVariant,
                            contentColor =
                            if (!enabled) {
                                GlanceTheme.colors.secondary
                            } else if (seatOpen == true) {
                                androidx.glance.unit.ColorProvider(Color.Red)
                            } else {
                                GlanceTheme.colors.primary
                            },
                            onClick = actionRunCallback<Ping>(),
                            enabled = enabled,
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
                            .background(if(enabled) GlanceTheme.colors.primary else GlanceTheme.colors.surfaceVariant)
                    ){
                        if(scanning){
                            CircularProgressIndicator(
                                color = if(enabled) GlanceTheme.colors.onPrimary else GlanceTheme.colors.primary,
                                modifier = GlanceModifier
                                    .size(32.dp)

                            )
                        } else {
                            SquareIconButton(
                                imageProvider = ImageProvider(if (locked == false && enabled) ic_unlock else ic_lock),
                                contentDescription = " ${if (locked == false) "Unlock" else "Lock"} scooter",
                                contentColor = if(enabled) GlanceTheme.colors.onPrimary else GlanceTheme.colors.secondary,
                                backgroundColor = if(enabled) GlanceTheme.colors.primary else GlanceTheme.colors.surfaceVariant,
                                onClick =
                                actionRunCallback<InteractiveAction>(
                                    // TODO
                                ),
                                modifier = GlanceModifier
                                    .fillMaxSize(),
                           )
                        }
                    }
                }

        }



}

class OpenLocation : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val backgroundIntent = HomeWidgetBackgroundIntent.getBroadcast(
            context,
            Uri.parse("unustasis://openLocation")
        )
        backgroundIntent.send()
    }
}

class Ping : ActionCallback {
    override suspend fun onAction(context: Context, glanceId: GlanceId, parameters: ActionParameters) {
        val backgroundIntent = HomeWidgetBackgroundIntent.getBroadcast(
            context,
            Uri.parse("unustasis://ping")
        )
        backgroundIntent.send()
    }
}

class InteractiveAction(
    private val actionUri: String
) : ActionCallback {

    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters
    ) {
        val backgroundIntent =
            HomeWidgetBackgroundIntent.getBroadcast(
                context, Uri.parse(actionUri)
            )
        backgroundIntent.send()
    }
}


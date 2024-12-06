package de.freal.unustasis

import HomeWidgetGlanceState
import HomeWidgetGlanceStateDefinition
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import android.content.Context
import android.graphics.BitmapFactory
import android.net.Uri
import android.os.Build
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.*
import androidx.glance.action.*
import androidx.glance.appwidget.*
import androidx.glance.appwidget.action.*
import androidx.glance.color.ColorProvider
import androidx.glance.color.ColorProviders
import androidx.glance.color.colorProviders
import androidx.glance.layout.*
import androidx.glance.text.*
import androidx.glance.material3.ColorProviders

class HomeWidgetGlanceAppWidget : GlanceAppWidget() {

    /** Needed for Updating */
    override val stateDefinition = HomeWidgetGlanceStateDefinition()

    override suspend fun provideGlance(context: Context, id: GlanceId) {
        provideContent { GlanceContent(context, currentState()) }
    }

    object UnuDefaultColorScheme {
        // TODO
    }

    @Composable
    private fun GlanceContent(context: Context, currentState: HomeWidgetGlanceState) {
        val data = currentState.preferences

        val connected = data.getBoolean("connected", false)!!
        val scanning = data.getBoolean("scanning", false)!!
        val poweredOn = data.getBoolean("poweredOn", false)!!
        val tick = data.getInt("tick", 0)!!
        val soc1 = data.getInt("soc1", 0)!!
        val soc2 = data.getInt("soc2", 0)!!

        val title =
            if (poweredOn) "Powered On" else if (connected) "Connected" else if (scanning) "Scanning..." else "Disconnected"

        val actionUriStringKey = ActionParameters.Key<String>(
            "actionUriString"
        )
        val powerActionUriString = if (poweredOn) "unustasis://lock" else "unustasis://unlock";

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
                    .padding(16.dp).cornerRadius(32.dp)
            ) {
                Column(
                    modifier = GlanceModifier.fillMaxSize(),
                    verticalAlignment = Alignment.Vertical.CenterVertically,
                    horizontalAlignment = Alignment.Horizontal.Start,
                ) {
                    Text("Unustasis ($tick)", style = TextStyle(color = GlanceTheme.colors.secondary))
                    Text(
                        title,
                        style = TextStyle(fontSize = 24.sp, fontWeight = FontWeight.Bold, color = GlanceTheme.colors.onBackground),
                        modifier = GlanceModifier.clickable(
                            onClick = actionRunCallback<InteractiveAction>(
                                actionParametersOf(
                                    actionUriStringKey to powerActionUriString
                                )
                            )
                        ).padding(bottom = 4.dp),
                    )
                    Row(
                        verticalAlignment = Alignment.Vertical.CenterVertically,
                        horizontalAlignment = Alignment.Horizontal.Start,
                    ) {
                        LinearProgressIndicator(
                            progress = soc1 / 100f,
                            modifier = GlanceModifier.width(64.dp).height(8.dp),
                            color = GlanceTheme.colors.primary,
                            backgroundColor = GlanceTheme.colors.secondaryContainer,
                        )
                        Text(
                            "$soc1%",
                            style = TextStyle(color = GlanceTheme.colors.secondary),
                            modifier = GlanceModifier.padding(start = 8.dp),
                        )
                    }
                    Row(
                        verticalAlignment = Alignment.Vertical.CenterVertically,
                        horizontalAlignment = Alignment.Horizontal.Start,
                    ) {
                        LinearProgressIndicator(
                            progress = soc2 / 100f,
                            modifier = GlanceModifier.width(64.dp).height(8.dp),
                            color = GlanceTheme.colors.primary,
                            backgroundColor = GlanceTheme.colors.secondaryContainer,

                            )
                        Text(
                            "$soc2%",
                            style = TextStyle(color = GlanceTheme.colors.secondary),
                            modifier = GlanceModifier.padding(start = 8.dp),
                        )
                    }
                }
            }
        }
    }
}

class InteractiveAction : ActionCallback {
    val actionUriStringKey = ActionParameters.Key<String>(
        "actionUriString"
    )

    override suspend fun onAction(
        context: Context,
        glanceId: GlanceId,
        parameters: ActionParameters
    ) {
        val backgroundIntent =
            HomeWidgetBackgroundIntent.getBroadcast(
                context, Uri.parse(parameters[actionUriStringKey])
            )
        backgroundIntent.send()
    }
}


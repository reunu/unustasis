package de.freal.unustasis

import android.content.Context
import android.content.Intent
import de.freal.unustasis.wear.WearBridge
import es.antonborri.home_widget.HomeWidgetGlanceWidgetReceiver

class HomeWidgetReceiver : HomeWidgetGlanceWidgetReceiver<HomeWidgetGlanceAppWidget>() {
  override val glanceAppWidget = HomeWidgetGlanceAppWidget()

  // home_widget's updateWidget() broadcasts explicitly to this class, so onReceive runs even
  // when no widget is placed on the home screen (onUpdate wouldn't). That makes this the one
  // hook that catches every state change Dart publishes, whether or not the user uses the
  // widget - which is what the Wear companion needs.
  override fun onReceive(context: Context, intent: Intent) {
    WearBridge.enqueueStateSync(context)
    super.onReceive(context, intent)
  }
}

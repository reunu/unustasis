package de.freal.unustasis

import android.annotation.SuppressLint
import android.content.Intent
import android.net.Uri
import android.os.PowerManager
import android.provider.Settings
import io.flutter.embedding.android.FlutterFragmentActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterFragmentActivity() {

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BATTERY_CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isIgnoringBatteryOptimizations" ->
                        result.success(BatteryOptimization.isIgnored(this))
                    "requestIgnoreBatteryOptimizations" ->
                        result.success(BatteryOptimization.request(this))
                    "openBatteryOptimizationSettings" ->
                        result.success(BatteryOptimization.openSettings(this))
                    else -> result.notImplemented()
                }
            }
    }

    companion object {
        private const val BATTERY_CHANNEL = "de.freal.unustasis/battery_optimization"
    }
}

/**
 * Whether the app is exempt from Doze and App Standby, and how to ask for it.
 *
 * The exemption is what lets an action arriving from another app — Tasker, say
 * — start the background service when it isn't already running. A widget tap
 * gets that privilege from the launcher; a broadcast doesn't.
 */
object BatteryOptimization {

    fun isIgnored(context: android.content.Context): Boolean {
        val power = context.getSystemService(android.content.Context.POWER_SERVICE) as? PowerManager
            ?: return false
        return power.isIgnoringBatteryOptimizations(context.packageName)
    }

    /**
     * Shows the system's own "ignore battery optimisations?" dialog. Returns
     * whether it could be shown: the dialog reports nothing back, so callers
     * re-read [isIgnored] once the user is done with it.
     */
    @SuppressLint("BatteryLife")
    fun request(activity: android.app.Activity): Boolean {
        if (isIgnored(activity)) return true
        return try {
            activity.startActivity(
                Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:${activity.packageName}"),
                )
            )
            true
        } catch (e: Exception) {
            openSettings(activity)
        }
    }

    /**
     * Opens this app's settings page, where Battery is one tap away. Android
     * gives an app no way to drop its own exemption, and exposes no intent for
     * the per-app battery screen, so this is as deep as it reliably goes. The
     * all-apps list is the fallback for devices with no app detail page.
     */
    fun openSettings(activity: android.app.Activity): Boolean {
        val destinations = listOf(
            Intent(
                Settings.ACTION_APPLICATION_DETAILS_SETTINGS,
                Uri.parse("package:${activity.packageName}"),
            ),
            Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS),
        )
        for (intent in destinations) {
            try {
                activity.startActivity(intent)
                return true
            } catch (e: Exception) {
                continue
            }
        }
        return false
    }
}

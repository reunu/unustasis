package de.freal.unustasis

import android.app.PendingIntent
import android.content.Intent
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.content.ContextCompat
import com.google.android.gms.wearable.MessageEvent
import com.google.android.gms.wearable.WearableListenerService
import es.antonborri.home_widget.HomeWidgetBackgroundIntent
import id.flutter.flutter_background_service.BackgroundService
import id.flutter.flutter_background_service.FlutterBackgroundServicePlugin
import org.json.JSONObject

class WearCommandListenerService : WearableListenerService() {

	private val mainHandler by lazy { Handler(Looper.getMainLooper()) }

	override fun onMessageReceived(messageEvent: MessageEvent) {
		Log.d(TAG, "Received message from Wear: path=${messageEvent.path}, size=${messageEvent.data?.size ?: 0}")
		if (messageEvent.path != COMMAND_PATH) {
			super.onMessageReceived(messageEvent)
			return
		}

		val payload = messageEvent.data?.let { String(it, Charsets.UTF_8) }
		if (payload.isNullOrBlank()) {
			Log.w(TAG, "Received empty command payload from Wear device")
			return
		}

		val uri = runCatching { Uri.parse(payload) }.getOrNull()
		val command = uri?.host?.lowercase() ?: payload.substringAfterLast('/')

		when (command) {
			"unlock", "lock", "openseat" -> dispatchCommand(command, uri)
			else -> Log.w(TAG, "Received unknown Wear command: $payload")
		}
	}

	private fun dispatchCommand(command: String, uri: Uri?) {
		ensureServiceRunning()
		dispatchViaServicePipe(command, uri)
		dispatchViaHomeWidget(command)
	}

	private fun dispatchViaServicePipe(command: String, uri: Uri?) {
		if (FlutterBackgroundServicePlugin.servicePipe.hasListener()) {
			sendThroughServicePipe(command, uri)
		} else {
			mainHandler.postDelayed({
				if (FlutterBackgroundServicePlugin.servicePipe.hasListener()) {
					sendThroughServicePipe(command, uri)
				} else {
					Log.w(TAG, "Service pipe still not ready for command '$command'")
				}
			}, SERVICE_START_DELAY_MS)
		}
	}

	private fun sendThroughServicePipe(command: String, uri: Uri?) {
		runCatching {
			val content = JSONObject().apply {
				put("source", "wear")
				put("timestamp", System.currentTimeMillis())
				uri?.let { put("uri", it.toString()) }
			}

			val message = JSONObject().apply {
				put("id", command)
				put("content", content)
			}

			FlutterBackgroundServicePlugin.servicePipe.invoke(message)
			Log.i(TAG, "Dispatched command '$command' to Flutter background service")
		}.onFailure {
			Log.e(TAG, "Failed to dispatch Wear command '$command' through service pipe", it)
		}
	}

	private fun dispatchViaHomeWidget(command: String) {
		val uri = Uri.parse("$URL_BASE$command")
		val pendingIntent = HomeWidgetBackgroundIntent.getBroadcast(this, uri)

		try {
			pendingIntent.send()
			Log.i(TAG, "Sent Wear command '$command' through HomeWidget background callback")
		} catch (exception: PendingIntent.CanceledException) {
			Log.e(TAG, "PendingIntent cancelled for command '$command'", exception)
			fallbackToDeepLink(command)
		} catch (exception: Exception) {
			Log.e(TAG, "Failed to send Wear command '$command'", exception)
			fallbackToDeepLink(command)
		}
	}

	private fun ensureServiceRunning() {
		if (!FlutterBackgroundServicePlugin.servicePipe.hasListener()) {
			runCatching {
				val intent = Intent(this, BackgroundService::class.java)
				ContextCompat.startForegroundService(this, intent)
				Log.i(TAG, "Requested background service start for Wear command handling")
			}.onFailure {
				Log.e(TAG, "Failed to start background service", it)
			}
		}
	}

	private fun fallbackToDeepLink(command: String) {
		val deepLink = Uri.parse("$URL_BASE$command")
		val intent = Intent(Intent.ACTION_VIEW, deepLink).apply {
			addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
			addCategory(Intent.CATEGORY_BROWSABLE)
			addCategory(Intent.CATEGORY_DEFAULT)
		}

		runCatching {
			startActivity(intent)
		}.onFailure {
			Log.e(TAG, "Fallback deep link failed for command '$command'", it)
		}
	}

	companion object {
		private const val TAG = "WearCommandListener"
		private const val COMMAND_PATH = "/unustasis/command"
		private const val URL_BASE = "unustasis://"
		private const val SERVICE_START_DELAY_MS = 600L
	}
}

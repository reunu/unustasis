import Flutter
import UIKit
import flutter_background_service_ios
import home_widget
import workmanager_apple

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {

    // BGTaskScheduler identifiers have to be claimed before launch finishes, so
    // this setup stays here instead of moving to the implicit engine callback.
    SwiftFlutterBackgroundServicePlugin.taskIdentifier = "de.freal.unustasis.background"

    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }
    WorkmanagerPlugin.registerPeriodicTask(
      withIdentifier: "de.freal.unustasis.widget_refresh",
      frequency: NSNumber(value: 20 * 60)  // 20 minutes
    )
    // WorkmanagerDebug.setCurrent(NotificationDebugHandler())

    // Register HomeWidget background callback (iOS 17+)
    if #available(iOS 17.0, *) {
      HomeWidgetBackgroundWorker.setPluginRegistrantCallback { registry in
        GeneratedPluginRegistrant.register(with: registry)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Under the UIScene lifecycle the engine is created after UIKit's
  // didFinishLaunchingWithOptions returns, so plugins register here instead.
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  // Incoming share URLs used to be routed here by hand. UIKit no longer calls
  // application(_:open:options:) on a scene-based app; FlutterSceneDelegate now
  // forwards scene(_:openURLContexts:) to flutter_sharing_intent for us.
}

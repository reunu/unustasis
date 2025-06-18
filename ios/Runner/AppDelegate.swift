import Flutter
import UIKit
import flutter_background_service_ios
import home_widget
import workmanager

@main
@objc class AppDelegate: FlutterAppDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    SwiftFlutterBackgroundServicePlugin.taskIdentifier = "de.freal.unustasis.background"
    GeneratedPluginRegistrant.register(with: self)

    UIApplication.shared.setMinimumBackgroundFetchInterval(TimeInterval(60 * 15))

    WorkmanagerPlugin.setPluginRegistrantCallback { registry in
      GeneratedPluginRegistrant.register(with: registry)
    }

    if #available(iOS 17, *) {
      HomeWidgetBackgroundWorker.setPluginRegistrantCallback { registry in
        GeneratedPluginRegistrant.register(with: registry)
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
}

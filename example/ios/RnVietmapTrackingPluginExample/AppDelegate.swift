import UIKit
import UserNotifications
import React
import React_RCTAppDelegate
import ReactAppDependencyProvider

/// The notification delegate lives here, in the app, not in the plugin.
///
/// `UNUserNotificationCenter.delegate` is a single app-wide slot. A library that
/// claimed it would silently break any host app that has its own delegate — push
/// handling, deep links from a tap, anything — and most real apps do. So the
/// plugin requests permission (`requestNotificationPermission()`) and leaves
/// presentation to the app. The Flutter plugin draws the line in the same place.
///
/// Without `willPresent` below, a notification posted while the app is in the
/// foreground is delivered and simply not shown. The SDK's post succeeds and it
/// looks exactly like a failure — which is how testing is usually done, with the
/// app open.
@main
class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
  var window: UIWindow?

  var reactNativeDelegate: ReactNativeDelegate?
  var reactNativeFactory: RCTReactNativeFactory?

  func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
  ) -> Bool {
    // Set before React Native starts, so a notification arriving during startup
    // is not dropped for want of a delegate.
    UNUserNotificationCenter.current().delegate = self

    let delegate = ReactNativeDelegate()
    let factory = RCTReactNativeFactory(delegate: delegate)
    delegate.dependencyProvider = RCTAppDependencyProvider()

    reactNativeDelegate = delegate
    reactNativeFactory = factory

    window = UIWindow(frame: UIScreen.main.bounds)

    factory.startReactNative(
      withModuleName: "RnVietmapTrackingPluginExample",
      in: window,
      launchOptions: launchOptions
    )

    return true
  }

  /// Show notifications while the app is in the foreground.
  ///
  /// iOS suppresses them by default; returning presentation options here is the
  /// only way to see a fake-GPS warning during a test run with the app open.
  func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if #available(iOS 14.0, *) {
      completionHandler([.banner, .sound])
    } else {
      completionHandler([.alert, .sound])
    }
  }
}

class ReactNativeDelegate: RCTDefaultReactNativeFactoryDelegate {
  override func sourceURL(for bridge: RCTBridge) -> URL? {
    self.bundleURL()
  }

  override func bundleURL() -> URL? {
#if DEBUG
    RCTBundleURLProvider.sharedSettings().jsBundleURL(forBundleRoot: "index")
#else
    Bundle.main.url(forResource: "main", withExtension: "jsbundle")
#endif
  }
}

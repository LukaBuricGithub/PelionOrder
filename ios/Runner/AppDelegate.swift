import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate {
  /// The background-time assertion held while the app finishes its MQTT work
  /// after being put away. See `lib/features/shared/platform/background_time.dart`.
  ///
  /// WHY: iOS suspends a backgrounded app after roughly five seconds. The
  /// kasa answers an order one to five seconds after it is sent, and the
  /// waiter usually pockets the phone immediately — so without this the
  /// confirmation lands on a suspended app, the broker queues it, and the
  /// order sits as "Nije potvrđena" although it was printed. Asking for
  /// background time buys about thirty seconds, which is all the connection
  /// needs to take the answer and close cleanly.
  private var bgTask: UIBackgroundTaskIdentifier = .invalid

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    if let controller = window?.rootViewController as? FlutterViewController {
      let channel = FlutterMethodChannel(
        name: "hr.pelion.order/background_time",
        binaryMessenger: controller.binaryMessenger
      )
      channel.setMethodCallHandler { [weak self] call, result in
        switch call.method {
        case "begin":
          self?.beginBackgroundTime()
          result(nil)
        case "end":
          self?.endBackgroundTime()
          result(nil)
        default:
          result(FlutterMethodNotImplemented)
        }
      }
    }

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  private func beginBackgroundTime() {
    // Already holding one: keep it rather than stacking assertions.
    guard bgTask == .invalid else { return }
    bgTask = UIApplication.shared.beginBackgroundTask(withName: "PelionOrderMqtt") {
      // iOS is out of patience — release it, or the app is killed.
      self.endBackgroundTime()
    }
  }

  private func endBackgroundTime() {
    guard bgTask != .invalid else { return }
    let task = bgTask
    bgTask = .invalid
    UIApplication.shared.endBackgroundTask(task)
  }
}

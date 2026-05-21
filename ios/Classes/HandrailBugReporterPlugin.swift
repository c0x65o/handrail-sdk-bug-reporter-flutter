import Flutter
import UIKit
import ObjectiveC.runtime

public class HandrailBugReporterPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static let channelName = "dev.handrail/bug_reporter/ios_shake"
  private static var eventSink: FlutterEventSink?
  private static var swizzled = false
  private static var lastShakeAt: TimeInterval = 0

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterEventChannel(name: channelName, binaryMessenger: registrar.messenger())
    let instance = HandrailBugReporterPlugin()
    channel.setStreamHandler(instance)
    installShakeHook()
  }

  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    HandrailBugReporterPlugin.eventSink = events
    return nil
  }

  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    HandrailBugReporterPlugin.eventSink = nil
    return nil
  }

  private static func installShakeHook() {
    guard !swizzled else {
      return
    }
    swizzled = true

    let originalSelector = #selector(UIApplication.sendEvent(_:))
    let swizzledSelector = #selector(UIApplication.handrail_sendEvent(_:))

    guard
      let originalMethod = class_getInstanceMethod(UIApplication.self, originalSelector),
      let swizzledMethod = class_getInstanceMethod(UIApplication.self, swizzledSelector)
    else {
      return
    }

    method_exchangeImplementations(originalMethod, swizzledMethod)
  }

  fileprivate static func emitShakeIfNeeded() {
    guard let eventSink = eventSink else {
      return
    }

    let now = Date().timeIntervalSince1970
    guard now - lastShakeAt >= 0.8 else {
      return
    }

    lastShakeAt = now
    DispatchQueue.main.async {
      eventSink(["type": "shake", "platform": "ios"])
    }
  }
}

private extension UIApplication {
  @objc func handrail_sendEvent(_ event: UIEvent) {
    handrail_sendEvent(event)

    guard event.type == .motion, event.subtype == .motionShake else {
      return
    }

    HandrailBugReporterPlugin.emitShakeIfNeeded()
  }
}

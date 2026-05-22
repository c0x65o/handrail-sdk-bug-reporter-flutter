import Flutter
import UIKit
import ObjectiveC.runtime

public class HandrailBugReporterPlugin: NSObject, FlutterPlugin, FlutterStreamHandler {
  private static let shakeChannelName = "dev.handrail/bug_reporter/ios_shake"
  private static let screenshotChannelName = "dev.handrail/bug_reporter/screenshot"
  private static let maxScreenshotDimension: CGFloat = 1280
  private static let jpegQuality: CGFloat = 0.72
  private static var eventSink: FlutterEventSink?
  private static var swizzled = false
  private static var lastShakeAt: TimeInterval = 0

  public static func register(with registrar: FlutterPluginRegistrar) {
    let channel = FlutterEventChannel(name: shakeChannelName, binaryMessenger: registrar.messenger())
    let screenshotChannel = FlutterMethodChannel(
      name: screenshotChannelName,
      binaryMessenger: registrar.messenger()
    )
    let instance = HandrailBugReporterPlugin()
    channel.setStreamHandler(instance)
    screenshotChannel.setMethodCallHandler(instance.handle)
    installShakeHook()
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard call.method == "captureScreenshot" else {
      result(FlutterMethodNotImplemented)
      return
    }
    captureScreenshot(result: result)
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

  private func captureScreenshot(result: FlutterResult) {
    guard let window = Self.currentWindow() else {
      result(FlutterError(
        code: "NO_WINDOW",
        message: "No iOS window is available for screenshot capture.",
        details: nil
      ))
      return
    }

    let bounds = window.bounds
    guard bounds.width > 0, bounds.height > 0 else {
      result(FlutterError(
        code: "WINDOW_NOT_READY",
        message: "The iOS window is not ready for screenshot capture.",
        details: nil
      ))
      return
    }

    let largestSide = max(bounds.width, bounds.height)
    let maxScale = largestSide > 0 ? Self.maxScreenshotDimension / largestSide : UIScreen.main.scale
    let outputScale = min(UIScreen.main.scale, maxScale)
    let format = UIGraphicsImageRendererFormat.default()
    format.opaque = true
    format.scale = max(0.1, outputScale)

    let renderer = UIGraphicsImageRenderer(size: bounds.size, format: format)
    let image = renderer.image { context in
      UIColor.white.setFill()
      context.fill(bounds)
      window.drawHierarchy(in: bounds, afterScreenUpdates: true)
    }

    guard let data = image.jpegData(compressionQuality: Self.jpegQuality) else {
      result(FlutterError(
        code: "CAPTURE_FAILED",
        message: "iOS did not return screenshot image bytes.",
        details: nil
      ))
      return
    }

    result([
      "base64": data.base64EncodedString(),
      "filename": "mobile-screenshot.jpg",
      "mimeType": "image/jpeg"
    ])
  }

  private static func currentWindow() -> UIWindow? {
    if #available(iOS 13.0, *) {
      return UIApplication.shared.connectedScenes
        .compactMap { $0 as? UIWindowScene }
        .flatMap { $0.windows }
        .first { $0.isKeyWindow } ??
        UIApplication.shared.connectedScenes
          .compactMap { $0 as? UIWindowScene }
          .flatMap { $0.windows }
          .first
    }
    return UIApplication.shared.keyWindow
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

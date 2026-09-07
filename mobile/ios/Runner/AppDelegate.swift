import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var cover: UIView?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    NotificationCenter.default.addObserver(
      self, selector: #selector(coverScreen),
      name: UIApplication.willResignActiveNotification, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(uncoverScreen),
      name: UIApplication.didBecomeActiveNotification, object: nil)
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
      PrivacyShield.attachToKeyWindow()
    }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }

  @objc private func coverScreen() {
    guard cover == nil, let window = PrivacyShield.keyWindow() else { return }
    let view = UIView(frame: window.bounds)
    view.backgroundColor = .black
    view.autoresizingMask = [.flexibleWidth, .flexibleHeight]
    window.addSubview(view)
    cover = view
  }

  @objc private func uncoverScreen() {
    cover?.removeFromSuperview()
    cover = nil
  }
}

enum PrivacyShield {
  static func keyWindow() -> UIWindow? {
    UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first { $0.isKeyWindow } ?? UIApplication.shared.windows.first
  }

  static func attachToKeyWindow() {
    guard let window = keyWindow() else { return }
    let field = UITextField()
    field.isSecureTextEntry = true
    field.isUserInteractionEnabled = false
    field.translatesAutoresizingMaskIntoConstraints = false
    window.addSubview(field)
    window.layer.superlayer?.addSublayer(field.layer)
    field.layer.sublayers?.last?.addSublayer(window.layer)
  }
}

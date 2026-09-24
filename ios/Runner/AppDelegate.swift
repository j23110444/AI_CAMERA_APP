import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(
      application,
      didFinishLaunchingWithOptions: launchOptions
    )
  }

  func didInitializeImplicitFlutterEngine(
    _ engineBridge: FlutterImplicitEngineBridge
  ) {
    // Flutter 套件註冊
    GeneratedPluginRegistrant.register(
      with: engineBridge.pluginRegistry
    )

    // 取得 ProCameraBridge 專用 Registrar
    guard let registrar = engineBridge.pluginRegistry.registrar(
      forPlugin: "ProCameraBridge"
    ) else {
      print("❌ ProCameraBridge registrar 建立失敗")
      return
    }

    // 註冊自訂 MethodChannel + PlatformView
    ProCameraBridge.register(
      with: registrar
    )
  }
}
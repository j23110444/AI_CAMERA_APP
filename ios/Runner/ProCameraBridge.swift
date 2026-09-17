import AVFoundation
import Flutter

final class ProCameraBridge: NSObject, FlutterPlugin {
  private let channelName = "ai_camera/pro"

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = ProCameraBridge()
    let channel = FlutterMethodChannel(
      name: instance.channelName,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let device = AVCaptureDevice.default(
      .builtInWideAngleCamera,
      for: .video,
      position: .back
    ) else {
      result(FlutterError(code: "NO_CAMERA", message: "找不到後置相機", details: nil))
      return
    }

    do {
      try device.lockForConfiguration()
      defer { device.unlockForConfiguration() }

      switch call.method {
      case "setManualExposure":
        guard
          let args = call.arguments as? [String: Any],
          let iso = (args["iso"] as? NSNumber)?.floatValue,
          let duration = (args["duration"] as? NSNumber)?.doubleValue
        else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "ISO 或快門參數無效", details: nil))
          return
        }
        guard device.isExposureModeSupported(.custom) else {
          result(FlutterError(code: "UNSUPPORTED", message: "裝置不支援手動曝光", details: nil))
          return
        }
        let clampedISO = min(max(iso, device.activeFormat.minISO), device.activeFormat.maxISO)
        let minDuration = device.activeFormat.minExposureDuration
        let maxDuration = device.activeFormat.maxExposureDuration
        let requested = CMTime(seconds: duration, preferredTimescale: 1_000_000)
        let clampedDuration = CMTimeMaximum(minDuration, CMTimeMinimum(requested, maxDuration))
        device.setExposureModeCustom(duration: clampedDuration, iso: clampedISO)
        result(nil)

      case "setExposureBias":
        guard let bias = (call.arguments as? NSNumber)?.doubleValue else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "EV 參數無效", details: nil))
          return
        }
        guard device.isExposureModeSupported(.continuousAutoExposure) else {
          result(FlutterError(code: "UNSUPPORTED", message: "裝置不支援自動曝光", details: nil))
          return
        }
        device.exposureMode = .continuousAutoExposure
        device.setExposureTargetBias(
          Float(bias.clamped(to: device.minExposureTargetBias...device.maxExposureTargetBias))
        )
        result(nil)

      case "setManualFocus":
        guard let position = (call.arguments as? NSNumber)?.doubleValue else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "對焦參數無效", details: nil))
          return
        }
        guard device.isLockingFocusWithCustomLensPositionSupported else {
          result(FlutterError(code: "UNSUPPORTED", message: "裝置不支援手動對焦", details: nil))
          return
        }
        device.setFocusModeLocked(lensPosition: Float(position))
        result(nil)

      case "setWhiteBalance":
        guard
          let args = call.arguments as? [String: Any],
          let temperature = (args["kelvin"] as? NSNumber)?.doubleValue
        else {
          result(FlutterError(code: "INVALID_ARGUMENT", message: "色溫參數無效", details: nil))
          return
        }
        guard device.isWhiteBalanceModeSupported(.locked) else {
          result(FlutterError(code: "UNSUPPORTED", message: "裝置不支援手動白平衡", details: nil))
          return
        }
        let temperatureAndTint = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
          temperature: Float(temperature),
          tint: 0
        )
        var gains = device.deviceWhiteBalanceGains(for: temperatureAndTint)
        let maxGain = device.maxWhiteBalanceGain
        gains.redGain = min(max(gains.redGain, 1), maxGain)
        gains.greenGain = min(max(gains.greenGain, 1), maxGain)
        gains.blueGain = min(max(gains.blueGain, 1), maxGain)
        device.setWhiteBalanceModeLocked(with: gains)
        result(nil)

      default:
        result(FlutterMethodNotImplemented)
      }
    } catch {
      result(FlutterError(code: "CONFIGURATION_FAILED", message: error.localizedDescription, details: nil))
    }
  }
}

private extension Comparable {
  func clamped(to limits: ClosedRange<Self>) -> Self {
    min(max(self, limits.lowerBound), limits.upperBound)
  }
}

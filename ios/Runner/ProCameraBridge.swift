import AVFoundation
import Flutter

final class ProCameraBridge: NSObject, FlutterPlugin {
  private let channelName = "ai_camera/pro"
  private var selectedPosition: AVCaptureDevice.Position = .back
  private var selectedLensType = "wide"

  static func register(with registrar: FlutterPluginRegistrar) {
    let instance = ProCameraBridge()
    let channel = FlutterMethodChannel(
      name: instance.channelName,
      binaryMessenger: registrar.messenger()
    )
    registrar.addMethodCallDelegate(instance, channel: channel)
  }

  func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    do {
      switch call.method {
      case "discoverCameras":
        result(discoverCameras())
      case "selectCamera":
        try selectCamera(call.arguments)
        result(nil)
      case "setManualExposure":
        try withSelectedDevice { device in
          guard
            let args = call.arguments as? [String: Any],
            let iso = (args["iso"] as? NSNumber)?.floatValue,
            let duration = (args["duration"] as? NSNumber)?.doubleValue
          else {
            throw BridgeError.invalidArgument("ISO 或快門參數無效")
          }
          guard device.isExposureModeSupported(.custom) else {
            throw BridgeError.unsupported("裝置不支援手動曝光")
          }
          let clampedISO = iso.clamped(
            to: device.activeFormat.minISO...device.activeFormat.maxISO
          )
          let requested = CMTime(seconds: duration, preferredTimescale: 1_000_000)
          let clampedDuration = CMTimeMaximum(
            device.activeFormat.minExposureDuration,
            CMTimeMinimum(requested, device.activeFormat.maxExposureDuration)
          )
          device.setExposureModeCustom(duration: clampedDuration, iso: clampedISO)
        }
        result(nil)
      case "setExposureBias":
        try withSelectedDevice { device in
          guard device.isExposureModeSupported(.continuousAutoExposure) else {
            throw BridgeError.unsupported("裝置不支援自動曝光")
          }
          let bias = (call.arguments as? NSNumber)?.floatValue ?? 0
          device.exposureMode = .continuousAutoExposure
          device.setExposureTargetBias(
            bias.clamped(to: device.minExposureTargetBias...device.maxExposureTargetBias)
          )
        }
        result(nil)
      case "setExposureMode":
        try withSelectedDevice { device in
          let mode = (call.arguments as? [String: Any])?["mode"] as? String
            ?? "continuous"
          let exposureMode: AVCaptureDevice.ExposureMode =
            mode == "locked" ? .locked : .continuousAutoExposure
          guard device.isExposureModeSupported(exposureMode) else {
            throw BridgeError.unsupported("裝置不支援指定曝光模式")
          }
          device.exposureMode = exposureMode
        }
        result(nil)
      case "setFocus":
        try withSelectedDevice { device in
          let args = call.arguments as? [String: Any]
          let mode = args?["mode"] as? String ?? "continuous"
          if mode == "locked" {
            guard device.isLockingFocusWithCustomLensPositionSupported else {
              throw BridgeError.unsupported("裝置不支援手動對焦")
            }
            let position = ((args?["position"] as? NSNumber)?.floatValue ?? 0.5)
              .clamped(to: 0...1)
            device.setFocusModeLocked(lensPosition: position)
          } else {
            let focusMode: AVCaptureDevice.FocusMode =
              mode == "auto" ? .auto : .continuousAutoFocus
            guard device.isFocusModeSupported(focusMode) else {
              throw BridgeError.unsupported("裝置不支援指定對焦模式")
            }
            device.focusMode = focusMode
          }
        }
        result(nil)
      case "setWhiteBalance":
        try withSelectedDevice { device in
          let args = call.arguments as? [String: Any]
          let mode = args?["mode"] as? String ?? "locked"
          if mode == "auto" {
            guard device.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) else {
              throw BridgeError.unsupported("裝置不支援自動白平衡")
            }
            device.whiteBalanceMode = .continuousAutoWhiteBalance
          } else {
            let kelvin = (args?["kelvin"] as? NSNumber)?.floatValue ?? 5200
            guard device.isWhiteBalanceModeSupported(.locked) else {
              throw BridgeError.unsupported("裝置不支援自訂白平衡")
            }
            let temperature = AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
              temperature: kelvin,
              tint: 0
            )
            var gains = device.deviceWhiteBalanceGains(for: temperature)
            gains.redGain = gains.redGain.clamped(to: 1...device.maxWhiteBalanceGain)
            gains.greenGain = gains.greenGain.clamped(to: 1...device.maxWhiteBalanceGain)
            gains.blueGain = gains.blueGain.clamped(to: 1...device.maxWhiteBalanceGain)
            device.setWhiteBalanceModeLocked(with: gains)
          }
        }
        result(nil)
      case "setZoom":
        try withSelectedDevice { device in
          let factor = ((call.arguments as? NSNumber)?.doubleValue ?? 1)
            .clamped(to: 1...Double(device.activeFormat.videoMaxZoomFactor))
          device.videoZoomFactor = factor
        }
        result(nil)
      case "setHDR":
        try withSelectedDevice { device in
          guard device.isVideoHDREnabledSupported else {
            throw BridgeError.unsupported("裝置不支援 HDR")
          }
          device.automaticallyAdjustsVideoHDREnabled = false
          device.isVideoHDREnabled = (call.arguments as? NSNumber)?.boolValue ?? false
        }
        result(nil)
      case "setFlashMode":
        try withSelectedDevice { device in
          let mode = call.arguments as? String ?? "auto"
          guard device.hasFlash, device.hasTorch else {
            throw BridgeError.unsupported("目前鏡頭不支援閃光燈或手電筒")
          }
          if mode == "torch" {
            try device.setTorchModeOn(level: AVCaptureDevice.maxAvailableTorchLevel)
          } else {
            device.torchMode = .off
            device.flashMode = mode == "on" ? .on : .off
          }
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    } catch let error as BridgeError {
      result(FlutterError(code: error.code, message: error.message, details: nil))
    } catch {
      result(FlutterError(code: "CONFIGURATION_FAILED", message: error.localizedDescription, details: nil))
    }
  }

  private func discoverCameras() -> [[String: Any]] {
    let session = AVCaptureDevice.DiscoverySession(
      deviceTypes: [
        .builtInWideAngleCamera,
        .builtInUltraWideCamera,
        .builtInTelephotoCamera,
        .builtInTripleCamera,
        .builtInDualWideCamera
      ],
      mediaType: .video,
      position: .unspecified
    )
    return session.devices.map { device in
      [
        "id": device.uniqueID,
        "name": device.localizedName,
        "position": device.position == .front ? "front" : "back",
        "lensType": lensType(for: device),
        "maxZoom": device.activeFormat.videoMaxZoomFactor,
        "hdrSupported": device.isVideoHDREnabledSupported,
        "hasFlash": device.hasFlash,
        "hasTorch": device.hasTorch
      ]
    }
  }

  private func selectCamera(_ arguments: Any?) throws {
    guard let args = arguments as? [String: Any] else {
      throw BridgeError.invalidArgument("鏡頭選擇參數無效")
    }
    selectedPosition = (args["position"] as? String) == "front" ? .front : .back
    selectedLensType = args["lensType"] as? String ?? "wide"
    _ = try selectedDevice()
  }

  private func selectedDevice() throws -> AVCaptureDevice {
    let requestedType: AVCaptureDevice.DeviceType
    switch selectedLensType {
    case "ultraWide": requestedType = .builtInUltraWideCamera
    case "telephoto": requestedType = .builtInTelephotoCamera
    default: requestedType = .builtInWideAngleCamera
    }
    guard let device = AVCaptureDevice.default(requestedType, for: .video, position: selectedPosition) else {
      throw BridgeError.unsupported("找不到指定的原生鏡頭")
    }
    return device
  }

  private func withSelectedDevice(_ body: (AVCaptureDevice) throws -> Void) throws {
    let device = try selectedDevice()
    try device.lockForConfiguration()
    defer { device.unlockForConfiguration() }
    try body(device)
  }

  private func lensType(for device: AVCaptureDevice) -> String {
    switch device.deviceType {
    case .builtInUltraWideCamera: return "ultraWide"
    case .builtInTelephotoCamera: return "telephoto"
    default: return "wide"
    }
  }
}

private enum BridgeError: Error {
  case invalidArgument(String)
  case unsupported(String)

  var code: String {
    switch self {
    case .invalidArgument: return "INVALID_ARGUMENT"
    case .unsupported: return "UNSUPPORTED"
    }
  }

  var message: String {
    switch self {
    case .invalidArgument(let message), .unsupported(let message): return message
    }
  }
}

private extension Comparable {
  func clamped(to limits: ClosedRange<Self>) -> Self {
    min(max(self, limits.lowerBound), limits.upperBound)
  }
}

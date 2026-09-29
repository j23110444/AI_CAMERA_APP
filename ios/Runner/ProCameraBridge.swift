import AVFoundation
import Flutter

final class ProCameraBridge: NSObject, FlutterPlugin {

  private let channelName = "ai_camera/pro"
  private let cameraManager = ProCameraManager()
  private func cameraPosition(from value: String) -> AVCaptureDevice.Position {
    value == "front" ? .front : .back
  }

  static func register(with registrar: FlutterPluginRegistrar) {
  let instance = ProCameraBridge()

  let channel = FlutterMethodChannel(
    name: instance.channelName,
    binaryMessenger: registrar.messenger()
  )

  registrar.addMethodCallDelegate(
    instance,
    channel: channel
  )

  let previewFactory = ProCameraPreviewFactory(
    cameraManager: instance.cameraManager
  )

  registrar.register(
    previewFactory,
    withId: "ai_camera/pro_preview"
  )
}

  func handle(
    _ call: FlutterMethodCall,
    result: @escaping FlutterResult
  ) {
    do {
      switch call.method {

      // MARK: - Camera lifecycle

      case "startNativeCamera":
        let args = call.arguments as? [String: Any]

        let positionString = args?["position"] as? String ?? "back"
        let lensType = args?["lensType"] as? String ?? "wide"

        try cameraManager.start(
          position: cameraPosition(from: positionString),
          lensType: lensType
        )

        result(nil)

      case "stopNativeCamera":
        cameraManager.stop()
        result(nil)

      // MARK: - Camera selection

      case "selectCamera":
        guard let args = call.arguments as? [String: Any] else {
          throw CameraBridgeError.invalidArgument(
            "鏡頭選擇參數無效"
          )
        }

        let positionString = args["position"] as? String ?? "back"
        let lensType = args["lensType"] as? String ?? "wide"

        try cameraManager.selectCamera(
          position: cameraPosition(from: positionString),
          lensType: lensType
        )

        result(nil)

      case "discoverCameras":
        result(cameraManager.discoverCameras())

      case "capturePhoto":
        Task {
          do {
            let path = try await cameraManager.capturePhoto()

            DispatchQueue.main.async {
              result(path)
            }
          } catch let error as CameraManagerError {
            DispatchQueue.main.async {
              result(
                FlutterError(
                  code: error.code,
                  message: error.message,
                  details: nil
                )
              )
            }
          } catch {
            DispatchQueue.main.async {
              result(
                FlutterError(
                  code: "CAMERA_ERROR",
                  message: error.localizedDescription,
                  details: nil
                )
              )
            }
          }
        }

     case "captureLivePhoto":

    Task {

        do {

            let captureResult =
                try await cameraManager.captureLivePhoto()

            DispatchQueue.main.async {
                result(captureResult)
            }

        } catch let error as CameraManagerError {

            DispatchQueue.main.async {

                result(
                    FlutterError(
                        code: error.code,
                        message: error.message,
                        details: nil
                    )
                )
            }

        } catch {

            DispatchQueue.main.async {

                result(
                    FlutterError(
                        code: "LIVE_PHOTO_ERROR",
                        message: error.localizedDescription,
                        details: nil
                    )
                )
            }
        }
    }
     case "saveLivePhoto":

    guard
        let args = call.arguments as? [String: Any],
        let photoPath = args["photoPath"] as? String,
        let videoPath = args["videoPath"] as? String
    else {
        result(
            FlutterError(
                code: "INVALID_ARGUMENT",
                message: "Live Photo 路徑無效",
                details: nil
            )
        )
        return
    }

    Task {
        do {
            let success =
                try await cameraManager.saveLivePhoto(
                    photoPath: photoPath,
                    videoPath: videoPath
                )

            DispatchQueue.main.async {
                result(success)
            }

        } catch {
            DispatchQueue.main.async {
                result(
                    FlutterError(
                        code: "SAVE_LIVE_PHOTO_FAILED",
                        message: error.localizedDescription,
                        details: nil
                    )
                )
            }
        }
    }

    case "startVideoRecording":

      do {

        try cameraManager.startVideoRecording()

        result(nil)

      } catch let error as CameraManagerError {

        result(
          FlutterError(
            code: error.code,
            message: error.message,
            details: nil
          )
        )

      } catch {

        result(
          FlutterError(
            code: "VIDEO_RECORDING_ERROR",
            message: error.localizedDescription,
            details: nil
          )
        )
      }

case "stopVideoRecording":

  Task {

    do {

      let path =
        try await cameraManager.stopVideoRecording()

      DispatchQueue.main.async {
        result(path)
      }

    } catch let error as CameraManagerError {

      DispatchQueue.main.async {

        result(
          FlutterError(
            code: error.code,
            message: error.message,
            details: nil
          )
        )
      }

    } catch {

      DispatchQueue.main.async {

        result(
          FlutterError(
            code: "VIDEO_RECORDING_ERROR",
            message: error.localizedDescription,
            details: nil
          )
        )
      }
    }
  }


      case "setZoom":
        let zoom = (call.arguments as? NSNumber)?.doubleValue ?? 1.0

        try cameraManager.setZoom(zoom)

        result(nil)

      // MARK: - Exposure

      case "setExposureBias":
        let bias = (call.arguments as? NSNumber)?.floatValue ?? 0

        try cameraManager.setExposureBias(bias)

        result(nil)

      case "setManualExposure":
        guard let args = call.arguments as? [String: Any] else {
          throw CameraBridgeError.invalidArgument(
            "手動曝光參數無效"
          )
        }

        guard
          let isoNumber = args["iso"] as? NSNumber,
          let durationNumber = args["duration"] as? NSNumber
        else {
          throw CameraBridgeError.invalidArgument(
            "ISO 或快門參數無效"
          )
        }

        try cameraManager.setManualExposure(
          iso: isoNumber.floatValue,
          duration: durationNumber.doubleValue
        )

        result(nil)

      case "setExposureMode":
        let args = call.arguments as? [String: Any]
        let mode = args?["mode"] as? String ?? "continuous"

        try cameraManager.setExposureMode(
            mode: mode
        )

        result(nil)

      // MARK: - Focus

      case "setFocus":
        let args = call.arguments as? [String: Any]

        let mode = args?["mode"] as? String ?? "continuous"
        let position = (args?["position"] as? NSNumber)?.floatValue ?? 0.5

        try cameraManager.setFocus(
            mode: mode,
            position: position
        )
        result(nil)

      case "setFocusPoint":
        guard let args = call.arguments as? [String: Any] else {
          throw CameraBridgeError.invalidArgument(
            "對焦點參數無效"
          )
        }

        let x = (args["x"] as? NSNumber)?.doubleValue ?? 0.5
        let y = (args["y"] as? NSNumber)?.doubleValue ?? 0.5

        try cameraManager.setFocusPoint(
          x: x,
          y: y
        )

        result(nil)

      // MARK: - White balance

      case "setWhiteBalance":
        let args = call.arguments as? [String: Any]

        let kelvin =
          (args?["kelvin"] as? NSNumber)?.floatValue ?? 5200

        try cameraManager.setWhiteBalance(
            kelvin: kelvin
        )

        result(nil)

      case "setAutoWhiteBalance":
        try cameraManager.setAutoWhiteBalance()
        result(nil)

      // MARK: - HDR

      case "setHDR":
        let enabled = (call.arguments as? NSNumber)?.boolValue ?? false

        try cameraManager.setHDR(
          enabled: enabled
        )

        result(nil)

      // MARK: - Flash

      case "setFlashMode":
        let mode = call.arguments as? String ?? "auto"

        try cameraManager.setFlashMode(
          mode: mode
        )

        result(nil)

      default:
        result(FlutterMethodNotImplemented)
      }

    } catch let error as CameraBridgeError {

      result(
        FlutterError(
          code: error.code,
          message: error.message,
          details: nil
        )
      )

    } catch let error as CameraManagerError {

      result(
        FlutterError(
          code: error.code,
          message: error.message,
          details: nil
        )
      )

    } catch {

      result(
        FlutterError(
          code: "CAMERA_ERROR",
          message: error.localizedDescription,
          details: nil
        )
      )
    }
  }
}

// MARK: - Bridge errors

private enum CameraBridgeError: Error {

  case invalidArgument(String)

  var code: String {
    switch self {
    case .invalidArgument:
      return "INVALID_ARGUMENT"
    }
  }

  var message: String {
    switch self {
    case .invalidArgument(let message):
      return message
    }
  }
}
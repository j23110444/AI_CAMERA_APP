import AVFoundation
import UIKit

final class ProCameraManager: NSObject {

  // MARK: - Camera Session

  let session = AVCaptureSession()

  private(set) var currentInput: AVCaptureDeviceInput?

  private(set) var currentPosition: AVCaptureDevice.Position = .back

  private(set) var currentLensType: String = "wide"

  // MARK: - Outputs

  let photoOutput = AVCapturePhotoOutput()

  let videoOutput = AVCaptureVideoDataOutput()

  // MARK: - Session Queue

  private let sessionQueue = DispatchQueue(
    label: "ai.camera.session.queue",
    qos: .userInitiated
  )

  private var isConfigured = false

  // MARK: - Initialization

  override init() {
    super.init()

    videoOutput.alwaysDiscardsLateVideoFrames = true

    videoOutput.videoSettings = [
      kCVPixelBufferPixelFormatTypeKey as String:
        kCVPixelFormatType_32BGRA
    ]
  }

  // MARK: - Start Camera

  func start(
  position: AVCaptureDevice.Position = .back,
  lensType: String = "wide"
) throws {

  let status = AVCaptureDevice.authorizationStatus(for: .video)

  switch status {

  case .authorized:
    break

  case .notDetermined:
    AVCaptureDevice.requestAccess(for: .video) { granted in
      guard granted else {
        return
      }

        DispatchQueue.main.async {
        do {
          try self.start(
            position: position,
            lensType: lensType
          )
        } catch {
          print("Camera start failed: \(error)")
        }
    }

    return

  case .denied, .restricted:
    throw CameraManagerError.unsupported(
      "相機權限被拒絕，請到設定 → 隱私權與安全性 → 相機開啟權限"
    )

  @unknown default:
    throw CameraManagerError.unsupported(
      "無法確認相機權限"
    )
  }

  try configureSession(
    position: position,
    lensType: lensType
  )

  guard !session.isRunning else {
    return
  }

  sessionQueue.async { [weak self] in
    guard let self = self else {
      return
    }

    self.session.startRunning()
  }
}

  // MARK: - Stop Camera

  func stop() {

    guard session.isRunning else {
      return
    }

    sessionQueue.async { [weak self] in
      guard let self = self else {
        return
      }

      self.session.stopRunning()
    }
  }

  // MARK: - Configure Session

  private func configureSession(
    position: AVCaptureDevice.Position,
    lensType: String
  ) throws {

    guard let device = findCamera(
      position: position,
      lensType: lensType
    ) else {
      throw CameraManagerError.cameraNotFound(
        position: position,
        lensType: lensType
      )
    }

    session.beginConfiguration()

    defer {
      session.commitConfiguration()
    }

    // Photo quality
    if session.canSetSessionPreset(.high) {
      session.sessionPreset = .high
    }

    // Remove old input
    if let currentInput = currentInput {
      session.removeInput(currentInput)
      self.currentInput = nil
    }

    // Create new input
    let newInput: AVCaptureDeviceInput

    do {
      newInput = try AVCaptureDeviceInput(
        device: device
      )
    } catch {
      throw CameraManagerError.inputCreationFailed(
        error.localizedDescription
      )
    }

    guard session.canAddInput(newInput) else {
      throw CameraManagerError.cannotAddInput
    }

    session.addInput(newInput)

    currentInput = newInput
    currentPosition = position
    currentLensType = lensType

    // Add photo output only once
    if !session.outputs.contains(photoOutput) {

      guard session.canAddOutput(photoOutput) else {
        throw CameraManagerError.cannotAddPhotoOutput
      }

      session.addOutput(photoOutput)

      if #available(iOS 16.0, *) {
        photoOutput.maxPhotoQualityPrioritization =
          .quality
      }
    }

    // Add video output only once
    if !session.outputs.contains(videoOutput) {

      guard session.canAddOutput(videoOutput) else {
        throw CameraManagerError.cannotAddVideoOutput
      }

      session.addOutput(videoOutput)
    }

    configureConnection()
  }

  // MARK: - Video Connection

  private func configureConnection() {

    guard let connection = videoOutput.connection(
      with: .video
    ) else {
      return
    }

    if connection.isVideoOrientationSupported {
      connection.videoOrientation = .portrait
    }

    if connection.isVideoMirroringSupported {
      connection.isVideoMirrored =
        currentPosition == .front
    }

    if connection.isVideoStabilizationSupported {
      connection.preferredVideoStabilizationMode =
        .auto
    }
  }

  // MARK: - Find Camera

  private func findCamera(
    position: AVCaptureDevice.Position,
    lensType: String
  ) -> AVCaptureDevice? {

    let deviceType: AVCaptureDevice.DeviceType

    switch lensType {

    case "ultraWide":
      deviceType = .builtInUltraWideCamera

    case "telephoto":
      deviceType = .builtInTelephotoCamera

    case "wide":
      deviceType = .builtInWideAngleCamera

    default:
      deviceType = .builtInWideAngleCamera
    }

    return AVCaptureDevice.default(
      deviceType,
      for: .video,
      position: position
    )
  }

  // MARK: - Select Camera

  func selectCamera(
    position: AVCaptureDevice.Position,
    lensType: String
  ) throws {

    guard let device = findCamera(
      position: position,
      lensType: lensType
    ) else {
      throw CameraManagerError.cameraNotFound(
        position: position,
        lensType: lensType
      )
    }

    let wasRunning = session.isRunning

    session.beginConfiguration()

    defer {
      session.commitConfiguration()
    }

    // Remove old input
    if let oldInput = currentInput {
      session.removeInput(oldInput)
      currentInput = nil
    }

    // Create new input
    let newInput: AVCaptureDeviceInput

    do {
      newInput = try AVCaptureDeviceInput(
        device: device
      )
    } catch {
      throw CameraManagerError.inputCreationFailed(
        error.localizedDescription
      )
    }

    guard session.canAddInput(newInput) else {
      throw CameraManagerError.cannotAddInput
    }

    session.addInput(newInput)

    currentInput = newInput
    currentPosition = position
    currentLensType = lensType

    configureConnection()

    if wasRunning {
      // AVCaptureSession 的 input 切換會在 commitConfiguration
      // 後繼續使用同一個 session。
    }
  }

  // MARK: - Selected Device

  private var selectedDevice: AVCaptureDevice? {
    currentInput?.device
  }

  // MARK: - Zoom

  func setZoom(_ value: Double) throws {

    guard let device = selectedDevice else {
      throw CameraManagerError.cameraNotInitialized
    }

    try device.lockForConfiguration()

    defer {
      device.unlockForConfiguration()
    }

    let minZoom = device.minAvailableVideoZoomFactor

    let maxZoom = min(
      device.maxAvailableVideoZoomFactor,
      20.0
    )

    let zoom = min(
      max(value, minZoom),
      maxZoom
    )

    device.videoZoomFactor = zoom
  }

  // MARK: - Exposure Bias

  func setExposureBias(_ value: Float) throws {

    guard let device = selectedDevice else {
      throw CameraManagerError.cameraNotInitialized
    }

    guard device.isExposureModeSupported(
      .continuousAutoExposure
    ) else {
      throw CameraManagerError.unsupported(
        "裝置不支援自動曝光"
      )
    }

    try device.lockForConfiguration()

    defer {
      device.unlockForConfiguration()
    }

    device.exposureMode = .continuousAutoExposure

    let bias = min(
      max(
        value,
        device.minExposureTargetBias
      ),
      device.maxExposureTargetBias
    )

    device.setExposureTargetBias(
      bias
    )
  }

  // MARK: - Manual Exposure

  func setManualExposure(
    iso: Float,
    duration: Double
  ) throws {

    guard let device = selectedDevice else {
      throw CameraManagerError.cameraNotInitialized
    }

    guard device.isExposureModeSupported(
      .custom
    ) else {
      throw CameraManagerError.unsupported(
        "裝置不支援手動曝光"
      )
    }

    try device.lockForConfiguration()

    defer {
      device.unlockForConfiguration()
    }

    let clampedISO = min(
      max(
        iso,
        device.activeFormat.minISO
      ),
      device.activeFormat.maxISO
    )

    let requestedDuration = CMTime(
      seconds: duration,
      preferredTimescale: 1_000_000
    )

    let minDuration =
      device.activeFormat.minExposureDuration

    let maxDuration =
      device.activeFormat.maxExposureDuration

    let clampedDuration = CMTimeMaximum(
      minDuration,
      CMTimeMinimum(
        requestedDuration,
        maxDuration
      )
    )

    device.setExposureModeCustom(
      duration: clampedDuration,
      iso: clampedISO
    )
  }

  // MARK: - Exposure Mode

  func setExposureMode(
    mode: String
  ) throws {

    guard let device = selectedDevice else {
      throw CameraManagerError.cameraNotInitialized
    }

    try device.lockForConfiguration()

    defer {
      device.unlockForConfiguration()
    }

    if mode == "locked" {

      guard device.isExposureModeSupported(
        .locked
      ) else {
        throw CameraManagerError.unsupported(
          "裝置不支援鎖定曝光"
        )
      }

      device.exposureMode = .locked

    } else {

      guard device.isExposureModeSupported(
        .continuousAutoExposure
      ) else {
        throw CameraManagerError.unsupported(
          "裝置不支援自動曝光"
        )
      }

      device.exposureMode =
        .continuousAutoExposure
    }
  }

  // MARK: - Focus

  func setFocus(
    mode: String,
    position: Float
  ) throws {

    guard let device = selectedDevice else {
      throw CameraManagerError.cameraNotInitialized
    }

    try device.lockForConfiguration()

    defer {
      device.unlockForConfiguration()
    }

    if mode == "locked" {

      guard device.isLockingFocusWithCustomLensPositionSupported else {
        throw CameraManagerError.unsupported(
          "裝置不支援手動對焦"
        )
      }

      let lensPosition = min(
        max(position, 0.0),
        1.0
      )

      device.setFocusModeLocked(
        lensPosition: lensPosition
      )

    } else {

      let focusMode: AVCaptureDevice.FocusMode

      if mode == "auto" {
        focusMode = .autoFocus
      } else {
        focusMode = .continuousAutoFocus
      }

      guard device.isFocusModeSupported(
        focusMode
      ) else {
        throw CameraManagerError.unsupported(
          "裝置不支援指定對焦模式"
        )
      }

      device.focusMode = focusMode
    }
  }

  // MARK: - Focus Point

  func setFocusPoint(
    x: Double,
    y: Double
  ) throws {

    guard let device = selectedDevice else {
      throw CameraManagerError.cameraNotInitialized
    }

    guard device.isFocusPointOfInterestSupported else {
      throw CameraManagerError.unsupported(
        "裝置不支援指定對焦點"
      )
    }

    try device.lockForConfiguration()

    defer {
      device.unlockForConfiguration()
    }

    let point = CGPoint(
      x: min(max(x, 0.0), 1.0),
      y: min(max(y, 0.0), 1.0)
    )

    device.focusPointOfInterest = point

    if device.isFocusModeSupported(
      .autoFocus
    ) {
      device.focusMode = .autoFocus
    }
  }

  // MARK: - White Balance

  func setWhiteBalance(
    kelvin: Float
  ) throws {

    guard let device = selectedDevice else {
      throw CameraManagerError.cameraNotInitialized
    }

    guard device.isWhiteBalanceModeSupported(
      .locked
    ) else {
      throw CameraManagerError.unsupported(
        "裝置不支援自訂白平衡"
      )
    }

    try device.lockForConfiguration()

    defer {
      device.unlockForConfiguration()
    }

    let temperature =
      AVCaptureDevice.WhiteBalanceTemperatureAndTintValues(
        temperature: kelvin,
        tint: 0
      )

    var gains =
      device.deviceWhiteBalanceGains(
        for: temperature
      )

    gains.redGain = min(
      max(
        gains.redGain,
        1.0
      ),
      device.maxWhiteBalanceGain
    )

    gains.greenGain = min(
      max(
        gains.greenGain,
        1.0
      ),
      device.maxWhiteBalanceGain
    )

    gains.blueGain = min(
      max(
        gains.blueGain,
        1.0
      ),
      device.maxWhiteBalanceGain
    )

    device.setWhiteBalanceModeLocked(
      with: gains
    )
  }

  // MARK: - Auto White Balance

  func setAutoWhiteBalance() throws {

    guard let device = selectedDevice else {
      throw CameraManagerError.cameraNotInitialized
    }

    guard device.isWhiteBalanceModeSupported(
      .continuousAutoWhiteBalance
    ) else {
      throw CameraManagerError.unsupported(
        "裝置不支援自動白平衡"
      )
    }

    try device.lockForConfiguration()

    defer {
      device.unlockForConfiguration()
    }

    device.whiteBalanceMode =
      .continuousAutoWhiteBalance
  }

  // MARK: - HDR

  func setHDR(
    enabled: Bool
  ) throws {

    guard let device = selectedDevice else {
      throw CameraManagerError.cameraNotInitialized
    }

    guard device.activeFormat.isVideoHDRSupported else {
      throw CameraManagerError.unsupported(
        "目前鏡頭不支援 HDR"
      )
    }

    try device.lockForConfiguration()

    defer {
      device.unlockForConfiguration()
    }

    device.automaticallyAdjustsVideoHDREnabled = false

    device.isVideoHDREnabled = enabled
  }

  // MARK: - Flash

  func setFlashMode(
    mode: String
  ) throws {

    guard let device = selectedDevice else {
      throw CameraManagerError.cameraNotInitialized
    }

    guard device.hasFlash || device.hasTorch else {
      throw CameraManagerError.unsupported(
        "目前鏡頭沒有閃光燈"
      )
    }

    try device.lockForConfiguration()

    defer {
      device.unlockForConfiguration()
    }

    switch mode {

    case "torch":

      guard device.hasTorch else {
        throw CameraManagerError.unsupported(
          "目前鏡頭不支援手電筒"
        )
      }

      try device.setTorchModeOn(
        level: AVCaptureDevice.maxAvailableTorchLevel
      )

    case "on":

      if device.hasTorch {
        device.torchMode = .off
      }

    case "off":

      if device.hasTorch {
        device.torchMode = .off
      }

    case "auto":

      if device.hasTorch {
        device.torchMode = .off
      }

    default:

      if device.hasTorch {
        device.torchMode = .off
      }
    }
  }

  // MARK: - Camera Information

  func cameraInfo() -> [String: Any] {

    guard let device = selectedDevice else {
      return [
        "initialized": false
      ]
    }

    return [
      "initialized": true,
      "position":
        currentPosition == .front
          ? "front"
          : "back",
      "lensType": currentLensType,
      "name": device.localizedName,
      "uniqueID": device.uniqueID,
      "minZoom":
        device.minAvailableVideoZoomFactor,
      "maxZoom":
        device.maxAvailableVideoZoomFactor,
      "hdrSupported":
        device.activeFormat.isVideoHDRSupported,
      "hasFlash":
        device.hasFlash,
      "hasTorch":
        device.hasTorch
    ]
  }

  // MARK: - Camera Discovery

  func discoverCameras() -> [[String: Any]] {

    let discoverySession =
      AVCaptureDevice.DiscoverySession(
        deviceTypes: [
          .builtInWideAngleCamera,
          .builtInUltraWideCamera,
          .builtInTelephotoCamera,
          .builtInTripleCamera,
          .builtInDualCamera,
          .builtInDualWideCamera
        ],
        mediaType: .video,
        position: .unspecified
      )

    return discoverySession.devices.map { device in

      let lensType: String

      switch device.deviceType {

      case .builtInUltraWideCamera:
        lensType = "ultraWide"

      case .builtInTelephotoCamera:
        lensType = "telephoto"

      default:
        lensType = "wide"
      }

      return [
        "id": device.uniqueID,
        "name": device.localizedName,
        "position":
          device.position == .front
            ? "front"
            : "back",
        "lensType": lensType,
        "maxZoom":
          device.activeFormat.videoMaxZoomFactor,
        "hdrSupported":
          device.activeFormat.isVideoHDRSupported,
        "hasFlash":
          device.hasFlash,
        "hasTorch":
          device.hasTorch
      ]
    }
  }
}

// MARK: - Errors

enum CameraManagerError: Error {

  case cameraNotFound(
    position: AVCaptureDevice.Position,
    lensType: String
  )

  case inputCreationFailed(
    String
  )

  case cannotAddInput

  case cannotAddPhotoOutput

  case cannotAddVideoOutput

  case cameraNotInitialized

  case unsupported(
    String
  )

  var code: String {

    switch self {

    case .cameraNotFound:
      return "CAMERA_NOT_FOUND"

    case .inputCreationFailed:
      return "INPUT_CREATION_FAILED"

    case .cannotAddInput:
      return "CANNOT_ADD_INPUT"

    case .cannotAddPhotoOutput:
      return "CANNOT_ADD_PHOTO_OUTPUT"

    case .cannotAddVideoOutput:
      return "CANNOT_ADD_VIDEO_OUTPUT"

    case .cameraNotInitialized:
      return "CAMERA_NOT_INITIALIZED"

    case .unsupported:
      return "UNSUPPORTED"
    }
  }

  var message: String {

    switch self {

    case .cameraNotFound(
      let position,
      let lensType
    ):

      let positionText =
        position == .front
          ? "前置"
          : "後置"

      return "找不到 \(positionText) \(lensType) 鏡頭"

    case .inputCreationFailed(
      let message
    ):

      return message

    case .cannotAddInput:
      return "無法加入相機輸入"

    case .cannotAddPhotoOutput:
      return "無法加入照片輸出"

    case .cannotAddVideoOutput:
      return "無法加入影片輸出"

    case .cameraNotInitialized:
      return "原生相機尚未初始化"

    case .unsupported(
      let message
    ):

      return message
    }
  }
}
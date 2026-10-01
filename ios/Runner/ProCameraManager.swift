import AVFoundation
import ImageIO
import UIKit
import Photos
import CoreImage
import CoreImage.CIFilterBuiltins

final class ProCameraManager: NSObject {

  // MARK: - Camera Session

  let session = AVCaptureSession()

  private(set) var currentInput: AVCaptureDeviceInput?

  private(set) var currentPosition: AVCaptureDevice.Position = .back

  private(set) var currentLensType: String = "wide"

  private var currentPhotoFlashMode: AVCaptureDevice.FlashMode = .off

  // MARK: - Outputs

  let photoOutput = AVCapturePhotoOutput()

  let videoOutput = AVCaptureVideoDataOutput()

  let movieOutput = AVCaptureMovieFileOutput()

  // MARK: - Session Queue

  private let sessionQueue = DispatchQueue(
    label: "ai.camera.session.queue",
    qos: .userInitiated
  )

  // MARK: - Core Image

  private let ciContext = CIContext(
    options: [
      CIContextOption.useSoftwareRenderer: false
    ]
  )

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

      AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in

        guard let self = self else {
          return
        }

        guard granted else {
          print("Camera permission denied")
          return
        }

        DispatchQueue.main.async {

          do {
            try self.start(
              position: position,
              lensType: lensType
            )
          } catch {
            print(
              "Camera start failed: \(error)"
            )
          }
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

    // ------------------------------------------------------------
    // Photo / Live Photo quality
    // ------------------------------------------------------------

    if session.canSetSessionPreset(.photo) {
      session.sessionPreset = .photo
    }

    // ------------------------------------------------------------
    // Remove old input
    // ------------------------------------------------------------

    if let currentInput = currentInput {

      session.removeInput(currentInput)

      self.currentInput = nil
    }

    // ------------------------------------------------------------
    // Create new input
    // ------------------------------------------------------------

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

    if photoOutput.isLivePhotoCaptureSupported {
        photoOutput.isLivePhotoCaptureEnabled = true
        photoOutput.isLivePhotoAutoTrimmingEnabled = true

        print(
            "📸 Live Photo: re-enabled after camera switch"
        )
    }

    configureConnection()

    // ------------------------------------------------------------
    // Photo output
    // ------------------------------------------------------------

    if !session.outputs.contains(photoOutput) {

    guard session.canAddOutput(photoOutput) else {
        throw CameraManagerError.cannotAddPhotoOutput
    }

    session.addOutput(photoOutput)
      }

      // ------------------------------------------------------------
      // Live Photo
      // ------------------------------------------------------------

      if photoOutput.isLivePhotoCaptureSupported {

          photoOutput.isLivePhotoCaptureEnabled = true
          photoOutput.isLivePhotoAutoTrimmingEnabled = true

          print(
              "📸 Live Photo: enabled =",
              photoOutput.isLivePhotoCaptureEnabled
          )

      } else {

          print("⚠️ Live Photo: NOT supported")
      }

      if #available(iOS 16.0, *) {

          photoOutput.maxPhotoQualityPrioritization =
              .quality
      }

    // ------------------------------------------------------------
    // Video output
    // ------------------------------------------------------------

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

    guard let connection =
      videoOutput.connection(with: .video)
    else {
      return
    }

    if connection.isVideoOrientationSupported {
      connection.videoOrientation = .portrait
    }

    if connection.isVideoStabilizationSupported {
      connection.preferredVideoStabilizationMode = .auto
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

    // ------------------------------------------------------------
    // 重新確認 Live Photo 狀態
    // ------------------------------------------------------------

    if photoOutput.isLivePhotoCaptureSupported {
        photoOutput.isLivePhotoCaptureEnabled = true
        photoOutput.isLivePhotoAutoTrimmingEnabled = true

        print(
            "📸 Live Photo after camera switch:",
            photoOutput.isLivePhotoCaptureEnabled
        )
    } else {
        photoOutput.isLivePhotoCaptureEnabled = false

        print(
            "⚠️ Live Photo 不支援目前鏡頭：",
            lensType
        )
    }
  // MARK: - Selected Device

  private var selectedDevice: AVCaptureDevice? {
    currentInput?.device
  }

  // MARK: - Capture Photo

  private var photoCaptureDelegate: PhotoCaptureDelegate?

  private var movieRecordingDelegate: MovieRecordingDelegate?

  func capturePhoto() async throws -> String {

    guard session.isRunning else {
      throw CameraManagerError.cameraNotInitialized
    }

    guard session.outputs.contains(photoOutput) else {
      throw CameraManagerError.cannotAddPhotoOutput
    }

    let settings: AVCapturePhotoSettings

    if photoOutput.availablePhotoCodecTypes.contains(
      AVVideoCodecType.jpeg
    ) {

      settings = AVCapturePhotoSettings(
        format: [
          AVVideoCodecKey:
            AVVideoCodecType.jpeg
        ]
      )

    } else {

      settings = AVCapturePhotoSettings()
    }

    // ------------------------------------------------------------
    // Photo quality
    // ------------------------------------------------------------

    if photoOutput.maxPhotoQualityPrioritization == .quality {

      settings.photoQualityPrioritization = .quality
    }

    // ------------------------------------------------------------
    // Photo flash
    // ------------------------------------------------------------

    if let device = selectedDevice,
       device.hasFlash,
       photoOutput.supportedFlashModes.contains(
         currentPhotoFlashMode
       ) {

      settings.flashMode = currentPhotoFlashMode
    }

    // ------------------------------------------------------------
    // Photo orientation
    // ------------------------------------------------------------

    if let connection =
      photoOutput.connection(with: .video) {

      if connection.isVideoOrientationSupported {
        connection.videoOrientation = .portrait
      }
    }

    return try await withCheckedThrowingContinuation {
      (
        continuation:
          CheckedContinuation<String, Error>
      ) in

      let delegate = PhotoCaptureDelegate(
        continuation: continuation
      )

      photoCaptureDelegate = delegate

      photoOutput.capturePhoto(
        with: settings,
        delegate: delegate
      )
    }
  }

  // MARK: - Core Image Photo Effects

func applyPhotoEffects(
    sourcePath: String,
    filter: String,
    paletteRed: Double,
    paletteGreen: Double,
    paletteBlue: Double,
    paletteOpacity: Double,
    exposure: Double,
    nightMode: Bool
) throws -> String {

    let sourceURL = URL(
        fileURLWithPath: sourcePath
    )

    guard FileManager.default.fileExists(
        atPath: sourceURL.path
    ) else {

        throw CameraManagerError.unsupported(
            "找不到要套用特效的照片"
        )
    }

    // ------------------------------------------------------------
    // 1. Load image
    // ------------------------------------------------------------

    guard let inputImage = CIImage(
        contentsOf: sourceURL,
        options: [
            CIImageOption.applyOrientationProperty: true
        ]
    ) else {

        throw CameraManagerError.unsupported(
            "Core Image 無法讀取照片"
        )
    }

    let originalExtent = inputImage.extent

    guard !originalExtent.isEmpty else {

        throw CameraManagerError.unsupported(
            "原始照片範圍為空"
        )
    }

    var image = inputImage

    print("🎨 Core Image Photo Effects")
    print("🎨 source:", sourcePath)
    print("🎨 filter:", filter)
    print("🎨 palette:",
          paletteRed,
          paletteGreen,
          paletteBlue)
    print("🎨 paletteOpacity:", paletteOpacity)
    print("🎨 exposure:", exposure)
    print("🎨 night:", nightMode)

   
    // ------------------------------------------------------------
    // 2. Filter：實際影像色彩處理
    // ------------------------------------------------------------

    func applyColorControls(
      saturation: Float,
      contrast: Float,
      brightness: Float
    ) {
      let filter = CIFilter.colorControls()
      filter.inputImage = image
      filter.saturation = saturation
      filter.contrast = contrast
      filter.brightness = brightness

      if let output = filter.outputImage {
        image = output
      }
    }

    func applyTemperature(
      temperature: Float,
      tint: Float = 0
    ) {
      let filter = CIFilter.temperatureAndTint()
      filter.inputImage = image
      filter.neutral = CIVector(
        x: 6500,
        y: 0
      )
      filter.targetNeutral = CIVector(
        x: CGFloat(temperature),
        y: CGFloat(tint)
      )

      if let output = filter.outputImage {
        image = output
      }
    }

    func applyHighlightShadow(
      shadows: Float,
      highlights: Float
    ) {
      let filter = CIFilter.highlightShadowAdjust()
      filter.inputImage = image
      filter.shadowAmount = shadows
      filter.highlightAmount = highlights

      if let output = filter.outputImage {
        image = output
      }
    }

    switch filter {

    case "鮮明":
      applyColorControls(
        saturation: 1.22,
        contrast: 1.12,
        brightness: 0.01
      )
      applyHighlightShadow(
        shadows: 0.15,
        highlights: 0.92
      )

    case "溫暖":
      applyTemperature(
        temperature: 7200,
        tint: 4
      )
      applyColorControls(
        saturation: 1.08,
        contrast: 1.04,
        brightness: 0.015
      )

    case "冷色":
      applyTemperature(
        temperature: 4300,
        tint: -3
      )
      applyColorControls(
        saturation: 1.04,
        contrast: 1.06,
        brightness: 0
      )

    case "復古":
      applyColorControls(
        saturation: 0.78,
        contrast: 0.92,
        brightness: 0.035
      )
      applyHighlightShadow(
        shadows: 0.35,
        highlights: 0.85
      )
      image = applyColorOverlay(
        image: image,
        red: 0.58,
        green: 0.39,
        blue: 0.23,
        opacity: 0.07
      )

    default:
      break
    }

    // ------------------------------------------------------------
    // 3. Palette：自訂色彩調整
    // ------------------------------------------------------------

    let clampedPaletteOpacity = min(
      max(paletteOpacity, 0.0),
      0.12
    )

    if clampedPaletteOpacity > 0.001 {
      image = applyColorOverlay(
        image: image,
        red: paletteRed,
        green: paletteGreen,
        blue: paletteBlue,
        opacity: clampedPaletteOpacity
      )
    }

    // ------------------------------------------------------------
    // 4. Exposure
    // ------------------------------------------------------------

    if abs(exposure) > 0.001 {

        let exposureFilter =
            CIFilter.exposureAdjust()

        exposureFilter.inputImage = image

        exposureFilter.ev =
            Float(exposure)

        if let output =
            exposureFilter.outputImage {

            image = output
        }

        print(
            "🎨 Exposure applied:",
            exposure
        )
    }

    // ------------------------------------------------------------
    // 5. Night Mode
    // ------------------------------------------------------------

    if nightMode {

        let colorControls =
            CIFilter.colorControls()

        colorControls.inputImage = image
        colorControls.brightness = 0.08
        colorControls.contrast = 1.02
        colorControls.saturation = 1.04

        if let output =
            colorControls.outputImage {

            image = output
        }

        image = applyColorOverlay(
            image: image,
            red: 0.20,
            green: 0.28,
            blue: 0.55,
            opacity: 0.06
        )

        print("🎨 Night Mode applied")
    }

    // ------------------------------------------------------------
    // 6. Crop back to original extent
    // ------------------------------------------------------------

    image =
        image.cropped(
            to: originalExtent
        )

    // ------------------------------------------------------------
    // 7. Render as standard sRGB JPEG
    // ------------------------------------------------------------

    guard let outputColorSpace =
        CGColorSpace(
            name: CGColorSpace.sRGB
        )
    else {

        throw CameraManagerError.unsupported(
            "無法建立 sRGB 色彩空間"
        )
    }

    guard let outputCGImage =
        ciContext.createCGImage(
            image,
            from: originalExtent,
            format: .RGBA8,
            colorSpace: outputColorSpace
        )
    else {

        throw CameraManagerError.unsupported(
            "Core Image 無法建立輸出影像"
        )
    }

    let outputImage =
        UIImage(
            cgImage: outputCGImage,
            scale: 1.0,
            orientation: .up
        )

    guard let jpegData =
        outputImage.jpegData(
            compressionQuality: 0.95
        )
    else {

        throw CameraManagerError.unsupported(
            "JPEG 編碼失敗"
        )
    }

    // ------------------------------------------------------------
    // 8. Output path
    // ------------------------------------------------------------

    let outputDirectory =
        sourceURL.deletingLastPathComponent()

    let filename =
        "processed_\(Int(Date().timeIntervalSince1970 * 1000)).jpg"

    let outputURL =
        outputDirectory.appendingPathComponent(
            filename
        )

    try jpegData.write(
        to: outputURL,
        options: .atomic
    )

    print(
        "🎨 Core Image output:",
        outputURL.path
    )

    print(
        "🎨 Output size:",
        jpegData.count,
        "bytes"
    )

    return outputURL.path
}

// MARK: - Core Image Color Overlay

private func applyColorOverlay(
    image: CIImage,
    red: Double,
    green: Double,
    blue: Double,
    opacity: Double
) -> CIImage {

    let clampedRed =
        min(
            max(red, 0.0),
            1.0
        )

    let clampedGreen =
        min(
            max(green, 0.0),
            1.0
        )

    let clampedBlue =
        min(
            max(blue, 0.0),
            1.0
        )

    let clampedOpacity =
        min(
            max(opacity, 0.0),
            1.0
        )

    let color =
        CIColor(
            red: CGFloat(clampedRed),
            green: CGFloat(clampedGreen),
            blue: CGFloat(clampedBlue),
            alpha: CGFloat(clampedOpacity)
        )

    let overlay =
        CIImage(
            color: color
        ).cropped(
            to: image.extent
        )

    let compositingFilter =
        CIFilter.sourceOverCompositing()

    compositingFilter.inputImage =
        overlay

    compositingFilter.backgroundImage =
        image

    return compositingFilter.outputImage ?? image
}


  // MARK: - Video Recording

  func startVideoRecording() throws {

    guard session.isRunning else {
      throw CameraManagerError.cameraNotInitialized
    }

    guard !movieOutput.isRecording else {
      throw CameraManagerError.movieAlreadyRecording
    }

    session.beginConfiguration()

    // 不需要移除 photoOutput。
    //
    // AVCapturePhotoOutput 可以與 MovieFileOutput 同時存在，
    // 但 MovieFileOutput 存在期間 Live Photo 會被停用。

    guard session.canAddOutput(movieOutput) else {

      session.commitConfiguration()

      throw CameraManagerError.cannotAddMovieOutput
    }

    session.addOutput(movieOutput)

    guard let connection =
      movieOutput.connection(with: .video)
    else {

      session.removeOutput(movieOutput)

      session.commitConfiguration()

      throw CameraManagerError.unsupported(
        "找不到影片輸出連線"
      )
    }

    if connection.isVideoOrientationSupported {
      connection.videoOrientation = .portrait
    }

    if connection.isVideoStabilizationSupported {
      connection.preferredVideoStabilizationMode = .auto
    }

    session.commitConfiguration()

    let fileManager =
      FileManager.default

    let documentsURL =
      fileManager.urls(
        for: .documentDirectory,
        in: .userDomainMask
      )[0]

    let capturesURL =
      documentsURL.appendingPathComponent(
        "captures",
        isDirectory: true
      )

    try fileManager.createDirectory(
      at: capturesURL,
      withIntermediateDirectories: true
    )

    let filename =
      "VID_\(Int(Date().timeIntervalSince1970 * 1000)).mov"

    let fileURL =
      capturesURL.appendingPathComponent(
        filename
      )

    let delegate =
      MovieRecordingDelegate(
        manager: self
      )

    movieRecordingDelegate = delegate

    movieOutput.startRecording(
      to: fileURL,
      recordingDelegate: delegate
    )

    print(
      "🎥 Start recording:",
      fileURL.path
    )
  }

  func stopVideoRecording() async throws -> String {

    guard movieOutput.isRecording else {
      throw CameraManagerError.movieNotRecording
    }

    guard let delegate =
      movieRecordingDelegate
    else {
      throw CameraManagerError.movieNotRecording
    }

    return try await withCheckedThrowingContinuation {
      (
        continuation:
          CheckedContinuation<String, Error>
      ) in

      delegate.continuation =
        continuation

      movieOutput.stopRecording()
    }
  }

  func finishVideoRecording() {

    sessionQueue.async { [weak self] in

        guard let self = self else {
            return
        }

        self.session.beginConfiguration()

        if self.session.outputs.contains(
            self.movieOutput
        ) {

            self.session.removeOutput(
                self.movieOutput
            )
        }

        // ----------------------------------------------------
        // 影片錄影結束後重新啟用 Live Photo
        // ----------------------------------------------------

        if self.photoOutput.isLivePhotoCaptureSupported {

            self.photoOutput.isLivePhotoCaptureEnabled = true
            self.photoOutput.isLivePhotoAutoTrimmingEnabled = true

            print(
                "📸 Live Photo: re-enabled after video"
            )
        }

          self.session.commitConfiguration()

          self.movieRecordingDelegate = nil

          print(
              "🎥 Movie output removed"
          )
      }
  }

  // MARK: - Capture Live Photo

  private var livePhotoCaptureDelegate:
    LivePhotoCaptureDelegate?

  func saveLivePhoto(
    photoPath: String,
    videoPath: String
  ) async throws -> Bool {

    let photoURL =
      URL(fileURLWithPath: photoPath)

    let videoURL =
      URL(fileURLWithPath: videoPath)

    guard FileManager.default.fileExists(
      atPath: photoURL.path
    ) else {

      throw CameraManagerError.unsupported(
        "找不到 Live Photo 照片檔案"
      )
    }

    guard FileManager.default.fileExists(
      atPath: videoURL.path
    ) else {

      throw CameraManagerError.unsupported(
        "找不到 Live Photo 影片檔案"
      )
    }

    let authorizationStatus =
      PHPhotoLibrary.authorizationStatus(
        for: .addOnly
      )

    if authorizationStatus == .notDetermined {

      let granted =
        await PHPhotoLibrary.requestAuthorization(
          for: .addOnly
        )

      guard granted == .authorized ||
            granted == .limited
      else {

        throw CameraManagerError.unsupported(
          "沒有照片加入權限"
        )
      }

    } else {

      guard authorizationStatus == .authorized ||
            authorizationStatus == .limited
      else {

        throw CameraManagerError.unsupported(
          "沒有照片加入權限"
        )
      }
    }

    return try await withCheckedThrowingContinuation {
      (
        continuation:
          CheckedContinuation<Bool, Error>
      ) in

      PHPhotoLibrary.shared().performChanges({

        let creationRequest =
          PHAssetCreationRequest.forAsset()

        creationRequest.addResource(
          with: .photo,
          fileURL: photoURL,
          options: nil
        )

        creationRequest.addResource(
          with: .pairedVideo,
          fileURL: videoURL,
          options: nil
        )

      }) { success, error in

        if let error = error {

          continuation.resume(
            throwing: error
          )

          return
        }

        continuation.resume(
          returning: success
        )
      }
    }
  }

  func captureLivePhoto() async throws
    -> [String: String] {

    guard session.isRunning else {
      throw CameraManagerError.cameraNotInitialized
    }

    guard session.outputs.contains(
      photoOutput
    ) else {

      throw CameraManagerError.cannotAddPhotoOutput
    }

    guard photoOutput.isLivePhotoCaptureSupported else {

      throw CameraManagerError.unsupported(
        "目前鏡頭或拍攝格式不支援 Live Photo"
      )
    }

    guard photoOutput.isLivePhotoCaptureEnabled else {

      throw CameraManagerError.unsupported(
        "Live Photo 尚未啟用"
      )
    }

    let fileManager =
      FileManager.default

    let documentsURL =
      fileManager.urls(
        for: .documentDirectory,
        in: .userDomainMask
      )[0]

    let capturesURL =
      documentsURL.appendingPathComponent(
        "captures",
        isDirectory: true
      )

    try fileManager.createDirectory(
      at: capturesURL,
      withIntermediateDirectories: true
    )

    let timestamp =
      Int(Date().timeIntervalSince1970 * 1000)

    let photoURL =
      capturesURL.appendingPathComponent(
        "LIVE_\(timestamp).jpg"
      )

    let movieURL =
      capturesURL.appendingPathComponent(
        "LIVE_\(timestamp).mov"
      )

    let settings: AVCapturePhotoSettings

    if photoOutput.availablePhotoCodecTypes.contains(
      AVVideoCodecType.jpeg
    ) {

      settings = AVCapturePhotoSettings(
        format: [
          AVVideoCodecKey:
            AVVideoCodecType.jpeg
        ]
      )

    } else {

      settings = AVCapturePhotoSettings()
    }

    // Photo quality

    if photoOutput.maxPhotoQualityPrioritization == .quality {

      settings.photoQualityPrioritization = .quality
    }

    // Flash

    if let device = selectedDevice,
       device.hasFlash,
       photoOutput.supportedFlashModes.contains(
         currentPhotoFlashMode
       ) {

      settings.flashMode =
        currentPhotoFlashMode
    }

    // Live Photo movie

    settings.livePhotoMovieFileURL =
      movieURL

    if let codec =
      photoOutput.availableLivePhotoVideoCodecTypes.first {

      settings.livePhotoVideoCodecType =
        codec
    }

    // Orientation

    if let connection =
      photoOutput.connection(
        with: .video
      ) {

      if connection.isVideoOrientationSupported {
        connection.videoOrientation =
          .portrait
      }
    }

    return try await withCheckedThrowingContinuation {
      (
        continuation:
          CheckedContinuation<
            [String: String],
            Error
          >
      ) in

      let delegate =
        LivePhotoCaptureDelegate(
          continuation: continuation,
          photoURL: photoURL,
          movieURL: movieURL
        )

      livePhotoCaptureDelegate =
        delegate

      photoOutput.capturePhoto(
        with: settings,
        delegate: delegate
      )
    }
  }

  // MARK: - Zoom

  func setZoom(
    _ value: Double
  ) throws {

    guard let device = selectedDevice else {
      throw CameraManagerError.cameraNotInitialized
    }

    try device.lockForConfiguration()

    defer {
      device.unlockForConfiguration()
    }

    let minZoom =
      device.minAvailableVideoZoomFactor

    let maxZoom =
      min(
        device.maxAvailableVideoZoomFactor,
        20.0
      )

    let zoom =
      min(
        max(value, minZoom),
        maxZoom
      )

    device.videoZoomFactor =
      zoom
  }

  // MARK: - Exposure Bias

  func setExposureBias(
    _ value: Float
  ) throws {

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

    device.exposureMode =
      .continuousAutoExposure

    let bias =
      min(
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

    let clampedISO =
      min(
        max(
          iso,
          device.activeFormat.minISO
        ),
        device.activeFormat.maxISO
      )

    let requestedDuration =
      CMTime(
        seconds: duration,
        preferredTimescale: 1_000_000
      )

    let minDuration =
      device.activeFormat.minExposureDuration

    let maxDuration =
      device.activeFormat.maxExposureDuration

    let clampedDuration =
      CMTimeMaximum(
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

      let lensPosition =
        min(
          max(position, 0.0),
          1.0
        )

      device.setFocusModeLocked(
        lensPosition: lensPosition
      )

    } else {

      let focusMode:
        AVCaptureDevice.FocusMode

      if mode == "auto" {

        focusMode = .autoFocus

      } else {

        focusMode =
          .continuousAutoFocus
      }

      guard device.isFocusModeSupported(
        focusMode
      ) else {

        throw CameraManagerError.unsupported(
          "裝置不支援指定對焦模式"
        )
      }

      device.focusMode =
        focusMode
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
      "目前鏡頭不支援指定對焦點"
    )
  }

  let point = CGPoint(
    x: min(max(x, 0.0), 1.0),
    y: min(max(y, 0.0), 1.0)
  )

  try device.lockForConfiguration()

  defer {
    device.unlockForConfiguration()
  }

  // 設定指定對焦位置。
  device.focusPointOfInterest = point

  // 先切換至連續對焦，再啟動單次自動對焦，
  // 讓重複點擊也能重新觸發對焦。
  if device.isFocusModeSupported(.continuousAutoFocus) {
    device.focusMode = .continuousAutoFocus
  }

  guard device.isFocusModeSupported(.autoFocus) else {
    throw CameraManagerError.unsupported(
      "目前鏡頭不支援單次自動對焦"
    )
  }

  device.focusMode = .autoFocus

  print(
    "🎯 Focus applied:",
    "device =", device.localizedName,
    "point =", point,
    "mode = autoFocus"
  )
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

    gains.redGain =
      min(
        max(
          gains.redGain,
          1.0
        ),
        device.maxWhiteBalanceGain
      )

    gains.greenGain =
      min(
        max(
          gains.greenGain,
          1.0
        ),
        device.maxWhiteBalanceGain
      )

    gains.blueGain =
      min(
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

    device.automaticallyAdjustsVideoHDREnabled =
      false

    device.isVideoHDREnabled =
      enabled
  }

  // MARK: - Flash / Torch

  func setFlashMode(
    mode: String
  ) throws {

    guard let device = selectedDevice else {
      throw CameraManagerError.cameraNotInitialized
    }

    guard device.hasFlash ||
          device.hasTorch
    else {

      throw CameraManagerError.unsupported(
        "目前鏡頭沒有閃光燈或手電筒"
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

      device.torchMode = .on

    case "on":

      currentPhotoFlashMode = .on

      if device.hasTorch {
        device.torchMode = .off
      }

    case "auto":

      currentPhotoFlashMode = .auto

      if device.hasTorch {
        device.torchMode = .off
      }

    case "off":

      currentPhotoFlashMode = .off

      if device.hasTorch {
        device.torchMode = .off
      }

    default:

      currentPhotoFlashMode = .off

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

      "lensType":
        currentLensType,

      "name":
        device.localizedName,

      "uniqueID":
        device.uniqueID,

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

  func discoverCameras()
    -> [[String: Any]] {

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

    return discoverySession.devices.map {
      device in

      let lensType: String

      switch device.deviceType {

      case .builtInUltraWideCamera:

        lensType =
          "ultraWide"

      case .builtInTelephotoCamera:

        lensType =
          "telephoto"

      default:

        lensType =
          "wide"
      }

      return [

        "id":
          device.uniqueID,

        "name":
          device.localizedName,

        "position":
          device.position == .front
            ? "front"
            : "back",

        "lensType":
          lensType,

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

// MARK: - Safe Array Access

private extension Array {

  subscript(
    safe index: Index
  ) -> Element? {

    guard indices.contains(index) else {
      return nil
    }

    return self[index]
  }
}

// MARK: - Movie Recording Delegate

private final class MovieRecordingDelegate:
  NSObject,
  AVCaptureFileOutputRecordingDelegate {

  weak var manager:
    ProCameraManager?

  var continuation:
    CheckedContinuation<String, Error>?

  init(
    manager: ProCameraManager
  ) {

    self.manager = manager

    super.init()
  }

  func fileOutput(
    _ output: AVCaptureFileOutput,
    didStartRecordingTo fileURL: URL,
    from connections: [AVCaptureConnection]
  ) {

    print(
      "🎥 Video recording started:",
      fileURL.path
    )
  }

  func fileOutput(
    _ output: AVCaptureFileOutput,
    didFinishRecordingTo outputFileURL: URL,
    from connections: [AVCaptureConnection],
    error: Error?
  ) {

    if let error = error {

      print(
        "❌ Video recording failed:",
        error.localizedDescription
      )

      continuation?.resume(
        throwing: error
      )

    } else {

      print(
        "🎥 Video recording finished:",
        outputFileURL.path
      )

      continuation?.resume(
        returning: outputFileURL.path
      )
    }

    continuation = nil

    manager?.finishVideoRecording()
  }
}

// MARK: - Live Photo Capture Delegate

private final class LivePhotoCaptureDelegate:
  NSObject,
  AVCapturePhotoCaptureDelegate {

  private let continuation:
    CheckedContinuation<
      [String: String],
      Error
    >

  private let photoURL: URL

  private let movieURL: URL

  private var photoPath: String?

  private var moviePath: String?

  private var assetIdentifier: String?

  private var finished = false

  init(
    continuation:
      CheckedContinuation<
        [String: String],
        Error
      >,
    photoURL: URL,
    movieURL: URL
  ) {

    self.continuation =
      continuation

    self.photoURL =
      photoURL

    self.movieURL =
      movieURL

    super.init()
  }

  // ------------------------------------------------------------
  // Photo
  // ------------------------------------------------------------

  func photoOutput(
    _ output: AVCapturePhotoOutput,
    didFinishProcessingPhoto photo: AVCapturePhoto,
    error: Error?
  ) {

    if let error = error {

      finish(
        throwing: error
      )

      return
    }

    guard let data =
      photo.fileDataRepresentation()
    else {

      finish(
        throwing:
          CameraManagerError.unsupported(
            "無法取得 Live Photo 照片資料"
          )
      )

      return
    }

    do {

      try data.write(
        to: photoURL,
        options: .atomic
      )

      photoPath =
        photoURL.path

      tryFinish()

    } catch {

      finish(
        throwing: error
      )
    }
  }

  // ------------------------------------------------------------
  // Live Photo Movie
  // ------------------------------------------------------------

  func photoOutput(
    _ output: AVCapturePhotoOutput,
    didFinishProcessingLivePhotoToMovieFileAt fileURL: URL,
    duration: CMTime,
    photoDisplayTime: CMTime,
    resolvedSettings: AVCaptureResolvedPhotoSettings,
    error: Error?
  ) {

    if let error = error {

      finish(
        throwing: error
      )

      return
    }

    do {

      if fileURL != movieURL {

        if FileManager.default.fileExists(
          atPath: movieURL.path
        ) {

          try FileManager.default.removeItem(
            at: movieURL
          )
        }

        try FileManager.default.moveItem(
          at: fileURL,
          to: movieURL
        )
      }

      moviePath =
        movieURL.path

      tryFinish()

    } catch {

      finish(
        throwing: error
      )
    }
  }

  // ------------------------------------------------------------
  // Finish
  // ------------------------------------------------------------

  private func tryFinish() {

    guard !finished else {
      return
    }

    guard
      let photoPath = photoPath,
      let moviePath = moviePath
    else {
      return
    }

    finished = true

    continuation.resume(
      returning: [

        "photoPath":
          photoPath,

        "videoPath":
          moviePath,

        "assetIdentifier":
          assetIdentifier ?? ""
      ]
    )
  }

  private func finish(
    throwing error: Error
  ) {

    guard !finished else {
      return
    }

    finished = true

    continuation.resume(
      throwing: error
    )
  }
}

// MARK: - Photo Capture Delegate

private final class PhotoCaptureDelegate:
  NSObject,
  AVCapturePhotoCaptureDelegate {

  private let continuation:
    CheckedContinuation<String, Error>

  init(
    continuation:
      CheckedContinuation<String, Error>
  ) {

    self.continuation =
      continuation

    super.init()
  }

  func photoOutput(
    _ output: AVCapturePhotoOutput,
    didFinishProcessingPhoto photo: AVCapturePhoto,
    error: Error?
  ) {

    if let error = error {

      continuation.resume(
        throwing: error
      )

      return
    }

    guard let data =
      photo.fileDataRepresentation()
    else {

      continuation.resume(
        throwing:
          CameraManagerError.unsupported(
            "無法取得照片資料"
          )
      )

      return
    }

    do {

      let fileManager =
        FileManager.default

      let documentsURL =
        fileManager.urls(
          for: .documentDirectory,
          in: .userDomainMask
        )[0]

      let capturesURL =
        documentsURL.appendingPathComponent(
          "captures",
          isDirectory: true
        )

      try fileManager.createDirectory(
        at: capturesURL,
        withIntermediateDirectories: true
      )

      let filename =
        "IMG_\(Int(Date().timeIntervalSince1970 * 1000)).jpg"

      let fileURL =
        capturesURL.appendingPathComponent(
          filename
        )

      try data.write(
        to: fileURL,
        options: .atomic
      )

      print(
        "📸 Original photo:",
        fileURL.path
      )

      print(
        "📸 Original photo size:",
        data.count,
        "bytes"
      )

      continuation.resume(
        returning: fileURL.path
      )

    } catch {

      continuation.resume(
        throwing: error
      )
    }
  }
}

// MARK: - Errors

enum CameraManagerError: Error {

  case cameraNotFound(
    position:
      AVCaptureDevice.Position,
    lensType: String
  )

  case inputCreationFailed(
    String
  )

  case cannotAddInput

  case cannotAddPhotoOutput

  case cannotAddVideoOutput

  case cannotAddMovieOutput

  case movieAlreadyRecording

  case movieNotRecording

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

    case .cannotAddMovieOutput:
      return "CANNOT_ADD_MOVIE_OUTPUT"

    case .movieAlreadyRecording:
      return "MOVIE_ALREADY_RECORDING"

    case .movieNotRecording:
      return "MOVIE_NOT_RECORDING"

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

      return
        "找不到 \(positionText) \(lensType) 鏡頭"

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

    case .cannotAddMovieOutput:

      return "無法加入影片錄影輸出"

    case .movieAlreadyRecording:

      return "影片目前已經在錄影"

    case .movieNotRecording:

      return "目前沒有正在進行的影片錄影"

    case .cameraNotInitialized:

      return "原生相機尚未初始化"

    case .unsupported(
      let message
    ):

      return message
    }
  }
}
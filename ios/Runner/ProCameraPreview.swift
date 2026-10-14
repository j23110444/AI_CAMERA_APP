import AVFoundation
import Flutter
import UIKit

final class ProCameraPreviewFactory: NSObject, FlutterPlatformViewFactory {

  private let cameraManager: ProCameraManager

  init(cameraManager: ProCameraManager) {
    self.cameraManager = cameraManager
    super.init()
  }

  func create(
    withFrame frame: CGRect,
    viewIdentifier viewId: Int64,
    arguments args: Any?
  ) -> FlutterPlatformView {
    return ProCameraPreview(
      frame: frame,
      cameraManager: cameraManager
    )
  }

  func createArgsCodec() -> FlutterMessageCodec & NSObjectProtocol {
    FlutterStandardMessageCodec.sharedInstance()
  }
}

final class ProCameraPreview: NSObject, FlutterPlatformView {

  private let previewView: CameraPreviewView

  init(
    frame: CGRect,
    cameraManager: ProCameraManager
  ) {
    previewView = CameraPreviewView(
      frame: frame,
      cameraManager: cameraManager
    )

    super.init()
  }

  func view() -> UIView {
    return previewView
  }
}

final class CameraPreviewView: UIView {

  private let previewLayer: AVCaptureVideoPreviewLayer

  init(
    frame: CGRect,
    cameraManager: ProCameraManager
  ) {
    let layer = AVCaptureVideoPreviewLayer(
      session: cameraManager.session
    )
    previewLayer = layer

    super.init(frame: frame)

    backgroundColor = .black

    previewLayer.videoGravity = .resizeAspectFill

    self.layer.addSublayer(previewLayer)

    cameraManager.previewPointConverter = { [weak layer] point in
      guard let layer else {
        return point
      }

      return layer.captureDevicePointConverted(
        fromLayerPoint: CGPoint(
          x: point.x * layer.bounds.width,
          y: point.y * layer.bounds.height
        )
      )
    }

    updatePreviewConnection()
  }

  required init?(coder: NSCoder) {
    fatalError("init(coder:) has not been implemented")
  }

  override func layoutSubviews() {
    super.layoutSubviews()

    previewLayer.frame = bounds

    updatePreviewConnection()
  }

  private func updatePreviewConnection() {
    guard let connection = previewLayer.connection else {
      return
    }

    if connection.isVideoOrientationSupported {
      connection.videoOrientation = .portrait
    }

    // 不手動設定 videoMirrored。
    // 避免 iOS 26 上 AVCaptureConnection setVideoMirrored:
    // 觸發 SIGABRT。
  }
}
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:video_player/video_player.dart';
import 'package:file_picker/file_picker.dart' as fp;
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:flutter/gestures.dart';
import 'package:video_player_win/video_player_win.dart';
import 'package:video_player/video_player.dart' as vp;
import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sensors_plus/sensors_plus.dart';

import '../../../core/core.dart';
import '../../../core/application/video_smart_capture_service.dart';

class IOSCameraPage extends StatefulWidget {
  const IOSCameraPage({super.key});

  @override
  State<IOSCameraPage> createState() => _IOSCameraPageState();
}

class _IOSCameraPageState extends State<IOSCameraPage> {

  String _effectDebugMessage = '';

  final PreferenceModel _preferenceModel = const PreferenceModel();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  final GlobalKey _previewKey = GlobalKey();
  final Map<String, String> _livePhotoAssetIdentifiers = {};
  VideoPlayerController? _recordedVideoPreviewController;
  String _currentMode = '拍照'; // 影片、拍照、物景
  bool _isCapturing = false;
  bool _captureAnimation = false;

  bool _isRecording = false;
  // ignore: prefer_final_fields
  int _recordingSeconds = 0;
  Timer? _recordingTimer;
  Timer? _captureTimer;

  // 上傳影片播放與抓拍相關狀態
  String? _activeUploadedVideo; // 有值代表正在預覽上傳的影片
  bool _isVideoPlaying = false;
  double _videoProgress = 0.0; // 0.0 ~ 1.0
  WinVideoPlayerController? _videoPlayerController;
  String? _videoLoadError;
  final List<String> _recordedVideos = [];
  // AI 影片分析：下一次分析的起始位置
  Duration? _nextVideoCapturePosition;

  final VideoSmartCaptureService _videoSmartCaptureService =
      VideoSmartCaptureService();
  final FlutterCameraAdapter _cameraAdapter = FlutterCameraAdapter();
  StreamSubscription<CameraMetrics>? _metricsSubscription;
  StreamSubscription<AccelerometerEvent>? _accelerometerSubscription;
  CameraMetrics? _cameraMetrics;
  bool _cameraInitializing = true;
  bool _cameraSwitching = false;
  bool _isUltraWideActive = false;
  String? _cameraError;
  bool _proModeEnabled = false;
  bool _histogramEnabled = false;
  bool _focusPeakingEnabled = false;
  bool _zebraEnabled = false;
  double _isoValue = 100;
  double _shutterSeconds = 1 / 120;
  double _manualFocus = 0.5;
  String _whiteBalance = '自動';
  int _kelvin = 5200;

  // ============================================================
  // AI 候選照片
  //
  // 影片分析後產生的暫存照片。
  // 左滑刪除 / 右滑保存。
  // ============================================================
  final List<String> _capturedImages = [];

  // ============================================================
  // 永久保存照片
  //
  // 真正保存到 App 專用資料夾後的照片路徑。
  // Gallery / 相簿應該使用這個清單。
  // ============================================================
  final List<String> _savedImages = [];
  final Map<String, String> _livePhotoVideos = {};

  // Live Photo 原始照片，用於最後匯出到 Apple 照片
  final Map<String, String> _livePhotoOriginalPhotos = {};
  String? _aiTipMessage;
  Timer? _aiTipTimer;

  // 構圖線狀態
  String _compositionGrid = '關閉';

  // iOS 相機進階設定狀態
  bool _isTopMenuExpanded = false;
  String _flashMode = '自動'; // 自動、開啟、關閉
  String _aspectRatio = '4:3'; // 4:3、16:9、1:1

  // 濾鏡與調色盤分離
  String _filterMode = '原味'; // 固定濾鏡：原味、鮮明、溫暖、冷色、復古
  // 底部調整模式：null / palette / filter
  String? _activeBottomAdjustment;
  // 調色盤：點擊控制項展開預設；長按預設進入方形自訂調色區
  bool _isPaletteOpen = false;
  bool _isPaletteEditing = false;
  String _selectedPalette = '原味';
  double _paletteX = 0.5; // 0 ~ 1：色彩方向
  double _paletteY = 0.5; // 0 ~ 1：亮度 / 強度

  // 曝光狀態
  double _exposureValue = 0.0; // -2.0 ~ 2.0
  bool _isExposureSliding = false; // 下方是否正在顯示曝光刻度

  bool _nightMode = false; // 夜間模式
  bool _levelEnabled = false;
  double _levelAngle = 0.0;
  bool _hdrEnabled = false;
  bool _livePhotoEnabled = false;
  int _timerSeconds = 0;
  int _timerCountdown = 0;

  // 點擊對焦與 AE/AF Lock
  Offset? _focusPoint;
  bool _isFocusVisible = false;
  bool _isAeAfLocked = false;
  Timer? _focusTimer;
  Timer? _longPressActivationTimer;
  bool _isLongPressActive = false;
  bool _exposureGestureArmed = false;
  bool _exposureGestureActive = false;
  double _longPressStartExposure = 0.0;
  Offset _gestureDelta = Offset.zero;

  // AI 智慧連拍與新設定狀態
  bool _aiDirectorMode = false; // AI 導演模式
  bool _aiBurstEnabled = true; // AI 智慧連拍開關（已修復：實際於 UI 與邏輯中使用）[cite: 2]
  int _aiBurstSeconds = 3; // 抓拍時間：3秒、5秒
  int _aiBurstCount = 5; // 抓拍張數：3、5、7、10張
  int _passingScore = 3; // 合格分數：1 ~ 5
  String _aiPromptText = ''; // 提示詞關鍵字
  String? _referencePhotoName; // 參考照片名稱

  // 個人化 AI 權重設定
  final Map<String, double> _aiWeights = {
    '構圖美感': 1.0,
    '光影表現': 1.0,
    '人物表情': 1.0,
    '色彩氛圍': 1.0,
  };

  // 💡 已修復：使用安全的一行內初始化，徹底解決 LateInitializationError
  late final TextEditingController _promptController = TextEditingController(
    text: _aiPromptText,
  );

  // 縮放倍數狀態
  double _zoomLevel = 1.0;
  double _baseZoom = 1.0;
  bool _isZoomDragging = false;

  final List<String> _modes = ['影片', '拍照', '物景'];

  //影片
  Future<void> _showRecordedVideoPreview(
  String videoPath,
) async {
  final file = File(videoPath);

  if (!await file.exists()) {
    if (mounted) {
      _showAiTip('⚠️ 找不到錄製的影片檔案');
    }
    return;
  }

  final controller =
      VideoPlayerController.file(file);

  _recordedVideoPreviewController = controller;

  try {
    await controller.initialize();

    if (!mounted) {
      await controller.dispose();
      return;
    }

    await controller.setLooping(true);

    await controller.play();

    if (!mounted) {
      await controller.dispose();
      return;
    }

    await showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black87,
      builder: (dialogContext) {
        return Dialog(
          backgroundColor: Colors.black,
          insetPadding:
              const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 40,
          ),
          child: Stack(
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio:
                      controller.value.aspectRatio > 0
                          ? controller.value.aspectRatio
                          : 9 / 16,
                  child: VideoPlayer(
                    controller,
                  ),
                ),
              ),

              Positioned(
                top: 8,
                right: 8,
                child: GestureDetector(
                  onTap: () {
                    Navigator.of(
                      dialogContext,
                    ).pop();
                  },
                  child: Container(
                    width: 40,
                    height: 40,
                    decoration:
                        const BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                ),
              ),

              Positioned(
                left: 12,
                right: 12,
                bottom: 12,
                child: VideoProgressIndicator(
                  controller,
                  allowScrubbing: true,
                  colors:
                      const VideoProgressColors(
                    playedColor:
                        Colors.yellowAccent,
                    bufferedColor:
                        Colors.white38,
                    backgroundColor:
                        Colors.white24,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  } catch (e, stackTrace) {
    debugPrint(
      '❌ Recorded video preview failed: $e',
    );
    debugPrint('$stackTrace');

    if (mounted) {
      _showAiTip(
        '⚠️ 影片無法播放：$e',
      );
    }
  } finally {
    if (_recordedVideoPreviewController ==
        controller) {
      _recordedVideoPreviewController = null;
    }

    await controller.dispose();
  }
}
  
  @override
  void initState() {
    super.initState();
    _loadSavedImageLists();
    _metricsSubscription = _cameraAdapter.metrics.listen((metrics) {
      if (mounted) setState(() => _cameraMetrics = metrics);
    });
    _accelerometerSubscription = accelerometerEventStream().listen((event) {
      if (!mounted) return;
      final angle = math.atan2(event.y, event.x) + math.pi / 2;
      setState(() => _levelAngle = angle);
    });
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    try {
      await _cameraAdapter.initialize();
      if (!mounted) return;
      setState(() {
        _cameraInitializing = false;
        _cameraError = null;
      });
    } catch (error, stackTrace) {
      debugPrint('Camera initialization failed: $error');
      debugPrint('$stackTrace');
      if (!mounted) return;
      setState(() {
        _cameraInitializing = false;
        _cameraError = error.toString();
      });
    }
  }

  Future<void> _switchCamera() async {
    if (_cameraSwitching || _cameraInitializing) return;
    setState(() => _cameraSwitching = true);
    try {
      await _cameraAdapter.switchCamera();
      if (!mounted) return;
      setState(() {
        _zoomLevel = 1.0;
        _isUltraWideActive = false;
        _focusPoint = null;
        _isFocusVisible = false;
        _isAeAfLocked = false;
      });
      _showAiTip('🔄 已切換鏡頭');
    } catch (error) {
      if (mounted) _showAiTip('⚠️ 鏡頭切換失敗：$error');
    } finally {
      if (mounted) setState(() => _cameraSwitching = false);
    }
  }

  Future<void> _switchToUltraWide() async {
    if (_cameraSwitching || _cameraInitializing) return;
    setState(() => _cameraSwitching = true);
    try {
      await _cameraAdapter.switchToUltraWide();
      if (!mounted) return;
      setState(() {
        _zoomLevel = 0.5;
        _isUltraWideActive = true;
        _focusPoint = null;
        _isFocusVisible = false;
        _isAeAfLocked = false;
      });
      _showAiTip('📷 已切換至 0.5x 廣角');
    } catch (error) {
      if (mounted) _showAiTip('⚠️ 0.5x 廣角無法使用：$error');
    } finally {
      if (mounted) setState(() => _cameraSwitching = false);
    }
  }


  Future<void> _switchToStandardWide() async {
    if (_cameraSwitching || _cameraInitializing) return;
    setState(() => _cameraSwitching = true);
    try {
      await _cameraAdapter.switchToStandardWide();
      if (!mounted) return;
      setState(() {
        _zoomLevel = 1.0;
        _isUltraWideActive = false;
        _focusPoint = null;
        _isFocusVisible = false;
        _isAeAfLocked = false;
      });
    } catch (error) {
      if (mounted) _showAiTip('⚠️ 1x 廣角無法使用：$error');
    } finally {
      if (mounted) setState(() => _cameraSwitching = false);
    }
  }

  
Future<void> _loadSavedImageLists() async {
  
  final prefs = await SharedPreferences.getInstance();

  final captured =
      prefs.getStringList('captured_images') ?? [];

  final saved =
      prefs.getStringList('saved_images') ?? [];

  final validCaptured = <String>[];
  final validSaved = <String>[];

  for (final path in captured) {
    if (await File(path).exists()) {
      validCaptured.add(path);
    }
  }

  for (final path in saved) {
    if (await File(path).exists()) {
      validSaved.add(path);
    }
  }

  // ------------------------------------------------------------
  // 還原 Live Photo 的 Photo ↔ MOV 關聯
  // ------------------------------------------------------------

  final livePhotoVideos = <String, String>{};

  final livePhotoAssetIdentifiers =
      <String, String>{};

  final livePhotoOriginalPhotos =
      <String, String>{};
  final storedVideosJson =
      prefs.getString('live_photo_videos');

  final storedAssetsJson =
      prefs.getString(
        'live_photo_asset_identifiers',
      );
  final storedOriginalPhotosJson =
      prefs.getString(
        'live_photo_original_photos',
      );
  if (storedVideosJson != null) {
    try {
      final decoded = jsonDecode(
        storedVideosJson,
      );

      if (decoded is Map) {
        decoded.forEach((key, value) {
          if (key is String && value is String) {
            livePhotoVideos[key] = value;
          }
        });
      }
    } catch (error) {
      debugPrint(
        '⚠️ Live Photo MOV 關聯資料讀取失敗：$error',
      );
    }
  }
  if (storedOriginalPhotosJson != null) {
    try {
      final decoded = jsonDecode(
        storedOriginalPhotosJson,
      );

      if (decoded is Map) {
        decoded.forEach((key, value) {
          if (key is String &&
              value is String) {
            livePhotoOriginalPhotos[key] =
                value;
          }
        });
      }
    } catch (error) {
      debugPrint(
        '⚠️ Live Photo 原始照片關聯資料讀取失敗：'
        '$error',
      );
    }
  }
  if (storedAssetsJson != null) {
    try {
      final decoded = jsonDecode(
        storedAssetsJson,
      );

      if (decoded is Map) {
        decoded.forEach((key, value) {
          if (key is String && value is String) {
            livePhotoAssetIdentifiers[key] =
                value;
          }
        });
      }
    } catch (error) {
      debugPrint(
        '⚠️ Live Photo assetIdentifier '
        '讀取失敗：$error',
      );
    }
  }

  // ------------------------------------------------------------
  // 只保留：
  // 1. Photo 還存在
  // 2. MOV 還存在
  // ------------------------------------------------------------

  final validPhotoPaths = {
    ...validCaptured,
    ...validSaved,
  };

  livePhotoVideos.removeWhere(
    (photoPath, videoPath) =>
        !validPhotoPaths.contains(photoPath) ||
        !File(videoPath).existsSync(),
  );

  livePhotoAssetIdentifiers.removeWhere(
    (photoPath, assetIdentifier) =>
        !livePhotoVideos.containsKey(photoPath),
  );
  livePhotoOriginalPhotos.removeWhere(
    (photoPath, originalPhotoPath) =>
        !livePhotoVideos.containsKey(photoPath) ||
        !File(originalPhotoPath).existsSync(),
  );
  if (!mounted) return;

  setState(() {
    _capturedImages
      ..clear()
      ..addAll(validCaptured);

    _savedImages
      ..clear()
      ..addAll(validSaved);

    _livePhotoVideos
      ..clear()
      ..addAll(livePhotoVideos);

    _livePhotoAssetIdentifiers
      ..clear()
      ..addAll(
        livePhotoAssetIdentifiers,
      );
      _livePhotoOriginalPhotos
        ..clear()
        ..addAll(
          livePhotoOriginalPhotos,
        );
  });

  // 同步清理已經不存在的 Live Photo 關聯
  await _persistImageLists();
}

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _captureTimer?.cancel();
    _aiTipTimer?.cancel();
    _focusTimer?.cancel();
    _longPressActivationTimer?.cancel();
    _metricsSubscription?.cancel();
    _accelerometerSubscription?.cancel();
    _videoPlayerController?.dispose();
    _cameraAdapter.dispose();
    _promptController.dispose();
    _recordedVideoPreviewController?.dispose();
    _recordedVideoPreviewController = null;
    super.dispose();
  }

  void _showAiTip(String message) {
    _aiTipTimer?.cancel();
    setState(() {
      _aiTipMessage = message;
    });
    _aiTipTimer = Timer(const Duration(seconds: 3), () {
      if (mounted) {
        setState(() {
          _aiTipMessage = null;
        });
      }
    });
  }

 void _handleFocusTap(Offset localPosition, Size size) {
  if (_isAeAfLocked || size.width <= 0 || size.height <= 0) return;

  final uiPoint = Offset(
    (localPosition.dx / size.width).clamp(0.08, 0.92),
    (localPosition.dy / size.height).clamp(0.08, 0.92),
  );

  setState(() {
    _focusPoint = uiPoint;
    _isFocusVisible = true;
    _exposureGestureArmed = true;
    _isLongPressActive = false;
  });

  // AVFoundation 的 focusPointOfInterest 座標
  final cameraPoint = Offset(
    uiPoint.dx,
    1.0 - uiPoint.dy,
  );

  unawaited(
    () async {
      try {
        await _cameraAdapter.setFocusPoint(
          cameraPoint.dx,
          cameraPoint.dy,
        );

        debugPrint(
          '🎯 Focus request success: '
          'UI=(${uiPoint.dx}, ${uiPoint.dy}) '
          'Camera=(${cameraPoint.dx}, ${cameraPoint.dy})',
        );
      } catch (e, stackTrace) {
        debugPrint('❌ Focus request failed: $e');
        debugPrint('$stackTrace');
      }
    }(),
  );

  _focusTimer?.cancel();
  _focusTimer = Timer(const Duration(seconds: 2), () {
    if (mounted && !_isAeAfLocked) {
      setState(() => _isFocusVisible = false);
    }
  });

  _showAiTip('◎ 已對焦');
}

  void _handleLongPressStart(LongPressStartDetails details) {
    final renderObject = _previewKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox) return;

    final localPosition = renderObject.globalToLocal(details.globalPosition);
    final point = _focusPoint;
    final focusCenter = point == null
        ? null
        : Offset(
            point.dx * renderObject.size.width,
            point.dy * renderObject.size.height,
          );
    final isOutsideFocusFrame =
        focusCenter == null || (localPosition - focusCenter).distance > 42;

    _longPressActivationTimer?.cancel();
    _longPressActivationTimer = Timer(const Duration(milliseconds: 450), () {
      if (!mounted) return;
      if (_exposureGestureArmed && isOutsideFocusFrame) {
        setState(() {
          _exposureGestureActive = true;
          _longPressStartExposure = _exposureValue;
        });
      } else {
        _exposureGestureArmed = false;
        _toggleAeAfLock();
      }
    });
    if (_exposureGestureArmed && isOutsideFocusFrame) {
      return;
    }
  }

  void _handleLongPressMove(LongPressMoveUpdateDetails details) {
    if (!_exposureGestureActive) return;

    final verticalDelta = details.offsetFromOrigin.dy;
    if (verticalDelta.abs() < 14) return;

    final nextExposure = (_longPressStartExposure - verticalDelta * 0.012)
        .clamp(-2.0, 2.0);
    setState(() {
      _isLongPressActive = true;
      _exposureValue = nextExposure;
    });
    unawaited(_cameraAdapter.setExposure(nextExposure));
  }

  void _handleLongPressEnd(LongPressEndDetails details) {
    _longPressActivationTimer?.cancel();
    if (mounted) {
      setState(() {
        _isLongPressActive = false;
        _exposureGestureActive = false;
      });
    }
  }

  void _toggleAeAfLock() {
    _focusTimer?.cancel();
    setState(() {
      _isAeAfLocked = !_isAeAfLocked;
      _focusPoint ??= const Offset(0.5, 0.5);
      _isFocusVisible = true;
    });
    unawaited(_cameraAdapter.setFocusLocked(_isAeAfLocked));
    _showAiTip(_isAeAfLocked ? '🔒 AE/AF Lock 已鎖定' : '🔓 AE/AF Lock 已解除');
  }

  Future<void> _startTimedCapture() async {
    if (_timerSeconds <= 0 || _currentMode == '影片') return;

    _captureTimer?.cancel();
    setState(() {
      _timerCountdown = _timerSeconds;
      _isCapturing = true;
    });

    _captureTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_timerCountdown <= 1) {
        timer.cancel();
        setState(() => _timerCountdown = 0);
        unawaited(_capturePhoto());
        _showAiTip('📷 計時拍攝完成');
        setState(() => _isCapturing = false);
        return;
      }

      setState(() => _timerCountdown--);
    });
  }



Future<String> _applyPhotoEffects(String sourcePath) async {
  _showEffectDebug('④-1 進入原生特效處理');

  final sourceFile = File(sourcePath);

  if (!await sourceFile.exists()) {
    throw Exception('找不到照片檔案');
  }

  try {
    // ====================================================
    // 1. 取得調色盤顏色
    // ====================================================

    final paletteColor = _paletteColor(_selectedPalette);

    final paletteOpacity =
        _selectedPalette == '原味'
            ? 0.0
            : (0.04 + (_paletteX * 0.05) + (_paletteY * 0.12))
                .clamp(0.04, 0.21);

    // Flutter Color → 0~1 RGB
    final paletteRed =
        paletteColor.r.toDouble() / 255.0;

    final paletteGreen =
        paletteColor.g.toDouble() / 255.0;

    final paletteBlue =
        paletteColor.b.toDouble() / 255.0;

    _showEffectDebug(
      '④-2 準備原生 Core Image\n'
      'Filter：$_filterMode\n'
      'Palette：$_selectedPalette\n'
      'Palette RGB：'
      '${paletteRed.toStringAsFixed(2)}, '
      '${paletteGreen.toStringAsFixed(2)}, '
      '${paletteBlue.toStringAsFixed(2)}\n'
      'Palette 強度：'
      '${paletteOpacity.toStringAsFixed(2)}\n'
      'Exposure：$_exposureValue\n'
      'Night：$_nightMode',
    );

    // ====================================================
    // 2. 呼叫 iOS 原生 Core Image
    // ====================================================

    final processedPath =
        await _cameraAdapter.applyPhotoEffects(
      sourcePath: sourcePath,

      filter: _filterMode,

      paletteRed: paletteRed,
      paletteGreen: paletteGreen,
      paletteBlue: paletteBlue,
      paletteOpacity: paletteOpacity,

      exposure: _exposureValue.toDouble(),

      nightMode: _nightMode,
    );

    // ====================================================
    // 3. 檢查 native 是否成功回傳
    // ====================================================

    if (processedPath == null ||
        processedPath.isEmpty) {
      throw Exception(
        'iOS Core Image 沒有回傳處理後照片路徑',
      );
    }

    final outputFile = File(processedPath);

    final exists = await outputFile.exists();

    if (!exists) {
      throw Exception(
        'iOS Core Image 輸出的照片不存在\n'
        '$processedPath',
      );
    }

    final size = await outputFile.length();

    if (size <= 0) {
      throw Exception(
        'iOS Core Image 輸出的照片大小為 0',
      );
    }

    // ====================================================
    // 4. 完成
    // ====================================================

    _showEffectDebug(
      '④-3 原生特效處理完成\n'
      'Filter：$_filterMode\n'
      'Palette：$_selectedPalette\n'
      'Exposure：$_exposureValue\n'
      'Night：$_nightMode',
    );

    _showEffectDebug(
      '④-4 已取得原生處理照片\n'
      '檔案：OK\n'
      '大小：$size bytes',
    );

    _showEffectDebug(
      '④-5 特效照片已輸出\n'
      'Filter：$_filterMode\n'
      'Palette：$_selectedPalette\n'
      'Exposure：$_exposureValue\n'
      'Night：$_nightMode\n'
      '檔案：OK\n'
      '大小：$size bytes',
    );

    return processedPath;
  } catch (error, stackTrace) {
    debugPrint(
      '❌ Native photo effect failed: $error',
    );

    debugPrint(
      '$stackTrace',
    );

    _showEffectDebug(
      '❌ 原生特效處理失敗\n'
      '$error',
    );

    rethrow;
  }
}

void _showEffectDebug(String message) {
  if (!mounted) return;

  setState(() {
    _effectDebugMessage = message;
  });

  debugPrint('🎨 EFFECT DEBUG: $message');
}
Future<void> _capturePhoto() async {
  try {
    String effectFlow = '① 開始拍照';

    _showEffectDebug(effectFlow);
    await Future<void>.delayed(
      const Duration(milliseconds: 150),
    );

    final liveCapture = _livePhotoEnabled
        ? await _cameraAdapter.captureLivePhoto()
        : null;

    effectFlow += '\n② 已取得拍照結果';
    _showEffectDebug(effectFlow);
    await Future<void>.delayed(
      const Duration(milliseconds: 150),
    );

    final originalPath =
        liveCapture?.photoPath ??
        await _cameraAdapter.capturePhoto();

    effectFlow += '\n③ 原始照片取得';
    _showEffectDebug(effectFlow);
    await Future<void>.delayed(
      const Duration(milliseconds: 150),
    );

    // ====================================================
    // 原始照片檢查
    // ====================================================
    debugPrint('📸 [1] 原始照片：$originalPath');

    final originalFile = File(originalPath);

    if (!await originalFile.exists()) {
      debugPrint('❌ [1] 原始照片不存在');
      throw Exception('原始照片不存在');
    }

    debugPrint(
      '📸 [1] 原始照片大小：'
      '${await originalFile.length()} bytes',
    );

    // ====================================================
    // 套用照片特效
    // ====================================================
    effectFlow += '\n④ 開始套用特效';
    _showEffectDebug(effectFlow);

    final path = await _applyPhotoEffects(
      originalPath,
    );

    debugPrint('📸 [2] 特效照片：$path');

    final processedFile = File(path);

    if (!await processedFile.exists()) {
      debugPrint('❌ [2] 特效照片不存在');
      throw Exception('特效照片不存在');
    }

    final processedSize =
        await processedFile.length();

    debugPrint(
      '📸 [3] 特效照片大小：'
      '$processedSize bytes',
    );

    effectFlow +=
        '\n⑤ 特效處理完成'
        '\nFilter：$_filterMode'
        '\nPalette：$_selectedPalette'
        '\nExposure：$_exposureValue'
        '\nNight：$_nightMode';

    _showEffectDebug(effectFlow);

    await Future<void>.delayed(
      const Duration(milliseconds: 300),
    );

    String? processedVideoPath;

    // ====================================================
    // Live Photo 影片
    //
    // Apple 照片匯出先使用原始 MOV。
    // 不重新編碼，避免破壞 Live Photo 配對資訊。
    // ====================================================
    if (liveCapture != null) {
      processedVideoPath =
          liveCapture.videoPath;
    }

    if (!mounted) return;

    effectFlow +=
        '\n⑥ 準備加入 AI 精選預覽';

    _showEffectDebug(effectFlow);

    await Future<void>.delayed(
      const Duration(milliseconds: 150),
    );

    setState(() {
    _capturedImages.add(path);

    if (liveCapture != null &&
        processedVideoPath != null) {
      // App 預覽使用的照片 → path
      _livePhotoVideos[path] =
          processedVideoPath;

      // 保留原本的 assetIdentifier
      _livePhotoAssetIdentifiers[path] =
          liveCapture.assetIdentifier;

      // 最重要：
      // 保存原始 Live Photo JPG
      // 最後匯出 Apple 照片時使用
      _livePhotoOriginalPhotos[path] =
          originalPath;
    }

    _isCapturing = false;
    _captureAnimation = true;
  });

    effectFlow += '\n⑦ 已加入特效照片';

    _showEffectDebug(effectFlow);

    Timer(
      const Duration(milliseconds: 550),
      () {
        if (mounted) {
          setState(
            () => _captureAnimation = false,
          );
        }
      },
    );

    await _persistImageLists();

    _showAiTip('📷 拍攝完成');
  } catch (error, stackTrace) {
    debugPrint('❌ 拍照失敗：$error');
    debugPrint('$stackTrace');

    if (!mounted) return;

    setState(
      () => _isCapturing = false,
    );

    _showEffectDebug(
      '❌ 拍照流程失敗\n$error',
    );

    _showAiTip('⚠️ 拍攝失敗：$error');
  }
}


  void _changeModeByVelocity(double? primaryVelocity) {
    // 錄影、上傳影片、濾鏡、調色盤開啟時
    // 禁止左右滑動切換模式
    if (_isRecording ||
        _activeUploadedVideo != null ||
        _activeBottomAdjustment != null) {
      return;
    }

    final int currentIndex = _modes.indexOf(_currentMode);

    if (primaryVelocity == null) return;

    if (primaryVelocity < 0) {
      if (currentIndex < _modes.length - 1) {
        setState(() {
          _currentMode = _modes[currentIndex + 1];
          _isTopMenuExpanded = false;
        });

        _showAiTip('✨ AI 已自動切換至 [$_currentMode] 模式');
      }
    } else if (primaryVelocity > 0) {
      if (currentIndex > 0) {
        setState(() {
          _currentMode = _modes[currentIndex - 1];
          _isTopMenuExpanded = false;
        });

        _showAiTip('✨ AI 已自動切換至 [$_currentMode] 模式');
      }
    }
  }

  void _handlePreviewScaleStart(ScaleStartDetails details) {
    _baseZoom = _zoomLevel;
    _gestureDelta = Offset.zero;
    _exposureGestureActive = _exposureGestureArmed;
    _longPressStartExposure = _exposureValue;
  }

  void _handlePreviewScaleUpdate(ScaleUpdateDetails details) {
    _gestureDelta += details.focalPointDelta;

    if (_exposureGestureActive &&
        _gestureDelta.dy.abs() > _gestureDelta.dx.abs()) {
      final nextExposure = (_longPressStartExposure - _gestureDelta.dy * 0.012)
          .clamp(-2.0, 2.0);
      setState(() => _exposureValue = nextExposure);
      unawaited(_cameraAdapter.setExposure(nextExposure));
      return;
    }

    if ((details.scale - 1).abs() > 0.01) {
      final nextZoom = (_baseZoom * details.scale).clamp(1.0, 5.0);
      if (_zoomLevel != nextZoom) {
        setState(() => _zoomLevel = nextZoom);
        unawaited(_cameraAdapter.setZoom(nextZoom));
      }
    }
  }

  void _handlePreviewScaleEnd(ScaleEndDetails details) {
    if (!_exposureGestureActive &&
        _gestureDelta.dx.abs() > 48 &&
        _gestureDelta.dx.abs() > _gestureDelta.dy.abs() * 1.2) {
      _changeModeByVelocity(_gestureDelta.dx > 0 ? 1000 : -1000);
    }
    _exposureGestureActive = false;
    _exposureGestureArmed = false;
    _gestureDelta = Offset.zero;
  }

  Future<void> _initializeVideoPlayer(String videoPath) async {
    final oldController = _videoPlayerController;
    _videoPlayerController = null;
    await oldController?.dispose();

    if (mounted) {
      setState(() {
        _videoLoadError = null;
        _videoProgress = 0.0;
        _isVideoPlaying = false;
      });
    }

    final file = File(videoPath);
    debugPrint('========== VIDEO DEBUG ==========');
    debugPrint('📁 path: $videoPath');
    debugPrint('📦 exists: ${await file.exists()}');
    if (await file.exists()) {
      debugPrint('📏 size: ${await file.length()} bytes');
    }

    final controller = WinVideoPlayerController.file(file);
    _videoPlayerController = controller;

    try {
      debugPrint('🎬 BEFORE initialize');
      await controller.initialize();
      debugPrint('🎬 AFTER initialize');

      if (!mounted) {
        await controller.dispose();
        return;
      }

      if (!controller.value.isInitialized) {
        throw StateError(controller.value.errorDescription ?? '影片無法初始化');
      }

      await controller.setLooping(true);

      controller.addListener(() {
        if (!mounted || _videoPlayerController != controller) return;

        final value = controller.value;

        if (!value.isInitialized) return;

        final durationMs = value.duration.inMilliseconds;

        final progress = durationMs > 0
            ? (value.position.inMilliseconds / durationMs).clamp(0.0, 1.0)
            : 0.0;

        // 避免影片播放時每一幀都觸發不必要的 setState
        if ((_videoProgress - progress).abs() < 0.01 &&
            _isVideoPlaying == value.isPlaying) {
          return;
        }

        setState(() {
          _videoProgress = progress;
          _isVideoPlaying = value.isPlaying;
        });
      });

      await controller.play();

      if (!mounted) return;
      setState(() {
        _videoLoadError = null;
        _isVideoPlaying = controller.value.isPlaying;
        _videoProgress = 0.0;
      });

      debugPrint('▶️ VIDEO PLAYING');
      debugPrint('⏱️ duration: ${controller.value.duration}');
      debugPrint('📐 aspectRatio: ${controller.value.aspectRatio}');
      debugPrint('📺 size: ${controller.value.size}');
      debugPrint('▶️ isPlaying: ${controller.value.isPlaying}');
      debugPrint('❌ error: ${controller.value.errorDescription}');
    } catch (e, stackTrace) {
      debugPrint('❌ VIDEO INITIALIZATION FAILED: $e');
      debugPrint('$stackTrace');

      await controller.dispose();
      if (_videoPlayerController == controller) {
        _videoPlayerController = null;
      }

      if (!mounted) return;
      setState(() {
        _videoLoadError = e.toString();
        _isVideoPlaying = false;
        _videoProgress = 0.0;
      });
      rethrow;
    }
  }

  Future<void> _handleUploadVideo() async {
    if (_isCapturing) return;

    try {
      final file = await fp.FilePicker.pickFile(type: fp.FileType.video);

      if (file == null) return;

      final path = file.path;
      if (path == null || path.isEmpty) {
        _showAiTip('⚠️ 無法取得影片路徑');
        return;
      }

      if (!mounted) return;

      _showAiTip('📤 正在載入影片...');
      setState(() {
        _activeUploadedVideo = path;
        _isTopMenuExpanded = false;
        _videoProgress = 0.0;
        _isVideoPlaying = false;
        _videoLoadError = null;
      });

      try {
        await _initializeVideoPlayer(path);

        if (mounted) {
          _showAiTip('📤 影片已匯入！按下快門即可讓 AI 分析最佳瞬間');
        }
      } catch (e) {
        debugPrint('Upload video initialization failed: $e');
        if (mounted) {
          _showAiTip('⚠️ 影片無法播放，請確認 Windows 可正常播放此 MP4');
        }
      }
    } catch (e, stackTrace) {
      debugPrint('❌ Upload video failed: $e');
      debugPrint('$stackTrace');

      if (mounted) {
        setState(() {
          _activeUploadedVideo = null;
          _videoPlayerController = null;
          _videoLoadError = e.toString();
          _isVideoPlaying = false;
          _videoProgress = 0.0;
        });
        _showAiTip('⚠️ 影片匯入失敗：$e');
      }
    }
  }

  Future<String?> _saveCandidateImage(String sourcePath) async {
    try {
      final sourceFile = File(sourcePath);

      // ============================================================
      // ① 確認來源檔案存在
      // ============================================================
      final sourceExists = await sourceFile.exists();

      debugPrint('📷 SAVE SOURCE: $sourcePath');

      debugPrint('📷 SOURCE EXISTS: $sourceExists');

      if (!sourceExists) {
        debugPrint('❌ Candidate image does not exist');

        return null;
      }

      // ============================================================
      // ② 使用 ai_frames 的上一層作為 AI 工作資料夾
      // ============================================================
      final aiDirectory = sourceFile.parent.parent;

      debugPrint('📁 AI DIRECTORY: ${aiDirectory.path}');

      // ============================================================
      // ③ 建立永久相簿 captures
      // ============================================================
      final capturesDirectory = Directory(
        '${aiDirectory.path}'
        '${Platform.pathSeparator}'
        'captures',
      );

      if (!await capturesDirectory.exists()) {
        await capturesDirectory.create(recursive: true);

        debugPrint(
          '📁 Created captures directory: '
          '${capturesDirectory.path}',
        );
      }

      // ============================================================
      // ④ 建立唯一檔名
      // ============================================================
      final now = DateTime.now();

      final timestamp =
          '${now.year.toString().padLeft(4, '0')}'
          '${now.month.toString().padLeft(2, '0')}'
          '${now.day.toString().padLeft(2, '0')}_'
          '${now.hour.toString().padLeft(2, '0')}'
          '${now.minute.toString().padLeft(2, '0')}'
          '${now.second.toString().padLeft(2, '0')}_'
          '${now.microsecond.toString().padLeft(6, '0')}';

      var newPath =
          '${capturesDirectory.path}'
          '${Platform.pathSeparator}'
          'AI_$timestamp.jpg';

      var destinationFile = File(newPath);

      // ============================================================
      // ⑤ 防止檔名重複
      // ============================================================
      int counter = 1;

      while (await destinationFile.exists()) {
        newPath =
            '${capturesDirectory.path}'
            '${Platform.pathSeparator}'
            'AI_${timestamp}_$counter.jpg';

        destinationFile = File(newPath);

        counter++;
      }

      // ============================================================
      // ⑥ 複製照片
      // ============================================================
      debugPrint('📋 COPY FROM: ${sourceFile.path}');

      debugPrint('📋 COPY TO: ${destinationFile.path}');

      final savedFile = await sourceFile.copy(destinationFile.path);

      // ============================================================
      // ⑦ 再次確認保存成功
      // ============================================================
      if (!await savedFile.exists()) {
        debugPrint('❌ Saved file does not exist after copy');

        return null;
      }

      debugPrint(
        '✅ Candidate image permanently saved: '
        '${savedFile.path}',
      );

      return savedFile.path;
    } catch (e, stackTrace) {
      debugPrint('❌ Failed to save candidate image: $e');

      debugPrint('$stackTrace');

      return null;
    }
  }

  Future<void> _persistImageLists() async {
  final prefs =
      await SharedPreferences.getInstance();

  await prefs.setStringList(
    'captured_images',
    List<String>.from(
      _capturedImages,
    ),
  );

  await prefs.setStringList(
    'saved_images',
    List<String>.from(
      _savedImages,
    ),
  );

  // ------------------------------------------------------------
  // Live Photo Photo ↔ MOV 關聯
  // ------------------------------------------------------------

  await prefs.setString(
    'live_photo_videos',
    jsonEncode(
      _livePhotoVideos,
    ),
  );


  await prefs.setString(
    'live_photo_original_photos',
    jsonEncode(
      _livePhotoOriginalPhotos,
    ),
  );

  await prefs.setString(
    'live_photo_asset_identifiers',
    jsonEncode(
      _livePhotoAssetIdentifiers,
    ),
  );

  await prefs.setString(
    'live_photo_original_photos',
    jsonEncode(
      _livePhotoOriginalPhotos,
    ),
  );

}

Future<void> _deleteLivePhotoResources(
  String photoPath,
) async {
  final videoPath =
      _livePhotoVideos.remove(
    photoPath,
  );

  _livePhotoAssetIdentifiers.remove(
    photoPath,
  );
  _livePhotoOriginalPhotos.remove(
    photoPath,
  );
  if (videoPath == null) {
    return;
  }

  try {
    final videoFile =
        File(videoPath);

    if (await videoFile.exists()) {
      await videoFile.delete();

      debugPrint(
        '🗑️ Deleted Live Photo MOV: '
        '$videoPath',
      );
    }
  } catch (error) {
    debugPrint(
      '⚠️ Live Photo MOV 刪除失敗：$error',
    );
  }
}

Future<bool> _saveImageToApplePhotos(String sourcePath) async {
  final file = File(sourcePath);

  try {
    if (!await file.exists()) {
      debugPrint(
        'Image does not exist: $sourcePath',
      );
      return false;
    }

    // ------------------------------------------------------------
    // Live Photo
    // ------------------------------------------------------------

    final livePhotoVideo =
        _livePhotoVideos[sourcePath];

    if (livePhotoVideo != null) {
      final videoFile =
          File(livePhotoVideo);

      if (!await videoFile.exists()) {
        debugPrint(
          '❌ Live Photo video does not exist: '
          '$livePhotoVideo',
        );
        return false;
      }

      final originalPhotoPath =
          _livePhotoOriginalPhotos[sourcePath] ??
          sourcePath;

      final originalPhotoFile =
          File(originalPhotoPath);

      if (!await originalPhotoFile.exists()) {
        debugPrint(
          '❌ Live Photo 原始照片不存在：'
          '$originalPhotoPath',
        );

        if (mounted) {
          _showAiTip(
            '⚠️ Live Photo 原始照片不存在',
          );
        }

        return false;
      }

      final success =
          await _cameraAdapter.saveLivePhoto(
        photoPath: originalPhotoPath,
        videoPath: livePhotoVideo,
      );

      if (!success) {
        debugPrint(
          '❌ Live Photo 保存失敗',
        );

        if (mounted) {
          _showAiTip(
            '⚠️ Live Photo 保存失敗',
          );
        }

        return false;
      }

      debugPrint(
        '✅ Live Photo saved to Apple Photos',
      );

      if (mounted) {
        _showAiTip(
          '✅ Live Photo 已保存到 Apple 照片',
        );
      }

      return true;
    }

    // ------------------------------------------------------------
    // 一般照片
    // ------------------------------------------------------------

    await Gal.putImage(sourcePath);

    debugPrint(
      '✅ Image saved to Apple Photos: $sourcePath',
    );

    if (mounted) {
      _showAiTip(
        '✅ 已保存到 Apple 照片',
      );
    }

    return true;
  } catch (error, stackTrace) {
    debugPrint(
      '❌ Failed to save to Apple Photos: $error',
    );
    debugPrint('$stackTrace');

    if (mounted) {
      _showAiTip(
        '⚠️ 保存到 Apple 照片失敗',
      );
    }

    return false;
  }
}


Future<bool> _saveCandidateToGallery(String sourcePath) async {
  final file = File(sourcePath);

  try {
    if (!await file.exists()) {
      debugPrint('Candidate image does not exist: $sourcePath');
      return false;
    }
  } catch (error, stackTrace) {
    debugPrint('Failed to check image: $error');
    debugPrint('$stackTrace');
    return false;
  }

  if (!mounted) return false;

  setState(() {
    _capturedImages.remove(sourcePath);

    if (!_savedImages.contains(sourcePath)) {
      _savedImages.add(sourcePath);
    }
  });

  try {
    await _persistImageLists();
    debugPrint('Image saved to App gallery: $sourcePath');
    return true;
  } catch (error, stackTrace) {
    debugPrint('Failed to persist image lists: $error');
    debugPrint('$stackTrace');

    if (mounted) {
      _showAiTip('⚠️ 圖片保存失敗');
    }

    return false;
  }
}

bool _isLivePhoto(String photoPath) {
  final videoPath = _livePhotoVideos[photoPath];

  if (videoPath == null || videoPath.isEmpty) {
    return false;
  }

  return File(videoPath).existsSync();
}

  Future<void> _showLivePhotoPreview(
  String photoPath, {
  bool showSavedImages = false,
}) async {
  final videoPath =
      _livePhotoVideos[photoPath];

  // ------------------------------------------------------------
  // 找不到 MOV
  // → 回到一般照片檢視
  // ------------------------------------------------------------

  if (videoPath == null ||
      !await File(videoPath).exists()) {
    final galleryImages = showSavedImages
        ? _savedImages
        : _capturedImages;

    final index =
        galleryImages.indexOf(photoPath);

    if (index >= 0) {
      _showEnlargedGallery(
        index,
        showSavedImages:
            showSavedImages,
      );
    }

    return;
  }

  final controller =
      vp.VideoPlayerController.file(
    File(videoPath),
  );

  try {
    await controller.initialize();
    await controller.setLooping(true);
    await controller.play();

    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (
            context,
            setDialogState,
          ) {
            return Dialog(
              backgroundColor: Colors.black,
              insetPadding:
                  const EdgeInsets.all(18),
              child: Column(
                mainAxisSize:
                    MainAxisSize.min,
                children: [
                  // ------------------------------------------------
                  // 原況影片
                  // ------------------------------------------------

                  GestureDetector(
                    behavior: HitTestBehavior.opaque,

                    onLongPressStart: (_) async {
                      await controller.seekTo(Duration.zero);
                      await controller.play();
                    },

                    onLongPressEnd: (_) async {
                      await controller.pause();

                      if (dialogContext.mounted) {
                        Navigator.of(dialogContext).pop();
                      }
                    },

                    child: AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: vp.VideoPlayer(controller),
                    ),
                  ),

                  Padding(
                    padding:
                        const EdgeInsets.fromLTRB(
                      14,
                      10,
                      14,
                      14,
                    ),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            '原況照片',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight:
                                  FontWeight.bold,
                            ),
                          ),
                        ),

                        // ------------------------------------------------
                        // 關閉
                        // ------------------------------------------------

                        IconButton(
                          onPressed: () {
                            Navigator.pop(
                              dialogContext,
                            );
                          },
                          icon: const Icon(
                            Icons.close,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),

                 
                ],
              ),
            );
          },
        );
      },
    );
  } finally {
    await controller.dispose();
  }
}

  Future<void> _showImageEditor(String sourcePath) async {
    final sourceFile = File(sourcePath);
    if (!await sourceFile.exists()) {
      _showAiTip('⚠️ 找不到要編輯的照片');
      return;
    }

    final original = img.decodeImage(await sourceFile.readAsBytes());
    if (original == null || !mounted) {
      _showAiTip('⚠️ 照片格式無法編輯');
      return;
    }

    var brightness = 0.0;
    var rotation = 0;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            final preview = img.adjustColor(
              img.copyRotate(original, angle: rotation),
              brightness: brightness,
            );
            return AlertDialog(
              backgroundColor: const Color(0xFF171717),
              title: const Text('照片調整', style: TextStyle(color: Colors.white)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      height: 260,
                      child: Image.memory(
                        Uint8List.fromList(img.encodeJpg(preview, quality: 90)),
                        fit: BoxFit.contain,
                      ),
                    ),
                    Row(
                      children: [
                        const Icon(Icons.brightness_6, color: Colors.white70),
                        Expanded(
                          child: Slider(
                            value: brightness,
                            min: -80,
                            max: 80,
                            divisions: 32,
                            activeColor: Colors.yellowAccent,
                            onChanged: (value) =>
                                setDialogState(() => brightness = value),
                          ),
                        ),
                      ],
                    ),
                    Row(
                      children: [
                        const Text(
                          '旋轉',
                          style: TextStyle(color: Colors.white70),
                        ),
                        const Spacer(),
                        IconButton(
                          onPressed: () => setDialogState(
                            () => rotation = (rotation + 90) % 360,
                          ),
                          icon: const Icon(
                            Icons.rotate_right,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: const Text('取消'),
                ),
                FilledButton(
                  onPressed: () async {
                    final edited = img.adjustColor(
                      img.copyRotate(original, angle: rotation),
                      brightness: brightness,
                    );
                    final editedPath =
                        '${sourceFile.parent.path}${Platform.pathSeparator}'
                        'edited_${DateTime.now().microsecondsSinceEpoch}.jpg';
                    await File(editedPath).writeAsBytes(img.encodeJpg(edited));
                    final capturedIndex = _capturedImages.indexOf(sourcePath);
                    final savedIndex = _savedImages.indexOf(sourcePath);
                    if (capturedIndex >= 0) {
                      _capturedImages[capturedIndex] = editedPath;
                    }
                    if (savedIndex >= 0) {
                      _savedImages[savedIndex] = editedPath;
                    }
                    final liveVideo = _livePhotoVideos.remove(sourcePath);
                    if (liveVideo != null) {
                      _livePhotoVideos[editedPath] = liveVideo;
                    }
                    await _persistImageLists();
                    
                    if (mounted) setState(() {});
                    if (dialogContext.mounted) Navigator.pop(dialogContext);
                    _showAiTip('✅ 照片調整已保存');
                  },
                  child: const Text('保存'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _exitUploadedVideo() async {
    await _videoPlayerController?.pause();
    await _videoPlayerController?.dispose();
    _videoPlayerController = null;
    if (!mounted) return;
    setState(() {
      _activeUploadedVideo = null;
      _isVideoPlaying = false;
      _videoProgress = 0.0;
      _videoLoadError = null;
    });
    _showAiTip('↩️ 已退出影片預覽模式');
  }

  Future<void> _analyzeUploadedVideo(
    String videoPath,
    Duration capturePosition,
  ) async {
    if (_isCapturing || !mounted) {
      return;
    }

    // ============================================================
    // 防止同時執行兩次 AI
    // ============================================================

    setState(() {
      _isCapturing = true;
    });

    _showAiTip(
      '🤖 AI 正在分析 ${_formatDuration(capturePosition.inSeconds)} 附近的影片...',
    );

    try {
      // ============================================================
      // AI 偏好設定
      // ============================================================

      final preference = _preferenceModel.copyWith(
        compositionWeight: _aiWeights['構圖美感'],
        lightingWeight: _aiWeights['光影表現'],
        expressionWeight: _aiWeights['人物表情'],
        colorWeight: _aiWeights['色彩氛圍'],
      );

      // ============================================================
      // AI 分析
      // ============================================================

      final result = await _videoSmartCaptureService.analyze(
        videoPath: videoPath,
        preference: preference,

        // ★ 這次真正重要的參數
        startPosition: capturePosition,

        aiBurstEnabled: _aiBurstEnabled,

        aiBurstSeconds: _aiBurstSeconds,

        aiBurstCount: _aiBurstCount,

        passingScore: _passingScore,
      );

      if (!mounted) {
        return;
      }

      // ============================================================
      // AI 分析完成
      // ============================================================

      setState(() {
        _isCapturing = false;
      });

      // ============================================================
      // 沒有結果
      // ============================================================

      if (!result.hasResult) {
        _showAiTip('⚠️ 這個時間區段沒有找到可用的最佳畫面');

        return;
      }

      // ============================================================
      // 取得 AI 選出的照片
      // ============================================================

      final selectedPaths = <String>[];

      for (final frame in result.selectedFrames) {
        final file = frame.file;

        if (!await file.exists()) {
          debugPrint(
            '⚠️ AI selected frame does not exist: '
            '${file.path}',
          );

          continue;
        }

        final permanentPath = await _saveCandidateImage(file.path);

        if (permanentPath == null) {
          debugPrint(
            '⚠️ AI frame 永久保存失敗: '
            '${file.path}',
          );
          continue;
        }

        selectedPaths.add(permanentPath);
      }

      // ============================================================
      // 沒有可用照片
      // ============================================================

      if (selectedPaths.isEmpty) {
        _showAiTip('⚠️ AI 找到了結果，但沒有可用的照片檔案');

        return;
      }

      // ============================================================
      // 加入候選照片
      //
      // 注意：
      // _capturedImages 只存實際圖片路徑
      // ============================================================

      setState(() {
        _capturedImages.addAll(selectedPaths);
      });
      await _persistImageLists();
      await _videoSmartCaptureService.cleanupFrames(videoPath: videoPath);
      // ============================================================
      // ★ 關鍵：
      // 記錄下一次 AI 分析應該從哪裡開始
      //
      // 例如：
      //
      // 第一次：
      // 0～3 秒
      //
      // 下一次：
      // 從 3 秒開始
      //
      // 第二次：
      // 3～6 秒
      //
      // 下一次：
      // 從 6 秒開始
      // ============================================================

      final nextPosition = capturePosition + Duration(seconds: _aiBurstSeconds);

      final controller = _videoPlayerController;

      if (controller != null && controller.value.isInitialized) {
        final duration = controller.value.duration;

        // ----------------------------------------------------------
        // 不允許超過影片總長度
        // ----------------------------------------------------------

        _nextVideoCapturePosition = nextPosition > duration
            ? duration
            : nextPosition;
      } else {
        _nextVideoCapturePosition = nextPosition;
      }

      // ============================================================
      // 顯示結果
      // ============================================================

      final score = (result.bestScore!.total * 100).toStringAsFixed(0);

      _showAiTip(
        '✅ AI 智慧抓拍完成！'
        '選出 ${selectedPaths.length} 張最佳照片，'
        '最高分數 $score%，'
        '分析 ${result.analyzedFrameCount} 幀，'
        '場景變化 ${result.sceneChangeCount} 次',
      );
    } catch (e, stackTrace) {
      debugPrint('Video AI analysis failed: $e');

      debugPrint('$stackTrace');

      if (mounted) {
        setState(() {
          _isCapturing = false;
        });

        _showAiTip('⚠️ 影片 AI 分析失敗：$e');
      }
    }
  }

  Future<void> _handleCaptureOrRecord() async {
    if (_isCapturing) return;

    // ============================================================
    // 上傳影片模式
    // ============================================================

    if (_activeUploadedVideo != null) {
      final videoController = _videoPlayerController;

      // ----------------------------------------------------------
      // Controller 尚未準備完成
      // ----------------------------------------------------------

      if (videoController == null || !videoController.value.isInitialized) {
        _showAiTip('⚠️ 影片尚未準備完成');
        return;
      }

      final videoValue = videoController.value;

      // ----------------------------------------------------------
      // 影片播放完成
      // ----------------------------------------------------------

      if (videoValue.isCompleted) {
        _showAiTip('⏹️ 影片已播放完成，請重新播放後再進行 AI 抓拍');
        return;
      }

      // ----------------------------------------------------------
      // 影片必須正在播放
      // ----------------------------------------------------------

      if (!videoValue.isPlaying) {
        _showAiTip('▶️ 請先播放影片，再進行 AI 抓拍');
        return;
      }

      // ----------------------------------------------------------
      // 取得目前影片位置
      // ----------------------------------------------------------

      final currentPosition = videoValue.position;

      // ----------------------------------------------------------
      // 決定這次 AI 分析的開始位置
      //
      // 第一次：
      // 直接使用目前播放位置
      //
      // 第二次之後：
      // 從上一次分析區段結束的位置開始
      // ----------------------------------------------------------

      final capturePosition = _nextVideoCapturePosition ?? currentPosition;

      // ----------------------------------------------------------
      // 如果目前播放位置已經超過下一個分析位置
      //
      // 代表使用者影片已經往前播放，
      // 這時直接使用目前播放位置比較合理。
      // ----------------------------------------------------------

      final actualCapturePosition = currentPosition > capturePosition
          ? currentPosition
          : capturePosition;

      // ----------------------------------------------------------
      // 執行 AI 分析
      // ----------------------------------------------------------

      await _analyzeUploadedVideo(_activeUploadedVideo!, actualCapturePosition);

      return;
    }

    // ============================================================
    // 一般影片錄影模式
    // ============================================================

    if (_currentMode == '影片') {
      // =========================
      // 停止錄影
      // =========================
      if (_isRecording) {
        _recordingTimer?.cancel();

        final recordedSeconds = _recordingSeconds;

        setState(() {
          _isRecording = false;
        });

        try {
          final videoPath =
              await _cameraAdapter.stopVideoRecording();

          debugPrint('🎬 原生錄影完成');
          debugPrint('📁 recorded video: $videoPath');

          final file = File(videoPath);
          final exists = await file.exists();

          debugPrint('📦 recorded file exists: $exists');

          if (!exists) {
            throw StateError('錄影完成，但找不到影片檔案');
          }

          debugPrint(
            '📏 recorded file size: ${await file.length()} bytes',
          );

          if (!mounted) return;

          if (!mounted) return;

            setState(() {
              _recordedVideos.insert(0, videoPath);
            });

            _showAiTip(
              '🎬 錄影完成 ${_formatDuration(recordedSeconds)}',
            );

          if (!mounted) return;

          _showAiTip(
            '🎬 錄影完成 ${_formatDuration(recordedSeconds)}',
          );
        } catch (e, stackTrace) {
          debugPrint('❌ 錄影停止/預覽失敗：$e');
          debugPrint('$stackTrace');

          if (mounted) {
            _showAiTip('❌ 錄影處理失敗：$e');
          }
        }

        return;
      }

      // =========================
      // 開始錄影
      // =========================
      setState(() {
        _isRecording = true;
        _recordingSeconds = 0;
      });

      try {
        await _cameraAdapter.startVideoRecording();

        _recordingTimer =
            Timer.periodic(const Duration(seconds: 1), (_) {
          if (!mounted || !_isRecording) {
            return;
          }

          setState(() {
            _recordingSeconds++;
          });
        });

        _showAiTip('🔴 開始錄影');
      } catch (e, stackTrace) {
        debugPrint('❌ 開始錄影失敗：$e');
        debugPrint('$stackTrace');

        if (mounted) {
          setState(() {
            _isRecording = false;
          });

          _showAiTip('❌ 無法開始錄影：$e');
        }
      }

      return;
    }

    // ============================================================
    // 一般拍照
    // ============================================================

    if (_currentMode == '拍照' || _currentMode == '物景') {
      if (_timerSeconds > 0) {
        await _startTimedCapture();
        return;
      }

      setState(() => _isCapturing = true);
      await _capturePhoto();
    }
  }

  // ============================================================
  // 調色盤
  // ============================================================

  static const List<String> _palettePresets = [
    '原味',
    '日系',
    '電影',
    '復古',
    '清透',
    '暖陽',
    '冷調',
  ];

  Color _paletteColor(String name) {
    switch (name) {
      case '日系':
        return const Color(0xFFE8C9B5);
      case '電影':
        return const Color(0xFF8D9A72);
      case '復古':
        return const Color(0xFFA77B5B);
      case '清透':
        return const Color(0xFFB9DDE5);
      case '暖陽':
        return const Color(0xFFE8B15C);
      case '冷調':
        return const Color(0xFF7194C4);
      default:
        return Colors.grey;
    }
  }

  Color? get _previewFilterOverlay {
    switch (_filterMode) {
      case '鮮明':
        return Colors.orange.withValues(alpha: 0.06);
      case '溫暖':
        return Colors.amber.withValues(alpha: 0.08);
      case '冷色':
        return Colors.blue.withValues(alpha: 0.08);
      case '復古':
        return Colors.brown.withValues(alpha: 0.10);
      default:
        return null;
    }
  }

  Color? get _previewPaletteOverlay {
    if (_selectedPalette == '原味') return null;

    final opacity = (0.04 + (_paletteX * 0.05) + (_paletteY * 0.12)).clamp(
      0.04,
      0.21,
    );
    return _paletteColor(_selectedPalette).withValues(alpha: opacity);
  }

  Widget _buildPreviewEffectOverlay() {
    final filterOverlay = _previewFilterOverlay;
    final paletteOverlay = _previewPaletteOverlay;
    final exposureOpacity = (_exposureValue.abs() * 0.12).clamp(0.0, 0.24);
    final exposureColor = _exposureValue >= 0
        ? Colors.white.withValues(alpha: exposureOpacity)
        : Colors.black.withValues(alpha: exposureOpacity);
    final nightOverlay = _nightMode
        ? Colors.indigo.withValues(alpha: 0.08)
        : null;

    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        clipBehavior: Clip.hardEdge,
        children: [
          if (filterOverlay != null) ColoredBox(color: filterOverlay),
          if (paletteOverlay != null) ColoredBox(color: paletteOverlay),
          if (exposureOpacity > 0) ColoredBox(color: exposureColor),
          if (nightOverlay != null) ColoredBox(color: nightOverlay),
        ],
      ),
    );
  }

  Widget _buildCameraPreview() {
    final controller = _cameraAdapter.controller;
    if (controller == null || !controller.value.isInitialized) {
      return Center(
        child: _cameraInitializing
            ? const CircularProgressIndicator(color: Colors.yellowAccent)
            : Text(
                _cameraError == null ? '相機尚未就緒' : '無法啟用相機\n$_cameraError',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white54, fontSize: 14),
              ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final previewAspectRatio = controller.value.aspectRatio;
        final width = constraints.maxWidth;
        return ClipRect(
          child: FittedBox(
            fit: BoxFit.cover,
            alignment: Alignment.center,
            child: SizedBox(
              width: width,
              height: width / previewAspectRatio,
              child: CameraPreview(controller),
            ),
          ),
        );
      },
    );
  }

  Widget _buildFocusOverlay() {
    final point = _focusPoint;
    if (!_isFocusVisible || point == null) return const SizedBox.shrink();

    final exposureProgress = ((_exposureValue + 2) / 4).clamp(0.0, 1.0);
    final focusFrame = Container(
      width: 72,
      height: 72,
      decoration: BoxDecoration(
        border: Border.all(
          color: _isAeAfLocked ? Colors.redAccent : Colors.yellowAccent,
          width: 1.5,
        ),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Align(
        alignment: Alignment.topRight,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 2),
          color: Colors.black45,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                _isAeAfLocked ? Icons.lock : Icons.center_focus_strong,
                color: _isAeAfLocked ? Colors.redAccent : Colors.yellowAccent,
                size: 14,
              ),
              if (_isAeAfLocked) ...[
                const SizedBox(width: 2),
                const Text(
                  'AE/AF',
                  style: TextStyle(
                    color: Colors.redAccent,
                    fontSize: 8,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );

    final exposureBar = Container(
      width: 8,
      height: 72,
      padding: const EdgeInsets.all(1),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        border: Border.all(color: Colors.white70, width: 0.8),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Align(
        alignment: Alignment.bottomCenter,
        child: FractionallySizedBox(
          heightFactor: exposureProgress,
          widthFactor: 1,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: _exposureValue >= 0
                  ? Colors.yellowAccent
                  : Colors.lightBlueAccent,
              borderRadius: BorderRadius.circular(3),
            ),
          ),
        ),
      ),
    );

    return Align(
      alignment: Alignment(point.dx * 2 - 1, point.dy * 2 - 1),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          focusFrame,
          if (_isLongPressActive || _exposureGestureArmed) ...[
            const SizedBox(width: 6),
            exposureBar,
          ],
        ],
      ),
    );
  }

  Widget _buildLevelOverlay() {
    if (!_levelEnabled) return const SizedBox.shrink();

    return IgnorePointer(
      child: Align(
        alignment: Alignment.center,
        child: Transform.rotate(
          angle: _levelAngle,
          child: SizedBox(
            width: 150,
            child: Row(
              children: [
                Expanded(
                  child: Container(height: 2, color: Colors.yellowAccent),
                ),
                Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black54,
                    border: Border.all(color: Colors.yellowAccent, width: 1.5),
                  ),
                ),
                Expanded(
                  child: Container(height: 2, color: Colors.yellowAccent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildProOverlay() {
    final metrics = _cameraMetrics;
    return IgnorePointer(
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (_histogramEnabled && metrics != null)
            Align(
              alignment: Alignment.topRight,
              child: Container(
                margin: const EdgeInsets.all(12),
                width: 150,
                height: 72,
                padding: const EdgeInsets.all(6),
                color: Colors.black.withValues(alpha: 0.55),
                child: CustomPaint(
                  painter: _HistogramPainter(metrics.histogram),
                ),
              ),
            ),
          if (_zebraEnabled &&
              metrics != null &&
              metrics.clippedHighlightRatio > 0.02)
            Align(
              alignment: Alignment.topLeft,
              child: Container(
                margin: const EdgeInsets.all(12),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                color: Colors.redAccent.withValues(alpha: 0.8),
                child: const Text(
                  'ZEBRA 高光溢出',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          if (_focusPeakingEnabled && _isFocusVisible)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                margin: const EdgeInsets.only(bottom: 12),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                color: Colors.black54,
                child: const Text(
                  'FOCUS PEAKING',
                  style: TextStyle(
                    color: Colors.greenAccent,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _showProControls() async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: const Color(0xFF171717),
      isScrollControlled: true,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheetState) => SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'PRO 控制',
                  style: TextStyle(
                    color: Colors.yellowAccent,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                _buildProSlider(
                  'ISO',
                  _isoValue,
                  50,
                  6400,
                  (value) {
                    setState(() => _isoValue = value);
                    unawaited(
                      _cameraAdapter.setManualExposure(
                        iso: value,
                        shutterSeconds: _shutterSeconds,
                      ),
                    );
                  },
                  setSheetState,
                  valueLabel: _isoValue.round().toString(),
                ),
                _buildProSlider(
                  '快門',
                  _shutterSeconds,
                  1 / 8000,
                  1 / 2,
                  (value) {
                    setState(() => _shutterSeconds = value);
                    unawaited(
                      _cameraAdapter.setManualExposure(
                        iso: _isoValue,
                        shutterSeconds: value,
                      ),
                    );
                  },
                  setSheetState,
                  valueLabel: _formatShutter(_shutterSeconds),
                ),
                _buildProSlider(
                  '手動對焦',
                  _manualFocus,
                  0,
                  1,
                  (value) {
                    setState(() => _manualFocus = value);
                    unawaited(_cameraAdapter.setManualFocus(value));
                  },
                  setSheetState,
                  valueLabel: '${(_manualFocus * 100).round()}%',
                ),
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    '白平衡 / Kelvin',
                    style: TextStyle(color: Colors.white),
                  ),
                  trailing: DropdownButton<String>(
                    value: _whiteBalance,
                    dropdownColor: const Color(0xFF292929),
                    style: const TextStyle(color: Colors.white),
                    items: ['自動', '日光', '陰天', '鎢絲燈', '自訂']
                        .map(
                          (value) => DropdownMenuItem(
                            value: value,
                            child: Text(value),
                          ),
                        )
                        .toList(),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() => _whiteBalance = value);
                      setSheetState(() {});
                    },
                  ),
                ),
                if (_whiteBalance == '自訂')
                  _buildProSlider(
                    'Kelvin',
                    _kelvin.toDouble(),
                    2000,
                    10000,
                    (value) {
                      setState(() => _kelvin = value.round());
                      unawaited(_cameraAdapter.setWhiteBalance(value));
                    },
                    setSheetState,
                    valueLabel: '${_kelvin}K',
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Histogram',
                    style: TextStyle(color: Colors.white),
                  ),
                  value: _histogramEnabled,
                  activeThumbColor: Colors.yellowAccent,
                  onChanged: (value) {
                    setState(() => _histogramEnabled = value);
                    setSheetState(() {});
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Focus Peaking',
                    style: TextStyle(color: Colors.white),
                  ),
                  value: _focusPeakingEnabled,
                  activeThumbColor: Colors.yellowAccent,
                  onChanged: (value) {
                    setState(() => _focusPeakingEnabled = value);
                    setSheetState(() {});
                  },
                ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: const Text(
                    'Zebra',
                    style: TextStyle(color: Colors.white),
                  ),
                  value: _zebraEnabled,
                  activeThumbColor: Colors.yellowAccent,
                  onChanged: (value) {
                    setState(() => _zebraEnabled = value);
                    setSheetState(() {});
                  },
                ),
              ],
            ),
          ),
        ),
      ),
    );
    if (mounted) {
      setState(() => _proModeEnabled = false);
    }
  }

  Widget _buildProSlider(
    String label,
    double value,
    double min,
    double max,
    ValueChanged<double> onChanged,
    StateSetter setSheetState, {
    required String valueLabel,
  }) {
    return Column(
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.white)),
            Text(
              valueLabel,
              style: const TextStyle(color: Colors.yellowAccent),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          activeColor: Colors.yellowAccent,
          onChanged: (next) {
            onChanged(next);
            setSheetState(() {});
          },
        ),
      ],
    );
  }

  String _formatShutter(double seconds) {
    if (seconds >= 1) return '${seconds.toStringAsFixed(1)}s';
    return '1/${(1 / seconds).round()}';
  }

  void _updatePalettePosition(Offset localPosition, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final x = (localPosition.dx / size.width).clamp(0.0, 1.0);
    final y = (localPosition.dy / size.height).clamp(0.0, 1.0);

    setState(() {
      _paletteX = x;
      _paletteY = y;
    });
  }

  void _openBottomAdjustment(String type) {
    setState(() {
      _activeBottomAdjustment = type;

      _isPaletteOpen = type == 'palette';
      _isPaletteEditing = false;

      _isExposureSliding = false;
      _isTopMenuExpanded = false;
    });
  }

  void _closeBottomAdjustment() {
    setState(() {
      _activeBottomAdjustment = null;
      _isPaletteOpen = false;
      _isPaletteEditing = false;
    });
  }

  Widget _buildPaletteAdjustmentContent() {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '調色盤',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),

        const SizedBox(height: 5),

        // ─────────────────────────
        // 調色盤預設
        // 原味 / 日系 / 電影 / 復古...
        // ─────────────────────────
        SizedBox(
          height: 32,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            itemCount: _palettePresets.length,
            separatorBuilder: (_, _) => const SizedBox(width: 6),
            itemBuilder: (context, index) {
              final palette = _palettePresets[index];
              final bool selected = _selectedPalette == palette;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,

                // 點一下即可選擇並進入可拖曳模式
                onTap: () {
                  setState(() {
                    _selectedPalette = palette;
                    _isPaletteOpen = true;
                    _isPaletteEditing = true;

                    // 每次切換預設，控制點回到中心
                    _paletteX = 0.5;
                    _paletteY = 0.5;
                  });

                  _showAiTip('🎨 已套用「$palette」，可直接拖曳原點調整');
                },

                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? Colors.white.withValues(alpha: 0.18)
                        : Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected ? Colors.yellowAccent : Colors.white24,
                      width: selected ? 1.2 : 0.7,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: _paletteColor(palette),
                        ),
                      ),

                      const SizedBox(width: 4),

                      Text(
                        palette,
                        style: TextStyle(
                          color: selected
                              ? Colors.yellowAccent
                              : Colors.white70,
                          fontSize: 10,
                          fontWeight: selected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 8),

        // ─────────────────────────
        // 上方：明亮 / 淡
        // ─────────────────────────
        const Text(
          '明亮 / 淡',
          style: TextStyle(color: Colors.white70, fontSize: 10),
        ),

        const SizedBox(height: 3),

        // ─────────────────────────
        // 正方形調色盤
        // ─────────────────────────
        SizedBox(
          width: 112,
          height: 112,
          child: LayoutBuilder(
            builder: (context, constraints) {
              final size = Size(constraints.maxWidth, constraints.maxHeight);

              final centerX = constraints.maxWidth / 2;
              final centerY = constraints.maxHeight / 2;

              return GestureDetector(
                behavior: HitTestBehavior.opaque,

                // 直接拖曳，不需要長按
                onPanStart: (details) {
                  if (!_isPaletteEditing) return;

                  _updatePalettePosition(details.localPosition, size);
                },

                onPanUpdate: (details) {
                  if (!_isPaletteEditing) return;

                  _updatePalettePosition(details.localPosition, size);
                },

                child: Stack(
                  clipBehavior: Clip.hardEdge,
                  children: [
                    // ─────────────────
                    // 基礎色彩
                    // ─────────────────
                    Container(
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.topRight,
                          colors: [
                            Color.lerp(
                              Colors.white,
                              _paletteColor(_selectedPalette),
                              0.42,
                            )!,
                            Color.lerp(
                              _paletteColor(_selectedPalette),
                              Colors.white,
                              0.18,
                            )!,
                          ],
                        ),
                      ),
                    ),

                    // ─────────────────
                    // 明亮 → 深
                    // ─────────────────
                    Container(
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            Colors.white,
                            Colors.transparent,
                            Colors.black,
                          ],
                        ),
                      ),
                    ),

                    // ─────────────────
                    // 冷 → 暖
                    // ─────────────────
                    Container(
                      width: constraints.maxWidth,
                      height: constraints.maxHeight,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(10),
                        gradient: LinearGradient(
                          begin: Alignment.centerLeft,
                          end: Alignment.centerRight,
                          colors: [
                            _paletteColor(_selectedPalette)
                                .withValues(alpha: 0.34),
                            Colors.transparent,
                            Color.lerp(
                              _paletteColor(_selectedPalette),
                              Colors.white,
                              0.35,
                            )!.withValues(alpha: 0.34),
                          ],
                        ),
                      ),
                    ),

                    // ─────────────────
                    // 水平中央十字軸
                    // ─────────────────
                    Positioned(
                      left: 0,
                      right: 0,
                      top: centerY,
                      child: Container(height: 1, color: Colors.white54),
                    ),

                    // ─────────────────
                    // 垂直中央十字軸
                    // ─────────────────
                    Positioned(
                      top: 0,
                      bottom: 0,
                      left: centerX,
                      child: Container(width: 1, color: Colors.white54),
                    ),

                    // ─────────────────
                    // 可拖曳控制點
                    // ─────────────────
                    Positioned(
                      left:
                          (_paletteX * constraints.maxWidth).clamp(
                            7.0,
                            constraints.maxWidth - 7.0,
                          ) -
                          7,

                      top:
                          (_paletteY * constraints.maxHeight).clamp(
                            7.0,
                            constraints.maxHeight - 7.0,
                          ) -
                          7,

                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(color: Colors.black87, width: 2),
                          boxShadow: const [
                            BoxShadow(color: Colors.black54, blurRadius: 3),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          ),
        ),

        const SizedBox(height: 2),

        // ─────────────────────────
        // 冷 / 暖
        // ─────────────────────────
        const SizedBox(
          width: 112,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('冷', style: TextStyle(color: Colors.white70, fontSize: 10)),
              Text('暖', style: TextStyle(color: Colors.white70, fontSize: 10)),
            ],
          ),
        ),

        const SizedBox(height: 2),

        // ─────────────────────────
        // 下方：深 / 濃
        // ─────────────────────────
        const Text(
          '深 / 濃',
          style: TextStyle(color: Colors.white70, fontSize: 10),
        ),
      ],
    );
  }

  Widget _buildFilterAdjustmentContent() {
    const filters = ['原味', '鮮明', '溫暖', '冷色', '復古'];

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Align(
          alignment: Alignment.centerLeft,
          child: Text(
            '濾鏡',
            style: TextStyle(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        const SizedBox(height: 7),
        SizedBox(
          height: 64,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: filters.map((filter) {
              final bool selected = _filterMode == filter;
              final Color color = _filterColor(filter);

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _filterMode = filter;
                  });

                  _showAiTip('🎨 濾鏡風格: $filter');
                },
                child: SizedBox(
                  width: 54,
                  child: Column(
                    children: [
                      Container(
                        width: 42,
                        height: 42,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: RadialGradient(
                            colors: [
                              Colors.white.withValues(alpha: 0.8),
                              color,
                              Color.lerp(color, Colors.black, 0.3)!,
                            ],
                          ),
                          border: Border.all(
                            color: selected
                                ? Colors.yellowAccent
                                : Colors.white24,
                            width: selected ? 2 : 1,
                          ),
                        ),
                        child: selected
                            ? const Icon(
                                Icons.check,
                                color: Colors.white,
                                size: 17,
                              )
                            : null,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        filter,
                        style: TextStyle(
                          color: selected
                              ? Colors.yellowAccent
                              : Colors.white70,
                          fontSize: 10,
                          fontWeight: selected
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Color _filterColor(String filter) {
    switch (filter) {
      case '鮮明':
        return const Color(0xFFE58F7A);
      case '溫暖':
        return const Color(0xFFE7B35C);
      case '冷色':
        return const Color(0xFF739BC8);
      case '復古':
        return const Color(0xFFA47A5A);
      default:
        return const Color(0xFF8E8E8E);
    }
  }

  Widget _buildPalettePanel() {
    final bool isFilter = _activeBottomAdjustment == 'filter';

    return Container(
      width: double.infinity,
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.fromLTRB(
        16,
        18, // 上方增加一點距離
        16,
        0, // 底部不要再留大空間
      ),
      decoration: const BoxDecoration(color: Colors.transparent),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          isFilter
              ? _buildFilterAdjustmentContent()
              : Transform.translate(
                  offset: const Offset(0, 12),
                  child: _buildPaletteAdjustmentContent(),
                ),

          const SizedBox(height: 4),

          Align(
            alignment: Alignment.centerLeft,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _closeBottomAdjustment,
              child: const SizedBox(
                width: 40,
                height: 24,
                child: Center(
                  child: Icon(
                    Icons.keyboard_arrow_down,
                    color: Colors.white70,
                    size: 22,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDuration(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  Future<void> _clearAllImages() async {
  final imagesToDelete =
      List<String>.from(
    _capturedImages,
  );

  for (final path in imagesToDelete) {
    try {
      // --------------------------------------------------------
      // Live Photo → 先刪 MOV
      // --------------------------------------------------------

      await _deleteLivePhotoResources(
        path,
      );

      // --------------------------------------------------------
      // 再刪 Photo
      // --------------------------------------------------------

      final file =
          File(path);

      if (await file.exists()) {
        await file.delete();

        debugPrint(
          '🗑️ Deleted captured file: '
          '$path',
        );
      }
    } catch (e) {
      debugPrint(
        '❌ Failed to delete file: '
        '$path',
      );
      debugPrint('$e');
    }
  }

  if (!mounted) return;

  setState(() {
    _capturedImages.clear();
  });

  await _persistImageLists();
}

  void _showCircularOptionsDialog({
    required String title,
    required String currentValue,
    required List<Map<String, dynamic>> options,
    required ValueChanged<String> onSelected,
  }) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.grey[900],
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
            side: const BorderSide(color: Colors.white24, width: 0.5),
          ),
          title: Text(
            title,
            style: const TextStyle(color: Colors.white, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          content: Wrap(
            spacing: 16,
            runSpacing: 16,
            alignment: WrapAlignment.center,
            children: options.map((opt) {
              final String val = opt['value'];
              final bool isSelected = currentValue == val;
              return GestureDetector(
                onTap: () {
                  onSelected(val);
                  Navigator.pop(context);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: isSelected
                            ? Colors.yellowAccent.withValues(alpha: 0.3)
                            : Colors.white10,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? Colors.yellowAccent
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      child: Icon(
                        opt['icon'],
                        color: isSelected ? Colors.yellowAccent : Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      opt['label'],
                      style: TextStyle(
                        color: isSelected
                            ? Colors.yellowAccent
                            : Colors.white70,
                        fontSize: 12,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _showAspectRatioSelectDialog() {
    _showCircularOptionsDialog(
      title: '選擇相片比例',
      currentValue: _aspectRatio,
      options: [
        {'label': '4:3', 'icon': Icons.aspect_ratio, 'value': '4:3'},
        {'label': '16:9', 'icon': Icons.crop_16_9, 'value': '16:9'},
        {'label': '1:1', 'icon': Icons.crop_square, 'value': '1:1'},
      ],
      onSelected: (val) {
        setState(() => _aspectRatio = val);
        _showAiTip('📐 比例已切換為：$_aspectRatio');
      },
    );
  }

  void _showCompositionSelectDialog() {
    _showCircularOptionsDialog(
      title: '選擇構圖線',
      currentValue: _compositionGrid,
      options: [
        {'label': '關閉', 'icon': Icons.grid_off, 'value': '關閉'},
        {'label': '九宮格', 'icon': Icons.grid_on, 'value': '九宮格'},
        {'label': '黃金比例', 'icon': Icons.straighten, 'value': '黃金比例'},
        {'label': '對角線', 'icon': Icons.show_chart, 'value': '對角線'},
        {'label': '中心十字', 'icon': Icons.add, 'value': '中心十字'},
        {'label': '安全框', 'icon': Icons.crop_free, 'value': '安全框'},
        {'label': '智能構圖', 'icon': Icons.auto_awesome, 'value': '智能構圖'},
      ],
      onSelected: (val) {
        setState(() => _compositionGrid = val);
        _showAiTip('📐 構圖線已切換為：$_compositionGrid');
      },
    );
  }

  // 個人化 AI 權重與重置設定對話框
  void _showPersonalizedAiDialog() {
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              backgroundColor: Colors.grey[900],
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(20),
              ),
              title: const Row(
                children: [
                  Icon(Icons.tune, color: Colors.yellowAccent),
                  SizedBox(width: 8),
                  Text(
                    '個人化 AI 權重設定',
                    style: TextStyle(color: Colors.white, fontSize: 18),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '調整 AI 評分選項的權重比例：',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  const SizedBox(height: 12),
                  ..._aiWeights.keys.map((key) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              key,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              '${(_aiWeights[key]! * 100).toInt()}%',
                              style: const TextStyle(
                                color: Colors.yellowAccent,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          value: _aiWeights[key]!,
                          min: 0.0,
                          max: 1.0,
                          divisions: 10,
                          activeColor: Colors.yellowAccent,
                          inactiveColor: Colors.white24,
                          onChanged: (val) {
                            setStateDialog(() {
                              _aiWeights[key] = val;
                            });
                            setState(() {});
                          },
                        ),
                      ],
                    );
                  }),
                  const SizedBox(height: 10),
                  Center(
                    child: TextButton.icon(
                      onPressed: () {
                        setStateDialog(() {
                          _aiWeights.updateAll((key, value) => 1.0);
                        });
                        setState(() {});
                        _showAiTip('🔄 個人化權重已全部重置');
                      },
                      icon: const Icon(Icons.refresh, color: Colors.redAccent),
                      label: const Text(
                        '重置所有權重',
                        style: TextStyle(
                          color: Colors.redAccent,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.redAccent.withValues(
                          alpha: 0.1,
                        ),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text(
                    '完成',
                    style: TextStyle(
                      color: Colors.yellowAccent,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEnlargedGallery(int initialIndex, {bool showSavedImages = false}) {
    // ============================================================
    // Gallery 資料來源
    //
    // 候選照片 → _capturedImages
    // 永久相簿 → _savedImages
    // ============================================================
    final List<String> galleryImages = showSavedImages
        ? _savedImages
        : _capturedImages;

    if (galleryImages.isEmpty) return;

    int currentIndex = initialIndex.clamp(0, galleryImages.length - 1).toInt();

    final PageController pageController = PageController(
      initialPage: currentIndex,
    );

    // ============================================================
    // 手勢狀態
    // ============================================================

    Offset dragStart = Offset.zero;
    Offset dragCurrent = Offset.zero;

    double horizontalDragOffset = 0.0;

    double verticalAnimationOffset = 0.0;

    bool isDragging = false;
    bool isAnimating = false;

    // 0 = 無操作
    // 1 = 保存
    // -1 = 刪除
    int horizontalAction = 0;

    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      barrierDismissible: true,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            // ========================================================
            // 沒有照片
            // ========================================================
            if (galleryImages.isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (Navigator.canPop(dialogContext)) {
                  Navigator.pop(dialogContext);
                }
              });

              return const SizedBox.shrink();
            }

            // ========================================================
            // 確保 currentIndex 永遠有效
            // ========================================================
            if (currentIndex >= galleryImages.length) {
              currentIndex = galleryImages.length - 1;
            }

            if (currentIndex < 0) {
              currentIndex = 0;
            }

            // ========================================================
            // 前往指定頁面
            // ========================================================
            void goToPage(int index) {
              if (galleryImages.isEmpty) return;
              if (isAnimating) return;

              final target = index.clamp(0, galleryImages.length - 1);

              if (target == currentIndex) {
                return;
              }

              setStateDialog(() {
                currentIndex = target;
                horizontalDragOffset = 0.0;
                verticalAnimationOffset = 0.0;
                horizontalAction = 0;
              });

              if (pageController.hasClients) {
                pageController.animateToPage(
                  target,
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutCubic,
                );
              }
            }

            // ========================================================
            // 滑鼠滾輪 / 觸控板
            //
            // 往下 → 下一張
            // 往上 → 上一張
            // ========================================================
            void handlePointerSignal(PointerSignalEvent event) {
              if (event is! PointerScrollEvent) {
                return;
              }

              if (galleryImages.isEmpty) {
                return;
              }

              if (isAnimating) {
                return;
              }

              final delta = event.scrollDelta.dy;

              if (delta > 0) {
                goToPage(currentIndex + 1);
              } else if (delta < 0) {
                goToPage(currentIndex - 1);
              }
            }

            // ========================================================
            // 手勢開始
            // ========================================================
            void handleDragStart(DragStartDetails details) {
              if (isAnimating) {
                return;
              }

              dragStart = details.globalPosition;
              dragCurrent = details.globalPosition;

              setStateDialog(() {
                isDragging = true;
                horizontalDragOffset = 0.0;
                horizontalAction = 0;
              });
            }

            // ========================================================
            // 手勢移動
            // ========================================================
            void handleDragUpdate(DragUpdateDetails details) {
              if (!isDragging) {
                return;
              }

              if (isAnimating) {
                return;
              }

              dragCurrent = details.globalPosition;

              final dx = dragCurrent.dx - dragStart.dx;

              final dy = dragCurrent.dy - dragStart.dy;

              // ======================================================
              // 水平手勢
              // ======================================================
              if (dx.abs() > dy.abs()) {
                final screenWidth = MediaQuery.of(context).size.width;

                final limitedOffset = dx.clamp(
                  -screenWidth * 0.55,
                  screenWidth * 0.55,
                );

                setStateDialog(() {
                  horizontalDragOffset = limitedOffset.toDouble();

                  if (horizontalDragOffset > 30) {
                    horizontalAction = 1;
                  } else if (horizontalDragOffset < -30) {
                    horizontalAction = -1;
                  } else {
                    horizontalAction = 0;
                  }
                });
              }
            }

            // ========================================================
            // 手勢結束
            // ========================================================
            Future<void> handleDragEnd(DragEndDetails details) async {
              if (!isDragging) {
                return;
              }

              if (isAnimating) {
                return;
              }

              final dx = dragCurrent.dx - dragStart.dx;

              final dy = dragCurrent.dy - dragStart.dy;

              final absDx = dx.abs();
              final absDy = dy.abs();

              setStateDialog(() {
                isDragging = false;
              });

              const double minimumDistance = 50.0;

              // ======================================================
              // 距離太短 → 回原位
              // ======================================================
              if (absDx < minimumDistance && absDy < minimumDistance) {
                setStateDialog(() {
                  horizontalDragOffset = 0.0;
                  verticalAnimationOffset = 0.0;
                  horizontalAction = 0;
                });

                return;
              }

              // ======================================================
              // 水平手勢
              // ======================================================
              if (absDx > absDy) {
                if (currentIndex >= galleryImages.length) {
                  return;
                }

                final itemPath = galleryImages[currentIndex];

                final screenWidth = MediaQuery.of(context).size.width;

                final screenHeight = MediaQuery.of(context).size.height;

                // ====================================================
                // 左滑 → 刪除
                // ====================================================
                if (dx < 0) {
                  isAnimating = true;

                  // ------------------------------------------------
                  // ① 目前照片往左飛出去
                  // ------------------------------------------------
                  setStateDialog(() {
                    horizontalAction = -1;
                    horizontalDragOffset = -screenWidth;
                    verticalAnimationOffset = 0.0;
                  });

                  await Future.delayed(const Duration(milliseconds: 180));

                  if (!mounted) {
                    isAnimating = false;
                    return;
                  }

                  final deletedIndex = currentIndex;

                  // ------------------------------------------------
                  // ② 刪除
                  // ------------------------------------------------
                  if (showSavedImages) {
                  // ==============================================
                  // 永久相簿
                  // 刪除 JPG + Live Photo MOV
                  // ==============================================
                  try {
                    await _deleteLivePhotoResources(
                      itemPath,
                    );

                    final file =
                        File(itemPath);

                    if (await file.exists()) {
                      await file.delete();
                    }
                    } catch (e) {
                      debugPrint('❌ 永久相簿照片刪除失敗: $e');

                      setStateDialog(() {
                        horizontalDragOffset = 0.0;
                        verticalAnimationOffset = 0.0;
                        horizontalAction = 0;
                      });

                      isAnimating = false;

                      _showAiTip('⚠️ 照片刪除失敗');

                      return;
                    }

                    setState(() {
                      if (deletedIndex >= 0 &&
                          deletedIndex < _savedImages.length) {
                        _savedImages.removeAt(deletedIndex);
                      }
                    });
                  } else {
                    // ==============================================
                    // AI 候選照片
                    // ==============================================
                     await _deleteLivePhotoResources(
                        itemPath,
                      );
                    setState(() {
                      if (deletedIndex >= 0 &&
                          deletedIndex < _capturedImages.length) {
                        _capturedImages.removeAt(deletedIndex);
                      }
                    });
                  }

                  // ------------------------------------------------
                  // ③ 已經沒有照片
                  // ------------------------------------------------
                  if (galleryImages.isEmpty) {
                    if (!dialogContext.mounted) return;

                    if (Navigator.canPop(dialogContext)) {
                      Navigator.pop(dialogContext);
                    }

                    isAnimating = false;

                    return;
                  }

                  // ------------------------------------------------
                  // ④ 修正 index
                  // ------------------------------------------------
                  if (currentIndex >= galleryImages.length) {
                    currentIndex = galleryImages.length - 1;
                  }

                  if (currentIndex < 0) {
                    currentIndex = 0;
                  }

                  final nextIndex = currentIndex;

                  // ------------------------------------------------
                  // ⑤ 先清掉左右動畫狀態
                  //
                  // 新照片先放在螢幕下方
                  // ------------------------------------------------
                  setStateDialog(() {
                    horizontalDragOffset = 0.0;
                    horizontalAction = 0;

                    verticalAnimationOffset = screenHeight * 0.60;
                  });

                  // ------------------------------------------------
                  // ⑥ PageView 直接定位到新照片
                  // ------------------------------------------------
                  if (pageController.hasClients) {
                    pageController.jumpToPage(nextIndex);
                  }

                  // ------------------------------------------------
                  // ⑦ 等待新照片完成定位
                  // ------------------------------------------------
                  await Future.delayed(const Duration(milliseconds: 20));

                  if (!mounted) {
                    isAnimating = false;
                    return;
                  }

                  // ------------------------------------------------
                  // ⑧ 新照片由下往上進場
                  // ------------------------------------------------
                  setStateDialog(() {
                    verticalAnimationOffset = 0.0;
                  });

                  // ------------------------------------------------
                  // ⑨ 等待進場動畫完成
                  // ------------------------------------------------
                  await Future.delayed(const Duration(milliseconds: 220));

                  if (!mounted) {
                    isAnimating = false;
                    return;
                  }

                  // ------------------------------------------------
                  // ⑩ 最終清除狀態
                  // ------------------------------------------------
                  setStateDialog(() {
                    horizontalDragOffset = 0.0;
                    verticalAnimationOffset = 0.0;
                    horizontalAction = 0;
                  });

                  isAnimating = false;

                  _showAiTip(
                    showSavedImages ? '🗑️ 已從永久相簿刪除這張照片' : '🗑️ 已刪除這張照片',
                  );

                  return;
                }

                // ====================================================
                // 右滑 → 兩階段保存
                // ====================================================
                if (dx > 0) {
                  isAnimating = true;

                  // ------------------------------------------------
                  // ① 照片往右飛出去
                  // ------------------------------------------------
                  setStateDialog(() {
                    horizontalAction = 1;
                    horizontalDragOffset = screenWidth;
                    verticalAnimationOffset = 0.0;
                  });

                  await Future.delayed(
                    const Duration(milliseconds: 180),
                  );

                  if (!mounted) {
                    isAnimating = false;
                    return;
                  }

                  // ==================================================
                  // 第一階段
                  // AI 精選預覽 → APP 內相簿
                  // ==================================================
                  if (!showSavedImages) {
                    // ------------------------------------------------
                    // ② 加入 APP 內相簿
                    // ------------------------------------------------
                    setState(() {
                      if (!_savedImages.contains(itemPath)) {
                        _savedImages.add(itemPath);
                      }

                      // 從 AI 精選預覽移除
                      if (currentIndex >= 0 &&
                          currentIndex < _capturedImages.length) {
                        _capturedImages.removeAt(currentIndex);
                      }
                    });

                    await _persistImageLists();

                    if (!mounted) {
                      isAnimating = false;
                      return;
                    }

                    debugPrint(
                      '✅ RIGHT SWIPE → APP ALBUM: $itemPath',
                    );

                    _showAiTip('📌 已加入 APP 相簿');
                  }

                  // ==================================================
                  // 第二階段
                  // APP 內相簿 → Apple 照片
                  // ==================================================
                  else {
                    // ------------------------------------------------
                    // ② 正式保存到 Apple 照片
                    // ------------------------------------------------
                    final savedSuccessfully =
                        await _saveImageToApplePhotos(itemPath);

                    if (!mounted) {
                      isAnimating = false;
                      return;
                    }

                    // ------------------------------------------------
                    // 保存失敗 → 彈回
                    // ------------------------------------------------
                    if (!savedSuccessfully) {
                      setStateDialog(() {
                        horizontalDragOffset = 0.0;
                        verticalAnimationOffset = 0.0;
                        horizontalAction = 0;
                      });

                      isAnimating = false;

                      _showAiTip('⚠️ 照片保存失敗');

                      return;
                    }

                    // ------------------------------------------------
                    // 保存成功
                    //
                    // 注意：
                    // 不從 _savedImages 移除
                    // ------------------------------------------------
                    await _persistImageLists();

                    debugPrint(
                      '✅ RIGHT SWIPE → APPLE PHOTOS: $itemPath',
                    );

                    _showAiTip('✅ 已保存到 Apple 照片');
                  }

                  // ==================================================
                  // ③ 已經沒有照片
                  // ==================================================
                  if (galleryImages.isEmpty) {
                    if (!dialogContext.mounted) {
                      isAnimating = false;
                      return;
                    }

                    if (Navigator.canPop(dialogContext)) {
                      Navigator.pop(dialogContext);
                    }

                    isAnimating = false;

                    return;
                  }

                  // ==================================================
                  // ④ 修正 index
                  // ==================================================
                  if (currentIndex >= galleryImages.length) {
                    currentIndex = galleryImages.length - 1;
                  }

                  if (currentIndex < 0) {
                    currentIndex = 0;
                  }

                  final nextIndex = currentIndex;

                  // ==================================================
                  // ⑤ 清除左右動畫
                  //
                  // 新照片先放到螢幕下方
                  // ==================================================
                  setStateDialog(() {
                    horizontalDragOffset = 0.0;
                    horizontalAction = 0;

                    verticalAnimationOffset = screenHeight * 0.60;
                  });

                  // ==================================================
                  // ⑥ PageView 跳到下一張
                  // ==================================================
                  if (pageController.hasClients) {
                    pageController.jumpToPage(nextIndex);
                  }

                  // ==================================================
                  // ⑦ 等待 PageView 更新
                  // ==================================================
                  await Future.delayed(
                    const Duration(milliseconds: 20),
                  );

                  if (!mounted) {
                    isAnimating = false;
                    return;
                  }

                  // ==================================================
                  // ⑧ 新照片由下往上進場
                  // ==================================================
                  setStateDialog(() {
                    verticalAnimationOffset = 0.0;
                  });

                  // ==================================================
                  // ⑨ 等待進場動畫完成
                  // ==================================================
                  await Future.delayed(
                    const Duration(milliseconds: 220),
                  );

                  if (!mounted) {
                    isAnimating = false;
                    return;
                  }

                  // ==================================================
                  // ⑩ 最終清除動畫狀態
                  // ==================================================
                  setStateDialog(() {
                    horizontalDragOffset = 0.0;
                    verticalAnimationOffset = 0.0;
                    horizontalAction = 0;
                  });

                  isAnimating = false;

                  return;
                }             
              }
              // ======================================================
              // 垂直手勢
              // ======================================================
              else {
                // ----------------------------------------------------
                // 上滑 → 下一張
                // ----------------------------------------------------
                if (dy < 0) {
                  if (currentIndex < galleryImages.length - 1) {
                    goToPage(currentIndex + 1);
                  }
                }
                // ----------------------------------------------------
                // 下滑 → 上一張
                // ----------------------------------------------------
                else {
                  if (currentIndex > 0) {
                    goToPage(currentIndex - 1);
                  }
                }

                setStateDialog(() {
                  horizontalDragOffset = 0.0;
                  verticalAnimationOffset = 0.0;
                  horizontalAction = 0;
                });
              }
            }

            // ========================================================
            // Gallery 卡片
            // ========================================================
            Widget buildGalleryCard(String itemPath, int index) {
              final imageFile = File(itemPath);

              final bool isRealImage = imageFile.existsSync();

              return Center(
                // ==================================================
                // 每張照片使用自己的 Key
                // ==================================================
                key: ValueKey<String>(itemPath),

                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,

                  // ==================================================
                  // 長按放大照片 → 播放 Live Photo
                  // ==================================================
                  onLongPress: () {
                    if (!_isLivePhoto(itemPath)) {
                      return;
                    }

                    unawaited(
                      _showLivePhotoPreview(
                        itemPath,
                        showSavedImages: showSavedImages,
                      ),
                    );
                  },

                  child: AnimatedContainer(
                    duration: isDragging
                        ? Duration.zero
                        : const Duration(milliseconds: 220),

                    curve: Curves.easeOutCubic,

                    transform: Matrix4.identity()
                      ..translateByDouble(
                        horizontalDragOffset,
                        verticalAnimationOffset,
                        0.0,
                        1.0,
                      )
                      ..rotateZ(horizontalDragOffset * 0.00035),

                    transformAlignment: Alignment.center,

                    width: 320,
                    height: 440,

                    decoration: BoxDecoration(
                      color: Colors.grey[900],

                      borderRadius: BorderRadius.circular(20),

                      border: Border.all(
                        color: isRealImage
                            ? Colors.yellowAccent
                            : Colors.orangeAccent,
                        width: 2,
                      ),

                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.5),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),

                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),

                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        if (isRealImage)
                          Image.file(
                            imageFile,
                            fit: BoxFit.contain,
                            errorBuilder: (context, error, stackTrace) {
                              return const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.broken_image,
                                      color: Colors.redAccent,
                                      size: 70,
                                    ),
                                    SizedBox(height: 12),
                                    Text(
                                      '照片載入失敗',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 18,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          )
                        else
                          const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.broken_image,
                                  color: Colors.redAccent,
                                  size: 70,
                                ),
                                SizedBox(height: 12),
                                Text(
                                  '照片檔案不存在',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ],
                            ),
                          ),

                        // =================================================
                        // 張數
                        // =================================================
                        Positioned(
                          bottom: 12,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 5,
                              ),

                              decoration: BoxDecoration(
                                color: Colors.black.withValues(alpha: 0.7),

                                borderRadius: BorderRadius.circular(12),
                              ),

                              child: Text(
                                '${index + 1} / ${galleryImages.length}',
                                style: const TextStyle(
                                  color: Colors.yellowAccent,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ),
                        ),

                        // =================================================
                        // 左滑 → 刪除提示
                        // =================================================
                        if (horizontalDragOffset < 0 || horizontalAction == -1)
                          Positioned(
                            left: 18,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 80),

                                opacity: horizontalDragOffset < 0
                                    ? (horizontalDragOffset.abs() / 60).clamp(
                                        0.0,
                                        1.0,
                                      )
                                    : horizontalAction == -1
                                    ? 1.0
                                    : 0.0,

                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),

                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.75),

                                    borderRadius: BorderRadius.circular(12),

                                    border: Border.all(
                                      color: Colors.redAccent,
                                      width: 1.5,
                                    ),
                                  ),

                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.delete_outline,
                                        color: Colors.redAccent,
                                        size: 20,
                                      ),

                                      SizedBox(width: 5),

                                      Text(
                                        '刪除',
                                        style: TextStyle(
                                          color: Colors.redAccent,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),

                        // =================================================
                        // 右滑 → 保存提示
                        // =================================================
                        if (horizontalDragOffset > 0 || horizontalAction == 1)
                          Positioned(
                            right: 18,
                            top: 0,
                            bottom: 0,
                            child: Center(
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 80),

                                opacity: horizontalDragOffset > 0
                                    ? (horizontalDragOffset / 60).clamp(
                                        0.0,
                                        1.0,
                                      )
                                    : horizontalAction == 1
                                    ? 1.0
                                    : 0.0,

                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),

                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.75),

                                    borderRadius: BorderRadius.circular(12),

                                    border: Border.all(
                                      color: Colors.greenAccent,
                                      width: 1.5,
                                    ),
                                  ),

                                  child: const Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.check_circle_outline,
                                        color: Colors.greenAccent,
                                        size: 20,
                                      ),

                                      SizedBox(width: 5),

                                      Text(
                                        '保存',
                                        style: TextStyle(
                                          color: Colors.greenAccent,
                                          fontSize: 13,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                )
              );           
            }

            // ============================================================
            // Gallery 主畫面
            // ============================================================
            return Listener(
              onPointerSignal: handlePointerSignal,

              child: Stack(
                children: [
                  // ======================================================
                  // 黑色背景
                  // ======================================================
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,

                      onTap: () {
                        if (!isDragging && !isAnimating) {
                          Navigator.pop(dialogContext);
                        }
                      },

                      child: Container(
                        color: Colors.black.withValues(alpha: 0.95),
                      ),
                    ),
                  ),

                  // ======================================================
                  // Gallery
                  // ======================================================
                  Positioned.fill(
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,

                      onPanStart: handleDragStart,

                      onPanUpdate: handleDragUpdate,

                      onPanEnd: handleDragEnd,

                      child: PageView.builder(
                        controller: pageController,

                        scrollDirection: Axis.vertical,

                        physics: const NeverScrollableScrollPhysics(),

                        itemCount: galleryImages.length,

                        onPageChanged: (index) {
                          currentIndex = index;

                          setStateDialog(() {
                            horizontalDragOffset = 0.0;

                            verticalAnimationOffset = 0.0;

                            horizontalAction = 0;
                          });
                        },

                        itemBuilder: (context, index) {
                          return buildGalleryCard(galleryImages[index], index);
                        },
                      ),
                    ),
                  ),

                  // ======================================================
                  // 左側提示
                  // ======================================================
                  Positioned(
                    left: 20,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: IgnorePointer(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.keyboard_arrow_up,
                              color: Colors.white.withValues(alpha: 0.45),
                              size: 28,
                            ),

                            Text(
                              '上下切換',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.45),
                                fontSize: 11,
                              ),
                            ),

                            Icon(
                              Icons.keyboard_arrow_down,
                              color: Colors.white.withValues(alpha: 0.45),
                              size: 28,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ======================================================
                  // 右側提示
                  // ======================================================
                  Positioned(
                    right: 20,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: IgnorePointer(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.swipe,
                              color: Colors.white.withValues(alpha: 0.35),
                              size: 24,
                            ),

                            const SizedBox(height: 4),

                            Text(
                              '左右操作',
                              style: TextStyle(
                                color: Colors.white.withValues(alpha: 0.35),
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // ======================================================
                  // Apple 照片保存 + 關閉按鈕
                  // ======================================================
                  Positioned(
                    top: 40,
                    right: 20,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (showSavedImages) const SizedBox(width: 8),

                        // ==================================================
                        // 關閉
                        // ==================================================
                        Material(
                          color: Colors.black.withValues(alpha: 0.5),
                          shape: const CircleBorder(),
                          child: IconButton(
                            tooltip: '關閉',
                            icon: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 32,
                            ),
                            onPressed: () {
                              if (!isAnimating) {
                                Navigator.pop(dialogContext);
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 40,
                    left: 20,
                    child: Material(
                      color: Colors.black.withValues(alpha: 0.5),
                      shape: const CircleBorder(),
                      child: IconButton(
                        icon: const Icon(
                          Icons.tune,
                          color: Colors.white,
                          size: 28,
                        ),
                        tooltip: '編輯照片',
                        onPressed: () {
                          if (!isAnimating &&
                              currentIndex >= 0 &&
                              currentIndex < galleryImages.length) {
                            _showImageEditor(galleryImages[currentIndex]);
                          }
                        },
                      ),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    ).then((_) {
      pageController.dispose();
    });
  }

  void _showPhotoAlbum() {
    if (_savedImages.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('📷 目前尚無已保存的照片'),
          duration: Duration(milliseconds: 800),
        ),
      );
      return;
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return Container(
          height: MediaQuery.of(sheetContext).size.height * 0.88,
          decoration: const BoxDecoration(
            color: Color(0xFF111111),
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          child: Column(
            children: [
              // 頂部標題列
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 12, 10),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        '相簿',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),

                    Text(
                      '${_savedImages.length} 張',
                      style: const TextStyle(
                        color: Colors.white54,
                        fontSize: 14,
                      ),
                    ),

                    const SizedBox(width: 8),

                    IconButton(
                      onPressed: () {
                        Navigator.pop(sheetContext);
                      },
                      icon: const Icon(Icons.close, color: Colors.white),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1, color: Colors.white12),

              // 照片 Grid
              Expanded(
                child: GridView.builder(
                  padding: const EdgeInsets.all(8),
                  physics: const BouncingScrollPhysics(),
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3,
                    crossAxisSpacing: 3,
                    mainAxisSpacing: 3,
                    childAspectRatio: 1,
                  ),
                  itemCount: _savedImages.length,
                  itemBuilder: (context, index) {
                    final imagePath = _savedImages[index];
                    final imageFile = File(imagePath);

                   return GestureDetector(
                    behavior: HitTestBehavior.opaque,

                    onTap: () {
                      Navigator.pop(sheetContext);

                      _showEnlargedGallery(
                        index,
                        showSavedImages: true,
                      );
                    },                   

                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(4),
                        child: imageFile.existsSync()
                            ? Image.file(
                                imageFile,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) {
                                  return Container(
                                    color: Colors.grey[850],
                                    child: const Icon(
                                      Icons.broken_image,
                                      color: Colors.redAccent,
                                      size: 32,
                                    ),
                                  );
                                },
                              )
                            : Container(
                                color: Colors.grey[850],
                                child: const Icon(
                                  Icons.broken_image,
                                  color: Colors.redAccent,
                                  size: 32,
                                ),
                              ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: _scaffoldKey,
      backgroundColor: Colors.black,
      // 側邊選項選單 (Drawer)
      drawer: Drawer(
        backgroundColor: Colors.grey[900],
        child: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.auto_awesome, color: Colors.yellowAccent),
                      SizedBox(width: 8),
                      Text(
                        'AI 智慧相機設定',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
              const Divider(color: Colors.white24, height: 24),

              // 1. AI 導演模式
              SwitchListTile(
                title: const Text(
                  'AI 導演模式',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: const Text(
                  '由 AI 分析預覽畫面給拍照者引導',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                value: _aiDirectorMode,
                activeThumbColor: Colors.yellowAccent,
                onChanged: (val) {
                  setState(() => _aiDirectorMode = val);
                  _showAiTip(
                    val ? '🎬 AI 導演模式已啟動（提供即時構圖與姿勢指引）' : '🎬 AI 導演模式已關閉',
                  );
                },
              ),
              const Divider(color: Colors.white24, height: 24),

              // 1.2 AI 智慧連拍開關（已修復：實際使用變數以消除未使用警告）[cite: 2]
              SwitchListTile(
                title: const Text(
                  'AI 智慧連拍功能',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: const Text(
                  '按下快門時啟動自動多張智慧抓拍',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                value: _aiBurstEnabled,
                activeThumbColor: Colors.yellowAccent,
                onChanged: (val) {
                  setState(() => _aiBurstEnabled = val);
                  _showAiTip(val ? '⚡ AI 智慧連拍已啟動' : '⚡ AI 智慧連拍已關閉（改為單張拍攝）');
                },
              ),
              const Divider(color: Colors.white24, height: 24),

              // 2. AI 抓拍與評分設定
              const Text(
                '📸 AI 抓拍與評分設定',
                style: TextStyle(
                  color: Colors.yellowAccent,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),

              const Text(
                '⏱️ 抓拍時間',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [3, 5].map((sec) {
                  bool selected = _aiBurstSeconds == sec;
                  return ChoiceChip(
                    label: Text('$sec 秒'),
                    selected: selected,
                    selectedColor: Colors.yellowAccent,
                    backgroundColor: Colors.grey[800],
                    labelStyle: TextStyle(
                      color: selected ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    onSelected: (bool selected) {
                      if (selected) {
                        setState(() => _aiBurstSeconds = sec);
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),

              const Text(
                '🔢 抓拍張數',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [3, 5, 7, 10].map((count) {
                  bool selected = _aiBurstCount == count;
                  return ChoiceChip(
                    label: Text('$count 張'),
                    selected: selected,
                    selectedColor: Colors.yellowAccent,
                    backgroundColor: Colors.grey[800],
                    labelStyle: TextStyle(
                      color: selected ? Colors.black : Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                    onSelected: (bool selected) {
                      if (selected) {
                        setState(() => _aiBurstCount = count);
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),

              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    '⭐ 合格分數 (門檻)',
                    style: TextStyle(color: Colors.white70, fontSize: 13),
                  ),
                  Text(
                    '$_passingScore 分',
                    style: const TextStyle(
                      color: Colors.yellowAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const Text(
                '（透過 AI 抓拍評分，到達此分數才會正式拍下）',
                style: TextStyle(color: Colors.white38, fontSize: 11),
              ),
              Slider(
                value: _passingScore.toDouble(),
                min: 1,
                max: 5,
                divisions: 4,
                activeColor: Colors.yellowAccent,
                inactiveColor: Colors.white24,
                onChanged: (val) {
                  setState(() {
                    _passingScore = val.toInt();
                  });
                },
              ),
              const SizedBox(height: 12),

              const Text(
                '💬 提示詞 (關鍵字引導)',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 6),
              TextField(
                controller: _promptController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: '輸入如 海邊夏日風、文青氣息...',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.grey[800],
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 10,
                  ),
                ),
                onChanged: (val) {
                  _aiPromptText = val;
                },
              ),
              const SizedBox(height: 16),

              const Text(
                '🖼️ 參考照片風格',
                style: TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 6),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _referencePhotoName = '風格範本_${DateTime.now().second}.jpg';
                  });
                  _showAiTip('✅ 已上傳參考照片風格，AI 將以此分析指引構圖');
                },
                icon: const Icon(Icons.upload_file, color: Colors.black),
                label: Text(
                  _referencePhotoName ?? '上傳想拍出的照片風格',
                  style: const TextStyle(
                    color: Colors.black,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.yellowAccent,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  minimumSize: const Size(double.infinity, 40),
                ),
              ),
              const Divider(color: Colors.white24, height: 30),

              // 3. 個人化 AI 設定
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.tune, color: Colors.yellowAccent),
                title: const Text(
                  '個人化 AI 權重與重置',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: const Text(
                  '設定評分選項權重與重置',
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                trailing: const Icon(
                  Icons.arrow_forward_ios,
                  color: Colors.white54,
                  size: 16,
                ),
                onTap: _showPersonalizedAiDialog,
              ),
            ],
          ),
        ),
      ),
      body: GestureDetector(
        child: Stack(
          children: [
            // 1. 背景：相機即時預覽區 或 獨立的上傳影片播放預覽區
            Positioned.fill(
              child: Container(
                color: Colors.grey[900],
                child: Stack(
                  children: [
                    Positioned(
                      top: 96,
                      left: 0,
                      right: 0,
                      bottom: 180,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTapUp: (details) {
                          final renderObject = _previewKey.currentContext
                              ?.findRenderObject();
                          if (renderObject is RenderBox) {
                            _handleFocusTap(
                              renderObject.globalToLocal(
                                details.globalPosition,
                              ),
                              renderObject.size,
                            );
                          }
                        },
                        onLongPressStart: _handleLongPressStart,
                        onLongPressMoveUpdate: _handleLongPressMove,
                        onLongPressEnd: _handleLongPressEnd,
                        onScaleStart: _handlePreviewScaleStart,
                        onScaleUpdate: _handlePreviewScaleUpdate,
                        onScaleEnd: _handlePreviewScaleEnd,
                        child: _activeUploadedVideo != null
                            ? Stack(
                                children: [
                                  Positioned.fill(
                                    child: Container(
                                      color: Colors.black,
                                      child: _videoLoadError != null
                                          ? Center(
                                              child: Padding(
                                                padding: const EdgeInsets.all(
                                                  24,
                                                ),
                                                child: Column(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    const Icon(
                                                      Icons.error_outline,
                                                      color: Colors.redAccent,
                                                      size: 48,
                                                    ),
                                                    const SizedBox(height: 12),
                                                    const Text(
                                                      '影片無法播放',
                                                      style: TextStyle(
                                                        color: Colors.white,
                                                        fontSize: 18,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                      ),
                                                    ),
                                                    const SizedBox(height: 8),
                                                    Text(
                                                      _videoLoadError!,
                                                      style: const TextStyle(
                                                        color: Colors.white60,
                                                        fontSize: 12,
                                                      ),
                                                      textAlign:
                                                          TextAlign.center,
                                                    ),
                                                    const SizedBox(height: 16),
                                                    ElevatedButton.icon(
                                                      onPressed:
                                                          _exitUploadedVideo,
                                                      icon: const Icon(
                                                        Icons.close,
                                                      ),
                                                      label: const Text('退出影片'),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            )
                                          : _videoPlayerController != null &&
                                                _videoPlayerController!.value.isInitialized
                                            ? Center(
                                                child: AspectRatio(
                                                  aspectRatio:
                                                      _videoPlayerController!.value.aspectRatio,
                                                  child: WinVideoPlayer(
                                                    _videoPlayerController!,
                                                  ),
                                                ),
                                              )
                                            : const Center(
                                                child: CircularProgressIndicator(
                                                  color: Colors.yellowAccent,
                                                ),
                                              ),
                                    ),
                                  ),
                                  Positioned(
                                    left: 24,
                                    right: 24,
                                    bottom: 130,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: 0.65,
                                        ),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(
                                          color: Colors.yellowAccent.withValues(
                                            alpha: 0.4,
                                          ),
                                          width: 1,
                                        ),
                                      ),
                                      child: Row(
                                        children: [
                                          IconButton(
                                            icon: Icon(
                                              _isVideoPlaying
                                                  ? Icons.pause
                                                  : Icons.play_arrow,
                                              color: Colors.yellowAccent,
                                            ),
                                            onPressed: () async {
                                              final controller =
                                                  _videoPlayerController;
                                              if (controller == null ||
                                                  !controller
                                                      .value
                                                      .isInitialized) {
                                                return;
                                              }

                                              if (controller.value.isPlaying) {
                                                await controller.pause();
                                              } else {
                                                await controller.play();
                                              }

                                              if (!mounted) return;
                                              setState(() {
                                                _isVideoPlaying =
                                                    controller.value.isPlaying;
                                              });
                                              _showAiTip(
                                                _isVideoPlaying
                                                    ? '▶️ 影片繼續播放'
                                                    : '⏸️ 影片已暫停',
                                              );
                                            },
                                          ),
                                          Expanded(
                                            child: Slider(
                                              value: _videoProgress,
                                              min: 0.0,
                                              max: 1.0,
                                              activeColor: Colors.yellowAccent,
                                              inactiveColor: Colors.white24,
                                              onChanged: (val) async {
                                                final controller =
                                                    _videoPlayerController;
                                                if (controller == null ||
                                                    !controller
                                                        .value
                                                        .isInitialized) {
                                                  return;
                                                }

                                                final duration =
                                                    controller.value.duration;
                                                if (duration.inMilliseconds <=
                                                    0) {
                                                  return;
                                                }

                                                await controller.seekTo(
                                                  Duration(
                                                    milliseconds:
                                                        (duration.inMilliseconds *
                                                                val)
                                                            .round(),
                                                  ),
                                                );

                                                if (!mounted) return;
                                                setState(() {
                                                  _videoProgress = val;
                                                });
                                              },
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Positioned(
                                    top: 40,
                                    right: 30,
                                    child: IconButton(
                                      icon: const Icon(
                                        Icons.close,
                                        color: Colors.white,
                                        size: 28,
                                      ),
                                      onPressed: _exitUploadedVideo,
                                      tooltip: '退出影片預覽',
                                    ),
                                  ),
                                ],
                              )
                           : SizedBox.expand(
                              key: _previewKey,
                              child: ClipRect(
                                child: Stack(
                                  fit: StackFit.expand,
                                  children: [
                                    // iOS 使用原生 AVFoundation 預覽
                                    if (Platform.isIOS)
                                      const UiKitView(
                                        viewType: 'ai_camera/pro_preview',
                                      )
                                    else
                                      _buildCameraPreview(),

                                    // Flutter UI overlay 保持不變
                                    _buildPreviewEffectOverlay(),
                                    _buildFocusOverlay(),
                                    _buildLevelOverlay(),
                                    _buildProOverlay(),

                                    CustomPaint(
                                      painter: CompositionGridPainter(
                                        _compositionGrid,
                                      ),
                                    ),

                                    if (_timerCountdown > 0)
                                      Center(
                                        child: Text(
                                          '$_timerCountdown',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 72,
                                            fontWeight: FontWeight.w300,
                                            shadows: [
                                              Shadow(
                                                color: Colors.black,
                                                blurRadius: 8,
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                            ),
                      ),
                    ),
                  ],
                ),
              ),          
            ),


                if (_effectDebugMessage.isNotEmpty)
                Positioned(
                  top: 100,
                  left: 20,
                  right: 20,
                  child: IgnorePointer(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.75),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        _effectDebugMessage,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
                ),


            // 2. iOS 風格頂部控制列與下拉控制面板
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: SafeArea(
                bottom: false,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16.0),
                      child: Row(
                        children: [
                          // ─────────────────────────
                          // 左側：AI 設定
                          // ─────────────────────────
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerLeft,
                              child: ElevatedButton.icon(
                                onPressed: () {
                                  _scaffoldKey.currentState?.openDrawer();
                                },
                                icon: const Icon(
                                  Icons.auto_awesome,
                                  color: Colors.yellowAccent,
                                  size: 16,
                                ),
                                label: const Text(
                                  'AI 設定',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 13,
                                  ),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.black54,
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 0,
                                  ),
                                  minimumSize: const Size(0, 34),
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(20),
                                    side: const BorderSide(
                                      color: Colors.yellowAccent,
                                      width: 0.4,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),

                          // ─────────────────────────
                          // 中央：濾鏡 / 調色盤
                          // ─────────────────────────
                          if (!_isRecording && _activeUploadedVideo == null)
                            Flexible(
                              flex: 3,
                              child: Padding(
                                padding: const EdgeInsets.only(top: 10),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // ─────────────────────────
                                    // 黑框：濾鏡 + 調色盤
                                    // ─────────────────────────
                                    Container(
                                      height: 42,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(
                                          alpha: 0.45,
                                        ),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(
                                          color: Colors.white.withValues(
                                            alpha: 0.12,
                                          ),
                                          width: 0.7,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          // ─────────────────────
                                          // 濾鏡
                                          // ─────────────────────
                                          GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () {
                                              if (_activeBottomAdjustment ==
                                                  'filter') {
                                                _closeBottomAdjustment();
                                              } else {
                                                _openBottomAdjustment('filter');
                                                _showAiTip('🎨 請選擇濾鏡');
                                              }
                                            },
                                            onLongPress: () {
                                              _openBottomAdjustment('filter');
                                            },
                                            child: SizedBox(
                                              width: 58,
                                              height: 38,
                                              child: Center(
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.filter_b_and_w,
                                                      color: _filterMode != '原味'
                                                          ? Colors.yellowAccent
                                                          : Colors.white,
                                                      size: 21,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      '濾鏡',
                                                      style: TextStyle(
                                                        color:
                                                            _filterMode != '原味'
                                                            ? Colors
                                                                  .yellowAccent
                                                            : Colors.white,
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),

                                          // 間距
                                          const SizedBox(width: 4),

                                          // ─────────────────────
                                          // 調色盤
                                          // ─────────────────────
                                          GestureDetector(
                                            behavior: HitTestBehavior.opaque,
                                            onTap: () {
                                              if (_activeBottomAdjustment ==
                                                  'palette') {
                                                _closeBottomAdjustment();
                                              } else {
                                                _openBottomAdjustment(
                                                  'palette',
                                                );

                                                setState(() {
                                                  _isPaletteEditing = true;
                                                  _isPaletteOpen = true;
                                                  _paletteX = 0.5;
                                                  _paletteY = 0.5;
                                                });

                                                _showAiTip('🎨 可直接拖曳原點調整色彩');
                                              }
                                            },
                                            onLongPress: () {
                                              _openBottomAdjustment('palette');
                                            },
                                            child: SizedBox(
                                              width: 70,
                                              height: 38,
                                              child: Center(
                                                child: Row(
                                                  mainAxisSize:
                                                      MainAxisSize.min,
                                                  children: [
                                                    Icon(
                                                      Icons.palette,
                                                      color:
                                                          _selectedPalette !=
                                                              '原味'
                                                          ? Colors.yellowAccent
                                                          : Colors.white,
                                                      size: 21,
                                                    ),
                                                    const SizedBox(width: 4),
                                                    Text(
                                                      '調色盤',
                                                      style: TextStyle(
                                                        color:
                                                            _selectedPalette !=
                                                                '原味'
                                                            ? Colors
                                                                  .yellowAccent
                                                            : Colors.white,
                                                        fontSize: 11,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // ─────────────────────────
                                    // 黑框外：目前選擇的值
                                    // ─────────────────────────
                                    const SizedBox(height: 2),

                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        // 濾鏡目前選擇
                                        SizedBox(
                                          width: 58,
                                          child: Text(
                                            _filterMode,
                                            textAlign: TextAlign.center,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: _filterMode != '原味'
                                                  ? Colors.yellowAccent
                                                  : Colors.white70,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),

                                        const SizedBox(width: 4),

                                        // 調色盤目前選擇
                                        SizedBox(
                                          width: 70,
                                          child: Text(
                                            _selectedPalette,
                                            textAlign: TextAlign.center,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: TextStyle(
                                              color: _selectedPalette != '原味'
                                                  ? Colors.yellowAccent
                                                  : Colors.white70,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          // ─────────────────────────
                          // 右側：影片上傳與功能選單
                          // ─────────────────────────
                          Expanded(
                            child: Align(
                              alignment: Alignment.centerRight,
                              child: Container(
                                height: 42,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(
                                    color: Colors.white.withValues(alpha: 0.12),
                                    width: 0.7,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    // 上傳影片
                                    if (_currentMode == '影片' &&
                                        !_isRecording &&
                                        _activeUploadedVideo == null)
                                      IconButton(
                                        icon: const Icon(
                                          Icons.upload_file,
                                          color: Colors.white,
                                          size: 21,
                                        ),
                                        tooltip: '上傳影片',
                                        padding: EdgeInsets.zero,
                                        constraints: const BoxConstraints(
                                          minWidth: 38,
                                          minHeight: 38,
                                        ),
                                        onPressed: _handleUploadVideo,
                                      ),

                                    // 選項：2 × 3 六格圖示
                                    GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: () {
                                        setState(() {
                                          _isTopMenuExpanded =
                                              !_isTopMenuExpanded;

                                          if (_isTopMenuExpanded) {
                                            _activeBottomAdjustment = null;
                                            _isPaletteOpen = false;
                                            _isPaletteEditing = false;
                                          }
                                        });
                                      },
                                      child: Container(
                                        width: 38,
                                        height: 38,
                                        padding: const EdgeInsets.all(7),
                                        decoration: BoxDecoration(
                                          color: _isTopMenuExpanded
                                              ? Colors.white.withValues(
                                                  alpha: 0.12,
                                                )
                                              : Colors.transparent,
                                          borderRadius: BorderRadius.circular(
                                            10,
                                          ),
                                        ),
                                        child: Transform.translate(
                                          offset: const Offset(0, 4),
                                          child: GridView.count(
                                            crossAxisCount: 3,
                                            mainAxisSpacing: 3,
                                            crossAxisSpacing: 3,
                                            physics:
                                                const NeverScrollableScrollPhysics(),
                                            padding: EdgeInsets.zero,
                                            children: List.generate(6, (index) {
                                              return Container(
                                                decoration: BoxDecoration(
                                                  color: _isTopMenuExpanded
                                                      ? Colors.yellowAccent
                                                      : Colors.white70,
                                                  borderRadius:
                                                      BorderRadius.circular(
                                                        1.5,
                                                      ),
                                                ),
                                              );
                                            }),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_isTopMenuExpanded &&
                        !_isRecording &&
                        _activeUploadedVideo == null)
                      Container(
                        margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                        padding: const EdgeInsets.symmetric(
                          vertical: 16,
                          horizontal: 12,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: Colors.white24, width: 0.5),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.5),
                              blurRadius: 10,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Wrap(
                              alignment: WrapAlignment.center,
                              spacing: 8,
                              runSpacing: 16,
                              children: [
                                _buildIOSControlItem(
                                  icon: Icons.aspect_ratio,
                                  label: '比例',
                                  value: _aspectRatio,
                                  onTap: () {
                                    setState(() {
                                      _aspectRatio = _aspectRatio == '4:3'
                                          ? '16:9'
                                          : (_aspectRatio == '16:9'
                                                ? '1:1'
                                                : '4:3');
                                    });
                                    _showAiTip('📐 比例已切換為：$_aspectRatio');
                                  },
                                  onLongPress: _showAspectRatioSelectDialog,
                                ),
                                _buildIOSControlItem(
                                  icon: Icons.nightlight_round,
                                  label: '夜間',
                                  value: _nightMode ? '開啟' : '關閉',
                                  highlight: _nightMode,
                                  onTap: () {
                                    setState(() {
                                      _nightMode = !_nightMode;
                                    });
                                    _showAiTip(
                                      '🌙 夜間模式: ${_nightMode ? "開啟" : "關閉"}',
                                    );
                                  },
                                ),
                                _buildIOSControlItem(
                                  icon: _compositionGrid == '關閉'
                                      ? Icons.grid_off
                                      : Icons.grid_on,
                                  label: '構圖線',
                                  value: _compositionGrid,
                                  highlight: _compositionGrid != '關閉',
                                  onTap: () {
                                    setState(() {
                                      if (_compositionGrid == '關閉') {
                                        _compositionGrid = '九宮格';
                                      } else if (_compositionGrid == '九宮格') {
                                        _compositionGrid = '黃金比例';
                                      } else if (_compositionGrid == '黃金比例') {
                                        _compositionGrid = '對角線';
                                      } else if (_compositionGrid == '對角線') {
                                        _compositionGrid = '中心十字';
                                      } else if (_compositionGrid == '中心十字') {
                                        _compositionGrid = '安全框';
                                      } else if (_compositionGrid == '安全框') {
                                        _compositionGrid = '智能構圖';
                                      } else {
                                        _compositionGrid = '關閉';
                                      }
                                    });
                                    _showAiTip('📐 構圖線已切換為：$_compositionGrid');
                                  },
                                  onLongPress: _showCompositionSelectDialog,
                                ),
                                _buildIOSControlItem(
                                  icon: _timerSeconds == 0
                                      ? Icons.timer_off
                                      : Icons.timer,
                                  label: '計時',
                                  value: _timerSeconds == 0
                                      ? '關閉'
                                      : '${_timerSeconds}s',
                                  highlight: _timerSeconds > 0,
                                  onTap: () {
                                    setState(() {
                                      _timerSeconds = _timerSeconds == 0
                                          ? 3
                                          : (_timerSeconds == 3
                                                ? 5
                                                : (_timerSeconds == 5
                                                      ? 10
                                                      : 0));
                                    });

                                    _showAiTip(
                                      _timerSeconds == 0
                                          ? '⏱️ 計時器已關閉'
                                          : '⏱️ 計時器：$_timerSeconds 秒',
                                    );
                                  },
                                ),
                                _buildIOSControlItem(
                                  icon: Icons.hdr_auto,
                                  label: 'HDR',
                                  value: _hdrEnabled ? '開啟' : '關閉',
                                  highlight: _hdrEnabled,
                                  onTap: () {
                                    setState(() => _hdrEnabled = !_hdrEnabled);
                                    unawaited(
                                      _cameraAdapter.setHdrEnabled(_hdrEnabled),
                                    );
                                    _showAiTip(
                                      _hdrEnabled ? '☀️ HDR 已開啟' : '☀️ HDR 已關閉',
                                    );
                                  },
                                ),
                                _buildIOSControlItem(
                                  icon: Icons.tune,
                                  label: 'PRO',
                                  value: _proModeEnabled ? '開啟' : '設定',
                                  highlight: _proModeEnabled,
                                  onTap: _showProControls,
                                ),
                                _buildIOSControlItem(
                                  icon: Icons.straighten,
                                  label: '水平儀',
                                  value: _levelEnabled ? '開啟' : '關閉',
                                  highlight: _levelEnabled,
                                  onTap: () {
                                    setState(
                                      () => _levelEnabled = !_levelEnabled,
                                    );
                                    _showAiTip(
                                      _levelEnabled ? '📏 水平儀已開啟' : '📏 水平儀已關閉',
                                    );
                                  },
                                ),
                                _buildIOSControlItem(
                                  icon: _livePhotoEnabled
                                      ? Icons.motion_photos_on
                                      : Icons.motion_photos_off,
                                  label: '原況',
                                  value: _livePhotoEnabled ? '開啟' : '關閉',
                                  highlight: _livePhotoEnabled,
                                  onTap: () {
                                    setState(() {
                                      _livePhotoEnabled = !_livePhotoEnabled;
                                    });
                                    _showAiTip(
                                      _livePhotoEnabled
                                          ? '📸 原況照片已開啟'
                                          : '📸 原況照片已關閉',
                                    );
                                  },
                                ),
                                _buildIOSControlItem(
                                  icon: _flashMode == '開'
                                      ? Icons.flash_on
                                      : _flashMode == '關'
                                      ? Icons.flash_off
                                      : Icons.flash_auto,
                                  label: '閃光',
                                  value: _flashMode,
                                  highlight: _flashMode != '自動',
                                  onTap: () {
                                    final nextMode = _flashMode == '自動'
                                        ? '開'
                                        : _flashMode == '開'
                                        ? '關'
                                        : '自動';
                                    setState(() {
                                      _flashMode = nextMode;
                                    });
                                    unawaited(
                                      _cameraAdapter.setFlashMode(
                                        nextMode == '開'
                                            ? 'on'
                                            : nextMode == '關'
                                            ? 'off'
                                            : 'auto',
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // 3. AI 即時提示懸浮卡片
            if (_isRecording ||
                _activeUploadedVideo != null ||
                _aiTipMessage != null)
              Positioned(
                top: _isTopMenuExpanded ? 240 : 100,
                left: 24,
                right: 24,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _isRecording
                          ? Colors.redAccent
                          : (_activeUploadedVideo != null
                                ? Colors.orangeAccent
                                : Colors.yellowAccent.withValues(alpha: 0.8)),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isRecording
                            ? Icons.fiber_manual_record
                            : (_activeUploadedVideo != null
                                  ? Icons.movie
                                  : Icons.auto_awesome),
                        color: _isRecording
                            ? Colors.redAccent
                            : (_activeUploadedVideo != null
                                  ? Colors.orangeAccent
                                  : Colors.yellowAccent),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isRecording
                            ? '【錄影中】 時間: ${_formatDuration(_recordingSeconds)}'
                            : (_activeUploadedVideo != null
                                  ? '【上傳影片播放中】 點擊快門按鈕可讓 AI 抓拍'
                                  : _aiTipMessage!),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),

            // 4. 右側直列式預覽清單
            Positioned(
  right: 16,
  top: 160,
  bottom: 140,
  width: 70,
  child: _capturedImages.isEmpty && _recordedVideos.isEmpty
      ? const SizedBox.shrink()
      : Column(
          children: [
            IconButton(
              onPressed: _clearAllImages,
              icon: const Icon(
                Icons.delete_sweep,
                color: Colors.redAccent,
                size: 28,
              ),
              tooltip: '全部清除',
            ),
            const SizedBox(height: 4),

            Expanded(
              child: ListView.builder(
                itemCount:
                    _capturedImages.length + _recordedVideos.length,

                itemBuilder: (context, index) {
                  // =========================================================
                  // 照片
                  // =========================================================
                  if (index < _capturedImages.length) {
                    final itemPath = _capturedImages[index];
                    final imageFile = File(itemPath);
                    final bool isRealImage =
                        imageFile.existsSync();

                    return Dismissible(
                      key: Key(
                        'photo-$itemPath-$index',
                      ),
                      direction:
                          DismissDirection.horizontal,

                      // -----------------------------------------------------
                      // 右滑 → 保存
                      // -----------------------------------------------------
                      background: Container(
                        alignment: Alignment.centerLeft,
                        padding:
                            const EdgeInsets.only(left: 12),
                        decoration: BoxDecoration(
                          color: Colors.green,
                          borderRadius:
                              BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.save,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),

                      // -----------------------------------------------------
                      // 左滑 → 刪除
                      // -----------------------------------------------------
                      secondaryBackground: Container(
                        alignment: Alignment.centerRight,
                        padding:
                            const EdgeInsets.only(right: 12),
                        decoration: BoxDecoration(
                          color: Colors.red,
                          borderRadius:
                              BorderRadius.circular(10),
                        ),
                        child: const Icon(
                          Icons.delete,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),

                      confirmDismiss:
                          (direction) async {
                        // =========================================
                        // 左滑 → 刪除
                        // =========================================
                        if (direction ==
                            DismissDirection.endToStart) {
                          return true;
                        }

                        // =========================================
                        // 右滑 → 保存
                        // =========================================
                        if (direction ==
                            DismissDirection.startToEnd) {
                          if (!isRealImage) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(
                              const SnackBar(
                                content: Text(
                                  '⚠️ 此項目不是可保存的圖片檔案',
                                ),
                                duration:
                                    Duration(seconds: 1),
                              ),
                            );

                            return false;
                          }

                          debugPrint(
                            '========================================',
                          );
                          debugPrint(
                            '➡️ RIGHT SWIPE SAVE',
                          );
                          debugPrint(
                            '➡️ SOURCE: $itemPath',
                          );
                          debugPrint(
                            '➡️ EXISTS: ${imageFile.existsSync()}',
                          );

                          final savedSuccessfully =
                              await _saveCandidateToGallery(
                            itemPath,
                          );

                          debugPrint(
                            '➡️ SAVE RESULT: $savedSuccessfully',
                          );
                          debugPrint(
                            '========================================',
                          );

                          if (!savedSuccessfully) {
                            if (!context.mounted) {
                              return false;
                            }

                            ScaffoldMessenger.of(context)
                                .showSnackBar(
                              const SnackBar(
                                content: Text(
                                  '⚠️ 照片保存失敗',
                                ),
                                duration:
                                    Duration(seconds: 1),
                              ),
                            );

                            return false;
                          }

                          if (!context.mounted) {
                            return false;
                          }

                          ScaffoldMessenger.of(context)
                              .showSnackBar(
                            const SnackBar(
                              content: Text(
                                '✅ AI 精選照片已保存',
                              ),
                              duration:
                                  Duration(seconds: 1),
                            ),
                          );

                          // _saveCandidateToGallery()
                          // 已經從 _capturedImages 移除
                          return false;
                        }

                        return false;
                      },

                      onDismissed:
                          (direction) async {
                        if (direction !=
                            DismissDirection.endToStart) {
                          return;
                        }

                        if (!mounted) return;

                        // ---------------------------------------------------------
                        // 如果是 Live Photo
                        // 先刪除對應 MOV + 關聯資料
                        // ---------------------------------------------------------

                        await _deleteLivePhotoResources(
                          itemPath,
                        );

                        final file =
                            File(itemPath);

                        setState(() {
                          if (index <
                              _capturedImages.length) {
                            _capturedImages.removeAt(
                              index,
                            );
                          }
                        });

                        // ---------------------------------------------------------
                        // 刪除 Photo 實體檔案
                        // ---------------------------------------------------------

                        try {
                          if (await file.exists()) {
                            await file.delete();

                            debugPrint(
                              '🗑️ Deleted captured file: '
                              '${file.path}',
                            );
                          }
                        } catch (e) {
                          debugPrint(
                            '❌ Failed to delete captured file: $e',
                          );
                        }

                        // 更新 SharedPreferences
                        await _persistImageLists();

                        debugPrint(
                          '🗑️ Deleted captured image: $itemPath',
                        );
                      },

                      child: GestureDetector(
                          behavior: HitTestBehavior.opaque,

                          onTap: () {
                            _showEnlargedGallery(
                              index,
                            );
                          },
                     
                        child: Stack(
                          children: [
                            Container(
                              margin: const EdgeInsets.only(
                                bottom: 10,
                              ),
                              height: 70,
                              decoration: BoxDecoration(
                                color: Colors.grey[800],
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Colors.yellowAccent,
                                  width: 2,
                                ),
                              ),
                              child: isRealImage
                                  ? ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: Image.file(
                                        imageFile,
                                        width: double.infinity,
                                        height: double.infinity,
                                        fit: BoxFit.cover,
                                        errorBuilder: (
                                          context,
                                          error,
                                          stackTrace,
                                        ) {
                                          return const Icon(
                                            Icons.broken_image,
                                            color: Colors.redAccent,
                                            size: 26,
                                          );
                                        },
                                      ),
                                    )
                                  : Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          const Icon(
                                            Icons.image,
                                            size: 20,
                                            color: Colors.yellowAccent,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '#${index + 1}',
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 12,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                            ),
                            if (_isLivePhoto(itemPath))
                              Positioned(
                                top: 4,
                                right: 4,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 3,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black87,
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: Colors.white,
                                    ),
                                  ),
                                  child: const Text(
                                    'LIVE',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 10,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        )
                    );
                  }

                  // =========================================================
                  // 影片
                  // =========================================================

                  final videoIndex =
                      index - _capturedImages.length;

                  final videoPath =
                      _recordedVideos[videoIndex];

                  final videoFile =
                      File(videoPath);

                  return GestureDetector(
                    key: Key(
                      'video-$videoPath-$videoIndex',
                    ),

                    // -------------------------------------------------------
                    // 長按影片 → 放大預覽
                    // -------------------------------------------------------
                    onLongPress: () {
                      _showRecordedVideoPreview(
                        videoPath,
                      );
                    },

                    child: Container(
                      margin:
                          const EdgeInsets.only(
                        bottom: 10,
                      ),
                      height: 70,

                      decoration: BoxDecoration(
                        color: Colors.grey[900],
                        borderRadius:
                            BorderRadius.circular(10),
                        border: Border.all(
                          color: Colors.redAccent,
                          width: 2,
                        ),
                      ),

                      child: ClipRRect(
                        borderRadius:
                            BorderRadius.circular(8),

                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            // -------------------------------------------------
                            // 目前先使用黑底
                            // 下一步再換成影片第一幀縮圖
                            // -------------------------------------------------
                            Container(
                              color: Colors.black87,
                            ),

                            const Center(
                              child: Icon(
                                Icons.videocam,
                                color: Colors.white,
                                size: 28,
                              ),
                            ),

                            // -------------------------------------------------
                            // VIDEO 標籤
                            // -------------------------------------------------
                            Positioned(
                              left: 5,
                              bottom: 5,
                              child: Container(
                                padding:
                                    const EdgeInsets.symmetric(
                                  horizontal: 5,
                                  vertical: 2,
                                ),
                                decoration:
                                    BoxDecoration(
                                  color: Colors.black87,
                                  borderRadius:
                                      BorderRadius.circular(
                                    5,
                                  ),
                                ),
                                child: const Text(
                                  'VIDEO',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 8,
                                    fontWeight:
                                        FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),

                            // -------------------------------------------------
                            // 影片檔案不存在
                            // -------------------------------------------------
                            if (!videoFile.existsSync())
                              const Center(
                                child: Icon(
                                  Icons.error_outline,
                                  color:
                                      Colors.redAccent,
                                  size: 24,
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
),

            if (_captureAnimation)
              Positioned(
                right: 82,
                bottom: 150,
                child: IgnorePointer(
                  child: TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0.7, end: 1.0),
                    duration: const Duration(milliseconds: 450),
                    builder: (context, scale, child) =>
                        Transform.scale(scale: scale, child: child),
                    child: Container(
                      width: 64,
                      height: 64,
                      decoration: BoxDecoration(
                        border: Border.all(color: Colors.white, width: 2),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: const [
                          BoxShadow(color: Colors.black54, blurRadius: 8),
                        ],
                      ),
                      child: const Icon(
                        Icons.photo_camera,
                        color: Colors.white,
                        size: 28,
                      ),
                    ),
                  ),
                ),
              ),

            // 5. 下方控制區
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // 5.1 精簡版曝光刻度尺
                  if (_isExposureSliding &&
                      !_isRecording &&
                      _activeUploadedVideo == null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 14,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.yellowAccent,
                          width: 0.8,
                        ),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text(
                                '☀️ 曝光補償',
                                style: TextStyle(
                                  color: Colors.yellowAccent,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              Text(
                                '${_exposureValue >= 0 ? "+" : ""}${_exposureValue.toStringAsFixed(1)}EV',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              GestureDetector(
                                onTap: () =>
                                    setState(() => _isExposureSliding = false),
                                child: const Icon(
                                  Icons.close,
                                  color: Colors.white54,
                                  size: 16,
                                ),
                              ),
                            ],
                          ),
                          SizedBox(
                            width: 280,
                            height: 18,
                            child: CustomPaint(
                              size: const Size(280, 18),
                              painter: ExposureTicksPainter(
                                exposureValue: _exposureValue,
                              ),
                            ),
                          ),
                          SizedBox(
                            height: 24,
                            child: Slider(
                              value: _exposureValue,
                              min: -2.0,
                              max: 2.0,
                              divisions: 20,
                              activeColor: Colors.yellowAccent,
                              inactiveColor: Colors.white24,
                              onChanged: (val) {
                                setState(() {
                                  _exposureValue = val;
                                });
                                unawaited(_cameraAdapter.setExposure(val));
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                  // 5.3 互動式倍數列與滑動刻度尺
                  if (!_isRecording &&
                      !_isExposureSliding &&
                      !_isPaletteOpen &&
                      _activeUploadedVideo == null)
                    Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (_isZoomDragging) ...[
                          Text(
                            '${_zoomLevel.toStringAsFixed(1)}x',
                            style: const TextStyle(
                              color: Colors.yellowAccent,
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          SizedBox(
                            width: 300,
                            height: 26,
                            child: CustomPaint(
                              size: const Size(300, 26),
                              painter: ZoomTicksPainter(zoomLevel: _zoomLevel),
                            ),
                          ),
                          const SizedBox(height: 6),
                        ],

                        GestureDetector(
                          onHorizontalDragStart: (details) {
                            setState(() {
                              _isZoomDragging = true;
                              _baseZoom = _zoomLevel;
                            });
                          },
                          onHorizontalDragUpdate: (details) async {
                                final nextZoom = (_zoomLevel - details.primaryDelta! * 0.01)
                                    .clamp(0.5, 5.0)
                                    .toDouble();

                                final shouldUseUltraWide = nextZoom < 1.0;

                                setState(() {
                                  _zoomLevel = nextZoom;
                                });

                                // ---------------------------------------------------------------
                                // 跨過 1.0x 才切換實體鏡頭
                                // ---------------------------------------------------------------

                                if (shouldUseUltraWide != _isUltraWideActive &&
                                    !_cameraSwitching &&
                                    !_cameraInitializing) {
                                  setState(() {
                                    _cameraSwitching = true;
                                  });

                                  try {
                                    if (shouldUseUltraWide) {
                                      await _cameraAdapter.switchToUltraWide();
                                    } else {
                                      await _cameraAdapter.switchToStandardWide();
                                    }

                                    if (!mounted) return;

                                    setState(() {
                                      _isUltraWideActive = shouldUseUltraWide;
                                      _focusPoint = null;
                                      _isFocusVisible = false;
                                      _isAeAfLocked = false;
                                    });
                                  } catch (error) {
                                    if (mounted) {
                                      _showAiTip(
                                        shouldUseUltraWide
                                            ? '⚠️ 0.5x 廣角無法使用：$error'
                                            : '⚠️ 1x 廣角無法使用：$error',
                                      );
                                    }
                                  } finally {
                                    if (mounted) {
                                      setState(() {
                                        _cameraSwitching = false;
                                      });
                                    }
                                  }
                                }

                                // ---------------------------------------------------------------
                                // UI zoom → Native zoom
                                // ---------------------------------------------------------------

                                final nativeZoom = shouldUseUltraWide
                                    ? (nextZoom / 0.5).clamp(1.0, 5.0).toDouble()
                                    : nextZoom.clamp(1.0, 5.0).toDouble();

                                // 鏡頭切換期間不要把 zoom 套到舊鏡頭
                                if (_cameraSwitching) {
                                  return;
                                }

                                unawaited(
                                  _cameraAdapter.setZoom(nativeZoom),
                                );
                              },
                          onHorizontalDragEnd: (details) {
                            setState(() {
                              _isZoomDragging = false;
                            });
                          },
                          onHorizontalDragCancel: () {
                            setState(() {
                              _isZoomDragging = false;
                            });
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              vertical: 8,
                              horizontal: 24,
                            ),
                            color: Colors.transparent,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildLensLabelButton(
                                  '0.5x',
                                  _switchToUltraWide,
                                ),
                                const SizedBox(width: 14),
                                _buildZoomLabelButton(
                                  1.0,
                                  '1x',
                                  onSelected: _switchToStandardWide,
                                ),
                                const SizedBox(width: 14),
                                _buildZoomLabelButton(2.0, '2x'),
                                const SizedBox(width: 14),
                                _buildZoomLabelButton(3.0, '3x'),
                                const SizedBox(width: 14),
                                _buildZoomLabelButton(5.0, '5x'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (!_isRecording &&
                      !_isExposureSliding &&
                      !_isPaletteOpen &&
                      _activeUploadedVideo == null)
                    const SizedBox(height: 12),

                  // 5.4 拍攝模式切換列
                  if (!_isRecording &&
                      _activeUploadedVideo == null &&
                      _activeBottomAdjustment == null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: _modes.map((mode) {
                        final bool isSelected = _currentMode == mode;

                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              // 濾鏡 / 調色盤開啟時禁止切換模式
                              if (_activeBottomAdjustment != null) {
                                return;
                              }

                              setState(() {
                                _currentMode = mode;
                                _isTopMenuExpanded = false;
                                _isExposureSliding = false;
                                _isPaletteOpen = false;
                                _isPaletteEditing = false;
                              });

                              _showAiTip('✨ AI 已切換至 [$_currentMode] 模式');
                            },
                            child: AnimatedScale(
                              scale: isSelected ? 1.12 : 1.0,
                              duration: const Duration(milliseconds: 220),
                              curve: Curves.easeOutBack,
                              child: AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 180),
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.yellowAccent
                                      : Colors.white60,
                                  fontSize: 16,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                ),
                                child: Text(mode),
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  if (!_isRecording &&
                      _activeUploadedVideo == null &&
                      _activeBottomAdjustment == null)
                    const SizedBox(height: 20),

                  // 5.5 快門與快捷按鈕列
                  if (_activeBottomAdjustment != null &&
                      !_isRecording &&
                      _activeUploadedVideo == null)
                    _buildPalettePanel()
                  else
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 36.0),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          GestureDetector(
                            onTap: _showPhotoAlbum,
                            child: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                color: Colors.grey[800],
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: _savedImages.isNotEmpty
                                      ? Colors.yellowAccent
                                      : Colors.white,
                                  width: 1.5,
                                ),
                              ),
                              child: _savedImages.isEmpty
                                  ? const Icon(
                                      Icons.photo,
                                      color: Colors.white70,
                                    )
                                  : ClipRRect(
                                      borderRadius: BorderRadius.circular(6),
                                      child: Image.file(
                                        File(_savedImages.last),
                                        width: 50,
                                        height: 50,
                                        fit: BoxFit.cover,
                                        errorBuilder:
                                            (context, error, stackTrace) {
                                              return const Icon(
                                                Icons.broken_image,
                                                color: Colors.redAccent,
                                                size: 26,
                                              );
                                            },
                                      ),
                                    ),
                            ),
                          ),

                          GestureDetector(
                            onTap: _handleCaptureOrRecord,
                            child: Container(
                              width: 76,
                              height: 76,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: _currentMode == '影片'
                                      ? (_isRecording
                                            ? Colors.white
                                            : Colors.redAccent)
                                      : Colors.white,
                                  width: 4,
                                ),
                              ),
                              child: Container(
                                margin: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: _currentMode == '影片'
                                      ? (_isRecording
                                            ? Colors.white
                                            : Colors.red)
                                      : (_isCapturing
                                            ? Colors.red
                                            : Colors.white),
                                ),
                                child: _isRecording
                                    ? const Center(
                                        child: Icon(
                                          Icons.stop,
                                          color: Colors.white,
                                          size: 36,
                                        ),
                                      )
                                    : null,
                              ),
                            ),
                          ),
                          GestureDetector(
                            onTap: _switchCamera,
                            child: Container(
                              width: 50,
                              height: 50,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: Colors.grey[800]?.withValues(alpha: 0.6),
                              ),
                              child: _cameraSwitching
                                  ? const SizedBox(
                                      width: 20,
                                      height: 20,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.yellowAccent,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.cameraswitch,
                                      color: Colors.white,
                                      size: 26,
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZoomLabelButton(
    double targetZoom,
    String label, {
    VoidCallback? onSelected,
  }) {
    final bool isSelected = (_zoomLevel - targetZoom).abs() < 0.25;
    return GestureDetector(
      onTap: () {
        if (onSelected != null) {
          onSelected();
          return;
        }
        setState(() {
          _zoomLevel = targetZoom;
        });
        unawaited(_cameraAdapter.setZoom(targetZoom));
        _showAiTip('🔍 變焦倍數調整至：$label');
      },
      child: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.yellowAccent : Colors.white60,
          fontSize: 17,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
    );
  }

  Widget _buildLensLabelButton(String label, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Text(
        label,
        style: TextStyle(
          color: _isUltraWideActive ? Colors.yellowAccent : Colors.white60,
          fontSize: 17,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }

  Widget _buildIOSControlItem({
    required IconData icon,
    required String label,
    required String value,
    required VoidCallback onTap,
    VoidCallback? onLongPress,
    bool highlight = false,
  }) {
    return SizedBox(
      width: 72,
      child: GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: highlight
                    ? Colors.yellowAccent.withValues(alpha: 0.2)
                    : Colors.white10,
                shape: BoxShape.circle,
                border: Border.all(
                  color: highlight ? Colors.yellowAccent : Colors.transparent,
                  width: 1.5,
                ),
              ),
              child: Icon(
                icon,
                color: highlight ? Colors.yellowAccent : Colors.white,
                size: 20,
              ),
            ),
            const SizedBox(height: 4),
            SizedBox(
              height: 18,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: TextStyle(
                    color: highlight ? Colors.yellowAccent : Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// 調色盤方形色彩區繪製器
class PaletteSquarePainter extends CustomPainter {
  final Color paletteColor;

  PaletteSquarePainter({required this.paletteColor});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;

    final base = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: 0.92),
          paletteColor,
          Color.lerp(paletteColor, Colors.black, 0.62)!,
        ],
      ).createShader(rect);

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      base,
    );

    final saturation = Paint()
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [Colors.white.withValues(alpha: 0.85), Colors.transparent],
      ).createShader(rect);

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      saturation,
    );

    final vignette = Paint()
      ..shader = RadialGradient(
        center: Alignment.center,
        radius: 0.85,
        colors: [Colors.transparent, Colors.black.withValues(alpha: 0.28)],
      ).createShader(rect);

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      vignette,
    );

    final border = Paint()
      ..color = Colors.white.withValues(alpha: 0.45)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(10)),
      border,
    );
  }

  @override
  bool shouldRepaint(covariant PaletteSquarePainter oldDelegate) {
    return oldDelegate.paletteColor != paletteColor;
  }
}

// 曝光刻度尺繪製器
class ExposureTicksPainter extends CustomPainter {
  final double exposureValue;

  ExposureTicksPainter({required this.exposureValue});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1.0;

    const double minExp = -2.0;
    const double maxExp = 2.0;

    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint..color = Colors.white24,
    );

    for (double e = minExp; e <= maxExp + 0.001; e += 0.2) {
      double roundedE = double.parse(e.toStringAsFixed(1));
      bool isKey =
          (roundedE == -2.0 ||
          roundedE == -1.0 ||
          roundedE == 0.0 ||
          roundedE == 1.0 ||
          roundedE == 2.0);

      double t = (roundedE - minExp) / (maxExp - minExp);
      double x = t * size.width;

      double tickHeight = isKey ? 12.0 : 6.0;
      bool isCurrent = (exposureValue - roundedE).abs() < 0.11;

      Paint currentPaint = Paint()
        ..color = isCurrent
            ? Colors.yellowAccent
            : (isKey ? Colors.white70 : Colors.white38)
        ..strokeWidth = isCurrent ? 2.0 : 1.0;

      canvas.drawLine(
        Offset(x, (size.height - tickHeight) / 2),
        Offset(x, (size.height + tickHeight) / 2),
        currentPaint,
      );
    }

    double currentT = (exposureValue - minExp) / (maxExp - minExp);
    double currentX = (currentT * size.width).clamp(0.0, size.width);

    final indicatorPaint = Paint()
      ..color = Colors.yellowAccent
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(currentX, 1);
    path.lineTo(currentX - 4, -4);
    path.lineTo(currentX + 4, -4);
    path.close();
    canvas.drawPath(path, indicatorPaint);
  }

  @override
  bool shouldRepaint(covariant ExposureTicksPainter oldDelegate) {
    return oldDelegate.exposureValue != exposureValue;
  }
}

// 風格刻度尺繪製器
class StyleTicksPainter extends CustomPainter {
  final double value;

  StyleTicksPainter({required this.value});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1.0;

    const double minValue = -1.0;
    const double maxValue = 1.0;

    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint..color = Colors.white24,
    );

    for (double v = minValue; v <= maxValue + 0.001; v += 0.1) {
      double roundedV = double.parse(v.toStringAsFixed(1));
      bool isKey =
          (roundedV == -1.0 ||
          roundedV == -0.5 ||
          roundedV == 0.0 ||
          roundedV == 0.5 ||
          roundedV == 1.0);

      double t = (roundedV - minValue) / (maxValue - minValue);
      double x = t * size.width;

      double tickHeight = isKey ? 12.0 : 6.0;
      bool isCurrent = (value - roundedV).abs() < 0.06;

      Paint currentPaint = Paint()
        ..color = isCurrent
            ? Colors.yellowAccent
            : (isKey ? Colors.white70 : Colors.white38)
        ..strokeWidth = isCurrent ? 2.0 : 1.0;

      canvas.drawLine(
        Offset(x, (size.height - tickHeight) / 2),
        Offset(x, (size.height + tickHeight) / 2),
        currentPaint,
      );
    }

    double currentT = (value - minValue) / (maxValue - minValue);
    double currentX = (currentT * size.width).clamp(0.0, size.width);

    final indicatorPaint = Paint()
      ..color = Colors.yellowAccent
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(currentX, 1);
    path.lineTo(currentX - 4, -4);
    path.lineTo(currentX + 4, -4);
    path.close();
    canvas.drawPath(path, indicatorPaint);
  }

  @override
  bool shouldRepaint(covariant StyleTicksPainter oldDelegate) {
    return oldDelegate.value != value;
  }
}

// 變焦刻度尺繪製器
class ZoomTicksPainter extends CustomPainter {
  final double zoomLevel;

  ZoomTicksPainter({required this.zoomLevel});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.white38
      ..strokeWidth = 1.0;

    const double minZoom = 0.5;
    const double maxZoom = 5.0;
    const double visibleRange = 3.0;
    final viewportMin = (zoomLevel - visibleRange / 2).clamp(
      minZoom,
      maxZoom - visibleRange,
    );
    final viewportMax = viewportMin + visibleRange;

    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint..color = Colors.white24,
    );

    for (double z = minZoom; z <= maxZoom + 0.001; z += 0.1) {
      double roundedZ = double.parse(z.toStringAsFixed(1));
      bool isMajor = (roundedZ * 10) % 5 == 0;
      bool isKey =
          (roundedZ == 0.5 ||
          roundedZ == 1.0 ||
          roundedZ == 2.0 ||
          roundedZ == 3.0 ||
          roundedZ == 5.0);

      if (roundedZ < viewportMin - 0.001 || roundedZ > viewportMax + 0.001) {
        continue;
      }
      double t = (roundedZ - viewportMin) / (viewportMax - viewportMin);
      double x = t * size.width;

      double tickHeight = isKey ? 18.0 : (isMajor ? 12.0 : 6.0);
      bool isCurrent = (zoomLevel - roundedZ).abs() < 0.06;

      Paint currentPaint = Paint()
        ..color = isCurrent
            ? Colors.yellowAccent
            : (isKey ? Colors.white70 : Colors.white38)
        ..strokeWidth = isCurrent ? 2.5 : (isKey ? 1.5 : 1.0);

      canvas.drawLine(
        Offset(x, (size.height - tickHeight) / 2),
        Offset(x, (size.height + tickHeight) / 2),
        currentPaint,
      );
    }

    double currentT = (zoomLevel - viewportMin) / (viewportMax - viewportMin);
    double currentX = (currentT * size.width).clamp(0.0, size.width);

    final indicatorPaint = Paint()
      ..color = Colors.yellowAccent
      ..style = PaintingStyle.fill;

    final path = Path();
    path.moveTo(currentX, 2);
    path.lineTo(currentX - 5, -5);
    path.lineTo(currentX + 5, -5);
    path.close();
    canvas.drawPath(path, indicatorPaint);
  }

  @override
  bool shouldRepaint(covariant ZoomTicksPainter oldDelegate) {
    return oldDelegate.zoomLevel != zoomLevel;
  }
}

// 構圖線繪製器
class CompositionGridPainter extends CustomPainter {
  final String gridType;

  CompositionGridPainter(this.gridType);

  @override
  void paint(Canvas canvas, Size size) {
    if (gridType == '關閉') return;

    final paint = Paint()
      ..color = Colors.white.withValues(alpha: 0.35)
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    if (gridType == '九宮格') {
      canvas.drawLine(
        Offset(size.width / 3, 0),
        Offset(size.width / 3, size.height),
        paint,
      );
      canvas.drawLine(
        Offset(size.width * 2 / 3, 0),
        Offset(size.width * 2 / 3, size.height),
        paint,
      );
      canvas.drawLine(
        Offset(0, size.height / 3),
        Offset(size.width, size.height / 3),
        paint,
      );
      canvas.drawLine(
        Offset(0, size.height * 2 / 3),
        Offset(size.width, size.height * 2 / 3),
        paint,
      );
    } else if (gridType == '黃金比例') {
      final w1 = size.width * 0.382;
      final w2 = size.width * 0.618;
      final h1 = size.height * 0.382;
      final h2 = size.height * 0.618;

      canvas.drawLine(Offset(w1, 0), Offset(w1, size.height), paint);
      canvas.drawLine(Offset(w2, 0), Offset(w2, size.height), paint);
      canvas.drawLine(Offset(0, h1), Offset(size.width, h1), paint);
      canvas.drawLine(Offset(0, h2), Offset(size.width, h2), paint);
    } else if (gridType == '對角線') {
      canvas.drawLine(Offset(0, 0), Offset(size.width, size.height), paint);
      canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), paint);
    } else if (gridType == '中心十字') {
      final center = Offset(size.width / 2, size.height / 2);
      canvas.drawLine(
        Offset(center.dx, 0),
        Offset(center.dx, size.height),
        paint,
      );
      canvas.drawLine(
        Offset(0, center.dy),
        Offset(size.width, center.dy),
        paint,
      );
    } else if (gridType == '安全框') {
      final safeRect = Rect.fromLTWH(
        size.width * 0.08,
        size.height * 0.08,
        size.width * 0.84,
        size.height * 0.84,
      );
      canvas.drawRect(safeRect, paint);
      final innerRect = Rect.fromLTWH(
        size.width * 0.16,
        size.height * 0.16,
        size.width * 0.68,
        size.height * 0.68,
      );
      canvas.drawRect(innerRect, paint..color = Colors.white24);
    } else if (gridType == '智能構圖') {
      final aiPaint = Paint()
        ..color = Colors.yellowAccent.withValues(alpha: 0.6)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      const double margin = 48.0;
      const double bracketLen = 30.0;

      canvas.drawLine(
        Offset(margin, margin + bracketLen),
        Offset(margin, margin),
        aiPaint,
      );
      canvas.drawLine(
        Offset(margin, margin),
        Offset(margin + bracketLen, margin),
        aiPaint,
      );

      canvas.drawLine(
        Offset(size.width - margin - bracketLen, margin),
        Offset(size.width - margin, margin),
        aiPaint,
      );
      canvas.drawLine(
        Offset(size.width - margin, margin),
        Offset(size.width - margin, margin + bracketLen),
        aiPaint,
      );

      canvas.drawLine(
        Offset(margin, size.height - margin - bracketLen),
        Offset(margin, size.height - margin),
        aiPaint,
      );
      canvas.drawLine(
        Offset(margin, size.height - margin),
        Offset(margin + bracketLen, size.height - margin),
        aiPaint,
      );

      canvas.drawLine(
        Offset(size.width - margin - bracketLen, size.height - margin),
        Offset(size.width - margin, size.height - margin),
        aiPaint,
      );
      canvas.drawLine(
        Offset(size.width - margin, size.height - margin),
        Offset(size.width - margin, size.height - margin - bracketLen),
        aiPaint,
      );

      final double cx = size.width / 2;
      final double cy = size.height / 2;
      const double crossLen = 12.0;

      canvas.drawLine(Offset(cx - crossLen, cy), Offset(cx - 4, cy), aiPaint);
      canvas.drawLine(Offset(cx + 4, cy), Offset(cx + crossLen, cy), aiPaint);
      canvas.drawLine(Offset(cx, cy - crossLen), Offset(cx, cy - 4), aiPaint);
      canvas.drawLine(Offset(cx, cy + 4), Offset(cx, cy + crossLen), aiPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return oldDelegate != this;
  }
}

class LivePhotoIconPainter extends CustomPainter {
  final Color color;

  LivePhotoIconPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);

    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..strokeCap = StrokeCap.round;

    // 外圍圓環
    canvas.drawCircle(center, size.width * 0.38, paint);

    // 中央圓
    canvas.drawCircle(center, size.width * 0.18, paint);

    // 中央實心點
    final dotPaint = Paint()
      ..color = color
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, size.width * 0.07, dotPaint);
  }

  @override
  bool shouldRepaint(covariant LivePhotoIconPainter oldDelegate) {
    return oldDelegate.color != color;
  }
}

class _HistogramPainter extends CustomPainter {
  final List<int> bins;

  const _HistogramPainter(this.bins);

  @override
  void paint(Canvas canvas, Size size) {
    if (bins.isEmpty) return;
    final maximum = bins.reduce((a, b) => a > b ? a : b);
    if (maximum == 0) return;
    final paint = Paint()
      ..color = Colors.greenAccent.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final path = Path();
    for (var i = 0; i < bins.length; i++) {
      final x = i / (bins.length - 1) * size.width;
      final y = size.height - bins[i] / maximum * size.height;
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _HistogramPainter oldDelegate) {
    return oldDelegate.bins != bins;
  }
}
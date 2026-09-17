import 'dart:async';
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

void main() {
  runApp(const AICameraApp());
}

class MyCustomScrollBehavior extends MaterialScrollBehavior {
  @override
  Set<PointerDeviceKind> get dragDevices => {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
      };
}

class AICameraApp extends StatelessWidget {
  const AICameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AI 智慧相機',
      theme: ThemeData.dark(),
      scrollBehavior: MyCustomScrollBehavior(),
      home: const IOSCameraPage(),
    );
  }
}

class IOSCameraPage extends StatefulWidget {
  const IOSCameraPage({super.key});

  @override
  State<IOSCameraPage> createState() => _IOSCameraPageState();
}

class _IOSCameraPageState extends State<IOSCameraPage> {
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  String _currentMode = '拍照'; // 影片、拍照、物景
  bool _isCapturing = false;
  
  bool _isRecording = false;
  int _recordingSeconds = 0;
  Timer? _recordingTimer;

  // 上傳影片播放與抓拍相關狀態
  String? _activeUploadedVideo; // 有值代表正在預覽上傳的影片
  bool _isVideoPlaying = false;
  double _videoProgress = 0.0; // 0.0 ~ 1.0
  Timer? _videoPlaybackTimer;

  final List<String> _capturedImages = [];
  
  String? _aiTipMessage;
  Timer? _aiTipTimer;

  // 構圖線狀態
  String _compositionGrid = '關閉';

  // iOS 相機進階設定狀態
  bool _isTopMenuExpanded = false;
  String _flashMode = '自動';       // 自動、開啟、關閉
  String _aspectRatio = '4:3';    // 4:3、16:9、1:1
  
  // 濾鏡與風格分離
  String _filterMode = '原味';      // 固定濾鏡：原味、鮮明、溫暖、冷色、復古
  double _styleTone = 0.0;        // 自訂風格：色調 (-1.0 ~ 1.0)
  double _styleTemp = 0.0;        // 自訂風格：色溫 (-1.0 ~ 1.0)
  bool _isStyleSliding = false;   // 下方是否正在顯示風格刻度尺
  String _styleActiveTab = '色調';  // '色調' 或 '色溫'

  // 曝光狀態
  bool _isExposureAuto = true;
  double _exposureValue = 0.0;    // -2.0 ~ 2.0
  bool _isExposureSliding = false; // 下方是否正在顯示曝光刻度

  bool _nightMode = false;        // 夜間模式

  // AI 智慧連拍與新設定狀態
  bool _aiDirectorMode = false;   // AI 導演模式
  bool _aiBurstEnabled = true;    // AI 智慧連拍開關（已修復：實際於 UI 與邏輯中使用）[cite: 2]
  int _aiBurstSeconds = 3;        // 抓拍時間：3秒、5秒
  int _aiBurstCount = 5;          // 抓拍張數：3、5、7、10張
  int _passingScore = 3;          // 合格分數：1 ~ 5
  String _aiPromptText = '';      // 提示詞關鍵字
  String? _referencePhotoName;    // 參考照片名稱
  
  // 個人化 AI 權重設定
  final Map<String, double> _aiWeights = {
    '構圖美感': 1.0,
    '光影表現': 1.0,
    '人物表情': 1.0,
    '色彩氛圍': 1.0,
  };

  // 💡 已修復：使用安全的一行內初始化，徹底解決 LateInitializationError
  late final TextEditingController _promptController = TextEditingController(text: _aiPromptText);

  // 縮放倍數狀態
  double _zoomLevel = 1.0;
  double _baseZoom = 1.0;
  bool _isZoomDragging = false;

  final List<String> _modes = ['影片', '拍照', '物景'];

  @override
  void initState() {
    super.initState();
    // 提示詞控制器已在宣告時透過行內初始化完成，此處無需重複賦值
  }

  @override
  void dispose() {
    _recordingTimer?.cancel();
    _videoPlaybackTimer?.cancel();
    _aiTipTimer?.cancel();
    _promptController.dispose();
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

  void _handleHorizontalDrag(DragEndDetails details) {
    if (_isRecording || _activeUploadedVideo != null) return;

    int currentIndex = _modes.indexOf(_currentMode);
    if (details.primaryVelocity! < 0) {
      if (currentIndex < _modes.length - 1) {
        setState(() {
          _currentMode = _modes[currentIndex + 1];
          _isTopMenuExpanded = false;
        });
        _showAiTip('✨ AI 已自動切換至 [$_currentMode] 模式');
      }
    } else if (details.primaryVelocity! > 0) {
      if (currentIndex > 0) {
        setState(() {
          _currentMode = _modes[currentIndex - 1];
          _isTopMenuExpanded = false;
        });
        _showAiTip('✨ AI 已自動切換至 [$_currentMode] 模式');
      }
    }
  }

  // 上傳影片按鈕事件
  void _handleUploadVideo() {
    setState(() {
      _activeUploadedVideo = '上傳影片 ${_capturedImages.length + 1} (0:32)';
      _isVideoPlaying = true;
      _videoProgress = 0.0;
      _isTopMenuExpanded = false;
    });
    _startVideoPlaybackSimulation();
    _showAiTip('📤 成功匯入影片！預覽區已切換為影片播放與進度控制');
  }

  // 退出影片預覽
  void _exitUploadedVideo() {
    _videoPlaybackTimer?.cancel();
    setState(() {
      _activeUploadedVideo = null;
      _isVideoPlaying = false;
      _videoProgress = 0.0;
    });
    _showAiTip('↩️ 已退出影片預覽模式');
  }

  void _startVideoPlaybackSimulation() {
    _videoPlaybackTimer?.cancel();
    _videoPlaybackTimer = Timer.periodic(const Duration(milliseconds: 200), (timer) {
      if (!mounted || !_isVideoPlaying || _activeUploadedVideo == null) return;
      setState(() {
        _videoProgress += 0.01;
        if (_videoProgress >= 1.0) {
          _videoProgress = 0.0; // 循環播放
        }
      });
    });
  }

  void _handleCaptureOrRecord() {
    setState(() {
      _isTopMenuExpanded = false;
      _isExposureSliding = false;
      _isStyleSliding = false;
    });

    // 如果當前正在預覽上傳的影片，按下快門代表「AI 進行抓拍」
    if (_activeUploadedVideo != null) {
      setState(() {
        _isCapturing = true;
      });
      _showAiTip('🤖 AI 正在根據設定從影片中智慧抓拍...');

      Future.delayed(const Duration(milliseconds: 600), () {
        if (mounted) {
          setState(() {
            _isCapturing = false;
            _capturedImages.add('影片抓拍畫面 ${_capturedImages.length + 1}');
          });
          _showAiTip('✅ AI 成功從影片抓拍精選畫面並存入預覽！');
        }
      });
      return;
    }

    if (_currentMode == '影片') {
      if (!_isRecording) {
        setState(() {
          _isRecording = true;
          _recordingSeconds = 0;
        });
        _recordingTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
          setState(() {
            _recordingSeconds++;
          });
        });
        _showAiTip('🔴 AI 智慧自動跟拍與防手震已啟動');
      } else {
        _recordingTimer?.cancel();
        setState(() {
          _isRecording = false;
          _capturedImages.add('影片 ${_capturedImages.length + 1} (${_formatDuration(_recordingSeconds)})');
        });
        _showAiTip('✅ 影片已錄製完成並存入預覽');
      }
    } else {
      setState(() {
        _isCapturing = true;
      });

      // 💡 實際運用 _aiBurstEnabled 狀態邏輯
      if (!_aiBurstEnabled) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (mounted) {
            setState(() {
              _isCapturing = false;
              _capturedImages.add('一般單拍相片 ${_capturedImages.length + 1}');
            });
            _showAiTip('✅ 拍照完成！');
          }
        });
        return;
      }

      _showAiTip('🤖 AI 導演評分中 (目標合格分數: $_passingScore 分)... 正在連續抓拍 $_aiBurstCount 張照片');

      int capturedSoFar = 0;
      final intervalMs = (_aiBurstSeconds * 1000) ~/ _aiBurstCount;
      Timer.periodic(Duration(milliseconds: intervalMs > 0 ? intervalMs : 200), (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }
        capturedSoFar++;
        setState(() {
          _capturedImages.add('AI評分抓拍 ${_capturedImages.length + 1}');
        });

        if (capturedSoFar >= _aiBurstCount) {
          timer.cancel();
          setState(() {
            _isCapturing = false;
          });
          _showAiTip('✅ 達到合格分數 ($_passingScore分)！AI 成功完成 $_aiBurstCount 張智慧抓拍！');
        }
      });
    }
  }

  String _formatDuration(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _clearAllImages() {
    setState(() {
      _capturedImages.clear();
    });
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
          title: Text(title, style: const TextStyle(color: Colors.white, fontSize: 16), textAlign: TextAlign.center),
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
                        color: isSelected ? Colors.yellowAccent.withValues(alpha: 0.3) : Colors.white10,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected ? Colors.yellowAccent : Colors.transparent,
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
                        color: isSelected ? Colors.yellowAccent : Colors.white70,
                        fontSize: 12,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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

  void _showFlashSelectDialog() {
    _showCircularOptionsDialog(
      title: '選擇閃光燈模式',
      currentValue: _flashMode,
      options: [
        {'label': '自動', 'icon': Icons.flash_auto, 'value': '自動'},
        {'label': '開啟', 'icon': Icons.flash_on, 'value': '開啟'},
        {'label': '關閉', 'icon': Icons.flash_off, 'value': '關閉'},
      ],
      onSelected: (val) {
        setState(() => _flashMode = val);
        _showAiTip('⚡ 閃光燈模式: $_flashMode');
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

  void _showFilterSelectDialog() {
    _showCircularOptionsDialog(
      title: '選擇固定濾鏡',
      currentValue: _filterMode,
      options: [
        {'label': '原味', 'icon': Icons.filter_b_and_w, 'value': '原味'},
        {'label': '鮮明', 'icon': Icons.flare, 'value': '鮮明'},
        {'label': '溫暖', 'icon': Icons.wb_sunny, 'value': '溫暖'},
        {'label': '冷色', 'icon': Icons.ac_unit, 'value': '冷色'},
        {'label': '復古', 'icon': Icons.history, 'value': '復古'},
      ],
      onSelected: (val) {
        setState(() => _filterMode = val);
        _showAiTip('🎨 濾鏡風格: $_filterMode');
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
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: const Row(
                children: [
                  Icon(Icons.tune, color: Colors.yellowAccent),
                  SizedBox(width: 8),
                  Text('個人化 AI 權重設定', style: TextStyle(color: Colors.white, fontSize: 18)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('調整 AI 評分選項的權重比例：', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  const SizedBox(height: 12),
                  ..._aiWeights.keys.map((key) {
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(key, style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                            Text('${(_aiWeights[key]! * 100).toInt()}%', style: const TextStyle(color: Colors.yellowAccent, fontSize: 13)),
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
                      label: const Text('重置所有權重', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                      style: TextButton.styleFrom(
                        backgroundColor: Colors.redAccent.withValues(alpha: 0.1),
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('完成', style: TextStyle(color: Colors.yellowAccent, fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showEnlargedGallery(int initialIndex) {
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            if (_capturedImages.isEmpty) {
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (Navigator.canPop(dialogContext)) {
                  Navigator.pop(dialogContext);
                }
              });
              return const SizedBox.shrink();
            }

            int safeIndex = initialIndex >= _capturedImages.length ? _capturedImages.length - 1 : initialIndex;
            final PageController verticalController = PageController(initialPage: safeIndex);

            return Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onTap: () => Navigator.pop(dialogContext),
                    child: Container(
                      color: Colors.black.withValues(alpha: 0.95),
                    ),
                  ),
                ),
                Positioned.fill(
                  child: PageView.builder(
                    scrollDirection: Axis.vertical,
                    controller: verticalController,
                    itemCount: _capturedImages.length,
                    itemBuilder: (context, index) {
                      final itemName = _capturedImages[index];
                      final bool isVideo = itemName.contains('影片');

                      return Center(
                        child: GestureDetector(
                          onTap: () {},
                          child: Dismissible(
                            key: Key('enlarged-$index-${_capturedImages.length}-$itemName'),
                            direction: DismissDirection.horizontal,
                            background: Container(
                              alignment: Alignment.centerLeft,
                              padding: const EdgeInsets.only(left: 30),
                              decoration: BoxDecoration(
                                color: Colors.green,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Row(
                                children: [
                                  Icon(Icons.save, color: Colors.white, size: 30),
                                  SizedBox(width: 8),
                                  Text('保存', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ),
                            secondaryBackground: Container(
                              alignment: Alignment.centerRight,
                              padding: const EdgeInsets.only(right: 30),
                              decoration: BoxDecoration(
                                color: Colors.red,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: const Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  Text('刪除', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
                                  SizedBox(width: 8),
                                  Icon(Icons.delete, color: Colors.white, size: 30),
                                ],
                              ),
                            ),
                            confirmDismiss: (direction) async {
                              if (direction == DismissDirection.endToStart) {
                                setState(() {
                                  _capturedImages.removeAt(index);
                                });
                                setStateDialog(() {});

                                if (_capturedImages.isEmpty) {
                                  WidgetsBinding.instance.addPostFrameCallback((_) {
                                    if (Navigator.canPop(dialogContext)) {
                                      Navigator.pop(dialogContext);
                                    }
                                  });
                                }
                                return false;
                              } else {
                                ScaffoldMessenger.of(dialogContext).showSnackBar(
                                  SnackBar(
                                    content: Text('✅ 已成功保存 $itemName！'),
                                    duration: const Duration(seconds: 1),
                                  ),
                                );
                                return false;
                              }
                            },
                            child: Container(
                              width: 320,
                              height: 440,
                              decoration: BoxDecoration(
                                color: Colors.grey[900],
                                borderRadius: BorderRadius.circular(20),
                                border: Border.all(color: Colors.yellowAccent, width: 2),
                              ),
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    isVideo ? Icons.videocam : Icons.image,
                                    size: 90,
                                    color: Colors.yellowAccent,
                                  ),
                                  const SizedBox(height: 20),
                                  Text(
                                    itemName,
                                    style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 10),
                                  Text(
                                    '(${index + 1} / ${_capturedImages.length})',
                                    style: const TextStyle(color: Colors.yellowAccent, fontSize: 16),
                                  ),
                                  const SizedBox(height: 30),
                                  const Text(
                                    '⬆️⬇️ 上下滑動切換照片/影片\n⬅️ 左滑刪除  |  ➡️ 右滑保存\n(點擊旁邊空白處退出放大)',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(color: Colors.white54, fontSize: 12),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                Positioned(
                  top: 40,
                  right: 20,
                  child: IconButton(
                    icon: const Icon(Icons.close, color: Colors.white, size: 32),
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                ),
              ],
            );
          },
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
                      Text('AI 智慧相機設定', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
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
                title: const Text('AI 導演模式', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text('由 AI 分析預覽畫面給拍照者引導', style: TextStyle(color: Colors.white54, fontSize: 12)),
                value: _aiDirectorMode,
                activeThumbColor: Colors.yellowAccent,
                onChanged: (val) {
                  setState(() => _aiDirectorMode = val);
                  _showAiTip(val ? '🎬 AI 導演模式已啟動（提供即時構圖與姿勢指引）' : '🎬 AI 導演模式已關閉');
                },
              ),
              const Divider(color: Colors.white24, height: 24),

              // 1.2 AI 智慧連拍開關（已修復：實際使用變數以消除未使用警告）[cite: 2]
              SwitchListTile(
                title: const Text('AI 智慧連拍功能', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text('按下快門時啟動自動多張智慧抓拍', style: TextStyle(color: Colors.white54, fontSize: 12)),
                value: _aiBurstEnabled,
                activeThumbColor: Colors.yellowAccent,
                onChanged: (val) {
                  setState(() => _aiBurstEnabled = val);
                  _showAiTip(val ? '⚡ AI 智慧連拍已啟動' : '⚡ AI 智慧連拍已關閉（改為單張拍攝）');
                },
              ),
              const Divider(color: Colors.white24, height: 24),

              // 2. AI 抓拍與評分設定
              const Text('📸 AI 抓拍與評分設定', style: TextStyle(color: Colors.yellowAccent, fontSize: 15, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              
              const Text('⏱️ 抓拍時間', style: TextStyle(color: Colors.white70, fontSize: 13)),
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
                    labelStyle: TextStyle(color: selected ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
                    onSelected: (bool selected) {
                      if (selected) {
                        setState(() => _aiBurstSeconds = sec);
                      }
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 12),

              const Text('🔢 抓拍張數', style: TextStyle(color: Colors.white70, fontSize: 13)),
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
                    labelStyle: TextStyle(color: selected ? Colors.black : Colors.white, fontWeight: FontWeight.bold),
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
                  const Text('⭐ 合格分數 (門檻)', style: TextStyle(color: Colors.white70, fontSize: 13)),
                  Text('$_passingScore 分', style: const TextStyle(color: Colors.yellowAccent, fontWeight: FontWeight.bold, fontSize: 14)),
                ],
              ),
              const Text('（透過 AI 抓拍評分，到達此分數才會正式拍下）', style: TextStyle(color: Colors.white38, fontSize: 11)),
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

              const Text('💬 提示詞 (關鍵字引導)', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 6),
              TextField(
                controller: _promptController,
                style: const TextStyle(color: Colors.white, fontSize: 14),
                decoration: InputDecoration(
                  hintText: '輸入如 海邊夏日風、文青氣息...',
                  hintStyle: const TextStyle(color: Colors.white38),
                  filled: true,
                  fillColor: Colors.grey[800],
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                ),
                onChanged: (val) {
                  _aiPromptText = val;
                },
              ),
              const SizedBox(height: 16),

              const Text('🖼️ 參考照片風格', style: TextStyle(color: Colors.white70, fontSize: 13)),
              const SizedBox(height: 6),
              ElevatedButton.icon(
                onPressed: () {
                  setState(() {
                    _referencePhotoName = '風格範本_${DateTime.now().second}.jpg';
                  });
                  _showAiTip('✅ 已上傳參考照片風格，AI 將以此分析指引構圖');
                },
                icon: const Icon(Icons.upload_file, color: Colors.black),
                label: Text(_referencePhotoName ?? '上傳想拍出的照片風格', style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.yellowAccent,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  minimumSize: const Size(double.infinity, 40),
                ),
              ),
              const Divider(color: Colors.white24, height: 30),

              // 3. 個人化 AI 設定
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.tune, color: Colors.yellowAccent),
                title: const Text('個人化 AI 權重與重置', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text('設定評分選項權重與重置', style: TextStyle(color: Colors.white54, fontSize: 12)),
                trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 16),
                onTap: _showPersonalizedAiDialog,
              ),
            ],
          ),
        ),
      ),
      body: GestureDetector(
        onHorizontalDragEnd: _handleHorizontalDrag,
        onScaleStart: (details) {
          _baseZoom = _zoomLevel;
        },
        onScaleUpdate: (details) {
          setState(() {
            _zoomLevel = (_baseZoom * details.scale).clamp(0.5, 5.0);
          });
        },
        child: Stack(
          children: [
            // 1. 背景：相機即時預覽區 或 獨立的上傳影片播放預覽區
            Positioned.fill(
              child: Container(
                color: Colors.grey[900],
                child: Stack(
                  children: [
                    Center(
                      child: _activeUploadedVideo != null
                          ? Stack(
                              children: [
                                Positioned.fill(
                                  child: Container(
                                    color: Colors.black,
                                    child: Column(
                                      mainAxisAlignment: MainAxisAlignment.center,
                                      children: [
                                        Icon(
                                          _isVideoPlaying ? Icons.play_circle_filled : Icons.pause_circle_filled,
                                          color: Colors.yellowAccent,
                                          size: 64,
                                        ),
                                        const SizedBox(height: 12),
                                        Text(
                                          _activeUploadedVideo!,
                                          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                                Positioned(
                                  left: 24,
                                  right: 24,
                                  bottom: 130,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    decoration: BoxDecoration(
                                      color: Colors.black.withValues(alpha: 0.65),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(color: Colors.yellowAccent.withValues(alpha: 0.4), width: 1),
                                    ),
                                    child: Row(
                                      children: [
                                        IconButton(
                                          icon: Icon(
                                            _isVideoPlaying ? Icons.pause : Icons.play_arrow,
                                            color: Colors.yellowAccent,
                                          ),
                                          onPressed: () {
                                            setState(() {
                                              _isVideoPlaying = !_isVideoPlaying;
                                            });
                                            _showAiTip(_isVideoPlaying ? '▶️ 影片繼續播放' : '⏸️ 影片已暫停');
                                          },
                                        ),
                                        Expanded(
                                          child: Slider(
                                            value: _videoProgress,
                                            min: 0.0,
                                            max: 1.0,
                                            activeColor: Colors.yellowAccent,
                                            inactiveColor: Colors.white24,
                                            onChanged: (val) {
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
                                    icon: const Icon(Icons.close, color: Colors.white, size: 28),
                                    onPressed: _exitUploadedVideo,
                                    tooltip: '退出影片預覽',
                                  ),
                                ),
                              ],
                            )
                          : Transform.scale(
                              scale: _zoomLevel,
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    _currentMode == '影片' ? Icons.videocam : Icons.camera_alt,
                                    color: Colors.white38,
                                    size: 48,
                                  ),
                                  if (_currentMode != '影片' || _isRecording) ...[
                                    const SizedBox(height: 12),
                                    Text(
                                      _currentMode == '影片'
                                          ? '🔴 正在錄影中... (${_formatDuration(_recordingSeconds)})'
                                          : '📷 相機即時預覽畫面${_aiDirectorMode ? " [AI導演模式啟動中]" : ""}\n(縮放: ${_zoomLevel.toStringAsFixed(1)}x${!_isExposureAuto ? " | 曝光: ${_exposureValue.toStringAsFixed(1)}" : ""})',
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        color: _isRecording ? Colors.redAccent : Colors.white54,
                                        fontSize: 16,
                                        fontWeight: _isRecording ? FontWeight.bold : FontWeight.normal,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                    ),
                    if (_activeUploadedVideo == null)
                      Positioned.fill(
                        child: CustomPaint(
                          painter: CompositionGridPainter(_compositionGrid),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // 2. iOS 風格頂部控制列與下拉控制面板
            Positioned(
              top: 40,
              left: 0,
              right: 0,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ElevatedButton.icon(
                          onPressed: () {
                            _scaffoldKey.currentState?.openDrawer();
                          },
                          icon: const Icon(Icons.auto_awesome, color: Colors.yellowAccent, size: 16),
                          label: const Text('AI 設定', style: TextStyle(color: Colors.white, fontSize: 13)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.black54,
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(20),
                              side: const BorderSide(color: Colors.yellowAccent, width: 0.4),
                            ),
                          ),
                        ),
                        if (!_isRecording && _activeUploadedVideo == null)
                          GestureDetector(
                            onTap: () {
                              setState(() {
                                _isTopMenuExpanded = !_isTopMenuExpanded;
                                _isExposureSliding = false;
                                _isStyleSliding = false;
                              });
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.black45,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    _isTopMenuExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                    color: _isTopMenuExpanded ? Colors.yellowAccent : Colors.white,
                                    size: 22,
                                  ),
                                ],
                              ),
                            ),
                          )
                        else
                          const SizedBox.shrink(),
                        Row(
                          children: [
                            if (_currentMode == '影片' && !_isRecording && _activeUploadedVideo == null)
                              Padding(
                                padding: const EdgeInsets.only(right: 8.0),
                                child: IconButton(
                                  icon: const Icon(Icons.upload_file, color: Colors.white, size: 22),
                                  tooltip: '上傳影片',
                                  onPressed: _handleUploadVideo,
                                ),
                              ),
                            if (_activeUploadedVideo == null)
                              GestureDetector(
                                onTap: () {
                                  setState(() {
                                    if (_flashMode == '自動') {
                                      _flashMode = '開啟';
                                    } else if (_flashMode == '開啟') {
                                      _flashMode = '關閉';
                                    } else {
                                      _flashMode = '自動';
                                    }
                                  });
                                  _showAiTip('⚡ 閃光燈模式: $_flashMode');
                                },
                                onLongPress: _showFlashSelectDialog,
                                child: Padding(
                                  padding: const EdgeInsets.all(8.0),
                                  child: Icon(
                                    _flashMode == '自動'
                                        ? Icons.flash_auto
                                        : (_flashMode == '開啟' ? Icons.flash_on : Icons.flash_off),
                                    color: _flashMode == '關閉' ? Colors.white60 : Colors.yellowAccent,
                                    size: 22,
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  if (_isTopMenuExpanded && !_isRecording && _activeUploadedVideo == null)
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildIOSControlItem(
                                icon: Icons.aspect_ratio,
                                label: '比例',
                                value: _aspectRatio,
                                onTap: () {
                                  setState(() {
                                    _aspectRatio = _aspectRatio == '4:3'
                                        ? '16:9'
                                        : (_aspectRatio == '16:9' ? '1:1' : '4:3');
                                  });
                                  _showAiTip('📐 比例已切換為：$_aspectRatio');
                                },
                                onLongPress: _showAspectRatioSelectDialog,
                              ),
                              _buildIOSControlItem(
                                icon: Icons.exposure,
                                label: '曝光',
                                value: _isExposureAuto ? '自動' : _exposureValue.toStringAsFixed(1),
                                highlight: !_isExposureAuto,
                                onTap: () {
                                  setState(() {
                                    _isExposureAuto = true;
                                    _exposureValue = 0.0;
                                    _isExposureSliding = false;
                                  });
                                  _showAiTip('☀️ 曝光已設為自動');
                                },
                                onLongPress: () {
                                  setState(() {
                                    _isExposureAuto = false;
                                    _isExposureSliding = true;
                                    _isStyleSliding = false;
                                    _isTopMenuExpanded = false;
                                  });
                                  _showAiTip('☀️ 請在下方刻度調整曝光');
                                },
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
                                  _showAiTip('🌙 夜間模式: ${_nightMode ? "開啟" : "關閉"}');
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 16),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceAround,
                            children: [
                              _buildIOSControlItem(
                                icon: Icons.filter_b_and_w,
                                label: '濾鏡',
                                value: _filterMode,
                                highlight: _filterMode != '原味',
                                onTap: () {
                                  setState(() {
                                    if (_filterMode == '原味') {
                                      _filterMode = '鮮明';
                                    } else if (_filterMode == '鮮明') {
                                      _filterMode = '溫暖';
                                    } else if (_filterMode == '溫暖') {
                                      _filterMode = '冷色';
                                    } else if (_filterMode == '冷色') {
                                      _filterMode = '復古';
                                    } else {
                                      _filterMode = '原味';
                                    }
                                  });
                                  _showAiTip('🎨 濾鏡風格: $_filterMode');
                                },
                                onLongPress: _showFilterSelectDialog,
                              ),
                              _buildIOSControlItem(
                                icon: Icons.palette,
                                label: '風格',
                                value: (_styleTone != 0.0 || _styleTemp != 0.0) ? '自訂' : '無',
                                highlight: _styleTone != 0.0 || _styleTemp != 0.0,
                                onTap: () {
                                  setState(() {
                                    _styleTone = 0.0;
                                    _styleTemp = 0.0;
                                    _isStyleSliding = false;
                                  });
                                  _showAiTip('🎨 風格已設為：無');
                                },
                                onLongPress: () {
                                  setState(() {
                                    _isStyleSliding = true;
                                    _isExposureSliding = false;
                                    _isTopMenuExpanded = false;
                                  });
                                  _showAiTip('🎨 請在下方刻度調整風格');
                                },
                              ),
                              _buildIOSControlItem(
                                icon: _compositionGrid == '關閉' ? Icons.grid_off : Icons.grid_on,
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
                                      _compositionGrid = '智能構圖';
                                    } else {
                                      _compositionGrid = '關閉';
                                    }
                                  });
                                  _showAiTip('📐 構圖線已切換為：$_compositionGrid');
                                },
                                onLongPress: _showCompositionSelectDialog,
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                ],
              ),
            ),

            // 3. AI 即時提示懸浮卡片
            if (_isRecording || _activeUploadedVideo != null || _aiTipMessage != null)
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
                          : (_activeUploadedVideo != null ? Colors.orangeAccent : Colors.yellowAccent.withValues(alpha: 0.8)),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        _isRecording
                            ? Icons.fiber_manual_record
                            : (_activeUploadedVideo != null ? Icons.movie : Icons.auto_awesome),
                        color: _isRecording
                            ? Colors.redAccent
                            : (_activeUploadedVideo != null ? Colors.orangeAccent : Colors.yellowAccent),
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _isRecording
                            ? '【錄影中】 時間: ${_formatDuration(_recordingSeconds)}'
                            : (_activeUploadedVideo != null
                                ? '【上傳影片播放中】 點擊快門按鈕可讓 AI 抓拍'
                                : _aiTipMessage!),
                        style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
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
              child: _capturedImages.isEmpty
                  ? const SizedBox.shrink()
                  : Column(
                      children: [
                        IconButton(
                          onPressed: _clearAllImages,
                          icon: const Icon(Icons.delete_sweep, color: Colors.redAccent, size: 28),
                          tooltip: '全部清除',
                        ),
                        const SizedBox(height: 4),
                        Expanded(
                          child: ListView.builder(
                            itemCount: _capturedImages.length,
                            itemBuilder: (context, index) {
                              final itemName = _capturedImages[index];
                              final bool isVideo = itemName.contains('影片');

                              return Dismissible(
                                key: Key(itemName + index.toString()),
                                direction: DismissDirection.horizontal,
                                background: Container(
                                  alignment: Alignment.centerLeft,
                                  padding: const EdgeInsets.only(left: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.green,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.save, color: Colors.white, size: 24),
                                ),
                                secondaryBackground: Container(
                                  alignment: Alignment.centerRight,
                                  padding: const EdgeInsets.only(right: 12),
                                  decoration: BoxDecoration(
                                    color: Colors.red,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: const Icon(Icons.delete, color: Colors.white, size: 24),
                                ),
                                confirmDismiss: (direction) async {
                                  if (direction == DismissDirection.endToStart) {
                                    return true;
                                  } else {
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('✅ 已成功保存 $itemName！'),
                                        duration: const Duration(seconds: 1),
                                      ),
                                    );
                                    return false;
                                  }
                                },
                                onDismissed: (direction) {
                                  if (direction == DismissDirection.endToStart) {
                                    setState(() {
                                      _capturedImages.removeAt(index);
                                    });
                                  }
                                },
                                child: GestureDetector(
                                  onLongPress: () => _showEnlargedGallery(index),
                                  child: Container(
                                    margin: const EdgeInsets.only(bottom: 10),
                                    height: 70,
                                    decoration: BoxDecoration(
                                      color: Colors.grey[800],
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isVideo ? Colors.orangeAccent : Colors.yellowAccent,
                                        width: 2,
                                      ),
                                    ),
                                    child: Center(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            isVideo ? Icons.videocam : Icons.image,
                                            size: 20,
                                            color: isVideo ? Colors.orangeAccent : Colors.yellowAccent,
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
                                ),
                              );
                            },
                          ),
                        ),
                      ],
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
                  if (_isExposureSliding && !_isRecording && _activeUploadedVideo == null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.yellowAccent, width: 0.8),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('☀️ 曝光補償', style: TextStyle(color: Colors.yellowAccent, fontSize: 12, fontWeight: FontWeight.bold)),
                              Text('${_exposureValue >= 0 ? "+" : ""}${_exposureValue.toStringAsFixed(1)}EV', style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                              GestureDetector(
                                onTap: () => setState(() => _isExposureSliding = false),
                                child: const Icon(Icons.close, color: Colors.white54, size: 16),
                              ),
                            ],
                          ),
                          SizedBox(
                            width: 280,
                            height: 18,
                            child: CustomPaint(
                              size: const Size(280, 18),
                              painter: ExposureTicksPainter(exposureValue: _exposureValue),
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
                                  _isExposureAuto = false;
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                  // 5.2 精簡版風格刻度尺 (色調 / 色溫)
                  if (_isStyleSliding && !_isRecording && _activeUploadedVideo == null)
                    Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.yellowAccent, width: 0.8),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(
                                children: [
                                  GestureDetector(
                                    onTap: () => setState(() => _styleActiveTab = '色調'),
                                    child: Text(
                                      '🎨 色調',
                                      style: TextStyle(
                                        color: _styleActiveTab == '色調' ? Colors.yellowAccent : Colors.white60,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  GestureDetector(
                                    onTap: () => setState(() => _styleActiveTab = '色溫'),
                                    child: Text(
                                      '🌡️ 色溫',
                                      style: TextStyle(
                                        color: _styleActiveTab == '色溫' ? Colors.yellowAccent : Colors.white60,
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              Text(
                                '${(_styleActiveTab == '色調' ? _styleTone : _styleTemp) >= 0 ? "+" : ""}${(_styleActiveTab == '色調' ? _styleTone : _styleTemp).toStringAsFixed(1)}',
                                style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              GestureDetector(
                                onTap: () => setState(() => _isStyleSliding = false),
                                child: const Icon(Icons.close, color: Colors.white54, size: 16),
                              ),
                            ],
                          ),
                          SizedBox(
                            width: 280,
                            height: 18,
                            child: CustomPaint(
                              size: const Size(280, 18),
                              painter: StyleTicksPainter(value: _styleActiveTab == '色調' ? _styleTone : _styleTemp),
                            ),
                          ),
                          SizedBox(
                            height: 24,
                            child: Slider(
                              value: _styleActiveTab == '色調' ? _styleTone : _styleTemp,
                              min: -1.0,
                              max: 1.0,
                              divisions: 20,
                              activeColor: Colors.yellowAccent,
                              inactiveColor: Colors.white24,
                              onChanged: (val) {
                                setState(() {
                                  if (_styleActiveTab == '色調') {
                                    _styleTone = val;
                                  } else {
                                    _styleTemp = val;
                                  }
                                });
                              },
                            ),
                          ),
                        ],
                      ),
                    ),

                  // 5.3 互動式倍數列與滑動刻度尺
                  if (!_isRecording && !_isExposureSliding && !_isStyleSliding && _activeUploadedVideo == null)
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
                          onHorizontalDragUpdate: (details) {
                            setState(() {
                              _zoomLevel = (_zoomLevel - details.primaryDelta! * 0.003).clamp(0.5, 5.0);
                            });
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
                            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 24),
                            color: Colors.transparent,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                _buildZoomLabelButton(0.5, '0.5x'),
                                const SizedBox(width: 16),
                                _buildZoomLabelButton(1.0, '1x'),
                                const SizedBox(width: 16),
                                _buildZoomLabelButton(2.0, '2x'),
                                const SizedBox(width: 16),
                                _buildZoomLabelButton(3.0, '3x'),
                                const SizedBox(width: 16),
                                _buildZoomLabelButton(5.0, '5x'),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  if (!_isRecording && !_isExposureSliding && !_isStyleSliding && _activeUploadedVideo == null) const SizedBox(height: 12),

                  // 5.4 拍攝模式切換列
                  if (!_isRecording && _activeUploadedVideo == null)
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: _modes.map((mode) {
                        final bool isSelected = _currentMode == mode;
                        return Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 16.0),
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _currentMode = mode;
                                _isTopMenuExpanded = false;
                                _isExposureSliding = false;
                                _isStyleSliding = false;
                              });
                              _showAiTip('✨ AI 已切換至 [$_currentMode] 模式');
                            },
                            child: Text(
                              mode,
                              style: TextStyle(
                                color: isSelected ? Colors.yellowAccent : Colors.white60,
                                fontSize: 16,
                                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  if (!_isRecording && _activeUploadedVideo == null) const SizedBox(height: 20),

                  // 5.5 快門與快捷按鈕列
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 36.0),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        GestureDetector(
                          onTap: () {
                            if (_capturedImages.isNotEmpty) {
                              _showEnlargedGallery(_capturedImages.length - 1);
                            } else {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('📸 目前尚無拍攝的相片或影片'),
                                  duration: Duration(milliseconds: 800),
                                ),
                              );
                            }
                          },
                          child: Container(
                            width: 50,
                            height: 50,
                            decoration: BoxDecoration(
                              color: Colors.grey[800],
                              borderRadius: BorderRadius.circular(8),
                              border: Border.all(
                                color: _capturedImages.isNotEmpty ? Colors.yellowAccent : Colors.white,
                                width: 1.5,
                              ),
                            ),
                            child: _capturedImages.isEmpty
                                ? const Icon(Icons.photo, color: Colors.white70)
                                : Center(
                                    child: Icon(
                                      _capturedImages.last.contains('影片') ? Icons.videocam : Icons.image,
                                      color: Colors.yellowAccent,
                                      size: 26,
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
                                color: _isRecording ? Colors.redAccent : Colors.white,
                                width: 4,
                              ),
                            ),
                            child: Container(
                              margin: const EdgeInsets.all(4),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _isRecording ? Colors.red : (_isCapturing ? Colors.red : Colors.white),
                              ),
                              child: _isRecording
                                  ? const Center(
                                      child: Icon(Icons.stop, color: Colors.white, size: 36),
                                    )
                                  : null,
                            ),
                          ),
                        ),
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.grey[800]?.withValues(alpha: 0.6),
                          ),
                          child: const Icon(Icons.cameraswitch, color: Colors.white, size: 26),
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

  Widget _buildZoomLabelButton(double targetZoom, String label) {
    final bool isSelected = (_zoomLevel - targetZoom).abs() < 0.25;
    return GestureDetector(
      onTap: () {
        setState(() {
          _zoomLevel = targetZoom;
        });
        _showAiTip('🔍 變焦倍數調整至：$label');
      },
      child: Text(
        label,
        style: TextStyle(
          color: isSelected ? Colors.yellowAccent : Colors.white60,
          fontSize: 13,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
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
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: highlight ? Colors.yellowAccent.withValues(alpha: 0.2) : Colors.white10,
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
          Text(
            value,
            style: TextStyle(
              color: highlight ? Colors.yellowAccent : Colors.white70,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
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
      bool isKey = (roundedE == -2.0 || roundedE == -1.0 || roundedE == 0.0 || roundedE == 1.0 || roundedE == 2.0);

      double t = (roundedE - minExp) / (maxExp - minExp);
      double x = t * size.width;

      double tickHeight = isKey ? 12.0 : 6.0;
      bool isCurrent = (exposureValue - roundedE).abs() < 0.11;

      Paint currentPaint = Paint()
        ..color = isCurrent ? Colors.yellowAccent : (isKey ? Colors.white70 : Colors.white38)
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
      bool isKey = (roundedV == -1.0 || roundedV == -0.5 || roundedV == 0.0 || roundedV == 0.5 || roundedV == 1.0);

      double t = (roundedV - minValue) / (maxValue - minValue);
      double x = t * size.width;

      double tickHeight = isKey ? 12.0 : 6.0;
      bool isCurrent = (value - roundedV).abs() < 0.06;

      Paint currentPaint = Paint()
        ..color = isCurrent ? Colors.yellowAccent : (isKey ? Colors.white70 : Colors.white38)
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

    canvas.drawLine(
      Offset(0, size.height / 2),
      Offset(size.width, size.height / 2),
      paint..color = Colors.white24,
    );

    for (double z = minZoom; z <= maxZoom + 0.001; z += 0.1) {
      double roundedZ = double.parse(z.toStringAsFixed(1));
      bool isMajor = (roundedZ * 10) % 5 == 0;
      bool isKey = (roundedZ == 0.5 || roundedZ == 1.0 || roundedZ == 2.0 || roundedZ == 3.0 || roundedZ == 5.0);

      double t = (roundedZ - minZoom) / (maxZoom - minZoom);
      double x = t * size.width;

      double tickHeight = isKey ? 18.0 : (isMajor ? 12.0 : 6.0);
      bool isCurrent = (zoomLevel - roundedZ).abs() < 0.06;

      Paint currentPaint = Paint()
        ..color = isCurrent ? Colors.yellowAccent : (isKey ? Colors.white70 : Colors.white38)
        ..strokeWidth = isCurrent ? 2.5 : (isKey ? 1.5 : 1.0);

      canvas.drawLine(
        Offset(x, (size.height - tickHeight) / 2),
        Offset(x, (size.height + tickHeight) / 2),
        currentPaint,
      );
    }

    double currentT = (zoomLevel - minZoom) / (maxZoom - minZoom);
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
      canvas.drawLine(Offset(size.width / 3, 0), Offset(size.width / 3, size.height), paint);
      canvas.drawLine(Offset(size.width * 2 / 3, 0), Offset(size.width * 2 / 3, size.height), paint);
      canvas.drawLine(Offset(0, size.height / 3), Offset(size.width, size.height / 3), paint);
      canvas.drawLine(Offset(0, size.height * 2 / 3), Offset(size.width, size.height * 2 / 3), paint);
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
    } else if (gridType == '智能構圖') {
      final aiPaint = Paint()
        ..color = Colors.yellowAccent.withValues(alpha: 0.6)
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;

      const double margin = 48.0;
      const double bracketLen = 30.0;

      canvas.drawLine(Offset(margin, margin + bracketLen), Offset(margin, margin), aiPaint);
      canvas.drawLine(Offset(margin, margin), Offset(margin + bracketLen, margin), aiPaint);

      canvas.drawLine(Offset(size.width - margin - bracketLen, margin), Offset(size.width - margin, margin), aiPaint);
      canvas.drawLine(Offset(size.width - margin, margin), Offset(size.width - margin, margin + bracketLen), aiPaint);

      canvas.drawLine(Offset(margin, size.height - margin - bracketLen), Offset(margin, size.height - margin), aiPaint);
      canvas.drawLine(Offset(margin, size.height - margin), Offset(margin + bracketLen, size.height - margin), aiPaint);

      canvas.drawLine(Offset(size.width - margin - bracketLen, size.height - margin), Offset(size.width - margin, size.height - margin), aiPaint);
      canvas.drawLine(Offset(size.width - margin, size.height - margin), Offset(size.width - margin, size.height - margin - bracketLen), aiPaint);

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
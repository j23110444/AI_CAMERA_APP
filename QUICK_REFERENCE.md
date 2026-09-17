# MVVM Quick Reference (快速參考)

## 文件導覽

### 核心檔案
- **main.dart** - Provider 配置，應用進入點
- **camera_viewmodel.dart** - 業務邏輯集中處

### 快速操作

#### 在 View 中使用 ViewModel

```dart
// 方式 1: 讀取狀態
final viewModel = context.read<CameraViewModel>();
viewModel.takePicture();

// 方式 2: 監聽狀態變化 (推薦)
Consumer<CameraViewModel>(
  builder: (context, viewModel, child) {
    return Text(viewModel.recordingState.formattedDuration);
  }
)
```

#### 常用操作

| 操作 | 代碼 |
|-----|------|
| 拍照 | `await viewModel.takePicture()` |
| 開始/停止錄影 | `await viewModel.toggleRecording()` |
| 切換模式 | `viewModel.switchMode('影片')` |
| 調整縮放 | `await viewModel.updateZoom(2.0)` |
| 調整曝光 | `await viewModel.updateExposure(0.5)` |
| 切換濾鏡 | `viewModel.switchFilter('鮮明')` |
| 顯示提示 | `viewModel.setAiTip('提示訊息')` |
| 获取媒體 | `viewModel.capturedMedia` |
| 清除媒體 | `viewModel.clearAllMedia()` |

### 狀態訪問

```dart
// 相機設定
viewModel.currentSettings.zoom           // 1.0 ~ 10.0
viewModel.currentSettings.exposure       // -2.0 ~ 2.0
viewModel.currentSettings.aiBurstEnabled // AI 連拍開關

// 錄影狀態
viewModel.recordingState.isRecording     // bool
viewModel.recordingState.formattedDuration  // '00:23'

// UI 狀態
viewModel.uiState.currentMode            // '拍照' / '影片' / '物景'
viewModel.uiState.aiTipMessage           // 提示訊息

// 上傳影片
viewModel.uploadedVideoState.isActive    // 是否在預覽
viewModel.uploadedVideoState.progress    // 0.0 ~ 1.0
```

### 模型結構

#### CameraSettings
```
zoom: double (1.0 ~ 10.0)
exposure: double (-2.0 ~ 2.0)
flashEnabled: bool
filterMode: String ('原味', '鮮明', etc.)
styleTone: double (-1.0 ~ 1.0)
styleTemp: double (-1.0 ~ 1.0)
nightMode: bool
aiBurstEnabled: bool
aiBurstCount: int (3, 5, 7, 10)
aiBurstSeconds: int (3, 5)
passingScore: int (1 ~ 5)
aiWeights: Map<String, double>
```

#### RecordingState
```
isRecording: bool
recordingSeconds: int
formattedDuration: String ('MM:SS')
```

#### UIState
```
currentMode: String
isCapturing: bool
isTopMenuExpanded: bool
isStyleSliding: bool
isExposureSliding: bool
aiTipMessage: String?
errorMessage: String?
```

#### MediaItem
```
id: String
name: String
type: MediaType (photo, video, burstPhoto, videoCapture)
duration: String? (for video)
timestamp: DateTime
filePath: String?
```

## 服務層

### CameraService
```dart
await initializeCamera()
await setZoom(double zoom)
await setExposure(double exposure)
XFile? takePicture()
startVideoRecording()
XFile? stopVideoRecording()
switchCamera()
getMinZoom() -> double
getMaxZoom() -> double
```

### AIService
```dart
AIResponse analyzeImage(String imagePath)
List<String> getAvailableFeatures()
bool healthCheck()
```

## 常見模式

### 添加新功能

1. **在 ViewModel 中添加方法**
```dart
Future<void> myNewFeature() async {
  try {
    // 業務邏輯
    notifyListeners();  // 通知 UI 更新
  } catch (e) {
    _setError(e.toString());
  }
}
```

2. **在 View 中調用**
```dart
ElevatedButton(
  onPressed: () => context.read<CameraViewModel>().myNewFeature(),
  child: Text('執行'),
)
```

### 監聽多個狀態

```dart
Selector<CameraViewModel, (bool, String)>(
  selector: (_, vm) => (
    vm.recordingState.isRecording,
    vm.currentSettings.filterMode,
  ),
  builder: (_, data, __) {
    return Text('錄影: ${data.$1}, 濾鏡: ${data.$2}');
  },
)
```

### 條件 UI 渲染

```dart
Consumer<CameraViewModel>(
  builder: (_, viewModel, __) {
    if (viewModel.isLoading) {
      return LoadingIndicator();
    }
    if (viewModel.errorMessage != null) {
      return ErrorWidget(viewModel.errorMessage!);
    }
    return MainContent();
  },
)
```

## 開發檢查清單

- [ ] 依賴已安裝 (`flutter pub get`)
- [ ] main.dart 中 Provider 配置正確
- [ ] ViewModel 初始化無誤
- [ ] View 層正確使用 Consumer
- [ ] 狀態變化觸發 notifyListeners()
- [ ] 錯誤處理完善
- [ ] 測試涵蓋關鍵功能

## 故障排除

### UI 沒有更新
✓ 確保調用了 `notifyListeners()`
✓ 確保使用了 `Consumer` 或 `Selector`
✓ 檢查 Provider 配置

### CameraService 未初始化
✓ 確保在 ViewModel 中調用了 `initializeCamera()`
✓ 檢查相機權限
✓ 查看 logcat 的初始化錯誤

### 內存洩漏
✓ 檢查 Timer 是否正確 cancelled
✓ 確保在 dispose() 中清理資源
✓ 確保 Provider 正確清理

## 性能優化提示

1. **使用 Selector 減少重建**
```dart
Selector<CameraViewModel, double>(
  selector: (_, vm) => vm.currentSettings.zoom,
  builder: (_, zoom, __) => ZoomDisplay(zoom),
)
```

2. **延遲初始化**
```dart
@override
void initState() {
  WidgetsBinding.instance.addPostFrameCallback((_) {
    context.read<CameraViewModel>().initializeCamera();
  });
}
```

3. **避免頻繁 rebuild**
```dart
// ❌ 不好 - 每個狀態變化都重建
Consumer<CameraViewModel>(builder: (_, vm, __) => ...)

// ✅ 好 - 只監聽需要的狀態
Selector<CameraViewModel, bool>(
  selector: (_, vm) => vm.recordingState.isRecording,
  builder: (_, isRecording, __) => ...
)
```

## 相關資源

- [Provider 官方文檔](https://pub.dev/packages/provider)
- [Flutter MVVM 最佳實踐](https://flutter.dev/)
- [Dart 語言指南](https://dart.dev/guides)

---

**快速參考版本**: 1.0
**最後更新**: 2026-08-31

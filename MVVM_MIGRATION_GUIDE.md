# AI Camera App - MVVM 架構遷移指南

## 📋 目錄
1. [架構概述](#架構概述)
2. [文件結構](#文件結構)
3. [核心概念](#核心概念)
4. [功能遷移](#功能遷移)
5. [使用指南](#使用指南)
6. [依賴項](#依賴項)
7. [後續開發](#後續開發)

---

## 架構概述

該項目採用 **MVVM (Model-View-ViewModel)** 架構，使用 **Provider** 進行狀態管理。

```
┌─────────────────────────────────────────┐
│          Presentation Layer             │
│  (Views, Widgets, Painters)             │
└──────────────┬──────────────────────────┘
               ↑↓ (Provider)
┌──────────────────────────────────────────┐
│         ViewModel Layer                  │
│  (CameraViewModel - Business Logic)      │
└──────────────┬──────────────────────────┘
               ↑↓
┌──────────────────────────────────────────┐
│      Model Layer                         │
│  (Data Models, States)                   │
└──────────────┬──────────────────────────┘
               ↑↓
┌──────────────────────────────────────────┐
│      Service Layer                       │
│  (CameraService, AIService)              │
└──────────────────────────────────────────┘
```

---

## 文件結構

```
lib/
├── main.dart                          # MVVM 進入點 (Provider 配置)
│
├── core/                              # 核心配置層
│   ├── constants.dart                 # 全域常數
│   └── theme.dart                     # 主題配置
│
├── models/                            # 資料層
│   ├── camera_settings.dart           # 相機設定 + AI 參數
│   ├── ai_response_model.dart         # AI 回應模型
│   ├── media_models.dart              # 媒體項目、錄影、影片狀態
│   └── ui_state.dart                  # UI 狀態
│
├── services/                          # 外部服務層
│   ├── camera_service.dart            # 相機硬體封裝
│   └── ai_service.dart                # AI API 封裝
│
├── viewmodels/                        # 業務邏輯層
│   └── camera_viewmodel.dart          # 相機視圖模型 (核心邏輯)
│
├── views/                             # 視圖層
│   └── camera_screen.dart             # 主畫面
│
├── widgets/                           # 可重用組件
│   ├── camera_controls.dart           # 快門、切換鏡頭按鈕
│   └── ai_dialogs.dart                # AI 對話框
│
└── painters/                          # 自訂繪製器
    ├── zoom_ticks_painter.dart        # 縮放刻度尺
    ├── exposure_painter.dart          # 曝光刻度
    └── composition_grid_painter.dart  # 構圖格線
```

---

## 核心概念

### 1. Models (模型層)

**CameraSettings** - 統一的設定管理
```dart
CameraSettings(
  zoom: 1.0,                    // 1.0 ~ 10.0
  exposure: 0.0,                // -2.0 ~ 2.0
  flashEnabled: false,
  filterMode: '原味',           // 濾鏡模式
  styleTone: 0.0,              // 色調 (-1.0 ~ 1.0)
  styleTemp: 0.0,              // 色溫 (-1.0 ~ 1.0)
  aiDirectorMode: false,        // AI 導演模式
  aiBurstEnabled: true,         // AI 連拍開關
  aiBurstCount: 5,              // 連拍張數
  aiBurstSeconds: 3,            // 連拍時間
  passingScore: 3,              // 合格分數
  aiWeights: {...}              // AI 評分權重
)
```

**RecordingState** - 錄影狀態
```dart
RecordingState(
  isRecording: false,
  recordingSeconds: 0,
  formattedDuration: '00:00'
)
```

**UIState** - UI 狀態
```dart
UIState(
  currentMode: '拍照',          // 影片/拍照/物景
  isCapturing: false,
  isTopMenuExpanded: false,
  aiTipMessage: null,           // 提示訊息
  errorMessage: null            // 錯誤訊息
)
```

### 2. Services (服務層)

**CameraService** - 相機硬體操作
```dart
await cameraService.initializeCamera();
await cameraService.setZoom(2.0);
await cameraService.setExposure(0.5);
final image = await cameraService.takePicture();
```

**AIService** - AI API 調用
```dart
final response = await aiService.analyzeImage(imagePath);
final features = await aiService.getAvailableFeatures();
final isHealthy = await aiService.healthCheck();
```

### 3. ViewModel (業務邏輯層)

**CameraViewModel** - 集中所有邏輯
```dart
// 拍照
await viewModel.takePicture();

// 錄影
await viewModel.toggleRecording();

// 切換模式
viewModel.switchMode('影片');

// 更新設定
await viewModel.updateZoom(2.0);
await viewModel.updateExposure(0.5);
viewModel.updateStyleTone(0.3);

// AI 操作
viewModel.toggleAIDirectorMode();
viewModel.toggleAIBurst();
```

### 4. Views (視圖層)

**CameraScreen** - 純 UI 渲染，通過 Consumer 自動訂閱狀態
```dart
Consumer<CameraViewModel>(
  builder: (context, viewModel, _) {
    return Stack(
      children: [
        CameraPreview(...),
        if (viewModel.recordingState.isRecording)
          RecordingIndicator(...),
        ...
      ],
    );
  }
)
```

---

## 功能遷移

### 現有功能遷移到 ViewModel

| 功能 | 原位置 | 新位置 | 方法 |
|------|--------|--------|------|
| 拍照/AI連拍 | main.dart | ViewModel | `takePicture()` |
| 錄影 | main.dart | ViewModel | `toggleRecording()` |
| 切換模式 | main.dart | ViewModel | `switchMode(mode)` |
| 上傳影片 | main.dart | ViewModel | `uploadVideo(name, duration)` |
| 縮放控制 | main.dart | ViewModel | `updateZoom(zoom)` |
| 曝光控制 | main.dart | ViewModel | `updateExposure(exposure)` |
| 濾鏡切換 | main.dart | ViewModel | `switchFilter(mode)` |
| 風格調整 | main.dart | ViewModel | `updateStyleTone(tone)`, `updateStyleTemp(temp)` |
| AI 提示 | main.dart | ViewModel | `setAiTip(message)` |

### 新增狀態管理

- `RecordingState` - 專注錄影狀態
- `UIState` - 統一 UI 狀態管理
- `UploadedVideoState` - 影片預覽狀態
- `MediaItem` - 媒體列表項目

---

## 使用指南

### 基本使用模式

#### 1. 訪問 ViewModel
```dart
final viewModel = context.read<CameraViewModel>();
```

#### 2. 監聽狀態變化
```dart
Consumer<CameraViewModel>(
  builder: (context, viewModel, _) {
    // 任何狀態變化都會重建此區域
    return Text(viewModel.recordingState.formattedDuration);
  }
)
```

#### 3. 觸發操作
```dart
ElevatedButton(
  onPressed: () async {
    await context.read<CameraViewModel>().takePicture();
  },
  child: const Text('拍照'),
)
```

### 常見操作

#### 拍照
```dart
// 單拍
viewModel.currentSettings.aiBurstEnabled = false;
await viewModel.takePicture();

// AI 連拍
viewModel.currentSettings.aiBurstEnabled = true;
await viewModel.takePicture();
```

#### 錄影
```dart
// 開始/停止
await viewModel.toggleRecording();

// 獲取狀態
print(viewModel.recordingState.formattedDuration);
print(viewModel.recordingState.isRecording);
```

#### 管理媒體
```dart
// 獲取所有媒體
List<MediaItem> items = viewModel.capturedMedia;

// 刪除特定媒體
viewModel.deleteMedia(mediaId);

// 清除所有
viewModel.clearAllMedia();
```

---

## 依賴項

### 必須的包

```yaml
dependencies:
  flutter:
    sdk: flutter
  provider: ^6.0.0              # 狀態管理
  camera: ^0.10.0               # 相機功能
  http: ^0.13.0                 # HTTP 請求
```

### 安裝

```bash
flutter pub get
```

---

## 後續開發

### 1. UI 層完成
- [ ] 完善 `camera_screen.dart` 的 UI 佈局
- [ ] 實現各個控制按鈕的交互
- [ ] 完成 AI 對話框邏輯

### 2. 功能實現
- [ ] 實現真實的相機硬體初始化
- [ ] 連接真實的 AI API
- [ ] 實現媒體保存和導出

### 3. 高級特性
- [ ] 影片編輯功能
- [ ] 批量導出
- [ ] 相冊管理
- [ ] 設定持久化

### 4. 測試
- [ ] 為 ViewModel 編寫單元測試
- [ ] 為 Services 編寫集成測試
- [ ] UI 測試

### 5. 優化
- [ ] 性能優化
- [ ] 內存管理
- [ ] 錯誤處理增強

---

## 開發建議

### 1. 添加新功能
```dart
// 在 ViewModel 中添加新方法
Future<void> newFeature() async {
  // 業務邏輯
}

// 在 View 中調用
await viewModel.newFeature();
```

### 2. 添加新狀態
```dart
// 在 models 中定義新狀態類
class NewState {
  final String data;
  // ...
}

// 在 ViewModel 中使用
late NewState _newState;
```

### 3. 測試
```dart
void main() {
  test('takePicture should update media list', () async {
    final viewModel = CameraViewModel(
      cameraService: mockCameraService,
      aiService: mockAIService,
    );
    
    await viewModel.takePicture();
    
    expect(viewModel.capturedMedia.length, 1);
  });
}
```

---

## 常見問題

### Q: Provider 自動更新 UI 嗎？
**A:** 是的。只要在 ViewModel 中調用 `notifyListeners()`，所有通過 `Consumer` 訂閱的 UI 都會自動重建。

### Q: 如何共享 ViewModel 狀態？
**A:** 使用 `Provider.of()` 或 `context.read()` 讀取，使用 `Consumer` 訂閱變化。

### Q: 可以同時有多個 ViewModel 嗎？
**A:** 可以，只需在 `main.dart` 的 `MultiProvider` 中添加多個 `ChangeNotifierProvider`。

### Q: 如何保存用戶設定？
**A:** 使用 `shared_preferences` 包在 ViewModel 中實現持久化。

---

## 文件清單

遷移完成的文件：
- ✓ lib/main.dart (已更新)
- ✓ lib/core/constants.dart (新建)
- ✓ lib/core/theme.dart (新建)
- ✓ lib/models/camera_settings.dart (已擴展)
- ✓ lib/models/ai_response_model.dart (新建)
- ✓ lib/models/media_models.dart (新建)
- ✓ lib/models/ui_state.dart (新建)
- ✓ lib/services/camera_service.dart (新建)
- ✓ lib/services/ai_service.dart (新建)
- ✓ lib/viewmodels/camera_viewmodel.dart (新建)
- ✓ lib/views/camera_screen.dart (新建)
- ✓ lib/widgets/camera_controls.dart (新建)
- ✓ lib/widgets/ai_dialogs.dart (新建)
- ✓ lib/painters/zoom_ticks_painter.dart (新建)
- ✓ lib/painters/exposure_painter.dart (新建)
- ✓ lib/painters/composition_grid_painter.dart (新建)

---

**最後更新:** 2026-08-31
**架構版本:** MVVM with Provider
**狀態管理:** ChangeNotifier + Provider

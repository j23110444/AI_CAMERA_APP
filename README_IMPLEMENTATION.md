# AI 智慧攝影 APP — V0 Implementation

本版本依 V2.1 計畫書開始實作，第一個可驗證切片為：

`UI → ShootingEngine → Moment Score → Peak Detection → Capture Decision`

## 已完成

- P0 初步架構：入口、Camera Feature、Domain/Application/Data/Camera Port 分離。
- `FrameFeatures`：定義即時影像分析的輸入資料。
- `PreferenceModel`：承接目前 UI 的四項 AI 權重。
- `MomentScorer`：分離 Objective Quality 與 Personal Preference Match。
- `PeakDetector`：以連續分數序列找局部峰值，而非固定時間盲拍。
- `ShootingEngine`：串接 Frame Analysis → Score → Peak → Capture Decision。
- `CameraPort`：建立正式 Camera API 抽象介面，並透過 iOS AVFoundation bridge 提供 Pro 控制。
- Preference Repository / Learning Service：建立 V1-B 所需的資料層骨架。
- 原本 UI 的 AI Burst 固定時間模擬已改成呼叫 V0 `ShootingEngine` 模擬流程。

## 尚未完成

- AVFoundation 原生預覽與 Photo Capture 的深度整合仍由 Flutter camera plugin 負責。
- Vision / Core ML 人物、臉部、眼睛、姿勢、構圖分析。
- 真實影像 Frame Stream。
- 真正的硬體快門延遲校正。
- 實際 Photo Asset / Gallery。
- Preference Learning 的真實使用者選片資料。
- Reference Image 深度分析。

## 下一個實作切片

V0 驗證後進入 V1-A：

1. Flutter Camera UI 保持目前畫面。
2. `CameraPort` 建立 iOS native adapter。
3. AVFoundation 提供 preview / frame stream / photo capture。
4. Vision / Core ML 將 frame 轉成 `FrameFeatures`。
5. `ShootingEngine.processFrame()` 接收真實連續影像。
6. Peak Detection 觸發 Capture Decision。
7. 真正執行 3/5/7/10 張候選照片。

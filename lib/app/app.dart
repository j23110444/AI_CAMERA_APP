import 'package:flutter/material.dart';

import '../features/camera/presentation/ios_camera_page.dart';
import '../features/gallery/presentation/gallery_page.dart';
import '../features/video/presentation/video_preview_page.dart';
import '../features/video/presentation/video_upload_page.dart';
import '../features/settings/presentation/settings_page.dart';
import 'routes.dart';
import 'theme.dart';

class AICameraApp extends StatelessWidget {
  const AICameraApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'AI 智慧相機',
      theme: AppTheme.dark(),
      scrollBehavior: const AppScrollBehavior(),
      initialRoute: AppRoutes.camera,
      routes: {
        AppRoutes.camera: (_) => const IOSCameraPage(),
        AppRoutes.gallery: (_) => const GalleryPage(),
        AppRoutes.videoPreview: (_) => const VideoPreviewPage(),
        AppRoutes.videoUpload: (_) => const VideoUploadPage(),
        AppRoutes.settings: (_) => const SettingsPage(),
      },
    );
  }
}

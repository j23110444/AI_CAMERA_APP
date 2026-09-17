import 'package:flutter/material.dart';

class VideoPreviewPage extends StatelessWidget {
  const VideoPreviewPage({super.key, this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: Text(path ?? 'Video preview')),
    );
  }
}

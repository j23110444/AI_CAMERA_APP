import 'package:flutter/material.dart';

class PhotoPreviewPage extends StatelessWidget {
  const PhotoPreviewPage({super.key, this.path});

  final String? path;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(child: Text(path ?? 'Photo preview')),
    );
  }
}

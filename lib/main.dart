import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'app_widget.dart';

Future<void> main() async {

  WidgetsFlutterBinding.ensureInitialized();

  final cameras = await availableCameras();

  final firstCamera = cameras.first;

  runApp(AppWidget(firstCamera: firstCamera));

}
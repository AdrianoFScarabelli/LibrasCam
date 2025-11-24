import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:camera/camera.dart';
import 'app_widget.dart';

Future<void> main() async {

  WidgetsFlutterBinding.ensureInitialized();

  SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
  ]);

  final cameras = await availableCameras();

  final firstCamera = cameras.first;

  runApp(AppWidget(firstCamera: firstCamera));

}
import 'package:flutter/material.dart';
import 'package:librascam/app_controller.dart';
import 'camera_page.dart';
import 'home_page.dart';
import 'login_page.dart';
import 'package:camera/camera.dart';

class AppWidget extends StatelessWidget {
  final CameraDescription firstCamera;

  const AppWidget({super.key, required this.firstCamera});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AppController.instance,
      builder: (context, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false,
          initialRoute: '/',
          routes: {
            '/': (context) => const LoginPage(),
            '/home': (context) => HomePage(),
            '/camera': (context) => CameraScreen(camera: firstCamera),
          },
          theme: ThemeData(
            primarySwatch: Colors.red,
            brightness: AppController.instance.darkTheme 
            ? Brightness.dark 
            : Brightness.light,
          ),
        );
      },
    );
  }
}
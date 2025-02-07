import 'package:flutter/material.dart';

class AppController extends ChangeNotifier {

  static AppController instance = AppController();

  bool darkTheme = false;
  changeTheme () {
    darkTheme = !darkTheme;
    notifyListeners();
  }

}
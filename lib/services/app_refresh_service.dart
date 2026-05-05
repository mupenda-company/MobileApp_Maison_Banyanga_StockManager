import 'package:flutter/foundation.dart';

class AppRefreshService extends ChangeNotifier {
  static final AppRefreshService instance = AppRefreshService._();

  AppRefreshService._();

  int _version = 0;

  int get version => _version;

  void notifyDataChanged() {
    _version++;
    notifyListeners();
  }
}

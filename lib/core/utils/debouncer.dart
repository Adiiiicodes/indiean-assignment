import 'dart:async';

import 'package:focusdesk/core/constants/app_constants.dart';

class Debouncer {
  Debouncer({this.delay = AppConstants.searchDebounce});

  final Duration delay;
  Timer? _timer;
  bool _isDisposed = false;

  void call(void Function() action) {
    if (_isDisposed) return;
    cancel();
    _timer = Timer(delay, () {
      _timer = null;
      if (!_isDisposed) action();
    });
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  void dispose() {
    _isDisposed = true;
    cancel();
  }
}

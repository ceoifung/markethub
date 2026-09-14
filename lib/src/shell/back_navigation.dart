/// 系统返回手势被拦截后的处理结果。
enum BackGestureOutcome {
  /// WebView 还有历史记录，应调用 goBack() 回到上一页。
  navigateBackInWebView,

  /// 确认窗口内再次按返回，应退出应用。
  exitApp,

  /// 在根页面首次按返回，提示用户再按一次退出。
  promptExitConfirmation,
}

/// 把 Android 系统返回手势翻译成 WebView 历史返回，
/// 到达根页面后采用“再按一次退出”策略，避免误触直接退出应用。
class BackGestureHandler {
  BackGestureHandler({this.exitConfirmWindow = const Duration(seconds: 2)});

  final Duration exitConfirmWindow;
  DateTime? _lastPromptAt;

  /// [canGoBack] WebView 当前是否还有可回退的历史记录；
  /// [now] 当前时间，测试时可注入固定值。
  BackGestureOutcome evaluate({required bool canGoBack, DateTime? now}) {
    final timestamp = now ?? DateTime.now();
    if (canGoBack) {
      _lastPromptAt = null;
      return BackGestureOutcome.navigateBackInWebView;
    }

    final lastPromptAt = _lastPromptAt;
    if (lastPromptAt != null &&
        timestamp.difference(lastPromptAt) < exitConfirmWindow) {
      _lastPromptAt = null;
      return BackGestureOutcome.exitApp;
    }

    _lastPromptAt = timestamp;
    return BackGestureOutcome.promptExitConfirmation;
  }
}

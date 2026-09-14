import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/src/shell/back_navigation.dart';

void main() {
  group('BackGestureHandler', () {
    late DateTime now;

    setUp(() {
      now = DateTime(2026, 9, 14, 12, 0, 0);
    });

    test('WebView 还有历史时返回应回退页面而不是退出', () {
      final handler = BackGestureHandler();

      expect(
        handler.evaluate(canGoBack: true, now: now),
        BackGestureOutcome.navigateBackInWebView,
      );
    });

    test('根页面首次返回应提示，确认窗口内再次返回才退出', () {
      final handler = BackGestureHandler();

      expect(
        handler.evaluate(canGoBack: false, now: now),
        BackGestureOutcome.promptExitConfirmation,
      );

      expect(
        handler.evaluate(
          canGoBack: false,
          now: now.add(const Duration(seconds: 1)),
        ),
        BackGestureOutcome.exitApp,
      );
    });

    test('超过确认窗口后再次返回应重新提示', () {
      final handler = BackGestureHandler();

      handler.evaluate(canGoBack: false, now: now);

      expect(
        handler.evaluate(
          canGoBack: false,
          now: now.add(const Duration(seconds: 3)),
        ),
        BackGestureOutcome.promptExitConfirmation,
      );
    });

    test('回退页面历史后应清空待退出的确认状态', () {
      final handler = BackGestureHandler();

      handler.evaluate(canGoBack: false, now: now);

      expect(
        handler.evaluate(
          canGoBack: true,
          now: now.add(const Duration(seconds: 1)),
        ),
        BackGestureOutcome.navigateBackInWebView,
      );

      // 页面回退后原有的“再按一次退出”提示不应继续生效。
      expect(
        handler.evaluate(
          canGoBack: false,
          now: now.add(const Duration(seconds: 2)),
        ),
        BackGestureOutcome.promptExitConfirmation,
      );
    });
  });
}

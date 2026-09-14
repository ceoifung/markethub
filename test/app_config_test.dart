import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/src/config/app_config.dart';

void main() {
  test('remote base url defaults to empty when not injected', () {
    expect(AppConfig.remoteBaseUrl, isEmpty);
    expect(AppConfig.hasRemoteBaseUrl, isFalse);
  });
}

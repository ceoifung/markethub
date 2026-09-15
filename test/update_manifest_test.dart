import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/src/update/update_service.dart';

void main() {
  group('latestManifestUri 清单地址构造', () {
    test('必须包含 releases/latest/download 完整路径(不能用resolve拼接)', () {
      // 回归: resolve('latest/...') 在无尾斜杠基准上会丢掉 releases 段
      final uri = UpdateService.latestManifestUri(repository: 'ceoifung/markethub');
      expect(uri.toString(),
          'https://github.com/ceoifung/markethub/releases/latest/download/version.yaml');
    });

    test('仓库为空时返回null', () {
      expect(UpdateService.latestManifestUri(repository: ''), isNull);
    });
  });

  group('parseFlatYaml (version.yaml 清单解析)', () {
    test('解析CI生成的清单字段', () {
      const text = '''
# 由CI生成
version: 1.2.0+6
tag: v1.2.0+6
apkUrl: https://github.com/ceoifung/markethub/releases/download/v1.2.0%2B6/markethub-1.2.0%2B6.apk
releaseUrl: https://github.com/ceoifung/markethub/releases/tag/v1.2.0%2B6
date: 2026-09-15T12:00:00Z
''';
      final fields = UpdateService.parseFlatYaml(text);
      expect(fields['version'], '1.2.0+6');
      expect(fields['tag'], 'v1.2.0+6');
      expect(fields['apkUrl'], contains('markethub-1.2.0%2B6.apk'));
      expect(fields['date'], '2026-09-15T12:00:00Z');
    });

    test('忽略注释/多行块引导符/缩进行/无冒号行', () {
      const text = '''
# 注释
version: 1.0.0+1
notes: |
  多行说明第一行
  多行说明第二行
  缩进内容 ignored
broken line no colon
''';
      final fields = UpdateService.parseFlatYaml(text);
      expect(fields['version'], '1.0.0+1');
      expect(fields['notes'], isNull);
      expect(fields.containsKey('broken line no colon'), isFalse);
    });

    test('空串与纯注释返回空map', () {
      expect(UpdateService.parseFlatYaml(''), isEmpty);
      expect(UpdateService.parseFlatYaml('# only comment\n'), isEmpty);
    });
  });
}

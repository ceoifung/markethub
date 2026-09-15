import 'package:flutter_test/flutter_test.dart';
import 'package:markethub/src/notify/alert_channel.dart';

Map<String, Object?> alertJson(
  String id,
  int ts, {
  int level = 2,
  String type = 'buy',
  String title = '标题',
}) =>
    {'id': id, 'ts': ts, 'level': level, 'type': type, 'title': title, 'body': '内容'};

void main() {
  group('parseAlertsResponse', () {
    test('解析正常响应并按时间升序排列', () {
      final items = parseAlertsResponse({
        'alerts': [
          alertJson('b', 200),
          alertJson('a', 100),
        ],
      });
      expect(items.map((e) => e.id).toList(), ['a', 'b']);
    });

    test('忽略缺 id/缺标题/非正时间戳/非对象的条目', () {
      final items = parseAlertsResponse({
        'alerts': [
          alertJson('ok', 100),
          {'ts': 100, 'title': '缺id'},
          alertJson('no-title', 100)..remove('title'),
          alertJson('zero-ts', 0),
          '不是map',
        ],
      });
      expect(items.map((e) => e.id).toList(), ['ok']);
    });

    test('响应结构不对时返回空列表', () {
      expect(parseAlertsResponse(null), isEmpty);
      expect(parseAlertsResponse('string'), isEmpty);
      expect(parseAlertsResponse({'alerts': 'not-list'}), isEmpty);
      expect(parseAlertsResponse({}), isEmpty);
    });
  });

  group('selectAlertDelta', () {
    test('首次轮询(since=0)只对齐游标, 不补弹历史消息', () {
      final delta = selectAlertDelta(
        [AlertItem.fromJson(alertJson('a', 100)), AlertItem.fromJson(alertJson('b', 300))],
        since: 0,
        seen: const [],
      );
      expect(delta.toNotify, isEmpty);
      expect(delta.cursor, 300);
    });

    test('按级别过滤: 默认只通知紧急(1)与重要(2)', () {
      final alerts = [
        AlertItem.fromJson(alertJson('urgent', 100, level: 1)),
        AlertItem.fromJson(alertJson('important', 200, level: 2)),
        AlertItem.fromJson(alertJson('normal', 300, level: 3)),
      ];
      final delta = selectAlertDelta(alerts, since: 50, seen: const []);
      expect(delta.toNotify.map((e) => e.id).toList(), ['urgent', 'important']);
      expect(delta.cursor, 300);
    });

    test('已通知过的 id 不重复弹窗', () {
      final delta = selectAlertDelta(
        [AlertItem.fromJson(alertJson('dup', 100))],
        since: 50,
        seen: const ['dup'],
      );
      expect(delta.toNotify, isEmpty);
    });

    test('游标取本轮最大 ts, 已通知 id 写回并环形裁剪', () {
      final seen = List.generate(80, (i) => 'old$i');
      final delta = selectAlertDelta(
        [AlertItem.fromJson(alertJson('new1', 500)), AlertItem.fromJson(alertJson('new2', 900))],
        since: 400,
        seen: seen,
      );
      expect(delta.cursor, 900);
      expect(delta.toNotify.map((e) => e.id).toList(), ['new1', 'new2']);
      expect(delta.updatedSeen.length, 80);
      expect(delta.updatedSeen.contains('new2'), isTrue);
      expect(delta.updatedSeen.contains('old0'), isFalse);
    });
  });
}

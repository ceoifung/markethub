// 告警通知的纯逻辑: 解析 /api/alerts 响应 + 级别过滤 + 去重游标。
// 不依赖任何插件, 便于单元测试; 约定与后端 alerts.js 的环形队列对齐。
// 级别: 1=紧急(回撤熔断等) 2=重要(买卖点/放量异动/模拟盘成交) 3=一般(缩量等)。

const String kPrefNotifyEnabled = 'notify.enabled';
const String kPrefNotifyRemoteBase = 'notify.remote_base';
const String kPrefNotifySince = 'notify.since';
const String kPrefNotifySeenIds = 'notify.seen_ids';

/// 通知点击后要打开的前端 hash 路由(消息中心)。
const String kTapRouteAlertsCenter = 'alerts-center';

class AlertItem {
  const AlertItem({
    required this.id,
    required this.ts,
    required this.level,
    required this.type,
    required this.title,
    required this.body,
  });

  final String id;
  final int ts;
  final int level;
  final String type;
  final String title;
  final String body;

  factory AlertItem.fromJson(Map<String, Object?> json) {
    return AlertItem(
      id: json['id']?.toString() ?? '',
      ts: (json['ts'] as num?)?.toInt() ?? 0,
      level: (json['level'] as num?)?.toInt() ?? 3,
      type: json['type']?.toString() ?? '',
      title: json['title']?.toString() ?? '',
      body: json['body']?.toString() ?? '',
    );
  }
}

/// 解析 GET /api/alerts?since= 的响应体(已 jsonDecode), 忽略坏数据并按时间升序返回。
List<AlertItem> parseAlertsResponse(Object? body) {
  if (body is! Map) return const [];
  final raw = body['alerts'];
  if (raw is! List) return const [];
  final items = <AlertItem>[];
  for (final entry in raw) {
    if (entry is! Map) continue;
    final item = AlertItem.fromJson(entry.cast<String, Object?>());
    if (item.id.isEmpty || item.title.isEmpty || item.ts <= 0) continue;
    items.add(item);
  }
  items.sort((a, b) => a.ts.compareTo(b.ts));
  return items;
}

/// 一轮轮询的增量结果。
class AlertDelta {
  const AlertDelta({
    required this.toNotify,
    required this.cursor,
    required this.updatedSeen,
  });

  /// 需要弹通知的告警(已过滤级别并去重, 按时间升序)。
  final List<AlertItem> toNotify;

  /// 写回的 since 游标(本轮见到的最大 ts)。
  final int cursor;

  /// 去重后写回的已通知 id 列表(环形裁剪)。
  final List<String> updatedSeen;
}

/// 从响应里选出要通知的告警。
///
/// - [since] 上次游标; 为 0 表示首次轮询: 只把游标对齐到最新, 不补弹历史消息。
/// - [seen] 上次已通知过的 id 列表, 兜底防止同 ts 边界的重复弹窗。
/// - [maxLevel] 通知的级别上限, 默认只推紧急(1)与重要(2)。
AlertDelta selectAlertDelta(
  List<AlertItem> alerts, {
  required int since,
  required List<String> seen,
  int maxLevel = 2,
  int seenCapacity = 80,
}) {
  var cursor = since;
  final seenSet = seen.toSet();
  final toNotify = <AlertItem>[];
  for (final a in alerts) {
    if (a.ts > cursor) cursor = a.ts;
    if (since == 0 || seenSet.contains(a.id) || a.level > maxLevel) continue;
    seenSet.add(a.id);
    toNotify.add(a);
  }
  var updatedSeen = seenSet.toList();
  if (updatedSeen.length > seenCapacity) {
    updatedSeen = updatedSeen.sublist(updatedSeen.length - seenCapacity);
  }
  return AlertDelta(toNotify: toNotify, cursor: cursor, updatedSeen: updatedSeen);
}

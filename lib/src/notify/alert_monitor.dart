// 行情告警后台监控: 用前台服务常驻(等价 ntfy App 的保活方式),
// 每 30 秒轮询远端 /api/alerts 增量流, 新告警按级别弹系统通知。
// 主 isolate 负责 init/开关/权限; 轮询逻辑跑在前台服务的后台 isolate, 经 SharedPreferences 传递状态。
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_foreground_task/flutter_foreground_task.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import 'alert_channel.dart';

const String _kForegroundChannelId = 'markethub_monitor';

FlutterLocalNotificationsPlugin _notificationsPlugin() {
  return FlutterLocalNotificationsPlugin();
}

/// 初始化通知插件(前台/后台 isolate 各自调用一次, 重复调用无副作用)。
Future<void> _ensureNotificationsInitialized() async {
  await _notificationsPlugin().initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
  );
}

/// 前台服务入口(后台 isolate 执行, 需防树摇裁剪)。
@pragma('vm:entry-point')
void alertMonitorCallback() {
  FlutterForegroundTask.setTaskHandler(AlertMonitorTaskHandler());
}

class AlertMonitorTaskHandler extends TaskHandler {
  @override
  Future<void> onStart(DateTime timestamp, TaskStarter starter) async {
    unawaited(pollOnce());
  }

  // onRepeatEvent 是同步签名, 异步轮询交给事件循环, 不阻塞调度。
  @override
  void onRepeatEvent(DateTime timestamp) {
    unawaited(pollOnce());
  }

  @override
  Future<void> onDestroy(DateTime timestamp, bool isTimeout) async {}
}

String _clock() {
  final now = DateTime.now();
  final hour = now.hour.toString().padLeft(2, '0');
  final minute = now.minute.toString().padLeft(2, '0');
  return '$hour:$minute';
}

/// 单轮轮询: 拉增量告警 → 过滤去重 → 弹通知 → 写回游标。
Future<void> pollOnce() async {
  final prefs = await SharedPreferences.getInstance();
  final remoteBase =
      (prefs.getString(kPrefNotifyRemoteBase) ?? AppConfig.remoteBaseUrl).trim();
  if (remoteBase.isEmpty) return;

  try {
    final since = prefs.getInt(kPrefNotifySince) ?? 0;
    final res = await http
        .get(Uri.parse('$remoteBase/api/alerts?since=$since'))
        .timeout(const Duration(seconds: 20));
    if (res.statusCode != 200) {
      await _updateServiceText('行情监控 · 服务异常(${res.statusCode})');
      return;
    }
    final delta = selectAlertDelta(
      parseAlertsResponse(jsonDecode(utf8.decode(res.bodyBytes))),
      since: since,
      seen: prefs.getStringList(kPrefNotifySeenIds) ?? const [],
    );
    if (delta.toNotify.isNotEmpty) {
      await _showAlertNotifications(delta.toNotify);
    }
    await prefs.setInt(kPrefNotifySince, delta.cursor);
    await prefs.setStringList(kPrefNotifySeenIds, delta.updatedSeen);
    await _updateServiceText(
      delta.toNotify.isEmpty
          ? '行情监控运行中 · $_clock()'
          : '行情监控 · ${delta.toNotify.length} 条新提醒 · $_clock()',
    );
  } catch (_) {
    await _updateServiceText('行情监控 · 网络异常, 稍后重试');
  }
}

Future<void> _updateServiceText(String text) async {
  if (await FlutterForegroundTask.isRunningService) {
    await FlutterForegroundTask.updateService(notificationText: text);
  }
}

Future<void> _showAlertNotifications(List<AlertItem> alerts) async {
  await _ensureNotificationsInitialized();
  final plugin = _notificationsPlugin();
  for (final a in alerts) {
    final urgent = a.level <= 1;
    final details = AndroidNotificationDetails(
      urgent ? 'markethub_alerts_urgent' : 'markethub_alerts',
      urgent ? '紧急提醒' : '行情与模拟盘提醒',
      channelDescription: urgent
          ? '回撤熔断等需要立即关注的事件'
          : '买卖点触发、量价异动与模拟盘成交',
      importance: urgent ? Importance.max : Importance.high,
      priority: urgent ? Priority.max : Priority.high,
    );
    await plugin.show(
      id: a.id.hashCode & 0x7fffffff,
      title: a.title,
      body: a.body,
      notificationDetails: NotificationDetails(android: details),
      payload: kTapRouteAlertsCenter,
    );
  }
}

/// 主 isolate 侧的控制面: 初始化、权限、开关、开机自恢复。
abstract final class AlertMonitor {
  static Future<bool> get enabled async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kPrefNotifyEnabled) ?? false;
  }

  /// App 启动时调用: 初始化通知(含点击回调)与前台服务参数。
  static Future<void> init({void Function(String route)? onNotificationTap}) async {
    await _notificationsPlugin().initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: (response) {
        final route = response.payload;
        if (route != null && route.isNotEmpty) {
          onNotificationTap?.call(route);
        }
      },
    );
    FlutterForegroundTask.init(
      androidNotificationOptions: AndroidNotificationOptions(
        channelId: _kForegroundChannelId,
        channelName: '后台行情监控',
        channelDescription: '保持运行以接收买卖点与模拟盘提醒',
        channelImportance: NotificationChannelImportance.LOW,
        priority: NotificationPriority.LOW,
        onlyAlertOnce: true,
        showWhen: false,
      ),
      iosNotificationOptions: const IOSNotificationOptions(),
      foregroundTaskOptions: ForegroundTaskOptions(
        eventAction: ForegroundTaskEventAction.repeat(30 * 1000),
        autoRunOnBoot: true,
        autoRunOnMyPackageReplaced: true,
        allowWakeLock: true,
      ),
    );
  }

  /// Android 13+ 动态申请通知权限; 已授予或低版本返回 true。
  static Future<bool> requestPermission() async {
    final android = _notificationsPlugin().resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? true;
  }

  static Future<bool> _startService() async {
    if (await FlutterForegroundTask.isRunningService) return true;
    final result = await FlutterForegroundTask.startService(
      serviceTypes: const [ForegroundServiceTypes.dataSync],
      notificationTitle: 'markethub 行情监控',
      notificationText: '正在监控买卖点与模拟盘成交',
      callback: alertMonitorCallback,
    );
    return result is ServiceRequestSuccess;
  }

  /// App 启动时若已启用则拉起前台服务(重启/更新后自恢复)。
  static Future<bool> startIfEnabled() async {
    if (!Platform.isAndroid || !(await enabled)) return false;
    return _startService();
  }

  /// 开关后台监控。开启时依次: 通知权限(拒绝则保持关闭) → 记录配置 →
  /// 请求加入电池优化白名单(降低被系统冻结的概率) → 拉起前台服务。
  static Future<bool> setEnabled(bool value) async {
    final prefs = await SharedPreferences.getInstance();
    if (!value) {
      await prefs.setBool(kPrefNotifyEnabled, false);
      await FlutterForegroundTask.stopService();
      return true;
    }
    if (!(await requestPermission())) {
      return false;
    }
    await prefs.setBool(kPrefNotifyEnabled, true);
    await prefs.setString(kPrefNotifyRemoteBase, AppConfig.remoteBaseUrl);
    await FlutterForegroundTask.requestIgnoreBatteryOptimization();
    return _startService();
  }
}

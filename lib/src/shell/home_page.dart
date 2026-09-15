import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/app_config.dart';
import '../proxy/proxy_server.dart';
import '../update/update_service.dart';
import '../notify/alert_channel.dart';
import '../notify/alert_monitor.dart';
import 'back_navigation.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.proxyServer});

  final ProxyServer proxyServer;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  InAppWebViewController? _webViewController;
  PullToRefreshController? _pullToRefreshController;
  final BackGestureHandler _backGestureHandler = BackGestureHandler();
  double _progress = 0;
  bool _checkedForUpdate = false;
  bool _monitorEnabled = false;
  String? _pendingRoute;
  Offset? _bellPos;

  static const String _kPrefBellX = 'notify.bell_x';
  static const String _kPrefBellY = 'notify.bell_y';

  bool get _supportsPullToRefresh => Platform.isAndroid;

  @override
  void initState() {
    super.initState();
    if (_supportsPullToRefresh) {
      _pullToRefreshController = PullToRefreshController(
        settings: PullToRefreshSettings(
          color: const Color(0xFF2563EB),
        ),
        onRefresh: () async {
          await _webViewController?.reload();
        },
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkForUpdate();
    });

    if (Platform.isAndroid) {
      AlertMonitor.init(onNotificationTap: _openRoute);
      _restoreMonitor();
    }
  }

  Future<void> _restoreMonitor() async {
    final prefs = await SharedPreferences.getInstance();
    final bellX = prefs.getDouble(_kPrefBellX);
    final bellY = prefs.getDouble(_kPrefBellY);
    final enabled = await AlertMonitor.enabled;
    if (!mounted) {
      return;
    }
    setState(() {
      _monitorEnabled = enabled;
      if (bellX != null && bellY != null) {
        _bellPos = Offset(bellX, bellY);
      }
    });
    if (enabled) {
      await AlertMonitor.startIfEnabled();
    }
  }

  Future<void> _persistBellPos() async {
    final pos = _bellPos;
    if (pos == null) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(_kPrefBellX, pos.dx);
    await prefs.setDouble(_kPrefBellY, pos.dy);
  }

  /// 点击通知跳转消息中心(hash 路由注入, 不整页刷新);
  /// WebView 未就绪(通知冷启动 App)时挂起, 待 onLoadStop 后补跳。
  void _openRoute(String route) {
    if (route != kTapRouteAlertsCenter) {
      return;
    }
    final controller = _webViewController;
    if (controller != null) {
      controller.evaluateJavascript(
        source: 'window.location.hash = "#/$kTapRouteAlertsCenter";',
      );
    } else {
      _pendingRoute = route;
    }
  }

  Future<void> _toggleMonitor() async {
    final ok = await AlertMonitor.setEnabled(!_monitorEnabled);
    final enabledNow = await AlertMonitor.enabled;
    if (!mounted) {
      return;
    }
    setState(() {
      _monitorEnabled = enabledNow;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          !ok
              ? '未授予通知权限，请在系统设置中开启后重试。'
              : (enabledNow ? '已开启后台提醒：买卖点与模拟盘成交将实时通知。' : '已关闭后台提醒。'),
        ),
      ),
    );
  }

  @override
  void dispose() {
    widget.proxyServer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: _onSystemBack,
      child: Scaffold(
        body: Stack(
          children: [
            Column(
              children: [
                if (_progress > 0 && _progress < 1)
                  LinearProgressIndicator(value: _progress),
                Expanded(
                  child: InAppWebView(
                    initialUrlRequest: URLRequest(
                      url: WebUri(widget.proxyServer.entryUrl),
                    ),
                    pullToRefreshController: _pullToRefreshController,
                    initialSettings: InAppWebViewSettings(
                      javaScriptEnabled: true,
                      mediaPlaybackRequiresUserGesture: false,
                      allowsInlineMediaPlayback: true,
                      useShouldOverrideUrlLoading: true,
                    ),
                    onWebViewCreated: (controller) {
                      _webViewController = controller;
                    },
                  onLoadStop: (controller, url) async {
                    await _pullToRefreshController?.endRefreshing();
                    final pending = _pendingRoute;
                    if (pending != null) {
                      _pendingRoute = null;
                      _openRoute(pending);
                    }
                  },
                    onReceivedError: (controller, request, error) async {
                      await _pullToRefreshController?.endRefreshing();
                      if (!context.mounted) {
                        return;
                      }
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('页面加载失败：${error.description}'),
                        ),
                      );
                    },
                    onProgressChanged: (controller, progress) async {
                      if (progress == 100) {
                        await _pullToRefreshController?.endRefreshing();
                      }
                      if (!mounted) {
                        return;
                      }
                      setState(() {
                        _progress = progress / 100;
                      });
                    },
                  ),
                ),
              ],
            ),
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: ValueListenableBuilder<ProxySnapshot>(
                valueListenable: widget.proxyServer.snapshot,
                builder: (context, snapshot, child) {
                  return _StatusBanner(snapshot: snapshot);
                },
              ),
            ),
          ),
          if (Platform.isAndroid)
            _buildBellButton(context),
        ],
        ),
      ),
    );
  }

  /// 拦截 Android 系统返回手势：优先回退 WebView 历史（前端 hash 路由
  /// 的每次跳转都会产生一条历史记录），到达根页面后再按一次才退出应用。
  Future<void> _onSystemBack(bool didPop, Object? result) async {
    if (didPop) {
      return;
    }

    final controller = _webViewController;
    final canGoBack = controller != null && await controller.canGoBack();
    if (!mounted) {
      return;
    }

    switch (_backGestureHandler.evaluate(canGoBack: canGoBack)) {
      case BackGestureOutcome.navigateBackInWebView:
        await controller?.goBack();
      case BackGestureOutcome.exitApp:
        await SystemNavigator.pop();
      case BackGestureOutcome.promptExitConfirmation:
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(
            const SnackBar(
              content: Text('再按一次返回键退出应用'),
              duration: Duration(seconds: 2),
            ),
          );
    }
  }

  /// 可拖动的后台提醒开关: 默认悬停在右下角(避开前端底部导航栏),
  /// 拖动后位置持久化; 点击切换开关。
  Widget _buildBellButton(BuildContext context) {
    final size = MediaQuery.of(context).size;
    const buttonSize = 44.0;
    var pos = _bellPos ??
        Offset(size.width - 16 - buttonSize, size.height - 88 - buttonSize);
    return Positioned(
      left: pos.dx,
      top: pos.dy,
      child: GestureDetector(
        onPanUpdate: (details) {
          setState(() {
            pos = Offset(
              (pos.dx + details.delta.dx)
                  .clamp(8.0, size.width - buttonSize - 8.0),
              (pos.dy + details.delta.dy)
                  .clamp(64.0, size.height - buttonSize - 24.0),
            );
            _bellPos = pos;
          });
        },
        onPanEnd: (_) => _persistBellPos(),
        child: Opacity(
          opacity: 0.8,
          child: FloatingActionButton.small(
            onPressed: _toggleMonitor,
            tooltip: _monitorEnabled ? '关闭后台提醒' : '开启后台提醒',
            child: Icon(
              _monitorEnabled
                  ? Icons.notifications_active
                  : Icons.notifications_none,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _checkForUpdate() async {
    if (_checkedForUpdate || !AppConfig.hasGithubRepository || !mounted) {
      return;
    }
    _checkedForUpdate = true;

    try {
      final updateInfo = await UpdateService.checkForUpdate();
      if (!mounted || updateInfo == null) {
        return;
      }

      final action = await showDialog<bool>(
        context: context,
        builder: (context) {
          final notes = updateInfo.releaseNotes.trim();
          final preview = notes.isEmpty
              ? '本次版本没有填写更新说明。'
              : (notes.length > 320 ? '${notes.substring(0, 320)}...' : notes);
          return AlertDialog(
            title: const Text('发现新版本'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('当前版本：${updateInfo.currentVersion}'),
                Text('最新版本：${updateInfo.latestVersion}'),
                const SizedBox(height: 12),
                Text(
                  preview,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('稍后'),
              ),
              FilledButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: const Text('前往升级'),
              ),
            ],
          );
        },
      );

      if (action != true || !mounted) {
        return;
      }

      final opened = await UpdateService.openRelease(updateInfo);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('未能打开升级链接，请稍后重试。')),
        );
      }
    } catch (_) {
      // 启动后的更新检查不应打断主流程，失败时静默忽略。
    }
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.snapshot});

  final ProxySnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    if (_shouldHide(snapshot)) {
      return const SizedBox.shrink();
    }

    final colorScheme = Theme.of(context).colorScheme;
    final isOffline = snapshot.servingFromCache;
    final backgroundColor = isOffline
        ? colorScheme.errorContainer
        : colorScheme.secondaryContainer;
    final foregroundColor = isOffline
        ? colorScheme.onErrorContainer
        : colorScheme.onSecondaryContainer;

    String message;
    if (snapshot.lastSuccessfulSync == null) {
      message = '正在启动本地缓存代理…';
    } else if (isOffline) {
      message =
          '离线缓存模式 · 最近同步 ${_formatTime(snapshot.lastSuccessfulSync!)}';
    } else {
      message = '在线访问中 · 最近同步 ${_formatTime(snapshot.lastSuccessfulSync!)}';
    }

    if (snapshot.lastError != null && snapshot.lastError!.isNotEmpty) {
      message = '$message  ·  ${snapshot.lastError}';
    }

    return Container(
      constraints: const BoxConstraints(maxWidth: 720),
      color: backgroundColor,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Text(
        message,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: foregroundColor, fontSize: 13),
      ),
    );
  }

  static bool _shouldHide(ProxySnapshot snapshot) {
    return snapshot.lastSuccessfulSync != null &&
        !snapshot.servingFromCache &&
        (snapshot.lastError == null || snapshot.lastError!.isEmpty);
  }

  static String _formatTime(DateTime value) {
    final local = value.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}

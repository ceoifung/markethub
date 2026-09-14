import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import '../config/app_config.dart';
import '../proxy/proxy_server.dart';
import '../update/update_service.dart';

class HomePage extends StatefulWidget {
  const HomePage({super.key, required this.proxyServer});

  final ProxyServer proxyServer;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  InAppWebViewController? _webViewController;
  PullToRefreshController? _pullToRefreshController;
  double _progress = 0;
  bool _checkedForUpdate = false;

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
  }

  @override
  void dispose() {
    widget.proxyServer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
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
        ],
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

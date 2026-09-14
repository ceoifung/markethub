import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'src/app.dart';
import 'src/config/app_config.dart';
import 'src/proxy/cache_store.dart';
import 'src/proxy/proxy_server.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android && kDebugMode) {
    await InAppWebViewController.setWebContentsDebuggingEnabled(true);
  }

  final remoteBaseUri = AppConfig.remoteBaseUri;
  if (remoteBaseUri == null) {
    runApp(
      const BootstrapErrorApp(
        message:
            '未注入 REMOTE_BASE_URL。请在运行或构建时通过 --dart-define 传入远端地址，或在 GitHub Actions 里配置同名 Secret。',
      ),
    );
    return;
  }

  final cacheStore = await CacheStore.create();
  final proxyServer = ProxyServer(
    cacheStore: cacheStore,
    remoteBaseUri: remoteBaseUri,
  );
  await proxyServer.start();

  runApp(MarketHubShellApp(proxyServer: proxyServer));
}

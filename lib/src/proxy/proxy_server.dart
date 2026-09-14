import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';

import '../config/app_config.dart';
import 'cache_store.dart';

class ProxySnapshot {
  const ProxySnapshot({
    this.servingFromCache = false,
    this.lastSuccessfulSync,
    this.lastError,
  });

  final bool servingFromCache;
  final DateTime? lastSuccessfulSync;
  final String? lastError;

  ProxySnapshot copyWith({
    bool? servingFromCache,
    DateTime? lastSuccessfulSync,
    String? lastError,
    bool clearError = false,
  }) {
    return ProxySnapshot(
      servingFromCache: servingFromCache ?? this.servingFromCache,
      lastSuccessfulSync: lastSuccessfulSync ?? this.lastSuccessfulSync,
      lastError: clearError ? null : (lastError ?? this.lastError),
    );
  }
}

class ProxyServer {
  ProxyServer({
    required this.cacheStore,
    required this.remoteBaseUri,
  });

  final CacheStore cacheStore;
  final Uri remoteBaseUri;
  final ValueNotifier<ProxySnapshot> snapshot =
      ValueNotifier(const ProxySnapshot());

  HttpServer? _server;
  HttpClient? _client;

  String get entryUrl {
    final server = _server;
    if (server == null) {
      throw StateError('Proxy server has not started.');
    }
    return 'http://127.0.0.1:${server.port}/';
  }

  Future<void> start() async {
    _client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 12)
      ..idleTimeout = const Duration(seconds: 10)
      ..maxConnectionsPerHost = 8;

    _server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    unawaited(_server!.forEach(_handleRequest));
  }

  Future<void> dispose() async {
    snapshot.dispose();
    _client?.close(force: true);
    await _server?.close(force: true);
  }

  Future<void> _handleRequest(HttpRequest request) async {
    if (request.uri.path == '/__shell_status') {
      await _writeJson(
        request.response,
        {
          'remoteBaseUrl': remoteBaseUri.toString(),
          'servingFromCache': snapshot.value.servingFromCache,
          'lastSuccessfulSync':
              snapshot.value.lastSuccessfulSync?.toIso8601String(),
          'lastError': snapshot.value.lastError,
        },
      );
      return;
    }

    final remoteUri = _resolveRemoteUri(request.uri);
    final cachedResponse =
        request.method == 'GET' ? await cacheStore.read(remoteUri) : null;

    try {
      final upstream = await _openUpstream(request, remoteUri);
      final bytes = await _readAll(upstream);
      final headers = _collectHeaders(upstream.headers);

      if (_isCacheable(request, upstream.statusCode, bytes.length)) {
        await cacheStore.write(
          uri: remoteUri,
          statusCode: upstream.statusCode,
          headers: headers,
          body: bytes,
        );
      }

      snapshot.value = snapshot.value.copyWith(
        servingFromCache: false,
        lastSuccessfulSync: DateTime.now(),
        clearError: true,
      );

      await _writeResponse(
        request.response,
        statusCode: upstream.statusCode,
        headers: headers,
        body: bytes,
      );
    } catch (error) {
      if (cachedResponse != null) {
        snapshot.value = snapshot.value.copyWith(
          servingFromCache: true,
          lastError: error.toString(),
        );

        final headers = Map<String, String>.from(cachedResponse.headers)
          ..['x-market-hub-cache'] = 'stale';
        await _writeResponse(
          request.response,
          statusCode: cachedResponse.statusCode,
          headers: headers,
          body: cachedResponse.body,
        );
        return;
      }

      snapshot.value = snapshot.value.copyWith(lastError: error.toString());
      await _writeJson(
        request.response,
        {
          'error': 'Unable to reach remote MarketHub service.',
          'detail': error.toString(),
        },
        statusCode: HttpStatus.badGateway,
      );
    }
  }

  Uri _resolveRemoteUri(Uri localUri) {
    final path = localUri.path.isEmpty ? '/' : localUri.path;
    return remoteBaseUri.replace(path: path, query: localUri.hasQuery ? localUri.query : null);
  }

  Future<HttpClientResponse> _openUpstream(
    HttpRequest request,
    Uri remoteUri,
  ) async {
    final client = _client;
    if (client == null) {
      throw StateError('Proxy client has not started.');
    }

    final upstreamRequest = await client.openUrl(request.method, remoteUri);
    request.headers.forEach((name, values) {
      final normalizedName = name.toLowerCase();
      if (_hopByHopHeaders.contains(normalizedName) ||
          normalizedName == 'host' ||
          normalizedName == 'content-length') {
        return;
      }
      for (final value in values) {
        upstreamRequest.headers.add(name, value);
      }
    });

    if (_hasRequestBody(request.method)) {
      await upstreamRequest.addStream(request);
    }

    return upstreamRequest.close();
  }

  Future<Uint8List> _readAll(HttpClientResponse response) async {
    final builder = BytesBuilder(copy: false);
    await for (final chunk in response) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Map<String, String> _collectHeaders(HttpHeaders headers) {
    final result = <String, String>{};
    headers.forEach((name, values) {
      if (_hopByHopHeaders.contains(name.toLowerCase())) {
        return;
      }
      result[name] = values.join(', ');
    });
    return result;
  }

  Future<void> _writeResponse(
    HttpResponse response, {
    required int statusCode,
    required Map<String, String> headers,
    required List<int> body,
  }) async {
    response.statusCode = statusCode;
    headers.forEach((name, value) {
      final normalizedName = name.toLowerCase();
      if (_hopByHopHeaders.contains(normalizedName) ||
          normalizedName == 'content-length') {
        return;
      }
      response.headers.set(name, value);
    });

    if (body.isNotEmpty) {
      response.add(body);
    }
    await response.close();
  }

  Future<void> _writeJson(
    HttpResponse response,
    Map<String, Object?> payload, {
    int statusCode = HttpStatus.ok,
  }) {
    return _writeResponse(
      response,
      statusCode: statusCode,
      headers: const {'content-type': 'application/json; charset=utf-8'},
      body: utf8.encode(jsonEncode(payload)),
    );
  }

  bool _isCacheable(HttpRequest request, int statusCode, int bodyLength) {
    return request.method == 'GET' &&
        statusCode == HttpStatus.ok &&
        bodyLength <= AppConfig.maxCachedResponseBytes;
  }

  bool _hasRequestBody(String method) {
    return !const {'GET', 'HEAD'}.contains(method.toUpperCase());
  }

  static const Set<String> _hopByHopHeaders = {
    'connection',
    'content-length',
    'host',
    'keep-alive',
    'proxy-authenticate',
    'proxy-authorization',
    'te',
    'trailer',
    'transfer-encoding',
    'upgrade',
  };
}

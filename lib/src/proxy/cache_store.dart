import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:path_provider/path_provider.dart';

class CachedResponse {
  CachedResponse({
    required this.uri,
    required this.statusCode,
    required this.headers,
    required this.body,
    required this.cachedAt,
  });

  final Uri uri;
  final int statusCode;
  final Map<String, String> headers;
  final Uint8List body;
  final DateTime cachedAt;
}

class CacheStore {
  CacheStore._(this._rootDirectory);

  final Directory _rootDirectory;

  static Future<CacheStore> create() async {
    final baseDirectory = await getApplicationSupportDirectory();
    final rootDirectory = Directory(
      '${baseDirectory.path}${Platform.pathSeparator}runtime_cache',
    );
    await rootDirectory.create(recursive: true);
    return CacheStore._(rootDirectory);
  }

  Future<void> write({
    required Uri uri,
    required int statusCode,
    required Map<String, String> headers,
    required List<int> body,
  }) async {
    final key = _keyForUri(uri);
    final bodyFile = File(_bodyFilePath(key));
    final metadataFile = File(_metadataFilePath(key));

    await bodyFile.writeAsBytes(body, flush: true);
    await metadataFile.writeAsString(
      jsonEncode({
        'url': uri.toString(),
        'statusCode': statusCode,
        'headers': headers,
        'cachedAt': DateTime.now().toUtc().toIso8601String(),
      }),
      flush: true,
    );
  }

  Future<CachedResponse?> read(Uri uri) async {
    final key = _keyForUri(uri);
    final bodyFile = File(_bodyFilePath(key));
    final metadataFile = File(_metadataFilePath(key));

    if (!await bodyFile.exists() || !await metadataFile.exists()) {
      return null;
    }

    try {
      final metadata = jsonDecode(await metadataFile.readAsString()) as Map;
      final body = await bodyFile.readAsBytes();
      final headers = <String, String>{};
      final rawHeaders = metadata['headers'];
      if (rawHeaders is Map) {
        for (final entry in rawHeaders.entries) {
          headers[entry.key.toString()] = entry.value.toString();
        }
      }

      return CachedResponse(
        uri: uri,
        statusCode: (metadata['statusCode'] as num?)?.toInt() ?? 200,
        headers: headers,
        body: body,
        cachedAt: DateTime.tryParse(metadata['cachedAt']?.toString() ?? '') ??
            DateTime.fromMillisecondsSinceEpoch(0),
      );
    } catch (_) {
      return null;
    }
  }

  String _keyForUri(Uri uri) {
    return sha1.convert(utf8.encode(uri.toString())).toString();
  }

  String _bodyFilePath(String key) {
    return '${_rootDirectory.path}${Platform.pathSeparator}$key.bin';
  }

  String _metadataFilePath(String key) {
    return '${_rootDirectory.path}${Platform.pathSeparator}$key.json';
  }
}

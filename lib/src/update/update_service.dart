import 'dart:io';
import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/app_config.dart';

class UpdateInfo {
  const UpdateInfo({
    required this.currentVersion,
    required this.latestVersion,
    required this.releaseNotes,
    required this.releasePageUri,
    required this.downloadUri,
  });

  final String currentVersion;
  final String latestVersion;
  final String releaseNotes;
  final Uri releasePageUri;
  final Uri? downloadUri;
}

class UpdateService {
  static Future<UpdateInfo?> checkForUpdate() async {
    final releaseApiUri = AppConfig.latestReleaseApiUri;
    if (releaseApiUri == null) {
      return null;
    }

    final packageInfo = await PackageInfo.fromPlatform();
    final currentVersion = _fullVersion(
      packageInfo.version,
      packageInfo.buildNumber,
    );

    final response = await http.get(
      releaseApiUri,
      headers: {
        'Accept': 'application/vnd.github+json',
        'User-Agent': '${AppConfig.appTitle}/$currentVersion',
      },
    );

    if (response.statusCode != 200) {
      return null;
    }

    final payload = jsonDecode(response.body);
    if (payload is! Map<String, dynamic>) {
      return null;
    }

    if (payload['draft'] == true || payload['prerelease'] == true) {
      return null;
    }

    final latestVersion = _normalizeVersion(payload['tag_name']?.toString() ?? '');
    if (latestVersion.isEmpty ||
        _compareVersions(latestVersion, currentVersion) <= 0) {
      return null;
    }

    final releasePageUri = Uri.tryParse(
      payload['html_url']?.toString() ?? AppConfig.releasesPageUri.toString(),
    );
    if (releasePageUri == null) {
      return null;
    }

    Uri? downloadUri;
    final assets = payload['assets'];
    if (assets is List) {
      for (final asset in assets) {
        if (asset is! Map<String, dynamic>) {
          continue;
        }
        final name = asset['name']?.toString().toLowerCase() ?? '';
        final url = asset['browser_download_url']?.toString() ?? '';
        if (name.endsWith('.apk') && url.isNotEmpty) {
          downloadUri = Uri.tryParse(url);
          break;
        }
      }
    }

    return UpdateInfo(
      currentVersion: currentVersion,
      latestVersion: latestVersion,
      releaseNotes: payload['body']?.toString().trim() ?? '',
      releasePageUri: releasePageUri,
      downloadUri: downloadUri,
    );
  }

  static Future<bool> openRelease(UpdateInfo updateInfo) {
    final targetUri = Platform.isAndroid
        ? (updateInfo.downloadUri ?? updateInfo.releasePageUri)
        : updateInfo.releasePageUri;
    return launchUrl(
      targetUri,
      mode: LaunchMode.externalApplication,
    );
  }

  static String _fullVersion(String versionName, String buildNumber) {
    if (buildNumber.trim().isEmpty) {
      return versionName.trim();
    }
    return '${versionName.trim()}+${buildNumber.trim()}';
  }

  static String _normalizeVersion(String rawVersion) {
    return rawVersion.trim().replaceFirst(RegExp(r'^v'), '');
  }

  static int _compareVersions(String left, String right) {
    final leftParts = _parseVersion(left);
    final rightParts = _parseVersion(right);
    for (var index = 0; index < leftParts.length; index++) {
      final comparison = leftParts[index].compareTo(rightParts[index]);
      if (comparison != 0) {
        return comparison;
      }
    }
    return 0;
  }

  static List<int> _parseVersion(String value) {
    final normalized = _normalizeVersion(value);
    final matcher =
        RegExp(r'^(\d+)\.(\d+)\.(\d+)(?:\+(\d+))?$').firstMatch(normalized);
    if (matcher == null) {
      return const [0, 0, 0, 0];
    }
    return [
      int.parse(matcher.group(1)!),
      int.parse(matcher.group(2)!),
      int.parse(matcher.group(3)!),
      int.parse(matcher.group(4) ?? '0'),
    ];
  }
}

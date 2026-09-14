/*
 * @Author: Ceoifung
 * @Date: 2026-08-28 13:39:58
 * @LastEditors: Ceoifung
 * @LastEditTime: 2026-09-14 16:05:42
 * @Description: XiaoRGEEK All Rights Reserved. Powered By Ceoifung
 */
abstract final class AppConfig {
  static const String appTitle = 'markethub';
  static const String remoteBaseUrl = String.fromEnvironment('REMOTE_BASE_URL');
  static const String githubRepository =
      String.fromEnvironment('GITHUB_REPOSITORY');
  static const int maxCachedResponseBytes = 8 * 1024 * 1024;

  static bool get hasRemoteBaseUrl => remoteBaseUrl.trim().isNotEmpty;

  static bool get hasGithubRepository => githubRepository.trim().isNotEmpty;

  static Uri? get remoteBaseUri =>
      hasRemoteBaseUrl ? Uri.tryParse(remoteBaseUrl) : null;

  static Uri? get latestReleaseApiUri => hasGithubRepository
      ? Uri.parse('https://api.github.com/repos/$githubRepository/releases/latest')
      : null;

  static Uri? get releasesPageUri => hasGithubRepository
      ? Uri.parse('https://github.com/$githubRepository/releases')
      : null;
}

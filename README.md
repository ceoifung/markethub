# markethub

Flutter 壳应用，默认加载远端 MarketHub，并带运行期缓存、GitHub Release 更新检查，以及 Android 正式签名发布流程。

## 当前能力

- 支持平台：Android、Windows
- 网站资源不打包进 App
- 首次联网访问后缓存页面资源和 `GET /api/*` 响应
- 远端不可达时回退到最近一次成功缓存
- 启动后自动检查 GitHub Release 新版本
- Android Release 支持正式签名
- GitHub Actions 可自动构建并发布 Android APK

## 关键目录

- `lib/src/proxy/proxy_server.dart`：本地代理与缓存回退
- `lib/src/update/update_service.dart`：GitHub Release 版本检查
- `android/app/build.gradle.kts`：Android 签名配置
- `.github/workflows/android_release.yml`：Android 发布工作流
- `scripts/setup_github_secrets.ps1`：把本地证书和远端地址写入 GitHub Secrets

## 运行

本地运行时需要通过 `--dart-define` 注入远端地址：

```powershell
flutter pub get
flutter run -d android --dart-define=REMOTE_BASE_URL=http://your-host:8123/ --dart-define=GITHUB_REPOSITORY=owner/repo
flutter run -d windows --dart-define=REMOTE_BASE_URL=http://your-host:8123/ --dart-define=GITHUB_REPOSITORY=owner/repo
```

也可以用文件注入：

```powershell
flutter run -d android --dart-define-from-file=android/release.env.json
```

示例文件见：

- `android/release.env.example.json`

## Android 正式签名

本地签名文件：

- `android/upload-keystore.jks`
- `android/key.properties`

这两个文件已经加入 `.gitignore`，不会进入开源仓库。

Gradle 规则：

- 存在 `android/key.properties` 时，Release 使用正式签名
- 不存在时，Release 回退到 debug 签名，方便开发阶段临时出包

## GitHub Actions

工作流文件：

- `.github/workflows/android_release.yml`

触发方式：

- 推送 tag：`v1.0.1+2`
- 手动触发 `workflow_dispatch`

工作流会执行：

1. `flutter pub get`
2. `flutter analyze`
3. `flutter test`
4. 恢复签名文件
5. 构建 signed release APK
6. 上传构建产物
7. 如果是 tag 触发，则自动发布 GitHub Release

## GitHub Secrets

需要配置这些 Secrets：

- `REMOTE_BASE_URL`
- `ANDROID_KEYSTORE_BASE64`
- `ANDROID_STORE_PASSWORD`
- `ANDROID_KEY_ALIAS`
- `ANDROID_KEY_PASSWORD`

如果这个工程后面挂到 GitHub 仓库上，可以直接运行：

```powershell
.\scripts\setup_github_secrets.ps1 -Repo owner/repo -RemoteBaseUrl http://your-host:8123/
```

这个脚本会从本地读取：

- `android/upload-keystore.jks`
- `android/key.properties`

然后自动写入对应 GitHub Secrets。

## 版本发布约定

建议统一：

- `pubspec.yaml`：`version: 1.0.1+2`
- git tag：`v1.0.1+2`
- Release APK：`markethub-1.0.1+2.apk`

App 启动时会读取 GitHub Releases latest，对比当前版本，发现新版本后提示用户打开 Release 附件安装。

## 注意

把远端地址改成 `GitHub Secrets + --dart-define` 后，源码仓库里不会再明文暴露这个地址。

但要说明白：

- 这只能防止“源码泄露地址”
- 对已经安装到用户设备上的 APK，远端地址仍然可能被逆向提取

如果你后面要进一步隐藏服务地址，建议再加一层你自己的更新/配置中转接口，而不是让 App 直接持有真实后端地址。

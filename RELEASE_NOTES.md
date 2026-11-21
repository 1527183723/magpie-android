# magpie Android v0.1.4652

首个公开 Android 构建，基于上游 magpie **v0.1.4652**（2026-11-21）。

## 本次更新

- 上游 magpie 更新到 v0.1.4652。
- 全部构建运行时升级到当前最新稳定版本：
  - Go 1.27.4
  - Bun 1.4.5
  - Gradle 9.9.2
  - Android Gradle Plugin 9.5.2
  - Android SDK Platform 37.2 / Build Tools 37.0.0
  - Android NDK r30
- 应用内新增“检查更新”，直接读取本仓库的 GitHub Release。
- 固定开源签名密钥，后续版本可直接覆盖安装。

## 安装包

| 文件 | 适用设备 | 大小 |
| --- | --- | --- |
| `magpie-android-arm64-v8a.apk` | 绝大多数 Android 手机 | 约 212 MB |
| `magpie-android-x86_64.apk` | x86_64 模拟器 | 约 224 MB |

最低系统版本：Android 16（API 36）。

## 校验

下载后可用 `SHA256SUMS` 核对：

```bash
sha256sum -c SHA256SUMS
```

## 安装

```bash
adb install -r magpie-android-arm64-v8a.apk
```

或在手机上直接点开 APK 安装。首次启动后，网关默认地址为 `http://127.0.0.1:3425/v1`。

完整构建、签名和更新说明见 [README](https://github.com/1527183723/magpie-android#readme)。

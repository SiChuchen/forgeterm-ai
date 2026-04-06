# Flutter 环境搭建

---

## 1. 系统要求

| 要求 | 最低 | 推荐 |
|------|------|------|
| 操作系统 | Windows 10+ / macOS 10.14+ / Ubuntu 18.04+ | Windows 11 / macOS 13+ / Ubuntu 22.04+ |
| 内存 | 4 GB | 8 GB+ |
| 磁盘 | 10 GB | 20 GB+ |
| Android SDK | API 26 (Android 8.0) | API 34 (Android 14) |

---

## 2. Windows 环境搭建

### 2.1 安装 Flutter SDK

```bash
# 1. 下载 Flutter SDK
# https://docs.flutter.dev/release/archive?tab=windows

# 2. 解压到合适位置（不要放 C:\Program Files）
cd C:\Users\YourName\
unzip flutter_windows_xxx.zip

# 3. 添加到 PATH
# 系统环境变量 → Path → 添加：
# C:\Users\YourName\flutter\bin

# 4. 验证安装
flutter --version
```

### 2.2 安装 Android Studio

```bash
# 1. 下载 Android Studio
# https://developer.android.com/studio

# 2. 安装时勾选：
# ☑️ Android SDK
# ☑️ Android Virtual Device

# 3. 配置 Flutter 使用 Android Studio 的 SDK
flutter config --android-studio-dir="C:\Program Files\Android\Android Studio"
```

### 2.3 验证 Android 许可

```bash
# 接受许可
flutter doctor --android-licenses

# 查看状态
flutter doctor
```

---

## 3. macOS 环境搭建

### 3.1 安装 Flutter SDK

```bash
# 方式一：Homebrew
brew install flutter

# 方式二：手动安装
cd ~/Development
curl -O https://storage.googleapis.com/flutter_infra_release/releases/stable/macos/flutter_macos_xxx-stable.zip
unzip flutter_macos_xxx-stable.zip
echo 'export PATH="$PATH:$HOME/Development/flutter/bin"' >> ~/.zshrc
source ~/.zshrc
```

### 3.2 Xcode 安装

```bash
# App Store 安装 Xcode

# 安装命令行工具
xcode-select --install

# 配置 iOS 开发（未来适配 iOS）
flutter doctor
```

---

## 4. Linux 环境搭建 (Ubuntu/Debian)

### 4.1 安装依赖

```bash
sudo apt update
sudo apt install -y curl git unzip xz-utils zip libglu1-mesa clang cmake ninja-build pkg-config libgtk-3-dev liblzma-dev libstdc++-12-dev
```

### 4.2 安装 Flutter SDK

```bash
cd ~
git clone https://github.com/flutter/flutter.git -b stable
echo 'export PATH="$PATH:$HOME/flutter/bin"' >> ~/.bashrc
source ~/.bashrc

# 验证
flutter --version
```

### 4.3 配置 Android SDK

```bash
# 下载 Android command line tools
mkdir -p ~/android-sdk/cmdline-tools
cd ~/android-sdk/cmdline-tools
wget https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip
unzip commandlinetools-linux-xxx.zip
mv cmdline-tools latest

# 设置环境变量
echo 'export ANDROID_HOME="$HOME/android-sdk"' >> ~/.bashrc
echo 'export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin:$ANDROID_HOME/platform-tools"' >> ~/.bashrc
source ~/.bashrc

# 接受许可
yes | sdkmanager --licenses 2>/dev/null

# 安装 Android SDK 组件
sdkmanager "platform-tools" "platforms;android-34" "build-tools;34.0.0"
```

---

## 5. 项目初始化

### 5.1 创建项目

```bash
# 切换到工作目录
cd ~/projects

# 创建项目
flutter create --org com.sshai --project-name ssh_ai_terminal ssh_ai_terminal

# 进入目录
cd ssh_ai_terminal

# 添加依赖到 pubspec.yaml
# (见技术方案文档)

# 获取依赖
flutter pub get

# 验证项目
flutter doctor
```

### 5.2 Git 初始化

```bash
cd ssh_ai_terminal
git init
git add .
git commit -m "Initial commit: Flutter project scaffold"

# 添加远程仓库（如有）
git remote add origin https://github.com/yourname/ssh-ai-terminal.git
git push -u origin main
```

---

## 6. 开发工具推荐

### 6.1 IDE

| IDE | 说明 |
|-----|------|
| **VS Code** | 轻量级，推荐 |
| **Android Studio** | 功能全，但重 |
| **IntelliJ IDEA** | Flutter 插件支持好 |

### 6.2 VS Code 插件

```
Flutter
Dart
Flutter Widget Snippets
Awesome Flutter Snippets
GitLens
```

### 6.3 调试工具

```bash
# Flutter DevTools
flutter run --devtools

# 查看日志
adb logcat | grep flutter
```

---

## 7. 构建与发布

### 7.1 构建 Debug APK

```bash
flutter build apk --debug
# 输出：build/app/outputs/flutter-apk/app-debug.apk
```

### 7.2 构建 Release APK

```bash
flutter build apk --release
# 输出：build/app/outputs/flutter-apk/app-release.apk
```

### 7.3 构建 Bundle (Google Play)

```bash
flutter build appbundle
# 输出：build/app/outputs/bundle/release/app-release.aab
```

---

## 8. 常见问题

### 8.1 Flutter SDK 版本不对

```bash
# 切换稳定版
flutter channel stable
flutter upgrade

# 切换指定版本
flutter version 3.24.0
```

### 8.2 Android SDK 找不到

```bash
# 设置 SDK 路径
flutter config --android-sdk /path/to/android-sdk
```

### 8.3 依赖下载失败

```bash
# 清除缓存重新获取
flutter pub cache repair
flutter pub get
```

### 8.4 Gradle 构建失败

```bash
# 删除 .gradle 目录重新构建
rm -rf android/.gradle
flutter clean
flutter pub get
flutter build apk
```

---

## 9. 验证清单

```bash
# 运行 flutter doctor，应该看到：
# ✓ Flutter
# ✓ Android toolchain
# ✓ Chrome (if web support needed)
# ✓ Visual Studio (if Windows desktop needed)
```

---

## 10. 下一步

环境搭建完成后：
1. 运行 `flutter create` 创建项目
2. 配置 pubspec.yaml 依赖
3. 运行 `flutter run` 验证
4. 开始开发

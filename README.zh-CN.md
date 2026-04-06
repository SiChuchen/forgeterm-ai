<p align="center">
  <img src="./docs/assets/forgeterm-ai-logo.png" alt="ForgeTerm AI logo" width="128" />
</p>

# ForgeTerm AI

[English](./README.md) | 简体中文

面向 Android 的开源移动端 SSH + AI 终端。

ForgeTerm AI 让你可以直接通过手机连接远程服务器、维护多个 Shell 会话、进行端口转发，并在同一套终端工作流中接入 OpenCode、OpenClaw 等远端 AI 编码工具。

---

## 为什么做这个项目

- 需要快速响应时，可以直接在手机上使用 SSH。
- 把终端访问和 AI 辅助放在同一个应用里。
- 在本地统一管理服务器、会话、密钥和快捷命令。
- 保持本地优先：服务器配置、对话和偏好设置都保存在设备上。

---

## 当前可以做什么

- 使用密码或私钥连接服务器
- 首次连接时通过 TOFU 校验主机指纹
- 使用跳板机
- 保持多个 Shell 会话
- 在短暂断线后自动重连
- 配置本地和远程端口转发
- 检测并使用远端 OpenCode / OpenClaw
- 在本地持久化服务器、密钥、会话、快捷命令和主题偏好

---

## 当前状态

当前主线 SSH + AI 工作流已经可以使用。

已实现：

- SSH 连接管理
- 多会话终端流程
- 端口转发
- OpenCode / OpenClaw 集成
- Hive + Secure Storage 本地持久化
- Android 前台服务接入

仍在完善或暂未包含：

- 后台 / 息屏长连接仍需更多真机验证
- Mosh 尚未实现
- 云同步、账号体系、订阅尚未实现

---

## 快速开始

当前分发方式：从源码构建。

环境要求：

- Flutter SDK
- Android 构建环境
- 可访问的 SSH 服务器
- 可选：远端已安装 OpenCode 或 OpenClaw

本地运行：

```bash
flutter pub get
flutter run
```

构建 Release APK：

```bash
dart run tool/verify.dart build-apk
```

---

## 典型使用流程

1. 添加一个服务器，配置密码或私钥认证。
2. 连接服务器并打开 Shell 会话。
3. 如果需要，继续打开更多会话。
4. 打开 AI Assistant，让应用检测远端可用工具。
5. 如果远端工具需要 HTTP 接口，则使用端口转发访问。

---

## 本地优先的数据模型

- 服务器配置、快捷命令、AI 会话和界面偏好保存在本地 Hive。
- 密码、私钥、口令和 AI 服务密码保存在本地安全存储。
- 当前代码库不包含云同步、账号体系、遥测或订阅系统。

---

## 中文文档

如果你想看当前实现的更详细说明，可以从 `docs/` 目录开始。当前项目的大部分实现文档使用简体中文维护：

- [docs/技术方案.md](./docs/技术方案.md)
- [docs/架构设计.md](./docs/架构设计.md)
- [docs/数据库设计.md](./docs/数据库设计.md)
- [docs/API接口设计.md](./docs/API接口设计.md)
- [docs/数据流图.md](./docs/数据流图.md)
- [docs/上线检查清单.md](./docs/上线检查清单.md)

---

## 开发校验

```bash
# 静态检查
dart run tool/verify.dart analyze

# 测试
dart run tool/verify.dart test

# Android Release 构建
dart run tool/verify.dart build-apk
```

---

## 参与贡献

欢迎贡献。

如果你的改动会影响架构、存储或产品方向，请先阅读 [CONTRIBUTING.md](./CONTRIBUTING.md)。

---

## 许可证

Apache-2.0，见 [LICENSE](./LICENSE)。

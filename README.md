<p align="center">
  <img src="./docs/assets/forgeterm-ai-logo.png" alt="ForgeTerm AI logo" width="128" />
</p>

# ForgeTerm AI

English | [简体中文](./README.zh-CN.md)

Open-source Mobile SSH + AI Terminal for Android.

ForgeTerm AI lets you connect to remote servers from your phone, keep multiple shell sessions open, forward ports, and use remote AI coding tools such as OpenCode and OpenClaw without leaving the terminal workflow.

---

## Why This Project

- Use SSH from a phone when you need to respond quickly.
- Keep terminal access and AI assistance in the same app.
- Manage multiple servers, sessions, keys, and quick commands locally.
- Stay local-first: server configs, conversations, and preferences are stored on device.

---

## What You Can Do Today

- Connect to servers with password or private key authentication
- Verify host fingerprints with TOFU on first connection
- Use jump hosts
- Keep multiple shell sessions open
- Reconnect automatically after transient disconnects
- Configure local and remote port forwarding
- Detect and use OpenCode / OpenClaw on remote servers
- Persist servers, keys, conversations, quick commands, and theme preferences locally

---

## Current Status

The project is usable today for the main SSH + AI workflow.

Implemented:

- SSH connection management
- Multi-session terminal flow
- Port forwarding
- OpenCode / OpenClaw integration
- Local persistence with Hive + secure storage
- Android foreground service integration

Still in progress or not included yet:

- Long-running background / screen-off behavior still needs more real-device validation
- Mosh is not implemented
- Cloud sync, accounts, and subscriptions are not implemented

---

## Quick Start

Current distribution model: build from source.

Requirements:

- Flutter SDK
- Android toolchain
- A reachable SSH server
- Optional: OpenCode or OpenClaw installed on the remote server

Run locally:

```bash
flutter pub get
flutter run
```

Build a release APK:

```bash
dart run tool/verify.dart build-apk
```

---

## Typical Flow

1. Add a server with password or key authentication.
2. Connect and open a shell session.
3. Start additional sessions if needed.
4. Open the AI assistant and let the app detect available remote tools.
5. Use port forwarding when a remote HTTP tool endpoint is needed.

---

## Local-First Data Model

- Server configs, quick commands, conversations, and UI preferences are stored locally in Hive.
- Passwords, private keys, passphrases, and AI service passwords are stored locally in secure storage.
- The current codebase does not ship with cloud sync, accounts, telemetry, or subscriptions.

---

## Project Documentation

If you want implementation details, start here:

- Looking for Chinese implementation docs? Most project documents in `docs/` are currently maintained in Simplified Chinese.
- [docs/技术方案.md](./docs/技术方案.md)
- [docs/架构设计.md](./docs/架构设计.md)
- [docs/数据库设计.md](./docs/数据库设计.md)
- [docs/API接口设计.md](./docs/API接口设计.md)
- [docs/数据流图.md](./docs/数据流图.md)

---

## Development Checks

```bash
# Static analysis
dart run tool/verify.dart analyze

# Tests
dart run tool/verify.dart test

# Android release build
dart run tool/verify.dart build-apk
```

---

## Contributing

Contributions are welcome.

Please read [CONTRIBUTING.md](./CONTRIBUTING.md) before opening large changes, especially if they touch architecture, storage, or product direction.

---

## License

Apache-2.0. See [LICENSE](./LICENSE).

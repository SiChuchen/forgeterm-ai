# API 接口设计

当前仓库没有自建云端后端 API。应用真正依赖的“接口”只有三类：

1. SSH 协议接口（通过 `dartssh2`）
2. OpenCode headless server HTTP 接口（通过 SSH 隧道访问）
3. OpenClaw Gateway HTTP 接口（通过 SSH 隧道访问）

早期文档中的账号、订阅、配置同步接口仍属于规划，不是当前代码路径。

---

## 1. 当前真实接口总览

| 接口类型 | 传输 | 认证 | 当前用途 |
|----------|------|------|----------|
| SSH | TCP / SSH | 密码或私钥 | 建连、开 Shell、执行命令、建立端口转发 |
| OpenCode HTTP | 本地 loopback + SSH tunnel | Basic Auth | 创建会话、发送消息、拉取历史、中断 |
| OpenClaw HTTP | 本地 loopback + SSH tunnel | Bearer Token | 优先 `/v1/responses`，回退 `/v1/chat/completions` |

---

## 2. SSH 运行接口

### 2.1 建连

调用方:

- `SSHService.connect`
- `SSHService.connectViaJumpHosts`

支持能力:

- 密码认证
- 私钥认证
- 多跳跳板机
- 主机指纹回调校验

关键运行时调用:

```dart
await SSHSocket.connect(host, port, timeout: ...)
SSHClient(
  socket,
  username: config.username,
  identities: identities,
  onPasswordRequest: ...
)
```

### 2.2 Shell

```dart
await client.shell(
  pty: SSHPtyConfig(width: width, height: height),
)
```

用途:

- 交互式终端
- PTY 模式 AI 工具执行

### 2.3 执行命令

```dart
await client.execute(command)
```

用途:

- 工具探测
- 自动启动远端 OpenCode / OpenClaw 服务
- execute 模式 AI 调用

### 2.4 端口转发

```dart
await client.forwardLocal(remoteHost, remotePort)
```

用途:

- 本地随机端口映射到远端 OpenCode / OpenClaw HTTP 端口
- 跳板机链路中的下一跳连接

---

## 3. OpenCode Headless Server HTTP 接口

### 3.1 服务发现与认证

- 默认远端端口: `4279`
- 启动命令: `opencode serve --port 4279 --hostname 127.0.0.1`
- 认证方式: HTTP Basic Auth
  - username: `opencode`
  - password: 远端环境变量 `OPENCODE_SERVER_PASSWORD`

### 3.2 当前使用的端点

| 方法 | 路径 | 用途 |
|------|------|------|
| `GET` | `/session` | 健康检查 / 认证校验 |
| `POST` | `/session` | 创建会话 |
| `POST` | `/session/{id}/message` | 发送消息 |
| `GET` | `/session/{id}/message` | 拉取远端消息历史 |
| `POST` | `/session/{id}/abort` | 中断 |

### 3.3 创建会话

```http
POST /session
Authorization: Basic base64(opencode:<password>)
Content-Type: application/json
```

```json
{}
```

### 3.4 发送消息

```http
POST /session/{id}/message
Authorization: Basic base64(opencode:<password>)
Content-Type: application/json
```

```json
{
  "parts": [
    {
      "type": "text",
      "text": "请解释当前项目的 SSH 重连逻辑"
    }
  ]
}
```

### 3.5 中断

```http
POST /session/{id}/abort
Authorization: Basic base64(opencode:<password>)
```

说明:

- 当前适配器消费的是完整响应，不是 SSE。
- 查询成功后，应用会进一步拉取 `GET /session/{id}/message`，用远端 transcript 回灌本地消息列表。
- 如果 HTTP 不可用，运行时会降级到 PTY 模式，而不是继续重试自建 API。

---

## 4. OpenClaw Gateway HTTP 接口

### 4.1 服务发现与认证

- 默认远端端口: `18789`
- 启动命令:
  - 开启配置: `openclaw config set gateway.http.endpoints.chatCompletions.enabled true --strict-json`
  - 开启配置: `openclaw config set gateway.http.endpoints.responses.enabled true --strict-json`
  - 启动 gateway: `openclaw gateway --allow-unconfigured --auth password --bind loopback --port 18789 --force`
- 认证方式:
  - `Authorization: Bearer <OPENCLAW_GATEWAY_PASSWORD>`

### 4.2 当前使用的端点

| 方法 | 路径 | 用途 |
|------|------|------|
| `GET` | `/healthz` | 存活探测 |
| `POST` | `/v1/responses` | 首选结构化流式对话 |
| `POST` | `/v1/chat/completions` | 兼容回退流式对话 |

### 4.3 请求头

```http
Authorization: Bearer <password>
Accept: text/event-stream
Content-Type: application/json
x-openclaw-agent-id: main
x-openclaw-session-key: <session-key>
```

### 4.4 `responses` 请求体

```json
{
  "model": "openclaw:main",
  "stream": true,
  "input": [
    {
      "type": "message",
      "role": "user",
      "content": [
        {
          "type": "input_text",
          "text": "列出当前服务器上的 Docker 容器"
        }
      ]
    }
  ]
}
```

### 4.5 `chat completions` 回退请求体

```json
{
  "model": "openclaw:main",
  "stream": true,
  "messages": [
    {
      "role": "user",
      "content": "列出当前服务器上的 Docker 容器"
    }
  ]
}
```

### 4.6 响应语义

- 首选 `responses` SSE 流，并消费结构化 `text / thinking / toolUse / error` 块。
- 若网关返回 JSON，则适配器按非流式 JSON 兼容处理。
- 对运行时来说，`200` 或 `400` 都可用于判断 `responses` / `chatCompletions` 端点已就绪。

### 4.7 降级策略

- `http` 失败 -> `execute`
- `execute` 失败 -> `pty`

---

## 5. 应用侧接口约束

### 5.1 工具检测结果

统一抽象为:

```dart
class ToolDetectionResult {
  final bool isInstalled;
  final String? version;
  final List<String> supportedModes;
  final String? preferredMode;
  final AIToolCapabilities capabilities;
}
```

### 5.2 AI 配置

统一抽象为:

```dart
class AIToolConfig {
  final String adapterId;
  final String mode;     // http / execute / pty
  final int? httpPort;
}
```

### 5.3 会话持久化

- `AIConversation.sessionContext` 仍保存字符串，但当前新值为版本化 JSON 字符串。
- 对 OpenClaw / OpenCode 而言，其中会记录 `sessionKey` 或 `remoteSessionId` 等字段。
- `AIChatMessage.isComplete` 用于标识中断消息或未完成流式消息。

---

## 6. 当前未实现的线上 API

以下内容仍不是当前代码路径的一部分：

- 账户体系
- 订阅管理
- 用户反馈上传
- 配置云同步

如果未来要恢复这些内容，应新建独立“云端 API 设计”文档，而不是继续和运行时 SSH / AI 接口混写。

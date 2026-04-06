# OpenCode Slash Command 接入调研

更新时间：2026-04-02

## 目标

在 AI 聊天输入框中，当用户第一次输入字符是 `/` 时，弹出 OpenCode 可用命令列表，用户可点选命令后继续输入参数，并在发送时走 OpenCode 真实的 slash command 执行链路。

---

## 一、当前项目现状

### 1. Flutter 端已经具备的能力

#### 已能拉到命令列表

`OpenCodeApiAdapter.loadControlCatalog()` 当前已经同时请求：

- `GET /config`
- `GET /config/providers`
- `GET /agent`
- `GET /command`
- `GET /mcp`
- `GET /permission`

也就是说，客户端其实已经能拿到 OpenCode 服务器上的命令列表，只是输入框没有消费这份数据。

相关代码：

- `lib/data/services/ai_cli/adapters/opencode_api_adapter.dart`
- `loadControlCatalog()`
- `_parseCommandOptions()`

#### 已能执行命令

`OpenCodeApiAdapter._buildRequest()` 在 `AIInputMode.command` 下已经会发：

- `POST /session/{sessionId}/command`

请求体字段已经正确包含：

- `command`
- `arguments`
- `model`（字符串 modelRef）
- `parts`（附件）

相关代码：

- `lib/data/services/ai_cli/adapters/opencode_api_adapter.dart`

#### 当前缺口

当前聊天输入框 `ChatInputBar` 只是普通 `TextField`，没有：

- slash 命令弹层
- slash 查询过滤
- 选中命令后的插入逻辑
- 发送时识别 inline slash command 的逻辑

相关代码：

- `lib/presentation/features/ai_chat/widgets/chat_input_bar.dart`
- `lib/presentation/features/ai_chat/ai_chat_screen.dart`

---

## 二、OpenCode 官方实现调研

### 1. 官方前端 slash 列表触发条件

OpenCode Web/TUI 前端在输入处理中使用：

- `@`：`/@(\S*)$/`
- `/`：`/^\/(\S*)$/`

也就是只有当当前输入内容整体仍处于“正在输入命令头”的状态时，才显示 slash popover。

这意味着：

- 输入 `/` 时应立刻弹出列表
- 输入 `/rev` 时应继续过滤
- 一旦输入空格变成 `/review `，popover 应关闭

相关源码：

- `else/opencode-dev/packages/app/src/components/prompt-input.tsx`

### 2. 官方命令来源

官方前端的 slash 列表由两部分组成：

- 本地已注册 builtin commands：来自 `useCommand().options`
- 服务端同步的 custom commands：来自 `sync.data.command`

其中：

- 选中 custom command 时，只是把 `/<command> ` 写回输入框
- 真正发送时，如果文本以 `/command` 开头，才调用 `client.session.command(...)`

相关源码：

- `else/opencode-dev/packages/app/src/components/prompt-input.tsx`
- `else/opencode-dev/packages/app/src/components/prompt-input/submit.ts`
- `else/opencode-dev/packages/app/src/context/command.tsx`
- `else/opencode-dev/packages/app/src/pages/session/use-session-commands.tsx`

### 3. 官方服务端接口

OpenCode 服务端真实提供两条接口：

- `GET /command`：列出所有可用命令
- `POST /session/:id/command`：执行 slash command

相关源码：

- `else/opencode-dev/packages/opencode/src/server/server.ts`
- `else/opencode-dev/packages/opencode/src/server/routes/session.ts`
- `else/opencode-dev/packages/opencode/src/session/prompt.ts`
- `else/opencode-dev/packages/opencode/src/command/index.ts`

---

## 三、真实服务器测试结果

### 1. 测试方式

使用仓库内 probe 脚本通过 SSH 连到真实 OpenCode 服务器，再直接请求本机 OpenCode HTTP 服务：

- 脚本：`tool/.codex_opencode_server_probe.dart`
- 凭据来源：服务器进程环境中的 `OPENCODE_SERVER_PASSWORD`
- 实际请求：
  - `GET http://127.0.0.1:4279/config`
  - `GET http://127.0.0.1:4279/command`

### 2. 真实结果

本次真实服务器返回：

- 当前模型：`deepseek/deepseek-reasoner`
- 命令总数：`27`
- source 分布：
  - `command`: `26`
  - `mcp`: `1`

实际返回的命令名包含：

- `init`
- `review`
- `plan`
- `tdd`
- `code-review`
- `security`
- `build-fix`
- `e2e`
- `refactor-clean`
- `orchestrate`
- `learn`
- `checkpoint`
- `verify`
- `eval`
- `update-docs`
- `update-codemaps`
- `test-coverage`
- `setup-pm`
- `go-review`
- `go-test`
- `go-build`
- `skill-create`
- `instinct-status`
- `instinct-import`
- `instinct-export`
- `evolve`
- `Arxiv:deep-paper-analysis`

本地留存证据文件：

- `.codex_opencode_probe_commands.json`

### 3. 一个重要结论

Flutter 端当前拿到的 `/command` 并不是“伪配置”或“演示数据”，而是真实服务器命令表。

因此输入框 popup 的命令来源不需要额外猜测，直接复用当前 `controlCatalog.commandOptions` 即可。

### 4. 关于真实执行测试

尝试对真实服务器执行 `/review` 作为 sample command，但这条命令本身执行较重，3 分钟超时，不能拿它作为轻量探测链路。

这不影响接入判断，因为：

- 命令列表接口已真实打通
- 执行接口路径和官方源码已经完全明确
- 当前客户端自身也已经具备 `AIInputMode.command -> POST /session/:id/command` 的现成代码

---

## 四、接入方案结论

## 推荐方案：按 OpenCode 官方行为做“inline slash command”

### 行为定义

#### 1. 弹出条件

当且仅当输入框文本匹配：

- `^/(\S*)$`

时弹出 slash 命令列表。

#### 2. 数据来源

命令列表直接来自当前会话的：

- `sessionState.controlCatalog.commandOptions`

也就是 OpenCode `/command` 的真实返回结果。

#### 3. 选中行为

点击某个命令后：

- 向输入框写入 `/<command> `
- 光标移动到末尾
- 关闭 popover
- 不立即发送

#### 4. 发送行为

如果发送时文本头部是：

- `/foo ...`

且 `foo` 存在于当前命令列表中，则本次发送应临时按命令模式执行：

- `commandName = foo`
- `arguments = 后续文本`
- 请求走 `POST /session/:id/command`

但这次命令执行不应把会话长期切到“命令模式”。

也就是：

- slash 是一次性 inline 行为
- 控制面里的“命令模式”仍然保留，作为高级显式模式

---

## 五、为什么不建议只靠当前“命令模式”顶上去

如果仅仅把“选择 slash 命令”实现成：

- 自动把会话切到 `AIInputMode.command`
- 把输入框只保留参数部分

虽然可以复用现有逻辑，但会有几个明显问题：

1. 和 OpenCode 官方交互不一致
- 官方是输入框里保留 `/<command> ` 形式
- 用户会天然期待这种行为

2. 容易把会话永久留在命令模式
- 用户执行一次 `/review` 后，下一条普通提问也可能继续走命令模式

3. 用户心智更差
- slash command 本质应该是一次性动作，不应强绑定长期 profile 状态

因此推荐方案是：

- popup 和 inline 行为模仿官方
- 底层发送临时借用现有 command endpoint 能力
- 会话持久 profile 不被污染

---

## 六、实施任务清单

### Phase 1：输入框 slash popup

- [x] 给 `ChatInputBar` 增加 `slashCommands` 输入
- [x] 在输入监听中识别 `^/(\S*)$`
- [x] 按命令名/描述做过滤
- [x] 在输入框上方渲染命令列表弹层
- [x] 点选后写入 `/<command> ` 并关闭弹层
- [x] 增加 widget test：输入 `/` 时出现列表，点选后文本正确回写

### Phase 2：发送链路接入真实 slash command

- [x] 在聊天发送入口识别 inline slash command
- [x] 增加一次性执行 profile override，不污染持久 `executionProfile`
- [x] 允许 `/command` 在无参数时也能发送
- [x] 用户消息展示保留原始 `/<command> ...` 文本
- [x] 增加单元测试：匹配命令时走 command request，不匹配时保持普通 prompt

### Phase 3：细节收口

- [x] slash popup 仅在 OpenCode 且命令列表非空时启用
- [x] 发送中或断线时禁用弹层交互
- [x] 对命令列表为空提供空状态文案
- [ ] 必要时为 MCP 来源命令补 source 标识

### Phase 4：验证

- [x] `flutter analyze`
- [ ] 定向 widget test / unit test
- [ ] 真机验证：输入 `/` -> 弹列表 -> 选择命令 -> 发送成功
- [x] 真机验证：普通问题不受影响

---

## 七、本轮开发建议执行顺序

1. 先做 Phase 1，让输入框先有 slash popup 和选中体验。
2. 再做 Phase 2，把发送链路改成 inline slash command 一次性执行。
3. 最后补测试和真机回归。

这条顺序的好处是：

- UI 触发和数据源先闭环
- 发送链路改动范围最小化
- 出问题时容易判断是 popup 问题还是 command transport 问题

---

## 八、当前落地状态（2026-04-06）

当前实际进度已经不是“纯方案”阶段，而是：

- slash popup 已接入
- inline slash command 已接入
- 命令请求已固定走 OpenCode HTTP，不再错误回退到 PTY
- 命令超时后会继续轮询历史与状态补捞结果
- 原始 `/<command> ...` 用户消息已保留

本轮新增确认：

- 真机上普通 OpenCode 提问链路已通过
- 中文输入法会把 slash 输入成全角 `／`
- 当前代码已对全角 `／` 做归一化处理，slash popup 和命令解析都已兼容

当前还没完全闭环的只剩：

- “全角 `／` -> 弹列表 -> 选择命令 -> 执行成功”的完整真机一次性回归
- 当前 Windows 环境里的 `flutter test` listener `503` 问题

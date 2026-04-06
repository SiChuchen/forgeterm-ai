# AI原生能力扩展开发计划

本文档用于规划 ForgeTerm AI 下一阶段的 AI 能力扩展，目标不是只做“能聊天”，而是把 OpenClaw / OpenCode 的原生会话控制、模型切换、思考强度、MCP、权限、命令系统、会话管理等能力，逐步搬到移动端可用的交互里。

本文档同时作为后续执行清单。每完成一项，都应回到本文档勾选并补充验收结论。

---

## 1. 目标

- 把当前“单一聊天框 + 文本输入”的 AI 页面，升级为“会话控制中心 + 聊天面板 + 工具控制面板”。
- 对齐 OpenClaw / OpenCode 已有的原生能力，而不是继续堆只适合当前适配层的临时 UI。
- 建立统一的移动端 AI 控制面抽象，避免后续每接一个工具就重写一套页面。
- 所有新增能力都要优先考虑移动端可操作性、可恢复性、弱网容错和 SSH 场景。

---

## 2. 调研来源

本次计划基于以下上游实现调研得出：

- OpenClaw 核心：
  - `else/openclaw-main/src/gateway/server-methods/chat.ts`
  - `else/openclaw-main/src/gateway/server-methods/sessions.ts`
  - `else/openclaw-main/src/gateway/sessions-patch.ts`
  - `else/openclaw-main/src/agents/model-selection.ts`
  - `else/openclaw-main/src/auto-reply/commands-registry.data.ts`
  - `else/openclaw-main/src/auto-reply/reply/commands-mcp.ts`
  - `else/openclaw-main/src/tui/tui-session-actions.ts`
- OpenCode 核心：
  - `else/opencode-dev/packages/app/src/pages/session/use-session-commands.tsx`
  - `else/opencode-dev/packages/app/src/components/prompt-input.tsx`
  - `else/opencode-dev/packages/app/src/components/prompt-input/submit.ts`
  - `else/opencode-dev/packages/app/src/context/prompt.tsx`
  - `else/opencode-dev/packages/app/src/context/local.tsx`
  - `else/opencode-dev/packages/app/src/context/permission.tsx`
  - `else/opencode-dev/packages/opencode/src/server/routes/session.ts`
  - `else/opencode-dev/packages/opencode/src/server/routes/event.ts`
  - `else/opencode-dev/packages/opencode/src/server/routes/global.ts`
  - `else/opencode-dev/packages/opencode/src/mcp/index.ts`
- agent-harness 补充：
  - `else/openclaw-main/agent-harness/OPENCLAW.md`
  - `else/openclaw-main/agent-harness/cli_anything/openclaw/openclaw_cli.py`
  - `else/opencode-dev/agent-harness/OPENCODE.md`
  - `else/opencode-dev/agent-harness/cli_anything/opencode/opencode_cli.py`
- 当前项目：
  - `lib/data/models/ai_tool_config.dart`
  - `lib/presentation/providers/ai_tool_provider.dart`
  - `lib/presentation/providers/ai_session_provider.dart`
  - `lib/presentation/features/ai_chat/ai_chat_screen.dart`
  - `lib/presentation/features/ai_chat/widgets/ai_tool_selector.dart`
  - `lib/presentation/features/ai_chat/widgets/chat_input_bar.dart`
  - `lib/data/services/ai_cli/adapters/openclaw_api_adapter.dart`
  - `lib/data/services/ai_cli/adapters/opencode_api_adapter.dart`

---

## 3. 上游能力结论

### 3.1 OpenClaw 已有能力

- Chat 平面不只支持 `responses/chat completions`，还存在完整的会话控制平面。
- `sessions.patch` 已支持：
  - `model`
  - `thinkingLevel`
  - `fastMode`
  - `verboseLevel`
  - `reasoningLevel`
  - `responseUsage`
  - `elevatedLevel`
  - `execHost`
  - `execSecurity`
  - `execAsk`
  - `execNode`
  - `sendPolicy`
  - `groupActivation`
  - `label`
- `chat.send` 已支持：
  - 文本消息
  - `thinking`
  - `attachments`
  - `timeoutMs`
  - `idempotencyKey`
  - sessionKey 复用
- `chat.history` 会返回：
  - 历史消息
  - `thinkingLevel`
  - `fastMode`
  - `verboseLevel`
  - usage/cost 元数据
- `chat.abort` 已是正式能力。
- 命令系统非常完整，现成命令包括：
  - `/help`
  - `/commands`
  - `/skill`
  - `/context`
  - `/btw`
  - `/approve`
  - `/session`
  - `/subagents`
  - `/acp`
  - `/focus`
  - `/kill`
  - `/steer`
  - `/config`
  - `/mcp`
  - `/plugins`
  - `/usage`
  - `/stop`
  - `/restart`
- `/mcp` 已支持 `show/get/set/unset`，说明 MCP 配置管理本身是第一方能力。
- 模型解析层已支持 provider/model、alias、think level、reasoning default、allowlist、xhigh 等策略。
- TUI 已经把 session info 做成了状态面板，能显示当前模型、provider、reasoning、usage、context tokens 等。

### 3.2 OpenCode 已有能力

- Prompt 输入不是单纯文本，而是结构化 prompt parts：
  - text
  - file attachment
  - agent mention
  - image attachment
- 本地状态层已经支持按 session 保存：
  - agent
  - model
  - variant
- Session 命令系统已覆盖：
  - model 选择
  - MCP 对话框
  - permission auto-accept
  - undo / redo
  - compact / summarize
  - fork
  - share / unshare
  - review 切换
  - terminal / file tree / input focus
- Prompt 提交已支持：
  - 自定义 slash command
  - shell mode
  - worktree 选择
  - 文件 / 图片 / 评论上下文
  - agent/model/variant 随请求发送
- 服务端路由已支持：
  - session list/get/create/delete/update
  - children
  - todo
  - init
  - fork
  - abort
  - share
  - diff
- SSE 路由已支持：
  - `/event`
  - `/global/event`
- MCP 运行时已支持：
  - connected / disabled / failed / needs_auth / needs_client_registration
  - tools changed notification

### 3.3 agent-harness 给出的补充信息

agent-harness 不是上游真源码，但它把上游能力“整理成了容易扫描的命令矩阵”，对规划很有价值。

- OpenCode harness 明确暴露了这些稳定表面：
  - `run --agent --model --variant --thinking --command --file --attach --password --share --fork`
  - `session list/show/delete`
  - `models list`
  - `providers list/login/logout`
  - `agent list/create`
  - `mcp list/add/auth/logout/debug`
  - `stats`
  - `export/import`
  - `db query/path/migrate`
  - `serve/workspace-serve`
  - `debug`
- OpenClaw harness 明确暴露了这些稳定表面：
  - `status/health/gateway`
  - `agents`
  - `sessions`
  - `channels`
  - `config`
  - `memory`
  - `message`
  - `backup`
  - `browser`
  - `setup/onboard/configure/reset/uninstall`
  - 原生 passthrough：`models/approvals/plugins/skills/nodes/devices/secrets/...`

结论不是“我们要把 harness 原样搬进 App”，而是：

- 上游已经存在清晰的控制面。
- 我们不应该只把 App 继续做成一个 prompt 输入框。
- 后续适配器必须区分“对话平面”和“控制平面”。

---

## 4. 当前项目缺口

### 4.1 数据模型缺口

当前 `AIToolConfig` 只有：

- `adapterId`
- `displayName`
- `command`
- `mode`
- `httpPort`
- `envVars`
- `autoDetect`

缺失了真正决定 AI 行为的核心字段：

- `agentId`
- `modelRef`
- `providerId`
- `variant`
- `thinkingLevel`
- `reasoningLevel`
- `fastMode`
- `verboseLevel`
- `responseUsage`
- `elevatedLevel`
- `execHost / execSecurity / execAsk / execNode`
- `sendPolicy`
- `groupActivation`
- `enabledMcpServers`
- `autoAcceptPermissions`
- `defaultCommandMode`
- `supportsShellMode`
- `showThinkingByDefault`

### 4.2 适配层缺口

- OpenClaw adapter 当前仍是固定 `model: openclaw:<defaultAgentId>`，没有会话级模型切换。
- OpenClaw 还没接 session patch / command / MCP / approvals / plugins 等控制面。
- OpenCode adapter 当前只发 `text` part，没有：
  - file/image attachment
  - agent
  - model
  - variant
  - custom command
  - shell mode
  - share/fork/summarize
- 两边都缺统一的“控制面接口”。

### 4.3 UI 缺口

当前页面已实现：

- 工具选择
- 文本发送
- 流式响应
- 思考块折叠查看
- 附带终端日志

当前页面还没有：

- 模型选择
- provider 切换
- variant / reasoning effort 切换
- thinking / usage / verbose 配置
- MCP 管理面板
- slash command / internal command 面板
- prompt 附件系统
- 权限请求与自动批准
- fork/share/compact/undo/redo
- todo / review / session tree / children
- session 头部状态面板
- raw event / debug inspector

### 4.4 架构缺口

当前代码默认“聊天能力 = 适配器 query() + provider 渲染”。

这已经不够了。后续必须拆成三层：

- 对话平面：发送 prompt、接收流式块、拉 transcript。
- 控制平面：模型、MCP、权限、命令、session patch、fork/share/summary。
- 展示平面：聊天消息、状态条、控制面板、命令表、资源/工具列表。

---

## 5. 产品方向

### 5.1 页面定位

建议把 AI 页面升级成三段式结构：

- 顶部：Session Control Bar
  - 当前工具
  - 当前模型
  - 当前 variant / thinking
  - MCP 状态
  - 权限模式
- 中部：Chat Timeline
  - 文本
  - thinking
  - tool use
  - usage
  - permission request
  - todo / summary / fork / share card
- 底部：Prompt Composer
  - 文本输入
  - 附件
  - slash / command
  - shell mode
  - context chips

### 5.2 交互原则

- 移动端不照搬桌面 command palette，而是用底部 sheet / segmented panel 承载。
- 高频操作放在 header chips 和 composer 上。
- 低频强能力放在“控制中心”面板里。
- power user 仍保留 raw command 输入能力。

### 5.3 对齐策略

- OpenCode 优先对齐：
  - model / variant
  - MCP
  - permission auto-accept
  - share/fork/compact
  - attachments
- OpenClaw 优先对齐：
  - sessions.patch 相关 session settings
  - slash commands
  - MCP config
  - approvals
  - usage / thinking / verbose / execution security

---

## 6. 总体架构方案

### 6.1 新增统一控制面抽象

新增 `AIToolControlAdapter`，与现有 `AICLIAdapter` 并列，或合并进更大的适配器协议中。至少需要以下能力：

- `loadSessionInfo`
- `patchSession`
- `listModels`
- `listProviders`
- `listAgents`
- `listCommands`
- `runCommand`
- `listMcpServers`
- `setMcpServerEnabled`
- `authenticateMcpServer`
- `loadPermissions`
- `respondPermission`
- `shareSession`
- `forkSession`
- `summarizeSession`
- `listTodos`
- `subscribeEvents`
- `loadChildren`

### 6.2 区分三种传输面

- HTTP/SSE：
  - 用于 prompt、stream、history、global event
- Gateway RPC / WebSocket：
  - 适合 OpenClaw `sessions.*`、`models.*`、`tools/commands`
- CLI over SSH：
  - 作为补充控制面
  - 用于上游未暴露稳定 HTTP/RPC 的命令

建议统一成：

- `conversation transport`
- `control transport`
- `fallback transport`

### 6.3 数据层拆分

建议新增：

- `AIExecutionProfile`
  - 工具级配置默认值
- `AISessionPreferences`
  - 会话级覆盖值
- `AIAttachmentDraft`
  - 输入中的附件
- `AICommandDefinition`
  - slash / internal command 元数据
- `AIMcpServerInfo`
  - MCP 状态、tools/resources/prompts
- `AIPermissionRequest`
  - 权限请求
- `AISessionRemoteInfo`
  - title / model / status / fork / share / todo / usage

### 6.4 状态持久化

建议把 `sessionContext` 再扩一层，保存：

- `remoteSessionId`
- `sessionKey`
- `adapterId`
- `conversationMode`
- `agentId`
- `modelRef`
- `variant`
- `reasoningLevel`
- `thinkingLevel`
- `enabledMcpServers`
- `permissionMode`
- `lastRunId`
- `shareUrl`
- `parentSessionId`

---

## 7. 功能范围与优先级

| 阶段 | 能力 | OpenClaw | OpenCode | 优先级 |
|------|------|----------|----------|--------|
| P0 | 统一控制面抽象 | 是 | 是 | 最高 |
| P1 | 模型 / agent / variant 选择 | 中 | 高 | 最高 |
| P1 | provider 列表 / 登录 / 登出 | 低 | 高 | 高 |
| P1 | thinking / reasoning / usage / verbose 设置 | 高 | 中 | 最高 |
| P1 | session info 同步 | 高 | 高 | 最高 |
| P2 | MCP 列表 / 状态 / auth / enable | 高 | 高 | 高 |
| P2 | 命令面板 / raw slash command | 高 | 中 | 高 |
| P2 | 权限请求与 auto-accept | 中 | 高 | 高 |
| P3 | 文件 / 图片 / 日志附件 | 中 | 高 | 高 |
| P3 | share / fork / compact / undo / redo | 中 | 高 | 高 |
| P3 | todo / children / lineage | 中 | 高 | 中 |
| P4 | approvals / plugins / skills / stats / export | 高 | 中 | 中 |
| P4 | debug / raw event inspector | 高 | 高 | 中 |

---

## 8. 分阶段开发计划

### 阶段 A：基础重构

目标：

- 让当前 AI 页面拥有“控制面”的可扩展骨架。

交付：

- 新的适配器控制面接口
- 新的数据模型
- 新的 session preferences 持久化
- 能力位扩展

清单：

- [x] A0. 完成 OpenClaw / OpenCode / agent-harness 调研
- [x] A1. 设计 `AIExecutionProfile` 与 `AISessionPreferences`
- [ ] A2. 扩展 `AIToolConfig`，补齐 model/agent/variant/thinking 等字段
- [x] A3. 扩展 `AIToolCapabilities`
- [x] A4. 增加 `AIToolControlAdapter` 抽象
- [ ] A5. 在 provider 层引入 `remote session info` 状态
- [x] A6. 在 `sessionContext` 中保存会话级设置快照
- [x] A7. 补持久化与兼容迁移测试

验收标准：

- 页面不改 UI 也能读取和保存会话级偏好
- 新抽象不影响现有 query 流程
- 老数据不崩

### 阶段 B：Session Control Center

目标：

- 用户可以在聊天页里控制模型和运行策略。

交付：

- 顶部控制条
- 会话设置面板
- 模型 / provider / agent / variant / thinking / usage 面板
- 会话预设与最近使用记录

清单：

- [x] B1. 新增 header control bar
- [x] B2. OpenCode：支持 agent/model/variant 读取与设置
- [ ] B3. OpenCode：支持 providers list/login/logout
- [ ] B4. OpenClaw：支持 model/thinking/reasoning/usage/verbose 读取与 patch
- [ ] B5. 把当前生效设置显示在会话头部
- [ ] B6. 提供“恢复默认”与“仅本会话生效”切换
- [ ] B7. 增加“最近模型 / 最近预设”与一键复用
- [ ] B8. Provider 层保存 patch 成功后的 authoritative state
- [ ] B9. 补 widget / adapter / provider 测试

验收标准：

- 用户能明确看到当前模型和思考强度
- 切换后下一轮请求使用新设置
- 页面重进后设置能恢复

### 阶段 C：MCP 控制中心

目标：

- 用户可以查看和控制 MCP，而不是只依赖远端默认配置。

交付：

- MCP 底部抽屉或独立面板
- 服务器状态卡片
- auth/debug/enable
- tools/resources/prompts 摘要

清单：

- [x] C1. 定义 `AIMcpServerInfo`
- [ ] C2. OpenCode：接入 MCP list/auth/logout/debug/status
- [ ] C3. OpenClaw：接入 `/mcp` show/set/unset 或等价控制面
- [x] C4. 展示 MCP 状态：connected/disabled/failed/needs_auth
- [ ] C5. 提供 OAuth / browser auth 触发链路
- [x] C6. 支持按会话启用 / 禁用 MCP server
- [ ] C7. 展示 tools/resources/prompts 计数与变更状态
- [ ] C8. 补 auth 失败与 needs_client_registration 的错误语义

验收标准：

- 用户能看到 MCP 是否可用
- 用户能完成最基本的 auth/debug
- MCP 状态变化能反馈到 UI

### 阶段 D：输入编排器升级

目标：

- 把 prompt 输入从纯文本升级为结构化输入。

交付：

- 附件 chips
- slash command / internal command
- shell mode
- 上下文选择能力

清单：

- [x] D1. 定义 `AIAttachmentDraft`
- [x] D2. 支持 terminal log 之外的文件附件
- [x] D3. 支持图片附件
- [x] D4. OpenCode：发送结构化 `parts`
- [ ] D5. OpenClaw：支持 attachments / timeout / thinking 参数
- [ ] D6. 增加 slash command 面板
- [x] D7. 增加 raw command 模式
- [x] D8. 增加 shell mode 或“命令执行模式”
- [ ] D9. 提供常用命令模板
- [ ] D10. 补输入恢复、失败回滚、重试测试

验收标准：

- 用户能发带附件的 prompt
- 用户能执行至少一类 internal command
- 请求失败后输入草稿可恢复

### 阶段 E：会话工作流

目标：

- 把 share/fork/summary/todo/lineage 做成移动端可用工作流。

交付：

- share / fork / compact / undo / redo / summary
- todo 面板
- session lineage

清单：

- [x] E1. OpenCode：接入 share / unshare
- [ ] E2. OpenCode：接入 fork
- [ ] E3. OpenCode：接入 summarize / compact
- [ ] E4. OpenCode：接入 children / todo / diff 摘要
- [ ] E5. OpenClaw：接入 session label / preview / reset / abort
- [ ] E6. 设计 lineage 视图与会话分叉入口
- [ ] E7. 在聊天时间线中显示 share/fork/summary 结果卡片
- [ ] E8. 补验收测试

验收标准：

- 用户能在移动端完成 share/fork/compact
- 用户能看到会话分支和 todo 摘要

### 阶段 F：权限与高级运维

目标：

- 把真正影响 agent 执行安全性的能力补上。

交付：

- permission request feed
- auto-accept 模式
- approvals
- debug/event inspector
- export/stats/debug

清单：

- [x] F1. OpenCode：接入 permission request 列表和响应
- [x] F2. OpenCode：接入 auto-accept 开关
- [ ] F3. OpenClaw：接入 approvals / approve
- [ ] F4. 接入 event/global event 订阅并驱动状态刷新
- [ ] F5. 增加 raw event inspector
- [ ] F6. OpenCode：接入 stats / export
- [ ] F7. OpenClaw：接入 usage / plugins / skills / debug 入口
- [ ] F8. 补弱网、断线重连和事件恢复测试

验收标准：

- 权限请求不会再是黑盒
- 断线重连后状态能恢复
- 支持最基本的故障排查

---

## 9. 关键设计决策

### 9.1 对话平面与控制平面必须分离

原因：

- OpenClaw 对话主要走 OpenAI 兼容 HTTP。
- OpenClaw 的 session settings / commands / MCP 管理主要在 gateway 控制面。
- OpenCode 的对话和 session 控制更偏 HTTP/SSE，但 models/providers/MCP/debug 又有 CLI 表面。

结论：

- 后续不能继续只扩 `query()`。
- 必须给适配器一个单独的 control 面。

### 9.2 优先做“会话设置”而不是先做大而全的 slash command

原因：

- model / thinking / MCP / permission 是每轮都会影响结果的核心能力。
- raw slash command 更适合第二阶段 power user。

### 9.3 移动端不做桌面级文件树复制

建议：

- 先做远端路径输入 + 最近路径 + 终端日志 + 图片附件。
- 更复杂的 file picker 放后续。

### 9.4 MCP auth 需要单独的移动端策略

建议：

- 支持打开外部浏览器。
- 提供 auth 状态和失败原因。
- OAuth 回跳做成后续增强项，不阻塞第一阶段列表/启停/调试。

---

## 10. 需要补充的数据结构

建议在后续实现时新增或扩展：

- `AIToolConfig`
  - `defaultAgentId`
  - `defaultModelRef`
  - `defaultVariant`
  - `defaultThinkingLevel`
  - `defaultReasoningLevel`
  - `defaultVerboseLevel`
  - `defaultResponseUsage`
  - `defaultFastMode`
  - `defaultPermissionMode`
  - `enabledMcpServers`
- `AISessionPreferences`
  - 会话级覆盖设置
- `AICommandDefinition`
  - `id`
  - `title`
  - `description`
  - `argsSchema`
  - `kind`
- `AIMcpServerInfo`
  - `name`
  - `status`
  - `kind`
  - `authStatus`
  - `toolCount`
  - `resourceCount`
  - `promptCount`
- `AISessionPreset`
  - `name`
  - `modelRef`
  - `variant`
  - `thinkingLevel`
  - `reasoningLevel`
  - `responseUsage`
  - `enabledMcpServers`
  - `permissionMode`
- `AIPermissionRequest`
  - `id`
  - `sessionId`
  - `label`
  - `riskLevel`
  - `details`

---

## 11. 测试计划

必须覆盖：

- 适配器控制面单测
- provider 状态迁移
- `sessionContext` 兼容迁移
- 模型切换后请求体变化
- MCP 状态刷新
- permission auto-accept
- 附件请求构造
- share/fork/summarize 工作流
- event 订阅断线恢复
- widget 交互：控制条、底部面板、命令面板、附件 chips

---

## 12. 风险清单

- OpenClaw 控制面不一定全部能通过当前 HTTP 端口直接访问，可能需要额外接 WebSocket/RPC。
- OpenCode 某些桌面功能依赖完整文件树和多面板布局，移动端需要裁剪。
- MCP OAuth 在移动端需要额外浏览器交互，流程复杂。
- 一次性把所有功能都堆进聊天页会造成交互拥挤，需要分层收纳。
- 会话偏好持久化一旦设计不好，后续迁移成本会很高。

---

## 13. 推荐实施顺序

建议严格按下面顺序做，不要倒着来：

1. 阶段 A：基础重构
2. 阶段 B：Session Control Center
3. 阶段 C：MCP 控制中心
4. 阶段 D：输入编排器升级
5. 阶段 E：会话工作流
6. 阶段 F：权限与高级运维

最小闭环版本建议是：

- 模型选择
- thinking/reasoning 设置
- MCP 列表
- permission auto-accept
- 至少一种 structured attachment

---

## 14. 本轮结论

这轮调研之后，可以明确三件事：

- 继续只优化聊天气泡或输入框，收益已经很低。
- 真正该做的是“控制面能力接入 + 会话级状态模型升级”。
- 只要把 OpenClaw/OpenCode 的控制面接起来，当前页面就能从“聊天页”升级成“移动端 AI 工作台”。

---

## 15. 2026-03-31 实现进展

本轮已实际落地的内容：

- 已新增 `AIExecutionProfile`，并把会话级执行偏好持久化到 `AISessionContext`。
- 已扩展 `AIToolCapabilities` 和 `AIToolControlAdapter`，让适配器同时暴露对话平面和控制平面。
- 聊天页已加入控制面入口、控制摘要条和底部控制面板，支持：
  - 输入模式切换：对话 / 命令 / Shell
  - OpenCode：provider / model / variant / agent 选择
  - OpenClaw：agent / modelRef / reasoning / command 选择
  - MCP 连接/断开与状态展示
  - 权限请求列表、手动批准、自动批准
  - 默认展开思考过程
  - 恢复默认配置
- OpenCode 已额外接入会话动作：
  - 分享并复制链接
  - 取消分享
  - 会话总结
- 当前会话摘要会显示在聊天页底部控制条，MCP 连接状态也会同步回会话配置。
- 聊天页已按高频 / 低频能力重新分层：
  - 快捷控制条负责模型切换、自动审批、待审批状态、MCP 状态和当前模式摘要
  - 独立模型切换弹层只负责切当前已发现模型，不再和其他控制混在一起
  - 底部加号面板承载图片 / 文件 / 终端日志附件、输入模式切换、模型管理、MCP 状态和高级设置入口
- 已新增 `AIAttachmentDraft`，并把附件真正接到请求链路：
  - OpenCode HTTP 走结构化 `parts`
  - OpenClaw HTTP `responses` 走 `input_image / input_file`
- 发送前已增加附件能力校验，避免在非 HTTP 或 Shell 模式下误发附件。
- 针对本轮改动的 `dart analyze` 与目标测试已通过。

本轮仍未完成的重点：

- `AIToolConfig` 默认值体系尚未扩展，当前仍以会话级偏好为主。
- OpenClaw 还没有接 `sessions.patch` / MCP 正式控制接口，现阶段以 HTTP 对话面 + 内部命令为主。
- OpenCode 还没有接 provider 登录/登出、fork、children、todo、diff 摘要。
- 结构化附件、图片输入、raw event inspector 仍未实现。

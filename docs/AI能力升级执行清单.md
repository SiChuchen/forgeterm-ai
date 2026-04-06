# AI能力升级执行清单

本文档用于约束当前仓库的 AI 能力升级顺序，并作为后续逐项核对的唯一清单。

---

## 目标

- 先把协议层和状态层做厚，再做 UI 包装。
- 优先提升 OpenClaw 的结构化能力，再补 OpenCode 的历史与事件同步。
- 任何一项完成后，都必须回到本清单核对并更新状态。

---

## 已完成决策

### 1. 协议升级范围

已确认以下边界:

- OpenClaw:
  - 主路径切换到 `POST /v1/responses`
  - 兼容回退保留 `POST /v1/chat/completions`
  - 第二阶段接入 `GET /sessions/:sessionKey/history`
  - 会话 kill / reset 相关接口先列为能力预留，不在第一批接入
- OpenCode:
  - 第一阶段保持当前 `POST /session` + `POST /session/{id}/message`
  - 第二阶段补 `GET /session/{id}/message`、`GET /event`、`GET /global/event`
  - `summarize` 作为增强能力，不阻塞第一批协议升级
- 通用原则:
  - 优先接“上游已经稳定暴露的 HTTP 接口”
  - 不把 UI 状态直接当作远端真实会话源
  - 先保留当前 `http -> execute -> pty` 回退链，不做破坏式替换

### 2. 数据模型升级方案

已确认以下设计:

- `ToolDetectionResult` 增加 `capabilities`，表达“当前首选链路可提供的能力”。
- `AIConversation.sessionContext` 暂不直接改成 Hive 复杂对象，后续升级为“版本化 JSON 字符串”。
- `sessionContext` 兼容策略:
  - 旧值若为普通字符串，视为 legacy session id / session key
  - 新值写入 JSON 字符串，至少包含:
    - `version`
    - `adapterId`
    - `mode`
    - `sessionKey`
    - `remoteSessionId`
    - `agentId`
    - `lastRunId`
- `AIChatMessage` 暂不做破坏式结构升级，持久化层仍保存 Markdown 文本。
- 结构化块先在运行时处理:
  - `text`
  - `thinking`
  - `toolUse`
  - `error`
  - `done`
- 等协议层跑通后，再决定是否把消息块拆分落盘。

---

## 执行清单

- [x] 1. 确定 AI 协议升级范围
- [x] 2. 设计数据模型升级
- [x] 3. 重构 AI 适配器抽象层
- [x] 4. 实现 OpenClaw Responses API 适配器
- [x] 5. 升级 OpenClaw launcher 与 detector
- [x] 6. 升级 AISessionProvider 与持久化逻辑
- [x] 7. 补 AI Chat UI
- [x] 8. 补 OpenCode 增强集成
- [x] 9. 补测试
- [x] 10. 做端到端校验与文档同步
- [x] 11. 追加需求: AI 思考过程可开关查看
- [x] 12. 一期控制面与会话动作扩展
- [x] 13. 聊天页交互重构: 快捷控制条 + 独立模型选择 + 加号面板
- [x] 14. OpenCode 调试收口: 过期 Provider/Model 兜底 + reasoning delta 流修复
- [ ] 15. OpenCode 二轮收口: 真实模型来源、slash command、真机边角修复

---

## 当前阶段产物要求

### 第 3 项完成标准

- `AICLIAdapter` 层能暴露能力标记
- 检测缓存可持久化能力标记
- 现有 `OpenCode / OpenClaw` 检测逻辑不因抽象升级而退化

### 第 4 项完成标准

- OpenClaw HTTP 适配器新增 `responses` 主路径
- 能消费结构化 SSE
- 能正确处理完成、错误和非流式回退
- 不破坏现有 `chat completions` 兼容路径

### 第 5 项完成标准

- launcher 能同时探测 `chat completions` 和 `responses`
- 自动启动时会同时开启两个 HTTP 端点
- detector 能基于真实端点状态暴露能力标记

### 第 6 项完成标准

- Provider 能按当前适配器/模式解析可用的 `sessionContext`
- 新的会话上下文以版本化 JSON 字符串持久化
- `thinking / toolUse / text / error / done` 在 Provider 层有统一消费逻辑
- 真实成功链路仍会写回检测缓存

### 第 7 项完成标准

- 聊天页能展示当前链路的关键能力
- 流式消息和完成消息使用一致的 AI 渲染风格
- 回退 / 中断 / 错误状态在 UI 上更容易区分

### 第 8 项完成标准

- OpenCode HTTP 链路可拉取远端消息历史
- 查询成功后可用远端 authoritative transcript 回灌本地消息列表
- OpenCode 历史消息中的工具调用 / 使用统计可被格式化展示

### 第 9 项完成标准

- 补覆盖 `sessionContext` 归一化 / 持久化的单测
- 补覆盖消息替换持久化链路的单测
- 补覆盖能力摘要文案的单测

### 第 10 项完成标准

- README / 核心技术文档同步 AI 链路现状
- 静态分析重新通过
- 把当前剩余验证阻塞项写清楚

### 第 11 项完成标准

- 当上游返回 `thinking` 块时，聊天页默认折叠展示
- 用户可按消息级别手动展开 / 收起思考内容
- 复制消息时不会把内部思考标记一并复制出去
- 至少覆盖一条交互测试和一条解析层测试

### 第 12 项完成标准

- 聊天页具备统一控制面入口与摘要条
- 会话级执行偏好可持久化并恢复
- OpenCode 至少支持模型 / agent / variant / MCP / permission / share / summarize 中的大部分核心能力
- OpenClaw 至少支持命令 / agent / modelRef / reasoning 的会话级配置

### 第 13 项完成标准

- 聊天页不再把高频能力全部塞进一个总控制面按钮
- 模型选择拥有独立入口，并优先用于切换当前已发现的模型
- 低频动作收纳到底部加号面板，至少覆盖图片 / 文件 / 终端日志附件
- 自动审批、待审批数和 MCP 状态在主聊天页可直接触达
- OpenCode / OpenClaw 允许存在差异化布局和能力展示

### 第 14 项完成标准

- OpenCode 控制面遇到过期 `providerId / modelId` 不会再触发下拉框断言崩溃
- 发问前与展示时都能对齐远端真实 `/config/providers` 结果
- OpenCode 的 `message.part.delta` 不再一律按正文处理，必须识别 reasoning/text 差异
- reasoning 已走过 delta 流的 part，不会在 completed update 时重复追加
- `flutter analyze` 重新通过

### 第 15 项完成标准

- 当前聊天页显示的 OpenCode 模型必须优先对齐真实 `/config.model`
- 模型列表只能展示已配置 provider / model，不能把总 provider 列表伪装成当前配置
- slash command 必须支持输入框弹层、一次性执行、原始命令文本保留
- 中文输入法下输入全角 `／` 时，也必须能触发 slash popup 和命令解析
- 普通 OpenCode 提问真机链路稳定，思考 / 正文 / 复制 / 使用统计展示不再出现已知错位
- `flutter analyze` 通过，debug APK 可成功构建并安装

---

## 最近核对结果

### 3. 重构 AI 适配器抽象层

验收结果:

- `ToolDetectionResult` 已增加 `capabilities`
- 检测缓存已可读写 `capabilities`
- `OpenCode / OpenClaw` 检测链路已按能力位返回结果
- `flutter analyze` 已通过

残留风险:

- `sessionContext` 仍是字符串，Provider 层还未升级到版本化上下文

### 4. 实现 OpenClaw Responses API 适配器

验收结果:

- `OpenClawApiAdapter` 已优先走 `/v1/responses`
- 已支持结构化 SSE 中的 `text / thinking / toolUse / error`
- 已支持非流式 JSON 响应解析
- `responses` 不可用时会自动回退到 `/v1/chat/completions`
- `flutter analyze` 已通过

残留风险:

- 目前仍未接 `history` 与显式会话恢复
- `usage` 已识别为能力，但尚未在 Provider / UI 中消费

### 5. 升级 OpenClaw launcher 与 detector

验收结果:

- launcher 已同时探测 `/v1/chat/completions` 与 `/v1/responses`
- 自动启动时会同时开启两个 OpenClaw HTTP 端点
- detector 会基于真实端点状态返回不同 `capabilities`
- `flutter analyze` 已通过

残留风险:

- 远端真实环境还未做端到端验证
- abort / kill 端点仍未纳入第一批协议实现

### 6. 升级 AISessionProvider 与持久化逻辑

验收结果:

- `AISessionProvider` 已按当前 `adapterId + mode` 解析可传给适配器的会话上下文
- 新的 `sessionContext` 已升级为版本化 JSON 字符串落盘，同时兼容旧的原始字符串
- Provider 已把 `thinking / toolUse / text` 统一转成流式 Markdown 输出
- 成功链路仍会回写到检测缓存
- `flutter analyze` 已通过

残留风险:

- 结构化块目前仍只在运行时展开，消息落盘仍是单段 Markdown
- `usage` 等 richer metadata 还未进入 Provider 状态

### 7. 补 AI Chat UI

验收结果:

- 聊天页会展示当前链路的关键能力摘要
- 工具选择器会展示工具链路策略和能力摘要
- 流式消息已切换到和完成消息一致的 AI 气泡样式
- 回退 / 中断 / 错误状态横幅已按语义区分图标与警示色
- `flutter analyze` 已通过

残留风险:

- `usage`、真正的结构化 tool card 仍未单独渲染
- 还未接入 OpenCode 的远端 authoritative history / event UI

### 8. 补 OpenCode 增强集成

验收结果:

- OpenCode adapter 已支持读取 `GET /session/{id}/message`
- OpenCode 查询成功后会尝试用远端 transcript 覆盖本地临时消息列表
- OpenCode 历史消息中的 `tool`、`step-finish` 已能格式化为工具调用和使用统计
- `listSessions` 已改为兼容真实的数组响应
- `flutter analyze` 已通过

残留风险:

- 还未接入 `GET /event` / `GET /global/event` 的长连接订阅
- `summarize` 仍未接入 UI 行为

### 9. 补测试

验收结果:

- 已新增 `AISessionContext` 单测
- 已新增 `AIConversationRepository.replaceMessages` 单测
- 已新增 AI 工具能力摘要文案单测
- 在全量 `flutter test` 输出中，新加测试均已执行通过

残留风险:

- 全量 `flutter test` 仍被仓库既有 widget 测试拦住，失败点不在本轮新增 AI 测试
- `verify test` 仍会被现有生成文件校验拦住

### 10. 做端到端校验与文档同步

验收结果:

- `README.md` 已同步 OpenClaw `responses` 优先链路与 OpenCode transcript 回灌说明
- `docs/技术方案.md` 已同步 AI 协议、`sessionContext` 持久化和 Provider 行为
- `docs/API接口设计.md` 已同步 OpenClaw / OpenCode 当前真实端点与能力说明
- 最终 `flutter analyze` 已通过

残留风险:

- `verify analyze` / `verify test` 仍会被仓库现有生成文件校验拦住
- 全量 `flutter test` 仍有既有 widget 测试失败，需后续单独治理

### 11. 追加需求: AI 思考过程可开关查看

验收结果:

- `thinking` 流式块已改为带内部标记的消息段，并在渲染层识别为可折叠的“模型思考”卡片
- 默认状态为折叠，用户可按消息单独点击“查看 / 收起”
- 复制 AI 消息时会自动剥离内部思考标记，避免把协议层标记暴露给用户
- 已新增 `thinking_disclosure_test.dart` 交互测试和 `ai_message_markup_test.dart` 解析测试
- `flutter analyze` 已通过

残留风险:

- 仅新生成的 `thinking` 消息段会自动折叠，历史上已落盘的旧 Markdown 思考块不会自动迁移
- 全量 `flutter test` 仍被仓库既有 widget 测试拦住，失败点不在本项新增改动

### 12. 一期控制面与会话动作扩展

验收结果:

- 已新增统一 `AIExecutionProfile`，并把执行偏好快照落到 `AISessionContext`
- `AIToolCapabilities` 与 `AIToolControlAdapter` 已扩展到控制面场景
- 聊天页已新增控制面按钮、控制摘要条和底部控制面板
- OpenCode 已支持 provider / model / variant / agent / shell / command / MCP / permission / share / unshare / summarize
- OpenClaw 已支持 agent / modelRef / reasoning / internal command 的会话级控制
- MCP 连接状态已同步回会话偏好，思考块支持按会话默认展开
- 已新增 `ai_execution_profile_test.dart`、`ai_session_context_test.dart`、`tool_mode_utils_test.dart`、`thinking_disclosure_test.dart` 相关覆盖
- 针对本轮改动的 `dart analyze` 与目标测试已通过

残留风险:

- OpenClaw 仍未接入正式的 `sessions.patch` 与 MCP 控制接口
- OpenCode 还未接 provider 登录/登出、fork、children、todo、diff 摘要
- 当前控制面仍以会话级偏好为主，`AIToolConfig` 默认值体系未扩展
- 全量回归尚未执行，当前验证范围是本轮涉及目录和新增/修改测试

### 13. 聊天页交互重构: 快捷控制条 + 独立模型选择 + 加号面板

验收结果:

- 聊天页已拆成“快捷控制条 + 高级设置 + 加号面板”三层，不再把常用能力全部堆进单个控制面弹层
- 快捷控制条已支持直接触达模型切换、自动审批、待审批数量、MCP 状态和当前输入模式 / 思考档位摘要
- 模型切换已独立成专门弹层，优先用于切换当前已发现的模型，不再混在总控制面里
- 已新增加号面板，承载图片、文件、终端日志附件、输入模式切换、模型管理、MCP 状态、分享 / 总结和高级设置入口
- OpenCode HTTP 已支持通过结构化 `parts` 发送图片 / 文件附件；OpenClaw HTTP `responses` 已支持 `input_image / input_file`
- 已新增 `chat_input_bar_test.dart`、`ai_control_strip_test.dart`，并与现有 `thinking_disclosure_test.dart` 一起通过目标测试
- `flutter analyze` 已通过

残留风险:

- OpenCode 的“添加模型 / Provider”目前仍以 Provider 切换和远端认证指引为主，尚未直接接入登录/登出 API
- OpenClaw 目前还没有把 `models.list` 与 `sessions.patch` 完整图形化，因此模型管理仍保留独立提示入口
- 附件当前只支持走 HTTP 链路；若用户主动切到非 HTTP 模式，会在发送前阻止并提示

### 14. OpenCode 调试收口: 过期 Provider/Model 兜底 + reasoning delta 流修复

验收结果:

- 已直接连接远端 OpenCode 服务器核对 `/config/providers`，确认当前真实 provider 只有 `minimax-cn-coding-plan` 与 `opencode`，不存在 `ollama-cloud`
- `AIControlSheet` 已对过期 `providerId / command / agent / model / variant` 做有效值收口，不再把失效值直接喂给 `DropdownButtonFormField`
- 高级设置中的模型切换已按 `provider/model` 解析并写回正确的 `providerId + modelId`
- OpenCode 事件流里的 `message.part.delta` 已不再一律按正文处理；现在会先识别 part 类型，再区分成 `thinking` 或 `text`
- 已对 reasoning delta 做去重保护，避免同一个 part 在 `message.part.updated` 完成时再次重复追加
- `AISessionProvider` 已改成基于当前流式内容合并 thinking 块，允许同一思考块持续增长，而不是一段一段拆成多个块
- `flutter analyze` 已通过

残留风险:

- 单文件 `flutter test` 在当前本机环境里仍会超时，暂时没有拿到稳定测试执行结果
- OpenCode 真实事件序列的远端自动化探针还没完全跑通到 `/event` 级别，因此最终真机验证仍需要你重装这版后复测
- 若远端模型本身不返回 reasoning，聊天页仍只会看到正文和“生成中”阶段，这是模型能力边界，不是 UI 解析问题

### 15. OpenCode 二轮收口: 真实模型来源、slash command、真机边角修复

验收结果:

- 已通过真实服务器与 OpenCode 源码核对，确认当前模型来源应以 `/config.model` 为准，`/config/providers` 只用于“已配置项列表”
- 聊天页顶部、高级设置、模型选择弹层已改为按真实当前模型与已配置模型分层展示
- OpenCode 配置入口已收回高级设置，不再通过加号面板伪装成“添加模型 / Provider”
- `session.status` 的结构化错误会直接展示，不再表现成“空 assistant / 没回复”
- OpenCode slash command 已接入输入框 popup、一次性执行和超时后轮询补捞结果
- slash command 已保留原始 `/<command> ...` 用户消息，避免被后续远端 transcript 再覆盖
- 复制已只保留正文，工具调用已并入“模型思考”，多段 thinking 会合并成单一思考框
- 非标准 Markdown 已增加回退文本渲染，长流式回复已收回消息列表滚动区，避免聊天页红屏和底部溢出
- SSH 密码认证前已增加换行清洗，真机 SSH 连接恢复后，OpenCode 普通提问链路已在设备上验证通过
- 针对中文输入法输入全角 `／` 的根因已定位并修复：slash 解析和本地 slash 消息保留逻辑均已兼容全角前缀
- `flutter analyze` 通过，debug APK 已成功构建并安装到真机

残留风险:

- 由于桌面端对连续 adb 交互存在不稳定拦截，“全角 `／` -> slash 列表 -> 选择命令 -> 执行成功”的完整真机闭环还没一次性跑完
- 当前 Windows 环境下 `flutter test` 仍存在本地 websocket listener `503` 问题，近期定向测试失败并不指向本轮 slash 修复本身
- OpenCode 的 `/event` / `/global/event` 长连接订阅仍未纳入产品正式主链
- provider 登录/登出、fork、children、todo、diff 等剩余 OpenCode 能力仍未完成图形化

---

## 核对规则

- 每完成一项，必须:
  - 回到本清单更新勾选状态
  - 在执行计划里同步标记完成
  - 说明本项的验收结果和残留风险

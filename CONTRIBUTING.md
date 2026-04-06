# Contributing

本仓库按开源项目方式维护，当前采用 `Apache-2.0` 许可证。本文件只约束当前协作流程，不替代未来可能补充的 `CODE_OF_CONDUCT` 或 `SECURITY` 文档。

---

## 当前状态

- 仓库已公开整理，欢迎通过 Issue / PR 参与讨论和改进。
- 仓库授权以根目录 [LICENSE](./LICENSE) 为准。
- 与当前实现不一致的历史规划文档很多，提交前请优先对照代码和 README。

---

## 提交前建议

1. 先阅读 [README.md](./README.md) 与 `docs/` 中的当前实现文档。
2. 尽量保持一次提交只解决一类问题。
3. 代码改动同步更新文档，避免“代码已实现、文档仍写规划态”。
4. 提交前至少完成与改动直接相关的 `analyze` / `test` 校验。

---

## 变更范围

- 欢迎：
  - Bug 修复
  - 文档同步
  - 测试补充
  - 现有功能的稳定性改进
- 提交前请谨慎扩 scope：
  - 未经讨论不要直接引入新的云服务依赖
  - 不要把历史规划文档里的商业化/订阅功能重新写回当前实现
  - 大范围 UI 重做建议先开 Issue 对齐方向

---

## 提交说明

- Commit message 尽量简洁明确，例如：
  - `fix: persist wallpaper and theme preferences`
  - `docs: sync backend implementation status`
  - `test: cover theme provider persistence`

---

## 文档约定

- 当前实现文档优先级高于历史规划文档。
- 涉及后端、存储、运行链路时，优先同步：
  - `README.md`
  - `docs/技术方案.md`
  - `docs/架构设计.md`
  - `docs/数据库设计.md`
  - `docs/API接口设计.md`
  - `docs/上线检查清单.md`

---

## 联系与协作

- 建议优先通过仓库 Issue 讨论问题、设计和任务边界。
- 如果未来补充社区规范或安全披露流程，以仓库最新文档为准。

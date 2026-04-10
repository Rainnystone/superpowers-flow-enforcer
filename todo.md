# TODO 追踪（2026-04-11）

## Superpowers Flow Enforcer 修复

- [x] 修复 `hooks.json` 中 Hook 输入变量引用（`$TOOL_INPUT/$TOOL_RESULT/$USER_PROMPT`）
- [x] 修复 `PreToolUse` 返回格式（`permissionDecision: allow|deny`）
- [x] 修复 `PostToolUse` 使用 `continue` 输出，`Stop` 使用 `decision` 输出
- [x] 修复中断状态字段不一致（统一 `interrupt.*`）
- [x] 修复 `update-state.sh` 顶层字段更新失败问题（支持 `current_phase`）
- [x] 增加用户输入状态同步脚本 `sync-user-prompt-state.sh`
- [x] 增加工具后状态同步脚本 `sync-post-tool-state.sh`
- [x] 收紧 TDD 例外范围（移除 `superpowers-flow-enforcer/*` 全目录豁免）
- [x] 本地验证：JSON、shell 语法、脚本行为
- [x] 提交并推送到远端

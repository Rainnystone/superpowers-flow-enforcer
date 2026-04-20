# Superpowers 流程强制执行器

[English](./README.md) | 中文

一个 Claude Code 插件，在会话**明确进入** superpowers 工作流之后，通过 workflow-aware hooks 强制执行关键阶段。它是 [obra/superpowers](https://github.com/obra/superpowers) 的补充，不是替代品，并且设计上需要配合 [planning-with-files](https://github.com/othmanadi/planning-with-files) 提供外部记忆。这个仓库仍然以单个插件的形式安装：Bash gate 使用仓库内 vendored 的 `vendor/bash-traverse` runtime，不需要额外 clone 或 build parser 仓库。

## 概述

**核心原则**: 执行时不跳步骤。

插件实现 workflow-aware hooks，强制执行：
- 在会话明确进入 superpowers workflow 之前，workflow-only 门禁默认 fail-open
- Brainstorming → SPEC → Planning → TDD → Review → Verification → Finishing 工作流
- 两阶段代码审查（spec 合规性 + 代码质量）
- 在 superpowers packetized execution 中增加 subagent 的 task-boundary 门禁，当前任务双 review 未完成前不能启动下一个任务的 implementer
- 完成声明前必须有新鲜验证证据
- 测试失败时使用系统化调试方法论

这里的“进入 workflow”是显式动作，不是对所有 Claude Code 会话一刀切推断。当前实现里，进入动作包括：记录 skip 请求、用户明确输入受支持的手动进入命令，比如 `开启 enforcer` / `enable enforcer`，或者兼容保留的长命令 `激活 superpowers enforcer` / `activate superpowers enforcer`，以及在当前项目作用域内写入 canonical superpowers 工件 `docs/superpowers/specs/*.md` / `docs/superpowers/plans/*.md`。自动路径激活既保留仓库根目录下的 canonical 路径，也支持像 `packages/foo/docs/superpowers/specs/*.md` 这种子树 canonical 路径，同时会排除 `.git`、`.worktrees`、`node_modules`、`vendor`、`.simulation` 以及 fixture/testdata 目录。

`PreToolUse/Bash` 只有在 `workflow.active == true` 时才会运行真正的 gate；如果 workflow 没有激活，它会静默 no-op。激活后，Bash gate 通过 Node 执行 vendored 的 Bash parser runtime，因此需要 Node 18+。

`planning-with-files` 仍然是这个工作流的预期组成部分，因为它提供 `task_plan.md`、`findings.md`、`progress.md` 这套持久化外部记忆。这个定位尤其适合 Claude Code 集成里路由到 GLM-5、只有 128K 上下文窗口的配置，磁盘上的记录可以降低长会话里的上下文丢失。

## 安装

按预期工作流，建议把这三部分一起装好并使用：

1. 安装并使用 [obra/superpowers](https://github.com/obra/superpowers)。
2. 安装并使用 [planning-with-files](https://github.com/othmanadi/planning-with-files)。
3. 从本地源码安装这个插件：
   ```
   /plugin marketplace add /absolute/path/to/superpowers-flow-enforcer
   /plugin install superpowers-flow-enforcer@superpowers-flow-enforcer-marketplace
   /reload-plugins
   ```

   如果你是通过三方 marketplace 安装，这个插件在 `/plugin` 里显示出来的身份信息，仍然来自插件包内的 `.claude-plugin/plugin.json`。那才是 Claude Code 官方识别的插件 manifest；仓库根目录的 `manifest.json` 不是。

   **备选方案：开发/测试时临时加载**
   ```
   claude --plugin-dir /absolute/path/to/superpowers-flow-enforcer
   ```
   这种方式只在当前会话生效，不会写入安装注册表。

如果你在当前会话里安装或变更了其他插件，执行：
   ```
   /reload-plugins
   ```

不需要额外 clone 或 build `bash-traverse`。它已经被 vendored 到这个仓库里；但激活中的 Bash gate 仍然要求运行 Claude Code 的机器上有 Node 18+。

## 使用方式

在 brainstorming、spec、planning、execution、review 和 verification 阶段，建议把三者一起用：

- `superpowers` 提供工作流纪律。
- `planning-with-files` 负责 `task_plan.md`、`findings.md`、`progress.md` 这套持久化外部记忆。
- 这个插件在会话真正进入 superpowers workflow 后，负责强制阶段衔接和 no-skip 规则。

插件不会对每个 Claude Code 会话强行激活 workflow。如果 workflow 从未激活，workflow-only 门禁会保持 inactive，不会阻断普通 Claude Code 工作。

如果你不想依赖自动路径激活，也可以手动控制。本轮只认这些精确命令，执行前会先做空白归一化：

- `开启 enforcer`
- `关闭 enforcer`
- `enable enforcer`
- `disable enforcer`

为了兼容既有习惯和脚本，长命令仍然可用，但同样只认精确命令：

- `激活 superpowers enforcer`
- `关闭 superpowers enforcer`
- `activate superpowers enforcer`
- `deactivate superpowers enforcer`

像 `请开启 enforcer`、`Please enable enforcer, thanks`、`disable enforcer and stop for now` 这样的句子，本轮都不会触发开关。`启动 enforcer`、`停止 enforcer`、`start enforcer`、`stop enforcer` 也不支持。要关闭强制执行，请用 `关闭 enforcer` / `disable enforcer`，不要把 `stop` 理解成“关闭 enforcement”。

## Hook 系统

| Hook 事件 | 匹配器 | 强制执行 |
|-----------|--------|----------|
| SessionStart | * | 初始化工作流状态 |
| UserPromptSubmit | * | Bypass / 精确开关命令检测 / 精确中断命令检测 + 缺失状态自举 |
| PreToolUse | Edit\|Write | workflow-aware 写入门禁 + TDD 铁律 |
| PreToolUse | AskUserQuestion | 仅在 workflow 激活时要求更新 Brainstorming findings |
| PreToolUse | Agent | 仅针对 superpowers packetized execution 的 task-boundary 门禁 + reviewer 角色约束 |
| PreToolUse | Bash | 只有 `workflow.active == true` 时才执行 Bash gate，否则静默 no-op |
| PostToolUse | * | 工作流状态同步，包括成功的 Agent 派发后的 task_flow 更新 |
| TaskCompleted | * | 仅在 workflow 激活时要求两阶段审查完成 |
| PostToolUseFailure | Bash | 测试失败时系统化调试 |
| Stop | * | 仅 command-only 完成验证，依据 `last_assistant_message` + workflow-aware 停止门禁 |

## TDD 强制执行（最关键）

PreToolUse hook 执行 TDD 铁律：

```
没有失败的测试，就不能写生产代码
```

写生产文件时（如 `src/utils/helper.ts`）：
1. 如果没有对应测试文件 → 阻断
2. 如果测试存在但未验证失败 → 阻断
3. 只有测试验证失败后 → 允许

**识别的测试文件模式**:
- `test/`, `tests/`, `spec/`, `__tests__/` 目录
- 文件名含 `.test.` 或 `.spec.`
- `_test.` 或 `_spec.` 后缀

**TDD 例外**（配置文件、类型定义、文档、生成文件）:
- 通过 PreToolUse 的路径白名单规则处理
- 类别: config, types, docs, generated, specs, plugin

## Packetized Subagent Execution

这不是全局禁用 Agent，而是一个 `PreToolUse/Agent` 的 command hook，只在 superpowers 的 packetized execution 已经进入执行态时约束任务边界。

运行时 Agent prompt 开头必须带上：

- `SPFE_TASK_ID=<task-id>`
- `SPFE_PACKET_ROLE=implementer|spec-reviewer|code-reviewer`

强制规则如下：

- 当前 open task 只有在 `spec_review_passed == true` 且 `code_review_passed == true` 后，才允许派发下一个任务的 `implementer`。
- `spec-reviewer` 和 `code-reviewer` 必须是两个独立 reviewer 角色；合并 reviewer 或泛化 reviewer 包会被拒绝。
- 当前任务 spec review 还没通过时，不允许先派发 `code-reviewer`。
- 同一任务内的 `implementer -> fix -> re-review` 循环会继续放行，因此 review 意见可以在不新开任务的情况下闭环。

## Bypass 机制

跳过某个阶段时，说明你的理由：

**英文**:
- "skip brainstorming - this is a simple bug fix"
- "skip tdd - this is a config file change"

**中文**:
- "跳过 brainstorming - 这是一个简单的 bug 修复"
- "跳过测试 - 这是一个配置文件修改"
- "不需要测试 - 这是自动生成的代码"

插件会：
1. 记录你的 bypass 请求到状态
2. 请求确认
3. 确认后允许跳过

## 中断处理

需要暂停任务时，请使用这些精确中断命令（会先做空白归一化）：

- `stop task`
- `pause task`
- `停止任务`
- `暂停任务`

这些命令和 enforcer 开关是两回事。`stop` 不表示关闭 workflow enforcement。

暂停处理是精确命令检测：只有这些受支持命令会写入 `interrupt.allowed`，再由 command-only 的 `Stop` 读取状态后放行停止。

## 恢复握手

如果是恢复一个未完成 workflow，必须先运行 `/superpowers-flow-enforcer:resume-enforcer`，然后才能开始新的编辑或新的 Agent 派发。这一步是恢复流程的一部分，不是可选补救。

恢复时的规划记录遵循 `planning-with-files` 的默认约定：

- 优先读取项目根目录下的 `task_plan.md`、`progress.md`、`findings.md`
- 如果根目录没有，再兼容读取 `.planning-with-files/task_plan.md`、`.planning-with-files/progress.md`、`.planning-with-files/findings.md`
- 如果两边都没有，恢复流程继续使用 workflow state 和 git 上下文，不会因此报错

恢复相关状态字段包括：

- `resume.recovery_required`
- `resume.recovery_completed_at`
- `resume.last_resume_source`

## 完成前验证

声明完成时（"完成", "tests pass", "修复了"）：
- 必须在当前 assistant message 中展示**新鲜**验证证据
- 不能用"上次通过了"或"应该没问题"
- Stop hook 会阻断无新鲜证据的声明

**中文关键词**: "完成", "done", "tests pass", "修复了", "working"

## 文件结构

```
.claude-plugin/
├── plugin.json        # Claude Code 在 /plugin 中使用的官方插件 manifest
└── marketplace.json   # 这个仓库自带的本地/测试 marketplace 目录文件
manifest.json          # 旧的仓库级元数据，不是 Claude Code 官方插件 manifest
CLAUDE.md              # Claude 指令文档
README.md              # 英文文档
README_cn.md           # 中文文档
hooks/
└── hooks.json         # 所有 hook 配置
scripts/
├── init-state.sh      # SessionStart 状态初始化
├── update-state.sh    # 状态更新辅助脚本
├── sync-user-prompt-state.sh # UserPromptSubmit 状态同步
├── sync-post-tool-state.sh   # PostToolUse 状态同步，包括 Agent task_flow 同步
├── check-pretool-gates.sh # PreToolUse/Edit|Write、AskUserQuestion 和 Agent gate
├── check-bash-command-gate.sh # PreToolUse/Bash gate
├── check-bash-command-gate-node.cjs # vendored bash-traverse 分析 runtime
├── check-task-completed.sh # TaskCompleted gate
├── check-stop-review-gate.sh # Stop 完成验证 gate
└── check-exception.sh # 历史辅助脚本（当前 hooks 不调用）
templates/
└── flow_state.json.tmpl # 状态文件模板
vendor/
└── bash-traverse/      # Bash gate 使用的 vendored parser/runtime
```

## 状态追踪

状态文件: `$CLAUDE_PROJECT_DIR/.claude/flow_state.json`

追踪内容:
- `current_phase`: init → brainstorming → planning → tdd → review → finishing
- `workflow.*`: `active`、`override`、`activated_by`、`activated_at`、`deactivated_by`、`deactivated_at`
- `brainstorming.*`: `question_asked`、`findings_updated_after_question`、`spec_written`、`spec_reviewed`、`user_approved_spec`
- `planning.*`: `plan_written`、`plan_file`、`execution_mode`
- `worktree.*`: `created`、`path`、`baseline_verified`
- `tdd.*`: `pending_failure_record`、`last_failed_command`、`test_files_created`、`production_files_written`、`tests_verified_fail`、`tests_verified_pass`
- `task_flow.*`: `active_task_id`、`active_packet_role`、`last_dispatch_at`
- `resume.*`: `recovery_required`、`recovery_completed_at`、`last_resume_source`
- `review.tasks`: 每个任务的审查状态
- `finishing.*`: `invoked`
- `debugging.*`: active, fixes attempted, root cause found
- `exceptions.*`: bypass 标记, 用户确认
- `interrupt.*`: allowed, reason, 兼容保留字段 `keywords_detected`

## 强制的 Skills

插件引用这些 superpowers skills:
- `brainstorming` - 设计阶段：问题 → SPEC
- `writing-plans` - 实现计划创建
- `using-git-worktrees` - 隔离工作空间设置
- `test-driven-development` - 先写测试，验证失败，再写代码
- `subagent-driven-development` - 每任务两阶段审查
- `requesting-code-review` - Spec + 代码质量审查
- `verification-before-completion` - 需要新鲜测试证据
- `systematic-debugging` - 修复前先调查根因
- `finishing-a-development-branch` - 最终验证和合并选项

## 故障排除

**Hook 未触发**: 执行 `/plugin` 查看 Installed/Errors，再执行 `/reload-plugins`。

**插件可见但元数据不对**: 先检查 `.claude-plugin/plugin.json`。Claude Code 在 `/plugin` 里识别插件身份看的是这个文件，不是仓库根目录的 `manifest.json`。

**意外被阻断**: 检查状态文件的当前阶段状态。可能需要先完成前一阶段。

**为什么 workflow 门禁没生效**: 先确认当前会话是否真的进入了 superpowers workflow，比如是否记录了 skip 请求、是否明确输入了受支持的手动进入命令 `开启 enforcer` / `enable enforcer`，或者兼容保留的长命令 `激活 superpowers enforcer` / `activate superpowers enforcer`，又或者是否写入了当前项目作用域内的 canonical `docs/superpowers/specs/*.md` / `docs/superpowers/plans/*.md`。

**恢复中的未完成 workflow 被拦住了**: 先运行 `/superpowers-flow-enforcer:resume-enforcer`。只要 `resume.recovery_required` 还没有清掉，就不要开始新的编辑或新的 Agent 派发。恢复时会先读根目录规划文件，必要时才 fallback 到 `.planning-with-files/`。

**Bash gate 提示需要 Node**: 安装 Node 18+，或者确保 `node` 在 `PATH` 里。激活中的 Bash gate 会通过 Node 运行 vendored 的 parser runtime。

**Bypass 不生效**: 确保清楚说明了理由。插件需要确认。

**测试验证失败**: 运行实际测试命令并展示输出。不要只说"tests pass"。

**SessionStart 报 `jq: command not found`**: 插件的 hook 脚本依赖 `jq` 做 JSON 状态管理。macOS 和大多数 Linux 发行版通常已预装或可通过包管理器安装（`brew install jq`、`apt install jq`）。Windows 用户可执行 `winget install jqlang.jq` 或从 [jqlang/jq releases](https://github.com/jqlang/jq/releases) 下载。安装后需重启终端使新 `PATH` 生效。

**SessionStart 报 `shasum: command not found`（Windows）**: `init-state.sh` 已使用跨平台 hash fallback（优先 `sha256sum`，回退 `shasum -a 256`）。如果两者都找不到，请确认你的 Git Bash / shell 环境包含 GNU coreutils（`sha256sum`）。标准的 Git Bash for Windows 安装应该自带。

## 许可证

MIT

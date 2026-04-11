# Superpowers 流程强制执行器

[English](./README.md) | 中文

一个 Claude Code 插件，通过 hooks 强制执行 superpowers 工作流，防止跳过关键开发阶段。它是 [obra/superpowers](https://github.com/obra/superpowers) 的补充，不是替代品，并且这个仓库的工作流设计为与 [planning-with-files](https://github.com/othmanadi/planning-with-files) 配合使用来提供外部记忆。

## 概述

**核心原则**: 执行时不跳步骤。

插件实现硬阻断 hooks，强制执行：
- Brainstorming → SPEC → Planning → TDD → Review → Verification → Finishing 工作流
- 两阶段代码审查（spec 合规性 + 代码质量）
- 完成声明前必须有新鲜验证证据
- 测试失败时使用系统化调试方法论

`planning-with-files` 在这里提供持久化的外部记忆，通过 `task_plan.md`、`findings.md`、`progress.md` 记录状态。这个定位尤其适合 Claude Code 集成里路由到 GLM-5、只有 128K 上下文窗口的配置，因为磁盘上的追踪可以帮助长会话保持一致。

## 安装

按这个顺序安装和使用：

1. 先安装并使用 [obra/superpowers](https://github.com/obra/superpowers)。
   ```
   /plugin install superpowers@claude-plugins-official
   ```
   如果你使用社区 marketplace 版本：
   ```
   /plugin marketplace add obra/superpowers-marketplace
   /plugin install superpowers@superpowers-marketplace
   ```
2. 再安装并使用 [planning-with-files](https://github.com/othmanadi/planning-with-files)，让项目具备 `task_plan.md`、`findings.md`、`progress.md` 这套持久记忆。
   ```
   /plugin marketplace add OthmanAdi/planning-with-files
   /plugin install planning-with-files@planning-with-files
   ```
3. 从本地源码持久化安装这个插件：
   ```
   /plugin marketplace add /absolute/path/to/superpowers-flow-enforcer
   /plugin install superpowers-flow-enforcer@superpowers-flow-enforcer-marketplace
   /reload-plugins
   ```

   **备选方案：开发/测试时临时加载**
   ```
   claude --plugin-dir /absolute/path/to/superpowers-flow-enforcer
   ```
   这种方式只在当前会话生效，不会写入安装注册表。

4. 如果你在当前会话里安装或变更了其他插件，执行：
   ```
   /reload-plugins
   ```

顺序很重要：先有 superpowers，再配合 planning-with-files，最后安装这个插件。

## 使用方式

在 brainstorming、spec、planning 和 execution 这几个阶段把三者一起用：

- `superpowers` 负责工作流和阶段纪律。
- `planning-with-files` 把稳定状态写进 `task_plan.md`、`findings.md`、`progress.md`。
- 这个插件负责强制衔接，避免跳过 brainstorming、planning、review 或 verification。

实际操作时，先用 superpowers 做 brainstorming 和 spec，再把计划写入 planning-with-files，执行过程中持续更新 `progress.md`。

## Hook 系统

| Hook 事件 | 匹配器 | 强制执行 |
|-----------|--------|----------|
| SessionStart | * | 初始化工作流状态 |
| UserPromptSubmit | * | Bypass 请求检测 |
| PreToolUse | Edit\|Write | TDD 铁律 - 无失败测试禁止写生产代码 |
| PostToolUse | AskUserQuestion | Brainstorming findings 更新 |
| PostToolUse | Write\|Edit | SPEC 自审要求 |
| PostToolUse | Write | Plan → Worktree 转换 |
| PostToolUse | Bash | Worktree → 基准测试 |
| PostToolUse | TaskCompleted | 两阶段审查完成 |
| PostToolUseFailure | Bash | 测试失败时系统化调试 |
| Stop | * | 完成前验证 + 中断处理 |

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

需要暂停时：

**英文**: "stop", "pause", "break"

**中文**: "停止", "暂停", "暂停一下", "休息一下", "明天继续", "稍后继续"

暂停处理是 text keyword 检测：从用户文本关键词写入 `interrupt.allowed`，再由 `Stop` 读取状态后放行停止。

## 完成前验证

声明完成时（"完成", "tests pass", "修复了"）：
- 必须展示**新鲜**验证证据（当前消息的测试输出）
- 不能用"上次通过了"或"应该没问题"
- Stop hook 会阻断无新鲜证据的声明

**中文关键词**: "完成", "done", "tests pass", "修复了", "working"

## 文件结构

```
manifest.json          # 插件元数据
CLAUDE.md              # Claude 指令文档
README.md              # 英文文档
README_cn.md           # 中文文档
hooks/
└── hooks.json         # 所有 hook 配置
scripts/
├── init-state.sh      # SessionStart 状态初始化
├── update-state.sh    # 状态更新辅助脚本
├── sync-user-prompt-state.sh # UserPromptSubmit 状态同步
├── sync-post-tool-state.sh   # PostToolUse 状态同步
└── check-exception.sh # 历史辅助脚本（当前 hooks 不调用）
templates/
└── flow_state.json.tmpl # 状态文件模板
```

## 状态追踪

状态文件: `$CLAUDE_PROJECT_DIR/.claude/flow_state.json`

追踪内容:
- `current_phase`: init → brainstorming → planning → tdd → review → finishing
- `brainstorming.*`: `question_asked`、`findings_updated_after_question`、`spec_written`、`spec_reviewed`、`user_approved_spec`
- `planning.*`: `plan_written`、`plan_file`、`execution_mode`
- `worktree.*`: `created`、`path`、`baseline_verified`
- `tdd.*`: `pending_failure_record`、`last_failed_command`、`test_files_created`、`production_files_written`、`tests_verified_fail`、`tests_verified_pass`
- `review.tasks`: 每个任务的审查状态
- `finishing.*`: `invoked`
- `debugging.*`: active, fixes attempted, root cause found
- `exceptions.*`: bypass 标记, 用户确认
- `interrupt.*`: allowed, reason, keywords detected

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

**意外被阻断**: 检查状态文件的当前阶段状态。可能需要先完成前一阶段。

**Bypass 不生效**: 确保清楚说明了理由。插件需要确认。

**测试验证失败**: 运行实际测试命令并展示输出。不要只说"tests pass"。

## 许可证

MIT

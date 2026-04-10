# Superpowers 流程强制执行器

[English](./README.md) | 中文

一个 Claude Code 插件，通过 hooks 强制执行 superpowers 工作流，防止跳过关键开发阶段。

## 概述

**核心原则**: 执行时不跳步骤。

插件实现硬阻断 hooks，强制执行：
- Brainstorming → SPEC → Planning → TDD → Review → Verification → Finishing 工作流
- 两阶段代码审查（spec 合规性 + 代码质量）
- 完成声明前必须有新鲜验证证据
- 测试失败时使用系统化调试方法论

## 安装

1. 将 `superpowers-flow-enforcer` 目录复制到你的 Claude 插件文件夹：
   ```
   ~/.claude/plugins/superpowers-flow-enforcer/
   ```

2. 重启 Claude Code 加载插件。

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
| PostToolUse | TaskUpdate | 两阶段审查完成 |
| PostToolUse | Bash | 测试失败时系统化调试 |
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
- 通过 `check-exception.sh` 自动检查
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

插件记录中断并允许干净停止。

## 完成前验证

声明完成时（"完成", "tests pass", "修复了"）：
- 必须展示**新鲜**验证证据（当前消息的测试输出）
- 不能用"上次通过了"或"应该没问题"
- Stop hook 会阻断无新鲜证据的声明

**中文关键词**: "完成", "done", "tests pass", "修复了", "working"

## 文件结构

```
superpowers-flow-enforcer/
├── manifest.json          # 插件元数据
├── CLAUDE.md              # Claude 指令文档
├── README.md              # 英文文档
├── README_cn.md           # 中文文档
├── hooks/
│   └── hooks.json         # 所有 hook 配置
├── scripts/
│   ├── init-state.sh      # SessionStart 状态初始化
│   ├── update-state.sh    # 状态更新辅助脚本
│   └── check-exception.sh # TDD 例外检测
└── templates/
    └── flow_state.json.tmpl # 状态文件模板
```

## 状态追踪

状态文件: `$CLAUDE_PROJECT_DIR/.claude/flow_state.json`

追踪内容:
- `current_phase`: init → brainstorming → planning → tdd → review → finishing
- `brainstorming.*`: skill invoked, findings updated, spec written/approved
- `planning.*`: plan written, execution mode
- `worktree.*`: created, baseline tests passed
- `tdd.*`: test files, production files, verified failing tests
- `review.tasks`: 每个任务的审查状态
- `finishing.*`: tests verified, choice made
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

**Hook 未触发**: 检查插件是否安装在 `~/.claude/plugins/`。

**意外被阻断**: 检查状态文件的当前阶段状态。可能需要先完成前一阶段。

**Bypass 不生效**: 确保清楚说明了理由。插件需要确认。

**测试验证失败**: 运行实际测试命令并展示输出。不要只说"tests pass"。

## 许可证

MIT
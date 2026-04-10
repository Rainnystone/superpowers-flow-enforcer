# 任务计划：Superpowers 流程强制执行 Hooks

## 目标
编写 hooks 系统强制执行 superpowers 流程，防止跳步骤（brainstorming → planning → TDD → review → verification）

## 当前阶段
阶段 2 完成（Plan 已写完，等待选择执行方式）

## 各阶段

### 阶段 1：需求与发现
- [x] 调用所有相关 superpowers skills 了解流程
- [x] 分析完整流程阶段和结束标志
- [x] 初步设计 9 个 hook 点
- [x] 研究 hooks 技术能力和限制
- [x] 确认技术实现细节（5 个问题）
- [x] 将发现记录到 findings.md
- **状态：** complete

### 阶段 2：Hook 设计 + SPEC + Plan
- [x] 设计状态文件结构
- [x] 设计每个 hook 的检测逻辑和阻断条件
- [x] 确定例外处理机制（用户 bypass）
- [x] 更新 findings.md 记录设计决策
- [x] 编写 SPEC 文件
- [x] 执行 Spec Self-Review
- [x] 编写 Implementation Plan（12 tasks）
- [x] 执行 Plan Self-Review
- **状态：** complete

### 阶段 3：Hook 实现（12 Tasks）
- [x] Task 1: Plugin 目录结构和 manifest.json
- [x] Task 2: 状态文件模板和 init-state.sh
- [x] Task 3: update-state.sh 辅助脚本
- [x] Task 4: check-exception.sh（TDD 例外检测）
- [x] Task 5: hooks.json（SessionStart + Hook 1-2）
- [x] Task 6: hooks.json（Hook 3-4：Planning → Worktree）
- [x] Task 7: hooks.json（Hook 5：TDD 入口检查）
- [x] Task 8: hooks.json（Hook 6-9：Review → Debugging）
- [x] Task 9: hooks.json（补充流程：Bypass + 中断）
- [x] Task 10: CLAUDE.md（Plugin 指令）
- [x] Task 11: README.md（用户文档）
- [x] Task 12: 测试和验证
- **状态：** complete

### 阶段 4：集成测试
- [x] 模拟完整流程验证 hooks
- [x] 修复问题
- **状态：** complete

### 阶段 5：交付
- [x] 文档说明 hooks 使用方式
- [x] 交付给用户
- **状态：** complete

## 关键问题
1. ~~Hook 能访问 tool call history 吗？（检测是否调用过某个 skill）~~ **已解决：不能，使用状态文件**
2. ~~Hook 能检测输出文本吗？（检测"完成/done"声明）~~ **已解决：不能直接检测，用 prompt hook 读取 transcript**
3. ~~PostToolUse on Bash 能匹配 command 内容吗？~~ **已解决：matcher 只匹配 tool_name，用 prompt hook 读取 $TOOL_INPUT.command**
4. ~~状态文件更新方式：Hooks 自动检测 vs 显式标记~~ **已解决：两者结合，hooks 自动更新关键节点**
5. ~~Review passed 判断：解析 subagent 输出 vs 明确返回格式~~ **已解决：按技能界定，prompt hook 检测 transcript**

## 待确认问题
1. ~~TDD 例外文件规则是否完整？~~ **已确认：不需要额外例外**
2. ~~用户 bypass 机制如何设计？~~ **已确认：A+B 方案**
3. ~~Stop hook 如何处理"工作中断"情况？~~ **已确认：关键词检测**

## 下一步：选择执行方式

## 已做决策
| 决策 | 理由 |
|------|------|
| 采用方案 A（硬阻断式） | B 和 C 没用，用户倾向于强制执行 |

## 遇到的错误
| 错误 | 尝试次数 | 解决方案 |
|------|---------|---------|
|      |         |         |

## 备注
- 核心：不让执行时跳步骤
- 问题 2：优先按技能界定，其次考虑检测文本
- 问题 1,3,4,5：按 best practice 给建议
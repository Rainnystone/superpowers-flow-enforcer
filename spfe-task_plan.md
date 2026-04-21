# 任务计划：Fix P0-P5 六项兼容性修复

## 目标
修复 superpowers-flow-enforcer 插件的六项 spec/contract 问题，按 TDD 流程逐 packet 实施。

## 当前阶段
阶段 3（TDD 实施）

## 各阶段

### 阶段 1：需求与发现
- [x] 理解 P0-P5 六项修复需求
- [x] 阅读 spec（`docs/superpowers/specs/fix-p0-p1-compatibility.md`）
- [x] 将发现记录到 findings.md
- **状态：** complete

### 阶段 2：规划与结构
- [x] 编写 implementation plan（`docs/superpowers/plans/2026-04-21-fix-p0-p1-p2-p3-compatibility.md`）
- [x] 7 个 packet 划定文件边界、并行安全性、验证命令
- [x] Plan review 通过（用户授权 bypass）
- **状态：** complete

### 阶段 3：TDD 实施
- **状态：** in_progress

#### Packet 1: P0 — code-quality-reviewer 兼容别名 ✅
- [x] RED: 编写测试（test_agent_task_boundary_gate.sh）
- [x] GREEN: 修改 task_flow_packets.sh、check-pretool-gates.sh、sync-post-tool-state.sh
- [x] 验证测试通过
- [x] Commit: `49cad75`
- [x] Spec review: PASS
- [x] Code quality review: Approved with suggestions
- **Important suggestions noted for Packet 7:** (1) comment on `_raw` function about un-normalized alias, (2) missing spec-specified tests for Python extraction unit test and integration workflow

#### Packet 2: P1 — 文档修正 hook profile pollution 🔄
- [ ] 更新 README.md、README_cn.md、CLAUDE.md
- [ ] 验证 hooks.json 未变
- [ ] Commit

#### Packet 3: P2 — Stop hook phase guard
- [ ] RED: 编写测试（test_stop_gates.sh）
- [ ] GREEN: 修改 check-stop-review-gate.sh
- [ ] 验证测试通过
- [ ] Commit

#### Packet 4: P3 — State file corruption guard
- [ ] RED: 编写测试（test_init_state.sh）
- [ ] GREEN: 修改 init-state.sh、update-state.sh
- [ ] 验证测试通过
- [ ] Commit

#### Packet 5: P4 — Repo-local plan review gate
- [ ] RED: 编写测试（test_posttool_command_gates.sh）
- [ ] GREEN: 修改 flow_state.json.tmpl、sync-post-tool-state.sh、migrate-state.sh；创建 record-plan-state.sh
- [ ] 验证测试通过
- [ ] Commit

#### Packet 6: P5 — Midstream activation phase recovery
- [ ] RED: 编写测试（test_bypass_state.sh、test_workflow_activation.sh）
- [ ] GREEN: 修改 sync-user-prompt-state.sh
- [ ] 验证测试通过 + resume contract 不变
- [ ] Commit

#### Packet 7: 全量回归 + 文档同步
- [ ] 运行全量测试套件
- [ ] 同步 CLAUDE.md、README.md、README_cn.md
- [ ] 更新 task_plan.md、progress.md、findings.md
- [ ] Final commit

### 阶段 4：Review
- [ ] Spec review
- [ ] Code quality review
- **状态：** pending

### 阶段 5：交付
- [ ] 验证所有需求已满足
- [ ] Finishing branch
- **状态：** pending

## 关键问题
1. 无（所有问题已在 spec/plan 中解决）

## 已做决策
| 决策 | 理由 |
|------|------|
| Brainstorming bypass | Spec 已在前序会话完成，用户授权 bypass |
| Spec/Plan review bypass | Plan 已经过多轮 review，用户授权 bypass |
| 从 TDD 阶段开始 | 前序阶段已完成，实施从 Packet 1 开始 |

## 遇到的错误
| 错误 | 尝试次数 | 解决方案 |
|------|---------|---------|
| assert.sh process substitution Windows 不兼容 | 1 | 添加 /dev/fd/* /proc/* 路径检测，用 cat pipe 替代 |
| Windows python3 为 Microsoft Store stub | — | 使用 python (3.12.10)，环境问题非代码缺陷 |

## 备注
- Plan 文件：`docs/superpowers/plans/2026-04-21-fix-p0-p1-p2-p3-compatibility.md`
- Spec 文件：`docs/superpowers/specs/fix-p0-p1-compatibility.md`
- Packet 1/3/4 可并行，Packet 2 与所有其他 packet 可并行
- 所有 checkbox 同步到 plan 文件

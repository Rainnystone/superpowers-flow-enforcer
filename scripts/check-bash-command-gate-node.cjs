#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const TARGET_PATH = process.env.BASH_GATE_TARGET_PATH || '.claude/flow_state.json';
const DENY_REASON = '禁止在激活工作流中直接操作 .claude/flow_state.json，请通过 scripts/update-state.sh。';
const ANALYSIS_FAILURE_REASON = 'Bash gate 无法完成命令分析：bash-traverse 解析失败。';

function deny(reason) {
  return JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'deny',
      permissionDecisionReason: reason,
    },
  });
}

function normalizeForFallback(command) {
  return command.replace(/['"\\]/g, '');
}

function main() {
  const payload = JSON.parse(fs.readFileSync(0, 'utf8') || '{}');
  JSON.parse(process.env.BASH_GATE_STATE_JSON || '{}');

  const command = payload && payload.tool_input && typeof payload.tool_input.command === 'string'
    ? payload.tool_input.command
    : '';
  if (!command) {
    return;
  }

  const runtimePath = path.join(__dirname, '..', 'vendor', 'bash-traverse', 'dist', 'index.js');
  if (normalizeForFallback(command).includes(TARGET_PATH)) {
    process.stdout.write(deny(DENY_REASON));
    return;
  }

  const { parse, traverse } = require(runtimePath);
  try {
    const ast = parse(command);
    traverse(ast, {});
  } catch (error) {
    return;
  }
}

try {
  main();
} catch (error) {
  process.stdout.write(deny(ANALYSIS_FAILURE_REASON));
}

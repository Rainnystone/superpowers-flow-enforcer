#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');

const TARGET_PATH = process.env.BASH_GATE_TARGET_PATH || '.claude/flow_state.json';
const DENY_REASON = '禁止在激活工作流中直接操作 .claude/flow_state.json，请通过 scripts/update-state.sh。';
const ANALYSIS_FAILURE_REASON = 'Bash gate 无法完成命令分析：bash-traverse 解析失败。';

const SHELL_WRAPPERS = new Set(['bash', 'sh', 'zsh']);
const INLINE_INTERPRETER_FLAGS = new Map([
  ['python', '-c'],
  ['python3', '-c'],
  ['node', '-e'],
  ['ruby', '-e'],
  ['perl', '-e'],
]);

function deny(reason) {
  return JSON.stringify({
    hookSpecificOutput: {
      hookEventName: 'PreToolUse',
      permissionDecision: 'deny',
      permissionDecisionReason: reason,
    },
  });
}

function getRuntime() {
  const runtimePath = path.join(__dirname, '..', 'vendor', 'bash-traverse', 'dist', 'index.js');
  return require(runtimePath);
}

function getTokenText(node) {
  if (!node || typeof node !== 'object') {
    return '';
  }

  if (typeof node.text === 'string') {
    return node.text;
  }

  if (typeof node.name?.text === 'string') {
    return node.name.text;
  }

  if (typeof node.argument?.text === 'string') {
    return node.argument.text;
  }

  if (typeof node.operator?.text === 'string') {
    return node.operator.text;
  }

  return '';
}

function getNodeOffsets(node) {
  const startOffset = node?.loc?.start?.offset;
  const endOffset = node?.loc?.end?.offset;

  return {
    startOffset: Number.isInteger(startOffset) ? startOffset : null,
    endOffset: Number.isInteger(endOffset) ? endOffset : null,
  };
}

function normalizeShellFragment(text) {
  if (typeof text !== 'string' || text === '') {
    return '';
  }

  let normalized = text;
  normalized = normalized.replace(/^(['"])(.*)\1$/s, '$2');
  normalized = normalized.replace(/\\(.)/gs, '$1');
  normalized = normalized.replace(/[\\'"]/g, '');
  return normalized;
}

function reconstructNormalizedWords(nodes) {
  const words = [];
  let currentWord = '';
  let previousEndOffset = null;

  const flushCurrentWord = () => {
    if (currentWord !== '') {
      words.push(currentWord);
      currentWord = '';
    }
    previousEndOffset = null;
  };

  for (const node of nodes || []) {
    const rawText = getTokenText(node);
    const normalizedText = normalizeShellFragment(rawText);
    const { startOffset, endOffset } = getNodeOffsets(node);
    const isSpaceToken = rawText.trim() === '' && rawText !== '';
    const isAdjacent = (
      currentWord !== '' &&
      previousEndOffset !== null &&
      startOffset !== null &&
      previousEndOffset === startOffset
    );

    if (isSpaceToken) {
      flushCurrentWord();
      continue;
    }

    if (currentWord !== '' && !isAdjacent) {
      flushCurrentWord();
    }

    currentWord += normalizedText;
    previousEndOffset = endOffset;
  }

  flushCurrentWord();
  return words;
}

function hasTargetPath(text) {
  return typeof text === 'string' && text.includes(TARGET_PATH);
}

function normalizeInlineInterpreterSource(text) {
  if (typeof text !== 'string' || text === '') {
    return '';
  }

  let normalized = text;
  normalized = normalized.replace(/%q\{([^}]*)\}/g, '$1');
  normalized = normalized.replace(/\\(.)/gs, '$1');
  normalized = normalized.replace(/["']/g, '');
  normalized = normalized.replace(/\s*\+\s*/g, '');
  normalized = normalized.replace(/\s+/g, '');
  return normalized;
}

function getCommandName(commandNode) {
  return normalizeShellFragment(getTokenText(commandNode.name)).trim();
}

function getCommandWords(commandNode) {
  return reconstructNormalizedWords(commandNode.arguments || []).filter((word) => word !== '');
}

function getFlagValue(words, acceptedFlags) {
  for (let index = 0; index < words.length; index += 1) {
    const text = words[index].trim();
    if (acceptedFlags.has(text) && words[index + 1]) {
      return words[index + 1];
    }
  }

  return '';
}

function analyzeCommandNode(commandNode, analyzeShellSource) {
  const commandName = getCommandName(commandNode);
  const commandWords = getCommandWords(commandNode);

  if (SHELL_WRAPPERS.has(commandName)) {
    const nestedShellSource = getFlagValue(commandWords, new Set(['-c', '-lc']));
    if (nestedShellSource && analyzeShellSource(nestedShellSource)) {
      return true;
    }
  }

  if (INLINE_INTERPRETER_FLAGS.has(commandName)) {
    const codeFlag = INLINE_INTERPRETER_FLAGS.get(commandName);
    const inlineSource = normalizeInlineInterpreterSource(getFlagValue(commandWords, new Set([codeFlag])));
    if (hasTargetPath(inlineSource)) {
      return true;
    }
  }

  if (hasTargetPath(commandName)) {
    return true;
  }

  return commandWords.some((word) => hasTargetPath(word));
}

function analyzeTestExpressionNode(testExpressionNode) {
  const expressionWords = reconstructNormalizedWords(
    (testExpressionNode.elements || []).map((elementNode) => elementNode.argument || elementNode.operator)
  );

  return expressionWords.some((word) => hasTargetPath(word));
}

function createShellAnalyzer(parse, traverse) {
  return function analyzeShellSource(source) {
    let ast;

    try {
      ast = parse(source);
    } catch (error) {
      return false;
    }

    let shouldDeny = false;

    traverse(ast, {
      Command(commandPath) {
        if (shouldDeny) {
          return;
        }

        if (analyzeCommandNode(commandPath.node, analyzeShellSource)) {
          shouldDeny = true;
        }
      },
      TestExpression(testExpressionPath) {
        if (shouldDeny) {
          return;
        }

        if (analyzeTestExpressionNode(testExpressionPath.node)) {
          shouldDeny = true;
        }
      },
    });

    return shouldDeny;
  };
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

  const { parse, traverse } = getRuntime();
  const analyzeShellSource = createShellAnalyzer(parse, traverse);
  if (analyzeShellSource(command)) {
    process.stdout.write(deny(DENY_REASON));
  }
}

try {
  main();
} catch (error) {
  process.stdout.write(deny(ANALYSIS_FAILURE_REASON));
}

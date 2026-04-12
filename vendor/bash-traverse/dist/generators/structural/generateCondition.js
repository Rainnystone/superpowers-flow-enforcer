"use strict";
/**
 * Condition-related structural generators
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateConditionStart = generateConditionStart;
exports.generateConditionEnd = generateConditionEnd;
exports.generateIfKeyword = generateIfKeyword;
exports.generateElifKeyword = generateElifKeyword;
exports.generateElseKeyword = generateElseKeyword;
function generateConditionStart() {
    return 'then';
}
function generateConditionEnd() {
    return 'fi';
}
function generateIfKeyword() {
    return 'if';
}
function generateElifKeyword() {
    return 'elif';
}
function generateElseKeyword() {
    return 'else';
}
//# sourceMappingURL=generateCondition.js.map
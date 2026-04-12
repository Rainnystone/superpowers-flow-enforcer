"use strict";
/**
 * Loop-related structural generators
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateLoopStart = generateLoopStart;
exports.generateLoopEnd = generateLoopEnd;
exports.generateWhileKeyword = generateWhileKeyword;
exports.generateUntilKeyword = generateUntilKeyword;
exports.generateForKeyword = generateForKeyword;
exports.generateInKeyword = generateInKeyword;
function generateLoopStart() {
    return 'do';
}
function generateLoopEnd() {
    return 'done';
}
function generateWhileKeyword() {
    return 'while';
}
function generateUntilKeyword() {
    return 'until';
}
function generateForKeyword() {
    return 'for';
}
function generateInKeyword() {
    return 'in';
}
//# sourceMappingURL=generateLoop.js.map
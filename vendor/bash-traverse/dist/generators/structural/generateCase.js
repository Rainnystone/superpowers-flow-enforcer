"use strict";
/**
 * Case-related structural generators
 * Case statements commonly need explicit spacing: "case $1 in"
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateCaseStart = generateCaseStart;
exports.generateCaseEnd = generateCaseEnd;
exports.generateCaseIn = generateCaseIn;
exports.generateClauseEnd = generateClauseEnd;
function generateCaseStart() {
    return 'case';
}
function generateCaseEnd(esacIndentation) {
    const indent = esacIndentation || '';
    return '\n' + indent + 'esac';
}
function generateCaseIn() {
    return ' in';
}
function generateClauseEnd() {
    return ';;';
}
//# sourceMappingURL=generateCase.js.map
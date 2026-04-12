"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateForStatement = generateForStatement;
const index_1 = require("../index");
/**
 * For statement generator
 * For loops always need explicit spacing: "for i in 1 2 3; do"
 */
function generateForStatement(forStatement) {
    let result = '';
    // for keyword
    result += 'for';
    // variable (always needs space after 'for')
    result += ' ' + (0, index_1.generateNode)(forStatement.variable);
    // in keyword (always needs space before and after)
    result += ' in';
    // word list (spaces between words)
    if (forStatement.wordlist && forStatement.wordlist.length > 0) {
        for (let i = 0; i < forStatement.wordlist.length; i++) {
            const word = forStatement.wordlist[i];
            if (word) {
                result += ' ' + (0, index_1.generateNode)(word);
            }
        }
    }
    // semicolon after wordlist (if present)
    if (forStatement.semicolonAfterWordlist) {
        result += ';';
    }
    // do keyword (always needs space before)
    result += ' do';
    // body - each statement generates itself with its own spacing
    for (const statement of forStatement.body) {
        result += (0, index_1.generateNode)(statement);
    }
    // done keyword
    result += 'done';
    return result;
}
//# sourceMappingURL=generateFor.js.map
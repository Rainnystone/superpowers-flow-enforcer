"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateWhileStatement = generateWhileStatement;
const index_1 = require("../index");
/**
 * While statement generator
 * Pure AST-driven generation - minimal spacing for structural parts
 */
function generateWhileStatement(whileStatement) {
    let result = '';
    // while keyword
    result += 'while';
    // condition
    result += ' ' + (0, index_1.generateNode)(whileStatement.condition);
    // semicolon after condition (if present)
    if (whileStatement.semicolonAfterCondition) {
        result += (0, index_1.generateNode)(whileStatement.semicolonAfterCondition);
    }
    // do
    result += ' do';
    // body - each statement generates itself with its own spacing
    for (const statement of whileStatement.body) {
        result += (0, index_1.generateNode)(statement);
    }
    // done
    result += 'done';
    return result;
}
//# sourceMappingURL=generateWhile.js.map
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateUntilStatement = generateUntilStatement;
const index_1 = require("../index");
/**
 * Until statement generator
 * Pure AST-driven generation - minimal spacing for structural parts
 */
function generateUntilStatement(untilStatement) {
    let result = '';
    // until keyword
    result += 'until';
    // condition
    result += (0, index_1.generateNode)(untilStatement.condition);
    // do
    result += 'do';
    // body - each statement generates itself with its own spacing
    for (const statement of untilStatement.body) {
        result += (0, index_1.generateNode)(statement);
    }
    // done
    result += 'done';
    return result;
}
//# sourceMappingURL=generateUntil.js.map
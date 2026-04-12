"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateIfStatement = generateIfStatement;
const index_1 = require("../index");
/**
 * If statement generator
 * If statements commonly need explicit spacing: "if [condition]; then"
 */
function generateIfStatement(ifStatement) {
    let result = '';
    // if keyword
    result += 'if';
    // condition (commonly needs space after 'if')
    result += ' ' + (0, index_1.generateNode)(ifStatement.condition);
    // semicolon after condition (if present)
    if (ifStatement['semicolonAfterCondition']) {
        result += (0, index_1.generateNode)(ifStatement['semicolonAfterCondition']);
    }
    // then keyword (commonly needs space before)
    result += ' then';
    // then body - each statement generates itself with its own spacing
    for (const statement of ifStatement.thenBody) {
        result += (0, index_1.generateNode)(statement);
    }
    // elif clauses
    for (const elifClause of ifStatement.elifClauses) {
        result += ' elif';
        result += ' ' + (0, index_1.generateNode)(elifClause.condition);
        // semicolon after elif condition (if present)
        if (elifClause.semicolonAfterCondition) {
            result += (0, index_1.generateNode)(elifClause.semicolonAfterCondition);
        }
        result += ' then';
        for (const statement of elifClause.body) {
            result += (0, index_1.generateNode)(statement);
        }
    }
    // else clause - no explicit space addition, let AST handle spacing
    if (ifStatement.elseBody) {
        result += 'else'; // Let the AST Space nodes handle spacing
        for (const statement of ifStatement.elseBody) {
            result += (0, index_1.generateNode)(statement);
        }
    }
    // fi keyword
    result += 'fi';
    return result;
}
//# sourceMappingURL=generateIf.js.map
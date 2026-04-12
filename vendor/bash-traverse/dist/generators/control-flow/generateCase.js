"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateCaseStatement = generateCaseStatement;
exports.generateCaseClause = generateCaseClause;
const index_1 = require("../index");
const structural_1 = require("../structural");
/**
 * Case statement generator
 * Case statements commonly need explicit spacing: "case $1 in"
 */
function generateCaseStatement(caseStatement) {
    let result = '';
    // case keyword
    result += (0, structural_1.generateCaseStart)();
    // expression (commonly needs space after 'case')
    result += ' ' + (0, index_1.generateNode)(caseStatement.expression);
    // in
    result += (0, structural_1.generateCaseIn)();
    // Add newlines after 'in' if they exist
    if (caseStatement.newlinesAfterIn) {
        for (const newline of caseStatement.newlinesAfterIn) {
            result += (0, index_1.generateNode)(newline);
        }
    }
    // clauses
    for (let i = 0; i < caseStatement.clauses.length; i++) {
        const clause = caseStatement.clauses[i];
        if (clause) {
            const clauseStr = generateCaseClause(clause);
            if (clauseStr) {
                result += clauseStr;
                // Add newline between clauses (but not after the last one)
                if (i < caseStatement.clauses.length - 1) {
                    result += '\n';
                }
            }
        }
    }
    // esac
    result += (0, structural_1.generateCaseEnd)(caseStatement.esacIndentation);
    return result;
}
/**
 * Case clause generator
 * Case clauses commonly need explicit spacing: "    start)"
 */
function generateCaseClause(caseClause) {
    let result = '';
    // Add indentation before patterns
    if (caseClause.indentation) {
        result += caseClause.indentation;
    }
    // patterns - join without spaces and add ) directly
    for (const pattern of caseClause.patterns) {
        result += (0, index_1.generateNode)(pattern);
    }
    result += ')';
    // statements
    if (caseClause.statements.length > 0) {
        for (let i = 0; i < caseClause.statements.length; i++) {
            const statement = caseClause.statements[i];
            if (!statement)
                continue;
            // Output all statements, including DoubleSemicolon
            const generated = (0, index_1.generateNode)(statement);
            if (generated) {
                result += generated;
            }
        }
    }
    // Do NOT add ;; manually here
    // result += generateClauseEnd();
    return result;
}
//# sourceMappingURL=generateCase.js.map
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateLoopBody = generateLoopBody;
const index_1 = require("../index");
// StatementArrayContext no longer needed
/**
 * Loop body generator
 * Handles while/until/for statement bodies
 */
function generateLoopBody(statements) {
    if (statements.length === 0) {
        return '';
    }
    const parts = [];
    for (let i = 0; i < statements.length; i++) {
        const statement = statements[i];
        if (!statement)
            continue;
        const generated = (0, index_1.generateNode)(statement);
        if (!generated)
            continue;
        // Handle semicolon statements specially
        if (statement.type === 'Semicolon') {
            parts.push(generated);
            continue;
        }
        // Handle newline statements specially
        if (statement.type === 'Newline') {
            parts.push('\n');
            continue;
        }
        // Only add semicolons if they were present in the original source
        // Don't automatically add them based on context
        parts.push(generated);
    }
    // Join without adding extra spaces (body parts already contain Space tokens)
    return parts.join('');
}
//# sourceMappingURL=generateLoopBody.js.map
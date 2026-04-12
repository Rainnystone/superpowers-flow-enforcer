"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateProgram = generateProgram;
const generateNode_1 = require("./generateNode");
/**
 * Program generator
 * Generates the complete program from the AST root
 */
function generateProgram(program) {
    let result = '';
    // Generate each statement directly (no array joining to preserve exact formatting)
    for (const statement of program.body) {
        result += (0, generateNode_1.generateNode)(statement);
    }
    return result;
}
//# sourceMappingURL=generateProgram.js.map
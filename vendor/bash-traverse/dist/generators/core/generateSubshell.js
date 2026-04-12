"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateSubshell = generateSubshell;
const statements_1 = require("../statements");
/**
 * Subshell generator
 * Handles subshell generation with parentheses
 */
function generateSubshell(subshell) {
    const body = (0, statements_1.generateBlockBody)(subshell.body);
    return `(${body})`;
}
//# sourceMappingURL=generateSubshell.js.map
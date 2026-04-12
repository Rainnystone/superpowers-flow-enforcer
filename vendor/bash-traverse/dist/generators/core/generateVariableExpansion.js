"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateVariableExpansion = generateVariableExpansion;
const generateNode_1 = require("./generateNode");
/**
 * VariableExpansion generator
 * Handles variable expansion generation with modifiers
 */
function generateVariableExpansion(expansion) {
    let result = `$${(0, generateNode_1.generateNode)(expansion.name)}`;
    if (expansion.modifier) {
        result += (0, generateNode_1.generateNode)(expansion.modifier);
    }
    return result;
}
//# sourceMappingURL=generateVariableExpansion.js.map
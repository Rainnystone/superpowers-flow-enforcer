"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateBraceGroup = generateBraceGroup;
const statements_1 = require("../statements");
const structural_1 = require("../structural");
/**
 * BraceGroup generator
 * Handles brace group generation with proper spacing
 */
function generateBraceGroup(braceGroup) {
    let result = '';
    result += (0, structural_1.generateBlockStart)();
    const body = (0, statements_1.generateBlockBody)(braceGroup.body);
    if (body) {
        result += body;
    }
    result += (0, structural_1.generateBlockEnd)();
    return result;
}
//# sourceMappingURL=generateBraceGroup.js.map
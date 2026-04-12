"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateFunctionDefinition = generateFunctionDefinition;
const generateNode_1 = require("./generateNode");
const statements_1 = require("../statements");
const structural_1 = require("../structural");
/**
 * FunctionDefinition generator
 * Handles function definition generation with proper spacing
 */
function generateFunctionDefinition(functionDef) {
    let result = '';
    result += (0, structural_1.generateFunctionKeyword)();
    // Emit spaces between 'function' and the function name
    if (functionDef['spaces'] && Array.isArray(functionDef['spaces'])) {
        for (const space of functionDef['spaces']) {
            result += (0, generateNode_1.generateNode)(space);
        }
    }
    result += (0, generateNode_1.generateNode)(functionDef.name);
    if (functionDef.hasParentheses) {
        result += '()';
    }
    result += ' ' + (0, structural_1.generateBlockStart)();
    const body = (0, statements_1.generateBlockBody)(functionDef.body);
    if (body) {
        result += body;
    }
    result += (0, structural_1.generateBlockEnd)();
    return result;
}
//# sourceMappingURL=generateFunctionDefinition.js.map
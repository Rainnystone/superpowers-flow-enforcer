"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateArrayAssignment = generateArrayAssignment;
const generateNode_1 = require("./generateNode");
/**
 * ArrayAssignment generator
 * Handles array assignment generation
 */
function generateArrayAssignment(arrayAssignment) {
    let result = '';
    result += (0, generateNode_1.generateNode)(arrayAssignment.name);
    result += '=(';
    for (const element of arrayAssignment.elements) {
        result += (0, generateNode_1.generateNode)(element);
    }
    result += ')';
    return result;
}
//# sourceMappingURL=generateArrayAssignment.js.map
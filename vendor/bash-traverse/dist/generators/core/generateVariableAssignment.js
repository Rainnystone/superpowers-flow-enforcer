"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateVariableAssignment = generateVariableAssignment;
const generateNode_1 = require("./generateNode");
/**
 * VariableAssignment generator
 * Handles variable assignment generation
 */
function generateVariableAssignment(assignment) {
    return `${(0, generateNode_1.generateNode)(assignment.name)}=${(0, generateNode_1.generateNode)(assignment.value)}`;
}
//# sourceMappingURL=generateVariableAssignment.js.map
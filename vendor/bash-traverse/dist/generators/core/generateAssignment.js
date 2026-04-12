"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateAssignment = generateAssignment;
const generateNode_1 = require("./generateNode");
/**
 * Assignment generator
 * Handles basic assignment generation
 */
function generateAssignment(assignment) {
    return `${(0, generateNode_1.generateNode)(assignment.name)}=${(0, generateNode_1.generateNode)(assignment.value)}`;
}
//# sourceMappingURL=generateAssignment.js.map
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateArrayElement = generateArrayElement;
const generateNode_1 = require("./generateNode");
/**
 * ArrayElement generator
 * Handles array element generation with optional index
 */
function generateArrayElement(element) {
    if (element.index) {
        return `[${(0, generateNode_1.generateNode)(element.index)}]=${(0, generateNode_1.generateNode)(element.value)}`;
    }
    else {
        return (0, generateNode_1.generateNode)(element.value);
    }
}
//# sourceMappingURL=generateArrayElement.js.map
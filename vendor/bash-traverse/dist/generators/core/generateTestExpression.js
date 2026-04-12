"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateTestExpression = generateTestExpression;
const generateNode_1 = require("./generateNode");
/**
 * TestExpression generator
 * Test expressions commonly need explicit spacing: "[ -f file.txt ]"
 */
function generateTestExpression(node) {
    // Use double brackets for extended test expressions, single brackets for POSIX
    const brackets = node.extended ? '[[' : '[';
    const closeBrackets = node.extended ? ']]' : ']';
    let result = brackets;
    // Generate elements in the order they appear
    for (let i = 0; i < node.elements.length; i++) {
        const element = node.elements[i];
        if (element && element.isOperator && element.operator) {
            result += ' ' + (0, generateNode_1.generateNode)(element.operator);
        }
        else if (element && !element.isOperator && element.argument) {
            result += ' ' + (0, generateNode_1.generateNode)(element.argument);
        }
    }
    result += ' ' + closeBrackets;
    return result;
}
//# sourceMappingURL=generateTestExpression.js.map
"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generatePipeline = generatePipeline;
const generateNode_1 = require("./generateNode");
/**
 * Pipeline generator
 * Handles pipeline generation with operators
 */
function generatePipeline(pipeline) {
    let result = '';
    for (let i = 0; i < pipeline.commands.length; i++) {
        if (i > 0) {
            const operator = pipeline.operators && pipeline.operators[i - 1] ? pipeline.operators[i - 1] : '|';
            // Add preserved spaces before operator if available
            if (pipeline.spacesBeforeOperators && pipeline.spacesBeforeOperators[i - 1]) {
                const spaces = pipeline.spacesBeforeOperators[i - 1];
                if (spaces) {
                    for (const spaceToken of spaces) {
                        result += spaceToken.value;
                    }
                }
            }
            result += (operator || '|') + ' ';
        }
        const command = pipeline.commands[i];
        if (command) {
            result += (0, generateNode_1.generateNode)(command);
        }
    }
    if (pipeline.negated) {
        result = '!' + result;
    }
    return result;
}
//# sourceMappingURL=generatePipeline.js.map
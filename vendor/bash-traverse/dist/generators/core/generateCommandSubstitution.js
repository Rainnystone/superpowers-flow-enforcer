"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateCommandSubstitution = generateCommandSubstitution;
const statements_1 = require("../statements");
/**
 * CommandSubstitution generator
 * Handles command substitution with different styles
 */
function generateCommandSubstitution(substitution) {
    const command = (0, statements_1.generateBlockBody)(substitution.command);
    if (substitution.style === '$()') {
        return `$(${command})`;
    }
    else {
        return `\`${command}\``;
    }
}
//# sourceMappingURL=generateCommandSubstitution.js.map
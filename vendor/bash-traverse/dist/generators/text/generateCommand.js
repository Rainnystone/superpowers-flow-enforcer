"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateCommand = generateCommand;
const index_1 = require("../index");
const generateHereDocument_1 = require("./generateHereDocument");
/**
 * Command generator
 * Handles command generation with proper spacing preservation
 */
function generateCommand(command) {
    const parts = [];
    // Variable assignment prefixes (e.g., NODE_ENV=production)
    if (command.prefixStatements && command.prefixStatements.length > 0) {
        for (const prefixStatement of command.prefixStatements) {
            parts.push((0, index_1.generateNode)(prefixStatement));
        }
    }
    // Command name
    parts.push((0, index_1.generateNode)(command.name));
    // Arguments
    for (const arg of command.arguments) {
        parts.push((0, index_1.generateNode)(arg));
    }
    // Redirects
    if (command.redirects && Array.isArray(command.redirects)) {
        for (const redirect of command.redirects) {
            parts.push((0, index_1.generateNode)(redirect));
        }
    }
    // Concatenate parts with proper spacing
    let result = '';
    for (let i = 0; i < parts.length; i++) {
        result += parts[i];
        // Add preserved spaces between prefix statements and command name
        if (i === 0 && command.prefixStatements && command.prefixStatements.length > 0) {
            // Use preserved spaces if available, otherwise add a single space
            if (command.name['spacesAfterPrefix'] && command.name['spacesAfterPrefix'].length > 0) {
                for (const spaceToken of command.name['spacesAfterPrefix']) {
                    result += spaceToken.value;
                }
            }
            else {
                result += ' ';
            }
        }
    }
    // Generate heredoc (no extra space needed)
    if (command.hereDocument) {
        result += (0, generateHereDocument_1.generateHereDocument)(command.hereDocument);
    }
    return result;
}
//# sourceMappingURL=generateCommand.js.map
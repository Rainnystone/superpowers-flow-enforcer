"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateHereDocument = generateHereDocument;
const index_1 = require("../index");
/**
 * HereDocument generator
 * Handles heredoc generation with proper newline handling
 */
function generateHereDocument(hereDoc) {
    let result = '<< ';
    if (hereDoc.stripTabs) {
        result += '-';
    }
    result += (0, index_1.generateNode)(hereDoc.delimiter);
    // Add content directly since it already includes the proper newlines
    result += hereDoc.content;
    result += (0, index_1.generateNode)(hereDoc.delimiter);
    return result;
}
//# sourceMappingURL=generateHereDocument.js.map
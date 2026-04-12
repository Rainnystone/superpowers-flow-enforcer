"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateWord = generateWord;
/**
 * Word generator
 * Handles quoted and unquoted words
 */
function generateWord(word) {
    // If the word was originally quoted, preserve the quotes
    if (word.quoted) {
        const quote = word.quoteType || '"';
        return `${quote}${word.text}${quote}`;
    }
    // If the word was not quoted, return as-is
    return word.text;
}
//# sourceMappingURL=generateWord.js.map
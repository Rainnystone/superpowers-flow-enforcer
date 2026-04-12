"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateComment = generateComment;
const config_1 = require("../config");
/**
 * Comment generator
 * Handles comment generation with configurable options
 */
function generateComment(comment) {
    const config = (0, config_1.getConfig)();
    if (!config.comments) {
        return '';
    }
    return comment.value;
}
//# sourceMappingURL=generateComment.js.map
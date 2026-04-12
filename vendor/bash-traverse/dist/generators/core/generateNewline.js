"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateNewline = generateNewline;
const config_1 = require("../config");
/**
 * Newline generator
 * Handles newline generation with configurable line terminators
 */
function generateNewline(_newline) {
    const config = (0, config_1.getConfig)();
    return config.lineTerminator;
}
//# sourceMappingURL=generateNewline.js.map
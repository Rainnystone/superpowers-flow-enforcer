"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateRedirect = generateRedirect;
const generateNode_1 = require("./generateNode");
/**
 * Redirect generator
 * Handles redirection generation with file descriptors
 */
function generateRedirect(redirect) {
    let result = '';
    if (redirect.fd !== undefined && redirect.fd !== 1) {
        result += `${redirect.fd}`;
    }
    result += redirect.operator;
    result += (0, generateNode_1.generateNode)(redirect.target);
    return result;
}
//# sourceMappingURL=generateRedirect.js.map
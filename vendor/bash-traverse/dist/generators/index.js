"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __exportStar = (this && this.__exportStar) || function(m, exports) {
    for (var p in m) if (p !== "default" && !Object.prototype.hasOwnProperty.call(exports, p)) __createBinding(exports, m, p);
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.generate = generate;
const core_1 = require("./core");
const config_1 = require("./config");
/**
 * Main generator function
 * Entry point for code generation
 */
function generate(ast, options) {
    // Initialize global config
    (0, config_1.initConfig)(options);
    // Generate the program
    return (0, core_1.generateNode)(ast);
}
// Re-export all generators
__exportStar(require("./core"), exports);
__exportStar(require("./text"), exports);
__exportStar(require("./structural"), exports);
__exportStar(require("./statements"), exports);
__exportStar(require("./control-flow"), exports);
__exportStar(require("./config"), exports);
//# sourceMappingURL=index.js.map
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
__exportStar(require("./generateNode"), exports);
__exportStar(require("./generateProgram"), exports);
__exportStar(require("./generateComment"), exports);
__exportStar(require("./generateShebang"), exports);
__exportStar(require("./generateNewline"), exports);
__exportStar(require("./generateSemicolon"), exports);
__exportStar(require("./generatePipeline"), exports);
__exportStar(require("./generateSubshell"), exports);
__exportStar(require("./generateBraceGroup"), exports);
__exportStar(require("./generateRedirect"), exports);
__exportStar(require("./generateVariableExpansion"), exports);
__exportStar(require("./generateCommandSubstitution"), exports);
__exportStar(require("./generateArithmeticExpansion"), exports);
__exportStar(require("./generateAssignment"), exports);
__exportStar(require("./generateVariableAssignment"), exports);
__exportStar(require("./generateArrayAssignment"), exports);
__exportStar(require("./generateArrayElement"), exports);
__exportStar(require("./generateTestExpression"), exports);
__exportStar(require("./generateFunctionDefinition"), exports);
__exportStar(require("./generateLineContinuation"), exports);
__exportStar(require("./generateContinuationMarker"), exports);
//# sourceMappingURL=index.js.map
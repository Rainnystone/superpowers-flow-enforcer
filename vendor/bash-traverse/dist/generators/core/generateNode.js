"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateNode = generateNode;
const generateProgram_1 = require("./generateProgram");
const generateCommand_1 = require("../text/generateCommand");
const generateWord_1 = require("../text/generateWord");
const generateComment_1 = require("./generateComment");
const generateShebang_1 = require("./generateShebang");
const generateNewline_1 = require("./generateNewline");
const generateSemicolon_1 = require("./generateSemicolon");
const generateSpace_1 = require("../text/generateSpace");
const generatePipeline_1 = require("./generatePipeline");
const generateSubshell_1 = require("./generateSubshell");
const generateBraceGroup_1 = require("./generateBraceGroup");
const generateRedirect_1 = require("./generateRedirect");
const generateVariableExpansion_1 = require("./generateVariableExpansion");
const generateCommandSubstitution_1 = require("./generateCommandSubstitution");
const generateArithmeticExpansion_1 = require("./generateArithmeticExpansion");
const generateAssignment_1 = require("./generateAssignment");
const generateVariableAssignment_1 = require("./generateVariableAssignment");
const generateArrayAssignment_1 = require("./generateArrayAssignment");
const generateArrayElement_1 = require("./generateArrayElement");
const generateHereDocument_1 = require("../text/generateHereDocument");
const generateTestExpression_1 = require("./generateTestExpression");
const generateFunctionDefinition_1 = require("./generateFunctionDefinition");
const generateLineContinuation_1 = require("./generateLineContinuation");
const generateContinuationMarker_1 = require("./generateContinuationMarker");
const control_flow_1 = require("../control-flow");
/**
 * Main node generator dispatcher
 * Routes to appropriate generator based on node type
 */
function generateNode(node) {
    switch (node.type) {
        case 'Program':
            return (0, generateProgram_1.generateProgram)(node);
        case 'Command':
            return (0, generateCommand_1.generateCommand)(node);
        case 'Word':
            return (0, generateWord_1.generateWord)(node);
        case 'Comment':
            return (0, generateComment_1.generateComment)(node);
        case 'Shebang':
            return (0, generateShebang_1.generateShebang)(node);
        case 'Newline':
            return (0, generateNewline_1.generateNewline)(node);
        case 'Semicolon':
            return (0, generateSemicolon_1.generateSemicolon)(node);
        case 'DoubleSemicolon':
            return ';;'; // This represents CLAUSE_END in the AST
        case 'Space':
            return (0, generateSpace_1.generateSpace)(node);
        case 'SpaceStatement':
            return (0, generateSpace_1.generateSpace)(node);
        case 'Pipeline':
            return (0, generatePipeline_1.generatePipeline)(node);
        case 'Subshell':
            return (0, generateSubshell_1.generateSubshell)(node);
        case 'BraceGroup':
            return (0, generateBraceGroup_1.generateBraceGroup)(node);
        case 'FunctionDefinition':
            return (0, generateFunctionDefinition_1.generateFunctionDefinition)(node);
        case 'Redirect':
            return (0, generateRedirect_1.generateRedirect)(node);
        case 'VariableExpansion':
            return (0, generateVariableExpansion_1.generateVariableExpansion)(node);
        case 'CommandSubstitution':
            return (0, generateCommandSubstitution_1.generateCommandSubstitution)(node);
        case 'ArithmeticExpansion':
            return (0, generateArithmeticExpansion_1.generateArithmeticExpansion)(node);
        case 'Assignment':
            return (0, generateAssignment_1.generateAssignment)(node);
        case 'VariableAssignment':
            return (0, generateVariableAssignment_1.generateVariableAssignment)(node);
        case 'ArrayAssignment':
            return (0, generateArrayAssignment_1.generateArrayAssignment)(node);
        case 'ArrayElement':
            return (0, generateArrayElement_1.generateArrayElement)(node);
        case 'HereDocument':
            return (0, generateHereDocument_1.generateHereDocument)(node);
        case 'TestExpression':
            return (0, generateTestExpression_1.generateTestExpression)(node);
        case 'IfStatement':
            return (0, control_flow_1.generateIfStatement)(node);
        case 'ForStatement':
            return (0, control_flow_1.generateForStatement)(node);
        case 'WhileStatement':
            return (0, control_flow_1.generateWhileStatement)(node);
        case 'UntilStatement':
            return (0, control_flow_1.generateUntilStatement)(node);
        case 'CaseStatement':
            return (0, control_flow_1.generateCaseStatement)(node);
        case 'CaseClause':
            return (0, control_flow_1.generateCaseClause)(node);
        case 'LineContinuation':
            return (0, generateLineContinuation_1.generateLineContinuation)(node);
        case 'ContinuationMarker':
            return (0, generateContinuationMarker_1.generateContinuationMarker)(node);
        default:
            throw new Error(`Unknown node type: ${node.type}`);
    }
}
//# sourceMappingURL=generateNode.js.map
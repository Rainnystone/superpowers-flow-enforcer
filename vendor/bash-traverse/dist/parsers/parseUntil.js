"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.parseUntilStatement = parseUntilStatement;
/**
 * Until statement parser
 * Handles until/do/done structures
 */
function parseUntilStatement(parser) {
    // 'until' keyword already consumed by parseStatement dispatch
    // Parse the condition - can be either a test expression [ ... ] or a command/word
    let condition;
    const token = parser.peek();
    if (token && token.type === 'LBRACKET') {
        // It's a test expression [ ... ]
        condition = parser.parsePosixTestExpression();
    }
    else {
        // It's a command or word (like 'true', 'command', etc.)
        condition = parser.parseCommand();
    }
    parser.consume('LOOP_START', 'Expected do');
    // Parse the body (everything up to 'done')
    const body = [];
    while (!parser.isAtEnd()) {
        const token = parser.peek();
        if (!token)
            break;
        // Stop if we encounter 'done'
        if (token.type === 'LOOP_END') {
            break;
        }
        const statement = parser.parseStatement();
        if (statement) {
            body.push(statement);
        }
    }
    parser.consume('LOOP_END', 'Expected done');
    const loc = parser.createLocation(condition.loc, parser.peek(-1)?.loc);
    return {
        type: 'UntilStatement',
        condition: condition,
        body: body,
        ...(loc && { loc })
    };
}
//# sourceMappingURL=parseUntil.js.map
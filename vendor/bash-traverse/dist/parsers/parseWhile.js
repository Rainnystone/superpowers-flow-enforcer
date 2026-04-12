"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.parseWhileStatement = parseWhileStatement;
/**
 * While statement parser
 * Handles while/do/done structures
 */
function parseWhileStatement(parser) {
    // 'while' keyword already consumed by parseStatement dispatch
    // Skip SPACE tokens
    while (parser.match('SPACE')) {
        parser.advance();
    }
    // Parse the condition - can be either a test expression [ ... ] or a command/word
    let condition;
    const token = parser.peek();
    if (token && token.type === 'TEST_START') {
        // It's a test expression [ ... ]
        condition = parser.parsePosixTestExpression();
    }
    else {
        // It's a command or word (like 'true', 'command', etc.)
        condition = parser.parseCommand();
    }
    // Skip SPACE tokens before potential semicolon
    while (parser.match('SPACE')) {
        parser.advance();
    }
    // Handle optional semicolon between condition and 'do'
    let semicolonAfterCondition = undefined;
    if (parser.match('SEMICOLON')) {
        const semicolonToken = parser.advance(); // consume semicolon
        if (semicolonToken) {
            semicolonAfterCondition = {
                type: 'Semicolon',
                loc: semicolonToken.loc
            };
        }
    }
    // Skip SPACE tokens before 'do'
    while (parser.match('SPACE')) {
        parser.advance();
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
        // Handle semicolons specially - add them to the body
        if (token.type === 'SEMICOLON') {
            parser.advance(); // consume semicolon
            const semicolonStatement = {
                type: 'Semicolon',
                loc: token.loc
            };
            body.push(semicolonStatement);
            continue;
        }
        const statement = parser.parseStatement();
        if (statement) {
            body.push(statement);
        }
    }
    parser.consume('LOOP_END', 'Expected done');
    const loc = parser.createLocation(condition.loc, body[body.length - 1]?.loc);
    return {
        type: 'WhileStatement',
        condition: condition,
        semicolonAfterCondition,
        body: body,
        ...(loc && { loc })
    };
}
//# sourceMappingURL=parseWhile.js.map
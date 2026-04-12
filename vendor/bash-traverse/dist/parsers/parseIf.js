"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.parseIfStatement = parseIfStatement;
/**
 * If statement parser
 * Handles if/elif/else/fi structures
 */
function parseIfStatement(parser) {
    // 'if' keyword already consumed by parseStatement dispatch
    // Skip SPACE tokens
    while (parser.match('SPACE')) {
        parser.advance();
    }
    // Parse the condition (test expression)
    // Check if it's a POSIX test [ ... ] or extended test [[ ... ]]
    const nextToken = parser.peek();
    let condition;
    if (nextToken?.type === 'TEST_START') {
        condition = parser.parsePosixTestExpression();
    }
    else if (nextToken?.type === 'EXTENDED_TEST_START') {
        condition = parser.parseExtendedTestExpression();
    }
    else {
        // Fallback to POSIX test for backward compatibility
        condition = parser.parsePosixTestExpression();
    }
    // Consume semicolon if present after condition
    if (parser.peek()?.type === 'SEMICOLON') {
        const semicolonToken = parser.advance();
        const semicolonAfterCondition = {
            type: 'Semicolon',
            loc: semicolonToken?.loc
        };
        // Store the semicolon for later use in generation
        parser.semicolonAfterCondition = semicolonAfterCondition;
    }
    // Skip SPACE tokens before 'then'
    while (parser.match('SPACE')) {
        parser.advance();
    }
    parser.consume('CONDITION_START', 'Expected then');
    // Parse the then body (everything up to 'fi' or 'elif' or 'else')
    const thenCommands = [];
    while (!parser.isAtEnd()) {
        const token = parser.peek();
        if (!token)
            break;
        // Stop if we encounter keywords that end the if statement
        if (token.type === 'CONDITION_END' || token.type === 'CONTROL_ELIF' || token.type === 'CONTROL_ELSE') {
            break;
        }
        // Handle semicolons specially - add them to the body
        if (token.type === 'SEMICOLON') {
            parser.advance(); // consume semicolon
            const semicolonStatement = {
                type: 'Semicolon',
                loc: token.loc
            };
            thenCommands.push(semicolonStatement);
            continue;
        }
        const statement = parser.parseStatement();
        if (statement) {
            thenCommands.push(statement);
        }
    }
    // Parse elif clauses
    const elifClauses = [];
    while (parser.match('CONTROL_ELIF')) {
        parser.advance(); // consume 'elif'
        // Skip SPACE tokens
        while (parser.match('SPACE')) {
            parser.advance();
        }
        // Parse elif condition (same logic as if condition)
        const elifNextToken = parser.peek();
        let elifCondition;
        if (elifNextToken?.type === 'TEST_START') {
            elifCondition = parser.parsePosixTestExpression();
        }
        else if (elifNextToken?.type === 'EXTENDED_TEST_START') {
            elifCondition = parser.parseExtendedTestExpression();
        }
        else {
            // Fallback to POSIX test for backward compatibility
            elifCondition = parser.parsePosixTestExpression();
        }
        // Consume semicolon if present after elif condition
        let elifSemicolonAfterCondition = undefined;
        if (parser.peek()?.type === 'SEMICOLON') {
            const semicolonToken = parser.advance(); // consume semicolon
            if (semicolonToken) {
                elifSemicolonAfterCondition = {
                    type: 'Semicolon',
                    loc: semicolonToken.loc
                };
            }
        }
        // Skip SPACE tokens before 'then'
        while (parser.match('SPACE')) {
            parser.advance();
        }
        parser.consume('CONDITION_START', 'Expected then');
        const elifCommands = [];
        while (!parser.isAtEnd()) {
            const token = parser.peek();
            if (!token)
                break;
            if (token.type === 'CONDITION_END' || token.type === 'CONTROL_ELIF' || token.type === 'CONTROL_ELSE') {
                break;
            }
            // Handle semicolons specially - add them to the body
            if (token.type === 'SEMICOLON') {
                parser.advance(); // consume semicolon
                const semicolonStatement = {
                    type: 'Semicolon',
                    loc: token.loc
                };
                elifCommands.push(semicolonStatement);
                continue;
            }
            const statement = parser.parseStatement();
            if (statement) {
                elifCommands.push(statement);
            }
        }
        const elifLoc = parser.createLocation(elifCondition.loc, elifCommands[elifCommands.length - 1]?.loc);
        elifClauses.push({
            type: 'ElifClause',
            condition: elifCondition,
            semicolonAfterCondition: elifSemicolonAfterCondition,
            body: elifCommands,
            ...(elifLoc && { loc: elifLoc })
        });
    }
    // Parse else clause
    let elseCommands;
    if (parser.match('CONTROL_ELSE')) {
        parser.advance(); // consume 'else'
        elseCommands = [];
        while (!parser.isAtEnd()) {
            const token = parser.peek();
            if (!token)
                break;
            if (token.type === 'CONDITION_END') {
                break;
            }
            // Handle semicolons specially - add them to the body
            if (token.type === 'SEMICOLON') {
                parser.advance(); // consume semicolon
                const semicolonStatement = {
                    type: 'Semicolon',
                    loc: token.loc
                };
                elseCommands.push(semicolonStatement);
                continue;
            }
            const statement = parser.parseStatement();
            if (statement) {
                elseCommands.push(statement);
            }
        }
    }
    // Consume semicolon if present before 'fi' and add it to the body
    if (parser.peek()?.type === 'SEMICOLON') {
        parser.advance(); // consume semicolon
        const semicolonStatement = {
            type: 'Semicolon',
            loc: parser.peek(-1)?.loc
        };
        if (elseCommands) {
            elseCommands.push(semicolonStatement);
        }
        else {
            thenCommands.push(semicolonStatement);
        }
    }
    // Consume 'fi'
    parser.consume('CONDITION_END', 'Expected fi');
    const loc = parser.createLocation(condition.loc, elseCommands?.[elseCommands.length - 1]?.loc || thenCommands[thenCommands.length - 1]?.loc);
    return {
        type: 'IfStatement',
        condition: condition,
        ...(parser.semicolonAfterCondition && { semicolonAfterCondition: parser.semicolonAfterCondition }),
        thenBody: thenCommands,
        elifClauses: elifClauses,
        ...(elseCommands && { elseBody: elseCommands }),
        ...(loc && { loc })
    };
}
//# sourceMappingURL=parseIf.js.map
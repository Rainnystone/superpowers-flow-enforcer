"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.parseForStatement = parseForStatement;
/**
 * For statement parser
 * Handles for/in/do/done structures
 */
function parseForStatement(parser) {
    // 'for' keyword already consumed by parseStatement dispatch
    // Skip SPACE tokens
    while (parser.match('SPACE')) {
        parser.advance();
    }
    // Parse the variable name
    const variable = parser.parseWord();
    // Skip SPACE tokens
    while (parser.match('SPACE')) {
        parser.advance();
    }
    // Parse optional 'in' and wordlist
    let wordlist;
    if (parser.match('CONTROL_IN')) {
        parser.advance(); // consume 'in'
        // Skip SPACE tokens
        while (parser.match('SPACE')) {
            parser.advance();
        }
        wordlist = [];
        while (!parser.isAtEnd()) {
            const token = parser.peek();
            if (!token)
                break;
            // Stop if we encounter 'do' or semicolon
            if (token.type === 'LOOP_START' || token.type === 'SEMICOLON') {
                break;
            }
            const word = parser.parseWord();
            if (word) {
                wordlist.push(word);
            }
            // Skip SPACE tokens between words
            while (parser.match('SPACE')) {
                parser.advance();
            }
        }
        // Consume semicolon if present
        if (parser.peek()?.type === 'SEMICOLON') {
            const semicolonToken = parser.advance();
            const semicolonAfterWordlist = {
                type: 'Semicolon',
                loc: semicolonToken?.loc
            };
            // Store the semicolon for later use in generation
            parser.semicolonAfterWordlist = semicolonAfterWordlist;
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
    const loc = parser.createLocation(variable.loc, body[body.length - 1]?.loc);
    return {
        type: 'ForStatement',
        variable: variable,
        ...(wordlist && wordlist.length > 0 && { wordlist: wordlist }),
        ...(parser.semicolonAfterWordlist && { semicolonAfterWordlist: parser.semicolonAfterWordlist }),
        body: body,
        ...(loc && { loc })
    };
}
//# sourceMappingURL=parseFor.js.map
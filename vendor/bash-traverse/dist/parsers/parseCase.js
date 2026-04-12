"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.parseCaseStatement = parseCaseStatement;
exports.parseCaseClause = parseCaseClause;
/**
 * Case statement parser
 * Handles case/in/esac structures
 */
function parseCaseStatement(parser) {
    console.log(`DEBUG parseCaseStatement: Starting, current token index: ${parser.current}`);
    // 'case' keyword already consumed by parseStatement dispatch
    // Skip SPACE tokens before the expression
    while (parser.match('SPACE')) {
        parser.advance();
    }
    // Parse the expression
    const expression = parser.parseWord();
    console.log(`DEBUG parseCaseStatement: Parsed expression: "${expression?.value}"`);
    // Skip SPACE and NEWLINE tokens before 'in'
    while (parser.match('SPACE') || parser.match('NEWLINE')) {
        parser.advance();
    }
    parser.consume('CONTROL_IN', 'Expected in');
    console.log(`DEBUG parseCaseStatement: Consumed 'in'`);
    // Parse the clauses
    const clauses = [];
    let clauseIndex = 0;
    let esacIndentation = ''; // Will capture indentation before 'esac'
    // Capture newlines after 'in' for fidelity
    const newlinesAfterIn = [];
    while (parser.peek()?.type === 'NEWLINE') {
        console.log(`DEBUG parseCaseStatement: Capturing newline after 'in'`);
        const newlineToken = parser.peek();
        if (newlineToken) {
            newlinesAfterIn.push({
                type: 'Newline',
                count: 1,
                ...(newlineToken.loc && { loc: newlineToken.loc })
            });
        }
        parser.advance();
    }
    while (!parser.isAtEnd()) {
        const token = parser.peek();
        if (!token)
            break;
        console.log(`DEBUG parseCaseStatement: Clause ${clauseIndex} - Current token: ${token.type} "${token.value}"`);
        // Skip newlines between clauses
        if (token.type === 'NEWLINE') {
            console.log(`DEBUG parseCaseStatement: Skipping newline between clauses`);
            parser.advance();
            continue;
        }
        // Stop if we encounter 'esac' - but don't break, let it continue to be processed
        if (token.type === 'CONTROL_ESAC') {
            console.log(`DEBUG parseCaseStatement: Found 'esac', will process it after clauses`);
            break;
        }
        // Check if we have spaces followed by 'esac' before trying to parse a clause
        const currentToken = parser.peek();
        if (currentToken?.type === 'SPACE') {
            // Look ahead to see if the next token is 'esac'
            const lookAhead = parser.peek(1);
            if (lookAhead?.type === 'CONTROL_ESAC') {
                console.log(`DEBUG parseCaseStatement: Found spaces followed by 'esac', capturing indentation`);
                // Capture the actual indentation before 'esac'
                while (parser.peek()?.type === 'SPACE') {
                    esacIndentation += parser.peek()?.value || '';
                    parser.advance();
                }
                break;
            }
        }
        const clause = parseCaseClause(parser);
        if (clause) {
            console.log(`DEBUG parseCaseStatement: Successfully parsed clause ${clauseIndex} with ${clause.statements.length} statements`);
            clauses.push(clause);
            clauseIndex++;
        }
        else {
            console.log(`DEBUG parseCaseStatement: Failed to parse clause ${clauseIndex}, breaking`);
            break;
        }
    }
    // Capture indentation before 'esac' for fidelity (if not already captured)
    if (!esacIndentation) {
        while (parser.peek()?.type === 'SPACE') {
            esacIndentation += parser.peek()?.value || '';
            parser.advance();
        }
    }
    // Skip newlines before 'esac'
    while (parser.peek()?.type === 'NEWLINE') {
        parser.advance();
    }
    parser.consume('CONTROL_ESAC', 'Expected esac');
    const loc = parser.createLocation(expression.loc, parser.peek(-1)?.loc);
    return {
        type: 'CaseStatement',
        expression: expression,
        clauses: clauses,
        newlinesAfterIn: newlinesAfterIn,
        esacIndentation: esacIndentation,
        ...(loc && { loc })
    };
}
/**
 * Case clause parser
 * Handles pattern) statements ;; structures
 */
function parseCaseClause(parser) {
    const clauseStart = parser.current;
    console.log(`DEBUG parseCaseClause: Starting, current token: "${parser.peek()?.value}" (${parser.peek()?.type})`);
    // Capture indentation before patterns
    let indentation = '';
    while (parser.match('SPACE')) {
        indentation += parser.peek()?.value || '';
        parser.advance();
    }
    // Parse patterns
    const patterns = [];
    // Check if we have a valid pattern start (WORD or ARGUMENT)
    const token = parser.peek();
    if (!token || (token.type !== 'WORD' && token.type !== 'ARGUMENT')) {
        console.log(`DEBUG parseCaseClause: No WORD or ARGUMENT token found, returning null`);
        return null;
    }
    // Parse the pattern(s) until we find a closing parenthesis
    while (!parser.isAtEnd()) {
        const token = parser.peek();
        if (!token)
            break;
        // Stop if we encounter the closing parenthesis
        if (token.type === 'RPAREN' || token.type === 'SUBSHELL_END' || token.type === 'CASE_DELIM_END') {
            console.log(`DEBUG parseCaseClause: Found closing parenthesis, consumed ')'`);
            parser.advance(); // consume ')'
            break;
        }
        // Parse pattern components (can be WORD, ARGUMENT, or operators like PIPE)
        if (token.type === 'WORD' || token.type === 'ARGUMENT' || token.type === 'PIPE') {
            const pattern = parser.parseWord();
            if (pattern) {
                console.log(`DEBUG parseCaseClause: Parsed pattern component: "${pattern.value}"`);
                patterns.push(pattern);
            }
        }
        else {
            // Skip other tokens (like spaces)
            parser.advance();
        }
    }
    // Parse statements
    const statements = [];
    console.log(`DEBUG parseCaseClause: Starting statement parsing`);
    while (!parser.isAtEnd()) {
        const token = parser.peek();
        if (!token)
            break;
        console.log(`DEBUG parseCaseClause: Statement parsing - Current token: ${token.type} "${token.value}"`);
        // Stop if we encounter ';;'
        if (token.type === 'CLAUSE_END') {
            console.log(`DEBUG parseCaseClause: Found CLAUSE_END, consuming ';;'`);
            statements.push({
                type: 'DoubleSemicolon',
                loc: token.loc
            });
            parser.advance(); // consume ';;'
            break;
        }
        // Check if next token is a WORD or ARGUMENT followed by closing parenthesis (new clause)
        if (token.type === 'WORD' || token.type === 'ARGUMENT') {
            const nextToken = parser.peek(1);
            if (nextToken && (nextToken.type === 'RPAREN' || nextToken.type === 'SUBSHELL_END' || nextToken.type === 'CASE_DELIM_END')) {
                console.log(`DEBUG parseCaseClause: Found start of new clause (WORD/ARGUMENT + closing parenthesis), breaking`);
                break; // This is the start of a new clause
            }
        }
        // Parse statements (including commands and newlines)
        const statement = parser.parseStatement();
        if (statement) {
            console.log(`DEBUG parseCaseClause: Parsed statement: ${statement.type}`);
            statements.push(statement);
        }
        else {
            console.log(`DEBUG parseCaseClause: Failed to parse statement, advancing to avoid infinite loop`);
            // If we can't parse a statement, advance to avoid infinite loop
            parser.advance();
        }
    }
    const clauseEnd = parser.current;
    console.log(`DEBUG parseCaseClause: Finished parsing clause with ${patterns.length} patterns and ${statements.length} statements`);
    const loc = parser.createLocation(patterns[0]?.loc, statements[statements.length - 1]?.loc);
    return {
        type: 'CaseClause',
        patterns: patterns,
        statements: statements,
        clauseStart: clauseStart,
        clauseEnd: clauseEnd,
        indentation: indentation,
        ...(loc && { loc })
    };
}
//# sourceMappingURL=parseCase.js.map
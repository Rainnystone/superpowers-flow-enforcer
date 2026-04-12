"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.BashLexer = void 0;
class BashLexer {
    source;
    position = 0;
    line = 1;
    column = 1;
    tokens = [];
    // Heredoc state tracking (simplified)
    // private heredocDelimiter: string = ''; // Not needed for two-pass approach
    constructor(source) {
        this.source = source;
    }
    tokenize() {
        this.tokens = [];
        this.position = 0;
        this.line = 1;
        this.column = 1;
        // Pass 1: Basic tokenization (ignore heredocs)
        this.basicTokenize();
        // Pass 2: Process heredocs
        this.postProcessHeredocs();
        this.postProcessRegexPatterns();
        // Pass 3: Fix function names and function argument parentheses
        this.postProcessFunctionTokens();
        return this.tokens;
    }
    basicTokenize() {
        while (!this.isAtEnd()) {
            const char = this.peek();
            if (char === '\n') {
                // Generate NEWLINE token instead of skipping
                this.addToken('NEWLINE', '\n');
                this.line++;
                this.column = 1;
                this.position++;
            }
            else if (char === '\\') {
                // Check for line continuation
                this.readBackslash();
            }
            else if (this.isWhitespace(char)) {
                // Capture SPACE tokens for exact preservation
                this.readSpace();
            }
            else if (char === '#') {
                // Check if this is a shebang (first line starting with #!)
                if (this.line === 1 && this.column === 1 && this.peekNext() === '!') {
                    this.readShebang();
                }
                else {
                    this.readComment();
                }
            }
            else if (char === '"' || char === "'") {
                this.readString();
            }
            else if (char === '$') {
                this.readExpansion();
            }
            else if (char === '`') {
                this.readBacktick();
            }
            else if (char === '(' || char === ')') {
                this.readParentheses();
            }
            else if (char === '[' || char === ']') {
                this.readBrackets();
            }
            else if (char === '{' || char === '}') {
                this.readBraces(); // Handle braces as keywords
            }
            else if (this.isTestOperator(char)) {
                this.readTestOperator();
            }
            else if (this.isOperator(char)) {
                this.readOperator();
            }
            else if (this.isWordStart(char)) {
                this.readWord();
            }
            else {
                // Unknown character, treat as single character token
                this.addToken('CHAR', char);
                this.advance();
            }
        }
    }
    isAtEnd() {
        return this.position >= this.source.length;
    }
    peek() {
        if (this.isAtEnd())
            return '\\0';
        return this.source[this.position] ?? '\\0';
    }
    peekNext() {
        if (this.position + 1 >= this.source.length)
            return '\\0';
        return this.source[this.position + 1] ?? '\\0';
    }
    advance() {
        if (this.peek() === '\n') {
            this.line++;
            this.column = 1;
        }
        else {
            this.column++;
        }
        this.position++;
    }
    isWhitespace(char) {
        return /\s/.test(char) && char !== '\n';
    }
    isWordStart(char) {
        return /[a-zA-Z_0-9\/.*?-]/.test(char);
    }
    isOperator(char) {
        return /[|&;<>!=]/.test(char);
    }
    isTestOperator(char) {
        return char === '-';
    }
    readComment() {
        const start = this.createPosition();
        let value = '#';
        this.advance(); // consume #
        while (!this.isAtEnd() && this.peek() !== '\n') {
            value += this.peek();
            this.advance();
        }
        this.addToken('COMMENT', value, start);
    }
    readShebang() {
        const start = this.createPosition();
        let value = '#';
        this.advance(); // consume #
        while (!this.isAtEnd() && this.peek() !== '\n') {
            value += this.peek();
            this.advance();
        }
        this.addToken('SHEBANG', value, start);
    }
    readString() {
        const start = this.createPosition();
        const quote = this.peek();
        this.advance(); // consume opening quote
        // For now, read the entire string as a single token
        // TODO: Parse variable expansions within strings
        let value = quote;
        while (!this.isAtEnd() && this.peek() !== quote) {
            if (this.peek() === '\\') {
                value += this.peek();
                this.advance();
                if (!this.isAtEnd()) {
                    value += this.peek();
                    this.advance();
                }
            }
            else {
                value += this.peek();
                this.advance();
            }
        }
        if (!this.isAtEnd()) {
            value += this.peek();
            this.advance(); // consume closing quote
        }
        this.addToken('STRING', value, start);
    }
    readExpansion() {
        const start = this.createPosition();
        let value = '$';
        this.advance(); // consume $
        if (this.peek() === '{') {
            // Variable expansion with braces: ${var}
            value += this.peek();
            this.advance();
            while (!this.isAtEnd() && this.peek() !== '}') {
                value += this.peek();
                this.advance();
            }
            if (!this.isAtEnd()) {
                value += this.peek();
                this.advance(); // consume }
            }
            this.addToken('EXPANSION', value, start);
        }
        else if (this.peek() === '(' && this.peekNext() === '(') {
            // Arithmetic expansion: $((expression))
            value += this.peek();
            this.advance();
            value += this.peek();
            this.advance();
            let parenCount = 2;
            while (!this.isAtEnd() && parenCount > 0) {
                if (this.peek() === '(') {
                    parenCount++;
                }
                else if (this.peek() === ')') {
                    parenCount--;
                }
                value += this.peek();
                this.advance();
            }
            this.addToken('ARITHMETIC_EXPANSION', value, start);
        }
        else if (this.peek() === '(') {
            // Command substitution: $(command)
            value += this.peek();
            this.advance();
            let parenCount = 1;
            while (!this.isAtEnd() && parenCount > 0) {
                if (this.peek() === '(') {
                    parenCount++;
                }
                else if (this.peek() === ')') {
                    parenCount--;
                }
                value += this.peek();
                this.advance();
            }
            this.addToken('COMMAND_SUBSTITUTION', value, start);
        }
        else {
            // Simple variable expansion: $var
            while (!this.isAtEnd() && this.isWordStart(this.peek())) {
                value += this.peek();
                this.advance();
            }
            this.addToken('EXPANSION', value, start);
        }
    }
    readBacktick() {
        const start = this.createPosition();
        let value = '`';
        this.advance(); // consume opening backtick
        while (!this.isAtEnd() && this.peek() !== '`') {
            if (this.peek() === '\\') {
                value += this.peek();
                this.advance();
                if (!this.isAtEnd()) {
                    value += this.peek();
                    this.advance();
                }
            }
            else {
                value += this.peek();
                this.advance();
            }
        }
        if (!this.isAtEnd()) {
            value += this.peek();
            this.advance(); // consume closing backtick
        }
        this.addToken('BACKTICK_SUBSTITUTION', value, start);
    }
    readParentheses() {
        const char = this.peek();
        // Check if this is function argument parentheses by looking at the previous token
        if (char === '(') {
            // Look back to see if we're in a function context
            const prevToken = this.tokens.length > 0 ? this.tokens[this.tokens.length - 1] : null;
            const prevPrevToken = this.tokens.length > 1 ? this.tokens[this.tokens.length - 2] : null;
            // Check if we have: function <name> ( or just <name> (
            if (prevToken && prevToken.type === 'FUNCTION_NAME' &&
                prevPrevToken && prevPrevToken.type === 'CONTROL_FUNCTION') {
                // This is function argument parentheses
                this.addToken('FUNCTION_ARGS_START', char);
            }
            else if (prevToken && prevToken.type === 'FUNCTION_NAME' &&
                prevPrevToken && prevPrevToken.type === 'SPACE') {
                // This could be function name() syntax without 'function' keyword
                // Look further back to see if there's a function keyword
                let foundFunction = false;
                for (let i = this.tokens.length - 3; i >= 0; i--) {
                    if (this.tokens[i]?.type === 'CONTROL_FUNCTION') {
                        foundFunction = true;
                        break;
                    }
                    if (this.tokens[i]?.type === 'NEWLINE' || this.tokens[i]?.type === 'SEMICOLON') {
                        break;
                    }
                }
                if (foundFunction) {
                    this.addToken('FUNCTION_ARGS_START', char);
                }
                else {
                    this.addToken('SUBSHELL_START', char);
                }
            }
            else {
                // Check if we're in a case statement context
                let inCaseContext = false;
                for (let i = this.tokens.length - 1; i >= 0; i--) {
                    const token = this.tokens[i];
                    if (token?.type === 'CONTROL_CASE') {
                        inCaseContext = true;
                        break;
                    }
                    if (token?.type === 'NEWLINE' || token?.type === 'SEMICOLON' ||
                        token?.type === 'BRACE_START' || token?.type === 'BRACE_END') {
                        break;
                    }
                }
                if (inCaseContext) {
                    // This is case pattern delimiter parentheses
                    this.addToken('CASE_DELIM_START', char);
                }
                else {
                    // Default to subshell parentheses
                    this.addToken('SUBSHELL_START', char);
                }
            }
        }
        else {
            // Closing parenthesis - check if we're closing function args, case delim, or subshell
            const prevToken = this.tokens.length > 0 ? this.tokens[this.tokens.length - 1] : null;
            if (prevToken && prevToken.type === 'FUNCTION_ARGS_START') {
                this.addToken('FUNCTION_ARGS_END', char);
            }
            else if (prevToken && prevToken.type === 'CASE_DELIM_START') {
                this.addToken('CASE_DELIM_END', char);
            }
            else {
                this.addToken('SUBSHELL_END', char);
            }
        }
        this.advance();
    }
    readBrackets() {
        const char = this.peek();
        // Check for double brackets [[ ... ]] (Bash extended test syntax)
        if (char === '[' && this.peekNext() === '[') {
            this.addToken('EXTENDED_TEST_START', '[[');
            this.advance(); // consume first [
            this.advance(); // consume second [
        }
        else if (char === ']' && this.peekNext() === ']') {
            this.addToken('EXTENDED_TEST_END', ']]');
            this.advance(); // consume first ]
            this.advance(); // consume second ]
        }
        else {
            // Single brackets [ ... ] (POSIX test command)
            this.addToken(char === '[' ? 'TEST_START' : 'TEST_END', char);
            this.advance();
        }
    }
    readBraces() {
        const char = this.peek();
        this.addToken(char === '{' ? 'BRACE_START' : 'BRACE_END', char);
        this.advance();
    }
    readTestOperator() {
        const start = this.createPosition();
        let value = this.peek();
        this.advance(); // consume the '-'
        // Read the test operator (e.g., 'lt', 'gt', 'eq', etc.)
        while (!this.isAtEnd() && this.isWordStart(this.peek())) {
            value += this.peek();
            this.advance();
        }
        // Categorize the test operator
        let tokenType = 'TEST_OPERATOR';
        if (this.isUnaryTestOperator(value)) {
            tokenType = 'UNARY_TEST_OPERATOR';
        }
        else if (this.isBinaryTestOperator(value)) {
            tokenType = 'BINARY_TEST_OPERATOR';
        }
        else if (this.isBooleanOperator(value)) {
            tokenType = 'BOOLEAN_OPERATOR';
        }
        this.addToken(tokenType, value, start);
    }
    isUnaryTestOperator(value) {
        const unaryOperators = ['-f', '-d', '-e', '-r', '-w', '-x', '-z', '-n', '-s', '-L', '-S', '-G', '-O', '-N'];
        return unaryOperators.includes(value);
    }
    isBinaryTestOperator(value) {
        const binaryOperators = ['-eq', '-ne', '-lt', '-le', '-gt', '-ge', '=', '!=', '=='];
        return binaryOperators.includes(value);
    }
    isBooleanOperator(value) {
        const booleanOperators = ['-a', '-o'];
        return booleanOperators.includes(value);
    }
    readOperator() {
        const start = this.createPosition();
        let value = this.peek();
        this.advance();
        // Handle multi-character operators
        const nextChar = this.peek();
        const twoCharOp = value + nextChar;
        // Check for three-character operators first
        if (twoCharOp === '<<' && this.peekNext() === '-') {
            value = '<<-';
            this.advance();
            this.advance();
        }
        else if (['&&', '||', '>>', '<<', '2>', '2>>', ';;', '==', '!=', '=~'].includes(twoCharOp)) {
            value = twoCharOp;
            this.advance();
        }
        else if (value === '2' && nextChar === '>&' && this.peekNext() === '1') {
            value = '2>&1';
            this.advance();
            this.advance();
        }
        // Map operator values to shell-level token types
        let tokenType = 'OPERATOR';
        if (value === ';') {
            tokenType = 'SEMICOLON';
        }
        else if (value === '&&') {
            tokenType = 'LOGICAL_AND';
        }
        else if (value === '||') {
            tokenType = 'LOGICAL_OR';
        }
        else if (value === '|') {
            tokenType = 'PIPE';
        }
        else if (value === ';;') {
            tokenType = 'CLAUSE_END'; // Explicit end of case clause
        }
        else if (value === '>') {
            tokenType = 'REDIRECT_OVERWRITE';
        }
        else if (value === '>>') {
            tokenType = 'REDIRECT_APPEND';
        }
        else if (value === '<') {
            tokenType = 'REDIRECT_INPUT';
        }
        else if (value === '<<') {
            tokenType = 'HEREDOC_START';
        }
        else if (value === '<<-') {
            tokenType = 'HEREDOC_START_TAB_STRIP';
        }
        else if (['2>', '2>>', '2>&1'].includes(value)) {
            tokenType = 'REDIRECT';
        }
        else if (['=', '==', '!=', '=~', '-eq', '-ne', '-lt', '-le', '-gt', '-ge', '-f', '-d', '-e', '-r', '-w', '-x', '-z', '-n', '-s', '-L', '-S', '-G', '-O', '-N', '-a', '-o'].includes(value)) {
            // Test operators for [ ... ] and [[ ... ]] expressions
            if (['-eq', '-ne', '-lt', '-le', '-gt', '-ge', '-f', '-d', '-e', '-r', '-w', '-x', '-z', '-n', '-s', '-L', '-S', '-G', '-O', '-N'].includes(value)) {
                tokenType = 'UNARY_TEST_OPERATOR';
            }
            else if (['-a', '-o'].includes(value)) {
                tokenType = 'BOOLEAN_OPERATOR';
            }
            else {
                tokenType = 'BINARY_TEST_OPERATOR';
            }
        }
        this.addToken(tokenType, value, start);
    }
    readSpace() {
        const start = this.createPosition();
        let value = '';
        while (!this.isAtEnd() && this.isWhitespace(this.peek())) {
            value += this.peek();
            this.advance();
        }
        this.addToken('SPACE', value, start);
    }
    readBackslash() {
        const start = this.createPosition();
        let value = '\\';
        this.advance(); // consume backslash
        // Check if this is a line continuation (backslash followed by newline)
        if (this.peek() === '\n') {
            // This is a line continuation - create a continuation marker token
            this.advance(); // consume newline
            this.line++;
            this.column = 1;
            // Create a CONTINUATION_MARKER token for generation purposes
            this.addToken('CONTINUATION_MARKER', '\\\n', start);
            return;
        }
        else {
            // Just a regular backslash (escape character)
            this.addToken('BACKSLASH', value, start);
        }
    }
    readWord() {
        const start = this.createPosition();
        let value = '';
        // Regular word parsing (heredoc processing happens in post-processing)
        while (!this.isAtEnd() && this.isWordStart(this.peek())) {
            value += this.peek();
            this.advance();
        }
        // Categorize into shell-level tokens
        const tokenType = this.getShellLevelTokenType(value);
        this.addToken(tokenType, value, start);
    }
    getShellLevelTokenType(value) {
        // First check if it's a control keyword
        const controlType = this.getControlKeywordType(value);
        if (controlType !== 'WORD') {
            return controlType;
        }
        // Check if it looks like a flag or option (starts with - or --)
        if (value.startsWith('-')) {
            // Don't classify as FLAG - let it be treated as an argument
            // This prevents issues with commands like "sed -E" or "npx --version"
            return 'ARGUMENT';
        }
        // Check if it looks like a command name (common patterns)
        const commonCommands = [
            'echo', 'cat', 'ls', 'cd', 'pwd', 'mkdir', 'rm', 'cp', 'mv',
            'grep', 'sed', 'awk', 'sort', 'uniq', 'wc', 'head', 'tail',
            'npm', 'npx', 'node', 'yarn', 'git', 'docker', 'kubectl',
            'curl', 'wget', 'ssh', 'scp', 'rsync', 'tar', 'gzip'
        ];
        if (commonCommands.includes(value)) {
            return 'COMMAND_NAME';
        }
        // Default to ARGUMENT for other words
        return 'ARGUMENT';
    }
    getControlKeywordType(value) {
        // Control structure keywords with explicit structural tokens
        const controlKeywords = {
            'if': 'CONTROL_IF',
            'then': 'CONDITION_START', // Explicit start of conditional body
            'else': 'CONTROL_ELSE',
            'elif': 'CONTROL_ELIF',
            'fi': 'CONDITION_END', // Explicit end of conditional body
            'for': 'CONTROL_FOR',
            'in': 'CONTROL_IN',
            'do': 'LOOP_START', // Explicit start of loop body
            'done': 'LOOP_END', // Explicit end of loop body
            'while': 'CONTROL_WHILE',
            'until': 'CONTROL_UNTIL',
            'case': 'CONTROL_CASE',
            'esac': 'CONTROL_ESAC',
            'function': 'CONTROL_FUNCTION',
            'return': 'CONTROL_RETURN',
            'break': 'CONTROL_BREAK',
            'continue': 'CONTROL_CONTINUE',
            'exit': 'CONTROL_EXIT',
            'export': 'CONTROL_EXPORT',
            'readonly': 'CONTROL_READONLY',
            'local': 'CONTROL_LOCAL'
        };
        return controlKeywords[value] || 'WORD';
    }
    createPosition() {
        return {
            line: this.line,
            column: this.column,
            offset: this.position
        };
    }
    createLocation(start, end) {
        if (!start || !end)
            return undefined;
        return {
            start: start.start,
            end: end.end
        };
    }
    addToken(type, value, start) {
        const startPos = start || this.createPosition();
        const endPos = {
            line: this.line,
            column: this.column,
            offset: this.position
        };
        const loc = {
            start: startPos,
            end: endPos
        };
        this.tokens.push({
            type,
            value,
            loc
        });
    }
    postProcessHeredocs() {
        for (let i = 0; i < this.tokens.length - 1; i++) {
            // Look for pattern: HEREDOC_START("<<") + [SPACE] + ARGUMENT(delimiter)
            const currentToken = this.tokens[i];
            if (currentToken && currentToken.type === 'HEREDOC_START' && currentToken.value === '<<') {
                // Find the delimiter, skipping over SPACE tokens
                let delimiterIndex = i + 1;
                while (delimiterIndex < this.tokens.length && this.tokens[delimiterIndex]?.type === 'SPACE') {
                    delimiterIndex++;
                }
                const delimiterToken = this.tokens[delimiterIndex];
                if (delimiterIndex < this.tokens.length && delimiterToken && (delimiterToken.type === 'WORD' || delimiterToken.type === 'ARGUMENT')) {
                    const delimiter = delimiterToken.value;
                    // Convert tokens to heredoc structure
                    const fallbackLoc = {
                        start: { line: 1, column: 1, offset: 0 },
                        end: { line: 1, column: 1, offset: 0 }
                    };
                    this.tokens[i] = {
                        type: 'HEREDOC_START',
                        value: '<<',
                        loc: currentToken.loc || fallbackLoc
                    };
                    this.tokens[delimiterIndex] = {
                        type: 'HEREDOC_DELIMITER',
                        value: delimiter,
                        loc: delimiterToken.loc || fallbackLoc
                    };
                    // Find content and closing delimiter
                    const { contentTokens, endIndex } = this.extractHeredocContent(delimiterIndex + 1, delimiter);
                    // Create content token
                    const contentValue = contentTokens.map(t => t.value).join('');
                    const firstContentToken = contentTokens[0];
                    const lastContentToken = contentTokens[contentTokens.length - 1];
                    const contentLoc = contentTokens.length > 0 && firstContentToken?.loc && lastContentToken?.loc ?
                        this.createLocation(firstContentToken.loc, lastContentToken.loc) :
                        delimiterToken.loc || fallbackLoc;
                    // Insert HEREDOC_CONTENT token
                    this.tokens.splice(delimiterIndex + 1, 0, {
                        type: 'HEREDOC_CONTENT',
                        value: contentValue,
                        loc: contentLoc || fallbackLoc
                    });
                    // Remove only the content tokens, keep the closing delimiter
                    // We need to account for the fact that we just inserted a token at delimiterIndex + 1
                    const tokensToRemove = endIndex - (delimiterIndex + 1);
                    this.tokens.splice(delimiterIndex + 2, tokensToRemove);
                    // Convert the closing delimiter to HEREDOC_DELIMITER type
                    // After splice, the closing delimiter is now at delimiterIndex + 2
                    const closingDelimiterIndex = delimiterIndex + 2;
                    const closingToken = this.tokens[closingDelimiterIndex];
                    if (closingDelimiterIndex < this.tokens.length && closingToken) {
                        this.tokens[closingDelimiterIndex] = {
                            type: 'HEREDOC_DELIMITER',
                            value: closingToken.value,
                            loc: closingToken.loc
                        };
                    }
                }
            }
        }
    }
    extractHeredocContent(startIndex, delimiter) {
        const contentTokens = [];
        let endIndex = startIndex;
        for (let i = startIndex; i < this.tokens.length; i++) {
            const token = this.tokens[i];
            if (token && (token.type === 'WORD' || token.type === 'ARGUMENT') && token.value === delimiter) {
                endIndex = i;
                break;
            }
            if (token) {
                contentTokens.push(token);
            }
        }
        return { contentTokens, endIndex };
    }
    // Removed old heredoc content method - using two-pass approach instead
    postProcessRegexPatterns() {
        for (let i = 0; i < this.tokens.length - 1; i++) {
            const currentToken = this.tokens[i];
            if (currentToken && currentToken.type === 'BINARY_TEST_OPERATOR' && currentToken.value === '=~') {
                // Find the end of the regex pattern (before the closing brackets)
                let patternEndIndex = i + 1;
                let bracketCount = 0;
                // Skip initial SPACE tokens
                while (patternEndIndex < this.tokens.length && this.tokens[patternEndIndex]?.type === 'SPACE') {
                    patternEndIndex++;
                }
                // Find the end of the regex pattern
                for (let j = patternEndIndex; j < this.tokens.length; j++) {
                    const token = this.tokens[j];
                    if (!token)
                        break;
                    // Count nested brackets to handle cases like [[:graph:]]
                    if (token.type === 'EXTENDED_TEST_START' && token.value === '[[') {
                        bracketCount++;
                    }
                    else if (token.type === 'EXTENDED_TEST_END' && token.value === ']]') {
                        bracketCount--;
                        if (bracketCount < 0) {
                            patternEndIndex = j;
                            break;
                        }
                    }
                }
                // Extract all tokens that make up the regex pattern
                const patternTokens = [];
                for (let j = i + 1; j < patternEndIndex; j++) {
                    const token = this.tokens[j];
                    if (token) {
                        patternTokens.push(token);
                    }
                }
                if (patternTokens.length > 0) {
                    // Remove leading and trailing SPACE tokens
                    let startIndex = 0;
                    let endIndex = patternTokens.length;
                    while (startIndex < patternTokens.length && patternTokens[startIndex]?.type === 'SPACE') {
                        startIndex++;
                    }
                    while (endIndex > startIndex && patternTokens[endIndex - 1]?.type === 'SPACE') {
                        endIndex--;
                    }
                    const trimmedTokens = patternTokens.slice(startIndex, endIndex);
                    // Create a single REGEX_PATTERN token from all the pattern tokens
                    // Preserve original spacing by including SPACE tokens
                    const patternValue = trimmedTokens.map(t => t.value).join('');
                    const firstToken = trimmedTokens.length > 0 ? trimmedTokens[0] : (patternTokens.length > 0 ? patternTokens[0] : undefined);
                    const lastToken = trimmedTokens.length > 0 ? trimmedTokens[trimmedTokens.length - 1] : (patternTokens.length > 0 ? patternTokens[patternTokens.length - 1] : undefined);
                    const patternLoc = firstToken?.loc && lastToken?.loc ?
                        this.createLocation(firstToken.loc, lastToken.loc) :
                        firstToken?.loc;
                    // Replace the first pattern token with the combined regex pattern
                    let firstPatternIndex = i + 1;
                    while (firstPatternIndex < this.tokens.length && this.tokens[firstPatternIndex]?.type === 'SPACE') {
                        firstPatternIndex++;
                    }
                    this.tokens[firstPatternIndex] = {
                        type: 'REGEX_PATTERN',
                        value: patternValue,
                        loc: patternLoc || {
                            start: { line: 1, column: 1, offset: 0 },
                            end: { line: 1, column: 1, offset: 0 }
                        }
                    };
                    // Remove the remaining pattern tokens
                    const tokensToRemove = patternEndIndex - firstPatternIndex - 1;
                    if (tokensToRemove > 0) {
                        this.tokens.splice(firstPatternIndex + 1, tokensToRemove);
                    }
                }
            }
        }
    }
    postProcessFunctionTokens() {
        for (let i = 0; i < this.tokens.length - 2; i++) {
            const currentToken = this.tokens[i];
            const nextToken = this.tokens[i + 1];
            const nextNextToken = this.tokens[i + 2];
            // Fix function name tokens: if we have CONTROL_FUNCTION -> SPACE -> ARGUMENT
            if (currentToken && currentToken.type === 'CONTROL_FUNCTION' &&
                nextToken && nextToken.type === 'SPACE' &&
                nextNextToken && nextNextToken.type === 'ARGUMENT') {
                // Convert the ARGUMENT to FUNCTION_NAME
                this.tokens[i + 2] = {
                    type: 'FUNCTION_NAME',
                    value: nextNextToken.value,
                    loc: nextNextToken.loc
                };
            }
            // Fix function argument parentheses: if we have FUNCTION_NAME followed by SUBSHELL_START
            if (currentToken && currentToken.type === 'FUNCTION_NAME' &&
                nextToken && nextToken.type === 'SUBSHELL_START') {
                // Convert SUBSHELL_START to FUNCTION_ARGS_START
                this.tokens[i + 1] = {
                    type: 'FUNCTION_ARGS_START',
                    value: nextToken.value,
                    loc: nextToken.loc
                };
                // Find the matching closing parenthesis and convert it too
                let parenDepth = 1;
                for (let j = i + 2; j < this.tokens.length; j++) {
                    if (this.tokens[j]?.type === 'SUBSHELL_START') {
                        parenDepth++;
                    }
                    else if (this.tokens[j]?.type === 'SUBSHELL_END') {
                        parenDepth--;
                        if (parenDepth === 0) {
                            // Convert SUBSHELL_END to FUNCTION_ARGS_END
                            this.tokens[j] = {
                                type: 'FUNCTION_ARGS_END',
                                value: this.tokens[j].value,
                                loc: this.tokens[j].loc
                            };
                            break;
                        }
                    }
                }
            }
        }
    }
}
exports.BashLexer = BashLexer;
//# sourceMappingURL=lexer.js.map
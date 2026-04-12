import { Token, SourceLocation } from '../types';
/**
 * Parser interface that parser modules can use
 * This abstracts the parser methods that modules need
 */
export interface BashParser {
    isAtEnd(): boolean;
    peek(offset?: number): Token | null;
    advance(): Token | null;
    match(type: string): boolean;
    consume(type: string, message: string): Token;
    current: number;
    parseStatement(): any;
    parsePosixTestExpression(): any;
    parseExtendedTestExpression(): any;
    parseWord(): any;
    parseCommand(): any;
    createLocation(start: SourceLocation | undefined, end: SourceLocation | undefined): SourceLocation | undefined;
}
//# sourceMappingURL=types.d.ts.map
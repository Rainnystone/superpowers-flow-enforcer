import { Token, Program, ASTNode, SourceLocation, Command, TestExpression, VariableAssignment } from './types';
import { BashPlugin } from './plugin-types';
export declare class BashParser {
    private tokens;
    current: number;
    private pluginRegistry;
    constructor(plugins?: BashPlugin[]);
    parse(source: string): Program;
    isAtEnd(): boolean;
    peek(offset?: number): Token | null;
    advance(): Token | null;
    match(type: string): boolean;
    consume(type: string, message: string): Token;
    parsePosixTestExpression(): TestExpression;
    parseExtendedTestExpression(): TestExpression;
    parseStatement(): ASTNode | null;
    private parseComment;
    private parseSpace;
    private parseContinuationMarker;
    private parseShebang;
    private parsePipeline;
    parseCommand(inPipelineContext?: boolean): Command | VariableAssignment;
    private findCustomCommandHandler;
    private parseCustomCommand;
    private parseStandardCommand;
    parseWord(): ASTNode;
    private parseRedirect;
    private parseHereDocument;
    private parseHeredocContent;
    private parseLineForExpansions;
    private parseFunctionDefinition;
    private parseBraceGroup;
    private parseStatementArray;
    private isPipelineStart;
    createLocation(start: SourceLocation | undefined, end: SourceLocation | undefined): SourceLocation | undefined;
}
export declare function parse(source: string, plugins?: BashPlugin[]): Program;
//# sourceMappingURL=parser.d.ts.map
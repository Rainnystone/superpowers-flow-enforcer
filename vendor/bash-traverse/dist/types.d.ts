export interface ASTNode {
    type: string;
    loc?: SourceLocation;
    [key: string]: any;
}
export interface SourceLocation {
    start: Position;
    end: Position;
    source?: string;
}
export interface Position {
    line: number;
    column: number;
    offset: number;
}
export interface Token {
    type: string;
    value: string;
    loc: SourceLocation;
}
export interface Word extends ASTNode {
    type: 'Word';
    text: string;
    quoted?: boolean;
    quoteType?: '"' | "'" | '`';
}
export interface Comment extends ASTNode {
    type: 'Comment';
    value: string;
    leading: boolean;
}
export interface Shebang extends ASTNode {
    type: 'Shebang';
    text: string;
}
export interface NewlineStatement extends ASTNode {
    type: 'Newline';
    count: number;
}
export interface SemicolonStatement extends ASTNode {
    type: 'Semicolon';
}
export interface DoubleSemicolonStatement extends ASTNode {
    type: 'DoubleSemicolon';
}
export interface SpaceStatement extends ASTNode {
    type: 'Space';
    value: string;
}
export interface LineContinuationStatement extends ASTNode {
    type: 'LineContinuation';
    value: string;
}
export interface ContinuationMarkerStatement extends ASTNode {
    type: 'ContinuationMarker';
    value: string;
}
export interface VariableAssignment extends ASTNode {
    type: 'VariableAssignment';
    name: Word;
    value: Word;
}
export interface TestExpression extends ASTNode {
    type: 'TestExpression';
    elements: TestElement[];
    negated?: boolean;
    extended?: boolean;
}
export interface TestElement extends ASTNode {
    type: 'TestElement';
    operator?: Word;
    argument?: Word;
    isOperator: boolean;
}
export type Statement = Command | Pipeline | TestExpression | IfStatement | ForStatement | WhileStatement | UntilStatement | CaseStatement | FunctionDefinition | Subshell | BraceGroup | Comment | Shebang | NewlineStatement | SemicolonStatement | DoubleSemicolonStatement | SpaceStatement | LineContinuationStatement | ContinuationMarkerStatement | VariableAssignment;
export interface Command extends ASTNode {
    type: 'Command';
    name: Word;
    arguments: Word[];
    redirects: Redirect[];
    hereDocument?: HereDocument;
    prefixStatements?: Statement[];
    async?: boolean;
    leadingComments?: Comment[];
    trailingComments?: Comment[];
    hasSpaceBefore?: boolean;
    hasSpaceAfter?: boolean;
    indentation?: string;
}
export interface Pipeline extends ASTNode {
    type: 'Pipeline';
    commands: Command[];
    operators: string[];
    spacesBeforeOperators?: Token[][];
    negated?: boolean;
}
export interface IfStatement extends ASTNode {
    type: 'IfStatement';
    condition: Statement;
    semicolonAfterCondition?: SemicolonStatement;
    thenBody: Statement[];
    elifClauses: ElifClause[];
    elseBody?: Statement[];
}
export interface ElifClause extends ASTNode {
    type: 'ElifClause';
    condition: Statement;
    semicolonAfterCondition?: SemicolonStatement;
    body: Statement[];
}
export interface ForStatement extends ASTNode {
    type: 'ForStatement';
    variable: Word;
    wordlist?: Word[];
    semicolonAfterWordlist?: SemicolonStatement;
    body: Statement[];
}
export interface WhileStatement extends ASTNode {
    type: 'WhileStatement';
    condition: TestExpression;
    semicolonAfterCondition?: SemicolonStatement;
    body: Statement[];
}
export interface UntilStatement extends ASTNode {
    type: 'UntilStatement';
    condition: TestExpression;
    body: Statement[];
}
export interface CaseStatement extends ASTNode {
    type: 'CaseStatement';
    expression: ASTNode;
    clauses: CaseClause[];
    newlinesAfterIn?: Statement[];
    esacIndentation?: string;
}
export interface CaseClause extends ASTNode {
    type: 'CaseClause';
    patterns: ASTNode[];
    statements: Statement[];
    clauseStart: number;
    clauseEnd: number;
    indentation?: string;
}
export interface FunctionDefinition extends ASTNode {
    type: 'FunctionDefinition';
    name: Word;
    body: Statement[];
    hasParentheses?: boolean;
}
export interface Subshell extends ASTNode {
    type: 'Subshell';
    body: Statement[];
}
export interface BraceGroup extends ASTNode {
    type: 'BraceGroup';
    body: Statement[];
}
export interface Redirect extends ASTNode {
    type: 'Redirect';
    operator: string;
    target: Word;
    fd?: number;
}
export interface HereDocument extends ASTNode {
    type: 'HereDocument';
    delimiter: Word;
    content: string;
    stripTabs?: boolean;
}
export interface VariableExpansion extends ASTNode {
    type: 'VariableExpansion';
    name: Word;
    modifier?: ExpansionModifier;
}
export interface ExpansionModifier extends ASTNode {
    type: 'ExpansionModifier';
    operator: string;
    value: Word;
}
export interface CommandSubstitution extends ASTNode {
    type: 'CommandSubstitution';
    command: Statement[];
    style: '$()' | '``';
}
export interface ArithmeticExpansion extends ASTNode {
    type: 'ArithmeticExpansion';
    expression: string;
}
export interface ArrayElement extends ASTNode {
    type: 'ArrayElement';
    index?: Word;
    value: Word;
}
export interface ArrayAssignment extends ASTNode {
    type: 'ArrayAssignment';
    name: Word;
    elements: ArrayElement[];
}
export interface Assignment extends ASTNode {
    type: 'Assignment';
    name: Word;
    value: Word;
}
export interface Program extends ASTNode {
    type: 'Program';
    body: Statement[];
    comments: Comment[];
}
export interface ParserOptions {
    locations?: boolean;
    comments?: boolean;
    ranges?: boolean;
    sourceType?: 'script' | 'module';
}
export interface NodePath<T = ASTNode> {
    node: T;
    parent: NodePath | null;
    parentKey: string | null;
    parentIndex: number | null;
    type: string;
    get(key: string): NodePath | null;
    getNode(key: string): ASTNode | null;
    isNodeType(type: string): boolean;
    replaceWith(node: ASTNode): void;
    insertBefore(node: ASTNode): void;
    insertAfter(node: ASTNode): void;
    remove(): void;
}
export interface Visitor {
    [nodeType: string]: (path: NodePath) => void;
}
export interface GeneratorOptions {
    comments?: boolean;
    compact?: boolean;
    indent?: string;
    lineTerminator?: string;
}
//# sourceMappingURL=types.d.ts.map
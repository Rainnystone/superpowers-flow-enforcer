import { BashPlugin, CustomCommandHandler, VisitorPlugin, GeneratorPlugin, ValidationResult, PluginSDK as IPluginSDK, PluginGeneratorOptions } from './plugin-types';
import { ASTNode, Token, NodePath, SourceLocation } from './types';
export declare class PluginSDK implements IPluginSDK {
    createCommandHandler(pattern: string, handlers: {
        parse: CustomCommandHandler['parse'];
        generate: CustomCommandHandler['generate'];
        validate?: CustomCommandHandler['validate'];
        priority?: number;
    }): CustomCommandHandler;
    createVisitor(name: string, visitors: Record<string, (path: NodePath) => void>): VisitorPlugin;
    createGenerator(name: string, handlers: {
        canHandle: (nodeType: string) => boolean;
        generate: (node: ASTNode, options?: PluginGeneratorOptions) => string;
    }): GeneratorPlugin;
    validatePlugin(plugin: BashPlugin): ValidationResult;
    static createLocation(start: SourceLocation | undefined, end: SourceLocation | undefined): SourceLocation | undefined;
    static parseWord(tokens: Token[], startIndex: number): {
        word: ASTNode;
        consumedTokens: number;
    };
    static parseWords(tokens: Token[], startIndex: number, count: number): {
        words: ASTNode[];
        consumedTokens: number;
    };
    static parseUntil(tokens: Token[], startIndex: number, predicate: (token: Token) => boolean): {
        words: ASTNode[];
        consumedTokens: number;
    };
    static findToken(tokens: Token[], startIndex: number, predicate: (token: Token) => boolean): number;
    static findTokenByType(tokens: Token[], startIndex: number, type: string): number;
    static findTokenByValue(tokens: Token[], startIndex: number, value: string): number;
}
//# sourceMappingURL=plugin-sdk.d.ts.map
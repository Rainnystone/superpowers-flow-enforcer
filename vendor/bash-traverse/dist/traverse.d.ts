import { Program, Visitor, NodePath } from './types';
import { BashPlugin } from './plugin-types';
export declare function traverse(ast: Program, visitor: Visitor, plugins?: BashPlugin[]): void;
export declare function findNodes(ast: Program, nodeType: string): NodePath[];
export declare function findNode(ast: Program, nodeType: string): NodePath | null;
export declare function hasNode(ast: Program, nodeType: string): boolean;
export declare function countNodes(ast: Program, nodeType: string): number;
export declare function transform(ast: Program, visitor: Visitor, plugins?: BashPlugin[]): Program;
//# sourceMappingURL=traverse.d.ts.map
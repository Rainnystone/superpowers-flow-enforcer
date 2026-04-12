export interface StatementArrayContext {
    type: "condition" | "loop" | "clause" | "block" | "function" | "pipeline" | "subshell";
    needsSemicolons?: boolean;
    needsNewlines?: boolean;
    compact?: boolean;
}
//# sourceMappingURL=types.d.ts.map
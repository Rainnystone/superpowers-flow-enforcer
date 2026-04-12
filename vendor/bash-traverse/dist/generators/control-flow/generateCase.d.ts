import { CaseStatement, CaseClause } from '../../types';
/**
 * Case statement generator
 * Case statements commonly need explicit spacing: "case $1 in"
 */
export declare function generateCaseStatement(caseStatement: CaseStatement): string;
/**
 * Case clause generator
 * Case clauses commonly need explicit spacing: "    start)"
 */
export declare function generateCaseClause(caseClause: CaseClause): string;
//# sourceMappingURL=generateCase.d.ts.map
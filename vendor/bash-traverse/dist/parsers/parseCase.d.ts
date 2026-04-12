import { CaseStatement, CaseClause } from '../types';
import { BashParser } from './types';
/**
 * Case statement parser
 * Handles case/in/esac structures
 */
export declare function parseCaseStatement(parser: BashParser): CaseStatement;
/**
 * Case clause parser
 * Handles pattern) statements ;; structures
 */
export declare function parseCaseClause(parser: BashParser): CaseClause | null;
//# sourceMappingURL=parseCase.d.ts.map
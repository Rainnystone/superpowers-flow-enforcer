"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.generateBlockBody = generateBlockBody;
const index_1 = require("../index");
function generateBlockBody(statements) {
    if (statements.length === 0) {
        return '';
    }
    let result = '';
    for (let i = 0; i < statements.length; i++) {
        const statement = statements[i];
        if (!statement)
            continue;
        const generated = (0, index_1.generateNode)(statement);
        if (!generated)
            continue;
        // Add the generated content directly without extra spacing
        result += generated;
    }
    return result;
}
//# sourceMappingURL=generateBlockBody.js.map
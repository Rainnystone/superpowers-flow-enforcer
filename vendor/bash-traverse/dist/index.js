"use strict";
var __createBinding = (this && this.__createBinding) || (Object.create ? (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    var desc = Object.getOwnPropertyDescriptor(m, k);
    if (!desc || ("get" in desc ? !m.__esModule : desc.writable || desc.configurable)) {
      desc = { enumerable: true, get: function() { return m[k]; } };
    }
    Object.defineProperty(o, k2, desc);
}) : (function(o, m, k, k2) {
    if (k2 === undefined) k2 = k;
    o[k2] = m[k];
}));
var __exportStar = (this && this.__exportStar) || function(m, exports) {
    for (var p in m) if (p !== "default" && !Object.prototype.hasOwnProperty.call(exports, p)) __createBinding(exports, m, p);
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.BashLexer = exports.dockerPlugin = exports.PluginSDK = exports.PluginRegistry = exports.transform = exports.countNodes = exports.hasNode = exports.findNode = exports.findNodes = exports.traverse = exports.generate = exports.BashParser = exports.parse = void 0;
// Main exports
var parser_1 = require("./parser");
Object.defineProperty(exports, "parse", { enumerable: true, get: function () { return parser_1.parse; } });
Object.defineProperty(exports, "BashParser", { enumerable: true, get: function () { return parser_1.BashParser; } });
var generators_1 = require("./generators");
Object.defineProperty(exports, "generate", { enumerable: true, get: function () { return generators_1.generate; } });
var traverse_1 = require("./traverse");
Object.defineProperty(exports, "traverse", { enumerable: true, get: function () { return traverse_1.traverse; } });
Object.defineProperty(exports, "findNodes", { enumerable: true, get: function () { return traverse_1.findNodes; } });
Object.defineProperty(exports, "findNode", { enumerable: true, get: function () { return traverse_1.findNode; } });
Object.defineProperty(exports, "hasNode", { enumerable: true, get: function () { return traverse_1.hasNode; } });
Object.defineProperty(exports, "countNodes", { enumerable: true, get: function () { return traverse_1.countNodes; } });
Object.defineProperty(exports, "transform", { enumerable: true, get: function () { return traverse_1.transform; } });
// Type exports
__exportStar(require("./types"), exports);
// Plugin system exports
__exportStar(require("./plugin-types"), exports);
var plugin_registry_1 = require("./plugin-registry");
Object.defineProperty(exports, "PluginRegistry", { enumerable: true, get: function () { return plugin_registry_1.PluginRegistry; } });
var plugin_sdk_1 = require("./plugin-sdk");
Object.defineProperty(exports, "PluginSDK", { enumerable: true, get: function () { return plugin_sdk_1.PluginSDK; } });
// Plugin examples
var docker_plugin_1 = require("./plugins/docker-plugin");
Object.defineProperty(exports, "dockerPlugin", { enumerable: true, get: function () { return docker_plugin_1.dockerPlugin; } });
// Lexer export (for advanced usage)
var lexer_1 = require("./lexer");
Object.defineProperty(exports, "BashLexer", { enumerable: true, get: function () { return lexer_1.BashLexer; } });
//# sourceMappingURL=index.js.map
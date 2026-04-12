"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.initConfig = initConfig;
exports.getConfig = getConfig;
exports.resetConfig = resetConfig;
exports.getConfigOption = getConfigOption;
/**
 * Global generator configuration
 * Singleton pattern for accessing generator options throughout the codebase
 */
let globalConfig = null;
/**
 * Initialize the global generator configuration
 */
function initConfig(options = {}) {
    globalConfig = {
        comments: options.comments ?? true,
        compact: options.compact ?? false,
        indent: options.indent ?? '  ',
        lineTerminator: options.lineTerminator ?? '\n'
    };
}
/**
 * Get the current global configuration
 */
function getConfig() {
    if (!globalConfig) {
        // Initialize with defaults if not set
        initConfig();
    }
    return globalConfig;
}
/**
 * Reset the global configuration (useful for testing)
 */
function resetConfig() {
    globalConfig = null;
}
/**
 * Get a specific config option with optional override
 */
function getConfigOption(key, override) {
    const config = getConfig();
    return (override !== undefined ? override : config[key]);
}
//# sourceMappingURL=config.js.map
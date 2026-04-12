import { GeneratorOptions } from '../types';
/**
 * Initialize the global generator configuration
 */
export declare function initConfig(options?: GeneratorOptions): void;
/**
 * Get the current global configuration
 */
export declare function getConfig(): Required<GeneratorOptions>;
/**
 * Reset the global configuration (useful for testing)
 */
export declare function resetConfig(): void;
/**
 * Get a specific config option with optional override
 */
export declare function getConfigOption<K extends keyof GeneratorOptions>(key: K, override?: GeneratorOptions[K]): Required<GeneratorOptions>[K];
//# sourceMappingURL=config.d.ts.map
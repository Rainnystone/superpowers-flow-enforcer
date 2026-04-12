import { BashPlugin, CustomCommandHandler, VisitorPlugin, GeneratorPlugin, ValidationResult, PluginRegistry as IPluginRegistry } from './plugin-types';
export declare class PluginRegistry implements IPluginRegistry {
    private plugins;
    private commandHandlers;
    private visitors;
    private generators;
    register(plugin: BashPlugin): void;
    unregister(pluginName: string): void;
    getPlugin(name: string): BashPlugin | undefined;
    getAllPlugins(): BashPlugin[];
    getCommandHandlers(): CustomCommandHandler[];
    getVisitors(): VisitorPlugin[];
    getGenerators(): GeneratorPlugin[];
    validatePlugin(plugin: BashPlugin): ValidationResult;
    findCommandHandler(commandStart: string): CustomCommandHandler | null;
    getGeneratorsForNodeType(nodeType: string): GeneratorPlugin[];
}
//# sourceMappingURL=plugin-registry.d.ts.map
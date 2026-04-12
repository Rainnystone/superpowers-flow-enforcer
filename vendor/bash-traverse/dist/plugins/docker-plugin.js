"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.dockerPlugin = void 0;
// Simplified Docker plugin implementation
exports.dockerPlugin = {
    name: 'docker-commands',
    version: '1.0.0',
    description: 'Plugin for parsing and generating Docker commands',
    commands: [
        // Docker run command handler
        {
            pattern: 'docker run',
            priority: 10,
            parse: (tokens, startIndex) => {
                let consumedTokens = 0;
                const options = [];
                let image;
                // Skip 'docker' and 'run'
                consumedTokens += 2;
                // Parse options and image
                while (startIndex + consumedTokens < tokens.length) {
                    const token = tokens[startIndex + consumedTokens];
                    if (!token)
                        break;
                    if (token.type === 'WORD' || token.type === 'STRING') {
                        if (token.value.startsWith('-')) {
                            // This is an option
                            options.push({
                                type: 'Word',
                                text: token.value,
                                loc: token.loc
                            });
                            consumedTokens++;
                        }
                        else {
                            // This should be the image name
                            if (!image) {
                                image = {
                                    type: 'Word',
                                    text: token.value,
                                    loc: token.loc
                                };
                                consumedTokens++;
                            }
                            else {
                                // Additional arguments after image
                                break;
                            }
                        }
                    }
                    else {
                        break;
                    }
                }
                if (!image) {
                    throw new Error('Docker run command requires an image name');
                }
                const node = {
                    type: 'DockerRunCommand',
                    image,
                    options
                };
                return { node, consumedTokens };
            },
            generate: (node) => {
                const dockerNode = node;
                let command = 'docker run';
                // Add options
                dockerNode.options.forEach((opt) => {
                    command += ` ${opt['text']}`;
                });
                // Add image
                command += ` ${dockerNode.image['text']}`;
                return command;
            },
            validate: (node) => {
                const dockerNode = node;
                const errors = [];
                const warnings = [];
                if (!dockerNode.image) {
                    errors.push({
                        message: 'Docker run command requires an image',
                        node: dockerNode
                    });
                }
                return {
                    isValid: errors.length === 0,
                    errors,
                    warnings
                };
            }
        },
        // Docker build command handler
        {
            pattern: 'docker build',
            priority: 10,
            parse: (tokens, startIndex) => {
                let consumedTokens = 0;
                const options = [];
                let context;
                // Skip 'docker' and 'build'
                consumedTokens += 2;
                while (startIndex + consumedTokens < tokens.length) {
                    const token = tokens[startIndex + consumedTokens];
                    if (!token)
                        break;
                    if (token.type === 'WORD' || token.type === 'STRING') {
                        if (token.value.startsWith('-')) {
                            // This is an option
                            options.push({
                                type: 'Word',
                                text: token.value,
                                loc: token.loc
                            });
                            consumedTokens++;
                        }
                        else {
                            // This should be the build context
                            if (!context) {
                                context = {
                                    type: 'Word',
                                    text: token.value,
                                    loc: token.loc
                                };
                                consumedTokens++;
                            }
                        }
                    }
                    else {
                        break;
                    }
                }
                if (!context) {
                    throw new Error('Docker build command requires a build context');
                }
                const node = {
                    type: 'DockerBuildCommand',
                    context,
                    options
                };
                return { node, consumedTokens };
            },
            generate: (node) => {
                const dockerNode = node;
                let command = 'docker build';
                // Add options
                dockerNode.options.forEach((opt) => {
                    command += ` ${opt['text']}`;
                });
                // Add context
                command += ` ${dockerNode.context['text']}`;
                return command;
            }
        }
    ],
    visitors: [
        {
            name: 'docker-optimizer',
            DockerRunCommand: (path) => {
                const node = path.node;
                // Add --rm flag if not present
                const hasRm = node.options.some((opt) => opt['text'] === '--rm');
                if (!hasRm) {
                    node.options.push({
                        type: 'Word',
                        text: '--rm',
                        loc: node.loc
                    });
                }
            },
            DockerBuildCommand: (path) => {
                const node = path.node;
                // Add --no-cache flag for faster builds in development
                const hasNoCache = node.options.some((opt) => opt['text'] === '--no-cache');
                if (!hasNoCache) {
                    node.options.push({
                        type: 'Word',
                        text: '--no-cache',
                        loc: node.loc
                    });
                }
            }
        }
    ],
    generators: [
        {
            name: 'docker-generator',
            canHandle: (nodeType) => {
                return ['DockerRunCommand', 'DockerBuildCommand'].includes(nodeType);
            },
            generate: (node) => {
                switch (node.type) {
                    case 'DockerRunCommand':
                        return generateDockerRun(node);
                    case 'DockerBuildCommand':
                        return generateDockerBuild(node);
                    default:
                        throw new Error(`Unknown Docker command type: ${node.type}`);
                }
            }
        }
    ]
};
// Helper functions for generation
function generateDockerRun(node) {
    let command = 'docker run';
    // Add options
    node.options.forEach((opt) => {
        command += ` ${opt['text']}`;
    });
    // Add image
    command += ` ${node.image['text']}`;
    return command;
}
function generateDockerBuild(node) {
    let command = 'docker build';
    // Add options
    node.options.forEach((opt) => {
        command += ` ${opt['text']}`;
    });
    // Add context
    command += ` ${node.context['text']}`;
    return command;
}
//# sourceMappingURL=docker-plugin.js.map
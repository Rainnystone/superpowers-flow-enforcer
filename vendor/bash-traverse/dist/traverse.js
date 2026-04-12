"use strict";
Object.defineProperty(exports, "__esModule", { value: true });
exports.traverse = traverse;
exports.findNodes = findNodes;
exports.findNode = findNode;
exports.hasNode = hasNode;
exports.countNodes = countNodes;
exports.transform = transform;
// NodePath implementation for AST traversal
class NodePathImpl {
    node;
    parent;
    parentKey;
    parentIndex;
    type;
    constructor(node, parent = null, parentKey = null, parentIndex = null) {
        this.node = node;
        this.parent = parent;
        this.parentKey = parentKey;
        this.parentIndex = parentIndex;
        this.type = node.type;
    }
    get(key) {
        const value = this.node[key];
        if (value === undefined || value === null) {
            return null;
        }
        if (Array.isArray(value)) {
            // Return first element if it's an array
            return value.length > 0 ? new NodePathImpl(value[0], this, key, 0) : null;
        }
        if (typeof value === 'object' && value.type) {
            return new NodePathImpl(value, this, key, null);
        }
        return null;
    }
    getNode(key) {
        const value = this.node[key];
        if (value === undefined || value === null) {
            return null;
        }
        if (Array.isArray(value)) {
            return value.length > 0 ? value[0] : null;
        }
        if (typeof value === 'object' && value.type) {
            return value;
        }
        return null;
    }
    isNodeType(type) {
        return this.type === type;
    }
    replaceWith(node) {
        if (!this.parent) {
            throw new Error('Cannot replace root node');
        }
        if (this.parentKey && this.parentIndex !== null) {
            // Array element
            const parentNode = this.parent.node;
            parentNode[this.parentKey][this.parentIndex] = node;
        }
        else if (this.parentKey) {
            // Object property
            const parentNode = this.parent.node;
            parentNode[this.parentKey] = node;
        }
        // Update this node
        this.node = node;
        this.type = node.type;
    }
    insertBefore(node) {
        if (!this.parent || this.parentKey === null || this.parentIndex === null) {
            throw new Error('Cannot insert before: not an array element');
        }
        const parentNode = this.parent.node;
        parentNode[this.parentKey].splice(this.parentIndex, 0, node);
        // Update indices for subsequent elements
        const parentPath = this.parent;
        for (let i = this.parentIndex + 1; i < parentNode[this.parentKey].length; i++) {
            const childPath = parentPath.get(this.parentKey);
            if (childPath && i < parentNode[this.parentKey].length) {
                childPath.parentIndex = i;
            }
        }
    }
    insertAfter(node) {
        if (!this.parent || this.parentKey === null || this.parentIndex === null) {
            throw new Error('Cannot insert after: not an array element');
        }
        const parentNode = this.parent.node;
        parentNode[this.parentKey].splice(this.parentIndex + 1, 0, node);
        // Update indices for subsequent elements
        const parentPath = this.parent;
        for (let i = this.parentIndex + 2; i < parentNode[this.parentKey].length; i++) {
            const childPath = parentPath.get(this.parentKey);
            if (childPath && i < parentNode[this.parentKey].length) {
                childPath.parentIndex = i;
            }
        }
    }
    remove() {
        if (!this.parent || this.parentKey === null || this.parentIndex === null) {
            throw new Error('Cannot remove: not an array element');
        }
        const parentNode = this.parent.node;
        parentNode[this.parentKey].splice(this.parentIndex, 1);
        // Update indices for subsequent elements
        const parentPath = this.parent;
        for (let i = this.parentIndex; i < parentNode[this.parentKey].length; i++) {
            const childPath = parentPath.get(this.parentKey);
            if (childPath && i < parentNode[this.parentKey].length) {
                childPath.parentIndex = i;
            }
        }
    }
}
// Helper function to get all child nodes of a given node
function getChildNodes(node) {
    const children = [];
    for (const [key, value] of Object.entries(node)) {
        if (key === 'type' || key === 'loc')
            continue;
        if (Array.isArray(value)) {
            // Array of nodes
            value.forEach((item, index) => {
                if (item && typeof item === 'object' && item.type) {
                    children.push({ key, value: item, index });
                }
            });
        }
        else if (value && typeof value === 'object' && value.type) {
            // Single node
            children.push({ key, value });
        }
    }
    return children;
}
// Main traversal function
function traverseNode(node, context, parent = null, parentKey = null, parentIndex = null) {
    const path = new NodePathImpl(node, parent, parentKey, parentIndex);
    // Call enter hooks
    const enterHooks = context.enterHooks.get(node.type) || [];
    for (const hook of enterHooks) {
        hook(path);
    }
    // Call visitor for this node type
    const allVisitors = [...context.visitors, ...context.pluginVisitors];
    for (const visitor of allVisitors) {
        const visitorFn = visitor[node.type];
        if (visitorFn && typeof visitorFn === 'function') {
            visitorFn(path);
        }
    }
    // Traverse children
    const children = getChildNodes(node);
    for (const child of children) {
        traverseNode(child.value, context, path, child.key, child.index);
    }
    // Call exit hooks
    const exitHooks = context.exitHooks.get(node.type) || [];
    for (const hook of exitHooks) {
        hook(path);
    }
}
// Main traverse function
function traverse(ast, visitor, plugins) {
    const context = {
        visitors: [visitor],
        pluginVisitors: [],
        enterHooks: new Map(),
        exitHooks: new Map()
    };
    // Add plugin visitors
    if (plugins) {
        for (const plugin of plugins) {
            if (plugin.visitors) {
                context.pluginVisitors.push(...plugin.visitors);
            }
        }
    }
    // Process enter/exit hooks from visitors
    for (const visitor of context.visitors) {
        for (const [nodeType, visitorFn] of Object.entries(visitor)) {
            if (nodeType.startsWith('enter')) {
                const actualNodeType = nodeType.slice(5); // Remove 'enter' prefix
                if (!context.enterHooks.has(actualNodeType)) {
                    context.enterHooks.set(actualNodeType, []);
                }
                context.enterHooks.get(actualNodeType).push(visitorFn);
            }
            else if (nodeType.startsWith('exit')) {
                const actualNodeType = nodeType.slice(4); // Remove 'exit' prefix
                if (!context.exitHooks.has(actualNodeType)) {
                    context.exitHooks.set(actualNodeType, []);
                }
                context.exitHooks.get(actualNodeType).push(visitorFn);
            }
        }
    }
    // Start traversal from root
    traverseNode(ast, context);
}
// Utility functions for common traversal patterns
// Find all nodes of a specific type
function findNodes(ast, nodeType) {
    const results = [];
    traverse(ast, {
        [nodeType]: (path) => {
            results.push(path);
        }
    });
    return results;
}
// Find the first node of a specific type
function findNode(ast, nodeType) {
    let result = null;
    traverse(ast, {
        [nodeType]: (path) => {
            if (!result) {
                result = path;
            }
        }
    });
    return result;
}
// Check if AST contains a specific node type
function hasNode(ast, nodeType) {
    let found = false;
    traverse(ast, {
        [nodeType]: () => {
            found = true;
        }
    });
    return found;
}
// Count nodes of a specific type
function countNodes(ast, nodeType) {
    let count = 0;
    traverse(ast, {
        [nodeType]: () => {
            count++;
        }
    });
    return count;
}
// Transform AST by applying a visitor that can modify nodes
function transform(ast, visitor, plugins) {
    // Clone the AST to avoid modifying the original
    const clonedAst = JSON.parse(JSON.stringify(ast));
    traverse(clonedAst, visitor, plugins);
    return clonedAst;
}
//# sourceMappingURL=traverse.js.map
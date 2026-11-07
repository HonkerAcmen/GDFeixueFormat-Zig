const std = @import("std");
const Allocator = std.mem.Allocator;

/// 将脚本中的词法单元分类，避免把注释和字符串里的符号当作结构语法。
pub const TokenKind = enum {
    identifier,
    keyword,
    annotation,
    string,
    number,
    punctuation,
    operator,
    comment,
    continuation,
};

/// 表示 GDScript 的语句类别，供后续排版规则按语法职责处理。
pub const NodeKind = enum {
    blank,
    comment,
    annotation,
    function,
    variable,
    constant,
    signal,
    enumeration,
    class_declaration,
    control_flow,
    declaration,
    expression,
    unknown,
};

/// 区分代码块、容器字面量和普通括号，避免单看 `{}` 就推断缩进作用域。
pub const DelimiterKind = enum {
    parentheses,
    array_literal,
    dictionary_literal,
    enum_body,
};

/// 保存词法单元在源代码中的字节范围和起始行。
pub const Token = struct {
    kind: TokenKind,
    start: usize,
    end: usize,
    line: usize,
};

/// 描述一个可独立排版的语句及其缩进父节点。
pub const Node = struct {
    kind: NodeKind,
    start_line: usize,
    end_line: usize,
    indent: usize,
    parent: ?usize = null,
    opens_suite: bool = false,
    delimiter: ?DelimiterKind = null,
    has_chain_call: bool = false,
    has_backslash_continuation: bool = false,
};

/// 表示数组、字典、枚举体或括号表达式，并链接其嵌套父节点。
pub const ContainerNode = struct {
    kind: DelimiterKind,
    start_line: usize,
    end_line: usize,
    parent: ?usize,
};

/// 保存词法结果与按语句构成的轻量 AST。
pub const Document = struct {
    tokens: []Token,
    nodes: []Node,
    containers: []ContainerNode,
    syntax_valid: bool,
};

const Keyword = struct { text: []const u8, kind: NodeKind };

const keywords = [_]Keyword{
    .{ .text = "assert", .kind = .control_flow },
    .{ .text = "as", .kind = .expression },
    .{ .text = "and", .kind = .expression },
    .{ .text = "await", .kind = .expression },
    .{ .text = "break", .kind = .control_flow },
    .{ .text = "breakpoint", .kind = .control_flow },
    .{ .text = "class", .kind = .class_declaration },
    .{ .text = "class_name", .kind = .declaration },
    .{ .text = "const", .kind = .constant },
    .{ .text = "continue", .kind = .control_flow },
    .{ .text = "elif", .kind = .control_flow },
    .{ .text = "else", .kind = .control_flow },
    .{ .text = "enum", .kind = .enumeration },
    .{ .text = "extends", .kind = .declaration },
    .{ .text = "for", .kind = .control_flow },
    .{ .text = "func", .kind = .function },
    .{ .text = "if", .kind = .control_flow },
    .{ .text = "match", .kind = .control_flow },
    .{ .text = "namespace", .kind = .declaration },
    .{ .text = "in", .kind = .expression },
    .{ .text = "is", .kind = .expression },
    .{ .text = "preload", .kind = .expression },
    .{ .text = "not", .kind = .expression },
    .{ .text = "or", .kind = .expression },
    .{ .text = "pass", .kind = .control_flow },
    .{ .text = "return", .kind = .control_flow },
    .{ .text = "signal", .kind = .signal },
    .{ .text = "static", .kind = .declaration },
    .{ .text = "self", .kind = .expression },
    .{ .text = "super", .kind = .expression },
    .{ .text = "trait", .kind = .declaration },
    .{ .text = "var", .kind = .variable },
    .{ .text = "while", .kind = .control_flow },
    .{ .text = "when", .kind = .control_flow },
    .{ .text = "void", .kind = .declaration },
    .{ .text = "yield", .kind = .expression },
};

/// 读取 UTF-8 标识符字节，ASCII 关键字仍按完整单词匹配。
fn isIdentifierByte(char: u8) bool {
    return std.ascii.isAlphanumeric(char) or char == '_' or char >= 0x80;
}

/// 判断单词是否属于 Godot 4 GDScript 关键字集合。
pub fn isKeyword(word: []const u8) bool {
    for (keywords) |keyword| {
        if (std.mem.eql(u8, word, keyword.text)) return true;
    }
    return std.mem.eql(u8, word, "true") or std.mem.eql(u8, word, "false") or
        std.mem.eql(u8, word, "null") or std.mem.eql(u8, word, "PI") or
        std.mem.eql(u8, word, "TAU") or std.mem.eql(u8, word, "INF") or
        std.mem.eql(u8, word, "NaN");
}

/// 按词法状态扫描字符串，识别字符串、注释、注解和关键字。
pub fn tokenize(allocator: Allocator, source: []const u8) ![]Token {
    var tokens: std.ArrayList(Token) = .empty;
    errdefer tokens.deinit(allocator);
    var index: usize = 0;
    var line: usize = 0;
    while (index < source.len) {
        const char = source[index];
        if (char == '\n') {
            line += 1;
            index += 1;
            continue;
        }
        if (std.ascii.isWhitespace(char)) {
            index += 1;
            continue;
        }
        const start = index;
        var kind: TokenKind = .punctuation;
        if (char == '#') {
            kind = .comment;
            while (index < source.len and source[index] != '\n') : (index += 1) {}
        } else if (char == '"' or char == '\'') {
            kind = .string;
            const quote = char;
            const triple = index + 2 < source.len and source[index + 1] == quote and source[index + 2] == quote;
            index += if (triple) 3 else 1;
            var escaped = false;
            while (index < source.len) {
                if (source[index] == '\n') line += 1;
                if (escaped) {
                    escaped = false;
                    index += 1;
                    continue;
                }
                if (source[index] == '\\') {
                    escaped = true;
                    index += 1;
                    continue;
                }
                if (source[index] == quote) {
                    if (!triple) {
                        index += 1;
                        break;
                    }
                    if (index + 2 < source.len and source[index + 1] == quote and source[index + 2] == quote) {
                        index += 3;
                        break;
                    }
                }
                index += 1;
            }
        } else if (char == '@') {
            kind = .annotation;
            index += 1;
            while (index < source.len and isIdentifierByte(source[index])) : (index += 1) {}
        } else if (std.ascii.isAlphabetic(char) or char == '_' or char >= 0x80) {
            index += 1;
            while (index < source.len and isIdentifierByte(source[index])) : (index += 1) {}
            if (isKeyword(source[start..index])) kind = .keyword else kind = .identifier;
        } else if (std.ascii.isDigit(char)) {
            kind = .number;
            index += 1;
            while (index < source.len and (std.ascii.isAlphanumeric(source[index]) or source[index] == '.' or source[index] == '_')) : (index += 1) {}
        } else if (char == '\\') {
            kind = .continuation;
            index += 1;
        } else {
            kind = if (isOperatorByte(char)) .operator else .punctuation;
            index += 1;
        }
        try tokens.append(allocator, .{ .kind = kind, .start = start, .end = index, .line = line });
    }
    return try tokens.toOwnedSlice(allocator);
}

/// 判断字符是否属于 GDScript 运算符。
fn isOperatorByte(char: u8) bool {
    return std.mem.indexOfScalar(u8, "+-*/%=<>!&|^~", char) != null;
}

/// 跳过缩进并返回一行的 AST 节点类型。
pub fn classifyLine(line: []const u8) NodeKind {
    var trimmed = std.mem.trimStart(u8, line, " \t");
    if (trimmed.len == 0) return .blank;
    if (trimmed[0] == '#') return .comment;
    if (trimmed[0] == '@') {
        trimmed = afterAnnotations(trimmed);
        if (trimmed.len == 0) return .annotation;
    }
    if (std.mem.startsWith(u8, trimmed, "static func ")) return .function;
    if (std.mem.startsWith(u8, trimmed, "static var ")) return .variable;
    var end: usize = 0;
    while (end < trimmed.len and isIdentifierByte(trimmed[end])) : (end += 1) {}
    if (end == 0) return .expression;
    for (keywords) |keyword| {
        if (std.mem.eql(u8, trimmed[0..end], keyword.text)) return keyword.kind;
    }
    return .expression;
}

/// 跳过注解名称及其括号参数，返回它所修饰的声明文本。
fn afterAnnotations(text: []const u8) []const u8 {
    var index: usize = 0;
    while (index < text.len and text[index] == '@') {
        index += 1;
        while (index < text.len and isIdentifierByte(text[index])) index += 1;
        while (index < text.len and (text[index] == ' ' or text[index] == '\t')) index += 1;
        if (index < text.len and text[index] == '(') {
            var depth: usize = 1;
            var quote: u8 = 0;
            var escaped = false;
            index += 1;
            while (index < text.len and depth > 0) : (index += 1) {
                const char = text[index];
                if (quote != 0) {
                    if (escaped) {
                        escaped = false;
                    } else if (char == '\\') {
                        escaped = true;
                    } else if (char == quote) {
                        quote = 0;
                    }
                } else if (char == '"' or char == '\'') {
                    quote = char;
                } else if (char == '(') {
                    depth += 1;
                } else if (char == ')') {
                    depth -= 1;
                }
            }
        }
        while (index < text.len and (text[index] == ' ' or text[index] == '\t')) index += 1;
    }
    return text[index..];
}

/// 计算一行的 Tab 缩进层级；空格缩进每四列作为一层兼容旧脚本。
pub fn indentationDepth(line: []const u8) usize {
    var depth: usize = 0;
    var spaces: usize = 0;
    for (line) |char| {
        if (char == '\t') {
            depth += 1;
            spaces = 0;
        } else if (char == ' ') {
            spaces += 1;
            if (spaces == 4) {
                depth += 1;
                spaces = 0;
            }
        } else break;
    }
    return depth;
}

/// 判断语句头是否打开缩进代码块，而非仅含有字典或数组字面量。
fn opensSuite(line: []const u8, kind: NodeKind) bool {
    if (kind != .function and kind != .class_declaration and kind != .control_flow and kind != .enumeration) return false;
    const trimmed = std.mem.trimEnd(u8, line, " \t\\");
    return trimmed.len > 0 and trimmed[trimmed.len - 1] == ':';
}

/// 合并括号续行、反斜杠续行和以点开头的链式调用到同一条 AST 语句。
fn continuesStatement(line: []const u8, bracket_depth: isize, continuation: bool) bool {
    if (bracket_depth > 0 or continuation) return true;
    const trimmed = std.mem.trimStart(u8, line, " \t");
    return std.mem.startsWith(u8, trimmed, ".") or std.mem.startsWith(u8, trimmed, "?.");
}

/// 为脚本构造轻量语句 AST，并为容器和枚举标注不同的括号节点。
pub fn parse(allocator: Allocator, source: []const u8) !Document {
    const tokens = try tokenize(allocator, source);
    errdefer allocator.free(tokens);
    const containers = try parseContainers(allocator, tokens, source);
    errdefer allocator.free(containers);
    var lines: std.ArrayList([]const u8) = .empty;
    defer lines.deinit(allocator);
    var line_iter = std.mem.splitScalar(u8, source, '\n');
    while (line_iter.next()) |line| try lines.append(allocator, line);

    var nodes: std.ArrayList(Node) = .empty;
    errdefer nodes.deinit(allocator);
    var parents: std.ArrayList(usize) = .empty;
    defer parents.deinit(allocator);
    var line_index: usize = 0;
    while (line_index < lines.items.len) {
        const first_line = line_index;
        const first = lines.items[line_index];
        const kind = classifyLine(first);
        const indent = indentationDepth(first);
        var end_line = line_index + 1;
        var bracket_depth: isize = 0;
        var continued = false;
        var has_chain_call = false;
        var has_backslash_continuation = false;
        while (end_line <= lines.items.len) {
            const current = lines.items[end_line - 1];
            const next_exists = end_line < lines.items.len;
            const next = if (next_exists) lines.items[end_line] else "";
            if (kind == .comment or kind == .blank) break;
            bracket_depth += tokenLineDelta(tokens, source, end_line - 1);
            const trimmed_current = std.mem.trimEnd(u8, current, " \t\r");
            continued = trimmed_current.len > 0 and trimmed_current[trimmed_current.len - 1] == '\\';
            has_backslash_continuation = has_backslash_continuation or continued;
            has_chain_call = has_chain_call or std.mem.startsWith(u8, std.mem.trimStart(u8, current, " \t"), ".");
            if (!next_exists or (!continuesStatement(next, bracket_depth, continued) and bracket_depth <= 0)) break;
            end_line += 1;
        }

        if (kind != .blank) {
            while (parents.items.len > 0 and nodes.items[parents.items[parents.items.len - 1]].indent >= indent) _ = parents.pop();
        }
        const parent = if (parents.items.len > 0) parents.items[parents.items.len - 1] else null;
        const last_line = lines.items[@min(end_line, lines.items.len) - 1];
        const opens_suite = opensSuite(last_line, kind);
        const delimiter = detectDelimiter(tokens, source, first_line, kind == .enumeration);
        try nodes.append(allocator, .{
            .kind = kind,
            .start_line = first_line,
            .end_line = @min(end_line, lines.items.len),
            .indent = indent,
            .parent = parent,
            .opens_suite = opens_suite,
            .delimiter = delimiter,
            .has_chain_call = has_chain_call,
            .has_backslash_continuation = has_backslash_continuation,
        });
        if (opens_suite or kind == .enumeration) try parents.append(allocator, nodes.items.len - 1);
        line_index = @min(end_line, lines.items.len);
    }
    return .{
        .tokens = tokens,
        .nodes = try nodes.toOwnedSlice(allocator),
        .containers = containers,
        .syntax_valid = validateDelimiters(tokens, source),
    };
}

/// 根据 token 类型建立嵌套容器树，枚举花括号按声明上下文单独分类。
fn parseContainers(allocator: Allocator, tokens: []const Token, source: []const u8) ![]ContainerNode {
    var containers: std.ArrayList(ContainerNode) = .empty;
    errdefer containers.deinit(allocator);
    var stack: [256]usize = undefined;
    var depth: usize = 0;
    for (tokens) |token| {
        if (token.kind != .punctuation) continue;
        const char = source[token.start];
        if (char == '(' or char == '[' or char == '{') {
            if (depth == stack.len) return error.NestingTooDeep;
            const kind: DelimiterKind = if (char == '(')
                .parentheses
            else if (char == '[')
                .array_literal
            else if (lineStartsWithEnum(tokens, source, token.line))
                .enum_body
            else
                .dictionary_literal;
            try containers.append(allocator, .{
                .kind = kind,
                .start_line = token.line,
                .end_line = token.line,
                .parent = if (depth > 0) stack[depth - 1] else null,
            });
            stack[depth] = containers.items.len - 1;
            depth += 1;
        } else if (char == ')' or char == ']' or char == '}') {
            if (depth == 0) continue;
            depth -= 1;
            containers.items[stack[depth]].end_line = token.line;
        }
    }
    return try containers.toOwnedSlice(allocator);
}

/// 判断花括号所在行的声明开头是否是 enum。
fn lineStartsWithEnum(tokens: []const Token, source: []const u8, line: usize) bool {
    for (tokens) |token| {
        if (token.line != line or token.kind == .comment) continue;
        if (token.kind == .keyword) return std.mem.eql(u8, source[token.start..token.end], "enum");
        if (token.kind == .annotation) continue;
        return false;
    }
    return false;
}

/// 检查括号是否正确配对；错误输入会让格式器保留原文，避免错误恢复破坏代码。
fn validateDelimiters(tokens: []const Token, source: []const u8) bool {
    var stack: [256]u8 = undefined;
    var depth: usize = 0;
    for (tokens) |token| {
        if (token.kind != .punctuation) continue;
        const char = source[token.start];
        if (char == '(' or char == '[' or char == '{') {
            if (depth == stack.len) return false;
            stack[depth] = char;
            depth += 1;
        } else if (char == ')' or char == ']' or char == '}') {
            if (depth == 0 or !matchingDelimiter(stack[depth - 1], char)) return false;
            depth -= 1;
        }
    }
    return depth == 0;
}

/// 判断开闭括号是否是同一类结构。
fn matchingDelimiter(open: u8, close: u8) bool {
    return (open == '(' and close == ')') or (open == '[' and close == ']') or (open == '{' and close == '}');
}

/// 根据 AST 语句类型识别花括号是字典值还是 enum 成员体。
fn detectDelimiter(tokens: []const Token, source: []const u8, line: usize, is_enum: bool) ?DelimiterKind {
    if (is_enum) {
        for (tokens) |token| {
            if (token.line == line and token.kind == .punctuation and source[token.start] == '{') return .enum_body;
        }
    }
    var stack: [256]u8 = undefined;
    var depth: usize = 0;
    for (tokens) |token| {
        if (token.line != line or token.kind == .string or token.kind == .comment or token.kind == .identifier or token.kind == .keyword or token.kind == .number or token.kind == .annotation) continue;
        const char = source[token.start];
        if (char == '(' or char == '[' or char == '{') {
            if (depth < stack.len) {
                stack[depth] = char;
                depth += 1;
            }
        } else if (char == ')' or char == ']' or char == '}') {
            if (depth > 0) depth -= 1;
        }
    }
    if (depth > 0) return switch (stack[0]) {
        '(' => .parentheses,
        '[' => .array_literal,
        '{' => .dictionary_literal,
        else => null,
    };
    return null;
}

/// 只处理指定源码行的词法单元，计算括号层级变化。
fn tokenLineDelta(tokens: []const Token, source: []const u8, line: usize) isize {
    var depth: isize = 0;
    for (tokens) |token| {
        if (token.line != line or token.kind == .string or token.kind == .comment) continue;
        const char = source[token.start];
        if (char == '(' or char == '[' or char == '{') {
            depth += 1;
        } else if (char == ')' or char == ']' or char == '}') {
            depth -= 1;
        }
    }
    return depth;
}

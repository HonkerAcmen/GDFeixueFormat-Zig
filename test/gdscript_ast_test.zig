const std = @import("std");
const ast = @import("gdscript_ast");

// 用例：关键字 lexer 应识别 Godot 4 的声明关键字，避免将其视为普通变量名。
test "Godot 4 声明关键字分类" {
    try std.testing.expect(ast.isKeyword("trait"));
    try std.testing.expect(ast.isKeyword("class_name"));
    try std.testing.expect(ast.isKeyword("signal"));
    try std.testing.expect(ast.isKeyword("await"));
    try std.testing.expect(ast.isKeyword("when"));
    try std.testing.expect(ast.isKeyword("yield"));
    try std.testing.expect(ast.isKeyword("PI"));
    try std.testing.expect(!ast.isKeyword("custom_name"));
}

// 用例：字典字面量和 enum 花括号拥有不同 AST 类型。
test "字典与枚举花括号分别解析" {
    const source = "var mapping = {\n\t\"a\": 1,\n}\nenum State {\n\tIDLE,\n}\n";
    const document = try ast.parse(std.testing.allocator, source);
    defer std.testing.allocator.free(document.tokens);
    defer std.testing.allocator.free(document.nodes);
    defer std.testing.allocator.free(document.containers);
    try std.testing.expectEqual(ast.DelimiterKind.dictionary_literal, document.nodes[0].delimiter.?);
    try std.testing.expectEqual(ast.NodeKind.enumeration, document.nodes[1].kind);
    try std.testing.expectEqual(ast.DelimiterKind.enum_body, document.nodes[1].delimiter.?);
    try std.testing.expectEqual(@as(usize, 2), document.containers.len);
    try std.testing.expectEqual(ast.DelimiterKind.dictionary_literal, document.containers[0].kind);
    try std.testing.expectEqual(ast.DelimiterKind.enum_body, document.containers[1].kind);
}

// 用例：注解、变量和多行续行被拆分为正确语句类别与跨度。
test "注解与反斜杠续行进入语句 AST" {
    const source = "@export_range(0, 10)\nvar speed: float\nvar total = 1 + \\\n\t2\n";
    const document = try ast.parse(std.testing.allocator, source);
    defer std.testing.allocator.free(document.tokens);
    defer std.testing.allocator.free(document.nodes);
    defer std.testing.allocator.free(document.containers);
    try std.testing.expectEqual(ast.NodeKind.annotation, document.nodes[0].kind);
    try std.testing.expectEqual(ast.NodeKind.variable, document.nodes[1].kind);
    try std.testing.expectEqual(@as(usize, 2), document.nodes[2].end_line - document.nodes[2].start_line);
    try std.testing.expect(document.nodes[2].has_backslash_continuation);
}

// 用例：字符串和注释中的分隔符不能被词法器当作真实括号。
test "分隔符词法识别忽略字符串与注释内容" {
    const source = "var text = \"{[()]#\" # }]\nvar data = {\"x\": 1}\n";
    const tokens = try ast.tokenize(std.testing.allocator, source);
    defer std.testing.allocator.free(tokens);
    var strings: usize = 0;
    var comments: usize = 0;
    var braces: usize = 0;
    for (tokens) |token| {
        switch (token.kind) {
            .string => strings += 1,
            .comment => comments += 1,
            .punctuation => {
                const character = source[token.start];
                if (character == '{' or character == '}') braces += 1;
            },
            else => {},
        }
    }
    try std.testing.expectEqual(@as(usize, 2), strings);
    try std.testing.expectEqual(@as(usize, 1), comments);
    try std.testing.expectEqual(@as(usize, 2), braces);
}

// 用例：缩进冒号创建语句父子关系，字典节点本身不会创建代码块作用域。
test "缩进代码块与字典容器保持不同的 AST 作用域" {
    const source = "func run():\n\tvar data = {\n\t\t\"x\": 1,\n\t}\n\tif data:\n\t\tpass\nvar root = {}\n";
    const document = try ast.parse(std.testing.allocator, source);
    defer std.testing.allocator.free(document.tokens);
    defer std.testing.allocator.free(document.nodes);
    defer std.testing.allocator.free(document.containers);
    try std.testing.expectEqual(ast.NodeKind.function, document.nodes[0].kind);
    try std.testing.expect(document.nodes[0].opens_suite);
    try std.testing.expectEqual(@as(?usize, 0), document.nodes[1].parent);
    try std.testing.expectEqual(ast.DelimiterKind.dictionary_literal, document.nodes[1].delimiter.?);
    try std.testing.expect(!document.nodes[1].opens_suite);
    try std.testing.expectEqual(ast.NodeKind.control_flow, document.nodes[2].kind);
    try std.testing.expectEqual(@as(?usize, 0), document.nodes[2].parent);
    try std.testing.expectEqual(@as(?usize, 2), document.nodes[3].parent);
    try std.testing.expectEqual(@as(?usize, null), document.nodes[4].parent);
}

// 用例：圆括号、字典、数组按实际嵌套关系构建容器父节点。
test "嵌套容器 AST 保留父节点关系" {
    const source = "var result = call({\n\"list\": [\n1,\n],\n})\n";
    const document = try ast.parse(std.testing.allocator, source);
    defer std.testing.allocator.free(document.tokens);
    defer std.testing.allocator.free(document.nodes);
    defer std.testing.allocator.free(document.containers);
    try std.testing.expectEqual(@as(usize, 3), document.containers.len);
    try std.testing.expectEqual(ast.DelimiterKind.parentheses, document.containers[0].kind);
    try std.testing.expectEqual(ast.DelimiterKind.dictionary_literal, document.containers[1].kind);
    try std.testing.expectEqual(ast.DelimiterKind.array_literal, document.containers[2].kind);
    try std.testing.expectEqual(@as(?usize, 0), document.containers[1].parent);
    try std.testing.expectEqual(@as(?usize, 1), document.containers[2].parent);
}

// 用例：完整 Godot 4 声明和注解关键字被词法器分类，普通名称仍是标识符。
test "注解声明与静态函数前缀正确分类" {
    try std.testing.expectEqual(ast.NodeKind.variable, ast.classifyLine("@export_range(1, 10) var speed: float"));
    try std.testing.expectEqual(ast.NodeKind.annotation, ast.classifyLine("@warning_ignore(\"unused\")"));
    try std.testing.expectEqual(ast.NodeKind.function, ast.classifyLine("static func update():"));
    try std.testing.expectEqual(ast.NodeKind.declaration, ast.classifyLine("trait Combatant"));
    try std.testing.expectEqual(ast.NodeKind.declaration, ast.classifyLine("class_name Combatant"));
    try std.testing.expectEqual(ast.NodeKind.constant, ast.classifyLine("const DEFAULT_SPEED = 1"));
}

// 用例：每种括号的未闭合及交叉配对错误都标记为不合法语法。
test "未闭合与错误配对括号标记为无效" {
    const sources = [_][]const u8{
        "var value = call(1\n",
        "var value = [1, 2\n",
        "var value = {\"key\": 1\n",
        "var value = ([1)}\n",
    };
    for (sources) |source| {
        const document = try ast.parse(std.testing.allocator, source);
        defer std.testing.allocator.free(document.tokens);
        defer std.testing.allocator.free(document.nodes);
        defer std.testing.allocator.free(document.containers);
        try std.testing.expect(!document.syntax_valid);
    }
}

// 用例：以点开头的成员调用被收进前一条表达式 AST。
test "链式调用记录在所属表达式节点中" {
    const source = "var value = make(\n1\n)\n.next()\n";
    const document = try ast.parse(std.testing.allocator, source);
    defer std.testing.allocator.free(document.tokens);
    defer std.testing.allocator.free(document.nodes);
    defer std.testing.allocator.free(document.containers);
    var chain_node_found = false;
    for (document.nodes) |node| {
        if (!node.has_chain_call) continue;
        chain_node_found = true;
        try std.testing.expectEqual(@as(usize, 4), node.end_line);
    }
    try std.testing.expect(chain_node_found);
}

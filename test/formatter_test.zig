const std = @import("std");
const formatter = @import("formatter");

// 用例：确认连续函数间始终保留两个空行。
test "相邻函数之间保留两个空行" {
    const actual = try formatter.formatText(std.testing.allocator, "func first():\n\tpass\nfunc second():\n\tpass\n");
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings("func first():\n\tpass\n\n\nfunc second():\n\tpass\n", actual);
}

// 用例：确认行尾空格、CRLF 和空格缩进都按统一规则处理。
test "清理行尾空格、统一 CRLF 并转换空格缩进" {
    const actual = try formatter.formatText(std.testing.allocator, "var value = 1  \r\n    var next = 2\r\n");
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings("var value = 1\n\tvar next = 2\n", actual);
}

// 用例：确认字符串内部的伪代码不会触发函数间距或缩进规则。
test "三引号字符串内容保持原样" {
    const source = "var text = \"\"\"\nfunc fake(a: int):\n\n  keep spacing\n\"\"\"\nfunc real():\n\tpass\n";
    const actual = try formatter.formatText(std.testing.allocator, source);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings("var text = \"\"\"\nfunc fake(a: int):\n\n  keep spacing\n\"\"\"\n\n\nfunc real():\n\tpass\n", actual);
}

// 用例：同一文件重复格式化时，第二次结果不再变化。
test "格式化结果可以重复运行而不再变化" {
    const once = try formatter.formatText(std.testing.allocator, "extends Node\nclass_name Example\nfunc run(a: int, b: int, c: int, d: int):\n\tpass\n");
    defer std.testing.allocator.free(once);
    const twice = try formatter.formatText(std.testing.allocator, once);
    defer std.testing.allocator.free(twice);
    try std.testing.expectEqualStrings(once, twice);
}

// 用例：AST 将嵌套字典和数组当作容器续行，而不是代码块缩进。
test "嵌套字典与数组按容器层级缩进" {
    const source = "var data = {\n\"outer\": {\n\"inner\": 1,\n},\n\"list\": [\n1,\n2,\n],\n}\n";
    const expected = "var data = {\n\t\"outer\": {\n\t\t\"inner\": 1,\n\t},\n\t\"list\": [\n\t\t1,\n\t\t2,\n\t],\n}\n";
    const actual = try formatter.formatText(std.testing.allocator, source);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
}

// 用例：注解紧贴其声明；函数和信号、枚举成员组采用确定的空行规则。
test "注解附着声明且信号枚举与函数分组" {
    const source = "@export_range(1, 10)\n@onready\nvar speed: int\nsignal changed\nenum State {\nIDLE,\n}\nfunc run():\n\tpass\n";
    const expected = "@export_range(1, 10)\n@onready\nvar speed: int\n\nsignal changed\n\nenum State {\n\tIDLE,\n}\n\n\nfunc run():\n\tpass\n";
    const actual = try formatter.formatText(std.testing.allocator, source);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
}

// 用例：空行不能拆开多行注解块与被修饰的函数。
test "函数注解块保持紧贴函数声明" {
    const source = "var count = 0\n@rpc\n\n@warning_ignore(\"unused_parameter\")\nfunc run():\n\tpass\n";
    const expected = "var count = 0\n\n\n@rpc\n@warning_ignore(\"unused_parameter\")\nfunc run():\n\tpass\n";
    const actual = try formatter.formatText(std.testing.allocator, source);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
}

// 用例：括号不匹配时保持源代码顺序，避免对无效输入进行部分重排。
test "无效括号结构保留原文本" {
    const source = "var data = {\n\"a\": [1, 2}\nfunc run():\n\tpass\n";
    const actual = try formatter.formatText(std.testing.allocator, source);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(source, actual);
}

// 用例：函数体结束后进入类级声明时仍保留两个空行。
test "函数体与后续类级变量之间有两个空行" {
    const actual = try formatter.formatText(std.testing.allocator, "func run():\n\tpass\nvar count = 0\n");
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings("func run():\n\tpass\n\n\nvar count = 0\n", actual);
}

// 用例：函数体内空行不结束 AST 缩进作用域，函数后仍按类级间距分隔。
test "函数体空行后回到类级作用域" {
    const actual = try formatter.formatText(std.testing.allocator, "func run():\n\tpass\n\n\treturn\nvar count = 0\n");
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings("func run():\n\tpass\n\n\treturn\n\n\nvar count = 0\n", actual);
}

// 用例：函数调用参数括号与内部字典、数组分别贡献各自的续行缩进。
test "括号内嵌套容器按 AST 父子层级缩进" {
    const source = "var result = create({\n\"data\": [\n1,\n],\n})\n";
    const expected = "var result = create({\n\t\t\t\"data\": [\n\t\t\t\t1,\n\t\t\t],\n})\n";
    const actual = try formatter.formatText(std.testing.allocator, source);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
}

// 用例：显式反斜杠续行与点开头的链式调用按表达式续行缩进。
test "反斜杠续行和链式调用增加两级缩进" {
    const source = "var result = get_first() + \\\n+get_second()\nvar node = get_node(\"A\")\n.call(\"B\")\n";
    const expected = "var result = get_first() + \\\n\t\t+get_second()\nvar node = get_node(\"A\")\n\t\t.call(\"B\")\n";
    const actual = try formatter.formatText(std.testing.allocator, source);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
}

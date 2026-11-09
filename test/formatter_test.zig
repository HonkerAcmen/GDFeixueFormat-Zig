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

// 用例：注解参数跨行时按照表达式续行缩进，注解与变量之间不插入空行。
test "多行注解参数与变量声明保持相邻" {
    const source = "@export_range(\n0,\n10\n)\nvar speed: float\n";
    const expected = "@export_range(\n\t\t0,\n\t\t10\n)\nvar speed: float\n";
    const actual = try formatter.formatText(std.testing.allocator, source);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
}

// 用例：同一行多个注解仍识别被修饰变量，不误判为独立注解块。
test "同一行注解与变量之间不插入空行" {
    const source = "@export @onready var target: Node\nvar count = 0\n";
    const actual = try formatter.formatText(std.testing.allocator, source);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(source, actual);
}

// 用例：多行函数调用结束后，链式调用仍使用两级续行缩进。
test "多行调用结束后的链式调用保持归属与缩进" {
    const source = "var node = get_node(\n\"Target\"\n)\n.call(\"activate\")\n";
    const expected = "var node = get_node(\n\t\t\"Target\"\n)\n\t\t.call(\"activate\")\n";
    const actual = try formatter.formatText(std.testing.allocator, source);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
}

// 用例：信号和枚举声明组前后均规范为一个空行，变量组继续保持紧凑。
test "信号枚举与变量组的空行规则稳定" {
    const source = "var first = 1\nsignal changed\nsignal reset\nenum State {\nIDLE,\n}\nvar last = 2\n";
    const expected = "var first = 1\n\nsignal changed\n\nsignal reset\n\nenum State {\n\tIDLE,\n}\n\nvar last = 2\n";
    const actual = try formatter.formatText(std.testing.allocator, source);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
}

// 用例：枚举标题注释和文档注释都与后续枚举声明保持相邻。
test "枚举前的标题注释和文档注释不留空行" {
    const source = "# --- 1. 枚举与常量 ---\n\nenum RightPanelBtnType {\n\tEQUIPMENT,\n\tITEM,\n\tMATERIAL\n}\n\n## 右键菜单选项（索引与 ContextMenu 的按钮对应）\n\nenum MenuOption {\n\tUSE,\n\tDROP,\n\tCANCEL\n}\n";
    const expected = "# --- 1. 枚举与常量 ---\nenum RightPanelBtnType {\n\tEQUIPMENT,\n\tITEM,\n\tMATERIAL\n}\n\n## 右键菜单选项（索引与 ContextMenu 的按钮对应）\nenum MenuOption {\n\tUSE,\n\tDROP,\n\tCANCEL\n}\n";
    const actual = try formatter.formatText(std.testing.allocator, source);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
}

// 用例：包含字典、枚举、注解、续行和函数边界的混合脚本重复格式化不再变化。
test "混合 AST 排版结果可以重复运行" {
    const source = "@export\nvar state = {\n\"value\": [\n1,\n],\n}\nsignal changed\nenum Mode {\nIDLE,\n}\nfunc run():\n\tvar node = make(\n\t\tstate\n\t)\n\t.call(\"go\")\n\treturn node\nvar done = true\n";
    const once = try formatter.formatText(std.testing.allocator, source);
    defer std.testing.allocator.free(once);
    const twice = try formatter.formatText(std.testing.allocator, once);
    defer std.testing.allocator.free(twice);
    try std.testing.expectEqualStrings(once, twice);
}

// 用例：显式反斜杠续行与点开头的链式调用按表达式续行缩进。
test "反斜杠续行和链式调用增加两级缩进" {
    const source = "var result = get_first() + \\\n+get_second()\nvar node = get_node(\"A\")\n.call(\"B\")\n";
    const expected = "var result = get_first() + \\\n\t\t+get_second()\nvar node = get_node(\"A\")\n\t\t.call(\"B\")\n";
    const actual = try formatter.formatText(std.testing.allocator, source);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
}

// 用例：控制流冒号开启代码块，不能将块头和首条语句分隔为空行。
test "控制流代码块首条语句紧贴冒号" {
    const source = "func hit() -> void:\n\tif hit_tween and hit_tween.is_running():\n\n\n\t\thit_tween.kill()\n";
    const expected = "func hit() -> void:\n\tif hit_tween and hit_tween.is_running():\n\t\thit_tween.kill()\n";
    const actual = try formatter.formatText(std.testing.allocator, source);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
}

// 用例：多行调用中的匿名回调保留代码块续行符和结束续行符。
test "匿名回调代码块续行符位置正确" {
    const source = "func setup() -> void:\n\tsetup_sub_panel(\n\t\t\tequipment_panel,\n\t\t\tdata,\n\t\t\tuser,\n\t\t\tfunc (slot_ui: SlotUI):\n\t\t\tif slot_ui.slot_landed.is_connected(_on_slot_landed):\n\t\t\t\tslot_ui.slot_landed.disconnect(_on_slot_landed)\n\t\t\tslot_ui.slot_landed.connect(_on_slot_landed)\n\n\t)\n";
    const expected = "func setup() -> void:\n\tsetup_sub_panel(\n\t\t\tequipment_panel,\n\t\t\tdata,\n\t\t\tuser,\n\t\t\tfunc (slot_ui: SlotUI):\n\t\t\tif slot_ui.slot_landed.is_connected(_on_slot_landed): \\\n\t\t\t\tslot_ui.slot_landed.disconnect(_on_slot_landed)\n\t\t\tslot_ui.slot_landed.connect(_on_slot_landed) \\\n\n\t)\n";
    const actual = try formatter.formatText(std.testing.allocator, source);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
}

// 用例：嵌套 if 的 return 保持在分支内部，后续装备转移语句回到回调层级。
test "匿名回调的 return 分支不增加冒号续行符" {
    const source = "func setup() -> void:\n\tsetup_sub_panel(\n\t\tpanel,\n\t\tfunc():\n\t\tif available_slot_index == -1:\n\t\t\tpush_warning(\"背包已满\")\n\t\t\treturn\n\t\tany_type_inventory_data.transfor_slot(curr_slot_index, available_slot_index, equipment_panel_inv_data)\n\t)\n";
    const expected = "func setup() -> void:\n\tsetup_sub_panel(\n\t\t\tpanel,\n\t\t\tfunc():\n\t\t\tif available_slot_index == -1:\n\t\t\t\tpush_warning(\"背包已满\")\n\t\t\t\treturn\n\t\t\tany_type_inventory_data.transfor_slot(curr_slot_index, available_slot_index, equipment_panel_inv_data) \\\n\t)\n";
    const actual = try formatter.formatText(std.testing.allocator, source);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
}

// 用例：完整右键菜单回调的 if 分支、return 和分支后续语句保持正确缩进。
test "完整右键菜单回调缩进结构正确" {
    const source = @embedFile("fixtures/right_click_menu_input.txt");
    const expected = @embedFile("fixtures/right_click_menu_expected.txt");
    const actual = try formatter.formatText(std.testing.allocator, source);
    defer std.testing.allocator.free(actual);
    try std.testing.expectEqualStrings(expected, actual);
    const twice = try formatter.formatText(std.testing.allocator, actual);
    defer std.testing.allocator.free(twice);
    try std.testing.expectEqualStrings(actual, twice);
}

// 回调参数的位置可以变化，但函数体及嵌套分支的相对缩进必须保持。
test "重复格式化保留匿名函数和提前返回分支的相对缩进" {
    const source =
        "func setup():\n" ++
        "\tSelfButton.new(\n" ++
        "\t\t\"卸下\",\n" ++
        "\t\tfunc():\n" ++
        "\t\t\t_menu_option_unuse()\n" ++
        "\t\t\t# 保留回调内注释\n" ++
        "\t\t\tvar available_slot_index = get_slot()\n" ++
        "\t\t\tif available_slot_index == -1:\n" ++
        "\t\t\t\tpush_warning(\"背包已满\")\n" ++
        "\t\t\t\treturn\n" ++
        "\t\t\ttransfor_slot()\\\n" ++
        "\t)\n";
    const once = try formatter.formatText(std.testing.allocator, source);
    defer std.testing.allocator.free(once);
    try std.testing.expect(std.mem.indexOf(u8, once, "\t\t\tfunc():\n\t\t\t\t_menu_option_unuse()") != null);
    try std.testing.expect(std.mem.indexOf(u8, once, "\t\t\t\tif available_slot_index == -1:\n\t\t\t\t\tpush_warning(\"背包已满\")\n\t\t\t\t\treturn\n\t\t\t\ttransfor_slot()") != null);
    var current = try std.testing.allocator.dupe(u8, once);
    defer std.testing.allocator.free(current);
    for (0..4) |_| {
        const next = try formatter.formatText(std.testing.allocator, current);
        errdefer std.testing.allocator.free(next);
        try std.testing.expectEqualStrings(once, next);
        std.testing.allocator.free(current);
        current = next;
    }
}

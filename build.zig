const std = @import("std");

/// 声明可执行程序、模块依赖及独立测试步骤。
pub fn build(b: *std.Build) void {
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    // 语法与声明模块被函数格式化流程复用，目录层只依赖文本格式化接口。
    const syntax = b.createModule(.{
        .root_source_file = b.path("src/gdscript_syntax.zig"),
        .target = target,
        .optimize = optimize,
    });
    const declarations = b.createModule(.{
        .root_source_file = b.path("src/declaration_formatter.zig"),
        .target = target,
        .optimize = optimize,
    });
    const comments = b.createModule(.{
        .root_source_file = b.path("src/comment_formatter.zig"),
        .target = target,
        .optimize = optimize,
    });
    const line_statistics = b.createModule(.{
        .root_source_file = b.path("src/line_statistics.zig"),
        .target = target,
        .optimize = optimize,
    });
    const functions = b.createModule(.{
        .root_source_file = b.path("src/function_formatter.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{.{ .name = "gdscript_syntax", .module = syntax }},
    });
    const formatter = b.createModule(.{
        .root_source_file = b.path("src/formatter.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "gdscript_syntax", .module = syntax },
            .{ .name = "declaration_formatter", .module = declarations },
            .{ .name = "function_formatter", .module = functions },
            .{ .name = "comment_formatter", .module = comments },
        },
    });
    const directory_formatter = b.createModule(.{
        .root_source_file = b.path("src/directory_formatter.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "formatter", .module = formatter },
            .{ .name = "line_statistics", .module = line_statistics },
        },
    });

    // CLI 只负责输入路径和结果提示，格式化文件委托给目录模块。
    const executable = b.addExecutable(.{
        .name = "GDFeixueFormat",
        .root_module = b.createModule(.{
            .root_source_file = b.path("src/main.zig"),
            .target = target,
            .optimize = optimize,
            .imports = &.{.{ .name = "directory_formatter", .module = directory_formatter }},
        }),
    });
    b.installArtifact(executable);

    // 测试模块集中导入各公开接口，测试代码与业务实现保持分离。
    const test_module = b.createModule(.{
        .root_source_file = b.path("test/all.zig"),
        .target = target,
        .optimize = optimize,
        .imports = &.{
            .{ .name = "formatter", .module = formatter },
            .{ .name = "directory_formatter", .module = directory_formatter },
            .{ .name = "gdscript_syntax", .module = syntax },
            .{ .name = "line_statistics", .module = line_statistics },
        },
    });
    const test_binary = b.addTest(.{ .root_module = test_module });
    const run_tests = b.addRunArtifact(test_binary);
    const test_step = b.step("test", "运行 GDFeixueFormat 的 Zig 测试用例");
    test_step.dependOn(&run_tests.step);

    const run_step = b.step("run", "运行 GDFeixueFormat");
    const run_command = b.addRunArtifact(executable);
    run_command.addPassthruArgs();
    run_step.dependOn(&run_command.step);
}

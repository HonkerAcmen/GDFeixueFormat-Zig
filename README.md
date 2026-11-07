# GDFeixueFormat

**English** | [简体中文](README.zh-CN.md)

GDFeixueFormat is a Zig command-line formatter for GDScript. It recursively scans a target directory, formats regular files ending in `.gd`, and writes changed content back to those files. It does not require the Godot editor or runtime.

## Project layout

```text
build.zig
src/
  main.zig                   Command-line entry point
  directory_formatter.zig    Directory traversal and file I/O
  formatter.zig              Text formatting flow and whitespace rules
  declaration_formatter.zig  class_name / extends normalization
  function_formatter.zig     Function parameter and callback formatting
  comment_formatter.zig     Function documentation normalization and wrapping
  line_statistics.zig       Formatted GDScript line counting
  gdscript_ast.zig          Tokenizer and statement/container AST
  gdscript_syntax.zig        Parenthesis matching and parameter parsing
test/
  all.zig                     Test suite entry point
  fixtures/                   Input and expected-output files for integration cases
  declaration_formatter_test.zig
  directory_formatter_test.zig
  formatter_test.zig
  function_formatter_test.zig
  line_statistics_test.zig
  gdscript_ast_test.zig
  gdscript_syntax_test.zig
  TEST_CASES.md              Complete inventory of named test cases
```

The text formatter does not perform file I/O, the directory module does not parse GDScript syntax, and the CLI does not contain formatting rules. `gdscript_ast.zig` tokenizes source and builds statement and nested-container nodes; the formatter uses those node kinds for indentation and spacing. Function documentation handling and line statistics remain separate modules. Tests live under `test/` and are grouped by responsibility. `test/fixtures/` contains larger callback input and expected-output samples. [`test/TEST_CASES.md`](test/TEST_CASES.md) lists every named case and its purpose (50 behavior cases plus the aggregate test entry point).

## Requirements

- Zig **0.17.1**. Other versions have not been validated for this project.
- A terminal environment supported by Zig. The project has currently been built and tested on macOS; native Linux and Windows builds have not been verified.
- Read and write access to the Godot project files you want to format.

Check the installed Zig version:

```sh
zig version
```

The expected output is `0.17.1`. If the `zig` command is unavailable, install Zig, add it to `PATH`, and reopen the terminal.

## Build from source

Run this command from the GDFeixueFormat project root:

```sh
zig build
```

The executable is created at:

```text
zig-out/bin/GDFeixueFormat
```

On Windows, the executable has an `.exe` suffix.

For an optimized build:

```sh
zig build -Doptimize=ReleaseFast
```

The default build is suitable for development. `zig-out/` and `.zig-cache/` are generated directories and should not be committed.

## Run the formatter

### Run the built executable

```sh
./zig-out/bin/GDFeixueFormat /path/to/godot/project
```

The argument is the directory to format. It can be absolute or relative to the current working directory. For example, when the terminal is already in the Godot project root:

```sh
/path/to/GDFeixueFormat/zig-out/bin/GDFeixueFormat .
```

### Run through the Zig build step

```sh
zig build run -- /path/to/godot/project
```

Arguments after `--` are passed to GDFeixueFormat. To format a directory relative to the current working directory:

```sh
zig build run -- .
```

This command starts in the GDFeixueFormat project directory, so `.` refers to the formatter project itself. Pass the Godot project path when formatting another project.

### Runtime behavior

- Recursively processes regular `.gd` files under the target directory.
- Skips files with other extensions.
- Writes only files whose contents change.
- Modifies files in place. Commit or back up your work before the first run.
- Does not currently provide a preview or dry-run mode. Review changes with `git diff` after running it.
- Prints the number of processed and changed GDScript files, followed by line totals across successfully processed files: total lines, code lines, standalone comment lines, and blank lines.
- Counts the formatted output, whether or not a file needed to be written. A final newline does not count as an extra line; inline comments belong to code lines.
- An unreadable target directory or file read/write failures produce a non-zero exit status.

## Test and check formatting

Run all Zig tests from the project root:

```sh
zig build test --summary all
```

The suite currently has 51 passing tests: 50 named behavior cases and the aggregate module-registration test. Coverage includes tokenization, statement and container AST construction, nested parent relationships, invalid delimiters, annotation and continuation handling, chained calls, callback branch and closing-parenthesis continuations, declaration and function formatting, documentation wrapping, declaration spacing, line statistics, idempotence, and recursive file selection. See the [complete test case inventory](test/TEST_CASES.md) for every case.

Check the source formatting with:

```sh
zig fmt --check build.zig src test
```

Before contributing, run:

```sh
zig fmt --check build.zig src test
zig build test --summary all
zig build
```

## Formatting rules

- Adjacent `class_name Example` and `extends Node` declarations become `class_name Example extends Node`, regardless of their input order.
- A `class_name` without an `extends` declaration remains on its own; the formatter does not invent a base type.
- Keeps two blank lines between functions.
- Keeps a section or documentation comment directly above an enum attached to that declaration, without inserting a blank line between them.
- Wraps ordinary function parameters when there are four or more.
- Always wraps `Callable` and anonymous callback parameters, regardless of count. Callback parameters are indented one additional level.
- Treats standalone `#` or `##` comment lines directly above a function as its documentation. It normalizes every documentation line to `##`, keeps the documentation block immediately above the function, and represents blank lines inside the block as `##`.
- Wraps function documentation at a maximum display width of 20 tab stops (80 columns, with a tab treated as four columns). The indentation and `##` prefix count toward that limit; common CJK wide characters count as two columns. Every wrapped continuation line starts with `##`.
- Builds statement nodes for functions, variables, constants, signals, enums, annotations, control-flow statements, and expressions. It recognizes Godot 4 keywords such as `class_name` and `trait` as keywords, not user identifiers.
- Distinguishes indentation-based suites introduced by `:` from dictionary literals and enum bodies. Nested arrays and dictionaries are represented as typed container nodes, so a dictionary brace never pushes a code-block indentation scope.
- Keeps annotation blocks attached to their declaration, including when blank lines occur between separate annotation lines. It keeps backslash-continued expressions together and indents their continuation lines by two levels.
- Tracks anonymous callback bodies inside multiline calls. It places a trailing `\\` where a callback suite or its final statement must continue the argument, skips blank lines when finding the call's closing `)` or `),`, and removes a redundant continuation marker from an `if` header whose branch ends with `return`, `continue`, or `break`.
- Groups leading-dot method calls with the preceding expression and formats the chain continuation at two indentation levels.
- Uses two blank lines around function boundaries. It uses one blank line to separate signal/enum declaration groups, keeps comments attached to enum declarations, and keeps annotations attached to the declarations they modify.
- If the tokenizer finds mismatched or unclosed parentheses, brackets, or braces, the formatter leaves that file's text unchanged instead of applying a partial rewrite.
- Removes trailing whitespace, converts CRLF to LF, and changes space-only indentation to tabs.
- Preserves the contents of multiline strings.

### Function documentation and line-count implementation

When the text formatter reaches a function declaration, it inspects the lines already collected immediately before it. If those lines contain a standalone comment block, it removes that block from its original position, normalizes and wraps it, then appends it immediately before the function header. The regular function-spacing rule runs before the documentation is appended, so the required blank separation stays before the documentation while there is no blank line between the documentation and the function. This keeps comments associated with their function when spacing is normalized.

The documentation formatter removes the leading `#` or `##`, trims surrounding horizontal whitespace, and emits a consistent `##` prefix. Empty lines within the comment block become `##` lines. It walks the UTF-8 text by code point rather than byte, estimates display width (including common CJK wide characters), and starts a continuation line before the 80-column limit would be exceeded. A word boundary is preferred when the input contains spaces; long unbroken text is split at a character boundary.

The GDScript parser first tokenizes identifiers, keywords, annotations, strings, comments, operators, delimiters, and explicit continuation markers. Strings and comments are single lexical units, so bracket characters inside them do not affect parsing. It then forms statement nodes with source line ranges, indentation parents, suite boundaries, and continuation metadata. A second pass matches nested delimiters and creates typed container nodes for parentheses, arrays, dictionaries, and enum bodies. Container nodes retain parent relationships. A `{` therefore gets its meaning from the surrounding declaration and expression context instead of being treated as a generic scope marker. This is a lightweight formatter-oriented AST, not a complete Godot language semantic AST; it records the structure needed by the current formatting rules.

The formatter walks these statement nodes in source order. For a multiline container it counts the active parent containers on each line: arrays, dictionaries, and enum bodies add one tab level, while parenthesized expression continuations add two. Closing lines return to the enclosing node's indentation. Explicit `\\` continuations and leading-dot call chains also stay with their owning expression and use the two-level continuation style. Inside a multiline anonymous callback, the formatter tracks the callback body and nested `if` branch so it can distinguish a branch that returns from one that continues normally. It adds or removes continuation markers accordingly and looks past blank lines to recognize the enclosing call's closing delimiter. Enum group spacing also accounts for a leading comment, keeping that comment directly attached to its enum. These choices follow the [Godot GDScript style guide](https://docs.godotengine.org/en/latest/tutorials/scripting/gdscript/gdscript_styleguide.html) for container and expression continuations. The parser also tracks which declaration owns an annotation block so empty lines can be removed from the middle of the relationship without moving the annotation away from its declaration.

After each `.gd` file is successfully formatted, the directory formatter counts the formatted text and adds it to the directory totals. A line is classified as blank when it contains only whitespace, as a comment when its first non-whitespace character is `#`, and as code otherwise. Thus inline comments count with their code line. The CLI prints the totals after the file-processing summary. Counting the formatted result means reported line counts match the files as they will exist after the formatter completes.

Example input:

```gdscript
extends Node2D
class_name Example

func attack(a: int, b: int, c: int, d: int) -> void:
 pass
```

Formatted output:

```gdscript
class_name Example extends Node2D


func attack(
 a: int,
 b: int,
 c: int,
 d: int
) -> void:
 pass
```

## Integrate with a Godot project

### Option 1: Keep the formatter separate

This is useful for trying the tool locally without changing the Godot project.

1. Build GDFeixueFormat once:

   ```sh
   cd /path/to/GDFeixueFormat
   zig build
   ```

2. Pass the Godot project directory to the executable:

   ```sh
   /path/to/GDFeixueFormat/zig-out/bin/GDFeixueFormat /path/to/godot/project
   ```

3. Review the modified scripts in the Godot project:

   ```sh
   cd /path/to/godot/project
   git diff -- '*.gd'
   ```

Each developer machine needs Zig and must build a native executable, or obtain an executable built for its operating system and processor architecture.

### Option 2: Include it in the Godot project repository

For a shared team workflow, include the formatter source in the Godot repository. You can add it as a Git submodule or vendor the source under a dedicated directory, for example `tools/GDFeixueFormat/`:

```sh
git submodule add <GDFeixueFormat-repository-url> tools/GDFeixueFormat
git submodule update --init --recursive
```

Replace `<GDFeixueFormat-repository-url>` with the repository URL you want to use.

Then build and run it from the Godot project root:

```sh
cd tools/GDFeixueFormat
zig build test --summary all
zig build
cd ../..
tools/GDFeixueFormat/zig-out/bin/GDFeixueFormat .
```

If you vendor the source at a different location, adjust the executable path accordingly. Avoid hard-coding a developer-specific absolute path into the project.

### Add it to project scripts or CI

After including the source, add the following steps to the project’s task runner, editor tooling, pre-commit workflow, or CI job:

1. Install the supported Zig version on the runner.
2. Run `zig build test --summary all` in the GDFeixueFormat directory.
3. Run `zig build` in that directory.
4. Run the built executable with the Godot project root as its argument.
5. Decide whether the workflow should keep the formatted changes or reject unformatted input.

For a workflow that checks formatting without retaining changes, run the formatter and then check whether tracked GDScript files changed:

```sh
tools/GDFeixueFormat/zig-out/bin/GDFeixueFormat .
git diff --exit-code -- '*.gd'
```

A non-zero `git diff` result means formatting changed files. GDFeixueFormat currently formats in place; it does not have a check-only mode.

## Troubleshooting

### `zig: command not found`

The terminal cannot find Zig through `PATH`. Install Zig 0.17.1, add it to `PATH`, and verify with `zig version`.

### `zig-out/bin/GDFeixueFormat` does not exist

The build has not completed successfully. Run `zig build` from the GDFeixueFormat project root before running the program.

### The formatter reports file errors

Check that the target directory exists and that the current user can read and write its `.gd` files. The formatter continues processing other scripts after an individual file fails, then exits with a non-zero status.

### Many files changed

The formatter writes changes directly to `.gd` files. Review them with `git diff -- '*.gd'`. Restore any unexpected changes and add a regression test before changing formatting behavior.

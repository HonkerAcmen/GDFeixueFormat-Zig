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
  gdscript_syntax.zig        Parenthesis matching and parameter parsing
test/
  all.zig                     Test suite entry point
  declaration_formatter_test.zig
  directory_formatter_test.zig
  formatter_test.zig
  function_formatter_test.zig
  gdscript_syntax_test.zig
```

The text formatter does not perform file I/O, the directory module does not parse GDScript syntax, and the CLI does not contain formatting rules. Tests live under `test/` and are grouped by responsibility.

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
- Prints the number of changed GDScript files. An unreadable target directory or file read/write failures produce a non-zero exit status.

## Test and check formatting

Run all Zig tests from the project root:

```sh
zig build test --summary all
```

The tests cover declaration normalization, preserving a class without a base type, parameter thresholds, callbacks, nested expressions, string contents, function spacing, indentation and line endings, idempotence, and recursive file selection.

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
- Wraps ordinary function parameters when there are four or more.
- Always wraps `Callable` and anonymous callback parameters, regardless of count. Callback parameters are indented one additional level.
- Removes trailing whitespace, converts CRLF to LF, and changes space-only indentation to tabs.
- Preserves the contents of multiline strings.

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

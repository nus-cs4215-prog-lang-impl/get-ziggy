const std = @import("std");
const Allocator = std.mem.Allocator;
const json = std.json;
const fs = std.fs;
const process = std.process;
const path = std.fs.path;

// Assuming types.zig and compiler.zig are in the same directory or accessible via build path
const types = @import("vm/types.zig");
const compiler = @import("vm/compiler.zig");

const JsonAstNode = types.JsonAstNode;
const Compiler = compiler.Compiler;

pub fn main() !void {
    // 1. Initialize allocator
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit(); // Ensure allocator is cleaned up
    const allocator = gpa.allocator();

    // 2. Get command line arguments
    const args = try process.argsAlloc(allocator);
    defer process.argsFree(allocator, args);

    if (args.len < 2) {
        std.debug.print("Usage: <program> <path_to_rust_source_file>\n", .{});
        return process.exit(1);
    }

    const rust_file_path = args[1];
    // Construct a temporary path for the JSON AST output
    // Note: This creates the JSON file in the current working directory.
    // Consider using std.os.tmpdir() for a more robust temporary location.
    const temp_json_path_buffer = try std.fmt.allocPrint(allocator, "{s}.json", .{rust_file_path});
    defer allocator.free(temp_json_path_buffer);
    const temp_json_path = temp_json_path_buffer;

    // Ensure the temporary JSON file is deleted upon exiting this scope
    defer {
        // Ignore error during deletion, as the file might not exist if python script failed
        fs.cwd().deleteFile(temp_json_path) catch |err| {
            std.debug.print("Warning: Failed to delete temporary file '{s}': {any}\n", .{ temp_json_path, err });
        };
        std.debug.print("Deleted temporary file: {s}\n", .{temp_json_path});
    }

    // 3. Execute the Python parser script
    std.debug.print("Running Python parser for: {s}\n", .{rust_file_path});
    const python_script_path = "parser/gen_parse_tree.py"; // Relative path to the script
    const python_args = &[_][]const u8{
        "python3", // or just "python" depending on the system
        python_script_path,
        "-i",
        rust_file_path,
        "-o",
        temp_json_path,
    };

    var child = process.Child.init(python_args, allocator);
    child.stdout_behavior = .Ignore; // Ignore stdout from the script
    child.stderr_behavior = .Pipe; // Capture stderr for error reporting

    const term = try child.spawnAndWait();

    // Check if the script executed successfully
    if (term.Exited != 0) {
        std.debug.print("Python parser script failed with code: {d}\n", .{term.Exited});
        // Read and print stderr from the script
        if (child.stderr) |stderr_pipe| {
            var reader = stderr_pipe.reader();
            var buf: [1024]u8 = undefined;
            while (reader.read(&buf)) |_| {} else |err| {
                if (err != error.EndOfStream) {
                    std.debug.print("Error reading stderr from python script: {any}\n", .{err});
                }
            }
        }
        return process.exit(1);
    }
    std.debug.print("Python parser finished successfully. Temporary AST at: {s}\n", .{temp_json_path});

    // 4. Read the generated temporary JSON file content
    std.debug.print("Reading generated AST from file: {s}\n", .{temp_json_path});
    const json_bytes = blk: {
        const file = try fs.cwd().openFile(temp_json_path, .{});
        defer file.close();
        break :blk try file.readToEndAlloc(allocator, 1024 * 1024 * 10); // Limit file size to 10MB
    };
    defer allocator.free(json_bytes);

    // 5. Parse the JSON into JsonAstNode
    std.debug.print("Parsing JSON AST...\n", .{});
    const parsed_node = blk: {
        break :blk try json.parseFromSlice(JsonAstNode, allocator, json_bytes, .{
            .ignore_unknown_fields = true, // Be lenient if JSON has extra fields
        });
    };
    // IMPORTANT: The parsed_node owns memory allocated during parsing (strings, nested nodes).
    // It needs to be deinitialized AFTER the compiler is done with it.
    // We'll pass a pointer to the parsed node's value to the compiler.
    defer parsed_node.deinit(); // Ensure parsed AST resources are freed

    // 6. Initialize the Compiler
    var comp = Compiler.init(allocator);
    defer comp.deinit(); // Ensure compiler resources are freed

    // 7. Compile the parsed AST
    std.debug.print("Compiling AST...\n", .{});
    comp.compileProgram(&parsed_node.value) catch |err| {
        std.debug.print("Compilation error: {any}\n", .{err});
        // Print details if it's a specific compile error we can inspect
        // if (err == types.CompileErrors.SomeSpecificError) { ... }
        return process.exit(1);
    };

    // 8. Print the compiled instructions
    std.debug.print("Compilation successful. Output:\n", .{});
    try comp.printCompiledMicrocode();

    std.debug.print("Done.\n", .{});
}

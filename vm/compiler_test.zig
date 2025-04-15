const std = @import("std");
const testing = std.testing;
const json = std.json;
const types = @import("types.zig");
const compile = @import("compiler.zig");

const Value = types.Value;
const UnaryOperator = types.UnaryOperator;
const BinaryOperator = types.BinaryOperator;
const LogicalOperator = types.LogicalOperator;
const Param = types.Param;
const CompileErrors = types.CompileErrors;
// const AstNode = types.AstNode; // Removed
const JsonAstNode = types.JsonAstNode;
const Instruction = types.Instruction;
const Compiler = compile.Compiler;

test "compile simple program: let x = 1 + 2; x" {
    // Setup
    var compiler = Compiler.init(testing.allocator);
    defer compiler.deinit();

    // Create AST for: let x = 1 + 2; x using JsonAstNode
    var one = JsonAstNode{ .lit = .{ .val = .{ .Int = 1 } } };
    var two = JsonAstNode{ .lit = .{ .val = .{ .Int = 2 } } };
    var add_expr = JsonAstNode{ .arith = .{ .sym = .{ .arith = .Add }, .first = &one, .second = &two } };
    var var_decl = JsonAstNode{ .assign = .{ .nam = "x", .value = &add_expr, .is_mut = false } }; // Assuming 'let' implies immutable by default
    var load_x = JsonAstNode{ .nam = "x" };

    var statements_slice = [_]*JsonAstNode{
        &var_decl,
        &load_x,
    };

    const program = JsonAstNode{ .seq = .{ .stmts = &statements_slice } };

    // Compile the program
    try compiler.compileProgram(&program);

    // Verify the generated instructions
    const instructions = compiler.instructions.items;

    std.debug.print("Generated Instructions (simple program):\n", .{});
    try compiler.printCompiledMicrocode(); // Use the existing print function

    // Basic length check (adjust as needed based on exact instruction sequence)
    // Ldc 1, Ldc 2, Binop Add, Assign "x", Pop, Ld "x", Done
    try testing.expectEqual(@as(usize, 7), instructions.len);

    // Check specific instructions
    try testing.expectEqual(Instruction{ .Ldc = .{ .Int = 1 } }, instructions[0]);
    try testing.expectEqual(Instruction{ .Ldc = .{ .Int = 2 } }, instructions[1]);
    try testing.expectEqual(Instruction{ .Binop = .{ .arith = .Add } }, instructions[2]);

    // For string comparisons, we need to check the tag and then the string content
    switch (instructions[3]) {
        .Assign => |name| try testing.expectEqualStrings("x", name),
        else => return error.TestUnexpectedInstructionType,
    }

    // Pop instruction after assignment statement
    try testing.expectEqual(Instruction.Pop, instructions[4]);

    switch (instructions[5]) {
        .Ld => |name| try testing.expectEqualStrings("x", name),
        else => return error.TestUnexpectedInstructionType,
    }

    try testing.expectEqual(Instruction.Done, instructions[6]);
}

test "fn_decl_test" {
    // Setup
    var compiler = Compiler.init(testing.allocator);
    defer compiler.deinit();

    var body = JsonAstNode{ .lit = .{ .val = .{ .Int = 2 } } };
    var fn_decl = JsonAstNode{ .fun = .{
        .nam = "foo",
        .params = &([_]Param{}),
        .body = &body,
    } };

    var statements_slice = [_]*JsonAstNode{&fn_decl};

    const program = JsonAstNode{ .seq = .{ .stmts = &statements_slice } };
    // Compile the program
    try compiler.compileProgram(&program);

    // Verify the generated instructions
    std.debug.print("Generated Instructions (fn_decl_test):\n", .{});
    try compiler.printCompiledMicrocode();
    // TODO: Should pop?
    // Expected: Goto, Ldc 2, Reset, Ldf, Assign "foo", Pop, Done
    const instructions = compiler.instructions.items;
    try testing.expectEqual(@as(usize, 6), instructions.len);
    try testing.expectEqual(Instruction{ .Goto = 3 }, instructions[0]); // Jump over body
    try testing.expectEqual(Instruction{ .Ldc = .{ .Int = 2 } }, instructions[1]); // Function body
    try testing.expectEqual(Instruction.Reset, instructions[2]); // Return from function
    try testing.expectEqual(Instruction{ .Ldf = .{ .params = &[_]Param{}, .addr = 1 } }, instructions[3]); // Load function object
    try testing.expectEqualStrings("foo", instructions[4].Assign); // Assign function to name "foo"
    try testing.expectEqual(Instruction.Done, instructions[5]); // Program end
}

test "logical_test" {
    // Setup
    var compiler = Compiler.init(testing.allocator);
    defer compiler.deinit();

    var left_true = JsonAstNode{ .lit = .{ .val = .{ .Bool = true } } };
    var right_false = JsonAstNode{ .lit = .{ .val = .{ .Bool = false } } };
    var log_and = JsonAstNode{ .logic = .{ .sym = .{ .logic = .And }, .first = &left_true, .second = &right_false } };
    var log_or = JsonAstNode{ .logic = .{ .sym = .{ .logic = .Or }, .first = &left_true, .second = &right_false } };

    var statements_slice = [_]*JsonAstNode{
        &log_and,
        &log_or,
    };

    const program = JsonAstNode{ .seq = .{ .stmts = &statements_slice } };
    // Compile the program
    try compiler.compileProgram(&program);

    // Verify the generated instructions
    std.debug.print("Generated Instructions (logical_test):\n", .{});
    try compiler.printCompiledMicrocode();

    // Expected for AND (true && false): Ldc true, Jof L4, Pop, Ldc false, Pop, Ldc true, Jof L9, Goto L11, Pop, Ldc false, Done
    // Expected for OR (true || false): Ldc true, Jof L4, Goto L7, Pop, Ldc false, Pop, Done
    // Combined:
    // 0: Ldc true  (and left)
    // 1: Jof 4     (and jump if false)
    // 2: Pop       (and pop true)
    // 3: Ldc false (and right)
    // --- end and --- (result is false)
    // 4: Pop       (pop result of 'and' statement)
    // 5: Ldc true  (or left)
    // 6: Jof 8     (or jump if false)
    // 7: Goto 11   (or jump to end if true)
    // --- jump target for Jof ---
    // 8: Pop       (or pop false)
    // 9: Ldc false (or right)
    // --- end or --- (result is true because left was true)
    // --- jump target for Goto ---
    // 10: Done
    const instructions = compiler.instructions.items;
    try testing.expectEqual(@as(usize, 11), instructions.len); // Adjust count based on actual output

    // And part
    try testing.expectEqual(Instruction{ .Ldc = .{ .Bool = true } }, instructions[0]);
    try testing.expectEqual(Instruction{ .Jof = 4 }, instructions[1]);
    try testing.expectEqual(Instruction.Pop, instructions[2]);
    try testing.expectEqual(Instruction{ .Ldc = .{ .Bool = false } }, instructions[3]);
    // Pop result of 'and'
    try testing.expectEqual(Instruction.Pop, instructions[4]);
    // Or part
    try testing.expectEqual(Instruction{ .Ldc = .{ .Bool = true } }, instructions[5]);
    try testing.expectEqual(Instruction{ .Jof = 8 }, instructions[6]); // Jumps to instruction 9 (Ldc false) if left is false
    try testing.expectEqual(Instruction{ .Goto = 10 }, instructions[7]); // Jumps to instruction 10 (Done) if left is true
    try testing.expectEqual(Instruction.Pop, instructions[8]); // Pop the false from left if we jumped here
    try testing.expectEqual(Instruction{ .Ldc = .{ .Bool = false } }, instructions[9]);
    // Done
    try testing.expectEqual(Instruction.Done, instructions[10]);
}

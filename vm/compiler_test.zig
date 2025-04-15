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
const AstNode = types.AstNode;
const JsonAstNode = types.JsonAstNode;
const Instruction = types.Instruction;
const Compiler = compile.Compiler;

test "compile simple program: let x = 1 + 2; x" {
    // Setup
    var compiler = Compiler.init(testing.allocator);
    defer compiler.deinit();

    // Create AST for: let x = 1 + 2; x
    var one = AstNode{ .Literal = .{ .Int = 1 } };
    var two = AstNode{ .Literal = .{ .Int = 2 } };
    var add_expr = AstNode{ .BinaryOp = .{ .op = BinaryOperator{ .arith = .Add }, .left = &one, .right = &two } };
    var var_decl = AstNode{ .VarDecl = .{ .name = "x", .value = &add_expr } };
    var load_x = AstNode{ .Name = "x" };

    var statements_slice = [_]*AstNode{
        &var_decl,
        &load_x,
    };

    const program = AstNode{ .Sequence = .{ .statements = &statements_slice } };

    // Compile the program
    try compiler.compileProgram(&program);

    // Verify the generated instructions
    const instructions = compiler.instructions.items;

    std.debug.print("Generated Instructions:\n", .{});
    for (compiler.instructions.items, 0..) |instr, i| {
        std.debug.print("{d}: ", .{i});
        switch (instr) {
            .Ld => |name| std.debug.print("Ld(\"{s}\")\n", .{name}),
            .Assign => |name| std.debug.print("Assign(\"{s}\")\n", .{name}),
            // NOTE: Add specific formatting for other instructions if needed
            // e.g., EnterScope, Ldf
            else => std.debug.print("{any}\n", .{instr}),
        }
    }
    try testing.expectEqual(@as(usize, 7), instructions.len);

    // Check specific instructions
    try testing.expectEqual(Instruction{ .Ldc = .{ .Int = 1 } }, instructions[0]);
    try testing.expectEqual(Instruction{ .Ldc = .{ .Int = 2 } }, instructions[1]);
    try testing.expectEqual(Instruction{ .Binop = BinaryOperator{ .arith = .Add } }, instructions[2]);

    // For string comparisons, we need to check the tag and then the string content
    switch (instructions[3]) {
        .Assign => |name| try testing.expectEqualStrings("x", name),
        else => return error.TestUnexpectedInstructionType,
    }

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

    var body = AstNode{ .Literal = .{ .Int = 2 } };
    var fn_decl = AstNode{ .FnDecl = .{
        .name = "foo",
        .params = &([_]Param{}),
        .body = &body,
    } };

    var statements_slice = [_]*AstNode{&fn_decl};

    const program = AstNode{ .Sequence = .{ .statements = &statements_slice } };
    // Compile the program
    try compiler.compileProgram(&program);

    // Verify the generated instructions
    try compiler.printCompiledMicrocode();
}

test "logical_test" {
    // Setup
    var compiler = Compiler.init(testing.allocator);
    defer compiler.deinit();

    var left = AstNode{ .Literal = .{ .Bool = true } };
    var right = AstNode{ .Literal = .{ .Bool = false } };
    var log_and = AstNode{ .LogicalOp = .{ .op = .And, .left = &left, .right = &right } };
    var log_or = AstNode{ .LogicalOp = .{ .op = .Or, .left = &left, .right = &right } };

    var statements_slice = [_]*AstNode{
        &log_and,
        &log_or,
    };

    const program = AstNode{ .Sequence = .{ .statements = &statements_slice } };
    // Compile the program
    try compiler.compileProgram(&program);

    // Verify the generated instructions
    try compiler.printCompiledMicrocode();
}

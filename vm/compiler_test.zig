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
const Instruction = types.Instruction;
const InstructionData = types.InstructionData;
const Compiler = compile.Compiler;

test "serialize AstNode to JSON" {
    var arena = std.heap.ArenaAllocator.init(testing.allocator);
    defer arena.deinit();
    const allocator = arena.allocator();

    // Test case 1: Literal node (integer)
    {
        const node = AstNode{
            .Literal = .{ .Int = 42 },
        };

        var string = std.ArrayList(u8).init(allocator);
        defer string.deinit();

        try json.stringify(node, .{}, string.writer());

        const result = string.items;
        try testing.expect(std.mem.indexOf(u8, result, "\"Literal\"") != null);
        try testing.expect(std.mem.indexOf(u8, result, "\"Int\"") != null);
        try testing.expect(std.mem.indexOf(u8, result, "42") != null);
    }

    // Test case 2: Name node
    {
        const name = try allocator.dupe(u8, "testVar");
        const node = AstNode{
            .Name = name,
        };

        var string = std.ArrayList(u8).init(allocator);
        defer string.deinit();

        try json.stringify(node, .{}, string.writer());

        const result = string.items;
        try testing.expect(std.mem.indexOf(u8, result, "\"Name\"") != null);
        try testing.expect(std.mem.indexOf(u8, result, "\"testVar\"") != null);
    }

    // Test case 3: Binary operation node
    {
        const left = try allocator.create(AstNode);
        left.* = AstNode{ .Literal = .{ .Int = 10 } };

        const right = try allocator.create(AstNode);
        right.* = AstNode{ .Literal = .{ .Int = 20 } };

        const node = AstNode{
            .BinaryOp = .{
                .op = .Add,
                .left = left,
                .right = right,
            },
        };

        var string = std.ArrayList(u8).init(allocator);
        defer string.deinit();

        try json.stringify(node, .{}, string.writer());

        const result = string.items;
        try testing.expect(std.mem.indexOf(u8, result, "\"BinaryOp\"") != null);
        try testing.expect(std.mem.indexOf(u8, result, "\"Add\"") != null);
        try testing.expect(std.mem.indexOf(u8, result, "\"left\"") != null);
        try testing.expect(std.mem.indexOf(u8, result, "\"right\"") != null);
        try testing.expect(std.mem.indexOf(u8, result, "10") != null);
        try testing.expect(std.mem.indexOf(u8, result, "20") != null);
    }
}

test "parse JSON to AstNode" {
    // var arena = std.heap.ArenaAllocator.init(testing.allocator);
    // defer arena.deinit();
    // const allocator = arena.allocator();

    // Test case 1: Parse a literal node
    {
        const json_str =
            \\{"Literal":{"Int":42}}
        ;

        const item = try json.parseFromSlice(AstNode, testing.allocator, json_str, .{});
        defer item.deinit();
        std.debug.print("Parsed item: {}\n", .{item.value});

        // try testing.expectEqual(AstNode.AstData.Literal, std.meta.activeTag(node.data));
        // try testing.expectEqual(Value.Int, std.meta.activeTag(node.data.Literal));
        // try testing.expectEqual(@as(i64, 42), node.data.Literal.Int);
    }

    // Test case 2: Parse a name node
    // {
    //     const json_str =
    //         \\{"data":{"Name":"testVar"}}
    //     ;

    //     var parser = json.Parser.init(allocator, false);
    //     defer parser.deinit();

    //     var tree = try parser.parse(json_str);
    //     defer tree.deinit();

    //     const node = try AstNode.parse(allocator, tree.root);
    //     defer node.deinit(allocator);

    //     try testing.expectEqual(AstNode.AstData.Name, std.meta.activeTag(node.data));
    //     try testing.expectEqualStrings("testVar", node.data.Name);
    // }

    // // Test case 3: Parse a binary operation
    // {
    //     const json_str =
    //         \\{
    //         \\  "data": {
    //         \\    "BinaryOp": {
    //         \\      "op": "Add",
    //         \\      "left": {"data":{"Literal":{"Int":10}}},
    //         \\      "right": {"data":{"Literal":{"Int":20}}}
    //         \\    }
    //         \\  }
    //         \\}
    //     ;

    //     var parser = json.Parser.init(allocator, false);
    //     defer parser.deinit();

    //     var tree = try parser.parse(json_str);
    //     defer tree.deinit();

    //     const node = try AstNode.parse(allocator, tree.root);
    //     defer node.deinit(allocator);

    //     try testing.expectEqual(AstNode.AstData.BinaryOp, std.meta.activeTag(node.data));
    //     try testing.expectEqual(BinaryOperator.Add, node.data.BinaryOp.op);

    //     const left = node.data.BinaryOp.left;
    //     try testing.expectEqual(AstNode.AstData.Literal, std.meta.activeTag(left.data));
    //     try testing.expectEqual(@as(i64, 10), left.data.Literal.Int);

    //     const right = node.data.BinaryOp.right;
    //     try testing.expectEqual(AstNode.AstData.Literal, std.meta.activeTag(right.data));
    //     try testing.expectEqual(@as(i64, 20), right.data.Literal.Int);
    // }
}

// test "round trip AstNode to JSON and back" {
//     var arena = std.heap.ArenaAllocator.init(testing.allocator);
//     defer arena.deinit();
//     const allocator = arena.allocator();
//
//     // Create a complex AST node
//     const left = try allocator.create(AstNode);
//     left.* = AstNode{ .data = .{ .Literal = .{ .Int = 10 } } };
//
//     const right = try allocator.create(AstNode);
//     const var_name = try allocator.dupe(u8, "x");
//     right.* = AstNode{ .data = .{ .Name = var_name } };
//
//     const original_node = AstNode{
//         .data = .{ .BinaryOp = .{
//             .op = .Add,
//             .left = left,
//             .right = right,
//         } },
//     };
//
//     // Serialize to JSON
//     var string = std.ArrayList(u8).init(allocator);
//     defer string.deinit();
//     try json.stringify(original_node, .{}, string.writer());
//
//     // Parse back to AstNode
//     var parser = json.Parser.init(allocator, false);
//     defer parser.deinit();
//
//     var tree = try parser.parse(string.items);
//     defer tree.deinit();
//
//     const parsed_node = try AstNode.parse(allocator, tree.root);
//     defer parsed_node.deinit(allocator);
//
//     // Verify the round-trip conversion
//     try testing.expectEqual(AstNode.AstData.BinaryOp, std.meta.activeTag(parsed_node.data));
//     try testing.expectEqual(BinaryOperator.Add, parsed_node.data.BinaryOp.op);
//
//     const parsed_left = parsed_node.data.BinaryOp.left;
//     try testing.expectEqual(AstNode.AstData.Literal, std.meta.activeTag(parsed_left.data));
//     try testing.expectEqual(@as(i64, 10), parsed_left.data.Literal.Int);
//
//     const parsed_right = parsed_node.data.BinaryOp.right;
//     try testing.expectEqual(AstNode.AstData.Name, std.meta.activeTag(parsed_right.data));
//     try testing.expectEqualStrings("x", parsed_right.data.Name);
// }

test "compile simple program: let x = 1 + 2; x" {
    // Setup
    var compiler = Compiler.init(testing.allocator);
    defer compiler.deinit();

    // Create AST for: let x = 1 + 2; x
    var one = AstNode{ .Literal = .{ .Int = 1 } };
    var two = AstNode{ .Literal = .{ .Int = 2 } };
    var add_expr = AstNode{ .BinaryOp = .{ .op = .Add, .left = &one, .right = &two } };
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

    // Expected instruction sequence:
    // 0: Ldc(Int=1)
    // 1: Ldc(Int=2)
    // 2: Binop(Add)
    // 3: Assign("x")
    // 4: Pop       // because we pop the value of of the finished statement
    // 5: Ld("x")
    // 6: Done

    try compiler.printCompiledMicrocode();

    try testing.expectEqual(@as(usize, 7), instructions.len);

    // Check specific instructions
    try testing.expectEqual(InstructionData{ .Ldc = .{ .Int = 1 } }, instructions[0].data);
    try testing.expectEqual(InstructionData{ .Ldc = .{ .Int = 2 } }, instructions[1].data);
    try testing.expectEqual(InstructionData{ .Binop = .Add }, instructions[2].data);

    // For string comparisons, we need to check the tag and then the string content
    switch (instructions[3].data) {
        .Assign => |name| try testing.expectEqualStrings("x", name),
        else => return error.TestUnexpectedInstructionType,
    }
    switch (instructions[4].data) {
        .Pop => _ = void,
        else => return error.TestUnexpectedInstructionType,
    }
    switch (instructions[5].data) {
        .Ld => |name| try testing.expectEqualStrings("x", name),
        else => return error.TestUnexpectedInstructionType,
    }

    try testing.expectEqual(InstructionData.Done, instructions[6].data);
}

test "conditional_compile" {
    // Setup
    var compiler = Compiler.init(testing.allocator);
    defer compiler.deinit();

    var one = AstNode{ .Literal = .{ .Int = 1 } };
    var two = AstNode{ .Literal = .{ .Int = 2 } };
    var add_expr = AstNode{ .BinaryOp = .{ .op = .Add, .left = &one, .right = &two } };
    var var_decl = AstNode{ .VarDecl = .{ .name = "x", .value = &add_expr } };
    var load_x = AstNode{ .Name = "x" };

    var statements_slice = [_]*AstNode{
        &var_decl,
        &load_x,
    };

    var condition = AstNode{ .Literal = .{ .Bool = true } };
    var cons = AstNode{ .Sequence = .{ .statements = &statements_slice } };
    var alt = AstNode{ .Sequence = .{ .statements = &statements_slice } };
    var cond_stmt = AstNode{ .Conditional = .{
        .condition = &condition,
        .cons = &cons,
        .alt = &alt,
    } };
    var statements_slice_2 = [_]*AstNode{
        &load_x,
        &cond_stmt,
        &var_decl,
    };

    const program = AstNode{ .Sequence = .{ .statements = &statements_slice_2 } };
    // Compile the program
    try compiler.compileProgram(&program);

    // Verify the generated instructions
    try compiler.printCompiledMicrocode();

    // Expected instruction sequence:
    // Generated Instructions:
    // 0: Ld("x")
    // 1: Pop
    // 2: Ldc(types.Value{ .Bool = true })
    // 3: Jof(11)
    // 4: Ldc(types.Value{ .Int = 1 })
    // 5: Ldc(types.Value{ .Int = 2 })
    // 6: Binop(types.BinaryOperator.Add)
    // 7: Assign("x")
    // 8: Pop
    // 9: Ld("x")
    // 10: Goto(17)
    // 11: Ldc(types.Value{ .Int = 1 })
    // 12: Ldc(types.Value{ .Int = 2 })
    // 13: Binop(types.BinaryOperator.Add)
    // 14: Assign("x")
    // 15: Pop
    // 16: Ld("x")
    // 17: Pop
    // 18: Ldc(types.Value{ .Int = 1 })
    // 19: Ldc(types.Value{ .Int = 2 })
    // 20: Binop(types.BinaryOperator.Add)
    // 21: Assign("x")
    // 22: Done

}

test "while_loop_comp" {
    // Setup
    var compiler = Compiler.init(testing.allocator);
    defer compiler.deinit();

    var zero = AstNode{ .Literal = .{ .Int = 0 } };
    var decl = AstNode{ .VarDecl = .{ .name = "x", .value = &zero } };

    var x = AstNode{ .Name = "x" };
    var one = AstNode{ .Literal = .{ .Int = 1 } };
    var add_expr = AstNode{ .BinaryOp = .{ .op = .Add, .left = &x, .right = &one } };
    var var_pp = AstNode{ .VarDecl = .{ .name = "x", .value = &add_expr } };

    var ten = AstNode{ .Literal = .{ .Int = 10 } };
    var comp_expr = AstNode{ .BinaryOp = .{ .op = .Lt, .left = &x, .right = &ten } };
    var body_stmt = [_]*AstNode{
        &var_pp,
    };
    var body = AstNode{ .Sequence = .{ .statements = &body_stmt } };
    var while_loop = AstNode{ .WhileLoop = .{ .condition = &comp_expr, .body = &body } };

    var statements_slice = [_]*AstNode{
        &decl,
        &while_loop,
    };

    const program = AstNode{ .Sequence = .{ .statements = &statements_slice } };
    // Compile the program
    try compiler.compileProgram(&program);

    // Verify the generated instructions
    try compiler.printCompiledMicrocode();
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

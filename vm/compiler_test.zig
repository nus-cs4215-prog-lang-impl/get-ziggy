const std = @import("std");
const testing = std.testing;
const json = std.json;
const types = @import("types.zig");
const compile = @import("compiler.zig");

const LiteralVal = types.LiteralVal; // Use LiteralVal
const TypeName = types.TypeName; // Import TypeName
const UnaryOperator = types.UnaryOperator;
const BorrowOperator = types.BorrowOperator;
const BorrowAttr = types.BorrowAttr;
const BinaryOperator = types.BinaryOperator;
const LogicalOperator = types.LogicalOperator;
const Param = types.Param;
const CompileErrors = types.CompileErrors;
// const AstNode = types.AstNode; // Removed
const JsonAstNode = types.JsonAstNode;
const Instruction = types.Instruction;
const Compiler = compile.Compiler;

// Helper to compare LiteralVal, needed because []const u8 cannot be compared directly with expectEqual
fn expectLiteralValEqual(expected: LiteralVal, actual: LiteralVal) !void {
    try testing.expectEqual(expected.type_name, actual.type_name);
    try testing.expectEqualStrings(expected.val, actual.val);
}

// Helper to compare Param slices
fn expectParamsEqual(expected: []const Param, actual: []const Param) !void {
    try testing.expectEqual(expected.len, actual.len);
    for (expected, actual) |exp, act| {
        try testing.expectEqualStrings(exp.nam, act.nam);
        try testing.expectEqual(exp.type_name, act.type_name);
    }
}

test "compile simple program: let x = 1 + 2; x" {
    // Setup
    var compiler = Compiler.init(testing.allocator);
    defer compiler.deinit();

    // Create AST for: let x = 1 + 2; x using JsonAstNode with LiteralVal
    var one = JsonAstNode{ .lit = .{ .val = "1", .type_name = .i32 } };
    var two = JsonAstNode{ .lit = .{ .val = "2", .type_name = .i32 } };
    var add_expr = JsonAstNode{ .arith = .{ .sym = .{ .arith = .Add }, .first = &one, .second = &two } };
    var var_decl = JsonAstNode{ .assign = .{ .nam = "x", .val = &add_expr, .is_mut = false, .type_name = .i32 } }; // Assuming 'let' implies immutable by default
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
    // Ldc "1", Ldc "2", Binop Add, Assign "x", Pop, Ld "x", Done
    try testing.expectEqual(@as(usize, 7), instructions.len);

    // Check specific instructions
    // Use helper for LiteralVal comparison
    try expectLiteralValEqual(LiteralVal{ .val = "1", .type_name = .i32 }, instructions[0].Ldc);
    try expectLiteralValEqual(LiteralVal{ .val = "2", .type_name = .i32 }, instructions[1].Ldc);
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

    // Update body to use LiteralVal
    var body = JsonAstNode{ .lit = .{ .val = "2", .type_name = .i32 } };
    var fn_decl = JsonAstNode{ .fun = .{
        .nam = "foo",
        .params = &([_]Param{}),
        .body = &body,
        .return_type = .i32,
    } };

    var statements_slice = [_]*JsonAstNode{&fn_decl};

    const program = JsonAstNode{ .seq = .{ .stmts = &statements_slice } };
    // Compile the program
    try compiler.compileProgram(&program);

    // Verify the generated instructions
    std.debug.print("Generated Instructions (fn_decl_test):\n", .{});
    try compiler.printCompiledMicrocode();
    // Expected: Goto, Ldc "2", Reset, Ldf, Assign "foo", Pop, Done
    // Sequence rule: pop result of statement unless it's the last one.
    // Here, fn_decl is the last statement, so its result (Assign "foo") is not popped.
    // Assign instruction itself doesn't leave value, but Ldf does before Assign.
    // Let's re-evaluate:
    // 0: Goto 3 (jump over body)
    // 1: Ldc "2" (body)
    // 2: Reset (end of body)
    // --- Jump target ---
    // 3: Ldf { params: [], addr: 1 } (create function object)
    // 4: Assign "foo" (assign function object to name)
    // --- End of sequence --- (last statement was assign, no pop needed)
    // 5: Done
    const instructions = compiler.instructions.items;
    try testing.expectEqual(@as(usize, 6), instructions.len);
    try testing.expectEqual(Instruction{ .Goto = 3 }, instructions[0]); // Jump over body
    // Use helper for LiteralVal comparison
    try expectLiteralValEqual(LiteralVal{ .val = "2", .type_name = .i32 }, instructions[1].Ldc); // Function body
    try testing.expectEqual(Instruction.Reset, instructions[2]); // Return from function
    // Check Ldf params and addr separately if direct comparison fails due to slice pointer
    try testing.expectEqual(@as(usize, 1), instructions[3].Ldf.addr);
    try testing.expectEqual(@as(usize, 0), instructions[3].Ldf.params.len);
    // try testing.expectEqual(Instruction{ .Ldf = .{ .params = &[_]Param{}, .addr = 1 } }, instructions[3]); // Load function object
    try testing.expectEqualStrings("foo", instructions[4].Assign); // Assign function to name "foo"
    try testing.expectEqual(Instruction.Done, instructions[5]); // Program end
}

test "fn apply test" {
    // Setup
    var compiler = Compiler.init(testing.allocator);
    defer compiler.deinit();

    // AST for:
    // fn add(a: i32, b: i32) -> i32 { a + b }
    // add(5, 3)

    // Function Body: a + b
    var load_a = JsonAstNode{ .nam = "a" };
    var load_b = JsonAstNode{ .nam = "b" };
    var add_body = JsonAstNode{ .arith = .{ .sym = .{ .arith = .Add }, .first = &load_a, .second = &load_b } };

    // Function Declaration
    var params = [_]Param{
        .{ .nam = "a", .type_name = .i32 },
        .{ .nam = "b", .type_name = .i32 },
    };
    var fn_decl = JsonAstNode{ .fun = .{
        .nam = "add",
        .params = &params,
        .body = &add_body,
        .return_type = .i32,
    } };

    // Function Call Arguments
    var five = JsonAstNode{ .lit = .{ .val = "5", .type_name = .i32 } };
    var three = JsonAstNode{ .lit = .{ .val = "3", .type_name = .i32 } };
    var args_slice = [_]*JsonAstNode{ &five, &three };

    // Function Call
    var fn_call = JsonAstNode{
        .app = .{
            .nam = "add",
            .args = &args_slice,
        },
    };

    // Program Sequence
    var statements_slice = [_]*JsonAstNode{
        &fn_decl,
        &fn_call,
    };
    const program = JsonAstNode{ .seq = .{ .stmts = &statements_slice } };

    // Compile
    try compiler.compileProgram(&program);

    // Verify Instructions
    std.debug.print("Generated Instructions (fn apply test):\n", .{});
    try compiler.printCompiledMicrocode();

    // Expected Instructions:
    // 0: Goto 5      (Skip function body)
    // --- Function Body ---
    // 1: Ld "a"
    // 2: Ld "b"
    // 3: Binop Add
    // 4: Reset       (Return from function)
    // --- After Body ---
    // 5: Ldf { params: [a, b], addr: 1 } (Load function object)
    // 6: Assign "add" (Assign function to name)
    // 7: Pop         (Pop result of assignment statement)
    // --- Function Call ---
    // 8: Ld "add"    (Load function object to call) <- Swapped order with args
    // 9: Ldc "5"     (Load arg 1)
    // 10: Ldc "3"     (Load arg 2)
    // 11: Call 2     (Call function with 2 args)
    // --- End ---
    // 12: Done        (Program end, result of call is on stack)

    const instructions = compiler.instructions.items;
    try testing.expectEqual(@as(usize, 13), instructions.len);

    // Function Definition Part
    try testing.expectEqual(Instruction{ .Goto = 5 }, instructions[0]);
    try testing.expectEqualStrings("a", instructions[1].Ld);
    try testing.expectEqualStrings("b", instructions[2].Ld);
    try testing.expectEqual(Instruction{ .Binop = .{ .arith = .Add } }, instructions[3]);
    try testing.expectEqual(Instruction.Reset, instructions[4]);
    // Check Ldf
    try testing.expectEqual(@as(usize, 1), instructions[5].Ldf.addr);
    try expectParamsEqual(&params, instructions[5].Ldf.params);
    // Check Assign
    try testing.expectEqualStrings("add", instructions[6].Assign);
    // Check Pop
    try testing.expectEqual(Instruction.Pop, instructions[7]);

    // Function Call Part
    try testing.expectEqualStrings("add", instructions[8].Ld); // Load function first
    try expectLiteralValEqual(LiteralVal{ .val = "5", .type_name = .i32 }, instructions[9].Ldc); // Arg 1
    try expectLiteralValEqual(LiteralVal{ .val = "3", .type_name = .i32 }, instructions[10].Ldc); // Arg 2
    try testing.expectEqual(Instruction{ .Call = .{ .arity = 2 } }, instructions[11]); // Call

    // End
    try testing.expectEqual(Instruction.Done, instructions[12]);
}

test "logical_test" {
    // Setup
    var compiler = Compiler.init(testing.allocator);
    defer compiler.deinit();

    // Update literals to use LiteralVal, using String for bools as TypeName lacks Bool
    var left_true = JsonAstNode{ .lit = .{ .val = "true", .type_name = .Bool } };
    var right_false = JsonAstNode{ .lit = .{ .val = "false", .type_name = .Bool } };
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
    // 0: Ldc "true" (and left)
    // 1: Jof 4      (and jump if false)
    // 2: Pop        (and pop true)
    // 3: Ldc "false" (and right)
    // --- end and --- (result is false)
    // 4: Pop        (pop result of 'and' statement)
    // 5: Ldc "true" (or left)
    // 6: Jof 9      (or jump if false to instruction 9) -> Should be Jof 8
    // 7: Goto 10    (or jump to end if true - instruction 10) -> Should be Goto 10
    // --- jump target for Jof ---
    // 8: Pop        (or pop false)
    // 9: Ldc "false" (or right)
    // --- end or --- (result is true because left was true)
    // --- jump target for Goto ---
    // 10: Done
    const instructions = compiler.instructions.items;
    try testing.expectEqual(@as(usize, 11), instructions.len); // Adjust count based on actual output

    // And part
    try expectLiteralValEqual(LiteralVal{ .val = "true", .type_name = .Bool }, instructions[0].Ldc);
    try testing.expectEqual(Instruction{ .Jof = 4 }, instructions[1]);
    try testing.expectEqual(Instruction.Pop, instructions[2]);
    try expectLiteralValEqual(LiteralVal{ .val = "false", .type_name = .Bool }, instructions[3].Ldc);
    // Pop result of 'and'
    try testing.expectEqual(Instruction.Pop, instructions[4]);
    // Or part
    try expectLiteralValEqual(LiteralVal{ .val = "true", .type_name = .Bool }, instructions[5].Ldc);
    try testing.expectEqual(Instruction{ .Jof = 8 }, instructions[6]); // Jumps to instruction 8 (Pop) if left is false
    try testing.expectEqual(Instruction{ .Goto = 10 }, instructions[7]); // Jumps to instruction 10 (Done) if left is true
    try testing.expectEqual(Instruction.Pop, instructions[8]); // Pop the false from left if we jumped here
    try expectLiteralValEqual(LiteralVal{ .val = "false", .type_name = .Bool }, instructions[9].Ldc);
    // Done
    try testing.expectEqual(Instruction.Done, instructions[10]);
}

test "borrow immutable test" {
    // Setup
    var compiler = Compiler.init(testing.allocator);
    defer compiler.deinit();

    // AST for: let x: i32 = 5; let y = &x; y
    var five = JsonAstNode{ .lit = .{ .val = "5", .type_name = .i32 } };
    var decl_x = JsonAstNode{ .assign = .{ .nam = "x", .val = &five, .is_mut = false, .type_name = .i32 } };
    var load_x_for_borrow = JsonAstNode{ .nam = "x" };
    var borrow_x = JsonAstNode{ .borrow = .{ .sym = .{ .borrow = .Borrow }, .first = &load_x_for_borrow } };
    var decl_y = JsonAstNode{ .assign = .{ .nam = "y", .val = &borrow_x, .is_mut = false, .type_name = null } }; // Type inferred
    var load_y = JsonAstNode{ .nam = "y" };

    var statements_slice = [_]*JsonAstNode{
        &decl_x,
        &decl_y,
        &load_y,
    };
    const program = JsonAstNode{ .seq = .{ .stmts = &statements_slice } };

    // Compile
    try compiler.compileProgram(&program);

    // Verify Instructions
    std.debug.print("Generated Instructions (borrow immutable test):\n", .{});
    try compiler.printCompiledMicrocode();

    // Expected:
    // 0: Ldc 5       (value for x)
    // 1: Assign "x"
    // 2: Pop         (result of assign)
    // 3: Ld "x"       (value for borrow)
    // 4: Unop Borrow (create immutable borrow)
    // 5: Assign "y"
    // 6: Pop         (result of assign)
    // 7: Ld "y"       (final expression)
    // 8: Done
    const instructions = compiler.instructions.items;
    try testing.expectEqual(@as(usize, 9), instructions.len);

    try expectLiteralValEqual(LiteralVal{ .val = "5", .type_name = .i32 }, instructions[0].Ldc);
    try testing.expectEqualStrings("x", instructions[1].Assign);
    try testing.expectEqual(Instruction.Pop, instructions[2]);
    try testing.expectEqualStrings("x", instructions[3].Ld);
    try testing.expectEqual(Instruction{ .Unop = .{ .borrow = .Borrow } }, instructions[4]);
    try testing.expectEqualStrings("y", instructions[5].Assign);
    try testing.expectEqual(Instruction.Pop, instructions[6]);
    try testing.expectEqualStrings("y", instructions[7].Ld);
    try testing.expectEqual(Instruction.Done, instructions[8]);
}

test "borrow mutable test" {
    // Setup
    var compiler = Compiler.init(testing.allocator);
    defer compiler.deinit();

    // AST for: let mut x: i32 = 5; let y = &mut x; y
    var five = JsonAstNode{ .lit = .{ .val = "5", .type_name = .i32 } };
    var decl_x = JsonAstNode{ .assign = .{ .nam = "x", .val = &five, .is_mut = true, .type_name = .i32 } }; // x is mutable
    var load_x_for_borrow = JsonAstNode{ .nam = "x" };
    var borrow_mut_x = JsonAstNode{ .borrow_mut = .{ .sym = .{ .borrow_mut = .BorrowAttr }, .first = &load_x_for_borrow } };
    var decl_y = JsonAstNode{ .assign = .{ .nam = "y", .val = &borrow_mut_x, .is_mut = false, .type_name = null } }; // Type inferred
    var load_y = JsonAstNode{ .nam = "y" };

    var statements_slice = [_]*JsonAstNode{
        &decl_x,
        &decl_y,
        &load_y,
    };
    const program = JsonAstNode{ .seq = .{ .stmts = &statements_slice } };

    // Compile
    try compiler.compileProgram(&program);

    // Verify Instructions
    std.debug.print("Generated Instructions (borrow mutable test):\n", .{});
    try compiler.printCompiledMicrocode();

    // Expected:
    // 0: Ldc 5       (value for x)
    // 1: Assign "x"
    // 2: Pop         (result of assign)
    // 3: Ld "x"       (value for borrow)
    // 4: Unop BorrowMut (create mutable borrow)
    // 5: Assign "y"
    // 6: Pop         (result of assign)
    // 7: Ld "y"       (final expression)
    // 8: Done
    const instructions = compiler.instructions.items;
    try testing.expectEqual(@as(usize, 9), instructions.len);

    try expectLiteralValEqual(LiteralVal{ .val = "5", .type_name = .i32 }, instructions[0].Ldc);
    try testing.expectEqualStrings("x", instructions[1].Assign);
    try testing.expectEqual(Instruction.Pop, instructions[2]);
    try testing.expectEqualStrings("x", instructions[3].Ld);
    try testing.expectEqual(Instruction{ .Unop = .{ .borrow_mut = .BorrowAttr } }, instructions[4]);
    try testing.expectEqualStrings("y", instructions[5].Assign);
    try testing.expectEqual(Instruction.Pop, instructions[6]);
    try testing.expectEqualStrings("y", instructions[7].Ld);
    try testing.expectEqual(Instruction.Done, instructions[8]);
}

test "borrow mutable fail" {
    // Setup
    var compiler = Compiler.init(testing.allocator);
    defer compiler.deinit();

    // AST for: let x: i32 = 5; let y = &mut x; y
    // This should fail type checking because x is not mutable.
    var five = JsonAstNode{ .lit = .{ .val = "5", .type_name = .i32 } };
    var decl_x = JsonAstNode{ .assign = .{ .nam = "x", .val = &five, .is_mut = false, .type_name = .i32 } }; // x is NOT mutable
    var load_x_for_borrow = JsonAstNode{ .nam = "x" };
    var borrow_mut_x = JsonAstNode{ .borrow_mut = .{ .sym = .{ .borrow_mut = .BorrowAttr }, .first = &load_x_for_borrow } };
    var decl_y = JsonAstNode{ .assign = .{ .nam = "y", .val = &borrow_mut_x, .is_mut = false, .type_name = null } };
    var load_y = JsonAstNode{ .nam = "y" };

    var statements_slice = [_]*JsonAstNode{
        &decl_x,
        &decl_y,
        &load_y,
    };
    const program = JsonAstNode{ .seq = .{ .stmts = &statements_slice } };

    // Compile and expect a type error
    // The error should come from type_checker.check called within compileProgram
    // Assuming the type checker returns MutationOfImmutable when trying to mutably borrow an immutable variable.
    // NOTE: The exact error might depend on the implementation details of the type checker's borrow checking.
    // Adjust the expected error if necessary.
    std.debug.print("Expecting type error for mutable borrow of immutable variable...\n", .{});
    try testing.expectError(CompileErrors.MutationOfImmutable, compiler.compileProgram(&program));
}

const std = @import("std");
const Allocator = std.mem.Allocator;

// Primitive Types
// We differentiate betweeen the primitive types in rust and zig
// by using PascalCase for the Rust types
const Value = union(enum) {
    // TODO: Might want to add char as primitive
    Int: i64,
    Float: f64,
    Bool: bool,
    String: []const u8, // TODO: Rust doesn't really have Strings as primitives, so this might not be needed
    Undefined: void,
};

// Enum Types
const UnaryOperator = enum {
    Negate, // -
    Not, // !
};

const BinaryOperator = enum {
    Add, // +
    Sub, // -
    Mul, // *
    Div, // /
    Mod, // %
    Eq, // ==
    Neq, // !=
    Lt, // <
    Lte, // <=
    Gt, // >
    Gte, // >=
};

const LogicalOperator = enum {
    And, // &&
    Or, // ||
};

const Param = struct {
    name: []const u8,
    // TODO: type_info?
};

// Explicit Error Set
const CompileErrors = error{
    UnimplementedAstNode,
    OutOfMemory,
};

// AstNode Declaration
const AstNode = struct {
    data: AstData,
    const AstData = union(enum) {
        Literal: Value,
        Name: []const u8,
        App: struct { func: *AstNode, args: []*AstNode },
        LogicalOp: struct { op: LogicalOperator, left: *AstNode, right: *AstNode },
        BinaryOp: struct { op: BinaryOperator, left: *AstNode, right: *AstNode },
        UnaryOp: struct { op: UnaryOperator, operand: *AstNode },
        Lambda: struct { params: []Param, body: *AstNode },
        Sequence: struct { statements: []*AstNode },
        Block: struct { body: *AstNode },
        VarDecl: struct { name: []const u8, value: *AstNode },
        Assignment: struct { name: []const u8, value: *AstNode },
        Conditional: struct { condition: *AstNode, cons: *AstNode, alt: *AstNode },
        FnDecl: struct { name: []const u8, params: []Param, body: *AstNode },
        Return: struct { value: ?*AstNode },
        WhileLoop: struct { condition: *AstNode, body: *AstNode },
    };
};

// Instruction Declaration
const Instruction = struct {
    data: InstructionData,
    const InstructionData = union(enum) {
        Ldc: Value, // Load constant
        Ld: []const u8, // Load variable by name
        Assign: []const u8, // Assign to variable name
        Unop: UnaryOperator,
        Binop: BinaryOperator,
        Pop: void, // Pop top value from stack
        Jof: usize, // Jump if false: target instruction address/index
        Goto: usize, // Unconditional jump: target instruction address/index
        EnterScope: struct { locals: [][]const u8 }, // Names declared in the scope
        ExitScope: void,
        Ldf: struct { params: []Param, addr: usize }, // Load function: Addr of function body start
        Call: struct { arity: usize }, // Function call
        TailCall: struct { arity: usize }, // Tail call optimization
        Reset: void, // Return from function / unwind stack frame
        Done: void, // Program termination
    };
};

const Compiler = struct {
    alloc: Allocator,
    instructions: std.ArrayList(Instruction),

    pub fn init(alloc: Allocator) Compiler {
        return .{
            .alloc = alloc,
            .instructions = std.ArrayList(Instruction).init(alloc),
        };
    }

    pub fn deinit(self: *Compiler) void {
        // TODO: Need to deallocate strings stored within instructions if they were allocated by the compiler
        self.instructions.deinit();
    }

    // Helper to add an instruction and return its index
    fn addInstr(self: *Compiler, instruction_data: Instruction.InstructionData) !usize {
        const index = self.instructions.items.len;
        try self.instructions.append(.{ .data = instruction_data });
        return index;
    }

    // Helper to get the index of the next instruction to be added
    fn nextInstrAddr(self: *const Compiler) usize {
        return self.instructions.items.len;
    }

    // Helper to patch a jump instruction later
    fn patchJump(self: *Compiler, instr_index: usize, target_addr: usize) void {
        switch (self.instructions.items[instr_index].data) {
            .Jof => |*addr| addr.* = target_addr,
            .Goto => |*addr| addr.* = target_addr,
            else => @panic("Attempting to patch non-jump instruction"),
        }
    }

    // Helper to compile binary operations
    fn compileBinaryOp(self: *Compiler, left: *const AstNode, right: *const AstNode, op: BinaryOperator) CompileErrors!void {
        try self.compile(left);
        try self.compile(right);
        _ = try self.addInstr(.{ .Binop = op });
    }

    // NOTE: CompileErrors!void is a hack to get around "unable to resolve inferred error set":
    // https://github.com/ziglang/zig/issues/763
    pub fn compile(self: *Compiler, node: *const AstNode) CompileErrors!void {
        switch (node.data) {
            .Literal => |val| {
                _ = try self.addInstr(.{ .Ldc = val });
            },
            .Name => |name| {
                _ = try self.addInstr(.{ .Ld = name });
            },
            .BinaryOp => |op_data| {
                try self.compileBinaryOp(op_data.left, op_data.right, op_data.op);
            },
            .UnaryOp => |op_data| {
                try self.compile(op_data.operand);
                _ = try self.addInstr(.{ .Unop = op_data.op });
            },
            .Sequence => |seq_data| {
                if (seq_data.statements.len == 0) {
                    // TODO: this needs to throw an error?
                    // Empty sequence evaluates to Undefined? Or is disallowed?
                    // Let's push Undefined for now.
                    // _ = try self.addInstr(.{ .Ldc = .{ .Undefined = .{} } });
                } else {
                    var i: usize = 0;
                    while (i < seq_data.statements.len) : (i += 1) {
                        try self.compile(seq_data.statements[i]);
                        // Pop result unless it's the last statement
                        if (i < seq_data.statements.len - 1) {
                            _ = try self.addInstr(.Pop);
                        }
                    }
                }
            },
            .Block => |block_data| {
                // TODO: Need a pass to collect local variable names for the scope
                const empty_locals = &.{};
                _ = try self.addInstr(.{ .EnterScope = .{ .locals = empty_locals } });
                try self.compile(block_data.body);
                _ = try self.addInstr(.ExitScope);
            },
            .VarDecl => |decl_data| {
                try self.compile(decl_data.value);
                _ = try self.addInstr(.{ .Assign = decl_data.name });
                // TODO: Assign instruction should leave the assigned value on the stack
                // according to some language semantics, or pop it.
                // If VarDecl itself shouldn't leave a value, add Pop here.
                // For now, assume Assign leaves value.
            },
            .Assignment => |assign_data| {
                try self.compile(assign_data.value);
                _ = try self.addInstr(.{ .Assign = assign_data.name });
                // TODO: Similar to VarDecl, assume Assign leaves the value on stack.
            },

            // --- More Complex Cases (GPT Placeholders) ---

            // .App => |app_data| {
            //     // 1. Compile arguments (right to left or left to right? Depends on VM convention)
            //     //    Let's assume left-to-right evaluation for args.
            //     for (app_data.args) |arg| {
            //         try self.compile(arg);
            //     }
            //     // 2. Compile the function expression
            //     try self.compile(app_data.func);
            //     // 3. Add Call instruction
            //     _ = try self.addInstr(.{ .Call = .{ .arity = app_data.args.len } });
            // },

            // .Conditional => |cond_data| {
            //     // 1. Compile condition
            //     try self.compile(cond_data.condition);
            //     // 2. Add Jof (Jump if False) instruction, store its index
            //     const jof_idx = try self.addInstr(.{ .Jof = 0 }); // Placeholder address 0
            //     // 3. Compile 'then' branch (cons)
            //     try self.compile(cond_data.cons);
            //     // 4. Add Goto instruction (to jump over 'else'), store its index
            //     const goto_idx = try self.addInstr(.{ .Goto = 0 }); // Placeholder address 0
            //     // 5. Get address for start of 'else' branch (alt)
            //     const alt_addr = self.nextInstrAddr();
            //     // 6. Patch Jof to jump to alt_addr
            //     self.patchJump(jof_idx, alt_addr);
            //     // 7. Compile 'else' branch (alt)
            //     try self.compile(cond_data.alt);
            //     // 8. Get address after 'else' branch
            //     const end_addr = self.nextInstrAddr();
            //     // 9. Patch Goto to jump to end_addr
            //     self.patchJump(goto_idx, end_addr);
            // },

            // .Lambda => |lambda_data| {
            //     // Compiling functions/lambdas requires careful handling of scope and jumps.
            //     // Technique: Jump over the body, compile body, then load function object.
            //     // 1. Add Goto to jump over the function body, store index
            //     const goto_idx = try self.addInstr(.{ .Goto = 0 }); // Placeholder
            //     // 2. Get the start address of the function body
            //     const func_body_addr = self.nextInstrAddr();
            //     // 3. Compile the function body
            //     //    Need EnterScope for params + body locals, then ExitScope? Or handled by Call/Reset?
            //     //    Let's assume Call handles scope setup based on Ldf params.
            //     try self.compile(lambda_data.body);
            //     // 4. Add Reset instruction at the end of the body to return
            //     _ = try self.addInstr(.Reset);
            //     // 5. Get address after the function body
            //     const after_func_addr = self.nextInstrAddr();
            //     // 6. Patch the initial Goto to jump to after_func_addr
            //     self.patchJump(goto_idx, after_func_addr);
            //     // 7. Add the Ldf instruction *before* the jump (tricky, need to insert or plan ahead)
            //     //    Alternative: Add Ldf *now*, pointing to func_body_addr. This is simpler.
            //     _ = try self.addInstr(.{ .Ldf = .{ .params = lambda_data.params, .addr = func_body_addr } });
            //     // This puts the function object on the stack *after* the jump over its code.
            // },

            // .FnDecl => |fndecl_data| {
            //     // Similar to Lambda, but assigns the resulting function object to a name.
            //     // 1. Add Goto to jump over the function body
            //     const goto_idx = try self.addInstr(.{ .Goto = 0 });
            //     // 2. Get body start address
            //     const func_body_addr = self.nextInstrAddr();
            //     // 3. Compile body
            //     try self.compile(fndecl_data.body);
            //     // 4. Add Reset at end of body
            //     _ = try self.addInstr(.Reset);
            //     // 5. Get address after body
            //     const after_func_addr = self.nextInstrAddr();
            //     // 6. Patch Goto
            //     self.patchJump(goto_idx, after_func_addr);
            //     // 7. Add Ldf instruction (creates function object on stack)
            //     _ = try self.addInstr(.{ .Ldf = .{ .params = fndecl_data.params, .addr = func_body_addr } });
            //     // 8. Assign the function object to the name
            //     _ = try self.addInstr(.{ .Assign = fndecl_data.name });
            //     // Function declaration itself doesn't leave a value on stack? Add Pop?
            //     // Let's assume Assign leaves the function value, like other assigns.
            // },

            // .Return => |ret_data| {
            //     if (ret_data.value) |val_node| {
            //         // Compile the return value if present
            //         try self.compile(val_node);
            //     } else {
            //         // No return value specified, push Undefined?
            //         //_ = try self.addInstr(.{ .Ldc = .{ .Undefined = .{} } });
            //     }
            //     // Add Reset instruction to return from function
            //     _ = try self.addInstr(.Reset);
            // },

            // .LogicalOp => |log_op_data| {
            //     // Logical operators require short-circuiting via jumps.
            //     switch (log_op_data.op) {
            //         .And => {
            //             // 1. Compile left
            //             try self.compile(log_op_data.left);
            //             // 2. Add Jof (if left is false, result is false, jump to end)
            //             const jof_idx = try self.addInstr(.{ .Jof = 0 });
            //             // 3. Left was true, result is the right side. Pop the true value from left.
            //             _ = try self.addInstr(.Pop);
            //             // 4. Compile right
            //             try self.compile(log_op_data.right);
            //             // 5. Get end address
            //             const end_addr = self.nextInstrAddr();
            //             // 6. Patch Jof
            //             self.patchJump(jof_idx, end_addr);
            //             // Stack now has: result of right (if left was true), or false (if left was false)
            //         },
            //         .Or => {
            //             // 1. Compile left
            //             try self.compile(log_op_data.left);
            //             // 2. Add Jof (if left is false, jump to compile right)
            //             const jof_idx = try self.addInstr(.{ .Jof = 0 });
            //             // 3. Left was true. Result is true. Jump to end.
            //             const goto_idx = try self.addInstr(.{ .Goto = 0 });
            //             // 4. Get address for right side compilation
            //             const right_addr = self.nextInstrAddr();
            //             // 5. Patch Jof to jump here
            //             self.patchJump(jof_idx, right_addr);
            //             // 6. Left was false. Pop the false value.
            //             _ = try self.addInstr(.Pop);
            //             // 7. Compile right
            //             try self.compile(log_op_data.right);
            //             // 8. Get end address
            //             const end_addr = self.nextInstrAddr();
            //             // 9. Patch Goto to jump here
            //             self.patchJump(goto_idx, end_addr);
            //             // Stack now has: true (if left was true), or result of right (if left was false)
            //         },
            //     }
            // },

            // .WhileLoop => |loop_data| {
            //     // 1. Get address for condition check (loop start)
            //     const cond_addr = self.nextInstrAddr();
            //     // 2. Compile condition
            //     try self.compile(loop_data.condition);
            //     // 3. Add Jof to jump past the loop body if condition is false
            //     const jof_idx = try self.addInstr(.{ .Jof = 0 });
            //     // 4. Compile loop body
            //     try self.compile(loop_data.body);
            //     // 5. Pop the result of the body (loop body result usually discarded)
            //     _ = try self.addInstr(.Pop);
            //     // 6. Add Goto to jump back to the condition check
            //     _ = try self.addInstr(.{ .Goto = cond_addr });
            //     // 7. Get address after the loop
            //     const after_loop_addr = self.nextInstrAddr();
            //     // 8. Patch Jof to jump here
            //     self.patchJump(jof_idx, after_loop_addr);
            //     // What should a while loop evaluate to? Undefined?
            //     //_ = try self.addInstr(.{ .Ldc = .{ .Undefined = .{} } });
            // },

            else => {
                // Get the tag name for better error reporting
                const tag_name = @tagName(node.data);
                std.debug.print("Compilation error: Unimplemented AST node type: {s}\n", .{tag_name});
                return CompileErrors.UnimplementedAstNode;
            },
        }
    }

    pub fn compileProgram(self: *Compiler, program_node: *const AstNode) !void {
        // TODO: Could add setup here if needed (e.g., initial EnterScope for globals)
        try self.compile(program_node);
        _ = try self.addInstr(.Done);
    }
};

pub fn main() !void {
    var gpa = std.heap.GeneralPurposeAllocator(.{}){};
    defer _ = gpa.deinit();
    const allocator = gpa.allocator();

    var compiler = Compiler.init(allocator);
    defer compiler.deinit();

    // Example AST: let x = 1 + 2; x
    // Node definitions (usually built by a parser)
    // These can remain const because we take *const pointers below
    var one = AstNode{ .data = .{ .Literal = .{ .Int = 1 } } };
    var two = AstNode{ .data = .{ .Literal = .{ .Int = 2 } } };
    // The struct fields now expect *const AstNode, so &one and &two work correctly
    var add_expr = AstNode{ .data = .{ .BinaryOp = .{ .op = .Add, .left = &one, .right = &two } } };
    var var_decl = AstNode{ .data = .{ .VarDecl = .{ .name = "x", .value = &add_expr } } };
    var load_x = AstNode{ .data = .{ .Name = "x" } };

    // Sequence of statements - type changed to []*const AstNode
    var statements_slice = [_]*AstNode{
        &var_decl,
        &load_x,
    };
    // Need to allocate on heap if we want to pass a slice owned by the allocator
    // Or just use the stack-allocated slice directly for this example
    // var statements = try allocator.alloc(*const AstNode, 2);
    // defer allocator.free(statements);
    // statements[0] = &var_decl;
    // statements[1] = &load_x;

    const program = AstNode{ .data = .{ .Sequence = .{ .statements = &statements_slice } } };

    std.debug.print("Compiling program: let x = 1 + 2; x\n", .{});
    try compiler.compileProgram(&program);

    std.debug.print("Generated Instructions:\n", .{});
    for (compiler.instructions.items, 0..) |instr, i| {
        // TODO: For Assign and Load, print strings instead of uint
        std.debug.print("{d}: {any}\n", .{ i, instr.data });
    }
}

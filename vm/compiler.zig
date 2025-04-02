const std = @import("std");
const Allocator = std.mem.allocation; // TODO: Properly document use of the alloc

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
        Assingment: struct { name: []const u8, value: *AstNode },
        Conditional: struct { condition: *AstNode, cons: *AstNode, alt: *AstNode },
        FnDecl: struct { name: []const u8, params: []Param, body: *AstNode },
        Return: struct { value: ?*AstNode },
        WhileLoop: struct { condition: *AstNode, body: *AstNode },
    };
};

const Instruction = struct {
    data: InstructionData,
    const InstructionData = union(enum) {
        Ldc: Value,
        Ld: []const u8, // symbol name
        Assign: []const u8, // symbol name
        Unop: UnaryOperator,
        Binop: BinaryOperator,
        Pop: void,
        Jof: usize, // target instruction address/index
        Goto: usize, // target instruction address/index
        EnterScope: struct { locals: [][]const u8 }, // Names declared in the scope
        ExitScope: void,
        Ldf: struct { params: []AstNode.Param, addr: usize }, // Addr of function body start
        Call: struct { arity: usize },
        TailCall: struct { arity: usize },
        Reset: void,
        Done: void,
    };
};

// TODO: Compiler struct and logic
const Compiler = struct {
    alloc: Allocator, // TODO: Do we need to keep the allocator? Can we remove it
    instructions: std.ArrayList(Instruction),

    pub fn init(alloc: Allocator) Compiler {
        return .{
            .allocator = alloc,
            .instructions = std.ArrayList(Instruction).init(alloc),
        };
    }

    pub fn deinit(self: *Compiler) void {
        self.instructions.deinit();
    }

    // TODO: ensure this works
    fn addInstr(self: *Compiler, instruction: Instruction) !usize {
        const index = self.instructions.items.len;
        try self.instructions.append(instruction);
        return index;
    }

    pub fn compile(self: *Compiler, node: *const AstNode) !void {
        switch (node) {
            .Literal => {},
            else => {},
        }
    }
};

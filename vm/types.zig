const std = @import("std");
const json = std.json;
// Primitive Types
// We differentiate betweeen the primitive types in rust and zig
// by using PascalCase for the Rust types
pub const Value = union(enum) {
    // TODO: Might want to add char as primitive
    Int: i64,
    Float: f64,
    Bool: bool,
    String: []const u8, // TODO: Rust doesn't really have Strings as primitives, so this might not be needed
    Undefined: void,
};

// Enum Types
pub const UnaryOperator = enum {
    Negate, // -
    Not, // !

    pub fn jsonStringify(self: UnaryOperator, writer: anytype) !void {
        try writer.write(switch (self) {
            .Negate => "-",
            .Not => "!",
        });
    }

    pub fn jsonParse(allocator: std.mem.Allocator, value: *json.Scanner, options: json.ParseOptions) !UnaryOperator {
        const val = try json.innerParse(json.Value, allocator, value, options);
        const str = val.string;
        // std.debug.print("val: {}\n", .{val});
        if (std.mem.eql(u8, str, "-")) return .Negate;
        if (std.mem.eql(u8, str, "!")) return .Not;
        return error.InvalidEnumTag;
    }
};

pub const CompOperator = enum {
    Eq, // ==
    Neq, // !=
    Lt, // <
    Lte, // <=
    Gt, // >
    Gte, // >=

    pub fn jsonStringify(self: CompOperator, writer: anytype) !void {
        try writer.write(switch (self) {
            .Eq => "==",
            .Neq => "!=",
            .Lt => "<",
            .Lte => "<=",
            .Gt => ">",
            .Gte => ">=",
        });
    }

    pub fn jsonParse(allocator: std.mem.Allocator, value: *json.Scanner, options: json.ParseOptions) !CompOperator {
        const val = try json.innerParse(json.Value, allocator, value, options);
        const str = val.string;
        // std.debug.print("val: {}\n", .{val});
        if (std.mem.eql(u8, str, "==")) return .Eq;
        if (std.mem.eql(u8, str, "!=")) return .Neq;
        if (std.mem.eql(u8, str, "<")) return .Lt;
        if (std.mem.eql(u8, str, "<=")) return .Lte;
        if (std.mem.eql(u8, str, ">")) return .Gt;
        if (std.mem.eql(u8, str, ">=")) return .Gte;
        return error.InvalidEnumTag;
    }
};

pub const ArithOperator = enum {
    Add, // +
    Sub, // -
    Mul, // *
    Div, // /
    Mod, // %
    Bitxor, // ^
    Bitor, // |
    Bitand, // &
    Shl, // <<
    Shr, // >>

    pub fn jsonStringify(self: ArithOperator, writer: anytype) !void {
        try writer.write(switch (self) {
            .Add => "+",
            .Sub => "-",
            .Mul => "*",
            .Div => "/",
            .Mod => "%",
            .Bitxor => "^",
            .Bitor => "|",
            .Bitand => "&",
            .Shl => "<<",
            .Shr => ">>",
        });
    }

    pub fn jsonParse(allocator: std.mem.Allocator, value: *json.Scanner, options: json.ParseOptions) !ArithOperator {
        const val = try json.innerParse(json.Value, allocator, value, options);
        const str = val.string;
        // std.debug.print("val: {}\n", .{val});
        if (std.mem.eql(u8, str, "+")) return .Add;
        if (std.mem.eql(u8, str, "-")) return .Sub;
        if (std.mem.eql(u8, str, "*")) return .Mul;
        if (std.mem.eql(u8, str, "/")) return .Div;
        if (std.mem.eql(u8, str, "%")) return .Mod;
        if (std.mem.eql(u8, str, "^")) return .Bitxor;
        if (std.mem.eql(u8, str, "|")) return .Bitor;
        if (std.mem.eql(u8, str, "&")) return .Bitand;
        if (std.mem.eql(u8, str, "<<")) return .Shl;
        if (std.mem.eql(u8, str, ">>")) return .Shr;
        return error.InvalidEnumTag;
    }
};

pub const LogicalOperator = enum {
    And, // &&
    Or, // ||

    pub fn jsonStringify(self: LogicalOperator, writer: anytype) !void {
        try writer.write(switch (self) {
            .And => "&&",
            .Or => "||",
        });
    }

    pub fn jsonParse(allocator: std.mem.Allocator, value: *json.Scanner, options: json.ParseOptions) !LogicalOperator {
        const val = try json.innerParse(json.Value, allocator, value, options);
        const str = val.string;
        // std.debug.print("val: {}\n", .{val});
        if (std.mem.eql(u8, str, "&&")) return .And;
        if (std.mem.eql(u8, str, "||")) return .Or;
        return error.InvalidEnumTag;
    }
};

pub const BinaryOperator = union(enum) {
    comp: CompOperator,
    logic: LogicalOperator,
    arith: ArithOperator,

    pub fn jsonStringify(self: BinaryOperator, writer: anytype) !void {
        switch (self) {
            .comp => |comp_op| try comp_op.jsonStringify(writer),
            .logic => |logic_op| try logic_op.jsonStringify(writer),
            .arith => |arith_op| try arith_op.jsonStringify(writer),
        }
    }

    pub fn jsonParse(allocator: std.mem.Allocator, value: *json.Scanner, options: json.ParseOptions) !BinaryOperator {
        const val = try json.innerParse(json.Value, allocator, value, options);
        const str = val.string;
        // std.debug.print("val: {}\n", .{val});

        // Try to parse as CompOperator
        if (std.mem.eql(u8, str, "==")) return BinaryOperator{ .comp = .Eq };
        if (std.mem.eql(u8, str, "!=")) return BinaryOperator{ .comp = .Neq };
        if (std.mem.eql(u8, str, "<")) return BinaryOperator{ .comp = .Lt };
        if (std.mem.eql(u8, str, "<=")) return BinaryOperator{ .comp = .Lte };
        if (std.mem.eql(u8, str, ">")) return BinaryOperator{ .comp = .Gt };
        if (std.mem.eql(u8, str, ">=")) return BinaryOperator{ .comp = .Gte };

        // Try to parse as LogicalOperator
        if (std.mem.eql(u8, str, "&&")) return BinaryOperator{ .logic = .And };
        if (std.mem.eql(u8, str, "||")) return BinaryOperator{ .logic = .Or };

        // Try to parse as ArithOperator
        if (std.mem.eql(u8, str, "+")) return BinaryOperator{ .arith = .Add };
        if (std.mem.eql(u8, str, "-")) return BinaryOperator{ .arith = .Sub };
        if (std.mem.eql(u8, str, "*")) return BinaryOperator{ .arith = .Mul };
        if (std.mem.eql(u8, str, "/")) return BinaryOperator{ .arith = .Div };
        if (std.mem.eql(u8, str, "%")) return BinaryOperator{ .arith = .Mod };
        if (std.mem.eql(u8, str, "^")) return BinaryOperator{ .arith = .Bitxor };
        if (std.mem.eql(u8, str, "|")) return BinaryOperator{ .arith = .Bitor };
        if (std.mem.eql(u8, str, "&")) return BinaryOperator{ .arith = .Bitand };
        if (std.mem.eql(u8, str, "<<")) return BinaryOperator{ .arith = .Shl };
        if (std.mem.eql(u8, str, ">>")) return BinaryOperator{ .arith = .Shr };

        return error.InvalidEnumTag;
    }
};

pub const BinaryOperation = struct {
    sym: BinaryOperator,
    first: *AstNode,
    second: *AstNode,
};

pub const Param = struct {
    name: []const u8,
    // TODO: type_info?
};

// Explicit Error Set
pub const CompileErrors = error{
    UnimplementedAstNode,
    OutOfMemory,
};

// AstNode Declaration
pub const AstNode = union(enum) {
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

pub const JsonAstNode = union(enum) {
    lit: struct { val: Value },
    nam: []const u8,
    app: struct { nam: []const u8, args: []*AstNode }, // NOTE: This differs from initial, becuase we aren't using AstNode for func
    logic: BinaryOperation,
    arith: BinaryOperation,
    neg: struct { sym: UnaryOperator, expr: *AstNode },
    seq: struct { stmts: []*AstNode },
    blk: struct { body: *AstNode },
    let: struct { nam: []const u8, value: *AstNode, is_mut: bool },
    assign: struct { nam: []const u8, val: *AstNode },
    cond: struct { pred: *AstNode, cons: *AstNode, alt: *AstNode },
    fun: struct { nam: []const u8, params: []Param, body: *AstNode },
    while_loop: struct { pred: *AstNode, body: *AstNode },
    // TODO: return: struct { value: ?*AstNode },
    // Other op types: borrow, deref, question, type_cast, compoud_assign
};

pub const Instruction = union(enum) {
    Ldc: Value, // Load constant
    Ld: []const u8, // Load variable by name
    Assign: []const u8, // Assign to variable name
    Unop: UnaryOperator,
    Binop: BinaryOperator, // TODO: Fix this with tagged unions, override the Json
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

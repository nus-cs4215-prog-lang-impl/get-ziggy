const std = @import("std");
const json = std.json;
// Primitive Types
// We differentiate betweeen the primitive types in rust and zig
// by using PascalCase for the Rust types
pub const TypeName = enum {
    i32,
    i64,
    u32,
    u64,
    f64,
    String,
    Bool,
    Undefined,

    pub fn jsonStringify(self: TypeName, writer: anytype) !void {
        try writer.write(switch (self) {
            .i32 => "i32",
            .u32 => "u32",
            .i64 => "i64",
            .u64 => "u64",
            .f64 => "f64",
            .String => "String",
            .Bool => "bool",
            .Undefined => "undefined",
        });
    }

    pub fn jsonParse(allocator: std.mem.Allocator, value: *json.Scanner, options: json.ParseOptions) !TypeName {
        const val = try json.innerParse(json.Value, allocator, value, options);
        const str = val.string;
        // std.debug.print("val: {}\n", .{val});
        if (std.mem.eql(u8, str, "i32")) return .i32;
        if (std.mem.eql(u8, str, "u32")) return .u32;
        if (std.mem.eql(u8, str, "i64")) return .i64;
        if (std.mem.eql(u8, str, "u64")) return .u64;
        if (std.mem.eql(u8, str, "f64")) return .f64;
        if (std.mem.eql(u8, str, "String")) return .String;
        if (std.mem.eql(u8, str, "bool")) return .Bool;
        if (std.mem.eql(u8, str, "undefined")) return .Undefined;
        return error.InvalidEnumTag;
    }
};

pub const LiteralVal = struct {
    val: []const u8,
    type_name: TypeName,
};

// Enum Types
pub const BorrowOperator = enum {
    Borrow, // &
    BorrowRef, // &&

    pub fn jsonStringify(self: BorrowOperator, writer: anytype) !void {
        try writer.write(switch (self) {
            .Borrow => "&",
            .BorrowRef => "&&",
        });
    }

    pub fn jsonParse(allocator: std.mem.Allocator, value: *json.Scanner, options: json.ParseOptions) !BorrowOperator {
        const val = try json.innerParse(json.Value, allocator, value, options);
        const str = val.string;
        // std.debug.print("val: {}\n", .{val});
        if (std.mem.eql(u8, str, "&")) return .Borrow;
        if (std.mem.eql(u8, str, "&&")) return .BorrowRef;
        return error.InvalidEnumTag;
    }
};

pub const BorrowAttr = enum {
    BorrowAttr, //mut

    pub fn jsonStringify(self: BorrowAttr, writer: anytype) !void {
        try writer.write(switch (self) {
            .BorrowAttr => "mut",
        });
    }

    pub fn jsonParse(allocator: std.mem.Allocator, value: *json.Scanner, options: json.ParseOptions) !BorrowAttr {
        const val = try json.innerParse(json.Value, allocator, value, options);
        const str = val.string;
        // std.debug.print("val: {}\n", .{val});
        if (std.mem.eql(u8, str, "mut")) return .BorrowAttr;
        return error.InvalidEnumTag;
    }
};

pub const NegateOperator = enum {
    Negate, // -
    Not, // !

    pub fn jsonStringify(self: NegateOperator, writer: anytype) !void {
        try writer.write(switch (self) {
            .Negate => "-",
            .Not => "!",
        });
    }

    pub fn jsonParse(allocator: std.mem.Allocator, value: *json.Scanner, options: json.ParseOptions) !NegateOperator {
        const val = try json.innerParse(json.Value, allocator, value, options);
        const str = val.string;
        // std.debug.print("val: {}\n", .{val});
        if (std.mem.eql(u8, str, "-")) return .Negate;
        if (std.mem.eql(u8, str, "!")) return .Not;
        return error.InvalidEnumTag;
    }
};

pub const DerefOperator = enum {
    Deref, // -

    pub fn jsonStringify(self: DerefOperator, writer: anytype) !void {
        try writer.write(switch (self) {
            .Deref => "*",
        });
    }

    pub fn jsonParse(allocator: std.mem.Allocator, value: *json.Scanner, options: json.ParseOptions) !DerefOperator {
        const val = try json.innerParse(json.Value, allocator, value, options);
        const str = val.string;
        // std.debug.print("val: {}\n", .{val});
        if (std.mem.eql(u8, str, "*")) return .Deref;
        return error.InvalidEnumTag;
    }
};

pub const QuestionOperator = enum {
    Question, // ?

    pub fn jsonStringify(self: QuestionOperator, writer: anytype) !void {
        try writer.write(switch (self) {
            .Question => "?",
        });
    }

    pub fn jsonParse(allocator: std.mem.Allocator, value: *json.Scanner, options: json.ParseOptions) !QuestionOperator {
        const val = try json.innerParse(json.Value, allocator, value, options);
        const str = val.string;
        // std.debug.print("val: {}\n", .{val});
        if (std.mem.eql(u8, str, "?")) return .Question;
        return error.InvalidEnumTag;
    }
};

pub const UnaryOperator = union(enum) {
    borrow: BorrowOperator,
    borrow_mut: BorrowAttr,
    deref: DerefOperator,
    neg: NegateOperator,
    question: QuestionOperator,

    pub fn jsonStringify(self: UnaryOperator, writer: anytype) !void {
        switch (self) {
            .borrow => |borrow| try borrow.jsonStringify(writer),
            .borrow_mut => |borrow_mut| try borrow_mut.jsonStringify(writer),
            .deref => |deref| try deref.jsonStringify(writer),
            .neg => |neg| try neg.jsonStringify(writer),
            .question => |question| try question.jsonStringify(writer),
        }
    }

    pub fn jsonParse(allocator: std.mem.Allocator, value: *json.Scanner, options: json.ParseOptions) !UnaryOperator {
        const val = try json.innerParse(json.Value, allocator, value, options);
        const str = val.string;
        // std.debug.print("val: {}\n", .{val});

        // Check for BorrowOperator
        if (std.mem.eql(u8, str, "&")) return UnaryOperator{ .borrow = .Borrow };
        if (std.mem.eql(u8, str, "&&")) return UnaryOperator{ .borrow = .BorrowRef };

        // Check for BorrowAttr
        if (std.mem.eql(u8, str, "mut")) return UnaryOperator{ .borrow_mut = .BorrowAttr };

        // Check for DerefOperator
        if (std.mem.eql(u8, str, "*")) return UnaryOperator{ .deref = .Deref };

        // Check for NegateOperator
        if (std.mem.eql(u8, str, "-")) return UnaryOperator{ .neg = .Negate };
        if (std.mem.eql(u8, str, "!")) return UnaryOperator{ .neg = .Not };

        // Check for QuestionOperator
        if (std.mem.eql(u8, str, "?")) return UnaryOperator{ .question = .Question };

        // If none match, return an error
        return error.InvalidEnumTag;
    }
};

pub const UnaryOperation = struct {
    sym: UnaryOperator,
    first: *JsonAstNode,
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

pub const AssignOperator = enum {
    Assign, // =

    pub fn jsonStringify(self: AssignOperator, writer: anytype) !void {
        try writer.write(switch (self) {
            .Assign => "=",
        });
    }

    pub fn jsonParse(allocator: std.mem.Allocator, value: *json.Scanner, options: json.ParseOptions) !AssignOperator {
        const val = try json.innerParse(json.Value, allocator, value, options);
        const str = val.string;
        if (std.mem.eql(u8, str, "=")) return .Assign;
        return error.InvalidEnumTag;
    }
};

pub const CompoundAssignOperator = enum {
    AddAssign, // +=
    SubAssign, // -=
    MulAssign, // *=
    DivAssign, // /=
    ModAssign, // %=
    BitAndAssign, // &=
    BitOrAssign, // |=
    BitXorAssign, // ^=
    ShlAssign, // <<=
    ShrAssign, // >>=

    pub fn jsonStringify(self: CompoundAssignOperator, writer: anytype) !void {
        try writer.write(switch (self) {
            .AddAssign => "+=",
            .SubAssign => "-=",
            .MulAssign => "*=",
            .DivAssign => "/=",
            .ModAssign => "%=",
            .BitAndAssign => "&=",
            .BitOrAssign => "|=",
            .BitXorAssign => "^=",
            .ShlAssign => "<<=",
            .ShrAssign => ">>=",
        });
    }

    pub fn jsonParse(allocator: std.mem.Allocator, value: *json.Scanner, options: json.ParseOptions) !CompoundAssignOperator {
        const val = try json.innerParse(json.Value, allocator, value, options);
        const str = val.string;
        if (std.mem.eql(u8, str, "+=")) return .AddAssign;
        if (std.mem.eql(u8, str, "-=")) return .SubAssign;
        if (std.mem.eql(u8, str, "*=")) return .MulAssign;
        if (std.mem.eql(u8, str, "/=")) return .DivAssign;
        if (std.mem.eql(u8, str, "%=")) return .ModAssign;
        if (std.mem.eql(u8, str, "&=")) return .BitAndAssign;
        if (std.mem.eql(u8, str, "|=")) return .BitOrAssign;
        if (std.mem.eql(u8, str, "^=")) return .BitXorAssign;
        if (std.mem.eql(u8, str, "<<=")) return .ShlAssign;
        if (std.mem.eql(u8, str, ">>=")) return .ShrAssign;
        return error.InvalidEnumTag;
    }
};

pub const TypeCastOperator = enum {
    As, // as

    pub fn jsonStringify(self: TypeCastOperator, writer: anytype) !void {
        try writer.write(switch (self) {
            .As => "as",
        });
    }

    pub fn jsonParse(allocator: std.mem.Allocator, value: *json.Scanner, options: json.ParseOptions) !TypeCastOperator {
        const val = try json.innerParse(json.Value, allocator, value, options);
        const str = val.string;
        if (std.mem.eql(u8, str, "as")) return .As;
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
    reassign: AssignOperator,
    compound_assign: CompoundAssignOperator,
    type_cast: TypeCastOperator,

    pub fn jsonStringify(self: BinaryOperator, writer: anytype) !void {
        switch (self) {
            .comp => |comp_op| try comp_op.jsonStringify(writer),
            .logic => |logic_op| try logic_op.jsonStringify(writer),
            .arith => |arith_op| try arith_op.jsonStringify(writer),
            .reassign => |assign_op| try assign_op.jsonStringify(writer),
            .compound_assign => |compound_assign_op| try compound_assign_op.jsonStringify(writer),
            .type_cast => |type_cast_op| try type_cast_op.jsonStringify(writer),
        }
    }

    pub fn jsonParse(allocator: std.mem.Allocator, value: *json.Scanner, options: json.ParseOptions) !BinaryOperator {
        const val = try json.innerParse(json.Value, allocator, value, options);
        const str = val.string;
        std.debug.print("val: {}\n", .{val});

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

        // Try to parse as AssignOperator
        if (std.mem.eql(u8, str, "=")) return BinaryOperator{ .reassign = .Assign };

        // Try to parse as CompoundAssignOperator
        if (std.mem.eql(u8, str, "+=")) return BinaryOperator{ .compound_assign = .AddAssign };
        if (std.mem.eql(u8, str, "-=")) return BinaryOperator{ .compound_assign = .SubAssign };
        if (std.mem.eql(u8, str, "*=")) return BinaryOperator{ .compound_assign = .MulAssign };
        if (std.mem.eql(u8, str, "/=")) return BinaryOperator{ .compound_assign = .DivAssign };
        if (std.mem.eql(u8, str, "%=")) return BinaryOperator{ .compound_assign = .ModAssign };
        if (std.mem.eql(u8, str, "&=")) return BinaryOperator{ .compound_assign = .BitAndAssign };
        if (std.mem.eql(u8, str, "|=")) return BinaryOperator{ .compound_assign = .BitOrAssign };
        if (std.mem.eql(u8, str, "^=")) return BinaryOperator{ .compound_assign = .BitXorAssign };
        if (std.mem.eql(u8, str, "<<=")) return BinaryOperator{ .compound_assign = .ShlAssign };
        if (std.mem.eql(u8, str, ">>=")) return BinaryOperator{ .compound_assign = .ShrAssign };

        // Try to parse as TypeCastOperator
        if (std.mem.eql(u8, str, "as")) return BinaryOperator{ .type_cast = .As };

        return error.InvalidEnumTag;
    }
};

pub const BinaryOperation = struct {
    sym: BinaryOperator,
    first: *JsonAstNode,
    second: *JsonAstNode,
};

pub const Param = struct { nam: []const u8, type_name: TypeName };

pub const ControlOperation = struct { body: ?*JsonAstNode };

// Explicit Error Set
pub const CompileErrors = error{
    UnimplementedAstNode,
    OutOfMemory,
};

pub const JsonAstNode = union(enum) {
    lit: LiteralVal,
    nam: []const u8,
    app: struct { nam: []const u8, args: []*JsonAstNode },
    comp: BinaryOperation,
    logic: BinaryOperation,
    arith: BinaryOperation,
    borrow: UnaryOperation,
    borrow_mut: UnaryOperation,
    deref: UnaryOperation,
    neg: UnaryOperation,
    question: UnaryOperation,
    seq: struct { stmts: []*JsonAstNode },
    blk: struct { body: *JsonAstNode },
    assign: struct { nam: []const u8, val: *JsonAstNode, is_mut: bool, type_name: ?TypeName },
    reassign: BinaryOperation,
    compound_assign: BinaryOperation,
    type_cast: BinaryOperation,
    cond: struct { pred: *JsonAstNode, cons: *JsonAstNode, alt: ?*JsonAstNode },
    fun: struct { nam: []const u8, params: []Param, body: ?*JsonAstNode, return_type: ?TypeName },
    while_loop: struct { pred: *JsonAstNode, body: *JsonAstNode },
    return_statement: ControlOperation,
    continue_statement: ControlOperation,
    break_statement: ControlOperation,
};

pub const Instruction = union(enum) {
    Ldc: LiteralVal, // Load constant
    Ld: struct { nam: []const u8, pos: u32 }, // Load variable by name
    Assign: struct { nam: []const u8, pos: u32 }, // Assign to variable name
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

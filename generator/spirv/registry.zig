//! See https://www.khronos.org/registry/spir-v/specs/unified1/MachineReadableGrammar.html
//! and the files in https://github.com/KhronosGroup/SPIRV-Headers/blob/master/include/spirv/unified1/

pub const CoreRegistry = struct {
    copyright: [][]const u8,
    magic_number: []const u8, // Hexadecimal representation of the magic number
    major_version: u32,
    minor_version: u32,
    revision: u32,
    instruction_printing_class: []InstructionPrintingClass,
    instructions: []Instruction,
    operand_kinds: []OperandKind,
};

pub const ExtensionRegistry = struct {
    copyright: [][]const u8,
    version: u32,
    revision: u32,
    instructions: []Instruction,
    operand_kinds: []OperandKind = &[_]OperandKind{},
};

pub const InstructionPrintingClass = struct {
    tag: []const u8,
    heading: ?[]const u8 = null,
};

pub const Instruction = struct {
    opname: []const u8,

    /// Note: Only available in the core registry.
    class: ?[]const u8 = null,
    opcode: u32,
    operands: []Operand = &[_]Operand{},
    capabilities: [][]const u8 = &[_][]const u8{},
    extensions: [][]const u8 = &[_][]const u8{},
    version: ?[]const u8 = null,

    /// Note: non-canonical casing to match Spir-V JSON spec
    lastVersion: ?[]const u8 = null,
};

pub const Operand = struct {
    kind: []const u8,

    /// If this field is 'null', the operand is only expected once.
    quantifier: ?Quantifier = null,
    name: []const u8 = "",
};

pub const Quantifier = enum {
    /// zero or once
    @"?",

    /// zero or more
    @"*",
};

pub const OperandCategory = enum {
    // Note: non-canonical casing to match Spir-V JSON spec
    BitEnum,
    ValueEnum,
    Id,
    Literal,
    Composite,
};

pub const OperandKind = struct {
    category: OperandCategory,

    /// The name
    kind: []const u8,
    doc: []const u8 = "",
    enumerants: ?[]Enumerant = null,
    bases: ?[]const []const u8 = null,
};

pub const Enumerant = struct {
    enumerant: []const u8,
    value: union(enum) {
        bitflag: []const u8, // Hexadecimal representation of the value
        int: u31,
    },
    capabilities: [][]const u8 = &[_][]const u8{},
    extensions: [][]const u8 = &[_][]const u8{}, // Valid for .ValueEnum
    parameters: []Operand = &[_]Operand{}, // `quantifier` will always be `null`.
    version: ?[]const u8 = null,

    // Note: non-canonical casing to match Spir-V JSON spec
    lastVersion: ?[]const u8 = null,
};

--!native
--!optimize 2

-- decompiler soon? :eyes:
-- created with :heart: by 0x1437 (github: https://github.com/0x1437, discord: @0x01437 (971650839888416799))

-- localize all used functions for faster access, no need to invoke the __index metamethod over and over for the same functions like string.format
local pairs = pairs
local tostring = tostring
local error = error
local pcall = pcall
local print = print

local string_format = string.format
local string_rep = string.rep
local string_lower = string.lower
local string_byte = string.byte
local string_sub = string.sub

local table_insert = table.insert
local table_create = table.create
local table_concat = table.concat
local table_find = table.find

local bit32_band = bit32.band
local bit32_rshift = bit32.rshift
local bit32_lshift = bit32.lshift
local bit32_bor = bit32.bor

local math_floor = math.floor
local os_clock = os.clock

local buffer_readu8 = buffer.readu8
local buffer_readu32 = buffer.readu32
local buffer_readi32 = buffer.readi32
local buffer_readf32 = buffer.readf32
local buffer_readf64 = buffer.readf64
local buffer_readstring = buffer.readstring
local buffer_fromstring = buffer.fromstring
local buffer_len = buffer.len

---

local NewOpcode = function(Name, Type, Number, Aux)
	return {
		Name = Name,
		Type = Type,
		Number = Number,
		Aux = Aux or false,
	}
end

local OpTableV5 = {}
local OpTableV6 = {
	NewOpcode("NOP", "none", 0x00), -- NOP: no operation
	NewOpcode("BREAK", "none", 0xE3), -- BREAK: debugger break

	-- LOADNIL: sets register to nil
	-- A: target register
	NewOpcode("LOADNIL", "iA", 0xC6),

	-- LOADB: sets register to boolean and jumps to a given short offset (used to compile comparison results into a boolean)
	-- A: target register
	-- B: value (0/1)
	-- C: jump offset
	NewOpcode("LOADB", "iABC", 0xA9),

	-- LOADN: sets register to a number literal
	-- A: target register
	-- D: value (-32768..32767)
	NewOpcode("LOADN", "iABx", 0x8C),

	-- LOADK: sets register to an entry from the constant table from the proto (number/vector/string)
	-- A: target register
	-- D: constant table index (0..32767)
	NewOpcode("LOADK", "iABx", 0x6F),

	-- MOVE: move (copy) value from one register to another
	-- A: target register
	-- B: source register
	NewOpcode("MOVE", "iAB", 0x52),

	-- GETGLOBAL: load value from global table using constant string as a key
	-- A: target register
	-- C: predicted slot index (based on hash)
	-- AUX: constant table index
	NewOpcode("GETGLOBAL", "iAC", 0x35, true),

	-- SETGLOBAL: set value in global table using constant string as a key
	-- A: source register
	-- C: predicted slot index (based on hash)
	-- AUX: constant table index
	NewOpcode("SETGLOBAL", "iAC", 0x18, true),

	-- GETUPVAL: load upvalue from the upvalue table for the current function
	-- A: target register
	-- B: upvalue index
	NewOpcode("GETUPVAL", "iAB", 0xFB),

	-- SETUPVAL: store value into the upvalue table for the current function
	-- A: target register
	-- B: upvalue index
	NewOpcode("SETUPVAL", "iAB", 0xDE),

	-- CLOSEUPVALS: close (migrate to heap) all upvalues that were captured for registers >= target
	-- A: target register
	NewOpcode("CLOSEUPVALS", "iA", 0xC1),

	-- GETIMPORT: load imported global table global from the constant table
	-- A: target register
	-- D: constant table index (0..32767); we assume that imports are loaded into the constant table
	-- AUX: 3 10-bit indices of constant strings that, combined, constitute an import path; length of the path is set by the top 2 bits (1,2,3)
	NewOpcode("GETIMPORT", "iABx", 0xA4, true),

	-- GETTABLE: load value from table into target register using key from register
	-- A: target register
	-- B: table register
	-- C: index register
	NewOpcode("GETTABLE", "iABC", 0x87),

	-- SETTABLE: store source register into table using key from register
	-- A: source register
	-- B: table register
	-- C: index register
	NewOpcode("SETTABLE", "iABC", 0x6A),

	-- GETTABLEKS: load value from table into target register using constant string as a key
	-- A: target register
	-- B: table register
	-- C: predicted slot index (based on hash)
	-- AUX: constant table index
	NewOpcode("GETTABLEKS", "iABC", 0x4D, true),

	-- SETTABLEKS: store source register into table using constant string as a key
	-- A: source register
	-- B: table register
	-- C: predicted slot index (based on hash)
	-- AUX: constant table index
	NewOpcode("SETTABLEKS", "iABC", 0x30, true),

	-- GETTABLEN: load value from table into target register using small integer index as a key
	-- A: target register
	-- B: table register
	-- C: index-1 (index is 1..256)
	NewOpcode("GETTABLEN", "iABC", 0x13),

	-- SETTABLEN: store source register into table using small integer index as a key
	-- A: source register
	-- B: table register
	-- C: index-1 (index is 1..256)
	NewOpcode("SETTABLEN", "iABC", 0xF6),

	-- NEWCLOSURE: create closure from a child proto; followed by a CAPTURE instruction for each upvalue
	-- A: target register
	-- D: child proto index (0..32767)
	NewOpcode("NEWCLOSURE", "iABx", 0xD9),

	-- NAMECALL: prepare to call specified method by name by loading function from source register using constant index into target register and copying source register into target register + 1
	-- A: target register
	-- B: source register
	-- C: predicted slot index (based on hash)
	-- AUX: constant table index
	-- Note that this instruction must be followed directly by CALL; it prepares the arguments
	-- This instruction is roughly equivalent to GETTABLEKS + MOVE pair, but we need a special instruction to support custom __namecall metamethod
	NewOpcode("NAMECALL", "iABC", 0xBC, true),

	-- CALL: call specified function
	-- A: register where the function object lives, followed by arguments; results are placed starting from the same register
	-- B: argument count + 1, or 0 to preserve all arguments up to top (MULTRET)
	-- C: result count + 1, or 0 to preserve all values and adjust top (MULTRET)
	NewOpcode("CALL", "iABC", 0x9F),

	-- RETURN: returns specified values from the function
	-- A: register where the returned values start
	-- B: number of returned values + 1, or 0 to return all values up to top (MULTRET)
	NewOpcode("RETURN", "iAB", 0x82),

	-- JUMP: jumps to target offset
	-- D: jump offset (-32768..32767; 0 means "next instruction" aka "don't jump")
	NewOpcode("JUMP", "isBx", 0x65),

	-- JUMPBACK: jumps to target offset; this is equivalent to JUMP but is used as a safepoint to be able to interrupt while/repeat loops
	-- D: jump offset (-32768..32767; 0 means "next instruction" aka "don't jump")
	NewOpcode("JUMPBACK", "isBx", 0x48),

	-- JUMPIF: jumps to target offset if register is not nil/false
	-- A: source register
	-- D: jump offset (-32768..32767; 0 means "next instruction" aka "don't jump")
	NewOpcode("JUMPIF", "iAsBx", 0x2B),

	-- JUMPIFNOT: jumps to target offset if register is nil/false
	-- A: source register
	-- D: jump offset (-32768..32767; 0 means "next instruction" aka "don't jump")
	NewOpcode("JUMPIFNOT", "iAsBx", 0x0E),

	-- JUMPIFEQ, JUMPIFLE, JUMPIFLT, JUMPIFNOTEQ, JUMPIFNOTLE, JUMPIFNOTLT: jumps to target offset if the comparison is true (or false, for NOT variants)
	-- A: source register 1
	-- D: jump offset (-32768..32767; 1 means "next instruction" aka "don't jump")
	-- AUX: source register 2
	NewOpcode("JUMPIFEQ", "iAsBx", 0xF1, true),
	NewOpcode("JUMPIFLE", "iAsBx", 0xD4, true),
	NewOpcode("JUMPIFLT", "iAsBx", 0xB7, true),
	NewOpcode("JUMPIFNOTEQ", "iAsBx", 0x9A, true),
	NewOpcode("JUMPIFNOTLE", "iAsBx", 0x7D, true),
	NewOpcode("JUMPIFNOTLT", "iAsBx", 0x60, true),

	-- ADD, SUB, MUL, DIV, MOD, POW: compute arithmetic operation between two source registers and put the result into target register
	-- A: target register
	-- B: source register 1
	-- C: source register 2
	NewOpcode("ADD", "iABC", 0x43),
	NewOpcode("SUB", "iABC", 0x26),
	NewOpcode("MUL", "iABC", 0x09),
	NewOpcode("DIV", "iABC", 0xEC),
	NewOpcode("MOD", "iABC", 0xCF),
	NewOpcode("POW", "iABC", 0xB2),

	-- ADDK, SUBK, MULK, DIVK, MODK, POWK: compute arithmetic operation between the source register and a constant and put the result into target register
	-- A: target register
	-- B: source register
	-- C: constant table index (0..255); must refer to a number
	NewOpcode("ADDK", "iABC", 0x95),
	NewOpcode("SUBK", "iABC", 0x78),
	NewOpcode("MULK", "iABC", 0x5B),
	NewOpcode("DIVK", "iABC", 0x3E),
	NewOpcode("MODK", "iABC", 0x21),
	NewOpcode("POWK", "iABC", 0x04),

	-- AND, OR: perform `and` or `or` operation (selecting first or second register based on whether the first one is truthy) and put the result into target register
	-- A: target register
	-- B: source register 1
	-- C: source register 2
	NewOpcode("AND", "iABC", 0xE7),
	NewOpcode("OR", "iABC", 0xCA),

	-- ANDK, ORK: perform `and` or `or` operation (selecting source register or constant based on whether the source register is truthy) and put the result into target register
	-- A: target register
	-- B: source register
	-- C: constant table index (0..255)
	NewOpcode("ANDK", "iABC", 0xAD),
	NewOpcode("ORK", "iABC", 0x90),

	-- CONCAT: concatenate all strings between B and C (inclusive) and put the result into A
	-- A: target register
	-- B: source register start
	-- C: source register end
	NewOpcode("CONCAT", "iABC", 0x73),

	-- NOT, MINUS, LENGTH: compute unary operation for source register and put the result into target register
	-- A: target register
	-- B: source register
	NewOpcode("NOT", "iAB", 0x56),
	NewOpcode("MINUS", "iAB", 0x39),
	NewOpcode("LENGTH", "iAB", 0x1C),

	-- NEWTABLE: create table in target register
	-- A: target register
	-- B: table size, stored as 0 for v=0 and ceil(log2(v))+1 for v!=0
	-- AUX: array size
	NewOpcode("NEWTABLE", "iAB", 0xFF, true),

	-- DUPTABLE: duplicate table using the constant table template to target register
	-- A: target register
	-- D: constant table index (0..32767)
	NewOpcode("DUPTABLE", "iABx", 0xE2),

	-- SETLIST: set a list of values to table in target register
	-- A: target register
	-- B: source register start
	-- C: value count + 1, or 0 to use all values up to top (MULTRET)
	-- AUX: table index to start from
	NewOpcode("SETLIST", "iABC", 0xC5, true),

	-- FORNPREP: prepare a numeric for loop, jump over the loop if first iteration doesn't need to run
	-- A: target register; numeric for loops assume a register layout [limit, step, index, variable]
	-- D: jump offset (-32768..32767)
	-- limit/step are immutable, index isn't visible to user code since it's copied into variable
	NewOpcode("FORNPREP", "iABx", 0xA8),

	-- FORNLOOP: adjust loop variables for one iteration, jump back to the loop header if loop needs to continue
	-- A: target register; see FORNPREP for register layout
	-- D: jump offset (-32768..32767)
	NewOpcode("FORNLOOP", "iABx", 0x8B),

	-- FORGLOOP: adjust loop variables for one iteration of a generic for loop, jump back to the loop header if loop needs to continue
	-- A: target register; generic for loops assume a register layout [generator, state, index, variables...]
	-- D: jump offset (-32768..32767)
	-- AUX: variable count (1..255) in the low 8 bits, high bit indicates whether to use ipairs-style traversal in the fast path
	-- loop variables are adjusted by calling generator(state, index) and expecting it to return a tuple that's copied to the user variables
	-- the first variable is then copied into index; generator/state are immutable, index isn't visible to user code
	NewOpcode("FORGLOOP", "iABx", 0x6E, true),

	-- FORGPREP_INEXT: prepare FORGLOOP with 2 output variables (no AUX encoding), assuming generator is luaB_inext, and jump to FORGLOOP
	-- A: target register (see FORGLOOP for register layout)
	NewOpcode("FORGPREP_INEXT", "none", 0x51),

	-- FORGPREP_NEXT: prepare FORGLOOP with 2 output variables (no AUX encoding), assuming generator is luaB_next, and jump to FORGLOOP
	-- A: target register (see FORGLOOP for register layout)
	NewOpcode("FORGPREP_NEXT", "none", 0x17),

	-- NATIVECALL: start executing new function in native code
	-- this is a pseudo-instruction that is never emitted by bytecode compiler, but can be constructed at runtime to accelerate native code dispatch
	NewOpcode("NATIVECALL", "none", 0xFA),

	-- GETVARARGS: copy variables into the target register from vararg storage for current function
	-- A: target register
	-- B: variable count + 1, or 0 to copy all variables and adjust top (MULTRET)
	NewOpcode("GETVARARGS", "iAB", 0xDD),

	-- DUPCLOSURE: create closure from a pre-created function object (reusing it unless environments diverge)
	-- A: target register
	-- D: constant table index (0..32767)
	NewOpcode("DUPCLOSURE", "iABx", 0xC0),

	-- PREPVARARGS: prepare stack for variadic functions so that GETVARARGS works correctly
	-- A: number of fixed arguments
	NewOpcode("PREPVARARGS", "iA", 0xA3),

	-- LOADKX: sets register to an entry from the constant table from the proto (number/string)
	-- A: target register
	-- AUX: constant table index
	NewOpcode("LOADKX", "iA", 0x86),

	-- JUMPX: jumps to the target offset; like JUMPBACK, supports interruption
	-- E: jump offset (-2^23..2^23; 0 means "next instruction" aka "don't jump")
	NewOpcode("JUMPX", "isAx", 0x69),

	-- FASTCALL: perform a fast call of a built-in function
	-- A: builtin function id (see BuiltInFunctionsMap)
	-- C: jump offset to get to following CALL
	-- FASTCALL is followed by one of (GETIMPORT, MOVE, GETUPVAL) instructions and by CALL instruction
	-- This is necessary so that if FASTCALL can't perform the call inline, it can continue normal execution
	-- If FASTCALL *can* perform the call, it jumps over the instructions *and* over the next CALL
	-- Note that FASTCALL will read the actual call arguments, such as argument/result registers and counts, from the CALL instruction
	NewOpcode("FASTCALL", "iAC", 0x4C),

	-- COVERAGE: update coverage information stored in the instruction
	-- E: hit count for the instruction (0..2^23-1)
	-- The hit count is incremented by VM every time the instruction is executed, and saturates at 2^23-1
	NewOpcode("COVERAGE", "isAx", 0x2F),

	-- CAPTURE: capture a local or an upvalue as an upvalue into a newly created closure; only valid after NEWCLOSURE
	-- A: capture type
	-- B: source register (for VAL/REF) or upvalue index (for UPVAL/UPREF)
	NewOpcode("CAPTURE", "iAB", 0x12),

	-- SUBRK, DIVRK: compute arithmetic operation between the constant and a source register and put the result into target register
	-- A: target register
	-- B: constant table index (0..255); must refer to a number
	-- C: source register
	NewOpcode("SUBRK", "iABx", 0xF5, true),
	NewOpcode("DIVRK", "iABx", 0xD8, true),

	-- FASTCALL1: perform a fast call of a built-in function using 1 register argument
	-- A: builtin function id (see BuiltInFunctionsMap)
	-- B: source argument register
	-- C: jump offset to get to following CALL
	NewOpcode("FASTCALL1", "iABC", 0xBB),

	-- FASTCALL2: perform a fast call of a built-in function using 2 register arguments
	-- A: builtin function id (see BuiltInFunctionsMap)
	-- B: source argument register
	-- C: jump offset to get to following CALL
	-- AUX: source register 2 in least-significant byte
	NewOpcode("FASTCALL2", "iABC", 0x9E, true),

	-- FASTCALL2K: perform a fast call of a built-in function using 1 register argument and 1 constant argument
	-- A: builtin function id (see BuiltInFunctionsMap)
	-- B: source argument register
	-- C: jump offset to get to following CALL
	-- AUX: constant index
	NewOpcode("FASTCALL2K", "iABC", 0x81, true),

	-- FASTCALL3: perform a fast call of a built-in function using 3 register arguments
	-- A: builtin function id (see BuiltInFunctionsMap)
	-- B: source argument register
	-- C: jump offset to get to following CALL
	-- AUX: source register 2 in least-significant byte
	-- AUX: source register 3 in second least-significant byte
	NewOpcode("FASTCALL3", "iABC", 0x34, true),

	-- FORGPREP: prepare loop variables for a generic for loop, jump to the loop backedge unconditionally
	-- A: target register; generic for loops assume a register layout [generator, state, index, variables...]
	-- D: jump offset (-32768..32767)
	NewOpcode("FORGPREP", "iAB", 0x64),

	-- JUMPXEQKNIL, JUMPXEQKB: jumps to target offset if the comparison with constant is true (or false, see AUX)
	-- A: source register 1
	-- D: jump offset (-32768..32767; 1 means "next instruction" aka "don't jump")
	-- AUX: constant value (for boolean) in low bit, NOT flag (that flips comparison result) in high bit
	NewOpcode("JUMPXEQKNIL", "iAsBx", 0x47, true),
	NewOpcode("JUMPXEQKB", "iAsBx", 0x2A, true),

	-- JUMPXEQKN, JUMPXEQKS: jumps to target offset if the comparison with constant is true (or false, see AUX)
	-- A: source register 1
	-- D: jump offset (-32768..32767; 1 means "next instruction" aka "don't jump")
	-- AUX: constant table index in low 24 bits, NOT flag (that flips comparison result) in high bit
	NewOpcode("JUMPXEQKN", "iAsBx", 0x0D, true),
	NewOpcode("JUMPXEQKS", "iAsBx", 0xF0, true),

	-- IDIV: compute floor division between two source registers and put the result into target register
	-- A: target register
	-- B: source register 1
	-- C: source register 2
	NewOpcode("IDIV", "iABC", 0xD3),

	-- IDIVK compute floor division between the source register and a constant and put the result into target register
	-- A: target register
	-- B: source register
	-- C: constant table index (0..255)
	NewOpcode("IDIVK", "iABC", 0xB6),

	-- COUNT: count.. FRIGGIN count. COUNT. COUNT!!!!!!!!!!!!!!!!! COUNT!!@34-YTIWE-HAD VHI0HIOTGFE O-EOHJAOO-EOJgvspjodnkfbjokdnc0WUH98YFVIOIWUHO RUSHOJGD
	NewOpcode("COUNT", "none", 0x99),
}

local BuiltInFunctionsMap = { -- should be updated when no longer up to date with new roblox functions
	[0] = "none",
	[1] = "assert",
	[2] = "math.abs",
	[3] = "math.acos",
	[4] = "math.asin",
	[5] = "math.atan2",
	[6] = "math.atan",
	[7] = "math.ceil",
	[8] = "math.cosh",
	[9] = "math.cos",
	[10] = "math.deg",
	[11] = "math.exp",
	[12] = "math.floor",
	[13] = "math.fmod",
	[14] = "math.frexp",
	[15] = "math.ldexp",
	[16] = "math.log10",
	[17] = "math.log",
	[18] = "math.max",
	[19] = "math.min",
	[20] = "math.modf",
	[21] = "math.pow",
	[22] = "math.rad",
	[23] = "math.sinh",
	[24] = "math.sin",
	[25] = "math.sqrt",
	[26] = "math.tanh",
	[27] = "math.tan",
	[28] = "bit32.arshift",
	[29] = "bit32.band",
	[30] = "bit32.bnot",
	[31] = "bit32.bor",
	[32] = "bit32.bxor",
	[33] = "bit32.btest",
	[34] = "bit32.extract",
	[35] = "bit32.lrotate",
	[36] = "bit32.lshift",
	[37] = "bit32.replace",
	[38] = "bit32.rrotate",
	[39] = "bit32.rshift",
	[40] = "type",
	[41] = "string.byte",
	[42] = "string.char",
	[43] = "string.len",
	[44] = "typeof",
	[45] = "string.sub",
	[46] = "math.clamp",
	[47] = "math.sign",
	[48] = "math.round",
	[49] = "rawset",
	[50] = "rawget",
	[51] = "rawequal",
	[52] = "table.insert",
	[53] = "table.unpack",
	[54] = "vector",
	[55] = "bit32.countlz",
	[56] = "bit32.countrz",
	[57] = "select",
	[58] = "rawlen",
	[59] = "bit32.extractk",
	[60] = "getmetatable",
	[61] = "setmetatable",
	[62] = "tonumber",
	[63] = "tostring",
	[64] = "bit32.byteswap",
	[65] = "buffer.readi8",
	[66] = "buffer.readu8",
	[67] = "buffer.writeu8",
	[68] = "buffer.readi16",
	[69] = "buffer.readu16",
	[70] = "buffer.writeu16",
	[71] = "buffer.readi32",
	[72] = "buffer.readu32",
	[73] = "buffer.writeu32",
	[74] = "buffer.readf32",
	[75] = "buffer.writef32",
	[76] = "buffer.readf64",
	[77] = "buffer.writef64",
	[78] = "vector.magnitude",
	[79] = "vector.normalize",
	[80] = "vector.cross",
	[81] = "vector.dot",
	[82] = "vector.floor",
	[83] = "vector.ceil",
	[84] = "vector.abs",
	[85] = "vector.sign",
	[86] = "vector.clamp",
	[87] = "vector.min",
	[88] = "vector.max",
	[89] = "math.lerp",
}

local LbcConstantBoolean = 1
local LbcConstantNumber = 2
local LbcConstantString = 3
local LbcConstantImport = 4
local LbcConstantTable = 5
local LbcConstantClosure = 6
local LbcConstantVector = 7

for i = 1, #OpTableV6 do
	local Opcode = OpTableV6[i]
	if Opcode.Name ~= "FASTCALL3" then
		table_insert(OpTableV5, Opcode)
	end
end

local OpInfoMaps = {}
local OpTableVersionMap = {
	[6] = OpTableV6,
	[5] = OpTableV5,
}

for Version, OpTable in pairs(OpTableVersionMap) do
	local Map = {}

	for i = 1, #OpTable do
		local Info = OpTable[i]

		Map[Info.Number] = Info
	end

	OpInfoMaps[Version] = Map
end

local function DecomposeImportId(Ids)
	local Count = bit32_rshift(Ids, 30)
	local Parts = {}

	if Count > 0 then
		table_insert(Parts, bit32_band(bit32_rshift(Ids, 20), 1023))
	end

	if Count > 1 then
		table_insert(Parts, bit32_band(bit32_rshift(Ids, 10), 1023))
	end

	if Count > 2 then
		table_insert(Parts, bit32_band(Ids, 1023))
	end

	return Parts
end

local OpcodeHandlerMaps = {}
for Version, OpTable in pairs(OpTableVersionMap) do
	local Handlers = {}

	local KToStr = function(K)
		if not K then return "Invalid" end

		local Value = K.Value

		if K.Type == 3 then
			return string_format('%q', Value)
		end

		return tostring(Value)
	end

	Handlers.NOP = function(Instruction)
		return "", "-- do nothing (no-op / NOP)"
	end

	Handlers.BREAK = function(Instruction)
		return "", "-- break"
	end

	Handlers.PREPVARARGS = function(Instruction)
		local A = Instruction.A

		if A > 0 then
			return A, "-- Prepare for " .. tostring(A - 1) .. " variables as ..."
		end

		return A, "-- Prepare for any number (top) of variables as ..."
	end

	Handlers.GETVARARGS = function(Instruction)
		local A = Instruction.A
		local B = Instruction.B

		if B == 0 then
			return string_format("%d, %d", A, B), string_format("var%d, ... = ... -- Load all remaining variables", A)
		end

		local VariableCount = B - 1

		if VariableCount == 0 then
			return string_format("%d, %d", A, B), "-- GETVARARGS (0 variables)"
		end

		local VarList = table_create(VariableCount)

		for i = 0, VariableCount - 1 do
			table_insert(VarList, "var" .. tostring(A + i))
		end

		local VarString = table_concat(VarList, ", ")
		local Plural = VariableCount == 1 and "" or "s"

		return string_format("%d, %d", A, B), string_format("%s = ... -- Load %d variable%s", VarString, VariableCount, Plural)
	end

	Handlers.LOADNIL = function(Instruction)
		local A = Instruction.A

		return A, string_format("var%d = nil", A)
	end

	Handlers.LOADB = function(Instruction)
		local A = Instruction.A
		local B = Instruction.B
		local C = Instruction.C
		local CodeIndex = Instruction.CodeIndex
		local Comment = string_format("var%d = %s", A, tostring(B ~= 0))

		if C ~= 0 then
			Comment = Comment .. " -- goto [" .. tostring(CodeIndex + 1 + C) .. "]"
		end

		return string_format("%d, %d, %d", A, B, C), Comment
	end

	Handlers.LOADN = function(Instruction)
		local A = Instruction.A
		local Bx = Instruction.Bx

		return string_format("%d, %d", A, Bx), string_format("var%d = %d", A, Bx)
	end

	Handlers.LOADK = function(Instruction)
		local A = Instruction.A
		local Bx = Instruction.Bx
		local K = Instruction.Proto.KTable[Bx + 1]

		return string_format("%d, %d", A, Bx), string_format("var%d = %s", A, KToStr(K))
	end

	Handlers.LOADKX = function(Instruction)
		local A = Instruction.A
		local Aux = Instruction.Aux
		local K = Instruction.Proto.KTable[Aux + 1]

		return A, string_format("var%d = %s", A, KToStr(K))
	end

	Handlers.MOVE = function(Instruction)
		local A = Instruction.A
		local B = Instruction.B

		return string_format("%d, %d", A, B), string_format("var%d = var%d", A, B)
	end

	Handlers.GETGLOBAL = function(Instruction)
		local A = Instruction.A
		local C = Instruction.C
		local Aux = Instruction.Aux
		local Name = Instruction.StringTable[Aux + 1] or "Invalid"

		return string_format("%d, %d [%d]", A, C, Aux), string_format("var%d = %s", A, Name)
	end

	Handlers.SETGLOBAL = function(Instruction)
		local A = Instruction.A
		local C = Instruction.C
		local Aux = Instruction.Aux
		local Name = Instruction.StringTable[Aux + 1] or "Invalid"

		return string_format("%d, %d [%d]", A, C, Aux), string_format("%s = var%d", Name, A)
	end

	Handlers.GETUPVAL = function(Instruction)
		local A = Instruction.A
		local B = Instruction.B

		return string_format("%d, %d", A, B), string_format("var%d = up%d", A, B)
	end

	Handlers.SETUPVAL = function(Instruction)
		local A = Instruction.A
		local B = Instruction.B

		return string_format("%d, %d", A, B), string_format("up%d = var%d", B, A)
	end

	Handlers.CLOSEUPVALS = function(Instruction)
		local A = Instruction.A

		return A, string_format("move_upvalues_to_heap(var%d->...)", A)
	end

	Handlers.GETTABLE = function(Instruction)
		local A = Instruction.A
		local B = Instruction.B
		local C = Instruction.C

		return string_format("%d, %d, %d", A, B, C), string_format("var%d = var%d[var%d]", A, B, C)
	end

	Handlers.SETTABLE = function(Instruction)
		local A = Instruction.A
		local B = Instruction.B
		local C = Instruction.C

		return string_format("%d, %d, %d", A, B, C), string_format("var%d[var%d] = var%d", B, C, A)
	end

	Handlers.GETTABLEKS = function(Instruction)
		local A = Instruction.A
		local B = Instruction.B
		local C = Instruction.C
		local Aux = Instruction.Aux
		local K = Instruction.Proto.KTable[Aux + 1]
		local Name = KToStr(K)

		return string_format("%d, %d, %d [%d]", A, B, C, Aux), string_format("var%d = var%d[%s]", A, B, Name)
	end

	Handlers.SETTABLEKS = function(Instruction)
		local A = Instruction.A
		local B = Instruction.B
		local C = Instruction.C
		local Aux = Instruction.Aux
		local K = Instruction.Proto.KTable[Aux + 1] or "Invalid"
		local Name = KToStr(K)

		return string_format("%d, %d, %d [%d]", A, B, C, Aux), string_format("var%d[%s] = var%d", B, Name, A)
	end

	Handlers.GETTABLEN = function(Instruction)
		local A = Instruction.A
		local B = Instruction.B
		local C = Instruction.C

		return string_format("%d, %d, %d", A, B, C), string_format("var%d = var%d[%d]", A, B, C + 1)
	end

	Handlers.SETTABLEN = function(Instruction)
		local A = Instruction.A
		local B = Instruction.B
		local C = Instruction.C

		return string_format("%d, %d, %d", A, B, C), string_format("var%d[%d] = var%d", B, C + 1, A)
	end

	Handlers.NEWCLOSURE = function(Instruction)
		local A = Instruction.A
		local Bx = Instruction.Bx
		local ChildProto = Instruction.ChildProto
		local FuncName

		if ChildProto and ChildProto.Source and ChildProto.Source ~= "Invalid source index" and #ChildProto.Source > 0 and #ChildProto.Source < 500 then
			FuncName = ChildProto.Source
		else
			local ProtoIndex = (ChildProto and ChildProto.ProtoIndex) or Bx
			FuncName = "anonymous_function_" .. ProtoIndex
		end

		return string_format("%d, %d", A, Bx), string_format("var%d = %s", A, FuncName)
	end

	Handlers.NAMECALL = function(Instruction)
		local A = Instruction.A
		local B = Instruction.B
		local C = Instruction.C
		local Aux = Instruction.Aux
		local K = Instruction.Proto.KTable[Aux + 1]
		local MethodName = KToStr(K)
		local Comment = string_format("var%d = var%d; var%d = var%d.%s -- Invokes __namecall", A + 1, B, A, B, MethodName)

		return string_format("%d, %d, %d [%d]", A, B, C, Aux), Comment
	end

	Handlers.CALL = function(Instruction)
		local A = Instruction.A
		local B = Instruction.B
		local C = Instruction.C
		local ArgCount = B - 1
		local RetCount = C - 1
		local Args = ""

		if ArgCount > 0 then
			local ArgList = {}

			for J = 1, ArgCount do
				table_insert(ArgList, "var" .. (A + J))
			end

			Args = table_concat(ArgList, ", ")
		elseif B == 0 then
			Args = "var" .. (A + 1) .. "->(top)"
		end

		local Rets = ""
		if RetCount >= 1 then
			local RetList = {}

			for J = 0, RetCount - 1 do
				table_insert(RetList, "var" .. (A + J))
			end

			Rets = table_concat(RetList, ", ")
		elseif C == 0 then
			Rets = "var" .. A .. "->(top)"
		end

		local CallStr = string_format("var%d(%s)", A, Args)

		if Rets ~= "" then
			CallStr = Rets .. " = " .. CallStr
		end

		return string_format("%d, %d, %d", A, B, C), CallStr
	end

	Handlers.RETURN = function(Instruction)
		local A = Instruction.A
		local B = Instruction.B
		local RetStr

		if B == 0 then
			RetStr = "return var" .. A .. "->(top)"
		elseif B == 1 then
			RetStr = "return"
		else
			local Rets = {}

			for J = 0, B - 2 do
				table_insert(Rets, "var" .. (A + J))
			end

			RetStr = "return " .. table_concat(Rets, "->")
		end

		return string_format("%d, %d", A, B), RetStr
	end

	Handlers.JUMP = function(Instruction)
		local SBx = Instruction.SBx
		local CodeIndex = Instruction.CodeIndex

		return SBx, string_format("-- goto [%d]", CodeIndex + 1 + SBx)
	end

	Handlers.JUMPBACK = function(Instruction)
		local SBx = Instruction.SBx
		local CodeIndex = Instruction.CodeIndex

		return SBx, string_format("-- goto [%d] (likely while/repeat loop)", CodeIndex + 1 + SBx)
	end

	Handlers.JUMPX = function(Instruction)
		local SAx = Instruction.SAx
		local CodeIndex = Instruction.CodeIndex

		return SAx, string_format("-- goto [%d]", CodeIndex + 1 + SAx)
	end

	Handlers.FORNPREP = function(Instruction)
		local A = Instruction.A
		local Bx = Instruction.Bx
		local CodeIndex = Instruction.CodeIndex
		local Comment = string_format("for var%d = var%d, var%d, var%d do -- If loop shouldn't start (var%d > var%d) then goto [%d]", A + 3, A, A + 1, A + 2, A, A + 1, CodeIndex + 1 + Bx + 1)

		return string_format("%d, %d", A, Bx), Comment
	end

	Handlers.FORNLOOP = function(Instruction)
		local A = Instruction.A
		local SBx = Instruction.SBx
		local CodeIndex = Instruction.CodeIndex
		local Comment = string_format("var%d += var%d; if var%d <= var%d then goto [%d] end", A + 3, A + 2, A + 3, A + 1, CodeIndex + 1 + SBx)

		return string_format("%d, %d", A, SBx), Comment
	end

	Handlers.FORGPREP = function(Instruction)
		local A = Instruction.A
		local Bx = Instruction.Bx
		local CodeIndex = Instruction.CodeIndex
		local Comment = string_format("for var%d->... in var%d, var%d, var%d do -- If loop shouldn't start then goto [%d]", A + 3, A, A + 1, A + 2, CodeIndex + 1 + Bx + 1)

		return string_format("%d, %d", A, Bx), Comment
	end

	Handlers.FORGPREP_INEXT = Handlers.FORGPREP
	Handlers.FORGPREP_NEXT = Handlers.FORGPREP
	Handlers.FORGLOOP = function(Instruction)
		local A = Instruction.A
		local SBx = Instruction.SBx
		local Aux = Instruction.Aux or 0
		local CodeIndex = Instruction.CodeIndex
		local C = bit32.band(Aux, 0xFF)
		local Rets = {}

		if C >= 1 then
			for J = 0, C - 1 do
				table_insert(Rets, "var" .. (A + 3 + J))
			end
		end

		local ReturnVarsStr = table_concat(Rets, ", ")
		local JumpTarget = CodeIndex + SBx
		local OperandsStr = string_format("%d, %d [0x%08X]", A, SBx, Aux)
		local CommentStr = string_format("%s = var%d(var%d, var%d); if var%d ~= nil then goto [%d] end", ReturnVarsStr, A, A + 1, A + 2, A + 3, JumpTarget)

		return OperandsStr, CommentStr
	end

	Handlers.MINUS = function(Instruction)
		local A = Instruction.A
		local B = Instruction.B

		return string_format("%d, %d", A, B), string_format("var%d = -var%d", A, B)
	end

	Handlers.LENGTH = function(Instruction)
		local A = Instruction.A
		local B = Instruction.B

		return string_format("%d, %d", A, B), string_format("var%d = #var%d", A, B)
	end

	Handlers.NEWTABLE = function(Instruction)
		local A = Instruction.A
		local B = Instruction.B
		local Aux = Instruction.Aux or 0
		local Comment

		if Aux == 0 then
			Comment = "{}"
		else
			Comment = "table.create(" .. Aux .. ")"
		end

		return string_format("%d, %d [%d]", A, B, Aux), string_format("var%d = %s", A, Comment)
	end

	Handlers.DUPTABLE = function(Instruction)
		local A = Instruction.A
		local Bx = Instruction.Bx

		return string_format("%d, %d", A, Bx), string_format("var%d = {} -- from template %d", A, Bx)
	end

	Handlers.SETLIST = function(Instruction)
		local A = Instruction.A
		local B = Instruction.B
		local C = Instruction.C
		local Aux = Instruction.Aux
		local Count = C - 1
		local StartIndex = Aux
		local EndIndex = StartIndex + Count - 1
		local SourceVars = {}

		for J = 1, Count do
			table_insert(SourceVars, "var" .. (A + J))
		end

		local Comment = string_format("var%d[%d->%d] = %s", A, StartIndex, EndIndex, table_concat(SourceVars, "->"))

		return string_format("%d, %d, %d [%d]", A, B, C, Aux), Comment
	end

	Handlers.CONCAT = function(Instruction)
		local A = Instruction.A
		local B = Instruction.B
		local C = Instruction.C

		return string_format("%d, %d, %d", A, B, C), string_format("var%d = var%d .. var%d", A, B, C)
	end

	Handlers.NOT = function(Instruction)
		local A = Instruction.A
		local B = Instruction.B

		return string_format("%d, %d", A, B), string_format("var%d = not var%d", A, B)
	end

	Handlers.DUPCLOSURE = function(Instruction)
		local A = Instruction.A
		local Bx = Instruction.Bx
		local K = Instruction.Proto.KTable[Bx + 1]
		local ProtoIndex = K.Value
		local TargetProtoData

		if Instruction.AllProtos then
			TargetProtoData = Instruction.AllProtos[ProtoIndex + 1]
		end

		local FuncName

		if TargetProtoData and TargetProtoData.RawProto.Source and TargetProtoData.RawProto.Source ~= "Invalid source index" and #TargetProtoData.RawProto.Source < 500 then
			FuncName = TargetProtoData.RawProto.Source
		else
			FuncName = "anonymous_function_" .. ProtoIndex
		end

		return string_format("%d, %d", A, Bx), string_format("var%d = %s", A, FuncName)
	end

	Handlers.GETIMPORT = function(Instruction)
		local A = Instruction.A
		local Bx = Instruction.Bx
		local Aux = Instruction.Aux or 0
		local Proto = Instruction.Proto
		local ImportKonstant = Proto.KTable[Bx + 1]

		if not ImportKonstant or ImportKonstant.Type ~= 4 then
			return string_format("%d, %d", A, Bx), string_format("var%d = --[[ Invalid Import Constant at K%d ]]", A, Bx)
		end

		local ImportId = ImportKonstant.Value
		local Ids = DecomposeImportId(ImportId)
		local ImportedPathParts = {}
		local IdsLen = #Ids

		for i = 1, IdsLen do
			local StringKIndex = Ids[i]
			local StringK = Proto.KTable[StringKIndex + 1]

			if StringK and StringK.Type == 3 then
				table_insert(ImportedPathParts, StringK.Value)
			else
				table_insert(ImportedPathParts, "InvalidImportPart")
			end
		end

		local ImportedPath = table_concat(ImportedPathParts, ".")

		if #ImportedPath == 0 then ImportedPath = "unknown_import" end

		local OperandsStr = string_format("%d, %d [0x%X]", A, Bx, Aux)
		local CommentStr = string_format("var%d = %s", A, ImportedPath)

		return OperandsStr, CommentStr
	end

	Handlers.CAPTURE = function(Instruction)
		local A = Instruction.A
		local B = Instruction.B
		local UpvalIndex = Instruction.UpvalIndex
		local T = { [0] = "Readable", [1] = "Readable and writable", [2] = "Upvalue" }

		return string_format("%d, %d", A, B), string_format("up%d = var%d -- %s", UpvalIndex, B, T[A] or "UNKOWN")
	end

	local function MakeJumpHandler(Op, Sym, NotOp)
		return function(Instruction)
			local A = Instruction.A
			local C = Instruction.C
			local AuxIsK = Instruction.AuxIsK
			local Proto = Instruction.Proto
			local CodeIndex = Instruction.CodeIndex
			local SBx = Instruction.SBx
			local KStr = AuxIsK and KToStr(Proto.KTable[C + 1]) or ("var" .. C)
			local Condition = string_format("var%d %s %s", A, Sym, KStr)

			if NotOp then Condition = "not (" .. Condition .. ")" end

			local Comment = string_format("if %s then goto [%d] end", Condition, CodeIndex + 1 + SBx)

			return string_format("%d, %d [%d]", A, C, Instruction.Aux), Comment
		end
	end

	local JumpOps = { EQ = "==", LE = "<=", LT = "<" }

	for Op, Sym in pairs(JumpOps) do
		Handlers["JUMPIF" .. Op] = MakeJumpHandler(Op, Sym, false)
		Handlers["JUMPIFNOT" .. Op] = MakeJumpHandler(Op, Sym, true)
	end

	Handlers["JUMPIFEQ"] = function(Instruction)
		local A = Instruction.A
		local C = Instruction.C
		local Aux = Instruction.Aux
		local CodeIndex = Instruction.CodeIndex
		local SBx = Instruction.SBx

		return string_format("%d, %d [%d]", A, C, Aux), string_format("if var%d == var%d then goto [%d] end", A, C, CodeIndex + 1 + SBx)
	end

	Handlers["JUMPIFNOTEQ"] = function(Instruction)
		local A = Instruction.A
		local C = Instruction.C
		local Aux = Instruction.Aux
		local CodeIndex = Instruction.CodeIndex
		local SBx = Instruction.SBx

		return string_format("%d, %d [%d]", A, C, Aux), string_format("if var%d ~= var%d then goto [%d] end", A, C, CodeIndex + 1 + SBx)
	end

	Handlers["JUMPIF"] = function(Instruction)
		local A = Instruction.A
		local SBx = Instruction.SBx
		local CodeIndex = Instruction.CodeIndex

		return string_format("%d, %d", A, SBx), string_format("if var%d then goto [%d] end", A, CodeIndex + 1 + SBx)
	end

	Handlers["JUMPIFNOT"] = function(Instruction)
		local A = Instruction.A
		local SBx = Instruction.SBx
		local CodeIndex = Instruction.CodeIndex

		return string_format("%d, %d", A, SBx), string_format("if not var%d then goto [%d] end", A, CodeIndex + 1 + SBx)
	end

	local function MakeJUMPXEQKHandler(ConstType)
		return function(Instruction)
			local A = Instruction.A
			local C = Instruction.C
			local Aux = Instruction.Aux
			local SBx = Instruction.SBx
			local CodeIndex = Instruction.CodeIndex
			local Proto = Instruction.Proto
			local IsNot = bit32_band(Aux, 0x80000000) ~= 0
			local OpSym = IsNot and "~=" or "=="
			local ConstData = bit32_band(Aux, 0x7FFFFFFF)
			local TargetPc = CodeIndex + 1 + SBx
			local ConstStr = "???"

			if ConstType == "NIL" then
				ConstStr = "nil"
			elseif ConstType == "B" then
				ConstStr = (ConstData == 1) and "true" or "false"
			elseif ConstType == "N" or ConstType == "S" then
				local K = Proto.KTable[ConstData + 1]
				ConstStr = KToStr(K)
			end

			local OperandsStr = string_format("%d, %d [0x%08X]", A, C, Aux)
			local CommentStr = string_format("if var%d %s %s then goto [%d] end", A, OpSym, ConstStr, TargetPc)

			return OperandsStr, CommentStr
		end
	end

	Handlers["JUMPXEQKNIL"] = MakeJUMPXEQKHandler("NIL")
	Handlers["JUMPXEQKB"] = MakeJUMPXEQKHandler("B")
	Handlers["JUMPXEQKN"] = MakeJUMPXEQKHandler("N")
	Handlers["JUMPXEQKS"] = MakeJUMPXEQKHandler("S")

	local MathOps = { ADD = "+", SUB = "-", MUL = "*", DIV = "/", IDIV = "//", MOD = "%", POW = "^" }

	for Op, Sym in pairs(MathOps) do
		Handlers[Op] = function(Instruction)
			local A = Instruction.A
			local B = Instruction.B
			local C = Instruction.C

			return string_format("%d, %d, %d", A, B, C), string_format("var%d = var%d %s var%d", A, B, Sym, C)
		end

		Handlers[Op .. "K"] = function(Instruction)
			local A = Instruction.A
			local B = Instruction.B
			local C = Instruction.C
			local K = Instruction.Proto.KTable[C + 1]

			return string_format("%d, %d, %d", A, B, C), string_format("var%d = var%d %s %s", A, B, Sym, KToStr(K))
		end
	end

	Handlers["SUBRK"] = function(Instruction)
		local A = Instruction.A
		local B = Instruction.B
		local C = Instruction.C
		local K = Instruction.Proto.KTable[B + 1]

		return string_format("%d, %d, %d", A, B, C), string_format("var%d = %s - var%d", A, KToStr(K), A)
	end

	Handlers["DIVRK"] = function(Instruction)
		local A = Instruction.A
		local B = Instruction.B
		local C = Instruction.C
		local K = Instruction.Proto.KTable[B + 1]

		return string_format("%d, %d, %d", A, B, C), string_format("var%d = %s / var%d", A, KToStr(K), A)
	end

	local AndOrOps = {"AND", "OR"}

	for i = 1, #AndOrOps do
		local Op = AndOrOps[i]
		local Sym = string_lower(Op)

		Handlers[Op] = function(Instruction)
			local A = Instruction.A
			local B = Instruction.B
			local C = Instruction.C

			return string_format("%d, %d, %d", A, B, C), string_format("var%d = var%d %s var%d", A, B, Sym, C)
		end

		Handlers[Op .. "K"] = function(Instruction)
			local A = Instruction.A
			local B = Instruction.B
			local C = Instruction.C
			local K = Instruction.Proto.KTable[C + 1]

			return string_format("%d, %d, %d", A, B, C), string_format("var%d = var%d %s %s", A, B, Sym, KToStr(K))
		end
	end

	local function GetBuiltinName(Id)
		return BuiltInFunctionsMap[Id] or "unknown_function"
	end

	Handlers.FASTCALL = function(Instruction)
		local A = Instruction.A
		local C = Instruction.C
		local FuncName = GetBuiltinName(A)

		return string_format("%d, %d", A, C), string_format("... = %s(...)", FuncName)
	end

	Handlers.FASTCALL1 = function(Instruction)
		local A = Instruction.A
		local B = Instruction.B
		local C = Instruction.C
		local FuncName = GetBuiltinName(A)

		return string_format("%d, %d, %d", A, B, C), string_format("... = %s(var%d)", FuncName, B)
	end

	Handlers.FASTCALL2 = function(Instruction)
		local A = Instruction.A
		local B = Instruction.B
		local C = Instruction.C
		local Aux = Instruction.Aux
		local FuncName = GetBuiltinName(A)
		local Arg2 = bit32_band(Aux, 0xFF)

		return string_format("%d, %d, %d [0x%X]", A, B, C, Aux), string_format("... = %s(var%d, var%d)", FuncName, B, Arg2)
	end

	Handlers.FASTCALL2K = function(Instruction)
		local A = Instruction.A
		local B = Instruction.B
		local C = Instruction.C
		local Aux = Instruction.Aux
		local Proto = Instruction.Proto
		local FuncName = GetBuiltinName(A)
		local K = Proto.KTable[Aux + 1]

		return string_format("%d, %d, %d [0x%X]", A, B, C, Aux), string_format("... = %s(var%d, %s)", FuncName, B, KToStr(K))
	end

	Handlers.FASTCALL3 = function(Instruction)
		local A = Instruction.A
		local B = Instruction.B
		local C = Instruction.C
		local Aux = Instruction.Aux
		local FuncName = GetBuiltinName(A)
		local Arg2 = bit32_band(Aux, 0xFF)
		local Arg3 = bit32_band(bit32_rshift(Aux, 8), 0xFF)

		return string_format("%d, %d, %d [0x%X]", A, B, C, Aux), string_format("... = %s(var%d, var%d, var%d)", FuncName, B, Arg2, Arg3)
	end

	OpcodeHandlerMaps[Version] = Handlers
end

local function GetOpcode(Instruction, IsFromRoblox)
	if not IsFromRoblox then
		Instruction = Instruction * 227
	end

    local Opcode = bit32_band(Instruction, 0xFF)

    if IsFromRoblox then
        Opcode = (Opcode * 203) % 256 -- inverse of 227 mod 256
    end

    return Opcode
end

local function GetArgA(Instruction)
	return bit32_band(bit32_rshift(Instruction, 8), 0xFF)
end

local function GetArgB(Instruction)
	return bit32_band(bit32_rshift(Instruction, 16), 0xFF)
end

local function GetArgC(Instruction)
	return bit32_band(bit32_rshift(Instruction, 24), 0xFF)
end

local function GetArgBx(Instruction)
	return bit32_rshift(Instruction, 16)
end

local function GetArgSBx(Instruction)
	local Bx = bit32_rshift(Instruction, 16)

	return Bx >= 0x8000 and Bx - 0x10000 or Bx
end

local function GetArgSAx(Instruction)
	return bit32_rshift(Instruction, 8)
end

---

local ReadProto
local Deserialize

local Disassembler = {}

local function CreateEmptyProto()
	return {
		CodeTable = {},
		KTable = {},
		PTable = {},
		SmallLineInfo = {},
		LargeLineInfo = {},
		LineInfoCompKey = 0,
		Locals = {},
		UpvalNames = {},
	}
end

local Buf, Offset, CurrentBufferLen

local function CanRead(N)
	return Offset + N <= CurrentBufferLen
end

local function CheckRead(N, ErrorMsg)
	if not CanRead(N) then
		error(string_format("%s at position %d, but buffer length is %d", ErrorMsg, Offset, CurrentBufferLen))
	end
end

local function NextByte()
	CheckRead(1, "Attempted to read 1 byte")
	local Value = buffer_readu8(Buf, Offset)

	Offset = Offset + 1

	return Value
end

local function NextUint32()
	CheckRead(4, "Attempted to read 4 bytes for Uint32")
	local Value = buffer_readu32(Buf, Offset)

	Offset = Offset + 4

	return Value
end

local function NextInt()
	CheckRead(4, "Attempted to read 4 bytes for Int32")
	local Value = buffer_readi32(Buf, Offset)

	Offset = Offset + 4

	return Value
end

local function NextFloat()
	CheckRead(4, "Attempted to read 4 bytes for Float32")
	local Value = buffer_readf32(Buf, Offset)

	Offset = Offset + 4

	return Value
end

local function NextDouble()
	CheckRead(8, "Attempted to read 8 bytes for Float64")
	local Value = buffer_readf64(Buf, Offset)

	Offset = Offset + 8

	return Value
end

local function NextVarInt()
	local Result = 0
	local Shift = 0

	while true do
		local B = NextByte()

		Result = bit32_bor(Result, bit32_lshift(bit32_band(B, 0x7F), Shift))

		if bit32_band(B, 0x80) == 0 then
			break
		end

		Shift = Shift + 7
	end

	return Result
end

local function NextString()
	local Length = NextVarInt()

	if Length == 0 then
		return ""
	end

	CheckRead(Length, ("Attempted to read string of length %d"):format(Length))
	local Result = buffer_readstring(Buf, Offset, Length)

	Offset = Offset + Length

	return Result
end

function Disassembler.ReadConstant(StringTable)
	local K = { Type = NextByte() }

	if K.Type == LbcConstantBoolean then
		K.Value = NextByte() == 1
	elseif K.Type == LbcConstantNumber then
		K.Value = NextDouble()
	elseif K.Type == LbcConstantString then
		local Index = NextVarInt()
		K.Value = StringTable[Index] or "Invalid string index"
	elseif K.Type == LbcConstantImport then
		K.Value = NextUint32()
	elseif K.Type == LbcConstantTable then
		local SizeKey = NextVarInt()
		local Keys = table_create(SizeKey)

		for I = 1, SizeKey do
			Keys[I] = NextVarInt() + 1
		end

		K.Value = { Size = SizeKey, Ids = Keys }
	elseif K.Type == LbcConstantClosure then
		K.Value = NextVarInt()
	elseif K.Type == LbcConstantVector then
		local Vec = table_create(4)

		for I = 1, 4 do
			Vec[I] = NextFloat()
		end

		K.Value = Vec
	elseif K.Type ~= 0 then
		error("Unrecognized constant type: " .. tostring(K.Type))
	end

	return K
end

local function ReadProtoSource(StringTable)
	local ProtoSourceId = NextVarInt()

	return StringTable[ProtoSourceId] or "Invalid source index"
end

local function ReadLineInfo(Proto)
	Proto.LineInfoCompKey = NextByte()

	local LineInterval = 2 ^ Proto.LineInfoCompKey
	local SmallLineInfo = table_create(Proto.SizeCode)
	local LastOffset = 0

	for I = 1, Proto.SizeCode do
		LastOffset = bit32_band(LastOffset + NextByte(), 0xFF)
		SmallLineInfo[I] = LastOffset
	end

	local Intervals = math_floor((Proto.SizeCode - 1) / LineInterval) + 1
	local LargeLineInfo = table_create(Intervals)
	local LastLine = 0

	for I = 1, Intervals do
		LastLine = LastLine + NextInt()
		LargeLineInfo[I] = LastLine
	end

	Proto.InstructionLines = table_create(Proto.SizeCode)

	for Pc = 1, Proto.SizeCode do
		local IntervalIndex = math_floor((Pc - 1) / LineInterval) + 1
		Proto.InstructionLines[Pc] = LargeLineInfo[IntervalIndex] + SmallLineInfo[Pc]
	end
end

local function ReadProtoData(Proto, StringTable, ProtoTableRef)
	Proto.MaxStackSize = NextByte()
	Proto.NumParams = NextByte()
	Proto.NumUpvalues = NextByte()
	Proto.IsVarArg = NextByte() ~= 0
	Proto.Flags = NextByte()

	local TypeSize = NextVarInt()

	Proto.TypeInfo = TypeSize > 0 and table_create(TypeSize) or {}

	for I = 1, TypeSize do
		Proto.TypeInfo[I] = NextByte()
	end

	Proto.SizeCode = NextVarInt()
	Proto.CodeTable = table_create(Proto.SizeCode)

	for I = 1, Proto.SizeCode do
		Proto.CodeTable[I] = NextUint32()
	end

	Proto.SizeConsts = NextVarInt()
	Proto.KTable = table_create(Proto.SizeConsts)

	for I = 1, Proto.SizeConsts do
		Proto.KTable[I] = Disassembler.ReadConstant(StringTable)
	end

	Proto.SizeProtos = NextVarInt()
	Proto.PTable = Proto.SizeProtos > 0 and table_create(Proto.SizeProtos) or {}

	for I = 1, Proto.SizeProtos do
		Proto.PTable[I] = ProtoTableRef[NextVarInt() + 1]
	end

	Proto.LineDefined = NextVarInt()
	Proto.Source = ReadProtoSource(StringTable)

	if NextByte() == 1 then
		ReadLineInfo(Proto)
	else
		Proto.InstructionLines = nil
	end

	if NextByte() == 1 then
		local SizeLocals = NextVarInt()

		Proto.Locals = SizeLocals > 0 and table_create(SizeLocals) or {}

		for _ = 1, SizeLocals do
			table_insert(Proto.Locals, {
				Name = StringTable[NextVarInt()] or "invalid_local_name",
				StartPC = NextVarInt(),
				EndPC = NextVarInt(),
				Register = NextByte(),
			})
		end

		local SizeUpvals = NextVarInt()

		Proto.UpvalNames = SizeUpvals > 0 and table_create(SizeUpvals) or {}

		for _ = 1, SizeUpvals do
			table_insert(Proto.UpvalNames, StringTable[NextVarInt()] or "invalid_upval_name")
		end
	end
end

local function DeserializeInternal(Version)
	local TypesVersion = NextByte()

	if not table_find({ 1, 2, 3 }, TypesVersion) then
		error("Invalid types version (types version: " .. tostring(TypesVersion) .. ")")
	end

	local SizeStrings = NextVarInt()
	local StringTable = table_create(SizeStrings)

	for I = 1, SizeStrings do
		StringTable[I] = NextString()
	end

	if TypesVersion >= 3 then
		while NextByte() ~= 0 do end
	end

	local SizeProtos = NextVarInt()
	local ProtoTable = table_create(SizeProtos)

	for I = 1, SizeProtos do
		ProtoTable[I] = CreateEmptyProto()
		ProtoTable[I].ProtoIndex = I - 1
	end

	for I = 1, SizeProtos do
		ReadProtoData(ProtoTable[I], StringTable, ProtoTable)
	end

	local MainProtoId = NextVarInt() + 1

	if MainProtoId > #ProtoTable then
		error("Index " .. MainProtoId .. " out of range for ProtoTable with length " .. #ProtoTable)
	end

	return ProtoTable[MainProtoId], ProtoTable, StringTable, Version, TypesVersion
end

Deserialize = function(InputBytecode)
	Buf = buffer_fromstring(InputBytecode)
	Offset = 0
	CurrentBufferLen = buffer_len(Buf)

	local Version = NextByte()

	if Version == 5 or Version == 6 then
		return DeserializeInternal(Version)
	else
		return error("Unsupported bytecode version: " .. tostring(Version))
	end
end

ReadProto = function(Proto, Depth, ProtoTable, StringTable, LuauVersion, IsFromRoblox)
	if not OpInfoMaps[LuauVersion] then
		error("Unsupported Luau version for disassembly: " .. tostring(LuauVersion))
	end

	local ProtoOutput = {
		ProtoIndex = Proto.ProtoIndex,
		LineDefined = Proto.LineDefined,
		Source = Proto.Source,
		NumParams = Proto.NumParams,
		IsVarArg = Proto.IsVarArg,
		MaxStackSize = Proto.MaxStackSize,
		Instructions = table_create(Proto.SizeCode),
		Constants = {},
		Protos = {},
		RawProto = Proto,
	}

	local KTable = Proto.KTable
	local KTableLen = #KTable

	for i = 1, KTableLen do
		table_insert(ProtoOutput.Constants, KTable[i])
	end

	local OpInfoMap = OpInfoMaps[LuauVersion]
	local CodeTable = Proto.CodeTable
	local CurrentPc = 1

	while CurrentPc <= #CodeTable do
		local InstructionInt = CodeTable[CurrentPc]
		local OpcodeNum = GetOpcode(InstructionInt, IsFromRoblox)
		local OpInfo = OpInfoMap[OpcodeNum]
		local Opname = OpInfo and OpInfo.Name or "UNKNOWN"

		local InstructionData = {
			Name = Opname,
			Opcode = OpcodeNum,
			A = GetArgA(InstructionInt),
			B = GetArgB(InstructionInt),
			C = GetArgC(InstructionInt),
			Bx = GetArgBx(InstructionInt),
			SBx = GetArgSBx(InstructionInt),
			SAx = GetArgSAx(InstructionInt),
			Line = Proto.InstructionLines and Proto.InstructionLines[CurrentPc] or -1,
			Pc = CurrentPc,
		}

		if OpInfo and OpInfo.Aux then
			CurrentPc = CurrentPc + 1

			if CurrentPc <= #CodeTable then
				InstructionData.Aux = CodeTable[CurrentPc]
			else
				InstructionData.Aux = "Missing AUX value"
			end
		end

		table_insert(ProtoOutput.Instructions, InstructionData)
		CurrentPc = CurrentPc + 1
	end

	local PTable = Proto.PTable
	local PTableLen = #PTable

	for i = 1, PTableLen do
		table_insert(ProtoOutput.Protos, ReadProto(PTable[i], Depth + 1, ProtoTable, StringTable, LuauVersion))
	end

	return ProtoOutput
end

function Disassembler.Disassemble(Bytecode, IsFromRoblox)
	if string_byte(Bytecode, 1) == 0 then
		local sourceOutput = {{
			type = "source",
			content = string_sub(Bytecode, 2),
		}}

		return sourceOutput, 0, -1, -1
	end

	local Ok, MainProto, ProtoTable, StringTable, LuauVersion, TypesVersion = pcall(Deserialize, Bytecode)

	if not Ok then
		error("Failed to deserialize bytecode: " .. tostring(MainProto))
	end

	local DisassembledProtos = table_create(#ProtoTable)
	local MainProtoData
	local ProtoTableLen = #ProtoTable

	for i = 1, ProtoTableLen do
		local Proto = ProtoTable[i]
		local ProcessedProto = ReadProto(Proto, 1, ProtoTable, StringTable, LuauVersion, IsFromRoblox)
		DisassembledProtos[i] = ProcessedProto

		if Proto == MainProto then
			MainProtoData = ProcessedProto
		end
	end

	return {
		MainProto = MainProtoData,
		Protos = DisassembledProtos,
		ProtoCount = #ProtoTable,
		LuauVersion = LuauVersion,
		TypesVersion = TypesVersion,
		StringTable = StringTable
	}
end

function Disassembler.FancyDisassemble(Bytecode, ShoveIntoOneString, IsFromRoblox)
	ShoveIntoOneString = ShoveIntoOneString or false
	local OutputParts = {}

	local function PrintOrConcat(Text)
		if ShoveIntoOneString then
			table_insert(OutputParts, Text)
		else
			print(Text)
		end
	end

	local StartBenchmark = os_clock()
	local Result = { pcall(Disassembler.Disassemble, Bytecode, IsFromRoblox) }
	local EndBenchmark = os_clock() - StartBenchmark

	if not Result[1] then
		PrintOrConcat("Disassembly failed: " .. tostring(Result[2]))

		if ShoveIntoOneString then
			return table_concat(OutputParts, "\n")
		end

		return
	end

	local Metadata = Result[2]
	local DisassembledProtos = Metadata.Protos
	local ProtosCount = Metadata.ProtoCount
	local LuauVersion = Metadata.LuauVersion
	local TypesVersion = Metadata.TypesVersion
	local StringTable = Metadata.StringTable

	PrintOrConcat("-- Disassembled with 0x1437's disassembler")
	PrintOrConcat("-- https://github.com/0x1437/Luau-Bytecode-Diassembler")
	PrintOrConcat("-- Inspired by @plusgiant5's Konstant Disassembler")
	PrintOrConcat("-- Disassembled on " .. os.date("%Y-%m-%d %H:%M:%S", os.time()))
	PrintOrConcat("-- Luau version " .. tostring(LuauVersion) .. ", Types version " .. tostring(TypesVersion))
	PrintOrConcat("-- Time taken: " .. string_format("%.8fs", EndBenchmark))
	PrintOrConcat("")

	if ProtosCount == 0 and DisassembledProtos and #DisassembledProtos > 0 and DisassembledProtos[1].type == "source" then
		PrintOrConcat(DisassembledProtos[1].content)

		if ShoveIntoOneString then
			return table_concat(OutputParts, "\n") 
		end

		return
	end

	if not DisassembledProtos then
		PrintOrConcat("Disassembly failed.")
		
		if ShoveIntoOneString then
			return table_concat(OutputParts, "\n")
		end
		
		return
	end

	local PrintedProtos = {}
	local function PrintProtoRecursive(ProtoData, Depth, IsMain, AllProtos)
		local TabSpace = string_rep("    ", Depth)
		local RawProto = ProtoData.RawProto

		if not IsMain then
			local FuncName

			if RawProto.Source and RawProto.Source ~= "Invalid source index" and #RawProto.Source > 0 and #RawProto.Source < 500 then
				FuncName = RawProto.Source
			else
				FuncName = "anonymous_function_" .. ProtoData.ProtoIndex
			end

			local ParamNames = table_create(ProtoData.NumParams)

			for i = 1, ProtoData.NumParams do
				ParamNames[i] = "var" .. (i - 1)
			end

			if RawProto.Locals then
				local RawProtoLocals = RawProto.Locals
				local RawProtoLocalsLen = #RawProtoLocals

				for i = 1, RawProtoLocalsLen do
					local LocalInfo = RawProtoLocals[i]
					
					if LocalInfo.StartPC == 0 and LocalInfo.Register < ProtoData.NumParams then
						ParamNames[LocalInfo.Register + 1] = LocalInfo.Name
					end
				end
			end

			local Params = table_create(ProtoData.NumParams + (ProtoData.IsVarArg and 1 or 0))

			for i = 1, ProtoData.NumParams do
				table_insert(Params, ParamNames[i])
			end

			if ProtoData.IsVarArg then
				table_insert(Params, "...")
			end

			local ParamString = table_concat(Params, ", ")
			local Signature = FuncName .. "(" .. ParamString .. ")"

			if ProtoData.LineDefined > 0 then
				Signature = Signature .. string_format(" -- Line %d", ProtoData.LineDefined)
			end

			local ProtoInfoComment = string_format("-- %d parameters, %d upvalues, %d constants, %d functions", RawProto.NumParams, RawProto.NumUpvalues, RawProto.SizeConsts, RawProto.SizeProtos)

			if not ShoveIntoOneString then
				print(TabSpace .. "")
				PrintOrConcat(TabSpace .. ProtoInfoComment)
				PrintOrConcat(TabSpace .. "local function " .. Signature)
			else
				PrintOrConcat("\n" .. TabSpace .. ProtoInfoComment)
				PrintOrConcat(TabSpace .. "local function " .. Signature)
			end
		end

		local InnerTabSpace = string_rep("    ", Depth + (IsMain and 0 or 1))
		local JumpTargets = {}
		local OpInfoMap_v = OpInfoMaps[LuauVersion]
		local Handlers_v = OpcodeHandlerMaps[LuauVersion]
		local CodeTable = RawProto.CodeTable
		local CodeTableLength = #CodeTable
		local ProtoInstructionLines = RawProto.InstructionLines

		for Index = 1, CodeTableLength do
			local Instruction = CodeTable[Index]
			local OpcodeNum = GetOpcode(Instruction, IsFromRoblox)
			local OpInfo = OpInfoMap_v[OpcodeNum]

			if OpInfo and OpInfo.Type:find("sBx") then
				local SBx = GetArgSBx(Instruction)
				local Target = Index + 1 + SBx

				JumpTargets[Target] = (JumpTargets[Target] or "") .. "::" .. tostring(Index) .. "::, "
			elseif OpInfo and OpInfo.Name == "JUMPBACK" then
				local Bx = GetArgBx(Instruction)
				local Target = Index + 1 - Bx

				JumpTargets[Target] = (JumpTargets[Target] or "") .. "::" .. tostring(Index) .. "::, "
			end
		end

		local UpvalueCounter = 0
		local CurrentPc = 1

		while CurrentPc <= CodeTableLength do
			if JumpTargets[CurrentPc] then
				PrintOrConcat(string_format("%s%s", InnerTabSpace, JumpTargets[CurrentPc]:sub(1, -3)))
			end

			local Instruction = CodeTable[CurrentPc]
			local OpcodeNum = GetOpcode(Instruction, IsFromRoblox)
			local OpInfo = OpInfoMap_v[OpcodeNum]
			local Opname = OpInfo and OpInfo.Name or "UNKNOWN"

			if Opname == "NEWCLOSURE" then
				local Bx = GetArgBx(Instruction)
				local ChildProtoData = ProtoData.Protos[Bx + 1]

				if ChildProtoData and not PrintedProtos[ChildProtoData.ProtoIndex] then
					PrintedProtos[ChildProtoData.ProtoIndex] = true
					
					PrintProtoRecursive(ChildProtoData, Depth + (IsMain and 0 or 1), false, AllProtos)
				end
			elseif Opname == "DUPCLOSURE" then
				local Bx = GetArgBx(Instruction)
				local Konstant = RawProto.KTable[Bx + 1]
				local ProtoIndex = Konstant.Value
				local TargetProtoData = AllProtos[ProtoIndex + 1]

				if TargetProtoData and not PrintedProtos[ProtoIndex] then
					PrintedProtos[ProtoIndex] = true
					
					PrintProtoRecursive(TargetProtoData, Depth + (IsMain and 0 or 1), false, AllProtos)
				end
			end

			local InstructionArgs = {
				A = GetArgA(Instruction),
				B = GetArgB(Instruction),
				C = GetArgC(Instruction),
				Bx = GetArgBx(Instruction),
				SBx = GetArgSBx(Instruction),
				SAx = GetArgSAx(Instruction),
				CodeIndex = CurrentPc - 1, 
				Proto = RawProto,
				StringTable = StringTable, 
				AllProtos = AllProtos,
			}

			if Opname == "NEWCLOSURE" then
				local Bx = InstructionArgs.Bx
				InstructionArgs.ChildProto = RawProto.PTable[Bx + 1]
			end

			if OpInfo and OpInfo.Aux then
				CurrentPc = CurrentPc + 1
				InstructionArgs.Aux = CodeTable[CurrentPc]
			end

			local Handler = Handlers_v[Opname]
			local OperandsStr, CommentStr = "", ""

			if Handler then
				if Opname == "CAPTURE" then
					InstructionArgs.UpvalIndex = UpvalueCounter
					UpvalueCounter = UpvalueCounter + 1
				end
				OperandsStr, CommentStr = Handler(InstructionArgs)
			else
				CommentStr = "Unimplemented Opcode: " .. Opname
			end

			local HexStr = string_format("[0x%08X]", Instruction)
			local OpAndOperands = Opname

			if OperandsStr and OperandsStr ~= "" then
				OpAndOperands = OpAndOperands .. " " .. OperandsStr
			end

			local PaddedOpSection = string_format("%-40s", OpAndOperands)
			local LineNumber = ProtoInstructionLines and ProtoInstructionLines[CurrentPc] or "?"
			local Line = string_format("%s[Line %s] [%d] %s        %s; %s", InnerTabSpace, tostring(LineNumber), CurrentPc - 1, HexStr, PaddedOpSection, CommentStr)
			PrintOrConcat(Line)

			CurrentPc = CurrentPc + 1
		end

		if not IsMain then
			if not ShoveIntoOneString then
				PrintOrConcat(TabSpace .. "end")
				print(TabSpace .. "")
			else
				PrintOrConcat(TabSpace .. "end\n")
			end
		end
	end

	local MainProto
	local LastProtoIndex = #DisassembledProtos

	for i = 1, #DisassembledProtos do
		local Proto = DisassembledProtos[i]

		if Proto.ProtoIndex == LastProtoIndex - 1 then
			MainProto = Proto

			break
		end
	end

	if MainProto then
		PrintProtoRecursive(MainProto, 0, true, DisassembledProtos)
	end

	PrintOrConcat(string_format("[END OF DISASSEMBLY]"))

	if ShoveIntoOneString then
		return table_concat(OutputParts, "\n")
	end

	return nil
end

return Disassembler
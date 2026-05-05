//     lc3-vm - virtual machine for Little Computer 3
//     Copyright (C) 2026-present  Not0ff
//
//     This program is free software: you can redistribute it and/or modify
//     it under the terms of the GNU General Public License as published by
//     the Free Software Foundation, either version 3 of the License, or
//     (at your option) any later version.
//
//     This program is distributed in the hope that it will be useful,
//     but WITHOUT ANY WARRANTY; without even the implied warranty of
//     MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
//     GNU General Public License for more details.
//
//     You should have received a copy of the GNU General Public License
//     along with this program.  If not, see <https://www.gnu.org/licenses/>.

const std = @import("std");
const Io = std.Io;
const Allocator = std.mem.Allocator;
const process = std.process;

const Memory = @import("Memory.zig");
const DevIo = @import("DevIo.zig");

const Self = @This();

const PC_START = 0x3000;

const COND_POS = 1 << 0;
const COND_ZRO = 1 << 1;
const COND_NEG = 1 << 2;

const Opcode = enum(u8) {
    BR,
    ADD,
    LD,
    ST,
    JSR,
    AND,
    LDR,
    STR,
    RTI,
    NOT,
    LDI,
    STI,
    JMP,
    RES,
    LEA,
    TRAP,
};

const Trap = enum(u8) {
    GETC = 0x20,
    OUT,
    PUTS,
    IN,
    PUTSP,
    HALT,
};

const Reg = enum {
    R0,
    R1,
    R2,
    R3,
    R4,
    R5,
    R6,
    R7,
    PC,
    COND,
};

registers: std.EnumArray(Reg, u16),
memory: Memory,
dev_io: DevIo,
alloc: Allocator,
running: bool = false,

pub fn init(dev_io: DevIo, alloc: Allocator) !Self {
    var vm: Self = .{
        .memory = .init(dev_io),
        .registers = .initFill(0),
        .dev_io = dev_io,
        .alloc = alloc,
    };
    vm.registers.set(Reg.COND, COND_ZRO);
    vm.registers.set(Reg.PC, PC_START);
    return vm;
}

pub fn loadImage(self: *Self, path: []const u8, io: Io) !void {
    const file = try Io.Dir.cwd().openFile(io, path, .{});
    defer file.close(io);

    var buf: [1024 * 4]u8 = undefined;
    var fr = file.reader(io, &buf);
    const reader = &fr.interface;

    const origin = try reader.takeInt(u16, .big);
    const buffer = self.memory.memory[origin..];

    _ = try reader.readSliceShort(@ptrCast(buffer));
    std.mem.byteSwapAllElements(u16, buffer);
}

pub fn run(self: *Self) !void {
    self.running = true;
    while (self.running) {
        const pc = self.registers.get(Reg.PC);
        const instr = self.memory.read(pc);
        self.registers.set(Reg.PC, pc +% 1);
        try self.runInstruction(instr, pc +% 1);
    }
}

inline fn runInstruction(self: *Self, instr: u16, pc: u16) !void {
    const op: Opcode = @enumFromInt(instr >> 12);
    switch (op) {
        .BR => {
            const cond_bits = (instr >> 9) & 0x7;
            if ((cond_bits & self.registers.get(Reg.COND)) >= 1) {
                const pc_offset9 = signExtend(instr & 0x1FF, 9);
                self.registers.set(Reg.PC, pc +% pc_offset9);
            }
        },
        .ADD => {
            const dest_reg: Reg = @enumFromInt((instr >> 9) & 0x7);
            const src_reg: Reg = @enumFromInt((instr >> 6) & 0x7);
            const imm_flag = (instr >> 5) & 0x1;

            if (imm_flag == 0) {
                const src_reg2: Reg = @enumFromInt(instr & 0x7);
                self.registers.set(dest_reg, self.registers.get(src_reg) +% self.registers.get(src_reg2));
            } else {
                const imm = signExtend(instr & 0x1F, 5);
                self.registers.set(dest_reg, self.registers.get(src_reg) +% imm);
            }
            self.setCondRegister(dest_reg);
        },
        .LD => {
            const dest_reg: Reg = @enumFromInt((instr >> 9) & 0x7);
            const pc_offset = signExtend(instr & 0x1FF, 9);

            self.registers.set(dest_reg, self.memory.read(pc +% pc_offset));
            self.setCondRegister(dest_reg);
        },
        .ST => {
            const src_reg: Reg = @enumFromInt((instr >> 9) & 0x7);
            const pc_offset = signExtend(instr & 0x1FF, 9);

            self.memory.store(pc +% pc_offset, self.registers.get(src_reg));
        },
        .JSR => {
            const cond_flag = (instr >> 11) & 0x1;
            self.registers.set(Reg.R7, pc);

            if (cond_flag == 0) {
                const base_reg: Reg = @enumFromInt((instr >> 6) & 0x7);
                self.registers.set(Reg.PC, self.registers.get(base_reg));
            } else {
                const pc_offset = signExtend(instr & 0x7FF, 11);
                self.registers.set(Reg.PC, pc +% pc_offset);
            }
        },
        .AND => {
            const dest_reg: Reg = @enumFromInt((instr >> 9) & 0x7);
            const src_reg: Reg = @enumFromInt((instr >> 6) & 0x7);
            const imm_flag = (instr >> 5) & 0x1;

            if (imm_flag == 0) {
                const src_reg2: Reg = @enumFromInt(instr & 0x7);
                self.registers.set(dest_reg, self.registers.get(src_reg) & self.registers.get(src_reg2));
            } else {
                const imm = signExtend(instr & 0x1F, 5);
                self.registers.set(dest_reg, self.registers.get(src_reg) & imm);
            }
            self.setCondRegister(dest_reg);
        },
        .LDR => {
            const dest_reg: Reg = @enumFromInt((instr >> 9) & 0x7);
            const base_reg: Reg = @enumFromInt((instr >> 6) & 0x7);
            const offset = signExtend(instr & 0x3F, 6);

            self.registers.set(dest_reg, self.memory.read(self.registers.get(base_reg) +% offset));
            self.setCondRegister(dest_reg);
        },
        .STR => {
            const src_reg: Reg = @enumFromInt((instr >> 9) & 0x7);
            const base_reg: Reg = @enumFromInt((instr >> 6) & 0x7);
            const offset = signExtend(instr & 0x3F, 6);

            self.memory.store(self.registers.get(base_reg) +% offset, self.registers.get(src_reg));
        },
        .NOT => {
            const dest_reg: Reg = @enumFromInt((instr >> 9) & 0x7);
            const src_reg: Reg = @enumFromInt((instr >> 6) & 0x7);

            self.registers.set(dest_reg, ~self.registers.get(src_reg));
            self.setCondRegister(dest_reg);
        },
        .LDI => {
            const dest_reg: Reg = @enumFromInt((instr >> 9) & 0x7);
            const pc_offset = signExtend(instr & 0x1FF, 9);

            self.registers.set(dest_reg, self.memory.read(self.memory.read(pc +% pc_offset)));
            self.setCondRegister(dest_reg);
        },
        .STI => {
            const src_reg: Reg = @enumFromInt((instr >> 9) & 0x7);
            const pc_offset = signExtend(instr & 0x1FF, 9);

            self.memory.store(self.memory.read(pc +% pc_offset), self.registers.get(src_reg));
        },
        .JMP => {
            const base_reg: Reg = @enumFromInt((instr >> 6) & 0x7);
            self.registers.set(Reg.PC, self.registers.get(base_reg));
        },
        .LEA => {
            const dest_reg: Reg = @enumFromInt((instr >> 9) & 0x7);
            const pc_offset = signExtend(instr & 0x1FF, 9);

            self.registers.set(dest_reg, pc +% pc_offset);
            self.setCondRegister(dest_reg);
        },
        .TRAP => {
            self.registers.set(Reg.R7, pc);
            try self.runTrapRoutine(@enumFromInt(instr & 0xFF));
        },
        .RTI, .RES => return error.InstructionUnsupported,
    }
}

inline fn runTrapRoutine(self: *Self, trap: Trap) !void {
    switch (trap) {
        .GETC => {
            self.registers.set(Reg.R0, self.dev_io.readByte());
            self.setCondRegister(Reg.R0);
        },
        .OUT => self.dev_io.writeByte(@intCast(self.registers.get(Reg.R0))),
        .PUTS => {
            var chars: std.ArrayList(u8) = try .initCapacity(self.alloc, 32);
            defer chars.deinit(self.alloc);

            const addr = self.registers.get(Reg.R0);
            var len: u16 = 0;
            while (true) : (len += 1) {
                const char = self.memory.read(addr + len);
                if (char == 0) break;
                try chars.append(self.alloc, @intCast(char & 0xFF));
            }
            const str = try chars.toOwnedSlice(self.alloc);
            defer self.alloc.free(str);
            self.dev_io.writeString(str);
        },
        .IN => {
            self.dev_io.writeString("\n> ");
            const char = self.dev_io.readByte();
            self.dev_io.writeByte(char);

            self.registers.set(Reg.R0, char);
            self.setCondRegister(Reg.R0);
        },
        .PUTSP => {
            var chars: std.ArrayList(u8) = try .initCapacity(self.alloc, 32);
            defer chars.deinit(self.alloc);

            const addr = self.registers.get(Reg.R0);
            var len: u16 = 0;
            while (true) : (len += 1) {
                const char = self.memory.read(addr + len);
                if (char == 0) break;
                try chars.append(self.alloc, @intCast(char & 0xFF));
                try chars.append(self.alloc, @intCast(char >> 8));
            }
            const str = try chars.toOwnedSlice(self.alloc);
            defer self.alloc.free(str);
            self.dev_io.writeString(str);
        },
        .HALT => self.running = false,
    }
}

fn setCondRegister(self: *Self, reg: Reg) void {
    if (self.registers.get(reg) == 0) {
        self.registers.set(Reg.COND, COND_ZRO);
    } else if ((self.registers.get(reg) >> 15) == 1) {
        self.registers.set(Reg.COND, COND_NEG);
    } else {
        self.registers.set(Reg.COND, COND_POS);
    }
}

inline fn signExtend(x: u16, comptime bit_count: u8) u16 {
    if (((x >> (bit_count - 1)) & 1) == 1) {
        return x | (@as(u16, 0xFFFF) << bit_count);
    }
    return x;
}

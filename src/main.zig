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
const posix = std.posix;
const Io = std.Io;

const MAX_MEMORY = 1 << 16;
const PC_START = 0x3000;

const Reg = enum(u4) {
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
    COUNT,
};

const MemReg = enum(u16) {
    KBSR = 0xFE00,
    KBDR = 0xFE02,
};

const Cond = enum(u4) {
    POS = 1 << 0,
    ZRO = 1 << 1,
    NEG = 1 << 2,
};

const Trap = enum(u8) {
    GETC = 0x20,
    OUT,
    PUTS,
    IN,
    PUTSP,
    HALT,
};

const Op = enum(u8) {
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

const LC3 = struct {
    memory: [MAX_MEMORY]u16 = [_]u16{0} ** MAX_MEMORY,
    regs: std.EnumArray(Reg, u16) = .initFill(0),
    out: *Io.Writer,
    in: *Io.Reader,
    pollfd: [1]posix.pollfd,

    pub fn init(out: *Io.Writer, in: *Io.Reader) LC3 {
        var self = LC3{
            .out = out,
            .in = in,
            .pollfd = .{.{
                .fd = posix.STDIN_FILENO,
                .events = 0x001,
                .revents = 0,
            }},
        };
        self.regs.set(Reg.COND, @intFromEnum(Cond.ZRO));
        self.regs.set(Reg.PC, PC_START);

        return self;
    }

    pub fn readImage(self: *LC3, path: []const u8, io: Io, _: std.mem.Allocator) !void {
        const file = try Io.Dir.cwd().openFile(io, path, .{ .mode = .read_only });
        defer file.close(io);
        var buf: [1024 * 4]u8 = undefined;
        var fr = file.reader(io, &buf);
        const reader = &fr.interface;

        const origin = try reader.takeInt(u16, .big);
        const buffer = self.memory[origin..];

        _ = try reader.readSliceShort(@ptrCast(buffer));
        for (buffer) |*elem| std.mem.byteSwapAllFields(u16, elem);
    }

    fn runInstruction(self: *LC3) !void {
        const pc = self.regs.get(Reg.PC);
        const instr = self.memRead(pc);
        self.regs.set(Reg.PC, pc +% 1);

        const op: Op = @enumFromInt(instr >> 12);
        switch (op) {
            .BR => {
                const cond_flag = (instr >> 9) & 0x7;

                if ((cond_flag & self.regs.get(Reg.COND)) >= 1) {
                    const pc_offset = signExtend(instr & 0x1FF, 9);
                    self.regs.set(Reg.PC, self.regs.get(Reg.PC) +% pc_offset);
                }
            },
            .ADD => {
                const dest_reg: Reg = @enumFromInt((instr >> 9) & 0x7);
                const src_reg: Reg = @enumFromInt((instr >> 6) & 0x7);
                const imm_flag = (instr >> 5) & 0x1;

                if (imm_flag == 0) {
                    const src_reg2: Reg = @enumFromInt(instr & 0x7);
                    self.regs.set(dest_reg, self.regs.get(src_reg) +% self.regs.get(src_reg2));
                } else {
                    const imm5 = signExtend(instr & 0x1F, 5);
                    self.regs.set(dest_reg, self.regs.get(src_reg) +% imm5);
                }
                self.updateFlags(dest_reg);
            },
            .LD => {
                const dest_reg: Reg = @enumFromInt((instr >> 9) & 0x7);
                const pc_offset = signExtend(instr & 0x1FF, 9);

                self.regs.set(dest_reg, self.memRead(self.regs.get(Reg.PC) +% pc_offset));
                self.updateFlags(dest_reg);
            },
            .ST => {
                const src_reg: Reg = @enumFromInt((instr >> 9) & 0x7);
                const pc_offset = signExtend(instr & 0x1FF, 9);

                self.memStore(self.regs.get(Reg.PC) +% pc_offset, self.regs.get(src_reg));
            },
            .JSR => {
                const cond_flag = (instr >> 11) & 0x1;
                self.regs.set(Reg.R7, self.regs.get(Reg.PC));

                if (cond_flag == 0) {
                    const base_reg: Reg = @enumFromInt((instr >> 6) & 0x7);
                    self.regs.set(Reg.PC, self.regs.get(base_reg));
                } else {
                    const pc_offset = signExtend(instr & 0x7FF, 11);
                    self.regs.set(Reg.PC, self.regs.get(Reg.PC) +% pc_offset);
                }
            },
            .AND => {
                const dest_reg: Reg = @enumFromInt((instr >> 9) & 0x7);
                const src_reg: Reg = @enumFromInt((instr >> 6) & 0x7);
                const imm_flag = (instr >> 5) & 0x1;

                if (imm_flag == 0) {
                    const src_reg2: Reg = @enumFromInt(instr & 0x7);
                    self.regs.set(dest_reg, self.regs.get(src_reg) & self.regs.get(src_reg2));
                } else {
                    const imm5 = signExtend(instr & 0x1F, 5);
                    self.regs.set(dest_reg, self.regs.get(src_reg) & imm5);
                }
                self.updateFlags(dest_reg);
            },
            .LDR => {
                const dest_reg: Reg = @enumFromInt((instr >> 9) & 0x7);
                const base_reg: Reg = @enumFromInt((instr >> 6) & 0x7);
                const offset = signExtend(instr & 0x3F, 6);

                self.regs.set(dest_reg, self.memRead(self.regs.get(base_reg) +% offset));
                self.updateFlags(dest_reg);
            },
            .STR => {
                const src_reg: Reg = @enumFromInt((instr >> 9) & 0x7);
                const base_reg: Reg = @enumFromInt((instr >> 6) & 0x7);
                const offset = signExtend(instr & 0x3F, 6);

                self.memStore(self.regs.get(base_reg) +% offset, self.regs.get(src_reg));
            },
            .NOT => {
                const dest_reg: Reg = @enumFromInt((instr >> 9) & 0x7);
                const src_reg: Reg = @enumFromInt((instr >> 6) & 0x7);

                self.regs.set(dest_reg, ~self.regs.get(src_reg));
                self.updateFlags(dest_reg);
            },
            .LDI => {
                const dest_reg: Reg = @enumFromInt((instr >> 9) & 0x7);
                const pc_offset = signExtend(instr & 0x1FF, 9);

                self.regs.set(dest_reg, self.memRead(self.memRead(self.regs.get(Reg.PC) +% pc_offset)));
                self.updateFlags(dest_reg);
            },
            .STI => {
                const src_reg: Reg = @enumFromInt((instr >> 9) & 0x7);
                const pc_offset = signExtend(instr & 0x1FF, 9);

                self.memStore(self.memRead(self.regs.get(Reg.PC) +% pc_offset), self.regs.get(src_reg));
            },
            .JMP => {
                const base_reg: Reg = @enumFromInt((instr >> 6) & 0x7);
                self.regs.set(Reg.PC, self.regs.get(base_reg));
            },
            .LEA => {
                const dest_reg: Reg = @enumFromInt((instr >> 9) & 0x7);
                const pc_offset = signExtend(instr & 0x1FF, 9);

                self.regs.set(dest_reg, self.regs.get(Reg.PC) +% pc_offset);
                self.updateFlags(dest_reg);
            },
            .TRAP => {
                self.regs.set(Reg.R7, self.regs.get(Reg.PC));
                const trap: Trap = @enumFromInt(instr & 0xFF);
                switch (trap) {
                    .GETC => {
                        self.regs.set(Reg.R0, try self.in.takeByte());
                        self.updateFlags(Reg.R0);
                    },
                    .OUT => {
                        try self.out.writeByte(@intCast(self.regs.get(Reg.R0)));
                        try self.out.flush();
                    },
                    .PUTS => {
                        const s = self.regs.get(Reg.R0);
                        for (self.memory[s..]) |char| {
                            if (char == 0) break;
                            try self.out.writeByte(@intCast(char));
                        }
                        try self.out.flush();
                    },
                    .IN => {
                        try self.out.writeAll("> ");
                        const char = try self.in.takeByte();
                        try self.out.writeByte(char);
                        try self.out.flush();

                        self.regs.set(Reg.R0, char);
                        self.updateFlags(Reg.R0);
                    },
                    .PUTSP => {
                        const s = self.regs.get(Reg.R0);
                        for (self.memory[s..]) |char| {
                            if (char == 0) break;
                            try self.out.writeByte(@intCast(char & 0xFF));

                            const c2 = char >> 8;
                            if (c2 != 0) try self.out.writeByte(@intCast(c2));
                        }
                        try self.out.flush();
                    },
                    .HALT => {
                        try self.out.writeAll("\nhalted\n");
                        try self.out.flush();
                        return error.Halted;
                    },
                }
            },
            .RTI, .RES => std.log.err("unimplemented opcode {}", .{op}),
        }
    }

    fn memRead(self: *LC3, addr: u16) u16 {
        if (addr != @intFromEnum(MemReg.KBSR)) return self.memory[addr];

        // if (std.c.poll(&self.pollfd, self.pollfd.len, 0) > 0) {
        if ((posix.poll(&self.pollfd, 0) catch 0) > 0) {
            self.memory[@intFromEnum(MemReg.KBSR)] = 1 << 15;
            self.memory[@intFromEnum(MemReg.KBDR)] = self.in.takeByte() catch 0;
        } else {
            self.memory[@intFromEnum(MemReg.KBSR)] = 0;
        }
        return self.memory[addr];
    }

    inline fn memStore(self: *LC3, addr: u16, val: u16) void {
        self.memory[addr] = val;
    }

    fn updateFlags(self: *LC3, r: Reg) void {
        if (self.regs.get(r) == 0) {
            self.regs.set(Reg.COND, @intFromEnum(Cond.ZRO));
        } else if ((self.regs.get(r) >> 15) == 1) {
            self.regs.set(Reg.COND, @intFromEnum(Cond.NEG));
        } else {
            self.regs.set(Reg.COND, @intFromEnum(Cond.POS));
        }
    }
};

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const alloc = init.arena.allocator();
    const args = try init.minimal.args.toSlice(alloc);

    var w_buf: [1024]u8 = undefined;
    var sw = Io.File.stdout().writer(io, &w_buf);
    const stdout = &sw.interface;
    defer stdout.flush() catch {};

    var r_buf: [1024]u8 = undefined;
    var sr = Io.File.stdin().reader(io, &r_buf);
    const stdin = &sr.interface;

    if (args.len < 2) {
        std.log.err("missing image in arguments!", .{});
        try stdout.writeAll("Usage: ./lc3 image [image2 image3... ]\n");
        return;
    }

    var lc3: LC3 = .init(stdout, stdin);
    for (args[1..]) |path| {
        try lc3.readImage(path, io, alloc);
    }

    const termAttrs = try applyTerminalAttrs();
    defer restoreTerminalAttr(termAttrs) catch {};

    while (true) {
        try lc3.runInstruction();
    }
}

inline fn signExtend(x: u16, comptime bit_count: u8) u16 {
    if (((x >> (bit_count - 1)) & 1) == 1) {
        return x | (@as(u16, 0xFFFF) << bit_count);
    }
    return x;
}

// Disables line buffering and echo. Returns original attributes
fn applyTerminalAttrs() !posix.termios {
    const term = try posix.tcgetattr(posix.STDIN_FILENO);
    var new_term = term;
    new_term.lflag.ICANON = false;
    new_term.lflag.ECHO = false;

    try posix.tcsetattr(posix.STDIN_FILENO, posix.TCSA.NOW, new_term);
    return term;
}

fn restoreTerminalAttr(prev: posix.termios) !void {
    try posix.tcsetattr(posix.STDIN_FILENO, posix.TCSA.NOW, prev);
}

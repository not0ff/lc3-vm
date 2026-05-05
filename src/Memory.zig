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
const DevIo = @import("DevIo.zig");

pub const MmapReg = enum(u16) {
    KBSR = 0xFE00,
    KBDR = 0xFE02,
};

const Self = @This();

pub const MEMORY_SIZE = 1 << 16;
pub const STATUS_RECEIVED = 1 << 15;

memory: [MEMORY_SIZE]u16,
dev_io: DevIo,

pub fn init(dev_io: DevIo) Self {
    return .{
        .memory = [_]u16{0} ** MEMORY_SIZE,
        .dev_io = dev_io,
    };
}

pub inline fn store(self: *Self, addr: u16, val: u16) void {
    if (addr == @intFromEnum(MmapReg.KBSR) or addr == @intFromEnum(MmapReg.KBDR)) return;
    self.memory[addr] = val;
}

pub inline fn read(self: *Self, addr: u16) u16 {
    if (addr != @intFromEnum(MmapReg.KBSR)) return self.memory[addr];

    var status: u16 = undefined;
    if (self.dev_io.inputReady()) {
        status = STATUS_RECEIVED;
        self.memory[@intFromEnum(MmapReg.KBDR)] = self.dev_io.readByte();
    } else {
        status = 0;
    }
    return status;
}

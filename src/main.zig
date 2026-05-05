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

const DevIo = @import("DevIo.zig");
const Vm = @import("Vm.zig");

pub fn main(init: std.process.Init) !void {
    const io = init.io;
    const alloc = init.arena.allocator();
    const args = try init.minimal.args.toSlice(alloc);

    var w_buf: [1024]u8 = undefined;
    var r_buf: [1024]u8 = undefined;
    var sw = Io.File.stdout().writer(io, &w_buf);
    var sr = Io.File.stdin().reader(io, &r_buf);
    const stdout = &sw.interface;
    const stdin = &sr.interface;

    if (args.len < 2) {
        std.log.err("missing image in arguments!", .{});
        try stdout.writeAll("Usage: ./lc3 image [image2 image3... ]\n");
        return;
    }

    const dev_io: DevIo = try .init(stdout, stdin);
    var vm: Vm = try .init(dev_io, alloc);
    for (args[1..]) |path| {
        try vm.loadImage(path, io);
    }

    const prev = try disableEchoAndBuffering();
    defer posix.tcsetattr(posix.STDIN_FILENO, posix.TCSA.NOW, prev) catch |err| {
        std.log.err("error restoring terminal attributes: {s}", .{@errorName(err)});
    };
    try vm.run();
}

// Disables line buffering and echo in terminal. Returns previous attributes
fn disableEchoAndBuffering() !posix.termios {
    const term = try posix.tcgetattr(posix.STDIN_FILENO);
    var new_term = term;
    new_term.lflag.ICANON = false;
    new_term.lflag.ECHO = false;

    try posix.tcsetattr(posix.STDIN_FILENO, posix.TCSA.NOW, new_term);
    return term;
}

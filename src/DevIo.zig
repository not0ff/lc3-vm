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
const process = std.process;
const Io = std.Io;

const Self = @This();

const POLLIN = 0x1;

stdout: *Io.Writer,
stdin: *Io.Reader,
pollfd: [1]posix.pollfd,

pub fn init(stdout: *Io.Writer, stdin: *Io.Reader) !Self {
    return .{
        .stdout = stdout,
        .stdin = stdin,
        .pollfd = .{.{
            .fd = posix.STDIN_FILENO,
            .events = POLLIN,
            .revents = 0,
        }},
    };
}

pub inline fn inputReady(self: *Self) bool {
    const ev = posix.poll(&self.pollfd, 0) catch |err| {
        std.log.err("input poll failed: {s}", .{@errorName(err)});
        process.exit(1);
    };
    return ev > 0;
}

pub inline fn readByte(self: Self) u8 {
    return self.stdin.takeByte() catch {
        std.log.err("reading byte from stdin failed", .{});
        process.exit(2);
    };
}

pub inline fn writeByte(self: Self, b: u8) void {
    self.stdout.writeByte(b) catch {
        std.log.err("writing byte to stdout failed", .{});
        process.exit(3);
    };
    self.stdout.flush() catch {
        std.log.err("stdout flush failed", .{});
        process.exit(4);
    };
}

pub inline fn writeString(self: Self, str: []const u8) void {
    self.stdout.writeAll(str) catch {
        std.log.err("writing string to stdout failed", .{});
        process.exit(3);
    };
    self.stdout.flush() catch {
        std.log.err("stdout flush failed", .{});
        process.exit(4);
    };
}

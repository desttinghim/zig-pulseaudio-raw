const Tagstruct = @This();

data: std.SegmentedList(u8, 128) = .{},
r_index: usize = 0,

const max_tag_size = (64 * 1024);

// take index ptr, write buffer, value, "put" the value into the buffer, advancing the index ptr by the
// amount written.

pub fn free(ts: *Tagstruct, allocator: std.mem.Allocator) void {
    ts.data.clearAndFree(allocator);
}

pub fn putString(ts: *Tagstruct, allocator: std.mem.Allocator, str_opt: ?[:0]const u8) !void {
    if (str_opt) |str| {
        try ts.data.append(allocator, @intFromEnum(Tag.String));
        try ts.data.appendSlice(allocator, str);
    } else {
        try ts.data.append(allocator, @intFromEnum(Tag.StringNull));
    }
}

pub fn putU32(ts: *Tagstruct, allocator: std.mem.Allocator, value: u32) !void {
    try ts.data.append(allocator, @intFromEnum(Tag.Uint32));
    try ts.writeU32(allocator, value);
}

pub fn putU8(ts: *Tagstruct, allocator: std.mem.Allocator, value: u8) !void {
    try ts.data.append(allocator, @intFromEnum(Tag.Uint8));
    try ts.data.append(allocator, value);
}

pub fn putSampleSpec(ts: *Tagstruct, allocator: std.mem.Allocator, sample_spec: SampleSpec) !void {
    try ts.data.append(allocator, @intFromEnum(Tag.SampleSpec));
    try ts.data.append(allocator, sample_spec.format);
    try ts.data.append(allocator, sample_spec.channels);
    try ts.writeU32(allocator, sample_spec.sample_rate);
}

pub fn putArbitrary(ts: *Tagstruct, allocator: std.mem.Allocator, bytes: []const u8) !void {
    try ts.data.append(allocator, @intFromEnum(Tag.Arbitrary));
    try ts.writeU32(allocator, @truncate(bytes.len));
    try ts.data.appendSlice(allocator, bytes);
}

pub fn putBoolean(ts: *Tagstruct, allocator: std.mem.Allocator, value: bool) !void {
    try ts.data.append(
        allocator,
        @intFromEnum(if (value)
            Tag.True
        else
            Tag.False),
    );
}

pub fn putTimeval(ts: *Tagstruct, allocator: std.mem.Allocator, timeval: TimeVal) !void {
    try ts.data.append(allocator, @intFromEnum(Tag.Time));
    try ts.writeU32(allocator, timeval.sec);
    try ts.writeU32(allocator, timeval.usec);
}

pub fn putUsec(ts: *Tagstruct, allocator: std.mem.Allocator, usec: Usec) !void {
    try ts.data.append(allocator, @intFromEnum(Tag.Usec));
    ts.writeU64(allocator, @bitCast(usec));
}

pub fn putU64(ts: *Tagstruct, allocator: std.mem.Allocator, uint64: u64) !void {
    try ts.data.append(allocator, @intFromEnum(Tag.Uint64));
    try ts.writeU64(allocator, uint64);
}

pub fn putS64(ts: *Tagstruct, allocator: std.mem.Allocator, sint64: i64) !void {
    try ts.data.append(allocator, @intFromEnum(Tag.Sint64));
    try ts.writeU64(allocator, @bitCast(sint64));
}

pub fn putChannelMap(ts: *Tagstruct, allocator: std.mem.Allocator, map: ChannelMap) !void {
    try ts.data.append(allocator, @intFromEnum(Tag.ChannelMap));
    try ts.data.append(allocator, map.channels);
    for (0..@intCast(map.channels)) |i| {
        try ts.data.append(allocator, map.map[i]);
    }
}

pub fn putCVolume(ts: *Tagstruct, allocator: std.mem.Allocator, c_volume: CVolume) !void {
    try ts.data.append(allocator, @intFromEnum(Tag.CVolume));
    try ts.data.append(allocator, c_volume.channels);
    for (0..@intCast(map.channels)) |i| {
        try ts.data.append(allocator, map.map[i]);
    }
}

pub fn putVolume(ts: *Tagstruct, allocator: std.mem.Allocator, volume: Volume) !void {
    try ts.data.append(allocator, @intFromEnum());
    try ts.data.appendSlice(allocator, std.mem.asBytes(@as(u32, @intCast(bytes.len))));
    // TODO
}

pub fn putPropList(ts: *Tagstruct, allocator: std.mem.Allocator, prop_list: PropList) !void {
    try ts.data.append(allocator, @intFromEnum());
    try ts.data.appendSlice(allocator, std.mem.asBytes(@as(u32, @intCast(bytes.len))));
    // TODO
}

pub fn putFormatInfo(ts: *Tagstruct, allocator: std.mem.Allocator, info: FormatInfo) !void {
    try ts.data.append(allocator, @intFromEnum());
    try ts.data.appendSlice(allocator, std.mem.asBytes(@as(u32, @intCast(bytes.len))));
    // TODO
}

// --- Public Data Structures -------------------------------------------------
pub const TimeVal = struct {
    sec: u32,
    usec: u32,
};
pub const Usec = u64;
pub const SampleSpec = struct {
    format: Format,
    channels: u8,
    sample_rate: u32,

    const Format = enum(u8) {
        Invalid = std.math.maxInt(u8),
        Uint8 = 0,
        Alaw = 1,
        Ulaw = 2,
        Sint16Le = 3,
        Sint16Be = 4,
        Float32Le = 5,
        Float32Be = 6,
        Sint32Le = 7,
        Sint32Be = 8,
        Sint24Le = 9,
        Sint24Be = 10,
        Sint24in32Le = 11,
        Sint24in32Be = 12,
    };
};
const MAX_CHANNELS = 32;
const ChannelMap = struct {
    channels: u8,
    map: [MAX_CHANNELS]Position,
    const Position = enum {};
};
const Volume = enum(u32) { _ };
const CVolume = struct {
    channels: u8,
    volumes: [MAX_CHANNELS]Volume,
};

// --- Private Functions ------------------------------------------------------

/// Write u32 to data in network-endian (big-endian) order
fn writeU32(ts: *Tagstruct, allocator: std.mem.Allocator, value: u32) !void {
    var buf: [4]u8 = .{0} ** 4;
    std.mem.writeInt(u32, &buf, value, .big);
    try ts.data.appendSlice(allocator, buf);
}

/// Write u64 to data in network-endian (big-endian) order
fn writeU64(ts: *Tagstruct, allocator: std.mem.Allocator, value: u64) !void {
    var buf: [8]u8 = .{0} ** 8;
    std.mem.writeInt(u64, &buf, value, .big);
    try ts.data.appendSlice(allocator, buf);
}

const Variant = union(enum) {
    String,
    Uint8,
    Uint32,
    Uint64,
    Sint64,
    Bool,
    // TODO
};

/// Tags used to build values
pub const Tag = enum(u8) {
    Invalid = 0,
    String = 't',
    StringNull = 'N',
    Uint32 = 'L',
    Uint8 = 'B',
    Uint64 = 'R',
    Sint64 = 'r',
    SampleSpec = 'a',
    Arbitrary = 'x',
    True = '1',
    False = '0',
    Time = 'T',
    Usec = 'U',
    ChannelMap = 'm',
    CVolume = 'v',
    PropList = 'P',
    Volume = 'V',
    FormatInfo = 'f',
};

const ParseError = error{
    TypeMismatch,
    StringNull,
} || std.io.AnyReader.Error;

pub fn readString(reader: std.io.AnyReader, buf: []u8) ParseError![]u8 {
    switch (try reader.readEnum(Type, .big)) {
        .String => {},
        .StringNull => {
            return error.StringNull;
        },
        else => return error.TypeMismatch,
    }
    return reader.readUntilDelimiter(buf, 0);
}

/// A list associating string keys with arbitrary values,
/// usually strings.
pub const PropertyList = struct {
    pub const Property = struct {
        key: []const u8,
        value: []const u8,
    };

    pub fn readProperty(reader: std.io.AnyReader, key_buf: []u8, value_buf: []u8) !?Property {
        const key = readString(reader, key_buf) catch |e| switch (e) {
            error.StringNull => return null,
            else => return e,
        };
        const value = try readString(reader, value_buf);
        return .{
            .key = key,
            .value = value,
        };
    }
};

test "PropertyList" {}

const std = @import("std");

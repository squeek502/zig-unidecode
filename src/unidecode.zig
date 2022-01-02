//! This file provides functions to convert UTF-8 text into
//! a (very) approximate ASCII-only transliteration. That is,
//! this is "meant to be a transliterator of last resort."
//!
//! For a more detailed description including motivation,
//! caveats, etc, see:
//!
//! https://metacpan.org/pod/Text::Unidecode
//!
//!
//! Some things worth noting:
//!
//! - The returned output will only contain ASCII characters (0x00-0x7F).
//! - Any ASCII characters in the input will be unconverted in the output.
//! - UTF-8 codepoints may be transliterated to a variable number of ASCII
//!   characters (including 0).
//! - UTF-8 codepoints > 0x7F will never be transliterated to include any
//!   ASCII control characters except \n.
//! - Unknown UTF-8 codepoints may be transliterated to "[?]"
//!
//!
//! The different functions provided are:
//! 
//! unidecodeAlloc
//!   Takes an allocator in order to handle any input size
//!   safely. This should be used for most use-cases.
//!
//! unidecodeBuf
//!   Takes a `dest` slice that must be large enough to
//!   handle the transliterated ASCII. Because the output
//!   size can vary greatly depending on the input, this
//!   is unsafe unless it can be known ahead-of-time that
//!   the transliterated output will fit (i.e. comptime).
//!
//! unidecodeStringLiteral
//!   A way to transliterate a UTF-8 string literal into
//!   ASCII at compile time.

const std = @import("std");
const testing = std.testing;
const Allocator = std.mem.Allocator;
const data = @import("data.zig").table;

/// Caller must free returned memory.
pub fn unidecodeAlloc(allocator: Allocator, utf8: []const u8) ![]u8 {
    var buf = try std.ArrayList(u8).initCapacity(allocator, utf8.len);
    errdefer buf.deinit();

    var utf8_view = try std.unicode.Utf8View.init(utf8);
    var codepoint_it = utf8_view.iterator();

    while (codepoint_it.nextCodepoint()) |codepoint| switch (codepoint) {
        // ASCII
        0x00...0x7F => {
            try buf.append(@intCast(u8, codepoint));
        },
        // Only have mappings for the Basic Multilingual Plane
        0x80...0xFFFF => {
            const replacement = getReplacement(codepoint);
            try buf.appendSlice(replacement);
        },
        // skip anything above the Basic Multilingual Plane
        else => {},
    };

    return buf.toOwnedSlice();
}

/// Decodes the `utf8` into `dest` and returns the length of
/// the decoded ASCII.
///
/// `dest` must be large enough to handle the converted ASCII,
/// or it will invoke safety-checked illegal behavior (or undefined
/// behavior in modes without runtime safety)
///
/// Because the conversions can be multiple characters long, it is
/// hard to calculate a 'safe' size for any input. As a result, this
/// should probably only be used at comptime or on known inputs.
pub fn unidecodeBuf(dest: []u8, utf8: []const u8) !usize {
    var utf8_view = try std.unicode.Utf8View.init(utf8);
    var codepoint_it = utf8_view.iterator();

    var end_index: usize = 0;
    while (codepoint_it.nextCodepoint()) |codepoint| switch (codepoint) {
        // ASCII
        0x00...0x7F => {
            dest[end_index] = @intCast(u8, codepoint);
            end_index += 1;
        },
        // Only have mappings for the Basic Multilingual Plane
        0x80...0xFFFF => {
            const replacement = getReplacement(codepoint);
            std.mem.copy(u8, dest[end_index..], replacement);
            end_index += replacement.len;
        },
        // skip anything above the Basic Multilingual Plane
        else => {},
    };

    return end_index;
}

/// Decodes a UTF-8 string literal into a unidecoded-ASCII string literal.
pub fn unidecodeStringLiteral(comptime utf8: []const u8) *const [calcUnidecodeLen(utf8):0]u8 {
    comptime {
        const len: usize = calcUnidecodeLen(utf8);
        var buf: [len:0]u8 = [_:0]u8{0} ** len;
        const buf_len = unidecodeBuf(&buf, utf8) catch |err| @compileError(err);
        std.debug.assert(len == buf_len);
        return &buf;
    }
}

fn calcUnidecodeLen(utf8: []const u8) usize {
    var codepoint_it = std.unicode.Utf8Iterator{ .bytes = utf8, .i = 0 };
    var dest_len: usize = 0;
    while (codepoint_it.nextCodepoint()) |codepoint| switch (codepoint) {
        // ASCII
        0x00...0x7F => {
            dest_len += 1;
        },
        // Only have mappings for the Basic Multilingual Plane
        0x80...0xFFFF => {
            const replacement = getReplacement(codepoint);
            dest_len += replacement.len;
        },
        // skip anything above the Basic Multilingual Plane
        else => {},
    };
    return dest_len;
}

fn getReplacement(codepoint: u21) []const u8 {
    const section = codepoint >> 8;
    const index = codepoint % 256;
    return data[section][index];
}

fn expectDecoded(expected: []const u8, utf8: []const u8) !void {
    const decoded = try unidecodeAlloc(testing.allocator, utf8);
    defer testing.allocator.free(decoded);

    try testing.expectEqualStrings(expected, decoded);
}

test "ascii" {
    // all ASCII including control characters should remain unchanged
    try expectDecoded("\x00\x01\r\n", "\x00\x01\r\n");
    try expectDecoded("hello!", "hello!");
}

test "transliteration / romanization" {
    // Greek -> unidecode directly
    try expectDecoded("Taugetos", "Ταΰγετος");
    // (Greek -> ELOT 743) -> unidecode
    try expectDecoded("Taygetos", "Taÿ́getos");

    // Cyrillic -> unidecode directly
    try expectDecoded("Slav'sia, Otechestvo nashe svobodnoe", "Славься, Отечество наше свободное");
    // (Cyrillic -> ISO 9) -> unidecode
    try expectDecoded("Slav'sa, Otecestvo nase svobodnoe", "Slavʹsâ, Otečestvo naše svobodnoe");
}

test "readme examples" {
    try expectDecoded("yeah", "ÿéáh");
    try expectDecoded("Bei Jing ", "北亰");
    try expectDecoded("Slav'sia", "Славься");
    try expectDecoded("[##  ] 50%", "[██  ] 50%");
}

test "string literals" {
    const utf8_literal = "Ταΰγετος";
    const unidecoded_literal = comptime unidecodeStringLiteral(utf8_literal);
    comptime try testing.expectEqualStrings("Taugetos", unidecoded_literal);
}

test "decoded is always ASCII" {
    // for every UTF-8 codepoint within the Basic Multilingual Plane,
    // check that its decoded form is valid ASCII
    var buf: [4]u8 = undefined;
    var decoded_buf: [256]u8 = undefined;
    var codepoint: u21 = 0;
    while (codepoint <= 0xFFFF) : (codepoint += 1) {
        if (!std.unicode.utf8ValidCodepoint(codepoint)) {
            continue;
        }
        const num_bytes = try std.unicode.utf8Encode(codepoint, &buf);
        const decoded_len = try unidecodeBuf(&decoded_buf, buf[0..num_bytes]);

        for (decoded_buf[0..decoded_len]) |c| {
            testing.expect(std.ascii.isASCII(c)) catch |err| {
                std.debug.print("non-ASCII char {} found when converting codepoint {x} ({s})\n", .{ c, codepoint, &buf });
                return err;
            };
        }
    }

    // TODO: this type of check could be done at comptime?
    // comptime evaluation is a bit too slow for that right now though
    // (needs like a million backwards branches for this to
    // not hit the limit):
    //
    // for (data) |row| {
    //     for (row) |conversion| {
    //         for (conversion) |c| {
    //             if (!std.ascii.isASCII(c)) {
    //                 @compileError("non-ASCII character found in conversion data");
    //             }
    //         }
    //     }
    // }
}

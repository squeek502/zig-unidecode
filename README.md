# zig-unidecode

A [Zig](https://ziglang.org/) implementation of the [Text::Unidecode Perl module](https://metacpan.org/pod/Text::Unidecode) to convert UTF-8 text into a (very) approximate ASCII-only transliteration. That is, this is "meant to be a transliterator of last resort."

For a more detailed description including motivation, caveats, etc, see:

https://metacpan.org/pod/Text::Unidecode

## Examples

| UTF-8  | Transliterated ASCII |
| ------------- | ------------- |
| `"ÿéáh"`  | `"yeah"`  |
| `"北亰"`  | `"Bei Jing "` |
| `"Славься"`  | `"Slav'sia"` |
| `"[██  ] 50%"`  | `"[##  ] 50%"` |

## Some things worth noting

- The returned output will only contain ASCII characters (`0x00`-`0x7F`).
- Any ASCII characters in the input will be unconverted in the output.
- UTF-8 codepoints may be transliterated to a variable number of ASCII
  characters (including 0).
- UTF-8 codepoints > `0x7F` will never be transliterated to include any
  ASCII control characters except `\n`.
- Unknown UTF-8 codepoints may be transliterated to `[?]`.

## The different functions provided

### `unidecodeAlloc`

Takes an allocator in order to handle any input size safely. This should be used for most use-cases.

### `unidecodeBuf`

Takes a `dest` slice that must be large enough to handle the transliterated ASCII. Because the output size can vary greatly depending on the input, this is unsafe unless it can be known ahead-of-time that the transliterated output will fit (i.e. comptime).

### `unidecodeStringLiteral`

A way to transliterate a UTF-8 string literal into ASCII at compile time.

# Measurements and runtime notes

These are records from the first implementation round on the development
machine (AMD Ryzen 7 5800H, 31 GiB RAM, Arch Linux, Bend 2.0.35). They describe
what was observed, not general performance guarantees.

## Text demo

`examples/text.bend` loads Liberation Sans, lays out and rasterizes ten text
blocks (12–48 px), draws them on a 980×560 grayscale surface, and writes a PGM.

| Measure | Value |
| --- | --- |
| Runs (native binary, CPU affinity to one core, `--threads 1 --gpu off`) | 3 |
| Wall time | 0.643 / 0.526 / 0.630 s, median 0.630 s |
| Peak RSS | 50788 KiB (about 49.6 MiB) |
| Output | identical image in all runs and in the `bend <file>` run, SHA-256 `fc9d84c270ba2656d21e3feceb2c2b9c9d6ba1b7055dde3f7fc47d6c6e8f3c32` |

Compilation is excluded. Native builds of the text demo, the window example,
and the combined tests took 9.2, 10.4, and 12.6 s, with a peak RSS of about
470 MiB for the compiler.

## Window example

The window example opened a 640×160 XWayland window titled
`AMAGE Eco · Texto em Bend 2` under Hyprland and exited with code 0. That record
comes from the compositor's window list; it confirms the window, not its pixels.
The exported PGM of the same frame was inspected visually.

## Analytic coverage (2026-10-09)

The 4×4 supersampler (lists of samples per sub-scanline, every edge tested on
every sub-scanline, a closure per bind in the flattening and path walk) was
replaced by analytic signed-area accumulation for `NonZero`, scanline spans
for `EvenOdd`, and explicit folds that thread the edge list, count, bounds,
and first error through the path walk.

`examples/bench.bend`: the 94 printable ASCII glyphs of Liberation Sans,
outlines parsed once, `R.rasterize` repeated. Pinned to one core with
`taskset -c 3`, `--threads 1 --gpu off`; old and new binaries interleaved,
3 runs × 3 batches each (9 batches), on a shared machine with load average
about 5–6 from other sessions.

| Glyphs | Before (median µs/glyph) | After (median µs/glyph) |
| --- | --- | --- |
| 16 px, `NonZero` | 70.5 (67.6–75.0) | 4.35 (4.18–4.67) |
| 64 px, `NonZero` | 755 (734–822) | 18.7 (17.9–19.0) |
| 16 px, `EvenOdd` | (same path as above) | 15.3 (15.0–16.5) |

The text demo (`examples/text.bend`, font load, layout, rasterization, PGM)
took 115 / 109 / 119 ms before and 68 / 66 / 71 ms after, same conditions.

Coverage changes: the demo image differs from the 4×4 output in 22284 of
548800 pixels, at most 60 levels, all on antialiased edges (mean ink 10.585
before, 10.592 after). Even-odd and non-zero renderings of the same glyphs at
120 px differ by at most 26 levels, on near-horizontal edges.

## Runtime findings

- `bend examples/window.bend` without `-o` stops with
  `Window.open: no display (build a native binary with bend <file> -o <out> ...)`.
  Windows need a native binary.
- The generated native runtime reserves an 8 GiB virtual arena at start-up with
  `MAP_NORESERVE`, plus large stack reservations. Running a binary under
  `RLIMIT_AS` of 6 GiB fails at once with `bend: reservation failed`, although
  the program's real RSS is about 50 MiB. Virtual-address limits are not memory
  limits for these programs; do not use them.
- The official file effect accepts `"r"` but not `"rb"` (exit 22,
  `Invalid argument`).
- Recursion over input-sized lists should be tail-recursive. Non-tail helpers in
  Runika's byte handling failed with `bend: memory fault (machine stack
  overflow?)` on a whole font file until they were rewritten.

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

# Dithra: instructions for contributors and agents

Dithra is the rasterization layer of the AMAGE UI ecosystem, implemented in
**Bend 2**: it turns glyph outlines and vector shapes into pixel coverage with
anti-aliasing, at the scales and positions the renderer needs. Read the README
for current capabilities and limits; a roadmap item is not implemented merely
because it appears in the project scope.

## Implementation

- Implement library logic in Bend 2, rather than wrapping an existing rasterizer
  or graphics library (FreeType, Skia, Cairo, ...).
- Use Splina's path types at the boundary instead of defining parallel ones.
  Document every coordinate system and conversion explicitly; never hide a scale.
- Validate paths and limits before allocating or subdividing. Return errors
  instead of partial results.
- The official Bend compiler/runtime, OS APIs, and drivers remain external
  dependencies. Keep any future native bridge minimal, explicit, and separate.
- Before writing Bend, run `bend version` and read `bend guide` from the installed
  toolchain. Verify available syntax/effects instead of assuming old examples work.
- Keep source, comments, documentation, and commit messages in English.

## Writing fast Bend

Correct Bend is not fast Bend by default. Measured rules (Bend 2.0.35):

- Indexed, large or hot data (bytes, pixels, coverage, quads) lives in an
  `Array<U32>` (native flat block, ~1 ns/read), not a `List`. Lists are fine
  when tiny, built once and consumed in order. Arrays are affine and cannot be
  fields of `Data` types: keep them local and convert once at the boundary.
- No `do Result`/`do Maybe` binds or callbacks per byte, pixel or glyph: each
  bind is a closure (45% of a measured profile). Thread state through one
  recursive def that matches on the result.
- `||`, `&&` and `Bool.pick` evaluate both sides; use `match` to stop early.
- Never `Array.clone` or append (`List.append`) in a loop; build with a
  reversed accumulator or a tail parameter.
- A parameter that a def only matches or passes to itself is borrowed (no
  refcount); descend trees with the selector as a parameter.
- Keep non-recursive records small (they are passed flattened; the widest one
  widens every call frame). Box big ones with an `Alias{x: T}` constructor.
- Split independent, balanced work of tens of µs or more with a parallel call
  (`a b = f(l) g(r)`); never parallelize tiny or IO-bound work.
- Measure before and after on the same input; print a result before the next
  `IO.now()`.

Here: coverage is accumulated as exact signed area in a local `Array<U32>`
(non-zero) or as exact spans over sub-rows (even-odd), then converted to
`Mask.coverage` once. That replaced 4x4 sample lists: 70.5 -> 4.35 us per 16px
glyph (`examples/bench.bend`). Keep per-edge and per-row work on arrays, and
measure with the bench before and after any change to `raster.bend`. Glyphs
are independent: a batch of missing glyphs is the natural parallel split.

## Linux first

The initial goal is excellent behavior on Ian's actual Linux development machine:
correct outlines and consistent anti-aliasing at different sizes and scales,
verified visually, with measured performance. Inspect the effective environment
before choosing integrations.

Build compatibility layers as the project progresses, after visible, well-made
Linux results. Do not let speculative Windows or macOS abstractions delay local
quality. Introduce abstractions from concrete needs.

## Working practice

- Preserve existing work and keep the library's boundary clear: font data
  belongs to Runika, layout to Syllo, composition and color to Chromi.
  Splina and Chromi import Dithra by relative path; coordinate API changes.
- Favor simple, maintainable code. Back performance claims with measurements.
- Run the native checks after changes. When output changes, export an image and
  look at it at several sizes; if a window is needed, capture only that window
  and close it.
- Compilation is not visual proof. Runtime checks are not proofs of the entire
  system. State partial support and unverified behavior explicitly.
- Build sequentially and keep compilation units small. Do not impose
  virtual-address limits on the Bend runtime or suppress crash reporting.
  Investigate failures before retrying.
- Keep generated binaries, images under `build/`, logs, crash dumps,
  credentials, and machine-specific evidence out of Git. Stage explicit paths
  and preserve concurrent changes.

See [CONTRIBUTING.md](CONTRIBUTING.md) for validation commands.

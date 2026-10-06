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

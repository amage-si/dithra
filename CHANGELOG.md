# Changelog

All notable changes to Dithra are recorded here. Dithra follows
[semantic versioning](https://semver.org) in its 0.x form: while the API is
experimental, a minor version (0.2.0) may change it in breaking ways and a
patch version (0.1.1) only fixes. Dithra is built from source together with its
sibling AMAGE libraries; the set of versions tested together is listed in
[eco-build's releases](https://github.com/amage-si/eco-build/tree/main/releases).

## [0.1.0] - 2026-10-09

First tagged release, tested with Bend 2.0.35 on Linux (X11/XWayland) as part
of AMAGE Eco 0.1.0.

### Included

- Quadratic and cubic flattening.
- Analytic area coverage for `NonZero` and exact-along-x spans for
  `EvenOdd`, with holes and overlaps.
- Glyph masks from Runika outlines and positioned masks for a Syllo layout.
- About 4.4 µs per 16 px glyph (the earlier 4x4 supersampler took 70 µs).
- 22 checks; `all_tests.bend` runs the whole text chain.

[0.1.0]: https://github.com/amage-si/dithra/releases/tag/v0.1.0

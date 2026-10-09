# Dithra API

`raster.bend` depends only on `Base` and [Splina](https://github.com/amage-si/splina)'s
path types (`Splina/path.bend`). `main.bend` adds
[Runika](https://github.com/amage-si/runika) and
[Syllo](https://github.com/amage-si/syllo). Import paths are relative to the
calling file. A module next to the sibling directories uses:

```bend
import Base
import ./Splina/path.bend as P
import ./Dithra/raster.bend as R
import ./Dithra/main.bend as D
```

All functions are pure and return `Result<&2, &2, String, T>`. Invalid input and
exceeded limits return `Fail{message}`, never a partial mask.

## Masks

```bend
Mask{width: U32, height: U32, left: F32, top: F32, advance: F32,
     coverage: List<&2, U32>}
```

- `coverage` holds exactly `width × height` values from 0 to 255, row-major:
  x increases along a row, rows go from top to bottom.
- `left` and `top` are whole-pixel offsets (stored as F32) of the mask's top-left
  corner from the origin: the glyph origin on the baseline, or the path's
  coordinate origin.
- `advance` is supplied by the caller, in physical pixels.
- A mask can be empty (`0 × 0`), for example for a space, while its advance stays
  positive.
- Coverage is not color. The compositor applies ink: Chromi uses coverage as
  alpha over straight (non-premultiplied) RGBA8.

## Rasterizing paths

| Function | Input coordinates |
| --- | --- |
| `R.rasterize_screen(path, advance)` | Physical pixels, x right, **y down** (Splina's screen paths). No scale is applied. |
| `R.rasterize(path, scale, advance)` | Font units, x right, **y up** (Runika outlines). Multiplies by `scale` and flips y. `scale` must be in `(0, 64]`. |

Every subpath must start with `MoveTo` and end with `ClosePath`. `Line`, `Quad`,
and `Cubic` segments are accepted. `NonZero` and `EvenOdd` follow the path's
`rule`.

## Text

```bend
PositionedMask{x: F32, y: F32, source_start: U32, source_end: U32, mask: R.Mask}

D.glyph(font, glyph_id, physical_size) -> Result<&2,&2,String,R.Mask>
D.render(font, layout, logical_size, device_scale)
  -> Result<&2,&2,String,List<&2,PositionedMask>>
```

- `glyph` rasterizes one Runika glyph at `physical_size` pixels per em, in
  `(0, 512]`, with the advance scaled from `hmtx`.
- `render` rasterizes every placement of a Syllo `Layout`. It uses the physical
  size `logical_size × device_scale`, with `device_scale` in `(0, 8]`, and
  multiplies the layout's logical positions by the same scale.
- `PositionedMask.x`/`y` are physical pixels relative to the layout's top-left
  corner, and already include the mask's `left`/`top`. The glyph origin is
  rounded down to a whole pixel before the offsets are added; there is no
  subpixel phase yet.
- `source_start`/`source_end` are copied from Syllo: Unicode scalar indices,
  end exclusive.

Chromi's `blit_mask` takes a logical origin. Pass `x / device_scale` and
`y / device_scale`; the mask itself already has physical dimensions. At device
scale 1 the two coincide, which is what the integration example uses.

## Limits

| Limit | Value |
| --- | --- |
| Path commands | 4096 |
| Edges after flattening | 32768 |
| Mask side | 1024 px |
| Mask area | 262144 px |
| Coordinates | finite, within ±1,000,000 |
| Glyph scale (`rasterize`) | `(0, 64]` |
| Physical glyph size (`glyph`) | `(0, 512]` |
| Device scale (`render`) | `(0, 8]` |
| Curve subdivision depth | 12 |

Control-point bounds are validated before subdivision.

## Algorithm

Curves are flattened by recursive subdivision. A quadratic piece is flat when
its control point lies within 0.25 px of the chord's midpoint (a curve error of
about 0.125 px); a cubic piece when both control points lie within 1/6 px of the
chord's thirds. A curve that needs more than 12 levels returns an error.

Coverage is computed in mask-local pixels, `x' = x - left` and
`y' = y - top`, y down, inside `[0, width] × [0, height]`. The accumulator is a
local `Array<U32>` with `width + 1` slots per row, holding signed 16.16 fixed
point in two's complement (one pixel of winding 1 is 65536); it never leaves
the rasterizer, which builds `coverage` from it once.

- `NonZero`: for every row an edge crosses, the piece inside the row (height
  `dy`, x range `lo..hi`) adds to each cell the change of the area right of the
  edge, so the row sums to `round(dy × 65536)` exactly. A running sum along the
  row gives each pixel's signed winding area; coverage is
  `round(255 × min(|area|, 1))`. Downward edges count +1, upward −1.
- `EvenOdd`: four sub-scanlines per pixel row, at `y' = (k + 1/2) / 4`, cross
  the active edges with half-open intervals `y0 <= y < y1`. Sorted crossings
  pair into inside spans, and each span adds two vertical steps of height 1/4
  at its exact x ends to the same accumulator, read back as above.

Values are exact for straight edges when no pixel holds two same-direction
overlapping contours (`NonZero`) and up to the four sub-scanlines along y
(`EvenOdd`).

## Runtime boundary

Rasterization happens entirely in Bend. Exporting images (PGM in the examples)
uses the official file effect; the window example uses Ankra and the official
window effect.

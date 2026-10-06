import Base
import ../Runika/font.bend as F
import ../Runika/glyf.bend as G
import ../Splina/path.bend as P
import ../Syllo/main.bend as S
import ./raster.bend as R

type PositionedMask is Data:
  PositionedMask{x: F32, y: F32, source_start: U32, source_end: U32, mask: R.Mask}

def glyph(+font: F.Font, +gid: U32, +physical_size: F32) -> Result<&2, &2, String, R.Mask>:
  do Result<&2, &2, String, R.Mask>:
    ok : Unit <- R.require(Bool.and(F32.is_gt(physical_size, 0.0), F32.is_le(physical_size, 512.0)), "physical font size must be in (0,512]")
    m : F.Metric <- F.metric(font, gid)
    path : P.Path <- G.outline(font, gid)
    +scale : F32 = (physical_size / S.units(font) : F32)
    R.rasterize(path, scale, (S.advance(m) * scale : F32))

def position(mask: R.Mask, x: F32, y: F32, start: U32, end: U32) -> PositionedMask:
  match mask:
    case R.Mask{w, h, +left, +top, advance, coverage}:
      PositionedMask{(F32.floor(x) + left : F32), (F32.floor(y) + top : F32), start, end, R.Mask{w, h, left, top, advance, coverage}}

def render_placements(ps: List<&2, S.Placement>, +font: F.Font, +size: F32, +device_scale: F32) -> Result<&2, &2, String, List<&2, PositionedMask>>:
  match ps:
    case Nil{}:
      Done{Nil{}}
    case Con{S.Placement{gid, start, end, x, baseline, advance, line}, tail}:
      do Result<&2, &2, String, List<&2, PositionedMask>>:
        m : R.Mask <- glyph(font, gid, (size * device_scale : F32))
        rest : List<&2, PositionedMask> <- render_placements(tail, font, size, device_scale)
        return Con{position(m, (x * device_scale : F32), (baseline * device_scale : F32), start, end), rest}

def render(font: F.Font, layout: S.Layout, size: F32, +device_scale: F32) -> Result<&2, &2, String, List<&2, PositionedMask>>:
  match layout:
    case S.Layout{ps, width, height, asc, desc, lh, lines}:
      do Result<&2, &2, String, List<&2, PositionedMask>>:
        ok : Unit <- R.require(Bool.and(F32.is_gt(device_scale, 0.0), F32.is_le(device_scale, 8.0)), "device scale must be in (0,8]")
        render_placements(ps, font, size, device_scale)

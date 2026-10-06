import Base
import ../Splina/path.bend as P
import ../Runika/check.bend as C
import ../Runika/font.bend as F
import ./raster.bend as R
import ./main.bend as D

def rectangle(+l: F32, +t: F32, +r: F32, +b: F32) -> List<&2, P.Segment>:
  [P.MoveTo{P.Point{l,t}}, P.Line{P.Point{r,t}}, P.Line{P.Point{r,b}}, P.Line{P.Point{l,b}}, P.ClosePath{}]

def equal_bytes(a: List<&2, U32>, b: List<&2, U32>) -> Bool:
  match a b:
    case Nil{} Nil{}: True{}
    case Con{x, xs} Con{y, ys}: Bool.and(U32.is_eq(x, y), equal_bytes(xs, ys))
    case _ _: False{}

def mask_bytes(m: R.Mask, expected: List<&2, U32>) -> Bool:
  match m:
    case R.Mask{w,h,l,t,a,cs}: equal_bytes(cs, expected)

def coverage(m: R.Mask) -> List<&2, U32>:
  match m:
    case R.Mask{w,h,l,t,a,cs}: cs

def partial(cs: List<&2, U32>) -> Bool:
  match cs:
    case Nil{}: False{}
    case Con{+h,t}: Bool.or(Bool.and(U32.is_gt(h, 0), U32.is_lt(h, 255)), partial(t))

def bounded(cs: List<&2, U32>) -> Bool:
  match cs:
    case Nil{}: True{}
    case Con{h,t}: Bool.and(U32.is_le(h, 255), bounded(t))

def well_formed(m: R.Mask) -> Bool:
  match m:
    case R.Mask{w,h,l,t,a,+cs}:
      Bool.and(U32.is_eq(U32.from_nat(List.length(&2, U32, cs)), (w * h : U32)), bounded(cs))

def space(m: R.Mask) -> Bool:
  match m:
    case R.Mask{0,0,l,t,advance,Nil{}}: F32.is_gt(advance, 0.0)
    case _: False{}

def main() -> IO(Unit):
  do IO<Unit>:
    full : R.Mask <- C.unwrap(R.Mask, R.rasterize_screen(P.Path{rectangle(0.0,0.0,1.0,1.0), P.NonZero{}}, 1.0))
    C.expect(mask_bytes(full, [255]), "unit square fully covered; horizontal edges and shared vertices")
    half : R.Mask <- C.unwrap(R.Mask, R.rasterize_screen(P.Path{rectangle(0.0,0.0,0.5,1.0), P.NonZero{}}, 1.0))
    C.expect(mask_bytes(half, [128]), "half pixel equals 8 of 16 samples")
    quarter : R.Mask <- C.unwrap(R.Mask, R.rasterize_screen(P.Path{rectangle(0.0,0.0,0.5,0.5), P.NonZero{}}, 1.0))
    C.expect(mask_bytes(quarter, [64]), "quarter pixel equals 4 of 16 samples")
    +double : List<&2, P.Segment> = List.append(&2, P.Segment, rectangle(0.0,0.0,1.0,1.0), rectangle(0.0,0.0,1.0,1.0))
    nonzero : R.Mask <- C.unwrap(R.Mask, R.rasterize_screen(P.Path{double,P.NonZero{}}, 0.0))
    parity : R.Mask <- C.unwrap(R.Mask, R.rasterize_screen(P.Path{double,P.EvenOdd{}}, 0.0))
    C.expect(mask_bytes(nonzero,[255]), "overlap preserved by nonzero winding")
    C.expect(mask_bytes(parity,[0]), "even-odd overlap cancels")
    hole : R.Mask <- C.unwrap(R.Mask, R.rasterize_screen(P.Path{List.append(&2,P.Segment,rectangle(0.0,0.0,3.0,3.0), rectangle(1.0,1.0,2.0,2.0)),P.EvenOdd{}}, 0.0))
    C.expect(mask_bytes(hole,[255,255,255,255,0,255,255,255,255]), "subpath hole is preserved")
    +curve : R.Mask <- C.unwrap(R.Mask, R.rasterize_screen(P.Path{[P.MoveTo{P.Point{0.0,4.0}},P.Quad{P.Point{2.0,0.0},P.Point{4.0,4.0}},P.ClosePath{}],P.NonZero{}}, 0.0))
    C.expect(Bool.and(well_formed(curve),partial(coverage(curve))), "quadratic antialiasing and buffer dimensions")
    cubic : R.Mask <- C.unwrap(R.Mask, R.rasterize_screen(P.Path{[P.MoveTo{P.Point{0.0,4.0}},P.Cubic{P.Point{0.0,0.0},P.Point{4.0,0.0},P.Point{4.0,4.0}},P.ClosePath{}],P.NonZero{}}, 0.0))
    C.expect(partial(coverage(cubic)), "shared Splina cubic path rasterized")
    C.expect(C.is_fail(R.Mask,R.rasterize_screen(P.Path{[P.Line{P.Point{1.0,1.0}}],P.NonZero{}},0.0)), "line without move rejected")
    C.expect(C.is_fail(R.Mask,R.rasterize_screen(P.Path{[P.MoveTo{P.Point{0.0,0.0}},P.Line{P.Point{1.0,1.0}}],P.NonZero{}},0.0)), "open subpath rejected")
    C.expect(C.is_fail(R.Mask,R.rasterize_screen(P.Path{rectangle(0.0,0.0,1025.0,1.0),P.NonZero{}},0.0)), "oversized mask rejected before rasterization")
    C.expect(C.is_fail(R.Mask,R.rasterize(P.Path{Nil{},P.NonZero{}},0.0,0.0)), "zero scale rejected")
    fr : Result<&2,&2,String,F.Font> <- F.load("/usr/share/fonts/liberation/LiberationSans-Regular.ttf")
    +font : F.Font <- C.unwrap(F.Font,fr)
    blank : R.Mask <- C.unwrap(R.Mask,D.glyph(font,3,24.0))
    C.expect(space(blank), "real space has zero bitmap and positive advance")
    +a12 : R.Mask <- C.unwrap(R.Mask,D.glyph(font,165,12.0))
    C.expect(Bool.and(well_formed(a12),partial(coverage(a12))), "real composed accent at 12px")
    +a48 : R.Mask <- C.unwrap(R.Mask,D.glyph(font,165,48.0))
    C.expect(Bool.and(well_formed(a48),partial(coverage(a48))), "real composed accent at 48px")
    IO.print("Dithra tests complete")

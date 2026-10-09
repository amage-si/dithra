import Base
import ../Splina/path.bend as P
import ../Runika/check.bend as C
import ../Runika/font.bend as F
import ./raster.bend as R
import ./main.bend as D

def rectangle(+l: F32, +t: F32, +r: F32, +b: F32) -> List<&2, P.Segment>:
  [P.MoveTo{P.Point{l,t}}, P.Line{P.Point{r,t}}, P.Line{P.Point{r,b}}, P.Line{P.Point{l,b}}, P.ClosePath{}]

def lines(ps: List<&2, P.Point>) -> List<&2, P.Segment>:
  match ps:
    case Nil{}: [P.ClosePath{}]
    case Con{h, t}: Con{P.Line{h}, lines(t)}

def polygon(ps: List<&2, P.Point>) -> List<&2, P.Segment>:
  match ps:
    case Nil{}: Nil{}
    case Con{h, t}: Con{P.MoveTo{h}, lines(t)}

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
    C.expect(mask_bytes(half, [128]), "half pixel: area 1/2 gives 128")
    quarter : R.Mask <- C.unwrap(R.Mask, R.rasterize_screen(P.Path{rectangle(0.0,0.0,0.5,0.5), P.NonZero{}}, 1.0))
    C.expect(mask_bytes(quarter, [64]), "quarter pixel: area 1/4 gives 64")
    # Exact area, rounded half up: 0.3 * 255 = 76.5 (4x4 sampling gave 64).
    strip : R.Mask <- C.unwrap(R.Mask, R.rasterize_screen(P.Path{rectangle(0.0,0.0,0.3,1.0), P.NonZero{}}, 1.0))
    C.expect(mask_bytes(strip, [77]), "0.3 pixel strip gives round(76.5) = 77")
    # A diagonal halves the pixel: 127.5 rounds to 128 (4x4 sampling gave 96).
    diagonal : R.Mask <- C.unwrap(R.Mask, R.rasterize_screen(P.Path{polygon([P.Point{0.0,0.0},P.Point{1.0,0.0},P.Point{0.0,1.0}]), P.NonZero{}}, 1.0))
    C.expect(mask_bytes(diagonal, [128]), "diagonal half pixel gives 128")
    # One row, the edge crosses four cells: pixel j holds (7 - 2j)/8 of its
    # area, 255 * [7,5,3,1]/8 = 223.1, 159.4, 95.6, 31.9. The even-odd spans
    # reach the same values: the midpoint rule is exact for a straight edge.
    shallow : R.Mask <- C.unwrap(R.Mask, R.rasterize_screen(P.Path{polygon([P.Point{0.0,0.0},P.Point{4.0,0.0},P.Point{0.0,1.0}]), P.EvenOdd{}}, 1.0))
    C.expect(mask_bytes(shallow, [223,159,96,32]), "even-odd spans: shallow edge across four cells")
    wedge : R.Mask <- C.unwrap(R.Mask, R.rasterize_screen(P.Path{polygon([P.Point{0.0,0.0},P.Point{4.0,0.0},P.Point{0.0,1.0}]), P.NonZero{}}, 1.0))
    C.expect(mask_bytes(wedge, [223,159,96,32]), "non-zero area: shallow edge across four cells")
    # One column, the edge crosses four rows: row r holds (2r + 1)/8.
    steep : R.Mask <- C.unwrap(R.Mask, R.rasterize_screen(P.Path{polygon([P.Point{0.0,0.0},P.Point{1.0,4.0},P.Point{0.0,4.0}]), P.NonZero{}}, 1.0))
    C.expect(mask_bytes(steep, [32,96,159,223]), "steep edge across four rows: exact areas per row")
    +double : List<&2, P.Segment> = List.append(&2, P.Segment, rectangle(0.0,0.0,1.0,1.0), rectangle(0.0,0.0,1.0,1.0))
    nonzero : R.Mask <- C.unwrap(R.Mask, R.rasterize_screen(P.Path{double,P.NonZero{}}, 0.0))
    parity : R.Mask <- C.unwrap(R.Mask, R.rasterize_screen(P.Path{double,P.EvenOdd{}}, 0.0))
    C.expect(mask_bytes(nonzero,[255]), "overlap preserved by nonzero winding")
    C.expect(mask_bytes(parity,[0]), "even-odd overlap cancels")
    hole : R.Mask <- C.unwrap(R.Mask, R.rasterize_screen(P.Path{List.append(&2,P.Segment,rectangle(0.0,0.0,3.0,3.0), rectangle(1.0,1.0,2.0,2.0)),P.EvenOdd{}}, 0.0))
    C.expect(mask_bytes(hole,[255,255,255,255,0,255,255,255,255]), "subpath hole is preserved")
    +inner : List<&2, P.Segment> = polygon([P.Point{1.0,1.0},P.Point{1.0,2.0},P.Point{2.0,2.0},P.Point{2.0,1.0}])
    counter : R.Mask <- C.unwrap(R.Mask, R.rasterize_screen(P.Path{List.append(&2,P.Segment,rectangle(0.0,0.0,3.0,3.0), inner),P.NonZero{}}, 0.0))
    C.expect(mask_bytes(counter,[255,255,255,255,0,255,255,255,255]), "nonzero hole from an opposite contour")
    # Two overlapping half-pixel strips: [0,0.5] has winding 1 and [0.25,0.75]
    # adds one more. Even-odd keeps [0,0.25] and [0.5,0.75]: area 1/2. An
    # averaged winding (mean 1) would read as full coverage here.
    stripes : R.Mask <- C.unwrap(R.Mask, R.rasterize_screen(P.Path{List.append(&2,P.Segment,rectangle(0.0,0.0,0.5,1.0), rectangle(0.25,0.0,0.75,1.0)),P.EvenOdd{}}, 0.0))
    C.expect(mask_bytes(stripes,[128]), "even-odd inside one pixel with windings 1 and 2")
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

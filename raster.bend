import Base
import ../Splina/path.bend as P

type Edge is Data:
  Edge{x0: F32, y0: F32, x1: F32, y1: F32}

type Mask is Data:
  Mask{width: U32, height: U32, left: F32, top: F32, advance: F32,
    coverage: List<&2, U32>}

type Bounds is Data:
  Bounds{left: F32, top: F32, right: F32, bottom: F32}

def add_point(b: Bounds, p: P.Point) -> Bounds:
  match b p:
    case Bounds{l,t,r,b} P.Point{+x,+y}:
      Bounds{F32.min(l,x),F32.min(t,y),F32.max(r,x),F32.max(b,y)}

def require(ok: Bool, message: String) -> Result<&2, &2, String, Unit>:
  match ok:
    case True{}: Done{Unit{}}
    case False{}: Fail{message}

def finite(+x: F32) -> Bool:
  Bool.and(F32.is_ge(x, F32.neg(1000000.0)), F32.is_le(x, 1000000.0))

def point_valid(p: P.Point) -> Bool:
  match p:
    case P.Point{x, y}:
      Bool.and(finite(x), finite(y))

# Preflight: one fold over the commands, threading the control bounds. Bad
# carries the first error, so later commands are not examined.
type Pre is Data:
  Fine{bounds: Bounds}
  Bad{message: String}

def checked(ok: Bool, b: Bounds) -> Pre:
  match ok:
    case True{}: Fine{b}
    case False{}: Bad{"invalid path coordinate"}

def segment_bounds(s: P.Segment, b: Bounds) -> Pre:
  match s:
    case P.MoveTo{+p}:
      checked(point_valid(p), add_point(b,p))
    case P.Line{+p}:
      checked(point_valid(p), add_point(b,p))
    case P.Quad{+c,+p}:
      checked(Bool.and(point_valid(c),point_valid(p)), add_point(add_point(b,c),p))
    case P.Cubic{+c1,+c2,+p}:
      checked(Bool.and(point_valid(c1),Bool.and(point_valid(c2),point_valid(p))), add_point(add_point(add_point(b,c1),c2),p))
    case P.ClosePath{}:
      Fine{b}

def counted(ok: Bool, s: P.Segment, b: Bounds) -> Pre:
  match ok:
    case True{}: segment_bounds(s, b)
    case False{}: Bad{"path exceeds 4096 commands"}

def preflight_end(nonempty: Bool, b: Bounds) -> Result<&2,&2,String,Unit>:
  match nonempty b:
    case False{} _: Done{Unit{}}
    case True{} Bounds{l,t,r,b}:
      +w = (F32.ceil(r) - F32.floor(l) : F32)
      +h = (F32.ceil(b) - F32.floor(t) : F32)
      require(Bool.and(Bool.and(F32.is_le(w,1024.0),F32.is_le(h,1024.0)), F32.is_le((w * h : F32),262144.0)), "control bounds exceed raster budget")

def preflight(xs: List<&2,P.Segment>, +count: U32, st: Pre) -> Result<&2,&2,String,Unit>:
  match xs st:
    case _ Bad{m}: Fail{m}
    case Nil{} Fine{b}: preflight_end(U32.is_gt(count,0),b)
    case Con{h,t} Fine{b}:
      preflight(t,(count + 1 : U32),counted(U32.is_lt(count,4096),h,b))

def screen(p: P.Point, +scale: F32) -> P.Point:
  match p:
    case P.Point{x, y}:
      P.Point{(x * scale : F32), F32.neg((y * scale : F32))}

# Edges
# -----
#
# The path is walked once. Curves are flattened straight into the running
# Build (edges are prepended; their order does not matter to the
# accumulator), and the edge count and edge bounds are threaded along with
# them. Horizontal edges change no coverage, so they are counted and widen
# the bounds but are not stored. Broken carries the first error.

type Build is Data:
  Build{edges: List<&2, Edge>, count: U32, bounds: Bounds}
  Broken{message: String}

def include(b: Bounds, +x0: F32, +y0: F32, +x1: F32, +y1: F32) -> Bounds:
  match b:
    case Bounds{l, t, r, b}:
      Bounds{F32.min(l, F32.min(x0, x1)), F32.min(t, F32.min(y0, y1)),
        F32.max(r, F32.max(x0, x1)), F32.max(b, F32.max(y0, y1))}

def keep_edge(level: Bool, e: Edge, es: List<&2, Edge>) -> List<&2, Edge>:
  match level:
    case True{}: es
    case False{}: Con{e, es}

def push(acc: Build, a: P.Point, b: P.Point) -> Build:
  match acc a b:
    case Build{es, n, bd} P.Point{+ax, +ay} P.Point{+bx, +by}:
      Build{keep_edge(F32.is_eq(ay, by), Edge{ax, ay, bx, by}, es), (n + 1 : U32), include(bd, ax, ay, bx, by)}
    case Broken{m} _ _:
      Broken{m}

def broken(acc: Build, message: String) -> Build:
  match acc:
    case Build{es, n, bd}: Broken{message}
    case Broken{m}: Broken{m}

# For a quadratic, half the control-to-chord-midpoint distance bounds the
# curve's distance from its chord. Subdivision halves parameter intervals.
def flat(a: P.Point, c: P.Point, b: P.Point) -> Bool:
  match a c b:
    case P.Point{ax, ay} P.Point{cx, cy} P.Point{bx, by}:
      F32.is_le(F32.hypot((cx - ((ax + bx) * 0.5) : F32), (cy - ((ay + by) * 0.5) : F32)), 0.25)

def flatten(+depth: Nat, enough: Bool, +a: P.Point, +c: P.Point, +b: P.Point, acc: Build) -> Build:
  match depth enough:
    case _ True{}:
      push(acc, a, b)
    case 0n False{}:
      broken(acc, "quadratic flattening exceeded 12 subdivisions")
    case 1n+p False{}:
      +ac = P.midpoint(a, c)
      +cb = P.midpoint(c, b)
      +mid = P.midpoint(ac, cb)
      flatten(p, flat(mid, cb, b), mid, cb, b, flatten(p, flat(a, ac, mid), a, ac, mid, acc))

def distance(a: P.Point, b: P.Point) -> F32:
  match a b:
    case P.Point{ax,ay} P.Point{bx,by}: F32.hypot((ax - bx : F32),(ay - by : F32))

def cubic_flat(+a: P.Point, b: P.Point, c: P.Point, +d: P.Point) -> Bool:
  Bool.and(F32.is_le(distance(b,P.lerp(a,d,0.333333333)),0.16666666),
    F32.is_le(distance(c,P.lerp(a,d,0.666666667)),0.16666666))

def flatten_cubic(+depth: Nat, enough: Bool, +a: P.Point, +b: P.Point, +c: P.Point, +d: P.Point, acc: Build) -> Build:
  match depth enough:
    case _ True{}:
      push(acc, a, d)
    case 0n False{}:
      broken(acc, "cubic flattening exceeded 12 subdivisions")
    case 1n+p False{}:
      +ab = P.midpoint(a, b)
      +bc = P.midpoint(b, c)
      +cd = P.midpoint(c, d)
      +abc = P.midpoint(ab, bc)
      +bcd = P.midpoint(bc, cd)
      +mid = P.midpoint(abc, bcd)
      flatten_cubic(p, cubic_flat(mid, bcd, cd, d), mid, bcd, cd, d,
        flatten_cubic(p, cubic_flat(a, ab, abc, mid), a, ab, abc, mid, acc))

# Coordinates were validated by `preflight` before the walk.
def walk(xs: List<&2, P.Segment>, acc: Build, first: Maybe<&2, P.Point>, current: Maybe<&2, P.Point>) -> Build:
  match xs acc first current:
    case _ Broken{m} _ _:
      Broken{m}
    case Nil{} Build{es, n, bd} None{} _:
      Build{es, n, bd}
    case Nil{} Build{es, n, bd} Some{p} _:
      Broken{"unclosed subpath"}
    case Con{P.MoveTo{+to}, t} Build{es, n, bd} None{} None{}:
      walk(t, Build{es, n, bd}, Some{to}, Some{to})
    case Con{P.Line{+to}, t} Build{es, n, bd} Some{start} Some{from}:
      walk(t, push(Build{es, n, bd}, from, to), Some{start}, Some{to})
    case Con{P.Quad{+control, +to}, t} Build{es, n, bd} Some{start} Some{+from}:
      walk(t, flatten(12n, flat(from, control, to), from, control, to, Build{es, n, bd}), Some{start}, Some{to})
    case Con{P.Cubic{+b, +c, +to}, t} Build{es, n, bd} Some{start} Some{+from}:
      walk(t, flatten_cubic(12n, cubic_flat(from, b, c, to), from, b, c, to, Build{es, n, bd}), Some{start}, Some{to})
    case Con{P.ClosePath{}, t} Build{es, n, bd} Some{start} Some{from}:
      walk(t, push(Build{es, n, bd}, from, start), None{}, None{})
    case _ _ _ _:
      Broken{"invalid path: every subpath requires MoveTo and explicit ClosePath"}

# Coverage
# --------
#
# Analytic signed-area accumulation (the font-rs / stb_truetype scheme).
# Mask-local coordinates: x' = x - left and y' = y - top, in pixels, with
# 0 <= x' <= width and 0 <= y' <= height, y down. For every pixel row an edge
# crosses, the part of the edge inside the row (vertical extent dy) adds, to
# each cell, the change of "area right of the edge" from the previous cell.
# A running sum along the row then gives the pixel's signed winding area.
#
# The accumulator is a local Array<U32> with width + 1 slots per row (the
# last one takes what falls right of the mask) holding signed 16.16 fixed
# point in two's complement: one full pixel of winding 1 is 65536. Per row,
# each edge adds exactly round(dy * 65536) in total (the last cell takes the
# remainder), so contributions cancel exactly across a row. The array never
# leaves this module: the result is converted to Mask.coverage once.

def fix(+v: F32) -> U32:
  F32.to_u32(F32.floor(((v * 65536.0) + 0.5 : F32)))

def bump.at(r: Array<U32> & U32, +i: U32, v: U32) -> Array<U32>:
  (b, old) = r
  Array.set(U32, b, i, (old + v : U32))

def bump(a: Array<U32>, +i: U32, v: U32) -> Array<U32>:
  bump.at(Array.get(U32, a, i), i, v)

# Integral of clamp(z, 0, 1) from -infinity to z.
def ramp_area(+z: F32) -> F32:
  +c = F32.clamp(z, 0.0, 1.0)
  ((c * c * 0.5) + F32.max((z - 1.0 : F32), 0.0) : F32)

# Cells ilo..ihi-1 of a row piece running from lo to hi (lo < hi). The
# coverage the piece gives cell j is dy * s * (A(j+1-lo) - A(j+1-hi)), with
# s = 1 / (hi - lo) and A = ramp_area; each cell stores the difference from
# the previous one and cell ihi takes the rest of round(dy * 65536).
def span(n: Nat, a: Array<U32>, +i: U32, +jf: F32, +lo: F32, +hi: F32, +s: F32, +dy: F32, +dm: U32, +prev: U32, +sign: U32) -> Array<U32>:
  match n:
    case 0n:
      bump(a, i, ((dm - prev) * sign : U32))
    case 1n+p:
      +c = fix((dy * s * (ramp_area((jf + 1.0 - lo : F32)) - ramp_area((jf + 1.0 - hi : F32))) : F32))
      span(p, bump(a, i, ((c - prev) * sign : U32)), (i + 1 : U32), (jf + 1.0 : F32), lo, hi, s, dy, dm, c, sign)

# One cell column (ihi <= ilo + 1): the piece covers (1 - xm) of cell ilo,
# where xm is its mean x inside the cell, and the rest goes to ilo + 1.
def cells(single: Bool, a: Array<U32>, +i: U32, +ilo: U32, +ihi: U32, +lo: F32, +hi: F32, +dy: F32, +sign: U32) -> Array<U32>:
  match single:
    case True{}:
      +dm = fix(dy)
      +c = fix((dy * (1.0 - (((lo + hi) * 0.5) - U32.to_f32(ilo))) : F32))
      bump(bump(a, i, (c * sign : U32)), (i + 1 : U32), ((dm - c) * sign : U32))
    case False{}:
      span(U32.to_nat((ihi - ilo : U32)), a, i, U32.to_f32(ilo), lo, hi, (1.0 / (hi - lo) : F32), dy, fix(dy), 0, sign)

# Rows r.. of an edge oriented downward (y0 < y1), clamped to the mask.
def rows(n: Nat, a: Array<U32>, +x0: F32, +y0: F32, +y1: F32, +dxdy: F32, +sign: U32, +r: U32, +stride: U32, +w: U32, +wf: F32) -> Array<U32>:
  match n:
    case 0n: a
    case 1n+p:
      +rf = U32.to_f32(r)
      +top = F32.max(rf, y0)
      +bot = F32.min((rf + 1.0 : F32), y1)
      +xa = (x0 + ((top - y0) * dxdy) : F32)
      +xb = (x0 + ((bot - y0) * dxdy) : F32)
      +lo = F32.clamp(F32.min(xa, xb), 0.0, wf)
      +hi = F32.clamp(F32.max(xa, xb), 0.0, wf)
      +ilo = U32.min(F32.to_u32(F32.floor(lo)), (w - 1 : U32))
      +ihi = F32.to_u32(F32.ceil(hi))
      rows(p, cells(U32.is_le(ihi, (ilo + 1 : U32)), a, ((r * stride) + ilo : U32), ilo, ihi, lo, hi, (bot - top : F32), sign),
        x0, y0, y1, dxdy, sign, (r + 1 : U32), stride, w, wf)

def oriented(+x0: F32, +y0: F32, +x1: F32, +y1: F32, +sign: U32, a: Array<U32>, +stride: U32, +w: U32, +hf: F32) -> Array<U32>:
  +r0 = F32.max(F32.floor(y0), 0.0)
  +r1 = F32.min(F32.ceil(y1), hf)
  rows(U32.to_nat(F32.to_u32(F32.max((r1 - r0 : F32), 0.0))), a, x0, y0, y1, ((x1 - x0) / (y1 - y0) : F32), sign,
    F32.to_u32(r0), stride, w, U32.to_f32(w))

# Downward edges add winding +1, upward ones -1 (4294967295).
def line(down: Bool, +x0: F32, +y0: F32, +x1: F32, +y1: F32, a: Array<U32>, +stride: U32, +w: U32, +hf: F32) -> Array<U32>:
  match down:
    case True{}: oriented(x0, y0, x1, y1, 1, a, stride, w, hf)
    case False{}: oriented(x1, y1, x0, y0, 4294967295, a, stride, w, hf)

def accumulate(es: List<&2, Edge>, a: Array<U32>, +left: F32, +top: F32, +stride: U32, +w: U32, +hf: F32) -> Array<U32>:
  match es:
    case Nil{}: a
    case Con{Edge{+x0, +y0, +x1, +y1}, t}:
      accumulate(t, line(F32.is_lt(y0, y1), (x0 - left : F32), (y0 - top : F32), (x1 - left : F32), (y1 - top : F32), a, stride, w, hf),
        left, top, stride, w, hf)

# Non-zero: |winding area| clamped to one pixel. Exact when no pixel holds
# two overlapping contours of the same direction (windings 0 and 2 inside one
# pixel average to 1 and read as full), the same compromise as FreeType and
# stb_truetype. Glyph outlines use non-zero with opposite-direction holes.
def nonzero(s: U32) -> U32:
  +v = s
  U32.shrn(((U32.min(U32.min(v, (0 - v : U32)), 65536) * 255) + 32768 : U32), 16n)

# Walks a row from its right end: before cell x, `run` holds the sum of the
# slots right of x, which is minus the running sum up to x because each row
# sums to zero. Coverage is prepended, so the list comes out row-major.
# `r` is the array with the slot just read (at i + 1): the slot right of x.
def cols(~f: U32 -> U32, n: Nat, r: Array<U32> & U32, +i: U32, +run: U32, out: List<&2, U32>) -> Array<U32> & List<&2, U32>:
  match n:
    case 0n:
      (a, v) = r
      (a, out)
    case 1n+p:
      (a, v) = r
      +next = (run + v : U32)
      cols(~f, p, Array.get(U32, a, i), (i - 1 : U32), next, Con{f(next), out})

def emit(~f: U32 -> U32, n: Nat, r: Array<U32> & List<&2, U32>, +base: U32, +stride: U32, +w: U32) -> List<&2, U32>:
  match n:
    case 0n:
      (a, out) = r
      out
    case 1n+p:
      (a, out) = r
      emit(~f, p, cols(~f, U32.to_nat(w), Array.get(U32, a, (base + w : U32)), (base + w - 1 : U32), 0, out),
        (base - stride : U32), stride, w)

# Smallest d with 2^d >= n.
def depth.pick(small: Bool, +n: U32) -> Nat:
  match small:
    case True{}: 0n
    case False{}: 1n+U32.log2((n - 1 : U32))

def depth(+n: U32) -> Nat:
  depth.pick(U32.is_le(n, 1), n)

def covered(~f: U32 -> U32, es: List<&2, Edge>, +w: U32, +h: U32, +left: F32, +top: F32) -> List<&2, U32>:
  +stride = (w + 1 : U32)
  emit(~f, U32.to_nat(h), (accumulate(es, Array.new(U32, depth((stride * h : U32)), 0), left, top, stride, w, U32.to_f32(h)), Nil{}),
    ((h - 1) * stride : U32), stride, w)

# Even-odd
# --------
#
# Averaging the winding cannot give parity (windings 1 and 2 inside one pixel
# average to 1.5), so even-odd keeps a scanline path: four sub-scanlines per
# pixel row (at y' = (k + 1/2) / 4) intersect the active edges, the sorted
# crossings pair up into inside spans, and each span is written into the same
# accumulator as two vertical steps of height 1/4 at its exact x ends. Spans
# never overlap, so the non-zero conversion reads them back. Coverage is exact
# along x and sampled along y (midpoint rule: exact for an edge that is
# straight within the row). Edges are sorted by their top once and enter the
# active list as the scanline reaches them.

type Seg is Data:
  Seg{x0: F32, y0: F32, y1: F32, dxdy: F32}

def seg(+x0: F32, +y0: F32, +x1: F32, +y1: F32) -> Seg:
  Seg{x0, y0, y1, ((x1 - x0) / (y1 - y0) : F32)}

def downward(down: Bool, +x0: F32, +y0: F32, +x1: F32, +y1: F32) -> Seg:
  match down:
    case True{}: seg(x0, y0, x1, y1)
    case False{}: seg(x1, y1, x0, y0)

def segs(es: List<&2, Edge>, +left: F32, +top: F32, acc: List<&2, Seg>) -> List<&2, Seg>:
  match es:
    case Nil{}: acc
    case Con{Edge{+x0, +y0, +x1, +y1}, t}:
      segs(t, left, top, Con{downward(F32.is_lt(y0, y1), (x0 - left : F32), (y0 - top : F32), (x1 - left : F32), (y1 - top : F32)), acc})

def seg_le(a: Seg, b: Seg) -> Bool:
  match a b:
    case Seg{ax, ay, aend, ad} Seg{bx, by, bend, bd}: F32.is_le(ay, by)

def starts_by(xs: List<&2, Seg>, +y: F32) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{Seg{x0, y0, y1, d}, t}: F32.is_le(y0, y)

# Moves the edges that start at or above y from `pending` (sorted by top)
# to `active`.
def admit(xs: List<&2, Seg>, go: Bool, +y: F32, active: List<&2, Seg>) -> List<&2, Seg> & List<&2, Seg>:
  match xs go:
    case Con{s, +t} True{}: admit(t, starts_by(t, y), y, Con{s, active})
    case _ _: (xs, active)

def before(xs: List<&2, F32>, +x: F32) -> Bool:
  match xs:
    case Nil{}: False{}
    case Con{h, t}: F32.is_lt(h, x)

def insert(xs: List<&2, F32>, +x: F32, go: Bool) -> List<&2, F32>:
  match xs go:
    case Con{h, +t} True{}: Con{h, insert(t, x, before(t, x))}
    case _ _: Con{x, xs}

def alive(s: Seg, +y: F32) -> Bool:
  match s:
    case Seg{x0, y0, y1, d}: F32.is_lt(y, y1)

def at(s: Seg, +y: F32) -> F32:
  match s:
    case Seg{x0, y0, y1, d}: (x0 + ((y - y0) * d) : F32)

def keep_seg(ok: Bool, s: Seg, keep: List<&2, Seg>) -> List<&2, Seg>:
  match ok:
    case True{}: Con{s, keep}
    case False{}: keep

def add_cross(ok: Bool, +x: F32, +xs: List<&2, F32>) -> List<&2, F32>:
  match ok:
    case True{}: insert(xs, x, before(xs, x))
    case False{}: xs

# Half-open edges (y0 <= y < y1): a shared vertex is crossed once.
def scan(active: List<&2, Seg>, +y: F32, keep: List<&2, Seg>, xs: List<&2, F32>) -> List<&2, Seg> & List<&2, F32>:
  match active:
    case Nil{}: (keep, xs)
    case Con{+s, t}:
      +ok = alive(s, y)
      scan(t, y, keep_seg(ok, s, keep), add_cross(ok, at(s, y), xs))

def mark(a: Array<U32>, +x: F32, +sign: U32, +base: U32, +w: U32, +wf: F32) -> Array<U32>:
  +lo = F32.clamp(x, 0.0, wf)
  +ilo = U32.min(F32.to_u32(F32.floor(lo)), (w - 1 : U32))
  cells(True{}, a, (base + ilo : U32), ilo, ilo, lo, lo, 0.25, sign)

def spans(xs: List<&2, F32>, a: Array<U32>, +base: U32, +w: U32, +wf: F32) -> Array<U32>:
  match xs:
    case Con{xa, Con{xb, rest}}:
      spans(rest, mark(mark(a, xa, 1, base, w, wf), xb, 4294967295, base, w, wf), base, w, wf)
    case _: a

def scanned(a: Array<U32>, pending: List<&2, Seg>, sc: List<&2, Seg> & List<&2, F32>, +base: U32, +w: U32, +wf: F32) ->
  Array<U32> & (List<&2, Seg> & List<&2, Seg>):
  (keep, xs) = sc
  (spans(xs, a, base, w, wf), (pending, keep))

def scanline(a: Array<U32>, pa: List<&2, Seg> & List<&2, Seg>, +y: F32, +base: U32, +w: U32, +wf: F32) ->
  Array<U32> & (List<&2, Seg> & List<&2, Seg>):
  (pending, active) = pa
  scanned(a, pending, scan(active, y, Nil{}, Nil{}), base, w, wf)

def scanlines(n: Nat, r: Array<U32> & (List<&2, Seg> & List<&2, Seg>), +k: U32, +stride: U32, +w: U32, +wf: F32) -> Array<U32>:
  match n:
    case 0n:
      (a, ls) = r
      a
    case 1n+p:
      (a, ls) = r
      (+pending, active) = ls
      +y = ((U32.to_f32(k) + 0.5) * 0.25 : F32)
      scanlines(p, scanline(a, admit(pending, starts_by(pending, y), y, active), y, (U32.shrn(k, 2n) * stride : U32), w, wf),
        (k + 1 : U32), stride, w, wf)

def parity(es: List<&2, Edge>, +w: U32, +h: U32, +left: F32, +top: F32) -> List<&2, U32>:
  +stride = (w + 1 : U32)
  a = scanlines(U32.to_nat((h * 4 : U32)), (Array.new(U32, depth((stride * h : U32)), 0),
    (List.sort(~Seg, ~seg_le, segs(es, left, top, Nil{})), Nil{})), 0, stride, w, U32.to_f32(w))
  emit(~nonzero, U32.to_nat(h), (a, Nil{}), ((h - 1) * stride : U32), stride, w)

def coverage(empty: Bool, rule: P.FillRule, es: List<&2, Edge>, +w: U32, +h: U32, +left: F32, +top: F32) -> List<&2, U32>:
  match empty rule:
    case True{} _: Nil{}
    case False{} P.NonZero{}: covered(~nonzero, es, w, h, left, top)
    case False{} P.EvenOdd{}: parity(es, w, h, left, top)

def raster_bounds(rule: P.FillRule, es: List<&2, Edge>, b: Bounds, advance: F32) -> Result<&2, &2, String, Mask>:
  match b:
    case Bounds{l, t, r, b}:
      do Result<&2, &2, String, Mask>:
        +left : F32 = F32.floor(l)
        +top : F32 = F32.floor(t)
        +w : F32 = (F32.ceil(r) - left : F32)
        +h : F32 = (F32.ceil(b) - top : F32)
        ok : Unit <- require(Bool.and(Bool.and(F32.is_ge(w, 0.0), F32.is_le(w, 1024.0)), Bool.and(F32.is_ge(h, 0.0), F32.is_le(h, 1024.0))), "glyph mask exceeds 1024px dimension or is invalid")
        +width : U32 = F32.to_u32(w)
        +height : U32 = F32.to_u32(h)
        ok2 : Unit <- require(U32.is_le((width * height : U32), 262144), "glyph mask exceeds 262144 pixel budget")
        return Mask{width, height, left, top, advance,
          coverage(U32.is_eq((width * height : U32), 0), rule, es, width, height, left, top)}

def edge_bounds(empty: Bool, b: Bounds) -> Bounds:
  match empty:
    case True{}: Bounds{0.0, 0.0, 0.0, 0.0}
    case False{}: b

def finish(rule: P.FillRule, b: Build, advance: F32) -> Result<&2, &2, String, Mask>:
  match b:
    case Broken{m}: Fail{m}
    case Build{es, +n, bd}:
      do Result<&2, &2, String, Mask>:
        edges_ok : Unit <- require(U32.is_le(n, 32768), "path exceeds 32768 flattened edges")
        raster_bounds(rule, es, edge_bounds(U32.is_eq(n, 0), bd), advance)

# Vector entry point: physical pixels, x right and y down.
def rasterize_screen(path: P.Path, +advance: F32) -> Result<&2, &2, String, Mask>:
  match path:
    case P.Path{+ss, rule}:
      do Result<&2, &2, String, Mask>:
        ok : Unit <- require(finite(advance), "invalid advance")
        budget : Unit <- preflight(ss, 0, Fine{Bounds{1000000.0, 1000000.0, F32.neg(1000000.0), F32.neg(1000000.0)}})
        finish(rule, walk(ss, Build{Nil{}, 0, Bounds{1000000.0, 1000000.0, F32.neg(1000000.0), F32.neg(1000000.0)}}, None{}, None{}), advance)

# Glyph entry point: design units, x right/y up; output in physical pixels.
def rasterize(outline: P.Path, +scale: F32, advance: F32) -> Result<&2, &2, String, Mask>:
  do Result<&2, &2, String, Mask>:
    ok : Unit <- require(Bool.and(F32.is_gt(scale, 0.0), F32.is_le(scale, 64.0)), "raster scale must be finite in (0,64]")
    rasterize_screen(P.transform(outline, P.scale(scale, F32.neg(scale))), advance)

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

def segment_bounds(s: P.Segment, b: Bounds) -> Result<&2,&2,String,Bounds>:
  match s:
    case P.MoveTo{+p}:
      do Result<&2,&2,String,Bounds>:
        ok : Unit <- require(point_valid(p), "invalid path coordinate")
        return add_point(b,p)
    case P.Line{+p}:
      do Result<&2,&2,String,Bounds>:
        ok : Unit <- require(point_valid(p), "invalid path coordinate")
        return add_point(b,p)
    case P.Quad{+c,+p}:
      do Result<&2,&2,String,Bounds>:
        ok : Unit <- require(Bool.and(point_valid(c),point_valid(p)), "invalid path coordinate")
        return add_point(add_point(b,c),p)
    case P.Cubic{+c1,+c2,+p}:
      do Result<&2,&2,String,Bounds>:
        ok : Unit <- require(Bool.and(point_valid(c1),Bool.and(point_valid(c2),point_valid(p))), "invalid path coordinate")
        return add_point(add_point(add_point(b,c1),c2),p)
    case P.ClosePath{}:
      Done{b}

def preflight_end(nonempty: Bool, b: Bounds) -> Result<&2,&2,String,Unit>:
  match nonempty b:
    case False{} _: Done{Unit{}}
    case True{} Bounds{l,t,r,b}:
      +w = (F32.ceil(r) - F32.floor(l) : F32)
      +h = (F32.ceil(b) - F32.floor(t) : F32)
      require(Bool.and(Bool.and(F32.is_le(w,1024.0),F32.is_le(h,1024.0)), F32.is_le((w * h : F32),262144.0)), "control bounds exceed raster budget")

def preflight(xs: List<&2,P.Segment>, +count: U32, b: Bounds) -> Result<&2,&2,String,Unit>:
  match xs:
    case Nil{}: preflight_end(U32.is_gt(count,0),b)
    case Con{h,t}:
      do Result<&2,&2,String,Unit>:
        ok : Unit <- require(U32.is_lt(count,4096), "path exceeds 4096 commands")
        next : Bounds <- segment_bounds(h,b)
        preflight(t,(count + 1 : U32),next)

def screen(p: P.Point, +scale: F32) -> P.Point:
  match p:
    case P.Point{x, y}:
      P.Point{(x * scale : F32), F32.neg((y * scale : F32))}

def edge(a: P.Point, b: P.Point) -> Edge:
  match a b:
    case P.Point{ax, ay} P.Point{bx, by}:
      Edge{ax, ay, bx, by}

# For a quadratic, half the control-to-chord-midpoint distance bounds the
# curve's distance from its chord. Subdivision halves parameter intervals.
def flat(a: P.Point, c: P.Point, b: P.Point) -> Bool:
  match a c b:
    case P.Point{ax, ay} P.Point{cx, cy} P.Point{bx, by}:
      F32.is_le(F32.hypot((cx - ((ax + bx) * 0.5) : F32), (cy - ((ay + by) * 0.5) : F32)), 0.25)

def flatten(+depth: Nat, enough: Bool, +a: P.Point, +c: P.Point, +b: P.Point) -> Result<&2, &2, String, List<&2, Edge>>:
  match depth enough:
    case _ True{}:
      Done{[edge(a, b)]}
    case 0n False{}:
      Fail{"quadratic flattening exceeded 12 subdivisions"}
    case 1n+p False{}:
      do Result<&2, &2, String, List<&2, Edge>>:
        +ac : P.Point = P.midpoint(a, c)
        +cb : P.Point = P.midpoint(c, b)
        +mid : P.Point = P.midpoint(ac, cb)
        left : List<&2, Edge> <- flatten(p, flat(a, ac, mid), a, ac, mid)
        right : List<&2, Edge> <- flatten(p, flat(mid, cb, b), mid, cb, b)
        return List.append(&2, Edge, left, right)

type PathStep is Data:
  PathStep{edges: List<&2, Edge>, first: Maybe<&2, P.Point>, current: Maybe<&2, P.Point>}

def distance(a: P.Point, b: P.Point) -> F32:
  match a b:
    case P.Point{ax,ay} P.Point{bx,by}: F32.hypot((ax - bx : F32),(ay - by : F32))

def cubic_flat(+a: P.Point, b: P.Point, c: P.Point, +d: P.Point) -> Bool:
  Bool.and(F32.is_le(distance(b,P.lerp(a,d,0.333333333)),0.16666666),
    F32.is_le(distance(c,P.lerp(a,d,0.666666667)),0.16666666))

def flatten_cubic(+depth: Nat, enough: Bool, +a: P.Point, +b: P.Point, +c: P.Point, +d: P.Point) -> Result<&2, &2, String, List<&2, Edge>>:
  match depth enough:
    case _ True{}:
      Done{[edge(a, d)]}
    case 0n False{}:
      Fail{"cubic flattening exceeded 12 subdivisions"}
    case 1n+p False{}:
      do Result<&2, &2, String, List<&2, Edge>>:
        +ab : P.Point = P.midpoint(a, b)
        +bc : P.Point = P.midpoint(b, c)
        +cd : P.Point = P.midpoint(c, d)
        +abc : P.Point = P.midpoint(ab, bc)
        +bcd : P.Point = P.midpoint(bc, cd)
        +mid : P.Point = P.midpoint(abc, bcd)
        left : List<&2, Edge> <- flatten_cubic(p, cubic_flat(a, ab, abc, mid), a, ab, abc, mid)
        right : List<&2, Edge> <- flatten_cubic(p, cubic_flat(mid, bcd, cd, d), mid, bcd, cd, d)
        return List.append(&2, Edge, left, right)

def path_step(s: P.Segment, first: Maybe<&2, P.Point>, current: Maybe<&2, P.Point>) -> Result<&2, &2, String, PathStep>:
  match s first current:
    case P.MoveTo{+to} None{} None{}:
      do Result<&2, &2, String, PathStep>:
        ok : Unit <- require(point_valid(to), "invalid move point")
        return PathStep{Nil{}, Some{to}, Some{to}}
    case P.Line{+to} Some{start} Some{from}:
      do Result<&2, &2, String, PathStep>:
        ok : Unit <- require(point_valid(to), "invalid line point")
        return PathStep{[edge(from, to)], Some{start}, Some{to}}
    case P.Quad{+control, +to} Some{start} Some{+from}:
      do Result<&2, &2, String, PathStep>:
        ok : Unit <- require(Bool.and(point_valid(control), point_valid(to)), "invalid quadratic point")
        es : List<&2, Edge> <- flatten(12n, flat(from, control, to), from, control, to)
        return PathStep{es, Some{start}, Some{to}}
    case P.Cubic{+b, +c, +to} Some{start} Some{+from}:
      do Result<&2, &2, String, PathStep>:
        ok : Unit <- require(Bool.and(point_valid(b), Bool.and(point_valid(c), point_valid(to))), "invalid cubic point")
        es : List<&2, Edge> <- flatten_cubic(12n, cubic_flat(from, b, c, to), from, b, c, to)
        return PathStep{es, Some{start}, Some{to}}
    case P.ClosePath{} Some{start} Some{from}:
      Done{PathStep{[edge(from, start)], None{}, None{}}}
    case _ _ _:
      Fail{"invalid path: every subpath requires MoveTo and explicit ClosePath"}

def step_edges(s: PathStep) -> List<&2, Edge>:
  match s:
    case PathStep{es, first, current}: es

def step_first(s: PathStep) -> Maybe<&2, P.Point>:
  match s:
    case PathStep{es, first, current}: first

def step_current(s: PathStep) -> Maybe<&2, P.Point>:
  match s:
    case PathStep{es, first, current}: current

def path_end(first: Maybe<&2, P.Point>) -> Result<&2, &2, String, List<&2, Edge>>:
  match first:
    case None{}: Done{Nil{}}
    case Some{p}: Fail{"unclosed subpath"}

def all_edges(xs: List<&2, P.Segment>, first: Maybe<&2, P.Point>, current: Maybe<&2, P.Point>) -> Result<&2, &2, String, List<&2, Edge>>:
  match xs:
    case Nil{}:
      path_end(first)
    case Con{h, t}:
      do Result<&2, &2, String, List<&2, Edge>>:
        +s : PathStep <- path_step(h, first, current)
        tail : List<&2, Edge> <- all_edges(t, step_first(s), step_current(s))
        return List.append(&2, Edge, step_edges(s), tail)

def include(b: Bounds, e: Edge) -> Bounds:
  match b e:
    case Bounds{l, t, r, b} Edge{+x0, +y0, +x1, +y1}:
      Bounds{F32.min(l, F32.min(x0, x1)), F32.min(t, F32.min(y0, y1)),
        F32.max(r, F32.max(x0, x1)), F32.max(b, F32.max(y0, y1))}

def bounds_go(es: List<&2, Edge>, b: Bounds) -> Bounds:
  match es:
    case Nil{}: b
    case Con{h, t}: bounds_go(t, include(b, h))

def bounds(es: List<&2, Edge>) -> Bounds:
  match es:
    case Nil{}: Bounds{0.0, 0.0, 0.0, 0.0}
    case Con{+e, t}:
      bounds_go(t, include(Bounds{1000000.0, 1000000.0, F32.neg(1000000.0), F32.neg(1000000.0)}, e))

type Cross is Data:
  Cross{x: F32, direction: F32}

def add_cross(hit: Bool, e: Edge, y: F32, rest: List<&2, Cross>) -> List<&2, Cross>:
  match hit e:
    case False{} _: rest
    case True{} Edge{+x0, +y0, x1, +y1}:
      Con{Cross{(x0 + ((y - y0) * (x1 - x0) / (y1 - y0)) : F32),
        Bool.pick(F32, F32.is_lt(y0, y1), 1.0, F32.neg(1.0))}, rest}

def crossings(es: List<&2, Edge>, +y: F32) -> List<&2, Cross>:
  match es:
    case Nil{}: Nil{}
    case Con{Edge{+x0, +y0, +x1, +y1}, tail}:
      add_cross(Bool.or(Bool.and(F32.is_le(y0, y), F32.is_lt(y, y1)),
        Bool.and(F32.is_le(y1, y), F32.is_lt(y, y0))), Edge{x0, y0, x1, y1}, y, crossings(tail, y))

def cross_le(a: Cross, b: Cross) -> Bool:
  match a b:
    case Cross{x, da} Cross{y, db}: F32.is_le(x, y)

type Sweep is Data:
  Sweep{crosses: List<&2, Cross>, winding: F32}

def before(cs: List<&2,Cross>, x: F32) -> Bool:
  match cs:
    case Nil{}: False{}
    case Con{Cross{cx,dir},tail}: F32.is_le(cx,x)

def sweep(cs: List<&2, Cross>, +x: F32, winding: F32, active: Bool) -> Sweep:
  match cs active:
    case _ False{}: Sweep{cs,winding}
    case Nil{} True{}: Sweep{Nil{},winding}
    case Con{Cross{cx,dir},+tail} True{}:
      sweep(tail,x,(winding + dir : F32),before(tail,x))

def sweep_crosses(s: Sweep) -> List<&2, Cross>:
  match s:
    case Sweep{cs, winding}: cs

def sweep_winding(s: Sweep) -> F32:
  match s:
    case Sweep{cs, winding}: winding

def inside(rule: P.FillRule, winding: F32) -> Bool:
  match rule:
    case P.NonZero{}: F32.is_ne(winding, 0.0)
    case P.EvenOdd{}: F32.is_ne(F32.mod(F32.abs(winding), 2.0), 0.0)

def samples(n: Nat, +rule: P.FillRule, +cs: List<&2, Cross>, winding: F32, +x: F32, acc: List<&2, U32>) -> List<&2, U32>:
  match n:
    case 0n: List.reverse(&2, U32, acc)
    case 1n+p:
      +s = sweep(cs, x, winding, before(cs,x))
      samples(p, rule, sweep_crosses(s), sweep_winding(s), (x + 0.25 : F32),
        Con{Bool.to_u32(inside(rule, sweep_winding(s))), acc})

def sample_row(rule: P.FillRule, +es: List<&2, Edge>, width: U32, left: F32, y: F32) -> List<&2, U32>:
  samples(U32.to_nat((width * 4 : U32)), rule, List.sort(~Cross, ~cross_le, crossings(es, y)), 0.0, (left + 0.125 : F32), Nil{})

def sum_rows(a: List<&2, U32>, b: List<&2, U32>, c: List<&2, U32>, d: List<&2, U32>) -> List<&2, U32>:
  match a b c d:
    case Con{x, xs} Con{y, ys} Con{z, zs} Con{w, ws}:
      Con{(x + y + z + w : U32), sum_rows(xs, ys, zs, ws)}
    case _ _ _ _: Nil{}

def pixels(xs: List<&2, U32>) -> List<&2, U32>:
  match xs:
    case Con{a, Con{b, Con{c, Con{d, rest}}}}:
      Con{((((a + b + c + d) * 255) + 8) / 16 : U32), pixels(rest)}
    case _: Nil{}

def raster_rows(n: Nat, +rule: P.FillRule, +es: List<&2, Edge>, +width: U32, +left: F32, +y: F32) -> List<&2, U32>:
  match n:
    case 0n: Nil{}
    case 1n+p:
      row = pixels(sum_rows(sample_row(rule, es, width, left, (y + 0.125 : F32)),
        sample_row(rule, es, width, left, (y + 0.375 : F32)), sample_row(rule, es, width, left, (y + 0.625 : F32)),
        sample_row(rule, es, width, left, (y + 0.875 : F32))))
      List.append(&2, U32, row, raster_rows(p, rule, es, width, left, (y + 1.0 : F32)))

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
        return Mask{width, height, left, top, advance, raster_rows(U32.to_nat(height), rule, es, width, left, top)}

def edge_count(es: List<&2,Edge>, n: U32) -> U32:
  match es:
    case Nil{}: n
    case Con{h,t}: edge_count(t,(n + 1 : U32))

# Vector entry point: physical pixels, x right and y down.
def rasterize_screen(path: P.Path, +advance: F32) -> Result<&2, &2, String, Mask>:
  match path:
    case P.Path{+ss, rule}:
      do Result<&2, &2, String, Mask>:
        ok : Unit <- require(finite(advance), "invalid advance")
        budget : Unit <- preflight(ss,0,Bounds{1000000.0,1000000.0,F32.neg(1000000.0),F32.neg(1000000.0)})
        +es : List<&2, Edge> <- all_edges(ss, None{}, None{})
        edges_ok : Unit <- require(U32.is_le(edge_count(es,0),32768), "path exceeds 32768 flattened edges")
        raster_bounds(rule, es, bounds(es), advance)

# Glyph entry point: design units, x right/y up; output in physical pixels.
def rasterize(outline: P.Path, +scale: F32, advance: F32) -> Result<&2, &2, String, Mask>:
  do Result<&2, &2, String, Mask>:
    ok : Unit <- require(Bool.and(F32.is_gt(scale, 0.0), F32.is_le(scale, 64.0)), "raster scale must be finite in (0,64]")
    rasterize_screen(P.transform(outline, P.scale(scale, F32.neg(scale))), advance)

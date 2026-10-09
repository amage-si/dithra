import Base
import ../../Runika/font.bend as F
import ../../Runika/glyf.bend as G
import ../../Syllo/main.bend as S
import ../../Splina/path.bend as P
import ../raster.bend as R

# Rasterization timing: the printable ASCII glyphs (U+0021..U+007E) of
# Liberation Sans, outlines parsed once up front, then `R.rasterize` repeated
# over the whole set. Each line reports one timed batch; the checksum (sum of
# coverage plus mask sizes) is printed before the clock is read again so the
# work cannot move past the second `IO.now()`. IO.now has 1 ms resolution, so
# batches should take a few hundred ms.
#
#   ./build/bench [reps16] [reps64] [batches]
#
# Glyph outlines are non-zero paths; the even-odd line rasterizes the same
# outlines under EvenOdd (reps64 repetitions) to time that path.

def keep(r: Result<&2, &2, String, P.Path>, acc: List<&2, P.Path>) -> List<&2, P.Path>:
  match r:
    case Fail{e}: acc
    case Done{p}: Con{p, acc}

def outline_of(+font: F.Font, r: Result<&2, &2, String, U32>, acc: List<&2, P.Path>) -> List<&2, P.Path>:
  match r:
    case Fail{e}: acc
    case Done{gid}: keep(G.outline(font, gid), acc)

def outlines(n: Nat, +font: F.Font, +code: U32, acc: List<&2, P.Path>) -> List<&2, P.Path>:
  match n:
    case 0n: acc
    case 1n+p: outlines(p, font, (code + 1 : U32), outline_of(font, F.glyph_id(font, code), acc))

def parity(ps: List<&2, P.Path>) -> List<&2, P.Path>:
  match ps:
    case Nil{}: Nil{}
    case Con{P.Path{ss, rule}, t}: Con{P.Path{ss, P.EvenOdd{}}, parity(t)}

def sum(cs: List<&2, U32>, acc: U32) -> U32:
  match cs:
    case Nil{}: acc
    case Con{c, t}: sum(t, (acc + c : U32))

def mask_sum(r: Result<&2, &2, String, R.Mask>) -> U32:
  match r:
    case Fail{e}: 1000000000
    case Done{R.Mask{w, h, l, t, a, cs}}: sum(cs, (w + h : U32))

def pass(ps: List<&2, P.Path>, +scale: F32, acc: U32) -> U32:
  match ps:
    case Nil{}: acc
    case Con{p, t}: pass(t, scale, (acc + mask_sum(R.rasterize(p, scale, 0.0)) : U32))

def passes(n: Nat, +ps: List<&2, P.Path>, +scale: F32, acc: U32) -> U32:
  match n:
    case 0n: acc
    case 1n+p: passes(p, ps, scale, (acc + pass(ps, scale, 0) : U32))

def numbers(xs: List<&1, String>) -> List<&2, U32>:
  match xs:
    case Nil{}: Nil{}
    case Con{h, t}: Con{Maybe.default(&2, U32, U32.read(h), 0), numbers(t)}

def arg(xs: List<&2, U32>, n: Nat, +fallback: U32) -> U32:
  match xs n:
    case Nil{} _: fallback
    case Con{h, t} 0n: U32.max(h, 1)
    case Con{h, t} 1n+p: arg(t, p, fallback)

def measure(label: String, +ps: List<&2, P.Path>, +scale: F32, +reps: U32, +count: U32) -> IO(Unit):
  do IO<Unit>:
    +t0 : Nat <- IO.now()
    # Tie the work to t0 so it cannot be evaluated before the first clock read.
    +check : U32 = passes(Nat.add(U32.to_nat(reps), Nat.sub(t0, t0)), ps, scale, 0)
    IO.print("  checksum " ++ U32.show(check))
    +t1 : Nat <- IO.now()
    +ms : U32 = U32.from_nat(Nat.sub(t1, t0))
    IO.print(label ++ " glyphs=" ++ U32.show(count) ++ " reps=" ++ U32.show(reps) ++ " ms=" ++ U32.show(ms) ++
      " ns/glyph=" ++ U32.show(((ms * 1000000) / (reps * count) : U32)))

def batches(n: Nat, +ps: List<&2, P.Path>, +eo: List<&2, P.Path>, +s16: F32, +s64: F32, +r16: U32, +r64: U32, +count: U32) -> IO(Unit):
  match n:
    case 0n: IO.pure(Unit, Unit{})
    case 1n+p:
      do IO<Unit>:
        measure("16px non-zero", ps, s16, r16, count)
        measure("64px non-zero", ps, s64, r64, count)
        measure("16px even-odd", eo, s16, r64, count)
        batches(p, ps, eo, s16, s64, r16, r64, count)

def font_unwrap(r: Result<&2, &2, String, F.Font>) -> IO(F.Font):
  match r:
    case Fail{e}: IO.die(F.Font, 1, e)
    case Done{x}: IO.pure(F.Font, x)

def main() -> IO(Unit):
  do IO<Unit>:
    argv : List<&1, String> <- IO.args()
    +args : List<&2, U32> = numbers(argv)
    fr : Result<&2, &2, String, F.Font> <- F.load("/usr/share/fonts/liberation/LiberationSans-Regular.ttf")
    +font : F.Font <- font_unwrap(fr)
    +ps : List<&2, P.Path> = outlines(94n, font, 33, Nil{})
    +count : U32 = U32.from_nat(List.length(&2, P.Path, ps))
    IO.print("outlines " ++ U32.show(count))
    +units : F32 = S.units(font)
    batches(U32.to_nat(arg(args, 3n, 5)), ps, parity(ps), (16.0 / units : F32), (64.0 / units : F32),
      arg(args, 1n, 40), arg(args, 2n, 4), count)

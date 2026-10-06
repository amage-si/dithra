import Base
import ../main.bend as D
import ../raster.bend as R

# A grayscale evidence surface, not the product compositor (Chromi owns it).
type Surface is Type:
  Surface{width: U32, height: U32, pixels: Array<U32>}

def new(+w: U32, +h: U32) -> Surface:
  Surface{w, h, Array.new(U32, 1n+U32.log2((w * h : U32)), 255)}

def blend_result(r: Array<U32> & U32, i: U32, coverage: U32) -> Array<U32>:
  (a, old) = r
  Array.set(U32, a, i, (((old * (255 - coverage)) + 127) / 255 : U32))

def plot(valid: Bool, pixels: Array<U32>, width: U32, x: F32, y: F32, cov: U32) -> Array<U32>:
  match valid:
    case False{}: pixels
    case True{}:
      +i = ((F32.to_u32(y) * width) + F32.to_u32(x) : U32)
      blend_result(Array.get(U32, pixels, i), i, cov)

def blit_bytes(cs: List<&2, U32>, pixels: Array<U32>, +w: U32, +h: U32, +mw: U32, +ox: F32, +oy: F32, +i: U32) -> Array<U32>:
  match cs:
    case Nil{}: pixels
    case Con{c, tail}:
      +x = (ox + U32.to_f32(U32.mod(i, mw)) : F32)
      +y = (oy + U32.to_f32((i / mw : U32)) : F32)
      next = plot(Bool.and(Bool.and(F32.is_ge(x, 0.0), F32.is_lt(x, U32.to_f32(w))),
        Bool.and(F32.is_ge(y, 0.0), F32.is_lt(y, U32.to_f32(h)))), pixels, w, x, y, c)
      blit_bytes(tail, next, w, h, mw, ox, oy, (i + 1 : U32))

def blit(surface: Surface, pm: D.PositionedMask, ox: F32, oy: F32) -> Surface:
  match surface pm:
    case Surface{+w, +h, pixels} D.PositionedMask{x, y, start, end, R.Mask{mw, mh, l, t, adv, cs}}:
      Surface{w, h, blit_bytes(cs, pixels, w, h, mw, (x + ox : F32), (y + oy : F32), 0)}

def draw(masks: List<&2, D.PositionedMask>, surface: Surface, +x: F32, +y: F32) -> Surface:
  match masks:
    case Nil{}: surface
    case Con{m, rest}: draw(rest, blit(surface, m, x, y), x, y)

def close_write(r: File & Result<&1, &1, U32 & String, Unit>) -> IO(Unit):
  (f, result) = r
  do IO<Unit>:
    File.close(f)
    IO.try(Unit, IO.pure(Result<&1, &1, U32 & String, Unit>, result))

def write_pixels(r: File & Result<&1, &1, U32 & String, Unit>, pixels: List<&2, U32>) -> IO(Unit):
  (f, result) = r
  do IO<Unit>:
    ok : Unit <- IO.try(Unit, IO.pure(Result<&1, &1, U32 & String, Unit>, result))
    written : File & Result<&1, &1, U32 & String, Unit> <- File.write_bytes(f, pixels)
    close_write(written)

def take_bytes(n: Nat, xs: List<U32>, acc: List<&2, U32>) -> List<&2, U32>:
  match n xs:
    case 0n _: List.reverse(&2, U32, acc)
    case _ Nil{}: List.reverse(&2, U32, acc)
    case 1n+p Con{h, t}: take_bytes(p, t, Con{h, acc})

def pgm(surface: Surface, path: String) -> IO(Unit):
  match surface:
    case Surface{+w, +h, pixels}:
      do IO<Unit>:
        f : File <- IO.try(File, File.open(path, "w"))
        head : File & Result<&1, &1, U32 & String, Unit> <- File.write(f, "P5\n" ++ U32.show(w) ++ " " ++ U32.show(h) ++ "\n255\n")
        write_pixels(head, take_bytes(U32.to_nat((w * h : U32)), Array.to_list(~U32, pixels), Nil{}))

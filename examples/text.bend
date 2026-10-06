import Base
import ../../Runika/font.bend as F
import ../../Syllo/main.bend as S
import ../main.bend as D
import ./export.bend as E

def unwrap(-A: Type, r: Result<&2, &1, String, A>) -> IO(A):
  match r:
    case Fail{e}: IO.die(A, 1, e)
    case Done{x}: IO.pure(A, x)

def font_unwrap(r: Result<&2, &2, String, F.Font>) -> IO(F.Font):
  match r:
    case Fail{e}: IO.die(F.Font, 1, e)
    case Done{x}: IO.pure(F.Font, x)

def layout_unwrap(r: Result<&2, &2, String, S.Layout>) -> IO(S.Layout):
  match r:
    case Fail{e}: IO.die(S.Layout, 1, e)
    case Done{x}: IO.pure(S.Layout, x)

def masks_unwrap(r: Result<&2, &2, String, List<&2, D.PositionedMask>>) -> IO(List<&2, D.PositionedMask>):
  match r:
    case Fail{e}: IO.die(List<&2, D.PositionedMask>, 1, e)
    case Done{x}: IO.pure(List<&2, D.PositionedMask>, x)

def metrics(l: S.Layout) -> String:
  match l:
    case S.Layout{ps, width, height, asc, desc, lh, lines}:
      "width=" ++ F32.show(width) ++ " height=" ++ F32.show(height) ++ " lines=" ++ U32.show(lines)

def line(+font: F.Font, surface: E.Surface, text: String, +size: F32, width: F32, x: F32, y: F32) -> IO(E.Surface):
  do IO<E.Surface>:
    +l : S.Layout <- layout_unwrap(S.layout(font, text, size, width))
    masks : List<&2, D.PositionedMask> <- masks_unwrap(D.render(font, l, size, 1.0))
    IO.print(metrics(l))
    return E.draw(masks, surface, x, y)

def main() -> IO(Unit):
  do IO<Unit>:
    start : Nat <- IO.now()
    fr : Result<&2, &2, String, F.Font> <- F.load("/usr/share/fonts/liberation/LiberationSans-Regular.ttf")
    +font : F.Font <- font_unwrap(fr)
    a : E.Surface <- line(font, E.new(980, 560), "AMAGE Eco · Texto em Bend 2", 40.0, 920.0, 28.0, 20.0)
    b : E.Surface <- line(font, a, "São João, ação, coração, café e açúcar.", 30.0, 920.0, 28.0, 85.0)
    c : E.Surface <- line(font, b, "À Á Â Ã Ç É Ê Í Ó Ô Õ Ú Ü   à á â ã ç é ê í ó ô õ ú ü", 26.0, 920.0, 28.0, 140.0)
    d : E.Surface <- line(font, c, "Precomposto: ação, coração, café", 26.0, 920.0, 28.0, 195.0)
    e : E.Surface <- line(font, d, "Combinante: ação, coração, café", 26.0, 920.0, 28.0, 235.0)
    f : E.Surface <- line(font, e, "Quebra de linha em português: texto real com acentos e medidas da fonte instalada.", 22.0, 430.0, 28.0, 305.0)
    g : E.Surface <- line(font, f, "12 px · ação, café, açúcar", 12.0, 410.0, 525.0, 315.0)
    h : E.Surface <- line(font, g, "18 px · ação, café, açúcar", 18.0, 410.0, 525.0, 345.0)
    i : E.Surface <- line(font, h, "32 px · São João", 32.0, 410.0, 525.0, 385.0)
    j : E.Surface <- line(font, i, "48 px · coração", 48.0, 850.0, 28.0, 455.0)
    E.pgm(j, "build/text.pgm")
    end : Nat <- IO.now()
    IO.print("Bend load + shape + raster + export ms=" ++ Nat.show(Nat.sub(end, start)))

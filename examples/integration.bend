import Base
import ../../Runika/font.bend as F
import ../../Runika/check.bend as Check
import ../../Syllo/main.bend as S
import ../../Tessra/main.bend as T
import ../../Tessra/geometry.bend as TG
import ../../Chromi/main.bend as C
import ../../Chromi/tree.bend as Tree
import ../main.bend as D
import ../raster.bend as R
import ./export.bend as E

def preferred(l: S.Layout) -> TG.Size:
  match l:
    case S.Layout{ps,w,h,asc,desc,lh,lines}: TG.Size{w,h}

def text_rect(layout: Result<&2,&2,T.Error,T.Layout>) -> IO(TG.Rect):
  match layout:
    case Done{T.Layout{content,Con{T.Placement{id,r},Nil{}},False{}}}:
      IO.pure(TG.Rect,r)
    case _:
      IO.die(TG.Rect,1,"Tessra integration failed or overflowed")

# PositionedMask coordinates are physical. Chromi receives logical origins;
# at device scale 1 these coincide. Its blit applies coverage to the ink alpha.
def draw_one(canvas: C.Canvas, m: D.PositionedMask, ox: F32, oy: F32) -> C.Canvas:
  match m:
    case D.PositionedMask{x,y,start,end,R.Mask{w,h,left,top,advance,coverage}}:
      C.blit_mask(canvas,(ox + x : F32),(oy + y : F32),w,h,coverage,255)

def draw(ms: List<&2,D.PositionedMask>, canvas: C.Canvas, +x: F32, +y: F32) -> C.Canvas:
  match ms:
    case Nil{}: canvas
    case Con{h,t}: draw(t,draw_one(canvas,h,x,y),x,y)

def draw_at(rect: TG.Rect, masks: List<&2,D.PositionedMask>) -> Result<&1,&1,U32 & String,Image>:
  match rect:
    case TG.Rect{x,y,w,h}:
      C.finish(draw(masks,C.new(640,160,1.0,4294967295),x,y))

def frame() -> IO(Image):
  do IO<Image>:
    fr : Result<&2,&2,String,F.Font> <- F.load("/usr/share/fonts/liberation/LiberationSans-Regular.ttf")
    +font : F.Font <- Check.unwrap(F.Font,fr)
    +layout : S.Layout <- Check.unwrap(S.Layout,S.layout(font,"São João: ação, café, açúcar.",28.0,592.0))
    rect : TG.Rect <- text_rect(T.layout(TG.Rect{0.0,0.0,640.0,160.0},
      T.Config{T.Column{},TG.Insets{24.0,24.0,24.0,24.0},0.0,T.Middle{},T.Start{}},
      [T.Child{1,preferred(layout),T.unconstrained()}]))
    masks : List<&2,D.PositionedMask> <- Check.unwrap(List<&2,D.PositionedMask>,D.render(font,layout,28.0,1.0))
    IO.try(Image,IO.pure(Result<&1,&1,U32 & String,Image>,draw_at(rect,masks)))

def image_bytes(n: Nat, +img: Image, +i: U32, acc: List<&2,U32>) -> List<&2,U32>:
  match n:
    case 0n: List.reverse(&2,U32,acc)
    case 1n+p:
      +x = U32.mod(i,640)
      +y = (i / 640 : U32)
      rgb = Tree.sample(img,1024,x,y,U32.is_lt(x,512),U32.is_lt(y,512))
      image_bytes(p,img,(i + 1 : U32),Con{U32.and(rgb,255),acc})

def export_image(img: Image) -> IO(Unit):
  do IO<Unit>:
    f : File <- IO.try(File,File.open("build/integration.pgm","w"))
    header : File & Result<&1,&1,U32 & String,Unit> <- File.write(f,"P5\n640 160\n255\n")
    E.write_pixels(header,image_bytes(102400n,img,0,Nil{}))

def main() -> IO(Unit):
  do IO<Unit>:
    img : Image <- frame()
    export_image(img)
    IO.print("PASS Syllo measures -> Tessra placement -> Dithra masks -> Chromi blit -> Bend PGM export")

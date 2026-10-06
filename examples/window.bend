import Base
import ../../Ankra/main.bend as A
import ./integration.bend as I

def tick(batch: A.Batch, state: Unit) -> IO(A.Step<Unit>):
  IO.pure(A.Step<Unit>,A.Keep{state})

def main() -> IO(Unit):
  do IO<Unit>:
    +img : Image <- I.frame()
    I.export_image(img)
    A.run(~Unit,~tick,"AMAGE Eco · Texto em Bend 2",640,160,180n,Unit{},img)

import Base
import ../Runika/tests.bend as RunikaTests
import ../Syllo/tests.bend as SylloTests
import ./tests.bend as DithraTests

def main() -> IO(Unit):
  do IO<Unit>:
    RunikaTests.main()
    SylloTests.main()
    DithraTests.main()

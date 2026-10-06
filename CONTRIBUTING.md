# Contributing to Dithra

Use Bend 2.0.35 for the current baseline. Read `bend guide` before editing Bend
and keep project text in English. Library implementation belongs in Bend; the
official runtime and operating system remain external dependencies.

Clone the sibling repositories next to Dithra as listed in the README (at least
`Splina`, `Runika`, and `Syllo`; `Tessra`, `Chromi`, and `Ankra` for the
integration and window examples), and install Liberation Sans 2.1.5 at
`/usr/share/fonts/liberation/LiberationSans-Regular.ttf`.

## Validation

From the repository root:

```sh
export BEND_NO_TELEMETRY=1
mkdir -p build
bend tests.bend -o build/tests
./build/tests --threads 2 --gpu off
bend all_tests.bend -o build/all-tests
./build/all-tests --threads 2 --gpu off
bend examples/text.bend -o build/text
./build/text --threads 2 --gpu off
bend examples/integration.bend -o build/integration
./build/integration --threads 2 --gpu off
bend examples/window.bend -o build/window
```

When a change affects coverage, open `build/text.pgm` and
`build/integration.pgm` in an image viewer and compare them with the previous
output at small and large sizes. To check the window, run `build/window` in an
X11/XWayland session; it closes itself after 180 frames. A successful build or
passing checks alone do not validate the rendering.

Build one target at a time. The native Bend runtime reserves substantial virtual
address space; a virtual-memory limit is not a resident-memory limit. Preserve
crash evidence and investigate before repeating a failed compiler invocation.

## Changes

Keep the API small and coordinate systems explicit. Add a focused regression
check when behavior changes (an analytic coverage value is better than a
snapshot), update affected contracts, and report what was actually validated.
Performance claims need repeated measurements on the same input.

Use English commit messages that explain the result. Do not commit `build/`,
generated C, images produced by validation runs, logs, crash dumps, credentials,
or machine-specific paths. Do not publish BendHub packages or create releases
as a side effect of validation.

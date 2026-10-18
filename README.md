# zxpaging: A lightweight 8KB MMU virtual memory, dynamic page-swapping, and inter-page vector framework for Boriel BASIC on the ZX Spectrum Next.

*Thank you to the creators of the ZX Spectrum Next, of Boriel BASIC, of sjasmplus and of ZEsarUX, without whom none
of this would have been possible. My deepest thank yous, and appreciation and respect, always.*

A small working example for the ZX Spectrum Next, written in Boriel ZX BASIC with embedded Z80. It shows one way for a
program to take all 64KB of the Z80's address space for itself, in eight 8KB pages, and to page its own code and data
in and out while it runs. Saving and reloading are part of it too.

It does nothing else. There are no graphics, scrolling or sound, as plenty of others cover those well. This is just
the paging, the swapping and the shims, kept as simple as it can be so it can be read and reused.

**Just want to try it?** Download `zxpaging.nex` from the
[latest release](https://github.com/sdo101/zxpaging/releases/latest) and run it on your Next (copy it to the SD card
and choose it in the Browser) or in ZEsarUX (as a Next, with Smart Load). No tools needed. The keys are under
"The keys" below.

## What it shows

**All eight MMU slots are ours.** No ROM, and no system variables:

| MMU slot | Address | What is in it |
|---|---|---|
| 0 | `$0000` | paged data: the left, centre and right stages' own pages take turns here |
| 1, 2 | `$2000`, `$4000` | paged data, tested by the start up stage |
| 3 | `$6000` | paged code: one stage at a time, or a library while a stage calls it |
| 4, 5 | `$8000` | the core's code, the jump table at `$8010`, the IM2 handler and its table |
| 6 | `$C000` | the core's data, never paged out, with the heap at the top |
| 7 | `$E000` | the screen (tilemap, 80 x 32) and the stack |

**Core and stages.** The core is always present. It picks a stage, pages the stage's code into MMU 3 and calls
`$6000`. When the stage returns, the core picks the next one. A stage never calls another stage.

**A library.** Code that any stage may call, on a page of its own, with 512 bytes of storage that belong to it alone.
See "Libraries" below.

**Shims.** A stage calls the core through a jump table at `$8010`, using small shims in `stage-include.bas`. So the core
can change and be rebuilt without the stages having to know where anything in it has moved to.

**Core data and paged data.** The core's data page sits in MMU 6 and never moves. Each of the left, centre and right
stages has its own page of data, and pages it into MMU 0 when it starts. If the page is already there it is not
swapped, and the core counts a hit instead. Press a stage's own letter again and you see the hit count go up, along
with the counter kept inside that page.

**Saving and reloading, in one file.** `S` saves the core's data and all three data pages to one file, `zxpaging.sav`,
on the SD card (in the fast start, zf, in the project folder on the PC, see below). `O` loads it back. Loading is all or nothing: the file is read into spare pages first and checked. Only
then is it copied over the live data, so a bad or foreign file changes nothing.

**A monitor.** It shows, for MMU 0 to 3, which page is in each slot and the hits and swaps, how much of the heap and the
stack has ever been used, and the CPU speed. The core brings it up to date each time a stage hands back. The `M` key
turns it on and off, in any stage.

**Other details:**

- the start up stage tests the three data slots, and saving and loading a page through the SD card
- interrupts use mode 2 with a handler of our own, so nothing needs to be at `$0038`
- the CPU runs at 28MHz throughout, and the monitor shows that it stays there after file access
- the build stops if a stage or the core uses anything that needs the ROM or the system variables, see below

## Strings: yes, in every module, through one shared heap

Strings work everywhere here, in the core and in every paged stage, and they pass freely between them.

The trick is simple: **every module is told where the heap begins and how big it is, and every one is told the same.**
Each module (the core, and each stage) is a separate compile, and each would otherwise put its own heap wherever
it liked. `build.ps1` gives them all the same `--heap-address` and `--heap-size`. So there is one Boriel heap, the
last 1024 bytes of the core data page (`$DC00` to `$DFFF`, in MMU 6, which is never paged out), and every module uses
that same one:

- a stage builds a string, e.g. `"page " + fs_core_number( n )`, and hands it to a core routine such as
  `s_core_print_string_at`, and the core frees it when it has finished with it
- a core function such as `fs_core_number` builds its result in the heap, and the stage frees it once it has used it
- `+`, `Len`, `Code` and slicing all work as usual

Three things to keep in mind:

- **only the core prepares the heap**, once, at start up. A stage must never do it again, or it would lose every string
  in use (see the top of `core.bas` and the heap notes in `build.ps1`)
- **it is 1024 bytes**, shared by everyone, so use strings judiciously. The monitor's heap line shows the biggest free
  block (`b`), the bytes in use now (`s`), free now (`f`) and the most ever used (`m`)
- **a String variable is only a pointer into the heap.** Keep data that is saved, or that lives in a paged data page,
  as plain bytes, not as String variables

## Libraries: code any stage can call, with 512 bytes of its own

Sooner or later a program on the Next outgrows this layout, probably before you expect it to. A stage is one page of
code, 8KB, and everything it does has to fit in it. Code that two stages both need cannot live in either of them: a
stage cannot call into another stage, because both would have to be at `$6000` at once. And the core's two pages fill
up soon enough. **Anything decently sized needs a way to have more pages of code than the stages themselves.**

A **library** is that way. It is a page of code built exactly like a stage, starting at `$6000`, but the core does not
run it in turn. A stage calls one of its routines when it wants it:

```basic
gub_lib_param_1 = pub_letter
s_core_call_library( UB_PAGED_CODE_LIB_DEMO , UB_LIB_DEMO_COUNT )
```

`s_core_call_library` is in the core, which is why it can do this: it notes which page is in MMU 3 (the stage that
called), puts the library's page there, calls `$6000` with the routine wanted in `gub_lib_function`, and then puts the
caller's page back. The stage carries on where it was, as if nothing had happened. The page to go back to is kept on the
stack, not in a fixed place, so **a library may call another library** in just the same way.

**Its own 512 bytes.** The last 512 bytes of a library's page, `$7E00` to `$7FFF` while it runs (`A_LIB_PRIVATE`), are its
working storage:

- **they belong to that library alone.** No other page can see them, and no stage has to give up any of the core's
  data for them
- **they are in view exactly when the library is**, so using them costs no page swap
- **they keep what is left in them from one call to the next**, the page being RAM like any other. In the demo the
  library counts how often each stage calls it, in its own 512 bytes, and the counts go up and up although nothing
  outside the library holds them
- **so a library's code must stop short of them.** `build.ps1` checks that a library's `.bin` is no more than 7680
  bytes (a stage may have all 8192), and stops the build if it is

Three things to keep in mind:

- **anything handed back to the caller goes in the core data** (here `guw_lib_result`), because the library's page, and
  its 512 bytes with it, go out of view the moment the call returns
- **they start out as noughts** (the rest of the page in the nex file), and they are not in a save, which keeps the
  core data and the data pages only. A library that must keep something across a save keeps it in the core data
- **a library is called through the core**, so a new one needs no new shim: a page number in `constants.bas`, a line in
  `src/sjasmplus.cfg`, and its name in `build.ps1`'s list. `stage-lib-demo.bas` is a short one to copy

The demo's library is on page 71. Each time a stage begins it calls the library twice: to count it, and to show the
counts, under "library" at the top right of the screen.

## The keys

| Key | In the left, centre or right stage |
|---|---|
| `L`, `C`, `R` | the stage's own letter: page its data in again (a hit) and count once more. Another stage's letter: go to that stage now |
| `S` | save everything to `zxpaging.sav` |
| `O` | load it back ("old", as `L` is taken) |
| `M` | monitor on or off, in any stage |

If no key is pressed, each stage counts down from 5 and moves on: left, centre, right, then left again.

## Boriel BASIC: what is not used here, and why

None of this is a fault in Boriel ZX BASIC. Its library is designed for a Spectrum with its ROM and system variables in
place, which is how almost every program uses it. This demo takes all eight MMU slots for its own code and data, so the
ROM and the system variables are not there. The library routines behind a few keywords rely on them, and so cannot
be used in this particular layout:

- `CHR$` (it uses the system variable DEST), `STR$` and `VAL`, and floating point (they use the ROM's calculator)
- `PRINT`, arrays and `MOD` on `Fixed` (the routines behind them use MEMBOT or the screen system variables)
- `RND` and `RANDOMIZE`, `INKEY$`, `PAUSE`, `BEEP`, `LOAD` and `SAVE`

As far as we know, all other aspects of the language work as normal, strings included (see above). So we only mention
it here, right now, to help others avoid such minor pitfalls.

The core has small replacements: a character, a number as text, printing at a row and column, reading the keyboard,
waiting for a frame and file access through NextZXOS. `build.ps1` searches the compiled assembly and stops with a
message if any of the above appears.

Boriel's integer division also follows its own rules, which differ from C and C++ in places. `constants.bas` has the
details, measured on the emulator. In short: `Integer` and `Long` division round towards zero as C does, `Byte`
division takes the divisor's sign, `MOD` is never negative, and a constant expression such as `22/4` is worked out with
its fraction (5.5) before it is assigned.

## What you need

- Windows with PowerShell 7
- Python 3, which runs the compiler
- [Boriel ZX BASIC](https://zxbasic.readthedocs.io/) 1.19
- [sjasmplus](https://github.com/z00m128/sjasmplus) 1.24, which builds the nex file
- [ZEsarUX](https://github.com/chernandezba/zesarux) 13, which comes with a NextZXOS SD card image
- hdfmonkey, which puts files on the SD card image
- optional: [AutoHotkey](https://www.autohotkey.com/) v2, for `tools/zesarux-keys.ahk`, which makes the PC's number
  pad, Ctrl and punctuation keys arrive in the emulator as the program expects

`build.ps1` finds the tools by looking upwards from its own folder for one that contains `boriel\zxbc.py`. So the
layout is:

```
<any folder>\
    boriel\         zxbc.py and the rest of Boriel ZX BASIC
    sjasmplus\      sjasmplus.exe
    zesarux\        zesarux.exe and its tbblue.mmc
    tools\          hdfmonkey.exe
    ...\zxpaging\   this folder, at any depth below
```

## Building and running

```
pwsh .\build.ps1
```

This compiles the loader, the core, the four stages and the library, checks them, builds `zxpaging.nex` from
`src/sjasmplus.cfg`, puts it on the SD card images, and then starts ZEsarUX. Only the modules whose sources have changed
are compiled again. The checks stop the build if two fixed-address variables share a byte (`tools\check-addresses.ps1`)
or if a module uses anything that needs the ROM (see above).

The log is written to `build.log`, and a dated copy of every build's log is kept in `logs\`.

Options:

- `-NoRun`: build, but do not start the emulator
- `-Full`: compile every module, changed or not
- `-Jobs <n>`: how many modules to compile at once (as many as the PC has processors if not given)
- `-Start <x>`: which way to start, `zf`, `za`, `zb` or `zd`, in place of `$StartWith` near the end of `build.ps1`

The ways to start:

- `zf`, the fast start and the default, hands the nex file straight to ZEsarUX, with no NextZXOS boot and no SD card.
  ZEsarUX answers the file calls itself, so saving and loading still work: `zxpaging.sav` is written to the project
  folder on the PC.
- `za` boots NextZXOS from `zxpaging-za.mmc`, and `autoexec.bas` on that card then loads the nex file, as a real Next
  would. `zxpaging.sav` is written to the card image.
- `zb` boots NextZXOS from `zxpaging-zb.mmc`, which has no `autoexec.bas`, to its browser menu, where the nex file can
  be chosen by hand.
- `zd` leaves ZEsarUX waiting for the DeZog debugger in VS Code, which then loads the nex file as `zf` does. With
  this folder open in VS Code and the DeZog extension installed, F5 builds and starts it all (see `.vscode`). The
  build makes `build\zxpaging.sld` with `tools\make-sld.py`, so you can step through the BASIC, the `Asm` blocks and
  the page swaps with the source on screen.

There are three SD card images, beside `build.ps1`:

- `zxpaging-base.mmc`: the first build copies it from the NextZXOS card that comes with ZEsarUX (`zesarux\tbblue.mmc`)
  and makes it read-only. Nothing is ever added to it.
- `zxpaging-zb.mmc` and `zxpaging-za.mmc`: copied from the base when they are not there. Every build then puts the new
  nex file and the licence (as `zxpaging.lic`) on both, and `autoexec.bas` on the za card. Whatever the demo has saved on
  a card stays there from build to build. To start a card afresh, delete it, and the next build makes it again.

`clean.bat` takes the project back to what is in git: it empties `build\` and `logs\`, and deletes the nex file, the
three card images (and with them anything the demo saved on them), `build.log` and ZEsarUX's menu index. The next
build makes it all again.

## The files

Everything written by hand is in `src`:

| File | What it is |
|---|---|
| `src/load.bas` | the loader: sets 28MHz and the MMU slots, then starts the core |
| `src/core.bas` | the core: the main loop, paging, the jump table, printing, keyboard, files, the monitor |
| `src/stage-init.bas` | the start up stage: the tests, fresh data, the screen's labels |
| `src/stage-left.bas`, `src/stage-centre.bas`, `src/stage-right.bas` | the three stages |
| `src/stage-lib-demo.bas` | a library: code any stage may call, with 512 bytes of its own |
| `src/stage-include.bas` | the shims a stage uses to call the core |
| `src/stage-data-include.bas` | what the three stages share: paging their data in, saving, loading |
| `src/constants.bas`, `src/globals.bas` | pages, addresses, the layout of the core's data, and the notes above in full |
| `src/sjasmplus.cfg` | the layout of the nex file: which page each part goes in |
| `src/zesarux.cfg` | the emulator settings each start begins from, made into `build\zesarux-<start>.cfg` for each |
| `src/create-font.ps1` | makes the 8x8 font, `build\font.bin`, which the build runs when the font is missing or older than it |

Beside them:

| File | What it is |
|---|---|
| `build.ps1` | the build |
| `clean.bat` | deletes everything the build makes, the card images included |
| `tools/check-addresses.ps1` | the build's check that no two fixed-address variables share a byte |
| `tools/make-sld.py` | makes the debugging data DeZog reads, which line of source is at which address and page |
| `.vscode/launch.json`, `.vscode/tasks.json` | F5 in VS Code: build, start ZEsarUX for the debugger, connect DeZog |
| `tools/zesarux-keys.ahk` | the optional keyboard script |

The build makes `build\` (compiled code, listings and maps, all of which can be deleted at any time), `logs\`,
`zxpaging.nex` and the three card images.

## Licence

MIT, see `LICENSE`. Use it, change it, build on it.

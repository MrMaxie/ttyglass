import std/[os, unicode]

const
  shimRoot = currentSourcePath().parentDir
  libvtermRoot = currentSourcePath().parentDir / ".." / ".." / "vendor" / "libvterm"
  libvtermInclude = libvtermRoot / "include"
  libvtermSource = libvtermRoot / "src"

{.passC: "-I\"" & shimRoot & "\" -I\"" & libvtermInclude & "\" -I\"" & libvtermSource & "\"".}
{.compile: "libvterm_shim.c".}
{.compile: libvtermSource / "encoding.c".}
{.compile: libvtermSource / "keyboard.c".}
{.compile: libvtermSource / "mouse.c".}
{.compile: libvtermSource / "parser.c".}
{.compile: libvtermSource / "pen.c".}
{.compile: libvtermSource / "screen.c".}
{.compile: libvtermSource / "state.c".}
{.compile: libvtermSource / "unicode.c".}
{.compile: libvtermSource / "vterm.c".}

type
  VTermHandle {.importc: "TtyglassVTerm", header: "libvterm_shim.h", incompleteStruct.} = object

  CursorState* = object
    row*: int
    col*: int
    visible*: bool

  TerminalScreenObj = object
    handle: ptr VTermHandle
    cols*: int
    rows*: int
    revision*: uint64
    cursor*: CursorState

  TerminalScreen* = ref TerminalScreenObj

proc vtermNew(cols, rows: cint): ptr VTermHandle
  {.importc: "ttyglass_vterm_new", header: "libvterm_shim.h".}
proc vtermFree(handle: ptr VTermHandle)
  {.importc: "ttyglass_vterm_free", header: "libvterm_shim.h".}
proc vtermWrite(handle: ptr VTermHandle; bytes: cstring; length: csize_t)
  {.importc: "ttyglass_vterm_write", header: "libvterm_shim.h".}
proc vtermResize(handle: ptr VTermHandle; cols, rows: cint)
  {.importc: "ttyglass_vterm_resize", header: "libvterm_shim.h".}
proc vtermCursor(
    handle: ptr VTermHandle;
    row, col, visible: ptr cint
  ) {.importc: "ttyglass_vterm_cursor", header: "libvterm_shim.h".}
proc vtermCell(
    handle: ptr VTermHandle;
    row, col: cint;
    codepoints: ptr uint32;
    capacity: cint;
    width: ptr cint
  ): cint {.importc: "ttyglass_vterm_cell", header: "libvterm_shim.h".}

proc `=destroy`(screen: var TerminalScreenObj) =
  if screen.handle != nil:
    vtermFree(screen.handle)
    screen.handle = nil

proc updateCursor(screen: TerminalScreen) =
  var row, col, visible: cint
  vtermCursor(screen.handle, addr row, addr col, addr visible)
  screen.cursor = CursorState(
    row: row.int,
    col: col.int,
    visible: visible != 0,
  )

proc newTerminalScreen*(cols, rows: int): TerminalScreen =
  if cols <= 0 or rows <= 0:
    raise newException(ValueError, "terminal dimensions must be positive")

  new(result)
  result.handle = vtermNew(cols.cint, rows.cint)
  if result.handle == nil:
    raise newException(OutOfMemDefect, "could not create libvterm screen")
  result.cols = cols
  result.rows = rows
  result.revision = 0
  result.updateCursor()

proc feed*(screen: TerminalScreen; data: string) =
  if data.len == 0:
    return
  vtermWrite(screen.handle, data.cstring, data.len.csize_t)
  screen.updateCursor()
  inc screen.revision

proc resize*(screen: TerminalScreen; cols, rows: int) =
  if cols <= 0 or rows <= 0:
    raise newException(ValueError, "terminal dimensions must be positive")
  vtermResize(screen.handle, cols.cint, rows.cint)
  screen.cols = cols
  screen.rows = rows
  screen.updateCursor()
  inc screen.revision

proc lines*(screen: TerminalScreen): seq[string] =
  result = newSeq[string](screen.rows)
  for row in 0 ..< screen.rows:
    var cells = newSeq[string](screen.cols)
    var lastVisible = -1
    for col in 0 ..< screen.cols:
      var codepoints: array[6, uint32]
      var width: cint
      let count = vtermCell(
        screen.handle,
        row.cint,
        col.cint,
        addr codepoints[0],
        codepoints.len.cint,
        addr width,
      ).int
      if count > 0:
        for index in 0 ..< count:
          cells[col].add(Rune(codepoints[index].int32).toUTF8)
        lastVisible = col
      elif width > 0:
        cells[col] = " "

    if lastVisible >= 0:
      for col in 0 .. lastVisible:
        result[row].add(cells[col])

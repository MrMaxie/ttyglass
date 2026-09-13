import jsony
import std/streams

type
  FrameKind* = enum
    StartFrame = 1
    InputFrame = 2
    ResizeFrame = 3
    StopFrame = 4
    StartedFrame = 16
    OutputFrame = 17
    ExitedFrame = 18
    ErrorFrame = 19

  Frame* = object
    kind*: FrameKind
    payload*: string

  StartControl* = object
    command*: string
    arguments*: seq[string]
    cwd*: string
    cols*: int
    rows*: int

  ResizeControl* = object
    cols*: int
    rows*: int

  StartedControl* = object
    pid*: int

  ExitedControl* = object
    pid*: int
    exitCode*: int

const MaximumFrameLength* = 1024 * 1024

proc encodeLength(length: int): array[4, char] =
  result[0] = char(length and 0xff)
  result[1] = char((length shr 8) and 0xff)
  result[2] = char((length shr 16) and 0xff)
  result[3] = char((length shr 24) and 0xff)

proc readExact(stream: Stream, length: int): string =
  result = newString(length)
  var offset = 0
  while offset < length:
    let count = stream.readData(addr result[offset], length - offset)
    if count <= 0:
      raise newException(IOError, "Unexpected end of ttyglass IPC stream.")
    offset += count

proc writeFrame*(stream: Stream, kind: FrameKind, payload = "") =
  let size = encodeLength(payload.len)
  stream.write(char(kind))
  stream.write(size)
  if payload.len > 0:
    stream.write(payload)
  stream.flush()

proc readFrame*(stream: Stream): Frame =
  let kindByte = stream.readExact(1)
  let size = stream.readExact(4)
  let length =
    ord(size[0]) or
    (ord(size[1]) shl 8) or
    (ord(size[2]) shl 16) or
    (ord(size[3]) shl 24)
  if length < 0 or length > MaximumFrameLength:
    raise newException(
      IOError,
      "Invalid ttyglass IPC frame length " & $length &
        " after frame byte " & $ord(kindByte[0]) & ".",
    )
  let kind =
    case ord(kindByte[0])
    of ord(StartFrame): StartFrame
    of ord(InputFrame): InputFrame
    of ord(ResizeFrame): ResizeFrame
    of ord(StopFrame): StopFrame
    of ord(StartedFrame): StartedFrame
    of ord(OutputFrame): OutputFrame
    of ord(ExitedFrame): ExitedFrame
    of ord(ErrorFrame): ErrorFrame
    else: raise newException(IOError, "Invalid ttyglass IPC frame type.")
  result = Frame(kind: kind, payload: stream.readExact(length))

proc startPayload*(control: StartControl): string = control.toJson()
proc resizePayload*(control: ResizeControl): string = control.toJson()
proc startedPayload*(control: StartedControl): string = control.toJson()
proc exitedPayload*(control: ExitedControl): string = control.toJson()

proc parseStart*(payload: string): StartControl = payload.fromJson(StartControl)
proc parseResize*(payload: string): ResizeControl = payload.fromJson(ResizeControl)
proc parseStarted*(payload: string): StartedControl = payload.fromJson(StartedControl)
proc parseExited*(payload: string): ExitedControl = payload.fromJson(ExitedControl)

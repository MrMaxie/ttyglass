when not defined(posix):
  {.error: "pty_posix is only available on POSIX".}

import std/[locks, posix, streams]

import ./ipc

when defined(linux):
  {.passL: "-lutil".}

type WindowSize {.bycopy.} = object
  rows: cushort
  columns: cushort
  pixelWidth: cushort
  pixelHeight: cushort

when defined(macosx):
  proc forkPty(
    master: ptr cint,
    name: cstring,
    terminalSettings: pointer,
    size: ptr WindowSize,
  ): Pid {.importc: "forkpty", header: "<util.h>".}
else:
  proc forkPty(
    master: ptr cint,
    name: cstring,
    terminalSettings: pointer,
    size: ptr WindowSize,
  ): Pid {.importc: "forkpty", header: "<pty.h>".}

var setWindowSizeRequest {.importc: "TIOCSWINSZ", header: "<sys/ioctl.h>".}: culong

var
  controlInput: Stream
  hostOutput: Stream
  masterDescriptor: cint
  childPid: Pid
  outputLock: Lock
  stateLock: Lock

proc sendFrame(kind: FrameKind, payload = "") {.gcsafe.} =
  withLock outputLock:
    {.cast(gcsafe).}:
      hostOutput.writeFrame(kind, payload)

proc stopProcess() =
  withLock stateLock:
    if childPid > 0:
      discard kill(-childPid, SIGTERM)

proc resize(cols, rows: int) =
  if cols < 2 or cols > 1000 or rows < 1 or rows > 500:
    return
  var size = WindowSize(rows: rows.cushort, columns: cols.cushort)
  withLock stateLock:
    if masterDescriptor >= 0:
      discard ioctl(masterDescriptor, setWindowSizeRequest, addr size)

proc writeTerminal(payload: string) =
  if payload.len == 0:
    return
  withLock stateLock:
    if masterDescriptor >= 0:
      var offset = 0
      while offset < payload.len:
        let count = posix.write(
          masterDescriptor,
          unsafeAddr payload[offset],
          payload.len - offset,
        )
        if count <= 0:
          break
        offset += count

proc controlLoop() {.thread, gcsafe.} =
  {.cast(gcsafe).}:
    try:
      while true:
        let frame = controlInput.readFrame()
        case frame.kind
        of InputFrame:
          writeTerminal(frame.payload)
        of ResizeFrame:
          let requested = frame.payload.parseResize()
          resize(requested.cols, requested.rows)
        of StopFrame:
          stopProcess()
          break
        else:
          discard
    except IOError, ValueError:
      stopProcess()

proc outputLoop() {.thread, gcsafe.} =
  var buffer: array[16 * 1024, byte]
  while true:
    let count = posix.read(masterDescriptor, addr buffer[0], buffer.len)
    if count <= 0:
      break
    var payload = newString(count)
    copyMem(addr payload[0], addr buffer[0], count)
    sendFrame(OutputFrame, payload)

proc runPosixPtyHost*(start: StartControl, input, output: Stream): int =
  initLock(outputLock)
  initLock(stateLock)
  controlInput = input
  hostOutput = output
  masterDescriptor = -1
  childPid = -1

  var initialSize = WindowSize(
    rows: max(1, min(500, start.rows)).cushort,
    columns: max(2, min(1000, start.cols)).cushort,
  )
  childPid = forkPty(addr masterDescriptor, nil, nil, addr initialSize)
  if childPid < 0:
    output.writeFrame(ErrorFrame, "forkpty failed with error " & $errno)
    return 1
  if childPid == 0:
    if chdir(start.cwd.cstring) != 0:
      quit(126)
    let commandLine = @[start.command] & start.arguments
    let arguments = allocCStringArray(commandLine)
    discard execvp(arguments[0], arguments)
    quit(127)

  sendFrame(StartedFrame, StartedControl(pid: childPid.int).startedPayload())
  var controlThread: Thread[void]
  var readerThread: Thread[void]
  createThread(controlThread, controlLoop)
  createThread(readerThread, outputLoop)

  var status: cint
  discard waitpid(childPid, status, 0)
  let exitCode =
    if WIFEXITED(status): WEXITSTATUS(status).int
    elif WIFSIGNALED(status): 128 + WTERMSIG(status).int
    else: 1
  joinThread(readerThread)
  sendFrame(
    ExitedFrame,
    ExitedControl(pid: childPid.int, exitCode: exitCode).exitedPayload(),
  )
  discard posix.close(masterDescriptor)
  masterDescriptor = -1
  result = exitCode

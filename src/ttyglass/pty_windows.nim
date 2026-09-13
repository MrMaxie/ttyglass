when not defined(windows):
  {.error: "pty_windows is only available on Windows".}

import std/[locks, os, streams, strutils, widestrs]
import winlean

import ./ipc

type
  PseudoConsole = Handle

  ConsoleSize {.bycopy.} = object
    x: int16
    y: int16

  StartupInfoEx {.bycopy.} = object
    startupInfo: STARTUPINFO
    attributeList: pointer

  IoCounters {.bycopy.} = object
    readOperationCount: uint64
    writeOperationCount: uint64
    otherOperationCount: uint64
    readTransferCount: uint64
    writeTransferCount: uint64
    otherTransferCount: uint64

  BasicLimitInformation {.bycopy.} = object
    perProcessUserTimeLimit: int64
    perJobUserTimeLimit: int64
    limitFlags: DWORD
    minimumWorkingSetSize: uint
    maximumWorkingSetSize: uint
    activeProcessLimit: DWORD
    affinity: uint
    priorityClass: DWORD
    schedulingClass: DWORD

  ExtendedLimitInformation {.bycopy.} = object
    basicLimitInformation: BasicLimitInformation
    ioInfo: IoCounters
    processMemoryLimit: uint
    jobMemoryLimit: uint
    peakProcessMemoryUsed: uint
    peakJobMemoryUsed: uint

const
  ExtendedStartupInfoPresent = 0x00080000'i32
  ProcessAttributePseudoConsole = 0x00020016'u
  JobObjectExtendedLimitInformation = 9'i32
  JobObjectLimitKillOnJobClose = 0x00002000'i32

proc createPseudoConsole(
  size: ConsoleSize,
  inputReadSide, outputWriteSide: Handle,
  flags: DWORD,
  console: ptr PseudoConsole,
): int32 {.stdcall, dynlib: "kernel32", importc: "CreatePseudoConsole".}

proc resizePseudoConsole(
  console: PseudoConsole,
  size: ConsoleSize,
): int32 {.stdcall, dynlib: "kernel32", importc: "ResizePseudoConsole".}

proc closePseudoConsole(
  console: PseudoConsole,
) {.stdcall, dynlib: "kernel32", importc: "ClosePseudoConsole".}

proc initializeProcThreadAttributeList(
  attributeList: pointer,
  attributeCount: DWORD,
  flags: DWORD,
  size: ptr uint,
): WINBOOL {.stdcall, dynlib: "kernel32", importc: "InitializeProcThreadAttributeList".}

proc updateProcThreadAttribute(
  attributeList: pointer,
  flags: DWORD,
  attribute: uint,
  value: pointer,
  size: uint,
  previousValue: pointer,
  returnSize: ptr uint,
): WINBOOL {.stdcall, dynlib: "kernel32", importc: "UpdateProcThreadAttribute".}

proc deleteProcThreadAttributeList(
  attributeList: pointer,
) {.stdcall, dynlib: "kernel32", importc: "DeleteProcThreadAttributeList".}

proc createProcessAttached(
  applicationName, commandLine: WideCString,
  processAttributes, threadAttributes: pointer,
  inheritHandles: WINBOOL,
  creationFlags: DWORD,
  environment: pointer,
  currentDirectory: WideCString,
  startupInfo: ptr StartupInfoEx,
  processInformation: ptr PROCESS_INFORMATION,
): WINBOOL {.stdcall, dynlib: "kernel32", importc: "CreateProcessW".}

proc createJobObject(
  attributes: pointer,
  name: WideCString,
): Handle {.stdcall, dynlib: "kernel32", importc: "CreateJobObjectW".}

proc setInformationJobObject(
  job: Handle,
  informationClass: DWORD,
  information: pointer,
  informationLength: DWORD,
): WINBOOL {.stdcall, dynlib: "kernel32", importc: "SetInformationJobObject".}

proc assignProcessToJobObject(
  job, process: Handle,
): WINBOOL {.stdcall, dynlib: "kernel32", importc: "AssignProcessToJobObject".}

proc terminateJobObject(
  job: Handle,
  exitCode: uint32,
): WINBOOL {.stdcall, dynlib: "kernel32", importc: "TerminateJobObject".}

var
  controlInput: Stream
  hostOutput: Stream
  pseudoConsole: PseudoConsole
  processHandle: Handle
  processJob: Handle
  terminalInput: Handle
  terminalOutput: Handle
  outputLock: Lock
  stateLock: Lock

proc failWindows(operation: string) {.noreturn.} =
  raise newException(OSError, operation & " failed with Windows error " & $osLastError())

proc createPipePair(readSide, writeSide: var Handle) =
  var attributes = SECURITY_ATTRIBUTES(
    nLength: sizeof(SECURITY_ATTRIBUTES).int32,
    lpSecurityDescriptor: nil,
    bInheritHandle: 0,
  )
  if createPipe(readSide, writeSide, attributes, 0) == 0:
    failWindows("CreatePipe")

proc sendFrame(kind: FrameKind, payload = "") {.gcsafe.} =
  withLock outputLock:
    {.cast(gcsafe).}:
      hostOutput.writeFrame(kind, payload)

proc quoteWindowsArgument(value: string): string =
  if value.len > 0 and value.allCharsInSet({char(33)..char(126)} - {' ', '\t', '"'}):
    return value
  result = "\""
  var backslashes = 0
  for character in value:
    if character == '\\':
      inc backslashes
    elif character == '"':
      result.add('\\'.repeat(backslashes * 2 + 1))
      result.add(character)
      backslashes = 0
    else:
      result.add('\\'.repeat(backslashes))
      result.add(character)
      backslashes = 0
  result.add('\\'.repeat(backslashes * 2))
  result.add('"')

proc directCommandLine(executable: string, arguments: openArray[string]): string =
  result = quoteWindowsArgument(executable)
  for argument in arguments:
    result.add(' ')
    result.add(quoteWindowsArgument(argument))

proc resolvedCommand(command: string): string =
  result = findExe(command)
  if result.len == 0:
    result = command

proc stopProcess() =
  withLock stateLock:
    if processJob != 0:
      discard terminateJobObject(processJob, 1)
    elif processHandle != 0:
      discard terminateProcess(processHandle, 1)

proc resize(cols, rows: int) =
  if cols < 2 or cols > 1000 or rows < 1 or rows > 500:
    return
  withLock stateLock:
    if pseudoConsole != 0:
      discard resizePseudoConsole(
        pseudoConsole,
        ConsoleSize(x: cols.int16, y: rows.int16),
      )

proc writeTerminal(payload: string) =
  if payload.len == 0:
    return
  withLock stateLock:
    if terminalInput != 0:
      var written: int32
      discard writeFile(
        terminalInput,
        unsafeAddr payload[0],
        payload.len.int32,
        addr written,
        nil,
      )

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
    var count: int32
    if readFile(terminalOutput, addr buffer[0], buffer.len.int32, addr count, nil) == 0 or count <= 0:
      break
    var payload = newString(count)
    copyMem(addr payload[0], addr buffer[0], count)
    sendFrame(OutputFrame, payload)

proc configureJob(child: Handle): Handle =
  result = createJobObject(nil, nil)
  if result == 0:
    return
  var limits: ExtendedLimitInformation
  limits.basicLimitInformation.limitFlags = JobObjectLimitKillOnJobClose
  if setInformationJobObject(
    result,
    JobObjectExtendedLimitInformation,
    addr limits,
    sizeof(limits).DWORD,
  ) == 0 or assignProcessToJobObject(result, child) == 0:
    discard closeHandle(result)
    result = 0

proc runWindowsPtyHost*(start: StartControl, input, output: Stream): int =
  initLock(outputLock)
  initLock(stateLock)
  controlInput = input
  hostOutput = output

  var
    consoleInput: Handle
    consoleOutput: Handle
    attributeBytes: uint
    startup: StartupInfoEx
    child: PROCESS_INFORMATION

  try:
    createPipePair(consoleInput, terminalInput)
    createPipePair(terminalOutput, consoleOutput)
    let initialSize = ConsoleSize(
      x: max(2, min(1000, start.cols)).int16,
      y: max(1, min(500, start.rows)).int16,
    )
    if createPseudoConsole(initialSize, consoleInput, consoleOutput, 0, addr pseudoConsole) != 0:
      failWindows("CreatePseudoConsole")
    discard closeHandle(consoleInput)
    consoleInput = 0
    discard closeHandle(consoleOutput)
    consoleOutput = 0

    discard initializeProcThreadAttributeList(nil, 1, 0, addr attributeBytes)
    startup.attributeList = allocShared0(attributeBytes)
    if startup.attributeList == nil:
      raise newException(OutOfMemDefect, "Could not allocate the process attribute list.")
    if initializeProcThreadAttributeList(startup.attributeList, 1, 0, addr attributeBytes) == 0:
      failWindows("InitializeProcThreadAttributeList")
    if updateProcThreadAttribute(
      startup.attributeList,
      0,
      ProcessAttributePseudoConsole,
      cast[pointer](pseudoConsole),
      sizeof(PseudoConsole).uint,
      nil,
      nil,
    ) == 0:
      failWindows("UpdateProcThreadAttribute")
    startup.startupInfo.cb = sizeof(StartupInfoEx).int32
    startup.startupInfo.dwFlags = STARTF_USESTDHANDLES

    let requested = resolvedCommand(start.command)
    let extension = requested.splitFile().ext.toLowerAscii()
    var executable = requested
    var commandLine = directCommandLine(requested, start.arguments)
    if extension in [".cmd", ".bat"]:
      executable = getEnv("ComSpec", "cmd.exe")
      commandLine = directCommandLine(executable, @["/d", "/s", "/c", commandLine])

    var mutableCommand = newWideCString(commandLine)
    let wideExecutable = newWideCString(executable)
    let wideDirectory = newWideCString(start.cwd)
    if createProcessAttached(
      wideExecutable,
      mutableCommand,
      nil,
      nil,
      0,
      ExtendedStartupInfoPresent or CREATE_UNICODE_ENVIRONMENT,
      nil,
      wideDirectory,
      addr startup,
      addr child,
    ) == 0:
      failWindows("CreateProcessW")

    processHandle = child.hProcess
    processJob = configureJob(child.hProcess)
    discard closeHandle(child.hThread)
    sendFrame(StartedFrame, StartedControl(pid: child.dwProcessId.int).startedPayload())

    var controlThread: Thread[void]
    var readerThread: Thread[void]
    createThread(controlThread, controlLoop)
    createThread(readerThread, outputLoop)

    discard waitForSingleObject(child.hProcess, INFINITE)
    var exitCode: int32
    discard getExitCodeProcess(child.hProcess, exitCode)
    closePseudoConsole(pseudoConsole)
    pseudoConsole = 0
    joinThread(readerThread)
    sendFrame(
      ExitedFrame,
      ExitedControl(pid: child.dwProcessId.int, exitCode: exitCode.int).exitedPayload(),
    )
    result = exitCode.int
  except CatchableError as error:
    try:
      sendFrame(ErrorFrame, error.msg)
    except CatchableError:
      discard
    result = 1
  finally:
    if startup.attributeList != nil:
      deleteProcThreadAttributeList(startup.attributeList)
      deallocShared(startup.attributeList)
    if pseudoConsole != 0:
      closePseudoConsole(pseudoConsole)
    for handle in [consoleInput, consoleOutput, terminalInput, terminalOutput, processHandle, processJob]:
      if handle != 0:
        discard closeHandle(handle)

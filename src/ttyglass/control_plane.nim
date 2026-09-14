import jsony
import std/[atomics, hashes, os, strutils, times, widestrs]

when defined(windows):
  import winlean

type
  ServiceDescriptor* = object
    pid*: int
    endpoint*: string
    origin*: string
    token*: string

  ControlHandler* = proc(payload: string): string {.gcsafe.}

  ControlServer* = ref object
    endpoint*: string
    stopped: Atomic[bool]
    thread: Thread[ControlServer]
    handler: ControlHandler

  ServiceLock* = object
    when defined(windows):
      handle: Handle
    else:
      descriptor: cint

const MaximumControlMessageBytes = 4 * 1024 * 1024

proc runtimeDirectory*(): string =
  let identity = getHomeDir().toLowerAscii()
  result = getTempDir() / ("ttyglass-" & toHex(hash(identity).uint, 16).toLowerAscii())

proc descriptorPath*(): string = runtimeDirectory() / "service.json"

proc prepareRuntimeDirectory*() =
  createDir(runtimeDirectory())
  when defined(posix):
    setFilePermissions(runtimeDirectory(), {fpUserRead, fpUserWrite, fpUserExec})

proc readDescriptor*(): ServiceDescriptor =
  readFile(descriptorPath()).fromJson(ServiceDescriptor)

proc writeDescriptor*(descriptor: ServiceDescriptor) =
  prepareRuntimeDirectory()
  let temporary = descriptorPath() & ".tmp-" & $getCurrentProcessId()
  writeFile(temporary, descriptor.toJson())
  when defined(posix):
    setFilePermissions(temporary, {fpUserRead, fpUserWrite})
  moveFile(temporary, descriptorPath())

proc removeDescriptor*() =
  try:
    if fileExists(descriptorPath()):
      removeFile(descriptorPath())
  except OSError:
    discard

proc encodeLength(length: int): array[4, char] =
  result[0] = char(length and 0xff)
  result[1] = char((length shr 8) and 0xff)
  result[2] = char((length shr 16) and 0xff)
  result[3] = char((length shr 24) and 0xff)

proc decodeLength(value: array[4, char]): int =
  ord(value[0]) or
    (ord(value[1]) shl 8) or
    (ord(value[2]) shl 16) or
    (ord(value[3]) shl 24)

proc lengthString(length: int): string =
  let encoded = encodeLength(length)
  result = newString(4)
  copyMem(addr result[0], unsafeAddr encoded[0], 4)

when defined(windows):
  const
    PipeAccessDuplex = 0x00000003'i32
    PipeTypeMessage = 0x00000004'i32
    PipeReadmodeMessage = 0x00000002'i32
    PipeWait = 0x00000000'i32
    PipeUnlimitedInstances = 255'i32
    GenericRead = 0x80000000'u32
    GenericWrite = 0x40000000'u32
    OpenExisting = 3'i32
    ErrorPipeConnected = 535'i32
    ErrorAlreadyExists = 183'i32
    InvalidHandleValue = cast[Handle](-1)

  proc connectNamedPipe(handle: Handle, overlapped: pointer): WINBOOL
    {.stdcall, dynlib: "kernel32", importc: "ConnectNamedPipe".}

  proc disconnectNamedPipe(handle: Handle): WINBOOL
    {.stdcall, dynlib: "kernel32", importc: "DisconnectNamedPipe".}

  proc createFilePipe(
    name: WideCString,
    access, shareMode: DWORD,
    security: pointer,
    creationDisposition, flags: DWORD,
    templateFile: Handle,
  ): Handle {.stdcall, dynlib: "kernel32", importc: "CreateFileW".}

  proc flushPipe(handle: Handle): WINBOOL
    {.stdcall, dynlib: "kernel32", importc: "FlushFileBuffers".}

  proc createMutex(
    attributes: pointer,
    initialOwner: WINBOOL,
    name: WideCString,
  ): Handle {.stdcall, dynlib: "kernel32", importc: "CreateMutexW".}

  proc releaseMutex(handle: Handle): WINBOOL
    {.stdcall, dynlib: "kernel32", importc: "ReleaseMutex".}

  proc acquireServiceLock*(): ServiceLock =
    let name = "Local\\ttyglass-" & toHex(hash(getHomeDir().toLowerAscii()).uint, 16).toLowerAscii()
    result.handle = createMutex(nil, 1, newWideCString(name))
    if result.handle == 0:
      raise newException(OSError, "Could not create the ttyglass service lock.")
    if osLastError().int32 == ErrorAlreadyExists:
      discard closeHandle(result.handle)
      result.handle = 0
      raise newException(IOError, "A ttyglass service is already running for this user.")

  proc release*(serviceLock: var ServiceLock) =
    if serviceLock.handle != 0:
      discard releaseMutex(serviceLock.handle)
      discard closeHandle(serviceLock.handle)
      serviceLock.handle = 0

  proc readExact(handle: Handle, size: int): string =
    result = newString(size)
    var offset = 0
    while offset < size:
      var count: int32
      if readFile(handle, addr result[offset], (size - offset).int32, addr count, nil) == 0 or count <= 0:
        raise newException(IOError, "The ttyglass control pipe closed unexpectedly.")
      offset += count

  proc writeExact(handle: Handle, value: string) =
    var offset = 0
    while offset < value.len:
      var count: int32
      if writeFile(handle, unsafeAddr value[offset], (value.len - offset).int32, addr count, nil) == 0 or count <= 0:
        raise newException(IOError, "Could not write to the ttyglass control pipe.")
      offset += count

  proc exchange(handle: Handle, payload: string): string =
    handle.writeExact(lengthString(payload.len))
    handle.writeExact(payload)
    var header: array[4, char]
    let headerValue = handle.readExact(4)
    copyMem(addr header[0], unsafeAddr headerValue[0], 4)
    let length = decodeLength(header)
    if length < 0 or length > MaximumControlMessageBytes:
      raise newException(IOError, "Invalid ttyglass control response length.")
    result = handle.readExact(length)

  proc serveOne(server: ControlServer) =
    let pipe = createNamedPipe(
      newWideCString(server.endpoint),
      PipeAccessDuplex.DWORD,
      (PipeTypeMessage or PipeReadmodeMessage or PipeWait).DWORD,
      PipeUnlimitedInstances.DWORD,
      MaximumControlMessageBytes.DWORD,
      MaximumControlMessageBytes.DWORD,
      0,
      nil,
    )
    if pipe == InvalidHandleValue:
      raise newException(OSError, "Could not create the ttyglass control pipe.")
    try:
      if connectNamedPipe(pipe, nil) == 0 and osLastError().int32 != ErrorPipeConnected:
        raise newException(OSError, "Could not accept a ttyglass control client.")
      let headerValue = pipe.readExact(4)
      var header: array[4, char]
      copyMem(addr header[0], unsafeAddr headerValue[0], 4)
      let length = decodeLength(header)
      if length < 0 or length > MaximumControlMessageBytes:
        raise newException(IOError, "Invalid ttyglass control request length.")
      let response = server.handler(pipe.readExact(length))
      pipe.writeExact(lengthString(response.len))
      pipe.writeExact(response)
      discard flushPipe(pipe)
    finally:
      discard disconnectNamedPipe(pipe)
      discard closeHandle(pipe)

  proc controlLoop(server: ControlServer) {.thread, gcsafe.} =
    {.cast(gcsafe).}:
      while not server.stopped.load(moRelaxed):
        try:
          server.serveOne()
        except CatchableError:
          if not server.stopped.load(moRelaxed):
            sleep(25)

  proc callEndpoint(endpoint, payload: string): string =
    let deadline = epochTime() + 2.0
    while epochTime() < deadline:
      let pipe = createFilePipe(
        newWideCString(endpoint),
        cast[DWORD](GenericRead or GenericWrite),
        0.DWORD,
        nil,
        OpenExisting.DWORD,
        0.DWORD,
        0.Handle,
      )
      if pipe != InvalidHandleValue:
        try:
          return pipe.exchange(payload)
        finally:
          discard closeHandle(pipe)
      sleep(5)
    raise newException(IOError, "The ttyglass service is not reachable.")

else:
  import std/net
  import std/posix

  var
    LockExclusive {.importc: "LOCK_EX", header: "<sys/file.h>".}: cint
    LockNonBlocking {.importc: "LOCK_NB", header: "<sys/file.h>".}: cint

  proc fileLock(descriptor, operation: cint): cint
    {.importc: "flock", header: "<sys/file.h>".}

  proc acquireServiceLock*(): ServiceLock =
    prepareRuntimeDirectory()
    result.descriptor = posix.open(
      (runtimeDirectory() / "service.lock").cstring,
      O_CREAT or O_RDWR,
      Mode(0o600),
    )
    if result.descriptor < 0 or fileLock(result.descriptor, LockExclusive or LockNonBlocking) != 0:
      if result.descriptor >= 0: discard posix.close(result.descriptor)
      result.descriptor = -1
      raise newException(IOError, "A ttyglass service is already running for this user.")

  proc release*(serviceLock: var ServiceLock) =
    if serviceLock.descriptor >= 0:
      discard posix.close(serviceLock.descriptor)
      serviceLock.descriptor = -1

  proc receiveExact(socket: Socket, size: int): string =
    result = newStringOfCap(size)
    while result.len < size:
      let part = socket.recv(size - result.len)
      if part.len == 0:
        raise newException(IOError, "The ttyglass control socket closed unexpectedly.")
      result.add(part)

  proc sendExact(socket: Socket, value: string) =
    socket.send(value)

  proc exchange(socket: Socket, payload: string): string =
    socket.sendExact(lengthString(payload.len))
    socket.sendExact(payload)
    let headerValue = socket.receiveExact(4)
    var header: array[4, char]
    copyMem(addr header[0], unsafeAddr headerValue[0], 4)
    let length = decodeLength(header)
    if length < 0 or length > MaximumControlMessageBytes:
      raise newException(IOError, "Invalid ttyglass control response length.")
    result = socket.receiveExact(length)

  proc controlLoop(server: ControlServer) {.thread, gcsafe.} =
    {.cast(gcsafe).}:
      let listener = newSocket(AF_UNIX, SOCK_STREAM, IPPROTO_IP)
      try:
        if fileExists(server.endpoint):
          removeFile(server.endpoint)
        listener.bindUnix(server.endpoint)
        setFilePermissions(server.endpoint, {fpUserRead, fpUserWrite})
        listener.listen()
        while not server.stopped.load(moRelaxed):
          var client = newSocket(AF_UNIX, SOCK_STREAM, IPPROTO_IP)
          try:
            listener.accept(client)
            let headerValue = client.receiveExact(4)
            var header: array[4, char]
            copyMem(addr header[0], unsafeAddr headerValue[0], 4)
            let length = decodeLength(header)
            if length < 0 or length > MaximumControlMessageBytes:
              raise newException(IOError, "Invalid ttyglass control request length.")
            let response = server.handler(client.receiveExact(length))
            client.sendExact(lengthString(response.len))
            client.sendExact(response)
          except CatchableError:
            discard
          finally:
            client.close()
      finally:
        listener.close()
        try:
          if fileExists(server.endpoint):
            removeFile(server.endpoint)
        except OSError:
          discard

  proc callEndpoint(endpoint, payload: string): string =
    let socket = newSocket(AF_UNIX, SOCK_STREAM, IPPROTO_IP)
    try:
      socket.connectUnix(endpoint)
      result = socket.exchange(payload)
    finally:
      socket.close()

proc startControlServer*(handler: ControlHandler): ControlServer =
  prepareRuntimeDirectory()
  let endpoint =
    when defined(windows):
      "\\\\.\\pipe\\ttyglass-" & toHex(hash(getHomeDir().toLowerAscii()).uint, 16).toLowerAscii()
    else:
      runtimeDirectory() / "control.sock"
  result = ControlServer(endpoint: endpoint, handler: handler)
  result.stopped.store(false, moRelaxed)
  createThread(result.thread, controlLoop, result)

proc controlCall*(descriptor: ServiceDescriptor, payload: string): string =
  callEndpoint(descriptor.endpoint, payload)

proc stop*(server: ControlServer) =
  if server.isNil or server.stopped.exchange(true, moRelaxed):
    return
  try:
    discard callEndpoint(server.endpoint, "{}")
  except CatchableError:
    discard
  joinThread(server.thread)

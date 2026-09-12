import std/[httpclient, json, os, strformat, strutils, terminal, times]

const
  Language = "Nim"
  Source = "stress-nim"
  Levels = ["trace", "debug", "info", "warn", "error"]
  Phases = ["full redraw", "rapid counters", "palette sweep", "wide glyphs"]

var inputChannel: Channel[char]

proc readInput() {.thread.} =
  while true:
    inputChannel.send(getch())

proc durationFromArguments(): int =
  let arguments = commandLineParams()
  for index in 0 ..< arguments.len - 1:
    if arguments[index] == "--duration-ms":
      try:
        let milliseconds = parseInt(arguments[index + 1])
        if milliseconds > 0:
          return milliseconds
      except ValueError:
        discard

proc dimensions(): tuple[columns, rows: int] =
  let columns = terminalWidth()
  let rows = terminalHeight()
  result.columns = if columns > 0: columns else: 100
  result.rows = if rows > 0: rows else: 30

proc clip(value: string, width: int): string =
  if value.len <= width:
    return value
  value[0 ..< max(0, width)]

proc progressBar(value, width: int): string =
  let safeWidth = max(4, width)
  let filled = (safeWidth * value + 50) div 100
  "#".repeat(filled) & ".".repeat(safeWidth - filled)

proc paletteLine(frame, width: int): string =
  let cells = clamp((width - 10) div 3, 1, 16)
  result = "ANSI-16  "
  for index in 0 ..< cells:
    let color = (index + frame div 3) mod 16
    result.add(&"\e[48;5;{color}m  \e[0m ")

proc gradientLine(frame, width: int): string =
  let cells = clamp((width - 10) div 2, 1, 32)
  result = "RGB      "
  for index in 0 ..< cells:
    let hue = (index * 11 + frame * 4) mod 256
    result.add(&"\e[48;2;{hue};{255 - hue};{(hue * 3) mod 256}m  \e[0m")

proc render(frame: int, startedAt: float, paused: bool, diagnosticsSent: int): tuple[columns, rows: int] =
  let size = dimensions()
  let phase = Phases[(frame div 25) mod Phases.len]
  let state = if paused: "PAUSED" else: "RUNNING"
  var lines = @[
    &"\e[1;36mTTYGLASS STRESS TUI\e[0m | {Language} | frame {frame} | {epochTime() - startedAt:.1f}s",
    "-".repeat(size.columns),
    &"viewport {size.columns}x{size.rows} | phase: {phase} | diagnostics: {diagnosticsSent} | {state}",
    paletteLine(frame, size.columns),
    gradientLine(frame, size.columns),
    clip("Wide glyphs: zażółć gęślą jaźń | 日本語 | λ | box: +---+ | combining: é", size.columns),
    "",
  ]

  let tableRows = max(0, size.rows - lines.len - 2)
  for index in 0 ..< tableRows:
    let progress = (frame * 3 + index * 13) mod 101
    let latency = (frame * 17 + index * 29) mod 997
    let workerState = if index mod 7 == 0: "\e[33mBUSY\e[0m" else: "\e[32mOK  \e[0m"
    let barWidth = clamp(size.columns - 47, 4, 28)
    lines.add(&"{index + 1:03} worker-{index mod 12:02} {workerState} [{progressBar(progress, barWidth)}] {latency:3} ms")

  lines.add("-".repeat(size.columns))
  lines.add(clip("q quit | p pause | b diagnostic burst | d diagnostic | r redraw", size.columns))
  if lines.len > size.rows:
    lines.setLen(size.rows)

  stdout.write("\e[H")
  for index, line in lines:
    stdout.write("\e[2K")
    stdout.write(line)
    if index + 1 != lines.len:
      stdout.write("\r\n")
  stdout.flushFile()
  size

proc sendDiagnostic(client: HttpClient, endpoint, token, event, level: string, fields: JsonNode) =
  if endpoint.len == 0 or token.len == 0:
    return
  let record = %*{
    "source": Source,
    "level": level,
    "event": event,
    "message": Language & " emitted " & event,
    "fields": fields,
  }
  try:
    let headers = newHttpHeaders({
      "Authorization": "Bearer " & token,
      "Content-Type": "application/json",
    })
    discard client.request(endpoint, HttpPost, $record, headers)
  except CatchableError:
    discard

proc main() =
  let duration = durationFromArguments()
  let startedAt = epochTime()
  let endpoint = getEnv("TTYGLASS_DIAGNOSTICS_URL")
  let token = getEnv("TTYGLASS_DIAGNOSTICS_TOKEN")
  let client = newHttpClient(timeout = 1000)
  defer:
    client.close()
    stdout.write("\e[?25h\e[?1049l")
    stdout.flushFile()

  inputChannel.open(16)
  var inputThread: Thread[void]
  if (duration == 0 or endpoint.len > 0) and stdin.isatty:
    createThread(inputThread, readInput)

  var frame = 0
  var diagnosticsSent = 0
  var paused = false
  var previousSize = dimensions()
  var lastRender = epochTime() - 1.0
  var lastDiagnostic = epochTime()
  var running = true

  template emit(event, level: string, extra: JsonNode = nil) =
    inc diagnosticsSent
    let size = dimensions()
    var fields = %*{
      "frame": frame,
      "columns": size.columns,
      "rows": size.rows,
    }
    if extra != nil:
      for key, value in extra:
        fields[key] = value
    sendDiagnostic(client, endpoint, token, event, level, fields)

  stdout.write("\e[?1049h\e[2J\e[H\e[?25l")
  emit("fixture.ready", "info", %*{"standardLibrary": true})

  while running:
    let now = epochTime()
    if now - lastRender >= 0.1:
      lastRender = now
      if not paused:
        inc frame
      let size = dimensions()
      if size != previousSize:
        previousSize = size
        stdout.write("\e[2J")
        emit("viewport.changed", "debug", %*{"size": &"{size.columns}x{size.rows}"})
      discard render(frame, startedAt, paused, diagnosticsSent)

    if now - lastDiagnostic >= 0.5:
      lastDiagnostic = now
      emit(
        "fixture.heartbeat",
        Levels[diagnosticsSent mod Levels.len],
        %*{"phase": Phases[(frame div 25) mod Phases.len]},
      )

    while true:
      let received = inputChannel.tryRecv()
      if not received.dataAvailable:
        break
      let key = received.msg
      case key
      of 'q', '\x03':
        emit("fixture.stopped", "info")
        running = false
      of 'p', ' ':
        paused = not paused
      of 'b':
        for index in 0 ..< 12:
          emit("burst.item", Levels[index mod Levels.len], %*{"index": index})
      of 'd':
        emit("input.manual", "info")
      of 'r':
        discard render(frame, startedAt, paused, diagnosticsSent)
      else:
        discard

    if duration > 0 and int((now - startedAt) * 1000) >= duration:
      emit("fixture.stopped", "info")
      running = false
    sleep(5)

when isMainModule:
  main()

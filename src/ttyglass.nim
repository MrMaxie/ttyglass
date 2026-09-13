import cligen
import std/[os, strutils]

import ttyglass/[pty_host, server]

const TtyglassVersion* = "1.0.1"

proc run(
  cwd = "",
  port = 0,
  diagnostics_limit = 500,
  open = false,
  no_open = false,
  command: seq[string],
) =
  ## Observe a real terminal user interface in a local browser.
  if command.len == 0:
    raise newException(ValueError, "Provide a TUI command after --.")
  let workingDirectory = if cwd.len == 0: getCurrentDir() else: absolutePath(cwd)
  let commandArguments = if command.len > 1: command[1 .. ^1] else: @[]
  quit runServer(RunOptions(
    command: command[0],
    arguments: commandArguments,
    cwd: workingDirectory,
    port: port,
    diagnosticsLimit: diagnostics_limit,
    openBrowser: open and not no_open,
  ))

when isMainModule:
  let arguments = commandLineParams()
  if arguments.len == 1 and arguments[0] == "--internal-pty-host":
    quit(runPtyHost())

  if arguments notin [@["--help"], @["-h"], @["--version"]] and "--" notin arguments:
    stderr.writeLine("ttyglass: Separate ttyglass options from the TUI command with --.")
    quit(2)

  var configuration = clCfg
  configuration.version = TtyglassVersion
  configuration.longPfxOk = false
  dispatchCf(
    run,
    cmdName = "ttyglass",
    cf = configuration,
    usage = "ttyglass [options] -- <command> [arguments...]\n\nOptions:\n$options",
    stopWords = @["--"],
    positional = "command",
    short = {"help": 'h'},
    help = {
      "help": "Show command help",
      "helpsyntax": "CLIGEN-NOHELP",
      "version": "Show version",
      "cwd": "Run the command from this directory",
      "port": "Use a fixed loopback port (default: available port)",
      "diagnostics-limit": "Keep 1-5000 application diagnostic entries",
      "open": "Open the browser after startup",
      "no-open": "Do not open the browser (default)",
      "command": "Command and arguments following --",
    },
  )

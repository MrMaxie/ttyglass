import unittest2
import std/strutils

import ttyglass/terminal_screen

suite "terminal screen":
  test "tracks alternate screen, unicode, cursor, and visibility":
    let screen = newTerminalScreen(12, 4)
    screen.feed("primary")
    screen.feed("\e[?1049h\e[2J\e[Hzażółć\e[2;4Hok\e[?25l")
    check screen.lines()[0].startsWith("zażółć")
    check screen.lines()[1].startsWith("   ok")
    check screen.cursor.row == 1
    check screen.cursor.col == 5
    check screen.cursor.visible == false

    screen.feed("\e[?1049l")
    check screen.lines()[0].startsWith("primary")

  test "resizes while retaining visible cells":
    let screen = newTerminalScreen(8, 3)
    screen.feed("one\r\ntwo")
    let revision = screen.revision
    screen.resize(10, 4)
    check screen.cols == 10
    check screen.rows == 4
    check screen.revision > revision
    check screen.lines()[0].startsWith("one")
    check screen.lines()[1].startsWith("two")

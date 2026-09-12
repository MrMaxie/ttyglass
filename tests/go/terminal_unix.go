//go:build !windows

package main

import (
	"os"
	"strconv"
	"syscall"
	"unsafe"
)

type windowSize struct {
	rows    uint16
	columns uint16
	xPixel  uint16
	yPixel  uint16
}

func terminalSize() (int, int) {
	var size windowSize
	_, _, errorNumber := syscall.Syscall(syscall.SYS_IOCTL, os.Stdout.Fd(), syscall.TIOCGWINSZ, uintptr(unsafe.Pointer(&size)))
	if errorNumber == 0 && size.columns > 0 && size.rows > 0 {
		return int(size.columns), int(size.rows)
	}
	columns, _ := strconv.Atoi(os.Getenv("COLUMNS"))
	rows, _ := strconv.Atoi(os.Getenv("LINES"))
	if columns <= 0 {
		columns = 100
	}
	if rows <= 0 {
		rows = 30
	}
	return columns, rows
}

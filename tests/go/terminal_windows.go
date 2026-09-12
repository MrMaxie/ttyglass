//go:build windows

package main

import (
	"syscall"
	"unsafe"
)

type coord struct {
	x int16
	y int16
}

type smallRect struct {
	left   int16
	top    int16
	right  int16
	bottom int16
}

type consoleScreenBufferInfo struct {
	size              coord
	cursorPosition    coord
	attributes        uint16
	window            smallRect
	maximumWindowSize coord
}

var (
	kernel32                   = syscall.NewLazyDLL("kernel32.dll")
	getStdHandle               = kernel32.NewProc("GetStdHandle")
	getConsoleScreenBufferInfo = kernel32.NewProc("GetConsoleScreenBufferInfo")
)

func terminalSize() (int, int) {
	handle, _, _ := getStdHandle.Call(uintptr(^uint32(10)))
	var info consoleScreenBufferInfo
	result, _, _ := getConsoleScreenBufferInfo.Call(handle, uintptr(unsafe.Pointer(&info)))
	if result == 0 {
		return 100, 30
	}
	return int(info.window.right-info.window.left) + 1, int(info.window.bottom-info.window.top) + 1
}

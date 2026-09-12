package main

import (
	"bufio"
	"bytes"
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"strconv"
	"strings"
	"time"
)

const (
	language = "Go"
	source   = "stress-go"
)

var (
	levels = []string{"trace", "debug", "info", "warn", "error"}
	phases = []string{"full redraw", "rapid counters", "palette sweep", "wide glyphs"}
)

type diagnosticRequest struct {
	event  string
	level  string
	fields map[string]any
}

type diagnosticRecord struct {
	Source  string         `json:"source"`
	Level   string         `json:"level"`
	Event   string         `json:"event"`
	Message string         `json:"message"`
	Fields  map[string]any `json:"fields"`
}

func durationFromArguments() time.Duration {
	for index, argument := range os.Args {
		if argument == "--duration-ms" && index+1 < len(os.Args) {
			milliseconds, errorValue := strconv.Atoi(os.Args[index+1])
			if errorValue == nil && milliseconds > 0 {
				return time.Duration(milliseconds) * time.Millisecond
			}
		}
	}
	return 0
}

func clip(value string, width int) string {
	runes := []rune(value)
	if width < 0 {
		return ""
	}
	if len(runes) <= width {
		return value
	}
	return string(runes[:width])
}

func progressBar(value int, width int) string {
	if width < 4 {
		width = 4
	}
	filled := (width*value + 50) / 100
	return strings.Repeat("#", filled) + strings.Repeat(".", width-filled)
}

func paletteLine(frame int, width int) string {
	cells := (width - 10) / 3
	if cells < 1 {
		cells = 1
	}
	if cells > 16 {
		cells = 16
	}
	var result strings.Builder
	result.WriteString("ANSI-16  ")
	for index := 0; index < cells; index++ {
		color := (index + frame/3) % 16
		fmt.Fprintf(&result, "\x1b[48;5;%dm  \x1b[0m ", color)
	}
	return result.String()
}

func gradientLine(frame int, width int) string {
	cells := (width - 10) / 2
	if cells < 1 {
		cells = 1
	}
	if cells > 32 {
		cells = 32
	}
	var result strings.Builder
	result.WriteString("RGB      ")
	for index := 0; index < cells; index++ {
		hue := (index*11 + frame*4) % 256
		fmt.Fprintf(&result, "\x1b[48;2;%d;%d;%dm  \x1b[0m", hue, 255-hue, (hue*3)%256)
	}
	return result.String()
}

func render(frame int, startedAt time.Time, paused bool, diagnosticsSent int) (int, int) {
	columns, rows := terminalSize()
	phase := phases[(frame/25)%len(phases)]
	lines := []string{
		fmt.Sprintf("\x1b[1;36mTTYGLASS STRESS TUI\x1b[0m | %s | frame %d | %.1fs", language, frame, time.Since(startedAt).Seconds()),
		strings.Repeat("-", columns),
		fmt.Sprintf("viewport %dx%d | phase: %s | diagnostics: %d | %s", columns, rows, phase, diagnosticsSent, map[bool]string{true: "PAUSED", false: "RUNNING"}[paused]),
		paletteLine(frame, columns),
		gradientLine(frame, columns),
		clip("Wide glyphs: zażółć gęślą jaźń | 日本語 | λ | box: +---+ | combining: e\u0301", columns),
		"",
	}

	tableRows := rows - len(lines) - 2
	if tableRows < 0 {
		tableRows = 0
	}
	for index := 0; index < tableRows; index++ {
		progress := (frame*3 + index*13) % 101
		latency := (frame*17 + index*29) % 997
		state := "\x1b[32mOK  \x1b[0m"
		if index%7 == 0 {
			state = "\x1b[33mBUSY\x1b[0m"
		}
		barWidth := columns - 47
		if barWidth > 28 {
			barWidth = 28
		}
		lines = append(lines, fmt.Sprintf("%03d worker-%02d %s [%s] %3d ms", index+1, index%12, state, progressBar(progress, barWidth), latency))
	}
	lines = append(lines, strings.Repeat("-", columns))
	lines = append(lines, clip("q quit | p pause | b diagnostic burst | d diagnostic | r redraw (press Enter)", columns))

	if len(lines) > rows {
		lines = lines[:rows]
	}
	var screen strings.Builder
	screen.WriteString("\x1b[H")
	for index, line := range lines {
		screen.WriteString("\x1b[2K")
		screen.WriteString(line)
		if index != len(lines)-1 {
			screen.WriteString("\r\n")
		}
	}
	fmt.Print(screen.String())
	return columns, rows
}

func runDiagnostics(requests <-chan diagnosticRequest) {
	endpoint := os.Getenv("TTYGLASS_DIAGNOSTICS_URL")
	token := os.Getenv("TTYGLASS_DIAGNOSTICS_TOKEN")
	client := &http.Client{Timeout: time.Second}
	for item := range requests {
		if endpoint == "" || token == "" {
			continue
		}
		body, errorValue := json.Marshal(diagnosticRecord{
			Source: source, Level: item.level, Event: item.event,
			Message: language + " emitted " + item.event, Fields: item.fields,
		})
		if errorValue != nil {
			continue
		}
		request, errorValue := http.NewRequest(http.MethodPost, endpoint, bytes.NewReader(body))
		if errorValue != nil {
			continue
		}
		request.Header.Set("Authorization", "Bearer "+token)
		request.Header.Set("Content-Type", "application/json")
		response, errorValue := client.Do(request)
		if errorValue == nil {
			response.Body.Close()
		}
	}
}

func main() {
	duration := durationFromArguments()
	startedAt := time.Now()
	frame := 0
	diagnosticsSent := 0
	paused := false
	columns, rows := terminalSize()
	previousSize := fmt.Sprintf("%dx%d", columns, rows)
	diagnostics := make(chan diagnosticRequest, 64)
	commands := make(chan string, 8)
	go runDiagnostics(diagnostics)
	go func() {
		scanner := bufio.NewScanner(os.Stdin)
		for scanner.Scan() {
			commands <- strings.TrimSpace(scanner.Text())
		}
	}()
	emit := func(event string, level string, fields map[string]any) {
		diagnosticsSent++
		columns, rows := terminalSize()
		completeFields := map[string]any{"frame": frame, "columns": columns, "rows": rows}
		for key, value := range fields {
			completeFields[key] = value
		}
		select {
		case diagnostics <- diagnosticRequest{event: event, level: level, fields: completeFields}:
		default:
		}
	}

	fmt.Print("\x1b[?1049h\x1b[2J\x1b[H\x1b[?25l")
	defer fmt.Print("\x1b[?25h\x1b[?1049l")
	emit("fixture.ready", "info", map[string]any{"standardLibrary": true})
	renderTicker := time.NewTicker(100 * time.Millisecond)
	diagnosticTicker := time.NewTicker(500 * time.Millisecond)
	defer renderTicker.Stop()
	defer diagnosticTicker.Stop()

	for {
		select {
		case <-renderTicker.C:
			if !paused {
				frame++
			}
			columns, rows = terminalSize()
			size := fmt.Sprintf("%dx%d", columns, rows)
			if size != previousSize {
				previousSize = size
				fmt.Print("\x1b[2J")
				emit("viewport.changed", "debug", map[string]any{"size": size})
			}
			render(frame, startedAt, paused, diagnosticsSent)
			if duration > 0 && time.Since(startedAt) >= duration {
				emit("fixture.stopped", "info", nil)
				return
			}
		case <-diagnosticTicker.C:
			emit("fixture.heartbeat", levels[diagnosticsSent%len(levels)], map[string]any{"phase": phases[(frame/25)%len(phases)]})
		case command := <-commands:
			switch command {
			case "q":
				emit("fixture.stopped", "info", nil)
				return
			case "p":
				paused = !paused
			case "b":
				for index := 0; index < 12; index++ {
					emit("burst.item", levels[index%len(levels)], map[string]any{"index": index})
				}
			case "d":
				emit("input.manual", "info", nil)
			case "r":
				render(frame, startedAt, paused, diagnosticsSent)
			}
		}
	}
}

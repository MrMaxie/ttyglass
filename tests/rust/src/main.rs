use std::env;
use std::fmt::Write as FormatWrite;
use std::io::{Read, Write};
use std::net::{TcpStream, ToSocketAddrs};
use std::sync::mpsc::{self, Receiver, SyncSender};
use std::thread;
use std::time::{Duration, Instant};

const LANGUAGE: &str = "Rust";
const SOURCE: &str = "stress-rust";
const LEVELS: [&str; 5] = ["trace", "debug", "info", "warn", "error"];
const PHASES: [&str; 4] = [
    "full redraw",
    "rapid counters",
    "palette sweep",
    "wide glyphs",
];

struct Diagnostic {
    event: &'static str,
    level: &'static str,
    fields: String,
}

fn duration_from_arguments() -> Option<Duration> {
    let arguments: Vec<String> = env::args().collect();
    arguments.windows(2).find_map(|pair| {
        if pair[0] != "--duration-ms" {
            return None;
        }
        pair[1]
            .parse::<u64>()
            .ok()
            .filter(|value| *value > 0)
            .map(Duration::from_millis)
    })
}

fn clip(value: &str, width: usize) -> String {
    value.chars().take(width).collect()
}

fn progress_bar(value: usize, width: usize) -> String {
    let safe_width = width.max(4);
    let filled = (safe_width * value + 50) / 100;
    format!("{}{}", "#".repeat(filled), ".".repeat(safe_width - filled))
}

fn palette_line(frame: usize, width: usize) -> String {
    let cells = width
        .saturating_sub(10)
        .checked_div(3)
        .unwrap_or(1)
        .clamp(1, 16);
    let mut result = String::from("ANSI-16  ");
    for index in 0..cells {
        let color = (index + frame / 3) % 16;
        let _ = write!(result, "\x1b[48;5;{color}m  \x1b[0m ");
    }
    result
}

fn gradient_line(frame: usize, width: usize) -> String {
    let cells = width
        .saturating_sub(10)
        .checked_div(2)
        .unwrap_or(1)
        .clamp(1, 32);
    let mut result = String::from("RGB      ");
    for index in 0..cells {
        let hue = (index * 11 + frame * 4) % 256;
        let _ = write!(
            result,
            "\x1b[48;2;{hue};{};{}m  \x1b[0m",
            255 - hue,
            (hue * 3) % 256
        );
    }
    result
}

fn render(
    frame: usize,
    started_at: Instant,
    paused: bool,
    diagnostics_sent: usize,
) -> (usize, usize) {
    let (columns, rows) = terminal_size();
    let phase = PHASES[(frame / 25) % PHASES.len()];
    let state = if paused { "PAUSED" } else { "RUNNING" };
    let mut lines = vec![
        format!(
            "\x1b[1;36mTTYGLASS STRESS TUI\x1b[0m | {LANGUAGE} | frame {frame} | {:.1}s",
            started_at.elapsed().as_secs_f64()
        ),
        "-".repeat(columns),
        format!(
            "viewport {columns}x{rows} | phase: {phase} | diagnostics: {diagnostics_sent} | {state}"
        ),
        palette_line(frame, columns),
        gradient_line(frame, columns),
        clip(
            "Wide glyphs: zażółć gęślą jaźń | 日本語 | λ | box: +---+ | combining: e\u{301}",
            columns,
        ),
        String::new(),
    ];

    let table_rows = rows.saturating_sub(lines.len() + 2);
    for index in 0..table_rows {
        let progress = (frame * 3 + index * 13) % 101;
        let latency = (frame * 17 + index * 29) % 997;
        let state = if index % 7 == 0 {
            "\x1b[33mBUSY\x1b[0m"
        } else {
            "\x1b[32mOK  \x1b[0m"
        };
        let bar_width = columns.saturating_sub(47).clamp(4, 28);
        lines.push(format!(
            "{:03} worker-{:02} {state} [{}] {latency:3} ms",
            index + 1,
            index % 12,
            progress_bar(progress, bar_width)
        ));
    }
    lines.push("-".repeat(columns));
    lines.push(clip(
        "q quit | p pause | b diagnostic burst | d diagnostic | r redraw (press Enter)",
        columns,
    ));
    lines.truncate(rows);

    let mut screen = String::from("\x1b[H");
    for (index, line) in lines.iter().enumerate() {
        screen.push_str("\x1b[2K");
        screen.push_str(line);
        if index + 1 != lines.len() {
            screen.push_str("\r\n");
        }
    }
    print!("{screen}");
    let _ = std::io::stdout().flush();
    (columns, rows)
}

fn parse_endpoint(endpoint: &str) -> Option<(String, u16, String)> {
    let remainder = endpoint.strip_prefix("http://")?;
    let (authority, path) = remainder
        .split_once('/')
        .map_or((remainder, "/"), |(host, path)| (host, path));
    let (host, port) = authority.rsplit_once(':')?;
    if host != "127.0.0.1" && host != "localhost" {
        return None;
    }
    Some((host.to_string(), port.parse().ok()?, format!("/{path}")))
}

fn send_diagnostic(endpoint: &str, token: &str, item: Diagnostic) {
    let Some((host, port, path)) = parse_endpoint(endpoint) else {
        return;
    };
    let Some(address) = (host.as_str(), port)
        .to_socket_addrs()
        .ok()
        .and_then(|mut items| items.next())
    else {
        return;
    };
    let Ok(mut stream) = TcpStream::connect_timeout(&address, Duration::from_secs(1)) else {
        return;
    };
    let _ = stream.set_write_timeout(Some(Duration::from_secs(1)));
    let body = format!(
        "{{\"source\":\"{SOURCE}\",\"level\":\"{}\",\"event\":\"{}\",\"message\":\"{LANGUAGE} emitted {}\",\"fields\":{{{}}}}}",
        item.level, item.event, item.event, item.fields
    );
    let request = format!(
        "POST {path} HTTP/1.1\r\nHost: {host}:{port}\r\nAuthorization: Bearer {token}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len()
    );
    let _ = stream.write_all(request.as_bytes());
}

fn run_diagnostics(receiver: Receiver<Diagnostic>) {
    let Ok(endpoint) = env::var("TTYGLASS_DIAGNOSTICS_URL") else {
        return;
    };
    let Ok(token) = env::var("TTYGLASS_DIAGNOSTICS_TOKEN") else {
        return;
    };
    for item in receiver {
        send_diagnostic(&endpoint, &token, item);
    }
}

fn emit(
    sender: &SyncSender<Diagnostic>,
    diagnostics_sent: &mut usize,
    frame: usize,
    event: &'static str,
    level: &'static str,
    extra_fields: &str,
) {
    *diagnostics_sent += 1;
    let (columns, rows) = terminal_size();
    let separator = if extra_fields.is_empty() { "" } else { "," };
    let fields =
        format!("\"frame\":{frame},\"columns\":{columns},\"rows\":{rows}{separator}{extra_fields}");
    let _ = sender.try_send(Diagnostic {
        event,
        level,
        fields,
    });
}

fn input_channel() -> Receiver<u8> {
    let (sender, receiver) = mpsc::channel();
    thread::spawn(move || {
        for byte in std::io::stdin().lock().bytes().flatten() {
            if sender.send(byte).is_err() {
                return;
            }
        }
    });
    receiver
}

fn main() {
    let duration = duration_from_arguments();
    let started_at = Instant::now();
    let input = input_channel();
    let (diagnostic_sender, diagnostic_receiver) = mpsc::sync_channel(64);
    thread::spawn(move || run_diagnostics(diagnostic_receiver));
    let mut frame = 0usize;
    let mut diagnostics_sent = 0usize;
    let mut paused = false;
    let mut previous_size = terminal_size();
    let mut last_diagnostic = Instant::now();
    let mut last_render = Instant::now() - Duration::from_millis(100);

    print!("\x1b[?1049h\x1b[2J\x1b[H\x1b[?25l");
    emit(
        &diagnostic_sender,
        &mut diagnostics_sent,
        frame,
        "fixture.ready",
        "info",
        "\"standardLibrary\":true",
    );

    loop {
        if last_render.elapsed() >= Duration::from_millis(100) {
            last_render = Instant::now();
            if !paused {
                frame += 1;
            }
            let size = terminal_size();
            if size != previous_size {
                previous_size = size;
                print!("\x1b[2J");
                emit(
                    &diagnostic_sender,
                    &mut diagnostics_sent,
                    frame,
                    "viewport.changed",
                    "debug",
                    &format!("\"size\":\"{}x{}\"", size.0, size.1),
                );
            }
            render(frame, started_at, paused, diagnostics_sent);
        }

        if last_diagnostic.elapsed() >= Duration::from_millis(500) {
            last_diagnostic = Instant::now();
            let level = LEVELS[diagnostics_sent % LEVELS.len()];
            let phase = PHASES[(frame / 25) % PHASES.len()];
            emit(
                &diagnostic_sender,
                &mut diagnostics_sent,
                frame,
                "fixture.heartbeat",
                level,
                &format!("\"phase\":\"{phase}\""),
            );
        }

        while let Ok(key) = input.try_recv() {
            match key {
                b'q' => {
                    emit(
                        &diagnostic_sender,
                        &mut diagnostics_sent,
                        frame,
                        "fixture.stopped",
                        "info",
                        "",
                    );
                    print!("\x1b[?25h\x1b[?1049l");
                    return;
                }
                b'p' => paused = !paused,
                b'b' => {
                    for index in 0..12 {
                        emit(
                            &diagnostic_sender,
                            &mut diagnostics_sent,
                            frame,
                            "burst.item",
                            LEVELS[index % LEVELS.len()],
                            &format!("\"index\":{index}"),
                        );
                    }
                }
                b'd' => emit(
                    &diagnostic_sender,
                    &mut diagnostics_sent,
                    frame,
                    "input.manual",
                    "info",
                    "",
                ),
                b'r' => {
                    render(frame, started_at, paused, diagnostics_sent);
                }
                _ => {}
            }
        }

        if duration.is_some_and(|limit| started_at.elapsed() >= limit) {
            emit(
                &diagnostic_sender,
                &mut diagnostics_sent,
                frame,
                "fixture.stopped",
                "info",
                "",
            );
            print!("\x1b[?25h\x1b[?1049l");
            return;
        }
        thread::sleep(Duration::from_millis(5));
    }
}

#[cfg(windows)]
fn terminal_size() -> (usize, usize) {
    use std::ffi::c_void;

    #[repr(C)]
    struct Coord {
        x: i16,
        y: i16,
    }

    #[repr(C)]
    struct SmallRect {
        left: i16,
        top: i16,
        right: i16,
        bottom: i16,
    }

    #[repr(C)]
    struct ConsoleScreenBufferInfo {
        size: Coord,
        cursor_position: Coord,
        attributes: u16,
        window: SmallRect,
        maximum_window_size: Coord,
    }

    #[link(name = "Kernel32")]
    unsafe extern "system" {
        fn GetStdHandle(standard_handle: u32) -> *mut c_void;
        fn GetConsoleScreenBufferInfo(
            console_output: *mut c_void,
            info: *mut ConsoleScreenBufferInfo,
        ) -> i32;
    }

    let mut info = ConsoleScreenBufferInfo {
        size: Coord { x: 0, y: 0 },
        cursor_position: Coord { x: 0, y: 0 },
        attributes: 0,
        window: SmallRect {
            left: 0,
            top: 0,
            right: 0,
            bottom: 0,
        },
        maximum_window_size: Coord { x: 0, y: 0 },
    };
    // SAFETY: both calls use the documented console output handle and a valid writable structure.
    let result = unsafe {
        let handle = GetStdHandle((-11i32) as u32);
        GetConsoleScreenBufferInfo(handle, &mut info)
    };
    if result == 0 {
        return (100, 30);
    }
    (
        usize::try_from(info.window.right - info.window.left + 1).unwrap_or(100),
        usize::try_from(info.window.bottom - info.window.top + 1).unwrap_or(30),
    )
}

#[cfg(unix)]
fn terminal_size() -> (usize, usize) {
    use std::os::fd::AsRawFd;

    #[repr(C)]
    struct WindowSize {
        rows: u16,
        columns: u16,
        x_pixel: u16,
        y_pixel: u16,
    }

    unsafe extern "C" {
        fn ioctl(file_descriptor: i32, request: usize, ...) -> i32;
    }

    #[cfg(any(target_os = "linux", target_os = "android"))]
    const TIOCGWINSZ: usize = 0x5413;
    #[cfg(any(
        target_os = "macos",
        target_os = "ios",
        target_os = "freebsd",
        target_os = "openbsd",
        target_os = "netbsd"
    ))]
    const TIOCGWINSZ: usize = 0x40087468;

    let mut size = WindowSize {
        rows: 0,
        columns: 0,
        x_pixel: 0,
        y_pixel: 0,
    };
    // SAFETY: ioctl receives stdout's valid descriptor and a writable winsize structure.
    let result = unsafe { ioctl(std::io::stdout().as_raw_fd(), TIOCGWINSZ, &mut size) };
    if result == 0 && size.columns > 0 && size.rows > 0 {
        (usize::from(size.columns), usize::from(size.rows))
    } else {
        (100, 30)
    }
}

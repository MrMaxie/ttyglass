export interface LanguageExample {
  id: string;
  label: string;
  fileName: string;
  language: 'javascript' | 'python' | 'go' | 'rust' | 'nim' | 'ruby';
  command: string;
  code: string;
  focusLines: number[];
  setupFile?: {
    fileName: string;
    language: 'toml';
    code: string;
  };
  fullExampleUrl?: string;
}

export const languageExamples: LanguageExample[] = [
  {
    id: 'node',
    label: 'Node.js',
    fileName: 'app.js',
    language: 'javascript',
    command: 'npx ttyglass --open -- node app.js',
    focusLines: [1, 2, 16],
    code: String.raw`const endpoint = process.env.TTYGLASS_DIAGNOSTICS_URL;
const token = process.env.TTYGLASS_DIAGNOSTICS_TOKEN;

function diagnostic(event, fields = {}) {
  if (!endpoint || !token) return;
  void fetch(endpoint, {
    method: 'POST',
    headers: {
      Authorization: 'Bearer ' + token,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ source: 'demo-node', level: 'info', event, fields }),
  }).catch(() => {});
}

diagnostic('dashboard.ready', { screen: 'orders' });

let frame = 0;

setInterval(() => {
  process.stdout.write('\x1b[2J\x1b[H');
  console.log('Orders dashboard\n');
  console.log('Processed: ' + frame++);
}, 250);`,
    fullExampleUrl: 'https://github.com/MrMaxie/ttyglass/blob/master/tests/typescript/main.ts',
  },
  {
    id: 'python',
    label: 'Python',
    fileName: 'app.py',
    language: 'python',
    command: 'npx ttyglass --open -- python app.py',
    focusLines: [8, 9, 29],
    code: String.raw`import json
import os
import time
import urllib.request


def diagnostic(event, fields=None):
    endpoint = os.environ.get("TTYGLASS_DIAGNOSTICS_URL")
    token = os.environ.get("TTYGLASS_DIAGNOSTICS_TOKEN")
    if not endpoint or not token:
        return

    body = json.dumps({
        "source": "demo-python",
        "level": "info",
        "event": event,
        "fields": fields or {},
    }).encode()
    request = urllib.request.Request(endpoint, data=body, headers={
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    })
    try:
        urllib.request.urlopen(request, timeout=1).close()
    except OSError:
        pass


diagnostic("dashboard.ready", {"screen": "orders"})

count = 0
while True:
    print("\033[2J\033[H", end="")
    print(f"Orders dashboard\n\nProcessed: {count}", flush=True)
    count += 1
    time.sleep(0.25)`,
  },
  {
    id: 'go',
    label: 'Go',
    fileName: 'main.go',
    language: 'go',
    command: 'npx ttyglass --open -- go run main.go',
    focusLines: [12, 13, 28],
    code: String.raw`package main

import (
  "fmt"
  "net/http"
  "os"
  "strings"
  "time"
)

func diagnostic() {
  endpoint := os.Getenv("TTYGLASS_DIAGNOSTICS_URL")
  token := os.Getenv("TTYGLASS_DIAGNOSTICS_TOKEN")
  if endpoint == "" || token == "" {
    return
  }

  body := strings.NewReader("{\"source\":\"demo-go\",\"level\":\"info\",\"event\":\"dashboard.ready\"}")
  request, _ := http.NewRequest(http.MethodPost, endpoint, body)
  request.Header.Set("Authorization", "Bearer "+token)
  request.Header.Set("Content-Type", "application/json")
  if response, err := (&http.Client{Timeout: time.Second}).Do(request); err == nil {
    response.Body.Close()
  }
}

func main() {
  diagnostic()
  for count := 0; ; count++ {
    fmt.Print("\x1b[2J\x1b[HOrders dashboard\n\n")
    fmt.Printf("Processed: %d\n", count)
    time.Sleep(250 * time.Millisecond)
  }
}`,
    fullExampleUrl: 'https://github.com/MrMaxie/ttyglass/blob/master/tests/go/main.go',
  },
  {
    id: 'rust',
    label: 'Rust',
    fileName: 'src/main.rs',
    language: 'rust',
    command: 'npx ttyglass --open -- cargo run',
    focusLines: [4, 5, 6, 7, 28],
    setupFile: {
      fileName: 'Cargo.toml',
      language: 'toml',
      code: `[package]
name = "ttyglass-demo"
version = "0.1.0"
edition = "2024"`,
    },
    code: String.raw`use std::{env, io::{self, Write}, net::TcpStream, thread, time::Duration};

fn diagnostic() {
    let (Ok(endpoint), Ok(token)) = (
        env::var("TTYGLASS_DIAGNOSTICS_URL"),
        env::var("TTYGLASS_DIAGNOSTICS_TOKEN"),
    ) else {
        return;
    };
    let Some(url) = endpoint.strip_prefix("http://") else {
        return;
    };
    let Some((authority, path)) = url.split_once('/') else {
        return;
    };
    let Ok(mut stream) = TcpStream::connect(authority) else {
        return;
    };
    let body = r#"{"source":"demo-rust","level":"info","event":"dashboard.ready"}"#;
    let request = format!(
        "POST /{path} HTTP/1.1\r\nHost: {authority}\r\nAuthorization: Bearer {token}\r\nContent-Type: application/json\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len(),
    );
    let _ = stream.write_all(request.as_bytes());
}

fn main() {
    diagnostic();
    for count in 0.. {
        print!("\x1b[2J\x1b[HOrders dashboard\n\nProcessed: {count}\n");
        io::stdout().flush().unwrap();
        thread::sleep(Duration::from_millis(250));
    }
}`,
    fullExampleUrl: 'https://github.com/MrMaxie/ttyglass/blob/master/tests/rust/src/main.rs',
  },
  {
    id: 'nim',
    label: 'Nim',
    fileName: 'app.nim',
    language: 'nim',
    command: 'npx ttyglass --open -- nim r app.nim',
    focusLines: [4, 5, 24],
    code: String.raw`import std/[httpclient, json, os, strformat]

proc diagnostic() =
  let endpoint = getEnv("TTYGLASS_DIAGNOSTICS_URL")
  let token = getEnv("TTYGLASS_DIAGNOSTICS_TOKEN")
  if endpoint.len == 0 or token.len == 0: return

  let client = newHttpClient(timeout = 1000)
  defer: client.close()
  let headers = newHttpHeaders({
    "Authorization": "Bearer " & token,
    "Content-Type": "application/json",
  })
  let body = $(%*{
    "source": "demo-nim",
    "level": "info",
    "event": "dashboard.ready",
  })
  try:
    discard client.request(endpoint, HttpPost, body, headers)
  except CatchableError:
    discard

diagnostic()

var count = 0
while true:
  stdout.write("\e[2J\e[H")
  stdout.write(&"Orders dashboard\n\nProcessed: {count}\n")
  stdout.flushFile()
  inc count
  sleep(250)`,
    fullExampleUrl: 'https://github.com/MrMaxie/ttyglass/blob/master/tests/nim/main.nim',
  },
  {
    id: 'ruby',
    label: 'Ruby',
    fileName: 'app.rb',
    language: 'ruby',
    command: 'npx ttyglass --open -- ruby app.rb',
    focusLines: [6, 7, 25],
    code: String.raw`require 'json'
require 'net/http'
require 'uri'

def diagnostic
  endpoint = ENV['TTYGLASS_DIAGNOSTICS_URL']
  token = ENV['TTYGLASS_DIAGNOSTICS_TOKEN']
  return unless endpoint && token

  uri = URI(endpoint)
  request = Net::HTTP::Post.new(uri)
  request['Authorization'] = "Bearer #{token}"
  request['Content-Type'] = 'application/json'
  request.body = JSON.generate(
    source: 'demo-ruby', level: 'info', event: 'dashboard.ready'
  )
  client = Net::HTTP.new(uri.host, uri.port)
  client.open_timeout = 1
  client.read_timeout = 1
  client.request(request)
rescue StandardError
  nil
end

diagnostic

count = 0

loop do
  print "\e[2J\e[HOrders dashboard\n\nProcessed: #{count}\n"
  STDOUT.flush
  count += 1
  sleep 0.25
end`,
    fullExampleUrl: 'https://github.com/MrMaxie/ttyglass/blob/master/tests/ruby/main.rb',
  },
];

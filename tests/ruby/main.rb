# frozen_string_literal: true

require 'io/console'
require 'json'
require 'net/http'
require 'uri'

LANGUAGE = 'Ruby'
SOURCE = 'stress-ruby'
LEVELS = %w[trace debug info warn error].freeze
PHASES = ['full redraw', 'rapid counters', 'palette sweep', 'wide glyphs'].freeze

def duration_from_arguments
  index = ARGV.index('--duration-ms')
  return 0 unless index && ARGV[index + 1]

  milliseconds = Integer(ARGV[index + 1], exception: false)
  milliseconds&.positive? ? milliseconds / 1000.0 : 0
end

def terminal_size
  rows, columns = STDOUT.winsize
  [columns.positive? ? columns : 100, rows.positive? ? rows : 30]
rescue Errno::ENOTTY, NoMethodError
  [100, 30]
end

def clip(value, width)
  value.each_char.take([width, 0].max).join
end

def progress_bar(value, width)
  safe_width = [width, 4].max
  filled = ((safe_width * value) + 50) / 100
  ('#' * filled) + ('.' * (safe_width - filled))
end

def palette_line(frame, width)
  cells = [[(width - 10) / 3, 1].max, 16].min
  colors = cells.times.map do |index|
    color = (index + (frame / 3)) % 16
    "\e[48;5;#{color}m  \e[0m "
  end
  "ANSI-16  #{colors.join}"
end

def gradient_line(frame, width)
  cells = [[(width - 10) / 2, 1].max, 32].min
  colors = cells.times.map do |index|
    hue = ((index * 11) + (frame * 4)) % 256
    "\e[48;2;#{hue};#{255 - hue};#{(hue * 3) % 256}m  \e[0m"
  end
  "RGB      #{colors.join}"
end

def render(frame, started_at, paused, diagnostics_sent)
  columns, rows = terminal_size
  phase = PHASES[(frame / 25) % PHASES.length]
  state = paused ? 'PAUSED' : 'RUNNING'
  lines = [
    format("\e[1;36mTTYGLASS STRESS TUI\e[0m | %s | frame %d | %.1fs", LANGUAGE, frame, monotonic_time - started_at),
    '-' * columns,
    "viewport #{columns}x#{rows} | phase: #{phase} | diagnostics: #{diagnostics_sent} | #{state}",
    palette_line(frame, columns),
    gradient_line(frame, columns),
    clip('Wide glyphs: zażółć gęślą jaźń | 日本語 | λ | box: +---+ | combining: é', columns),
    ''
  ]

  [rows - lines.length - 2, 0].max.times do |index|
    progress = ((frame * 3) + (index * 13)) % 101
    latency = ((frame * 17) + (index * 29)) % 997
    worker_state = (index % 7).zero? ? "\e[33mBUSY\e[0m" : "\e[32mOK  \e[0m"
    bar_width = [[columns - 47, 4].max, 28].min
    lines << format('%03d worker-%02d %s [%s] %3d ms', index + 1, index % 12, worker_state, progress_bar(progress, bar_width), latency)
  end

  lines << ('-' * columns)
  lines << clip('q quit | p pause | b diagnostic burst | d diagnostic | r redraw', columns)
  lines = lines.take(rows)

  print "\e[H"
  lines.each_with_index do |line, index|
    print "\e[2K#{line}"
    print "\r\n" unless index == lines.length - 1
  end
  [columns, rows]
end

def monotonic_time
  Process.clock_gettime(Process::CLOCK_MONOTONIC)
end

def available_input
  return '' unless IO.select([STDIN], nil, nil, 0)

  STDIN.readpartial(64)
rescue EOFError, IOError, SystemCallError
  ''
end

def send_diagnostic(endpoint, token, diagnostic)
  return if endpoint.nil? || endpoint.empty? || token.nil? || token.empty?

  uri = URI(endpoint)
  request = Net::HTTP::Post.new(uri)
  request['Authorization'] = "Bearer #{token}"
  request['Content-Type'] = 'application/json'
  request.body = JSON.generate(diagnostic)

  client = Net::HTTP.new(uri.host, uri.port)
  client.open_timeout = 1
  client.read_timeout = 1
  client.request(request)
rescue StandardError
  nil
end

def run
  duration = duration_from_arguments
  started_at = monotonic_time
  endpoint = ENV.fetch('TTYGLASS_DIAGNOSTICS_URL', '')
  token = ENV.fetch('TTYGLASS_DIAGNOSTICS_TOKEN', '')
  diagnostics = SizedQueue.new(64)

  diagnostics_thread = Thread.new do
    loop do
      diagnostic = diagnostics.pop
      break if diagnostic.nil?

      send_diagnostic(endpoint, token, diagnostic)
    end
  end

  frame = 0
  diagnostics_sent = 0
  paused = false
  previous_size = terminal_size
  last_render = started_at - 1
  last_diagnostic = started_at
  running = true

  emit = lambda do |event, level, extra = {}|
    diagnostics_sent += 1
    columns, rows = terminal_size
    item = {
      source: SOURCE,
      level: level,
      event: event,
      message: "#{LANGUAGE} emitted #{event}",
      fields: { frame: frame, columns: columns, rows: rows }.merge(extra)
    }
    diagnostics.push(item, true)
  rescue ThreadError
    nil
  end

  print "\e[?1049h\e[2J\e[H\e[?25l"
  emit.call('fixture.ready', 'info', standardLibrary: true)

  while running
    now = monotonic_time
    if now - last_render >= 0.1
      last_render = now
      frame += 1 unless paused
      current_size = terminal_size
      if current_size != previous_size
        previous_size = current_size
        print "\e[2J"
        emit.call('viewport.changed', 'debug', size: current_size.join('x'))
      end
      render(frame, started_at, paused, diagnostics_sent)
    end

    if now - last_diagnostic >= 0.5
      last_diagnostic = now
      emit.call('fixture.heartbeat', LEVELS[diagnostics_sent % LEVELS.length], phase: PHASES[(frame / 25) % PHASES.length])
    end

    available_input.each_char do |key|
      case key
      when 'q', "\u0003"
        emit.call('fixture.stopped', 'info')
        running = false
      when 'p', ' '
        paused = !paused
      when 'b'
        12.times { |index| emit.call('burst.item', LEVELS[index % LEVELS.length], index: index) }
      when 'd'
        emit.call('input.manual', 'info')
      when 'r'
        render(frame, started_at, paused, diagnostics_sent)
      end
    end

    if duration.positive? && now - started_at >= duration
      emit.call('fixture.stopped', 'info')
      running = false
    end
    sleep 0.005
  end
ensure
  diagnostics&.push(nil)
  diagnostics_thread&.join(1)
  print "\e[?25h\e[?1049l"
  STDOUT.flush
end

run if $PROGRAM_NAME == __FILE__

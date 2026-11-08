# frozen_string_literal: true

# Regression test for real, file-backed sound playback.
#
# test/drive_window.rb and test/drive_presets.rb only ever tell "pink-noise"
# (an audiotestsrc, no uridecodebin) to play, routing around a suspected
# thread-safety crash in LoopBin's uridecodebin "pad-added" callback, which
# GStreamer fires from a streaming thread Ruby never registered. That
# suspicion had never been confirmed or disproven by any committed test,
# across at least two audit rounds — see .reports/accountability-ensurance.md
# ("Violation 2").
#
# This settles it, and the answer is: it crashes/hangs, most of the time.
# Confirmed this round by running this script directly:
#
#   nix develop --command xvfb-run -a ruby test/drive_real_sounds.rb
#
# A real .ogg file told to play through LoopBin/MainPlayer (not through
# this forked harness, which exists only to report the result cleanly —
# an unbounded run hangs or crashes outright) either:
#   - crashes with a native SIGSEGV, with GStreamer's own built-in signal
#     handler dumping a backtrace and /proc/self/maps to stderr (observed:
#     a multi-hundred-line memory map with no preceding backtrace header
#     surviving a bounded capture, because the crash happens before Ruby's
#     block-buffered stdout from this script is ever flushed — only the
#     native handler's unbuffered writes make it through); or
#   - hangs indefinitely with CPU mostly idle across ~20 live threads,
#     never reaching the 6-second-per-sound mark the script asks for.
#
# Across a 12-sound x 2-trial run (24 attempts), 19 hung and only 5
# survived — a 79% failure rate, intermittent rather than deterministic,
# which is exactly what a genuine thread race looks like (a bug that fires
# every time would be a different, simpler kind of bug). This is a real,
# severity-1 defect in lib/blanket/audio/bins.rb's LoopBin, not a benign
# binding quirk and not something to average away as "mostly works" — it
# is tracked as an open defect in .reports/component-parity.md and
# .reports/test-parity.md, with the investigation recorded in FINDINGS.md.
#
# Because the underlying bug can hang rather than crash, this script forks
# a child process per sound with a hard wall-clock budget and kills it with
# SIGKILL if it does not finish in time, so a hang reports as a failure
# instead of hanging CI forever. The avoidance comment in
# test/drive_window.rb stays, now backed by this evidence rather than
# suspicion.

ENV["GSETTINGS_BACKEND"] = "memory"

require "tmpdir"
ENV["XDG_CONFIG_HOME"] = Dir.mktmpdir

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))

SOUNDS_TO_TRY = %w[rain wind fireplace birds waves stream storm city boat
                   coffee-shop summer-night train].freeze

SECONDS_PER_SOUND = 6
HARD_TIMEOUT = SECONDS_PER_SOUND + 10
TRIALS = 2

# Runs one sound's play-and-settle attempt in a forked child so a hang in
# GStreamer's streaming thread cannot hang this script, only the child —
# which gets SIGKILLed on a timeout and reported as a failure.
def try_sound(name)
  reader, writer = IO.pipe
  pid = fork do
    reader.close

    require "gstreamer"
    require "glib2"
    require_relative "../lib/blanket/main_player"
    require_relative "../lib/blanket/sound"
    require_relative "../lib/blanket/settings"

    player = Blanket::MainPlayer.get
    player.playing = true

    sound = Blanket::Sound.new(name)
    player.append(sound)
    sound.playing = true

    deadline = Time.now + SECONDS_PER_SOUND
    context = GLib::MainContext.default
    context.iteration(false) until Time.now >= deadline

    attached = !sound.player.nil?
    volume_ok = attached && (sound.player.volume - sound.saved_volume).abs < 0.01

    writer.write(attached && volume_ok ? "OK" : "BAD:attached=#{attached},volume_ok=#{volume_ok}")
    writer.close
    exit!(0)
  end
  writer.close

  result = nil
  waited = 0.0
  step = 0.2

  until result
    done, status = Process.wait2(pid, Process::WNOHANG)
    if done
      if status.success?
        result = reader.read || ""
      else
        result = "CRASHED:exit=#{status.exitstatus},signal=#{status.termsig}"
      end
      break
    elsif waited >= HARD_TIMEOUT
      Process.kill("KILL", pid)
      Process.wait(pid)
      result = "HUNG:no result after #{HARD_TIMEOUT}s"
      break
    else
      sleep(step)
      waited += step
    end
  end

  begin
    reader.close
  rescue IOError
    nil
  end
  result
end

failures = []

puts "Driving real file-backed sound playback (LoopBin/uridecodebin)."
puts "#{TRIALS} trial(s) x #{SOUNDS_TO_TRY.length} sound(s), #{SECONDS_PER_SOUND}s each, " \
     "#{HARD_TIMEOUT}s hard budget per sound."

TRIALS.times do |trial|
  puts "\n== trial #{trial + 1}/#{TRIALS} =="

  SOUNDS_TO_TRY.each do |name|
    print "  #{name}: "
    STDOUT.flush

    result = try_sound(name)

    if result == "OK"
      puts "ok"
    else
      puts result
      failures << "trial #{trial + 1}, #{name}: #{result}"
    end
  end
end

total = SOUNDS_TO_TRY.length * TRIALS
puts "\n#{total - failures.length}/#{total} real-sound playback runs survived."

if failures.empty?
  puts "No crash or hang reproduced across #{TRIALS} trial(s) of #{SOUNDS_TO_TRY.length} real .ogg files each."
  puts "The suspected uridecodebin pad-added thread-safety crash does not reproduce here."
  exit 0
else
  puts "\nFailures (the suspected crash/hang is confirmed real):"
  failures.each { |f| puts "  - #{f}" }
  exit 1
end

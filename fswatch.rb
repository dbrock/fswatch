#!/usr/bin/env ruby

# Usage: fswatch [-t FILE-EXTENSION] DIRECTORIES...
# This will print one line to stdout for every change.

require "rubygems"
require "fssm"

class FSSM::Backends::FSEvents
  alias :__fswatch_run :run
  def run
    begin
      __fswatch_run
    ensure
      @fsevents.each(&:stop)
    end
  end
end

module FSWatch
  class Watcher
    def initialize(options)
      @directories = options[:directories] or fail "Need `:directories'."

      if options[:glob]
        @glob = glob
      elsif options[:extension]
        @glob = "**/[^.]*.#{options[:extension]}"
      else
        @glob = "**/*"
      end

      @listeners = []
    end

    attr_reader :directories
    attr_reader :glob

    def path
      @directories * ":"
    end

    def run!
      until_stopped { watch! }
    end

    def stop!
      @stopped = true
      interrupt_monitor!
    end
    
    def on_change(&block)
      @listeners << block
    end

   private

    def watch!
      begin
        get_current_monitor.run
      rescue
        # I know from experience that FSSM throws all kinds of
        # one-off errors that are fixed by simply retrying.
      end
    end

    # We need to build a new monitor each time we restart in order to
    # watch any newly created files.
    def get_current_monitor
      FSSM::Monitor.new.tap do |monitor|
        @directories.each do |directory|
          monitor.path(directory, @glob) do |watch|
            watch.update { handle_change! }
            watch.create { handle_change! ; interrupt_monitor! }
            watch.delete { handle_change! ; interrupt_monitor! }
          end
        end
      end
    end

    def handle_change!
      @listeners.each { |block| block.call }
    end

    def until_stopped(&block)
      until @stopped
        catch(interrupt_token, &block)
      end
    end

    def interrupt_monitor!
      throw interrupt_token
    end

    def interrupt_token
      :fswatch_interrput
    end
  end

  class Main
    def initialize(*arguments)
      @directories = []

      until arguments.empty?
        case argument = arguments.shift
        when "-t"
          @extension = arguments.shift
        when "--"
          @directories.concat(arguments)
          arguments = []
        when /^-/
          syntax_error!
        else
          @directories << argument
        end
      end

      if @directories.empty?
        syntax_error!
      end
    end

    def syntax_error!
      warn "Usage: fswatch [-t FILE-EXTENSION] DIRECTORIES..."
      warn "This will print one line to stdout for every change."
      exit 1
    end

    def run!
      watcher = Watcher.new \
        :directories => @directories,
        :extension => @extension
      say "Watching `#{watcher.path}' for `#{watcher.glob}'."
      watcher.on_change { handle_change! }
      Signal.trap("INT") { watcher.stop! }
      watcher.run!
    end

    def handle_change!
      say "Change detected."
    end

    def say(message)
      STDOUT.puts "fswatch: [#{timestamp}] #{message}"
      STDOUT.flush
    end

    def timestamp
      Time.now.strftime("%Y-%m-%d %H:%M:%S")
    end
  end
end

FSWatch::Main.new(*ARGV).run!

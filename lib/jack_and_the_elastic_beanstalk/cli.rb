module JackAndTheElasticBeanstalk
  module CLI
    def self.commands
      {
        version: Version,
        stage: Stage,
      }
    end

    class ArgumentParsingError < StandardError; end

    def self.run(argv)
      config_dir = Pathname("jack")

      OptionParser.new do |opts|
        opts.on("--config-dir=DIR") {|dir| config_dir = Pathname(dir) }
      end.order!(argv)

      command_name = argv.shift

      klass = commands[command_name.to_sym]
      if klass
        klass.new(config_dir: config_dir, argv: argv).execute()
      else
        STDOUT.puts "Unknown command: #{command_name}"
        STDOUT.puts "  available commands: #{commands.keys.join(', ')}"
        0
      end
    rescue ArgumentParsingError => exn
      STDOUT.puts "Invalid argument: #{exn.message}"
      1
    end
  end
end

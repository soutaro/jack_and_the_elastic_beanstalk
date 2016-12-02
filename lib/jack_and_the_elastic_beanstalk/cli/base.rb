module JackAndTheElasticBeanstalk
  module CLI
    class Base
      attr_reader :config_dir
      attr_reader :stderr
      attr_reader :stdout
      attr_reader :stdin

      def initialize(config_dir:, argv:, stdin: STDIN, stdout: STDOUT, stderr: STDERR)
        @config_dir = config_dir
        @stdin = stdin
        @stdout = stdout
        @stderr = stderr

        self.parse(argv)
      end

      def runner
        logger = Logger.new(STDERR)
        logger.level = Logger::DEBUG
        @runner ||= Runner.new(stdin: stdin, stdout: stdout, stderr: stderr, logger: logger)
      end

      def config
        @config ||= Config.load(path: config_dir)
      end

      def execute
        run || 0
      end

      def parse(_)

      end
    end
  end
end

module JackAndTheElasticBeanstalk
  class Runner
    attr_reader :stdin
    attr_reader :stdout
    attr_reader :stderr
    attr_reader :paths
    attr_reader :logger

    def initialize(stdin:, stdout:, stderr:, logger: Logger.new(STDERR))
      @stdin = stdin
      @stdout = stdout
      @stderr = stderr
      @paths = [Pathname.pwd]
      @logger = logger
    end

    def chdir(dir)
      paths.push dir
      yield
    ensure
      paths.pop
    end

    def pwd
      paths.last
    end

    def each_line(string, prefix: nil)
      Array(string).flat_map {|s| s.split(/\n/) }.each do |line|
        if prefix
          yield "#{prefix}: #{line}"
        else
          yield line
        end
      end
    end

    def capture3(*commands, options: {}, env: {})
      logger.debug("jeb") { commands.inspect }

      Open3.capture3(env, *commands, { chdir: pwd.to_s }.merge(options)).tap do |out, err, status|
        logger.debug("jeb") { status.inspect }

        each_line(out, prefix: "stdout") do |line|
          logger.debug("jeb") { line }
        end

        each_line(err, prefix: "stderr") do |line|
          logger.debug("jeb") { line }
        end
      end
    end

    def capture3!(*commands, options: {}, env: {})
      out, err, status = capture3(*commands, options: options, env: env)

      unless status.success?
        raise "Faiiled to execute command: #{commands.inspect}"
      end

      [out, err]
    end
  end
end

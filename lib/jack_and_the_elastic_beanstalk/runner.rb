module JackAndTheElasticBeanstalk
  class Runner
    attr_reader :stdin
    attr_reader :stdout
    attr_reader :stderr
    attr_reader :paths

    def initialize(stdin:, stdout:, stderr:)
      @stdin = stdin
      @stdout = stdout
      @stderr = stderr
      @paths = [Pathname.pwd]
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
  end
end

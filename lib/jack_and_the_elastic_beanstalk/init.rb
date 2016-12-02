module JackAndTheElasticBeanstalk
  class Init
    attr_reader :config
    attr_reader :runner

    def initialize(config:, runner:)
      @config = config
      @runner = runner
    end

    def run
      runner.capture3("eb", "init", config.app_name, "-r", config.region, "-p", config.platform)
    end
  end
end

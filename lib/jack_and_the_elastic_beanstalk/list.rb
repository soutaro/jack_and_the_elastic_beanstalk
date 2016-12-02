module JackAndTheElasticBeanstalk
  class List
    attr_reader :config
    attr_reader :runner

    def initialize(config:, runner:)
      @config = config
      @runner = runner
    end

    def run
      stdout, _ = runner.capture3!("eb", "list")
      stdout.lines.map {|line| line.chomp.sub(/\* +/, '') }
    end
  end
end

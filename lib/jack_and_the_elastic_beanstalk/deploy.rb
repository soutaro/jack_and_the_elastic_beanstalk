module JackAndTheElasticBeanstalk
  class Deploy
    attr_reader :config
    attr_reader :runner
    attr_reader :version
    attr_reader :jack_env
    attr_reader :group_name
    attr_reader :worker_name

    def initialize(config:, runner:, version:, jack_env:, worker_name:, group_name:)
      @config = config
      @runner = runner
      @version = version
      @jack_env = jack_env
      @worker_name = worker_name
      @group_name = group_name
    end

    def eb_env_name
      "jeb-#{group_name}-#{worker_name}"
    end

    def type
      config.app_hash[jack_env.to_s][worker_name.to_s]["type"]&.to_sym || :web
    end

    def run
      out, _ = runner.capture3!("eb", "list")
      if out.lines.map {|line| line.chomp.gsub(/\* +/, '') }.include? eb_env_name
        # deploy

      else
        # create
        if type != :worker
          runner.capture3!("eb", "create", eb_env_name)
        else
          runner.capture3!("eb", "create", "-t", "worker", eb_env_name)
        end
      end
    end
  end
end

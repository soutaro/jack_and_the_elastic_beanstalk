module JackAndTheElasticBeanstalk
  class Stage
    attr_reader :config
    attr_reader :jack_name
    attr_reader :eb_name
    attr_reader :output_dir
    attr_reader :runner

    def initialize(config:, jack_name:, eb_name:, output_dir:, runner:)
      @config = config
      @jack_name = jack_name
      @eb_name = eb_name
      @output_dir = output_dir
      @runner = runner
    end

    def run(delete_after:, &block)
      output_dir.mkpath

      export_files
      prepare_envyml
      prepare_ebextensions

      if block_given?
        runner.chdir output_dir, &block
      end

      if delete_after
        output_dir.rmtree
      end
    end

    def export_files

    end

    def prepare_envyml

    end

    def prepare_ebextensions

    end
  end
end

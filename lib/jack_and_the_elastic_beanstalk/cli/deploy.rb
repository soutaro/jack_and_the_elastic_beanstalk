module JackAndTheElasticBeanstalk
  module CLI
    class Deploy < Base
      attr_reader :env
      attr_reader :group

      def parse(argv)
        unless argv.length == 2
          raise ArgumentParsingError, Rainbow("eb deploy env group").red
        end

        @env = argv[0].to_sym
        @group = argv[1].to_sym
      end

      def run
        version = Time.now.strftime("%Y%m%d%H%M")
        p version

        Dir.mktmpdir do |path|
          output_dir = Pathname(path)
          ::JackAndTheElasticBeanstalk::Stage.new(config: config, runner: runner, jack_name: env, output_dir: output_dir).run(delete_after: false) do |worker_name|
            Init.new(config: config, runner: runner).run
            ::JackAndTheElasticBeanstalk::Deploy.new(config: config, runner: runner, jack_env: env, group_name: group, worker_name: worker_name, version: version).run
          end
        end
      end
    end
  end
end

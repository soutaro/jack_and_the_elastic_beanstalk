module JackAndTheElasticBeanstalk
  module CLI
    class Stage < Base
      attr_reader :jack_name
      attr_reader :output_dir

      def parse(argv)
        unless argv.length == 2
          raise ArgumentParsingError, Rainbow("eb stage [jack_name] [output_dir]").red
        end

        jack_name, output_dir = argv

        @jack_name = jack_name.to_sym
        @output_dir = Pathname(output_dir)
      end

      def run
        JackAndTheElasticBeanstalk::Stage.new(config: config, jack_name: jack_name, output_dir: output_dir, runner: runner).run(delete_after: false)
      end
    end
  end
end

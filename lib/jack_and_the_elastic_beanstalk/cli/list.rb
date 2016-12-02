module JackAndTheElasticBeanstalk
  module CLI
    class List < Base
      def parse(argv)
        unless argv.length == 0
          raise ArgumentParsingError, Rainbow("eb list").red
        end
      end

      def run
        Dir.mktmpdir do |dir|
          path = Pathname(dir)
          runner.chdir path do
            JackAndTheElasticBeanstalk::Init.new(config: config, runner: runner).run()
            list = JackAndTheElasticBeanstalk::List.new(config: config, runner: runner).run()

            list.each do |env|
              runner.stdout.puts env
            end
          end
        end

        0
      end
    end
  end
end

module JackAndTheElasticBeanstalk
  module CLI
    class Version < Base
      def run
        stdout.puts "Jack and the Elastic Beanstalk, #{JackAndTheElasticBeanstalk::VERSION}"
      end
    end
  end
end

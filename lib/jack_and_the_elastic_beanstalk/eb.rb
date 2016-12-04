module JackAndTheElasticBeanstalk
  class EB
    attr_reader :application_name
    attr_reader :logger
    attr_reader :client
    attr_accessor :timeout

    def initialize(application_name:, logger:, client:)
      @application_name = application_name
      @logger = logger
      @client = client
      @env_stack = []
      @timeout = 600
    end

    def environments
      @environments = client.describe_environments(application_name: application_name, include_deleted: false).environments.map {|env|
        Environment.new(application_name: application_name,
                        environment_name: env.environment_name,
                        logger: logger,
                        client: client).tap do |e|
          e.timeout = timeout
          e.data = env
        end
      }
    end

    def refresh
      @environments = nil
    end

    class Environment
      attr_reader :application_name
      attr_reader :logger
      attr_reader :client
      attr_reader :environment_name
      attr_accessor :timeout

      def initialize(application_name:, logger:, client:, environment_name:)
        @application_name = application_name
        @logger = logger
        @client = client
        @environment_name = environment_name
        @timeout = 600
      end

      def refresh
        @data = nil
        @configuration_setting = nil
      end

      def data=(v)
        @data = v
      end

      def data
        @data ||= client.describe_environments(application_name: application_name).environments.find {|env|
          env.environment_name == environment_name
        }
      end

      def configuration_setting
        @configuration_setting ||= client.describe_configuration_settings(application_name: application_name, environment_name: environment_name).configuration_settings.first
      end

      def env_vars
        configuration_setting.option_settings.each.with_object({}) do |option, hash|
          if option.namespace == "aws:elasticbeanstalk:application:environment"
            hash[option.option_name] = option.value
          end
        end
      end

      def set_env_vars(env)
        need_update = env.all? {|key, value|
          if value
            env_vars[key] == value
          else
            !env_vars.key?(key)
          end
        }

        if need_update
          logger.info("jeb::eb") { "Env vars looks like identical; skip" }
        else
          logger.info("jeb::eb") { "Updating environment variables" }

          options_to_update = []
          options_to_remove = []

          env.each do |key, value|
            if value
              options_to_update << {
                namespace: "aws:elasticbeanstalk:application:environment",
                option_name: key.to_s,
                value: value.to_s
              }
            else
              options_to_remove << {
                namespace: "aws:elasticbeanstalk:application:environment",
                option_name: key.to_s
              }
            end
          end

          client.update_environment(application_name: application_name,
                                    environment_name: environment_name,
                                    option_settings: options_to_update,
                                    options_to_remove: options_to_remove)

          refresh
        end
      end

      def synchronize_update(timeout: self.timeout)
        logger.info("jeb::eb") { "Synchronizing update started... (timeout = #{timeout})" }

        yield if block_given?

        start = Time.now

        while true
          refresh
          st = status

          logger.info("jeb::eb") { "#{environment_name}:: status=#{st}" }

          case st
          when "Ready"
            break
          when "Updating", "Launching"
            # ok
          else
            raise "Unexpected status: #{st}"
          end

          if Time.now - start > timeout
            raise "Timeout exceeded"
          end

          sleep 10
        end

        logger.info("jeb::eb") { "Synchronized in #{(Time.now - start).to_i} seconds" }
      end

      def scale
        option_settings = configuration_setting.option_settings

        min = option_settings.find {|option| option.namespace == "aws:autoscaling:asg" && option.option_name == "MinSize" }.value.to_i
        max = option_settings.find {|option| option.namespace == "aws:autoscaling:asg" && option.option_name == "MaxSize" }.value.to_i

        min...max
      end

      def status
        data.status
      end

      def set_scale(scale)
        if scale.is_a?(Integer)
          scale = scale...scale
        end

        if self.scale == scale
          logger.info("jeb::eb") { "New scale is identical to current scale; skip" }
        else
          logger.info("jeb::eb") { "Scaling to #{scale}" }

          client.update_environment(application_name: application_name,
                                    environment_name: environment_name,
                                    option_settings: [
                                      {
                                        namespace: "aws:autoscaling:asg",
                                        option_name: "MinSize",
                                        value: scale.begin.to_s
                                      },
                                      {
                                        namespace: "aws:autoscaling:asg",
                                        option_name: "MaxSize",
                                        value: scale.end.to_s
                                      }
                                    ])

          refresh
        end
      end

      def environment_id
        data.environment_id
      end

      def destroy
        logger.info("jeb::eb") { "Terminating #{environment_name}..." }
        client.terminate_environment(environment_id: environment_id)
      end

      def health
        logger.info("jeb::eb") { "Downloading health data on #{environment_name}..." }

        client.describe_environment_health(environment_id: environment_id, attribute_names: ["All"])
      end
    end
  end
end

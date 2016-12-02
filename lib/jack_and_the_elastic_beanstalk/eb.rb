module JackAndTheElasticBeanstalk
  class EB
    attr_reader :application_name
    attr_reader :logger
    attr_reader :client
    attr_reader :env_stack
    attr_accessor :timeout

    def initialize(application_name:, logger:, client:)
      @application_name = application_name
      @logger = logger
      @client = client
      @env_stack = []
      @timeout = 600
    end

    def environments
      client.describe_environments(application_name: application_name, include_deleted: false).environments
    end

    def set_current_environment(environment)
      env_stack.push environment
      yield
    ensure
      env_stack.pop
    end

    def current_environment
      env_stack.last || raise("set_env(environment) to set current env")
    end

    def env_vars
      config = client.describe_configuration_settings(application_name: application_name, environment_name: current_environment).configuration_settings.first
      config.option_settings.each.with_object({}) do |option, hash|
        if option.namespace == "aws:elasticbeanstalk:application:environment"
          hash[option.option_name] = option.value
        end
      end
    end

    def set_env_vars(env)
      current_env_vars = env_vars

      if env.all? {|key, value| value && current_env_vars[key] == value }
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
                                  environment_name: current_environment,
                                  option_settings: options_to_update,
                                  options_to_remove: options_to_remove)
      end
    end

    def synchronize_update(timeout: self.timeout)
      logger.info("jeb::eb") { "Synchronizing update started... (timeout = #{timeout})" }

      yield if block_given?

      start = Time.now

      while true
        st = status

        logger.info("jeb::eb") { "#{current_environment}:: status=#{st}" }

        case st
        when "Ready"
          break
        when "Updating"
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

    def configuration_setting
      client.describe_configuration_settings(application_name: application_name, environment_name: current_environment).configuration_settings.first
    end

    def scale
      option_settings = configuration_setting.option_settings

      min = option_settings.find {|option| option.namespace == "aws:autoscaling:asg" && option.option_name == "MinSize" }.value.to_i
      max = option_settings.find {|option| option.namespace == "aws:autoscaling:asg" && option.option_name == "MaxSize" }.value.to_i

      min...max
    end

    def status
      environments.find {|env| env.environment_name == current_environment }.status
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
                                  environment_name: current_environment,
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
      end
    end
  end
end

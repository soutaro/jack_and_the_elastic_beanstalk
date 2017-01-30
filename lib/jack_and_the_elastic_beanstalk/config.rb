module JackAndTheElasticBeanstalk
  class Config
    attr_reader :app_hash
    attr_reader :eb_configs

    def initialize(app_hash:, eb_configs:)
      @app_hash = app_hash
      @eb_configs = eb_configs
    end

    def self.load(path:)
      app_yml = path + "app.yml"
      app_hash = YAML.load_file(app_yml.to_s)

      eb_configs = path.children.each.with_object({}) do |file, acc|
        relative_path = file.relative_path_from(path)
        acc[relative_path] = file.read if file.extname == ".config"
      end

      Config.new(app_hash: app_hash, eb_configs: eb_configs)
    end

    def app_name
      app_hash.dig("application", "name")
    end

    def region
      app_hash.dig("application", "region")
    end

    def platform
      app_hash.dig("application", "platform")
    end

    def configurations
      app_hash["configurations"]
    end

    def s3_bucket
      app_hash["s3_bucket"]
    end

    def processes(configuration)
      configurations[configuration].select {|_, value| value["type"] }
    end

    def process_type(configuration, process)
      processes(configuration)[process]["type"].to_s
    end

    def each_config
      if block_given?
        eb_configs.each do |path, content|
          yield path, ERB.new(content).result
        end
      else
        enum_for :each_config
      end
    end

    def each_process(configuration)
      if block_given?
        processes(configuration).each do |key, hash|
          yield key, hash
        end
      else
        enum_for :each_process, configuration
      end
    end
  end
end

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
      app_hash["application"]["name"]
    end

    def region
      app_hash["application"]["region"]
    end

    def platform
      app_hash.dig("application", "platform")
    end

    def option_settings(env:, worker:)
      app_hash[env.to_s][worker.to_s]["option_settings"]
    end

    def type(env_name)
      app_hash[env_name.to_s]["type"]
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

    def each_worker(env:)
      if block_given?
        app_hash[env.to_s].each do |key, value|
          if value.key?("type")
            yield key.to_sym
          end
        end
      else
        enum_for :each_worker, env: env
      end
    end
  end
end

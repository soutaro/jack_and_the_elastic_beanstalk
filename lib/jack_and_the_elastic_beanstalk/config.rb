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
        acc[file] = file.read if file.extname == ".config"
      end

      Config.new(app_hash: app_hash, eb_config: eb_configs)
    end
  end
end

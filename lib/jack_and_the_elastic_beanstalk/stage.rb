module JackAndTheElasticBeanstalk
  class Stage
    attr_reader :config
    attr_reader :jack_name
    attr_reader :output_dir
    attr_reader :runner

    def initialize(config:, jack_name:, output_dir:, runner:)
      @config = config
      @jack_name = jack_name
      @output_dir = output_dir
      @runner = runner
    end

    def run(delete_after:, &block)
      output_dir.mkpath

      config.each_worker(env: jack_name) do |worker_name|
        worker_dir = output_dir + worker_name.to_s
        worker_dir.mkdir

        export_files(dest: worker_dir)
        with_env env: jack_name, worker: worker_name do
          prepare_eb_extensions(dir: worker_dir, env: jack_name, worker: worker_name)
        end

        runner.chdir worker_dir, &block if block_given?
      end

      output_dir.rmtree if delete_after
    end

    def with_env(env:, worker:)
      ENV["JEB_ENV"] = env.to_s
      ENV["JEB_WORKER"] = worker.to_s
      yield
    ensure
      ENV.delete("JEB_ENV")
      ENV.delete("JEB_WORKER")
    end

    def export_files(dest:)
      files = `git ls-files -z`.split("\x0")
      FileUtils.copy(files, dest.to_s)
    end

    def prepare_eb_extensions(dir:, env:, worker:)
      eb_dir = dir + ".ebextensions"
      eb_dir.mkdir

      option_settings = config.option_settings(env: env, worker: worker)
      (eb_dir + "option_settings.conf").write(YAML.dump("option_settings" => option_settings))

      config.each_config do |path, content|
        (eb_dir + path).write(content)
      end
    end
  end
end

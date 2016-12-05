module JackAndTheElasticBeanstalk
  class CLI < Thor
    no_commands do
      def client
        @client ||= Aws::ElasticBeanstalk::Client.new(region: config.region)
      end

      def runner
        @runner ||= JackAndTheElasticBeanstalk::Runner.new(stdin: STDIN, stdout: STDOUT, stderr: STDERR, logger: logger)
      end

      def logger
        @logger ||= Logger.new(STDERR).tap do |logger|
          logger.level = Logger.const_get(options[:loglevel].upcase)
        end
      end

      def eb
        @eb ||= JackAndTheElasticBeanstalk::EB.new(application_name: config.app_name, logger: logger, client: client).tap do |eb|
          eb.timeout = options[:timeout] * 60
        end
      end

      def config
        @config ||= JackAndTheElasticBeanstalk::Config.load(path: Pathname(options[:jack_dir]))
      end

      def service
        @service ||= JackAndTheElasticBeanstalk::Service.new(source_dir: Pathname(options[:source_dir]), config: config, eb: eb, runner: runner, logger: logger)
      end

      def output_dir
        Dir.mktmpdir do |dir|
          yield Pathname(dir)
        end
      end

      def try_process(name, is:)
        if !is || is == name
          yield(name)
        end
      end

      def each_in_parallel(array, &block)
        Parallel.each(array, in_threads: array.size, &block)
      end
    end

    class_option :timeout, type: :numeric, default: 10, desc: "Minutes to timeout for each EB operation"
    class_option :loglevel, type: :string, enum: ["info", "debug", "error"], default: "error", desc: "Loglevel"
    class_option :jack_dir, type: :string, default: (Pathname.pwd + "jack").to_s, desc: "Directory to app.yml"
    class_option :source_dir, type: :string, default: __dir__, desc: "Directory for source code"

    desc "create CONFIGURATION GROUP", "Create new group"
    def create(configuration, group)
      processes = config.each_process(configuration).to_a

      each_in_parallel(processes) do |process, hash|
        runner.stdout.puts "Creating new environment for #{process}..."
        output_dir do |path|
          service.eb_init(target_dir: path)
          service.stage(target_dir: path, process: process)
          service.eb_create(target_dir: path, configuration: configuration, group: group, process: process)
        end

        if hash["type"] == "oneoff"
          runner.stdout.puts "Scaling to 0 (#{process} is a oneoff process)"
          env = service.each_environment(group: group).find {|_, p| p == process }.first
          env.set_scale(0)
          env.synchronize_update
        end
      end
    end

    desc "deploy GROUP", "Deploy to group"
    def deploy(group)
      envs = service.each_environment(group: group).to_a

      each_in_parallel(envs) do |_, process|
        runner.stdout.puts "Deploying to #{process}..."
        output_dir do |path|
          service.eb_init(target_dir: path)
          service.stage(target_dir: path, process: process)
          service.eb_deploy(target_dir: path, group: group, process: process)
        end
      end
    end

    desc "printenv GROUP [PROCESS]", "Print environment variables"
    def printenv(group, process=nil)
      service.each_environment(group: group) do |env, p|
        try_process(p, is: process) do
          puts "#{p} (#{env.environment_name}):"
          env.env_vars.each do |key, value|
            runner.stdout.puts "  #{key}=#{value}"
          end
        end
      end
    end

    desc "setenv GROUP name=var name= ...", "Set environment variables"
    option :process, type: :string
    def setenv(group, *args)
      hash = {}
      args.each do |arg|
        k,v = arg.split("=")
        hash[k] = v
      end

      logger.info("jeb::cli") { "Setting environment hash: #{hash.inspect}" }

      envs = service.each_environment(group: group)
      each_in_parallel(envs) do |env, p|
        try_process(p, is: options[:process]) do
          runner.stdout.puts "Updating #{p}'s environment variable..."
          env.synchronize_update do
            env.set_env_vars hash
          end
        end
      end
    end

    desc "restart GROUP [PROCESS]", "Restart applications"
    def restart(group, process=nil)
      envs = service.each_environment(group: group)
      each_in_parallel(envs) do |env, p|
        try_process(p, is: process) do
          runner.stdout.puts "Restarting #{p}..."
          env.synchronize_update do
            env.restart
          end
        end
      end
    end

    desc "destroy GROUP [PROCESS]", "Terminate environments associated to GROUP"
    def destroy(group, process=nil)
      service.each_environment(group: group) do |env, p|
        try_process p, is: process do
          runner.stdout.puts "Destroying #{p}: #{env.environment_name}..."
          env.destroy
        end
      end
    end

    desc "status GROUP [PROCESS]", "Print status of environments associated to GROUP"
    def status(group, process=nil)
      service.each_environment(group: group) do |env, p|
        try_process p, is: process do
          h = env.health
          ih = h.instances_health
          total = ih.no_data + ih.ok + ih.info + ih.warning + ih.degraded + ih.severe + ih.pending
          runner.stdout.puts "#{p}: name=#{env.environment_name}, status=#{env.status}, health: #{h.health_status}, instances: #{total}, scale: #{env.scale}"
        end
      end
    end

    desc "exec GROUP command...", "Run oneoff command"
    def exec(group, *command)
      env = service.each_environment(group: group).find {|_, p| p == "oneoff" }&.first
      if env
        begin
          env.synchronize_update do
            runner.stdout.puts "Starting #{env.environment_name} for oneoff process..."
            env.set_scale 1
          end

          output_dir do |path|
            service.eb_init target_dir: path

            commandline = "cd /var/app/current && sudo -E -u webapp env PATH=$PATH #{command.join(' ')}"
            out, err = runner.capture3! "eb", "ssh", "-c", commandline

            runner.stdout.print out
            runner.stderr.print err
          end
        ensure
          env.synchronize_update do
            runner.stdout.puts "Shutting down #{env.environment_name}..."
            env.set_scale 0
          end
        end
      else
        runner.stdout.puts "Could not find environment associated to oneoff process..."
      end
    end

    desc "scale GROUP PROCESS min max", "Scale instances"
    def scale(group, process, min, max=min)
      service.each_environment(group: group) do |env, p|
        try_process p, is: process do
          runner.stdout.puts "Scaling #{group} (#{env.environment_name}) to min=#{min}, max=#{max}..."
          env.synchronize_update do
            env.set_scale(min...max)
          end
        end
      end
    end

    desc "list", "List groups"
    def list
      service.each_group do |group, envs|
        runner.stdout.puts "#{group}: #{envs.map(&:environment_name).join(", ")}"
      end
    end

    desc "synchronize", "Wait for update"
    def synchronize(group)
      service.each_environment(group: group) do |env, process|
        if env.status != "Ready"
          runner.stdout.puts "Waiting for #{process} (#{env.environment_name})..."
          env.synchronize_update
        end
      end
    end

    desc "resources GROUP [PROCESS]", "Download resources associated to each environment"
    def resources(group, process_name=nil)
      resources = {}

      service.each_environment(group: group) do |env, process|
        try_process process, is: process_name do
          ress = env.resources.environment_resources
          resources[process] = {
            environment_name: env.environment_name,
            environment_id: env.environment_id,
            auto_scaling_groups: ress.auto_scaling_groups.map(&:name),
            instances: ress.instances.map(&:id),
            launch_configurations: ress.launch_configurations.map(&:name),
            load_balancers: ress.load_balancers.map(&:name),
            queues: ress.queues.map(&:url).reject(&:empty?),
            triggers: ress.triggers.map(&:name)
          }
        end
      end

      unless resources.empty?
        runner.stdout.puts JSON.pretty_generate(resources)
      end
    end
  end
end

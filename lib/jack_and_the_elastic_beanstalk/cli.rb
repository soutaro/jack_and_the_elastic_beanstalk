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

      def each_in_parallel(array)
        Parallel.each_with_index(array, in_threads: array.size) do |a, index|
          sleep index*5
          yield a
        end
      end

      def parse_env_args(args)
        args.each.with_object({}) do |arg, hash|
          k,v = arg.split("=", 2)
          hash[k] = v
        end
      end
    end

    class_option :timeout, type: :numeric, default: 10, desc: "Minutes to timeout for each EB operation"
    class_option :loglevel, type: :string, enum: ["info", "debug", "error"], default: "error", desc: "Loglevel"
    class_option :jack_dir, type: :string, default: (Pathname.pwd + "jack").to_s, desc: "Directory to app.yml"
    class_option :source_dir, type: :string, default: Pathname.pwd.to_s, desc: "Directory for source code"

    desc "create CONFIGURATION GROUP ENV_VAR=VALUE...", "Create new group"
    def create(configuration, group, *env_var_args)
      processes = config.each_process(configuration).to_a
      env_vars = parse_env_args(env_var_args)

      output_dir do |base_path|
        processes.each do |process, hash|
          path = base_path + process
          runner.stdout.puts "Staging for #{process}..."
          service.stage(target_dir: path, process: process)
        end

        each_in_parallel(processes) do |process, hash|
          runner.stdout.puts "Creating new environment for #{process}..."

          path = base_path + process

          service.eb_init(target_dir: path)
          service.eb_create(target_dir: path, configuration: configuration, group: group, process: process, env_vars: env_vars)

          if hash["type"] == "oneoff"
            runner.stdout.puts "Scaling to 0 (#{process} is a oneoff process)"
            env = service.each_environment(group: group).find {|_, p| p == process }.first
            env.set_scale(0)
            env.synchronize_update
          end
        end
      end
    end

    desc "deploy GROUP", "Deploy to group"
    def deploy(group)
      envs = service.each_environment(group: group).to_a

      prefix = Time.now.utc.iso8601

      output_dir do |base_path|
        archives = {}

        envs.each do |_, process|
          path = base_path + process
          path.mkpath

          runner.stdout.puts "Staging for #{process}..."
          service.stage(target_dir: path, process: process)

          name = "#{group}-#{prefix}-#{process}"
          key = "#{config.app_name}/#{name}"

          archive_path = base_path + "#{name}.zip"
          service.archive(input_dir: path, output_path: archive_path)

          archives[process] = [key, name, archive_path]
        end

        each_in_parallel(envs) do |_, process|
          runner.stdout.puts "Deploying to #{process}..."

          s3_key, label, archive_path = archives[process]

          service.deploy(group: group,
                         process: process,
                         archive_path: archive_path,
                         s3_key: s3_key,
                         label: label)
        end
      end
    end

    desc "stage PROCESS OUTPUT_DIR", "Prepare application to deploy"
    def stage(process, output_dir)
      path = Pathname(output_dir)

      if path.directory?
        runner.stdout.puts "Deleting #{path}..."
        path.rmtree
      end

      runner.stdout.puts "Staging for #{process} in #{path}..."

      path.mkpath
      service.eb_init target_dir: path
      service.stage(target_dir: path, process: process)
    end

    desc "archive PROCESS OUTPUT_PATH", "Prepare application bundle at OUTPUT_PATH"
    def archive(process, output_path)
      zip_path = Pathname(output_path)

      Dir.mktmpdir do |dir|
        dir_path = Pathname(dir)

        runner.stdout.puts "Staging for #{process}..."

        dir_path.mkpath
        service.stage(target_dir: dir_path, process: process)

        runner.stdout.puts "Making application bundle to #{zip_path}..."

        service.archive(input_dir: dir_path, output_path: zip_path)
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

    desc "setenv GROUP PROCESS name=var name= ...", "Set environment variables"
    def setenv(group, *args)
      process = if args.first !~ /=/
                  args.shift
                end

      hash = parse_env_args(args)

      logger.info("jeb::cli") { "Setting environment hash: #{hash.inspect}" }

      envs = service.each_environment(group: group)
      each_in_parallel(envs) do |env, p|
        try_process(p, is: process) do
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
    option :keep, type: :boolean, default: false, desc: "Keep started oneoff environment"
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

            runner.stdout.puts "Waiting for EB to complete deploy..."
            sleep 30

            start = Time.now

            while true
              dirs, _ = runner.capture3! "eb", "ssh", env.environment_name, "-c", "ls /var/app"

              if dirs =~ /ondeck/
                logger.info("jeb::cli") { "Waiting for deploy..." }
              end
              if dirs =~ /current/ && dirs !~ /ondeck/
                break
              end
              if Time.now - start > options[:timeout]*60
                raise "Timed out for waiting deploy..."
              end

              sleep 15
            end

            commandline = "cd /var/app/current && sudo -E -u webapp env PATH=$PATH #{command.join(' ')}"
            out, err, status = runner.capture3 "eb", "ssh", env.environment_name, "-c", commandline

            runner.stdout.print out
            runner.stderr.print err

            raise status.to_s unless status.success?
          end
        ensure
          unless options[:keep]
            env.synchronize_update do
              runner.stdout.puts "Shutting down #{env.environment_name}..."
              env.set_scale 0
            end
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

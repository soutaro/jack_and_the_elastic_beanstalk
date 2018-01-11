module JackAndTheElasticBeanstalk
  class Service
    attr_reader :config
    attr_reader :source_dir
    attr_reader :eb
    attr_reader :runner
    attr_reader :logger

    def initialize(config:, source_dir:, eb:, runner:, logger:)
      @config = config
      @source_dir = source_dir
      @eb = eb
      @runner = runner
      @logger = logger
    end

    def eb_init(target_dir:)
      runner.chdir target_dir do
        runner.capture3!("eb", "init", config.app_name, "-r", config.region, "-p", config.platform)
      end
    end

    def eb_deploy(target_dir:, group:, process:)
      runner.chdir target_dir do
        runner.capture3!("eb", "deploy", env_name(group: group, process: process), "--nohang")
      end

      env = eb.environments.find {|e| e.environment_name == env_name(group: group, process: process) }
      env.synchronize_update
    end

    def eb_create(target_dir:, configuration:, group:, process:, env_vars:)
      if eb.environments.none? {|env| env.environment_name == env_name(group: group, process: process) }
        logger.info("jeb::service") { "Creating eb environment for #{process} from #{target_dir}..." }

        commandline = ["eb", "create", env_name(group: group, process: process), "--nohang", "--scale", "1"]

        hash = config.processes(configuration)[process]

        commandline.concat(["-t", "worker"]) if config.process_type(configuration, process) == "worker"
        commandline.concat(["--region", hash["region"] || config.region])
        commandline.concat(["--platform", hash["platform"] || config.platform])
        commandline.concat(["--instance_profile", hash["instance_profile"]]) if hash["instance_profile"]
        commandline.concat(["--keyname", hash["keyname"]]) if hash["keyname"]
        commandline.concat(["--instance_type", hash["instance_type"]]) if hash["instance_type"]
        commandline.concat(["--service-role", hash["service_role"]]) if hash["service_role"]

        if hash["tags"]&.any?
          commandline.concat(["--tags", hash["tags"].each.with_object([]) do |(key, value), acc|
            acc << "#{key}=#{value}"
          end.concat(",")])
        end

        if hash["vpc"]
          vpc = hash["vpc"]

          commandline.concat(["--vpc", "--vpc.id", vpc["id"]])
          commandline.concat(["--vpc.ec2subnets", vpc["ec2subnets"].join(",")]) if vpc["ec2subnets"]&.any?
          commandline.concat(["--vpc.elbpublic"]) if vpc["elbpublic"]
          commandline.concat(["--vpc.elbsubnets", vpc["elbsubnets"].join(",")]) if vpc["elbsubnets"]&.any?
          commandline.concat(["--vpc.publicip"]) if vpc["publicip"]
          commandline.concat(["--vpc.securitygroups", vpc["securitygroups"].join(",")]) if vpc["securitygroups"]&.any?
        end

        unless env_vars.empty?
          vars = env_vars.to_a.map {|(k, v)| "#{k}=#{v}" }.join(",")
          commandline.concat(["--envvars", vars])
        end

        runner.chdir target_dir do
          runner.capture3!(*commandline)
        end

        eb.refresh
        env = eb.environments.find {|e| e.environment_name == env_name(group: group, process: process) }
        env.synchronize_update
      else
        logger.info("jeb::service") { "Environment #{env_name(group:group, process: process)} already exists..." }
      end
    end

    def env_name(group:, process:)
      "jeb-#{group}-#{process}"
    end

    def stage(target_dir:, process:)
      logger.info("jeb::service") { "Staging files in #{target_dir} for #{process}" }

      ENV["JEB_PROCESS"] = process

      export_files(dest: target_dir)

      eb_extensions = target_dir + ".ebextensions"
      eb_extensions.mkpath
      config.each_config do |path, content|
        logger.debug("jeb::service") { "Writing #{path} ..." }
        (eb_extensions + path).write content
      end
    ensure
      ENV.delete("JEB_PROCESS")
    end

    def archive(input_dir:, output_path:)
      paths = Pathname.glob(input_dir + "**/*", File::FNM_DOTMATCH).select(&:file?)

      Zip::File.open(output_path.to_s, Zip::File::CREATE) do |zip|
        paths.each do |path|
          zip.add(path.relative_path_from(input_dir).to_s, path.to_s)
        end
      end
    end

    def export_files(dest:)
      files = runner.chdir(source_dir) do
        runner.capture3!("git", "ls-files", "-z").first.split("\x0")
      end

      files.each do |f|
        logger.debug("jeb::service") { "Copying #{f} ..."}

        source_path = source_dir + f
        target_path = dest + f

        unless target_path.parent.directory?
          target_path.parent.mkpath
        end

        FileUtils.copy(source_path.to_s, target_path.to_s)
      end
    end

    def upload(archive_path:, name:)
      logger.debug("jeb::service") { "Uploading #{archive_path} to #{config.s3_bucket}/#{name}..." }
      s3 = Aws::S3::Client.new(region: config.region)
      archive_path.open do |io|
        s3.put_object(bucket: config.s3_bucket, key: name, body: io)
      end
    end

    def deploy(group:, process:, archive_path:, s3_key:, label:)
      upload(archive_path: archive_path, name: s3_key)
      eb.create_version(s3_bucket: config.s3_bucket, s3_key: s3_key, label: label)

      eb.environments.find {|env| env.environment_name == env_name(group: group, process: process) }.try do |env|
        env.synchronize_update do
          env.deploy(label: label)
        end

        env.ensure_version!(expected_label: label)
      end

      eb.cleanup_versions
    end

    def destroy(group:)
      logger.info("jeb::service") { "Destroying #{group} ..." }

      each_environment(group: group) do |env, _|
        env.destroy
      end
    end

    def each_environment(group:)
      if block_given?
        regexp = /\Ajeb-#{group}-([^\-]+)\Z/

        eb.environments.each do |env|
          if env.environment_name =~ regexp
            yield env, $1
          end
        end
      else
        enum_for :each_environment, group: group
      end
    end

    def each_group
      if block_given?
        regexp = /\Ajeb-(.+)-([^\-]+)\Z/

        eb.environments.group_by {|env|
          if env.environment_name =~ regexp
            $1
          end
        }.each do |group, envs|
          if group
            yield group, envs
          end
        end
      else
        enum_for :each_group
      end
    end
  end
end

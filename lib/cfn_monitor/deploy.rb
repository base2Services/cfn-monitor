require 'aws-sdk-s3'
require 'yaml'

module CfnMonitor
  class Deploy

    def self.run(options)

      if options['application']
        application = options['application']
        custom_alarms_config_file = "#{application}/alarms.yml"
        output_path = "output/#{application}"
      else
        application = File.basename(Dir.getwd)
        custom_alarms_config_file = "alarms.yml"
        output_path = "output"
      end

      upload_path = "cloudformation/monitoring/#{application}"

      # Load custom config files
      if File.file?(custom_alarms_config_file)
        custom_alarms_config = YAML.load(File.read(custom_alarms_config_file)) if File.file?(custom_alarms_config_file)
      else
        puts "Failed to load #{custom_alarms_config_file}"
        exit 1
      end

      puts "-----------------------------------------------"
      s3 = Aws::S3::Client.new(region: custom_alarms_config['source_region'])
      ["#{output_path}/*.json"].each { |path|
        Dir.glob(path) do |file|
          template = File.open(file, 'rb')
          filename = file.gsub("#{output_path}/", "")
          s3.put_object({
              body: template,
              bucket: "#{custom_alarms_config['source_bucket']}",
              key: "#{upload_path}/#{filename}",
          })
          puts "INFO: Copied #{file} to s3://#{custom_alarms_config['source_bucket']}/#{upload_path}/#{filename}"
        end
      }
      puts "-----------------------------------------------"
      puts "Master stack: https://s3.#{custom_alarms_config['source_region']}.amazonaws.com/#{custom_alarms_config['source_bucket']}/#{upload_path}/master.json"
      puts "-----------------------------------------------"
    end

  end
end

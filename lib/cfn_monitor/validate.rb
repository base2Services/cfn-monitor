require 'aws-sdk-s3'
require 'yaml'

module CfnMonitor
  class Validate

    def self.run(options)

      if !options['application']
        raise "No application specified"
      end

      application = options['application']

      custom_alarms_config_file = "#{application}/alarms.yml"
      output_path = "output/#{application}"
      validate_path = "cloudformation/monitoring/#{application}/validate"

      # Load custom config files
      if File.file?(custom_alarms_config_file)
        custom_alarms_config = YAML.load(File.read(custom_alarms_config_file)) if File.file?(custom_alarms_config_file)
      else
        puts "Failed to load #{custom_alarms_config_file}"
        exit 1
      end

      source_region = custom_alarms_config['source_region']
      source_bucket = custom_alarms_config['source_bucket']

      cfn = Aws::CloudFormation::Client.new(region: source_region)
      s3 = Aws::S3::Client.new(region: source_region)
      validated = 0
      unvalidated = 0

      puts "-----------------------------------------------"

      ["#{output_path}/*.json"].each { |path|
        Dir.glob(path) do |file|
          template = File.open(file, 'rb')
          filename = file.gsub("#{output_path}/", "")
          begin
            puts "INFO - Copying #{file} to s3://#{source_bucket}/#{validate_path}/#{filename}"
            s3.put_object({
              body: template,
              bucket: "#{source_bucket}",
              key: "#{validate_path}/#{filename}",
            })
            template_url = "https://#{source_bucket}.s3.amazonaws.com/#{validate_path}/#{filename}"
            puts "INFO - Validating #{template_url}"
            begin
              resp = cfn.validate_template({ template_url: template_url })
              puts "INFO - Template #{filename} validated successfully"
              validated += 1
            rescue => e
              puts "ERROR - Template #{filename} failed to validate: #{e}"
              unvalidated += 1
            end
          rescue => e
            puts "ERROR - #{e.class}, #{e}"
            exit 1
          end
        end
      }

      if unvalidated > 0
        puts "ERROR - #{validated}/#{Dir["output/**/*.json"].count} templates validated successfully"
        exit 1
      else
        puts "INFO - #{validated}/#{Dir["output/**/*.json"].count} templates validated successfully"
      end
    end

  end
end

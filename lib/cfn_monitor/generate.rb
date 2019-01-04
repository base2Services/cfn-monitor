require "cfndsl"
require 'fileutils'
require 'tempfile'
require 'yaml'

require "cfn_monitor/utils"

module CfnMonitor
  class Generate

    def self.run(options)

      if !options['application']
        raise "No application specified"
      end

      if options['silent']
        verbose_cfndsl = false
      else
        verbose_cfndsl = STDOUT
      end

      application = options['application']

      template_path = File.join(File.dirname(__FILE__),'../config/templates.yml')
      config_path = File.join(File.dirname(__FILE__),'../config/config.yml')
      # Load global config files
      global_templates_config = YAML.load(File.read(template_path))
      config = YAML.load(File.read(config_path))

      custom_alarms_config_file = "#{application}/alarms.yml"
      custom_templates_config_file = "#{application}/templates.yml"
      output_path = "output/#{application}"
      upload_path = "cloudformation/monitoring/#{application}"

      # Load custom config files
      if File.file?(custom_alarms_config_file)
        custom_alarms_config = YAML.load(File.read(custom_alarms_config_file))
      else
        puts "Failed to load #{custom_alarms_config_file}"
        exit 1
      end

      # Merge custom template configs over global template configs
      if File.file?(custom_templates_config_file)
        custom_templates_config = YAML.load(File.read(custom_templates_config_file))
        templates = CfnMonitor::Utils.deep_merge(global_templates_config, custom_templates_config)
      else
        templates = global_templates_config
      end

      # Create an array of alarms based on the templates associated with each resource
      alarms = []
      resources = custom_alarms_config['resources']
      metrics = custom_alarms_config['metrics']
      hosts = custom_alarms_config['hosts'] || {}
      services = custom_alarms_config['services'] || {}
      endpoints = custom_alarms_config['endpoints'] || {}

      alarm_parameters = { resources: resources, metrics: metrics, endpoints: endpoints, hosts: hosts, services: services }
      source_bucket = custom_alarms_config['source_bucket']

      alarm_parameters.each do | k,v |
        if !v.nil?
          v.each do | resource,attributeList |
            # set environments to 'all' by default
            environments = ['all']
            # Support config hashs for additional parameters
            params = {}
            if !attributeList.kind_of?(Array)
              attributeList = [attributeList]
            end
            attributeList.each do | attributes |
              if attributes.kind_of?(Hash)
                attributes.each do | a,b |
                  environments = b if a == 'environments'
                  # Convert strings to arrays for consistency
                  if !environments.kind_of?(Array) then environments = environments.split end
                  params[a] = b if !['template','environments'].member? a
                end
                templatesEnabled = attributes['template']
              else
                templatesEnabled = attributes
              end
              # Convert strings to arrays for looping
              if !templatesEnabled.kind_of?(Array) then templatesEnabled = templatesEnabled.split end
              templatesEnabled.each do | templateEnabled |
                if !templates['templates'][templateEnabled].nil?
                  # If a template is provided, inherit that template
                  if !templates['templates'][templateEnabled]['template'].nil?
                    template_from = Marshal.load( Marshal.dump(templates['templates'][templates['templates'][templateEnabled]['template']]) )
                    template_to = templates['templates'][templateEnabled].without('template')
                    template_merged = CfnMonitor::Utils.deep_merge(template_from, template_to)
                    templates['templates'][templateEnabled] = template_merged
                  end
                  templates['templates'][templateEnabled].each do | alarm,parameters |
                    resourceParams = parameters.clone
                    # Override template params if overrides provided
                    params.each do | x,y |
                      resourceParams[x] = y
                    end

                    if k == :hosts
                      resourceParams['cmds'].each do |cmd|
                        hostParams = resourceParams.clone
                        hostParams['cmd'] = cmd
                        # Construct alarm object per cmd
                        alarms << {
                          resource: resource,
                          type: k[0...-1],
                          template: templateEnabled,
                          alarm: alarm,
                          parameters: hostParams,
                          environments: environments
                        }
                      end
                    else
                      # Construct alarm object
                      alarms << {
                        resource: resource,
                        type: k[0...-1],
                        template: templateEnabled,
                        alarm: alarm,
                        parameters: resourceParams,
                        environments: environments
                      }
                    end
                  end
                end
              end
            end
          end
        end
      end

      # Create temp alarms file for CfnDsl
      temp_file = Tempfile.new(["alarms-",'.yml'])
      temp_file_path = temp_file.path
      temp_file.write({'alarms' => alarms}.to_yaml)
      temp_file.rewind

      # Split resources for mulitple templates to avoid CloudFormation template resource limits
      split = []
      template_envs = ['production']
      alarms.each_with_index do |alarm,index|
        split[index/config['resource_limit']] ||= {}
        split[index/config['resource_limit']]['alarms'] ||= []
        split[index/config['resource_limit']]['alarms'] << alarm
        template_envs |= get_alarm_envs(alarm[:parameters])
      end

      # Create temp files for split resources for CfnDsl input
      temp_files=[]
      temp_file_paths=[]
      (alarms.count/config['resource_limit'].to_f).ceil.times do | i |
        temp_files[i] = Tempfile.new(["alarms-#{i}-",'.yml'])
        temp_file_paths[i] = temp_files[i].path
        temp_files[i].write(split[i].to_yaml)
        temp_files[i].rewind
      end

      write_cfdndsl_template(temp_file_path, temp_file_paths, custom_alarms_config_file, source_bucket, template_envs, output_path, upload_path, verbose_cfndsl)

    end

    def self.write_cfdndsl_template(alarms_config,configs,custom_alarms_config_file,source_bucket,template_envs,output_path,upload_path,verbose_cfndsl)
      template_path = File.expand_path("../../templates", __FILE__)
      FileUtils::mkdir_p output_path
      configs.each_with_index do |config,index|
        File.open("#{output_path}/resources#{index}.json", 'w') { |file|
          file.write(JSON.pretty_generate( CfnDsl.eval_file_with_extras("#{template_path}/resources.rb",[[:yaml, config],[:raw, "template_number=#{index}"],[:raw, "source_bucket='#{source_bucket}'"],[:raw, "upload_path='#{upload_path}'"]],verbose_cfndsl)))}
        File.open("#{output_path}/alarms#{index}.json", 'w') { |file|
          file.write(JSON.pretty_generate( CfnDsl.eval_file_with_extras("#{template_path}/alarms.rb",[[:yaml, config],[:raw, "template_number=#{index}"],[:raw, "template_envs=#{template_envs}"]],verbose_cfndsl)))}
      end
      File.open("#{output_path}/endpoints.json", 'w') { |file|
        file.write(JSON.pretty_generate( CfnDsl.eval_file_with_extras("#{template_path}/endpoints.rb",[[:yaml, alarms_config],[:raw, "template_envs=#{template_envs}"]],verbose_cfndsl)))}
      File.open("#{output_path}/hosts.json", 'w') { |file|
        file.write(JSON.pretty_generate( CfnDsl.eval_file_with_extras("#{template_path}/hosts.rb",[[:yaml, alarms_config],[:raw, "template_envs=#{template_envs}"]],verbose_cfndsl)))}
      File.open("#{output_path}/services.json", 'w') { |file|
        file.write(JSON.pretty_generate( CfnDsl.eval_file_with_extras("#{template_path}/services.rb",[[:yaml, alarms_config],[:raw, "template_envs=#{template_envs}"]],verbose_cfndsl)))}
      File.open("#{output_path}/master.json", 'w') { |file|
        file.write(JSON.pretty_generate( CfnDsl.eval_file_with_extras("#{template_path}/master.rb",[[:yaml, custom_alarms_config_file],[:raw, "templateCount=#{configs.count}"],[:raw, "template_envs=#{template_envs}"],[:raw, "upload_path='#{upload_path}'"]],verbose_cfndsl)))}
    end

    def self.get_alarm_envs(params)
      envs = []
      params.each do | key,value |
        if key.include? '.'
          envs << key.split('.').last
        end
      end
      return envs
    end

  end
end

require 'cfndsl/rake_task'
require 'rake'
require 'tempfile'
require 'yaml'
require 'json'
require_relative 'ext/common_helper'
require_relative 'ext/alarms'
require 'fileutils'
require 'digest'
require 'aws-sdk'

namespace :cfn do

  # Global and customer config files
  config_file = 'config/config.yml'
  global_templates_config_file = 'config/templates.yml'

  # Load global config files
  global_templates_config = YAML.load(File.read(global_templates_config_file))
  config = YAML.load(File.read(config_file))

  desc('Generate CloudFormation for CloudWatch alarms')
  task :generate do

    ARGV.each { |a| task a.to_sym do ; end }
    customer = ARGV[1]
    application = ARGV[2]

    if !customer
      puts "Usage:"
      puts "rake cfn:generate <customer> [application]"
      exit 1
    end

    if application
      customer_alarms_config_file = "ciinaboxes/#{customer}/monitoring/#{application}/alarms.yml"
      customer_templates_config_file = "ciinaboxes/#{customer}/monitoring/#{application}/templates.yml"
      output_path = "output/#{customer}/#{application}"
      upload_path = "cloudformation/monitoring/#{application}"
    else
      customer_alarms_config_file = "ciinaboxes/#{customer}/monitoring/alarms.yml"
      customer_templates_config_file = "ciinaboxes/#{customer}/monitoring/templates.yml"
      output_path = "output/#{customer}"
      upload_path = "cloudformation/monitoring"
    end

    # Load customer config files
    if File.file?(customer_alarms_config_file)
      customer_alarms_config = YAML.load(File.read(customer_alarms_config_file))
    else
      puts "Failed to load #{customer_alarms_config_file}"
      exit 1
    end

    # Merge customer template configs over global template configs
    if File.file?(customer_templates_config_file)
      customer_templates_config = YAML.load(File.read(customer_templates_config_file))
      templates = CommonHelper.deep_merge(global_templates_config, customer_templates_config)
    else
      templates = global_templates_config
    end

    # Create an array of alarms based on the templates associated with each resource
    alarms = []
    resources = customer_alarms_config['resources']
    metrics = customer_alarms_config['metrics']
    hosts = customer_alarms_config['hosts']
    hosts ||= {}
    endpoints = customer_alarms_config['endpoints']
    endpoints ||= {}
    rme = { resources: resources, metrics: metrics, endpoints: endpoints, hosts: hosts }
    source_bucket = customer_alarms_config['source_bucket']

    rme.each do | k,v |
      if !v.nil?
        v.each do | resource,attributes |
          # set environments to 'all' by default
          environments = ['all']
          # Support config hashs for additional parameters
          params = {}
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
                template_merged = CommonHelper.deep_merge(template_from, template_to)
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

    ARGV.each { |a| task a.to_sym do ; end }
    write_cfdndsl_template(temp_file_path,temp_file_paths,customer_alarms_config_file,customer,source_bucket,template_envs,output_path,upload_path)
  end

  desc('Deploy cloudformation templates to S3')
  task :deploy do
    ARGV.each { |a| task a.to_sym do ; end }
    customer = ARGV[1]
    application = ARGV[2]

    if !customer
      puts "Usage:"
      puts "rake cfn:deploy <customer> [application]"
      exit 1
    end

    if application
      customer_alarms_config_file = "ciinaboxes/#{customer}/monitoring/#{application}/alarms.yml"
      output_path = "output/#{customer}/#{application}"
      upload_path = "cloudformation/monitoring/#{application}"
    else
      customer_alarms_config_file = "ciinaboxes/#{customer}/monitoring/alarms.yml"
      output_path = "output/#{customer}"
      upload_path = "cloudformation/monitoring"
    end

    # Load customer config files
    if File.file?(customer_alarms_config_file)
      customer_alarms_config = YAML.load(File.read(customer_alarms_config_file)) if File.file?(customer_alarms_config_file)
    else
      puts "Failed to load #{customer_alarms_config_file}"
      exit 1
    end

    puts "-----------------------------------------------"
    s3 = Aws::S3::Client.new(region: customer_alarms_config['source_region'])
    ["#{output_path}/*.json"].each { |path|
      Dir.glob(path) do |file|
        template = File.open(file, 'rb')
        filename = file.gsub("#{output_path}/", "")
        s3.put_object({
            body: template,
            bucket: "#{customer_alarms_config['source_bucket']}",
            key: "#{upload_path}/#{filename}",
        })
        puts "INFO: Copied #{file} to s3://#{customer_alarms_config['source_bucket']}/#{upload_path}/#{filename}"
      end
    }
    puts "-----------------------------------------------"
    puts "Master stack: https://s3.#{customer_alarms_config['source_region']}.amazonaws.com/#{customer_alarms_config['source_bucket']}/#{upload_path}/master.json"
    puts "-----------------------------------------------"
  end

  desc('Query environment for monitorable resources')
  task :query do
    ARGV.each { |a| task a.to_sym do ; end }
    region = ARGV[1]
    stack = ARGV[2]
    customer = ARGV[3]
    application = ARGV[4]

    if !customer || !stack || !region
      puts "Usage:"
      puts "rake cfn:query <region> <stack> <customer> [application]"
      exit 1
    end

    if application
      customer_alarms_config_file = "ciinaboxes/#{customer}/monitoring/#{application}/alarms.yml"
    else
      customer_alarms_config_file = "ciinaboxes/#{customer}/monitoring/alarms.yml"
    end

    # Load customer config files
    customer_alarms_config = YAML.load(File.read(customer_alarms_config_file)) if File.file?(customer_alarms_config_file)
    customer_alarms_config ||= {}
    customer_alarms_config['resources'] ||= {}

    puts "-----------------------------------------------"
    puts "stack: #{stack}"
    puts "customer: #{customer}"
    puts "region: #{region}"
    puts "-----------------------------------------------"
    puts "Searching Stacks for Monitorable Resources"
    puts "-----------------------------------------------"

    cfClient = Aws::CloudFormation::Client.new(region: region)
    elbClient = Aws::ElasticLoadBalancingV2::Client.new(region: region)

    def query_stacks (config,cfClient,elbClient,stack,stackResources={template:{},physical_resource_id:{}},location='')
      stackResourceCount = 0
      stackResourceCountLocal = 0
      begin
        resp = cfClient.list_stack_resources({
          stack_name: stack
        })
      rescue Aws::CloudFormation::Errors::ServiceError => e
        puts "Error: #{e}"
        exit 1
      end

      resp.stack_resource_summaries.each do | resource |
        if resource['resource_type'] == 'AWS::CloudFormation::Stack'
          query = query_stacks(config,cfClient,elbClient,resource['physical_resource_id'],stackResources,"#{location}.#{resource['logical_resource_id']}")
          stackResourceCount += query[:stackResourceCount]
        end
        if config['resource_defaults'].key? resource['resource_type']
          if resource['resource_type'] == 'AWS::ElasticLoadBalancingV2::TargetGroup'
            begin
              tg = elbClient.describe_target_groups({
                target_group_arns: [ resource['physical_resource_id'] ]
              })
            rescue Aws::ElasticLoadBalancingV2::Errors::ServiceError => e
              puts "Error: #{e}"
              exit 1
            end
            stackResources[:template]["#{location[1..-1]}.#{resource['logical_resource_id']}/#{tg['target_groups'][0]['load_balancer_arns'][0]}"] = config['resource_defaults'][resource['resource_type']]
          else
            stackResources[:template]["#{location[1..-1]}.#{resource['logical_resource_id']}"] = config['resource_defaults'][resource['resource_type']]
          end
          stackResourceCount += 1
          stackResourceCountLocal += 1
          print "#{location[1..-1]}: Found #{stackResourceCount} resource#{"s" if stackResourceCount != 1}\r"
          sleep 0.2
        elsif resource['resource_type'] == 'AWS::ElasticLoadBalancingV2::LoadBalancer'
          stackResources[:physical_resource_id][resource['physical_resource_id']] = "#{location[1..-1]}.#{resource['logical_resource_id']}"
        end
      end
      stackResourceQuery = {
        stackResourceCount: stackResourceCount,
        stackResources: stackResources
      }
      sleep 0.2
      puts "#{stack if location == ''}#{location[1..-1]}: Found #{stackResourceCountLocal} resource#{"s" if stackResourceCountLocal != 1}"
      stackResourceQuery
    end

    stackResourceQuery = query_stacks(config,cfClient,elbClient,stack)
    stackResourceCount = stackResourceQuery[:stackResourceCount]
    stackResources = stackResourceQuery[:stackResources]

    configResourceCount = customer_alarms_config['resources'].keys.count
    configResources = []
    keyUpdates = []

    stackResources[:template].each do | k,v |
      if stackResources[:physical_resource_id].key? k.partition('/').last
        keyUpdates << k
      end
    end

    keyUpdates.each do | k |
      stackResources[:template]["#{k.partition('/').first}/#{stackResources[:physical_resource_id][k.partition('/').last]}"] = stackResources[:template].delete(k)
    end

    stackResources[:template].each do | k,v |
      if !customer_alarms_config['resources'].any? {|x, y| x == k}
        configResources.push("#{k}: #{v}")
      end
    end

    puts "-----------------------------------------------"
    puts "Monitorable Resources (with default templates)"
    puts "-----------------------------------------------"
    stackResources[:template].each do | k,v |
      puts "#{k}: #{v}"
    end
    puts "-----------------------------------------------"
    if configResourceCount < stackResourceCount
      puts "Missing resources (with default templates)"
      puts "-----------------------------------------------"
      configResources.each do | r |
        puts r
      end
      puts "-----------------------------------------------"
    end
    puts "Monitorable resources in #{stack} stack: #{stackResourceCount}"
    puts "Resources in #{customer} alarms config: #{configResourceCount}"
    if stackResourceCount > 0
      puts "Coverage: #{100-(configResources.count*100/stackResourceCount)}%"
    end
    puts "-----------------------------------------------"
  end

  def write_cfdndsl_template(alarms_config,configs,customer_alarms_config_file,customer,source_bucket,template_envs,output_path,upload_path)
    FileUtils::mkdir_p output_path
    configs.each_with_index do |config,index|
      File.open("#{output_path}/resources#{index}.json", 'w') { |file|
        file.write(JSON.pretty_generate( CfnDsl.eval_file_with_extras("templates/resources.rb",[[:yaml, config],[:raw, "template_number=#{index}"],[:raw, "source_bucket='#{source_bucket}'"],[:raw, "upload_path='#{upload_path}'"]],STDOUT)))}
      File.open("#{output_path}/alarms#{index}.json", 'w') { |file|
        file.write(JSON.pretty_generate( CfnDsl.eval_file_with_extras("templates/alarms.rb",[[:yaml, config],[:raw, "template_number=#{index}"],[:raw, "template_envs=#{template_envs}"]],STDOUT)))}
    end
    File.open("#{output_path}/endpoints.json", 'w') { |file|
      file.write(JSON.pretty_generate( CfnDsl.eval_file_with_extras("templates/endpoints.rb",[[:yaml, alarms_config],[:raw, "template_envs=#{template_envs}"]],STDOUT)))}
    File.open("#{output_path}/hosts.json", 'w') { |file|
      file.write(JSON.pretty_generate( CfnDsl.eval_file_with_extras("templates/hosts.rb",[[:yaml, alarms_config],[:raw, "template_envs=#{template_envs}"]],STDOUT)))}
    File.open("#{output_path}/master.json", 'w') { |file|
      file.write(JSON.pretty_generate( CfnDsl.eval_file_with_extras("templates/master.rb",[[:yaml, customer_alarms_config_file],[:raw, "templateCount=#{configs.count}"],[:raw, "template_envs=#{template_envs}"],[:raw, "upload_path='#{upload_path}'"]],STDOUT)))}
  end
end

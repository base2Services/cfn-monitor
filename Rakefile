require 'cfndsl/rake_task'
require 'rake'
require 'tempfile'
require 'yaml'
require 'json'
require_relative 'ext/common_helper'
require_relative 'ext/alarms'
require 'fileutils'
require 'digest'

namespace :cfn do

  resource_limit = 50 # Number of alarms per CloudFormation template
  ARGV.each { |a| task a.to_sym do ; end }
  customer = ARGV[1]

  # Global and customer config files
  global_templates_config_file = 'config/templates.yml'
  customer_templates_config_file = "ciinaboxes/#{customer}/monitoring/templates.yml"
  customer_alarms_config_file = "ciinaboxes/#{customer}/monitoring/alarms.yml"

  # Load global and customer config files
  global_templates_config = YAML.load(File.read(global_templates_config_file))
  customer_alarms_config = YAML.load(File.read(customer_alarms_config_file))

  # Merge customer template configs over global template configs
  if File.file?(customer_templates_config_file)
    customer_templates_config = YAML.load(File.read(customer_templates_config_file))
    templates = CommonHelper.deep_merge(global_templates_config, customer_templates_config)
  else
    templates = global_templates_config
  end

  # Write templates config to temporary file for CfnDsl
  templates_input_file = Tempfile.new(["templates-",'.yml'])
  templates_input_file.write(templates.to_yaml)
  templates_input_file.rewind

  # Create an array of alarms based on the templates associated with each resource
  alarms = []
  resources = customer_alarms_config['resources']
  source_bucket = customer_alarms_config['source_bucket']
  resources.each do | resource,templatesEnabled |
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
        templates['templates'][templateEnabled].each do | alarm |
          # Include template name as first element of the individual alarm array
          alarm.insert(0,*[templateEnabled])
          # Add alarm to alarms array with association to resource
          alarms << { resource => alarm }
        end
      end
    end
  end

  # Split resources for mulitple templates to avoid CloudFormation template resource limits
  split = []
  template_envs = ['production']
  alarms.each_with_index do |alarm,index|
    split[index/resource_limit] ||= {}
    split[index/resource_limit]['alarms'] ||= []
    split[index/resource_limit]['alarms'] << alarm
    template_envs |= get_alarm_envs(alarm.values[0][2])
  end

  # Create temp files for split resources for CfnDsl input
  temp_files=[]
  temp_file_paths=[]
  (alarms.count/resource_limit.to_f).ceil.times do | i |
    temp_files[i] = Tempfile.new(["alarms-#{i}-",'.yml'])
    temp_file_paths << temp_files[i].path
    temp_files[i].write(split[i].to_yaml)
    temp_files[i].rewind
  end

  desc('Generate CloudWatch for alarms')
  task :generate do
    ARGV.each { |a| task a.to_sym do ; end }
    write_cfdndsl_template(templates_input_file,temp_file_paths,customer_alarms_config_file,customer,source_bucket,template_envs)
  end

  def write_cfdndsl_template(templates_input_file,configs,customer_alarms_config_file,customer,source_bucket,template_envs)
    FileUtils::mkdir_p "output/#{customer}"
    configs.each_with_index do |config,index|
      File.open("output/#{customer}/resources#{index}.json", 'w') { |file|
        file.write(JSON.pretty_generate( CfnDsl.eval_file_with_extras("templates/resources.rb",[[:yaml, config],[:raw, "template_number=#{index}"],[:raw, "source_bucket='#{source_bucket}'"]],STDOUT)))}
      File.open("output/#{customer}/alarms#{index}.json", 'w') { |file|
        file.write(JSON.pretty_generate( CfnDsl.eval_file_with_extras("templates/alarms.rb",[[:yaml, config],[:raw, "template_number=#{index}"],[:raw, "template_envs=#{template_envs}"]],STDOUT)))}
    end
    File.open("output/#{customer}/master.json", 'w') { |file|
      file.write(JSON.pretty_generate( CfnDsl.eval_file_with_extras("templates/master.rb",[[:yaml, customer_alarms_config_file],[:raw, "templateCount=#{configs.count}"],[:raw, "template_envs=#{template_envs}"]],STDOUT)))}
  end
end

require 'aws-sdk-cloudformation'
require 'aws-sdk-elasticloadbalancingv2'

module CfnMonitor
  class Query

    def self.run(options)

      if !options['stack']
        raise "No stack specified"
      end

      if options['application']
        application = options['application']
        custom_alarms_config_file = "#{application}/alarms.yml"
      else
        application = File.basename(Dir.getwd)
        custom_alarms_config_file = "alarms.yml"
      end

      config_path = File.join(File.dirname(__FILE__),'../config/config.yml')
      # Load global config files
      config = YAML.load(File.read(config_path))

      custom_alarms_config_file = "#{application}/alarms.yml"

      # Load custom config files
      custom_alarms_config = YAML.load(File.read(custom_alarms_config_file)) if File.file?(custom_alarms_config_file)
      custom_alarms_config ||= {}
      custom_alarms_config['resources'] ||= {}

      puts "-----------------------------------------------"
      puts "stack: #{options['stack']}"
      puts "application: #{application}"
      puts "-----------------------------------------------"
      puts "Searching Stacks for Monitorable Resources"
      puts "-----------------------------------------------"

      cfClient = Aws::CloudFormation::Client.new()
      elbClient = Aws::ElasticLoadBalancingV2::Client.new()

      stackResourceQuery = query_stacks(config,cfClient,elbClient,options['stack'])
      stackResourceCount = stackResourceQuery[:stackResourceCount]
      stackResources = stackResourceQuery[:stackResources]

      configResourceCount = custom_alarms_config['resources'].keys.count
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
        if !custom_alarms_config['resources'].any? {|x, y| x == k}
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
      puts "Monitorable resources in #{options['stack']} stack: #{stackResourceCount}"
      puts "Resources in #{application} alarms config: #{configResourceCount}"
      if stackResourceCount > 0
        puts "Coverage: #{100-(configResources.count*100/stackResourceCount)}%"
      end
      puts "-----------------------------------------------"

    end

    def self.query_stacks (config,cfClient,elbClient,stack,stackResources={template:{},physical_resource_id:{}},location='')
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
            if location[1..-1].nil?
                stackResources[:template]["#{stack}::#{resource['logical_resource_id']}"] = config['resource_defaults'][resource['resource_type']]
            else
                stackResources[:template]["#{location[1..-1]}.#{resource['logical_resource_id']}"] = config['resource_defaults'][resource['resource_type']]
            end
          end
          stackResourceCount += 1
          stackResourceCountLocal += 1
          if location[1..-1].nil?
            print "#{stack}: Found #{stackResourceCount} resource#{"s" if stackResourceCount != 1}\r"
           else
            print "#{location[1..-1]}: Found #{stackResourceCount} resource#{"s" if stackResourceCount != 1}\r"
           end
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

  end
end

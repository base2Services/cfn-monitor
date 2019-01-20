require 'cfndsl'

CloudFormation do
  Description("CloudWatch ECS Container Instances")

  Parameter("EcsCICheckFunctionArn"){
    Type 'String'
  }

  Parameter("MonitoredStack"){
    Type 'String'
  }
  Parameter("GetPhysicalIdFunctionArn"){
    Type 'String'
  }
  Parameter("EnvironmentName"){
    Type 'String'
  }
  Parameter("ConfigToggle"){
    Type 'String'
  }

  alarms.each do |alarm|
    if alarm[:type] == 'ecsCluster'

      resourceHash =  Digest::MD5.hexdigest alarm[:resource]

      Resource("GetPhysicalId#{resourceHash}") do
        Type 'Custom::GetResourcePhysicalId'
        Property('ServiceToken', Ref('GetPhysicalIdFunctionArn'))
        Property('StackName', Ref('MonitoredStack'))
        if alarm[:resource].include? "::"
          Property('LogicalResourceId', alarm[:resource].gsub('::','.') )
        else
          Property('LogicalResourceId', FnJoin( '.', [ Ref('MonitoredStack'), alarm[:resource] ] ))
        end
        Property('Region', Ref('AWS::Region'))
        Property('ConfigToggle', Ref('ConfigToggle'))
      end

      # Conditionally create shedule based on environments attribute
      if alarm[:environments] != ['all']
        conditions = []
        alarm[:environments].each do | env |
          conditions << FnEquals(Ref("EnvironmentName"),env)
        end
        if conditions.length > 1
          Condition("Condition#{resourceHash}", FnOr(conditions))
        else
          Condition("Condition#{resourceHash}", conditions[0])
        end
      end

      # Set defaults
      params = alarm[:parameters]
      params['scheduleExpression'] ||= "0/5 * * * ? *"

      Events_Rule("EcsCICheckSchedule#{resourceHash}") {
        Condition "Condition#{resourceHash}" if alarm[:environments] != ['all']
        Description FnJoin("",["ECS container instance check for the ", FnGetAtt("GetPhysicalId#{resourceHash}",'PhysicalResourceId') ," ECS cluster"])
        ScheduleExpression "cron(#{params['scheduleExpression']})"
        State params['enabled'] ? 'ENABLED' : 'DISABLED'
        Targets([
            {
              Arn: Ref('EcsCICheckFunctionArn'),
              Id: resourceHash,
              Input: FnSub({CLUSTER: '${cluster}'}.to_json, cluster: FnGetAtt("GetPhysicalId#{resourceHash}",'PhysicalResourceId'))
            }
        ])
      }

    end

  end

end

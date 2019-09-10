require 'cfndsl'

CloudFormation do
  Description("CloudWatch SQL Queries")

  Parameter("MonitoredStack"){
    Type 'String'
  }
  Parameter("EnvironmentName"){
    Type 'String'
  }
  Parameter("SslCheckFunctionArn"){
    Type 'String'
  }

  alarms.each do |alarm|
    if alarm[:type] == 'ss'
      endpointHash =  Digest::MD5.hexdigest "ssl-" + alarm[:resource]

      # Conditionally create shedule based on environments attribute
      if alarm[:environments] != ['all']
        conditions = []
        alarm[:environments].each do | env |
          conditions << FnEquals(Ref("EnvironmentName"),env)
        end
        if conditions.length > 1
          Condition("Condition#{endpointHash}", FnOr(conditions))
        else
          Condition("Condition#{endpointHash}", conditions[0])
        end
      end

      params = alarm[:parameters]

      # Set defaults
      params['scheduleExpression'] ||= "0 12 * * ? *"   # 12PM every day

      # Create payload
      payload = {}
      payload['Url'] = alarm[:resource]
      payload['Region'] = "${region}"

      endpointHash =  Digest::MD5.hexdigest alarm[:resource]
      Resource("SslCheckSchedule#{endpointHash}") do
        Condition "Condition#{endpointHash}" if alarm[:environments] != ['all']
        Type 'AWS::Events::Rule'
        Property('Description', "#{payload['Url']}")
        Property('ScheduleExpression', "cron(#{params['scheduleExpression']})")
        Property('State', 'ENABLED')
        Property('Targets', [
          {
            Arn: Ref('SslCheckFunctionArn'),
            Id: endpointHash,
            Input: FnSub(payload.to_json, region: Ref("AWS::Region"))
          }
        ])
      end
    end
  end

end

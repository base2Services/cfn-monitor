require 'cfndsl'

CloudFormation do
  Description("CloudWatch Endpoints")

  Parameter("MonitoredStack"){
    Type 'String'
  }
  Parameter("EnvironmentName"){
    Type 'String'
  }
  Parameter("HttpCheckFunctionArn"){
    Type 'String'
  }

  alarms.each do |alarm|
    if alarm[:type] == 'endpoint'
      endpointHash =  Digest::MD5.hexdigest alarm[:resource]

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

      ep = alarm[:parameters]

      # Set defaults
      ep['scheduleExpression'] ||= "* * * * ? *"

      # Create payload
      payload = {}
      payload['TIMEOUT'] = ep['timeOut'] || 120
      payload['STATUS_CODE_MATCH'] = ep['statusCode'] || 200
      payload['ENDPOINT'] = alarm[:resource]
      payload['BODY_REGEX_MATCH'] = ep['bodyRegex'] if !ep['bodyRegex'].nil?
      payload['HEADERS'] = ep['headers'] if !ep['headers'].nil?
      payload['METHOD'] = ep['method'] || "GET"
      payload['PAYLOAD'] = ep['payload'] if !ep['payload'].nil?

      endpointHash =  Digest::MD5.hexdigest alarm[:resource]
      Resource("HttpCheckSchedule#{endpointHash}") do
        Condition "Condition#{endpointHash}" if alarm[:environments] != ['all']
        Type 'AWS::Events::Rule'
        Property('Description', FnSub( payload['ENDPOINT'], env: Ref('EnvironmentName') ) )
        Property('ScheduleExpression', "cron(#{ep['scheduleExpression']})")
        Property('State', 'ENABLED')
        Property('Targets', [
          {
            Arn: Ref('HttpCheckFunctionArn'),
            Id: endpointHash,
            Input: FnSub( payload.to_json, env: Ref('EnvironmentName') )
          }
        ])
      end
    end
  end

end

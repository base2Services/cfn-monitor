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

  endpoints ||= {}
  endpoints.each do |ep|
    # Flatten array/hash into simple hash
    endpoint = ep[0]
    ep = ep[1]
    ep['endpoint'] = endpoint

    # Set defaults
    ep['ScheduleExpression'] ||= "* * * * ? *"

    # Create payload
    payload = {}
    payload['TIMEOUT'] = ep['timeOut'] || 120
    payload['STATUS_CODE_MATCH'] = ep['statusCode'] || 200
    payload['ENDPOINT'] = ep['endpoint']
    payload['BODY_REGEX_MATCH'] = ep['bodyRegex'] if !ep['bodyRegex'].nil?

    endpointHash =  Digest::MD5.hexdigest ep['endpoint']
    Resource("HttpCheckSchedule#{endpointHash}") do
      Type 'AWS::Events::Rule'
      Property('ScheduleExpression', "cron(#{ep['ScheduleExpression']})")
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

require 'cfndsl'

CloudFormation do

  Description("CloudWatch Alarms Master")

  Parameter("MonitoredStack"){
    Type 'String'
  }
  Parameter("SnsTopicCrit"){
    Type 'String'
  }
  Parameter("SnsTopicWarn"){
    Type 'String'
  }
  Parameter("SnsTopicTask"){
    Type 'String'
  }
  Parameter("MonitoringDisabled"){
    Type 'String'
    Default false
    AllowedValues [true,false]
  }
  Parameter("EnvironmentType"){
    Type 'String'
    AllowedValues template_envs
    Default 'production'
  }
  Parameter("ConfigToggle"){
    Type 'String'
    AllowedValues ['up','down']
    Default 'up'
  }

  Resource("CFLambdaExecutionRole") do
    Type 'AWS::IAM::Role'
    Property('AssumeRolePolicyDocument', {
      Version: '2012-10-17',
      Statement: [{
        Effect: 'Allow',
        Principal: { Service: [ 'lambda.amazonaws.com' ] },
        Action: [ 'sts:AssumeRole' ]
      }]
    })
    Property('Path','/')
    Property('Policies', [
      PolicyName: 'CloudFormationReadOnly',
      PolicyDocument: {
        Version: '2012-10-17',
        Statement: [{
          Effect: 'Allow',
          Action: [ 'logs:CreateLogGroup', 'logs:CreateLogStream', 'logs:PutLogEvents' ],
          Resource: 'arn:aws:logs:*:*:*'
        },
        {
          Effect: 'Allow',
          Action: [ 'cloudformation:Describe*', 'cloudformation:Get*', 'cloudformation:List*' ],
          Resource: '*'
        }]
      }
    ])
  end

  Resource("HttpLambdaExecutionRole") do
    Type 'AWS::IAM::Role'
    Property('AssumeRolePolicyDocument', {
      Version: '2012-10-17',
      Statement: [{
        Effect: 'Allow',
        Principal: { Service: [ 'lambda.amazonaws.com' ] },
        Action: [ 'sts:AssumeRole' ]
      }]
    })
    Property('Path','/')
    Property('Policies', [
      PolicyName: 'CloudFormationReadOnly',
      PolicyDocument: {
        Version: '2012-10-17',
        Statement: [{
          Effect: 'Allow',
          Action: [ 'logs:CreateLogGroup', 'logs:CreateLogStream', 'logs:PutLogEvents' ],
          Resource: 'arn:aws:logs:*:*:*'
        },
        {
          Effect: 'Allow',
          Action: [ 'cloudwatch:PutMetricData' ],
          Resource: '*'
        }]
      }
    ])
  end

  Resource("GetPhysicalIdFunction") do
    Type 'AWS::Lambda::Function'
    Property('Code', { ZipFile: FnJoin("", IO.readlines("ext/lambda/getPhysicalId.py").each { |line| "\"#{line}\"," }) })
    Property('Handler', 'index.handler')
    Property('MemorySize', 128)
    Property('Runtime', 'python2.7')
    Property('Timeout', 300)
    Property('Role', FnGetAtt('CFLambdaExecutionRole','Arn'))
  end

  Resource("GetEnvironmentNameFunction") do
    Type 'AWS::Lambda::Function'
    Property('Code', { ZipFile: FnJoin("", IO.readlines("ext/lambda/getEnvironmentName.py").each { |line| "\"#{line}\"," }) })
    Property('Handler', 'index.handler')
    Property('MemorySize', 128)
    Property('Runtime', 'python2.7')
    Property('Timeout', 300)
    Property('Role', FnGetAtt('CFLambdaExecutionRole','Arn'))
  end

  Resource("GetEnvironmentName") do
    Type 'Custom::GetEnvironmentName'
    Property('ServiceToken',FnGetAtt('GetEnvironmentNameFunction','Arn'))
    Property('StackName', Ref('MonitoredStack'))
    Property('Region', Ref('AWS::Region'))
    Property('ConfigToggle', Ref('ConfigToggle'))
  end

  Resource("HttpCheckFunction") do
    Type 'AWS::Lambda::Function'
    Property('Code', { S3Bucket: FnJoin('.',[Ref('AWS::Region'),'aws-lambda-http-check']), S3Key: 'httpCheck-v2.zip' })
    Property('Handler', 'handler.http_check')
    Property('MemorySize', 128)
    Property('Runtime', 'python3.6')
    Property('Timeout', 300)
    Property('Role', FnGetAtt('HttpLambdaExecutionRole','Arn'))
  end

  Resource("HttpCheckPermissions") do
    Type 'AWS::Lambda::Permission'
    Property('FunctionName', Ref('HttpCheckFunction'))
    Property('Action', 'lambda:InvokeFunction')
    Property('Principal', 'events.amazonaws.com')
  end

  params = {
    MonitoredStack: Ref('MonitoredStack'),
    SnsTopicCrit: Ref('SnsTopicCrit'),
    SnsTopicWarn: Ref('SnsTopicWarn'),
    SnsTopicTask: Ref('SnsTopicTask'),
    MonitoringDisabled: Ref('MonitoringDisabled'),
    EnvironmentType: Ref('EnvironmentType'),
    GetPhysicalIdFunctionArn: FnGetAtt('GetPhysicalIdFunction','Arn'),
    EnvironmentName: FnGetAtt('GetEnvironmentName', 'EnvironmentName' ),
    ConfigToggle: Ref('ConfigToggle')
  }

  templateCount.times do |i|
    Resource("ResourcesStack#{i}") do
      Type 'AWS::CloudFormation::Stack'
      Property('TemplateURL', "https://#{source_bucket}.s3.amazonaws.com/#{upload_path}/resources#{i}.json")
      Property('TimeoutInMinutes', 5)
      Property('Parameters', params)
    end
  end

  endpointParams = {
    MonitoredStack: Ref('MonitoredStack'),
    HttpCheckFunctionArn: FnGetAtt('HttpCheckFunction','Arn'),
    EnvironmentName: FnGetAtt('GetEnvironmentName', 'EnvironmentName' )
  }

  endpoints ||= {}
  if !endpoints.empty?
    Resource("EndpointsStack") do
      Type 'AWS::CloudFormation::Stack'
      Property('TemplateURL', "https://#{source_bucket}.s3.amazonaws.com/#{upload_path}/endpoints.json")
      Property('TimeoutInMinutes', 5)
      Property('Parameters', endpointParams)
    end
  end

  hostParams = {
    EnvironmentName: FnGetAtt('GetEnvironmentName', 'EnvironmentName' )
  }

  hosts ||= {}
  if !hosts.empty?
    Resource("HostsStack") do
      Type 'AWS::CloudFormation::Stack'
      Property('TemplateURL', "https://#{source_bucket}.s3.amazonaws.com/#{upload_path}/hosts.json")
      Property('TimeoutInMinutes', 5)
      Property('Parameters', hostParams)
    end
  end

  servicesParams = {
    EnvironmentName: FnGetAtt('GetEnvironmentName', 'EnvironmentName' )
  }

  services ||= {}
  if !services.empty?
    Resource("ServicesStack") do
      Type 'AWS::CloudFormation::Stack'
      Property('TemplateURL', "https://#{source_bucket}.s3.amazonaws.com/#{upload_path}/services.json")
      Property('TimeoutInMinutes', 5)
      Property('Parameters', servicesParams)
    end
  end

  Output("RenderDate") { Value(Time.now.strftime("%Y-%m-%d")) }
  Output("MonitoredStack") { Value(Ref("MonitoredStack")) }
  Output("StackName") { Value(Ref("AWS::StackName")) }
  Output("Region") { Value(Ref("AWS::Region")) }
  Output("MonitoringDisabled") { Value(Ref("MonitoringDisabled")) }

end

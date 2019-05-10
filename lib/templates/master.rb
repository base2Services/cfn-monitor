require 'cfndsl'
require 'cfn_monitor/version'

src_lambda_dir = File.expand_path("../../lambda", __FILE__)

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
  Parameter("SnsTopicInfo"){
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

  Resource("EcsCICheckLambdaExecutionRole") do
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
          Action: [ 'ecs:ListContainerInstances', 'ecs:DescribeContainerInstances' ],
          Resource: '*'
        },
        {
          Effect: 'Allow',
          Action: [ 'cloudwatch:PutMetricData' ],
          Resource: '*'
        }]
      }
    ])
  end

  Resource("LambdaExecutionRole") do
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
    Property('Code', { ZipFile: FnJoin("", IO.readlines("#{src_lambda_dir}/getPhysicalId.py").each { |line| "\"#{line}\"," }) })
    Property('Handler', 'index.handler')
    Property('MemorySize', 128)
    Property('Runtime', 'python2.7')
    Property('Timeout', 300)
    Property('Role', FnGetAtt('CFLambdaExecutionRole','Arn'))
  end

  Resource("GetEnvironmentNameFunction") do
    Type 'AWS::Lambda::Function'
    Property('Code', { ZipFile: FnJoin("", IO.readlines("#{src_lambda_dir}/getEnvironmentName.py").each { |line| "\"#{line}\"," }) })
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
    Property('Code', { S3Bucket: FnJoin('.', ['base2.lambda', Ref('AWS::Region')]), S3Key: 'aws-lambda-http-check/0.1/handler.zip' })
    Property('Handler', 'handler.main')
    Property('MemorySize', 128)
    Property('Runtime', 'python3.6')
    Property('Timeout', 120)
    Property('Role', FnGetAtt('LambdaExecutionRole','Arn'))
  end

  Resource("HttpCheckPermissions") do
    Type 'AWS::Lambda::Permission'
    Property('FunctionName', Ref('HttpCheckFunction'))
    Property('Action', 'lambda:InvokeFunction')
    Property('Principal', 'events.amazonaws.com')
  end

  Resource("SslCheckFunction") do
    Type 'AWS::Lambda::Function'
    Property('Code', { S3Bucket: FnJoin('.', ['base2.lambda', Ref('AWS::Region')]), S3Key: 'aws-lambda-ssl-check/0.1/handler.zip' })
    Property('Handler', 'main')
    Property('MemorySize', 128)
    Property('Runtime', 'go1.x')
    Property('Timeout', 30)
    Property('Role', FnGetAtt('LambdaExecutionRole','Arn'))
  end

  Resource("SslCheckPermissions") do
    Type 'AWS::Lambda::Permission'
    Property('FunctionName', Ref('SslCheckFunction'))
    Property('Action', 'lambda:InvokeFunction')
    Property('Principal', 'events.amazonaws.com')
  end

  Resource("DnsCheckFunction") do
    Type 'AWS::Lambda::Function'
    Property('Code', { S3Bucket: FnJoin('.', ['base2.lambda', Ref('AWS::Region')]), S3Key: 'aws-lambda-dns-check/0.1/handler.zip' })
    Property('Handler', 'main')
    Property('MemorySize', 128)
    Property('Runtime', 'go1.x')
    Property('Timeout', 30)
    Property('Role', FnGetAtt('LambdaExecutionRole','Arn'))
  end

  Resource("DnsCheckPermissions") do
    Type 'AWS::Lambda::Permission'
    Property('FunctionName', Ref('DnsCheckFunction'))
    Property('Action', 'lambda:InvokeFunction')
    Property('Principal', 'events.amazonaws.com')
  end

  Resource("EcsCICheckFunction") do
    Type 'AWS::Lambda::Function'
    Property('Code', { S3Bucket: FnJoin('.', ['base2.lambda', Ref('AWS::Region')]), S3Key: 'aws-lambda-ecs-container-instance-check/0.1/handler.zip' })
    Property('Handler', 'handler.run_check')
    Property('MemorySize', 128)
    Property('Runtime', 'python3.6')
    Property('Timeout', 30)
    Property('Role', FnGetAtt('EcsCICheckLambdaExecutionRole','Arn'))
  end

  Resource("EcsCICheckPermissions") do
    Type 'AWS::Lambda::Permission'
    Property('FunctionName', Ref('EcsCICheckFunction'))
    Property('Action', 'lambda:InvokeFunction')
    Property('Principal', 'events.amazonaws.com')
  end

  params = {
    MonitoredStack: Ref('MonitoredStack'),
    SnsTopicCrit: Ref('SnsTopicCrit'),
    SnsTopicWarn: Ref('SnsTopicWarn'),
    SnsTopicTask: Ref('SnsTopicTask'),
    SnsTopicInfo: Ref('SnsTopicInfo'),
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

  sslParams = {
    MonitoredStack: Ref('MonitoredStack'),
    SslCheckFunctionArn: FnGetAtt('SslCheckFunction','Arn'),
    EnvironmentName: FnGetAtt('GetEnvironmentName', 'EnvironmentName' )
  }

  ssl ||= {}
  if !ssl.empty?
    Resource("SslStack") do
      Type 'AWS::CloudFormation::Stack'
      Property('TemplateURL', "https://#{source_bucket}.s3.amazonaws.com/#{upload_path}/ssl.json")
      Property('TimeoutInMinutes', 5)
      Property('Parameters', sslParams)
    end
  end

  dnsParams = {
    MonitoredStack: Ref('MonitoredStack'),
    DnsCheckFunctionArn: FnGetAtt('DnsCheckFunction','Arn'),
    EnvironmentName: FnGetAtt('GetEnvironmentName', 'EnvironmentName' )
  }

  dns ||= {}
  if !dns.empty?
    Resource("DnsStack") do
      Type 'AWS::CloudFormation::Stack'
      Property('TemplateURL', "https://#{source_bucket}.s3.amazonaws.com/#{upload_path}/dns.json")
      Property('TimeoutInMinutes', 5)
      Property('Parameters', dnsParams)
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

  ecsClusterParams = {
    MonitoredStack: Ref('MonitoredStack'),
    GetPhysicalIdFunctionArn: FnGetAtt('GetPhysicalIdFunction','Arn'),
    EnvironmentName: FnGetAtt('GetEnvironmentName', 'EnvironmentName' ),
    ConfigToggle: Ref('ConfigToggle'),
    EcsCICheckFunctionArn: FnGetAtt('EcsCICheckFunction','Arn')
  }

  ecsClusters ||= {}
  if !ecsClusters.empty?
    Resource("ServicesStack") do
      Type 'AWS::CloudFormation::Stack'
      Property('TemplateURL', "https://#{source_bucket}.s3.amazonaws.com/#{upload_path}/ecsClusters.json")
      Property('TimeoutInMinutes', 5)
      Property('Parameters', ecsClusterParams)
    end
  end

  Output("CfnMonitorVersion") { Value(CfnMonitor::VERSION) }
  Output("RenderDate") { Value(Time.now.strftime("%Y-%m-%d")) }
  Output("MonitoredStack") { Value(Ref("MonitoredStack")) }
  Output("StackName") { Value(Ref("AWS::StackName")) }
  Output("Region") { Value(Ref("AWS::Region")) }
  Output("MonitoringDisabled") { Value(Ref("MonitoringDisabled")) }

end

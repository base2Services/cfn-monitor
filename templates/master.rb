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
          Action: [ 'cloudformation:Describe*', 'cloudformation:Get*', 'cloudformation:List*' ],
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
    Property('Role', FnGetAtt('LambdaExecutionRole','Arn'))
  end

  Resource("GetEnvironmentNameFunction") do
    Type 'AWS::Lambda::Function'
    Property('Code', { ZipFile: FnJoin("", IO.readlines("ext/lambda/getEnvironmentName.py").each { |line| "\"#{line}\"," }) })
    Property('Handler', 'index.handler')
    Property('MemorySize', 128)
    Property('Runtime', 'python2.7')
    Property('Timeout', 300)
    Property('Role', FnGetAtt('LambdaExecutionRole','Arn'))
  end

  Resource("GetEnvironmentName") do
    Type 'Custom::GetEnvironmentName'
    Property('ServiceToken',FnGetAtt('GetEnvironmentNameFunction','Arn'))
    Property('StackName', Ref('MonitoredStack'))
    Property('Region', Ref('AWS::Region'))
  end

  params = {
    MonitoredStack: Ref('MonitoredStack'),
    SnsTopicCrit: Ref('SnsTopicCrit'),
    SnsTopicWarn: Ref('SnsTopicWarn'),
    SnsTopicTask: Ref('SnsTopicTask'),
    MonitoringDisabled: Ref('MonitoringDisabled'),
    EnvironmentType: Ref('EnvironmentType'),
    GetPhysicalIdFunctionArn: FnGetAtt('GetPhysicalIdFunction','Arn'),
    EnvironmentName: FnGetAtt('GetEnvironmentName', 'EnvironmentName' )
  }

  templateCount.times do |i|
    Resource("ResourcesStack#{i}") do
      Type 'AWS::CloudFormation::Stack'
      Property('TemplateURL', "https://#{source_bucket}.s3.amazonaws.com/cloudformation/monitoring/resources#{i}.json")
      Property('TimeoutInMinutes', 5)
      Property('Parameters', params)
    end
  end

end

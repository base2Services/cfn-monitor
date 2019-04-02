require 'cfndsl'

CloudFormation do
  Description("CloudWatch Endpoints")

  Parameter("MonitoredStack"){
    Type 'String'
  }
  Parameter("EnvironmentName"){
    Type 'String'
  }

  Resource("SqlLambdaExecutionRole") do
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
      PolicyName: 'SQL',
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
        },
        {
          Effect: 'Allow',
          Action: [ 'ec2:CreateNetworkInterface', 'ec2:DescribeNetworkInterfaces', 'ec2:DeleteNetworkInterface' ],
          Resource: '*'
        }]
      }
    ])
  end

  alarms.each do |alarm|
    if alarm[:type] == 'sq'

      config = alarm[:parameters]
      configHash =  Digest::MD5.hexdigest ("sql-" + config['subnetIds'].sort().join() + config['vpcId'])

      # No default as this is value is highly variable
      #params['scheduleExpression'] ||= "0 12 * * ? *"

      Resource("SqlSecurityGroup#{configHash}") {
        Type 'AWS::EC2::SecurityGroup'
        Property('VpcId', config['vpcId'])
        Property('GroupDescription', "Monitoring Security Group (SQL)")
      }

      Resource("SqlCheckFunction#{configHash}") do
        Type 'AWS::Lambda::Function'
        Property('Code', { S3Bucket: FnJoin('.', ['base2.lambda', Ref('AWS::Region')]), S3Key: 'aws-lambda-sql-check/0.2/handler.zip' })
        Property('Handler', 'main')
        Property('MemorySize', 128)
        Property('Runtime', 'go1.x')
        Property('Timeout', 300)
        Property('Role', FnGetAtt("SqlLambdaExecutionRole",'Arn'))
        Property('VpcConfig', {
          SecurityGroupIds: config['securityGroupIds'] || [  Ref("SqlSecurityGroup#{configHash}") ],
          SubnetIds: config['subnetIds']
        })
      end

      Resource("SqlCheckPermissions#{configHash}") do
        Type 'AWS::Lambda::Permission'
        Property('FunctionName', Ref("SqlCheckFunction#{configHash}"))
        Property('Action', 'lambda:InvokeFunction')
        Property('Principal', 'events.amazonaws.com')
      end

      # e.g. db_user:password@tcp(localhost:3306)/my_db
      connection_string = "#{config['databaseUsername']}:#{config['databasePassword']}@tcp(#{config['databaseHost']}:#{config['databasePort']})"
      if config.key?('databaseName')
        connection_string += "/#{config['databaseName']}"
      end

      #p "Connection string for metric is: #{connection_string}"

      # Create payload
      payload = {
        SqlHost:      config['databaseHost'],
        SqlDriver:    config['databaseDriver'],
        SqlCall:      config['databaseQuery'],
        SqlConnectionString: connection_string,
        MetricName:   alarm[:resource],
        Region:       "${region}",
        TestType:     '1-row-1-value-zero-is-good'
      }

      Resource("SqlCheckSchedule#{configHash}") do
        Type 'AWS::Events::Rule'
        Property('Description', "#{config['databaseHost']} => #{alarm[:resource]}")
        Property('ScheduleExpression', config['scheduleExpression'])
        Property('State', 'ENABLED')
        Property('Targets', [
          {
            Arn: FnGetAtt("SqlCheckFunction#{configHash}", "Arn"),
            Id: configHash,
            Input: FnSub(payload.to_json, region: Ref("AWS::Region"))
          }
        ])
      end
    end
  end
end

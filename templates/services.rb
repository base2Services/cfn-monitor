require 'cfndsl'

CloudFormation do
  Description("CloudWatch Services")

  Parameter("EnvironmentName"){
    Type 'String'
  }

  Resource("ServicesCheckLambdaExecutionRole") do
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
      PolicyName: 'ServicesCheck',
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
          Action: [ 'ssm:SendCommand', 'ssm:ListCommandInvocations', 'ssm:DescribeInstanceProperties' ],
          Resource: '*'
        },
        {
          Effect: 'Allow',
          Action: [ 'autoscaling:SetInstanceHealth', 'ec2:DescribeInstances' ],
          Resource: '*'
        }]
      }
    ])
  end

  Resource("ServicesCheckFunction") do
    Type 'AWS::Lambda::Function'
    Property('Code', { S3Bucket: FnJoin('.',['base2.lambda',Ref('AWS::Region')]), S3Key: 'check-services.zip' })
    Property('Handler', 'lambda_handler')
    Property('MemorySize', 128)
    Property('Runtime', 'python2.7')
    Property('Timeout', 300)
    Property('Role', FnGetAtt("ServicesCheckLambdaExecutionRole",'Arn'))
  end

  Resource("ServicesCheckPermissions") do
    Type 'AWS::Lambda::Permission'
    Property('FunctionName', Ref("ServicesCheckFunction"))
    Property('Action', 'lambda:InvokeFunction')
    Property('Principal', 'events.amazonaws.com')
  end

  SSM_Document('ServiceCheck') do
    Content ({
      schemaVersion: "2.2",
      description: "Check status of a running services using the service command",
      parameters: {
        Process: {
          type: "String",
          description: "process name to check",
          default: ""
        }
      },
      mainSteps: [ {
        action: "aws:runShellScript",
        name: "checkProcess",
        inputs: {
          runCommand: [ "service {{Process}} status" ]
        }
      } ]
    })
  end

  alarms.each do |alarm|
    if alarm[:type] == 'service'
      servicesHash = Digest::MD5.hexdigest alarm[:resource]

      # Conditionally create shedule based on environments attribute
      if alarm[:environments] != ['all']
        conditions = []
        alarm[:environments].each do | env |
          conditions << FnEquals(Ref("EnvironmentName"),env)
        end
        if conditions.length > 1
          Condition("Condition#{servicesHash}", FnOr(conditions))
        else
          Condition("Condition#{servicesHash}", conditions[0])
        end
      end

      # Set defaults
      services = alarm[:parameters]
      services['scheduleExpression'] ||= "* * * * ? *"

      # Create payload
      payload = {}
      payload['service'] = alarm[:resource]
      payload['environment'] = "${env}"
      payload['region'] = "${region}"
      payload['track_failed_ssm'] = services['track_failed_ssm']
      payload['cw_namespace'] = 'Services'
      payload['terminate_on_failure'] = services['terminate_on_failure']

      Resource("ServicesCheckSchedule#{servicesHash}") do
        Condition "Condition#{servicesHash}" if alarm[:environments] != ['all']
        Type 'AWS::Events::Rule'
        Property('Description', FnSub( "${env}-Service-Check-#{alarm[:resource]}", env: Ref('EnvironmentName') ) )
        Property('ScheduleExpression', "cron(#{services['scheduleExpression']})")
        Property('State', 'ENABLED')
        Property('Targets', [
          {
            Arn: FnGetAtt("ServicesCheckFunction",'Arn'),
            Id: servicesHash,
            Input: FnSub( payload.to_json, env: Ref('EnvironmentName'), region: Ref("AWS::Region") )
          }
        ])
      end

    end
  end

end

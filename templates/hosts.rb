require 'cfndsl'

CloudFormation do
  Description("CloudWatch Hosts")

  Parameter("EnvironmentName"){
    Type 'String'
  }

  alarms.each do |alarm|
    if alarm[:type] == 'host'
      hostHash = Digest::MD5.hexdigest alarm[:resource]

      # Conditionally create shedule based on environments attribute
      if alarm[:environments] != ['all']
        conditions = []
        alarm[:environments].each do | env |
          conditions << FnEquals(Ref("EnvironmentName"),env)
        end
        if conditions.length > 1
          Condition("Condition#{hostHash}", FnOr(conditions))
        else
          Condition("Condition#{hostHash}", conditions[0])
        end
      end

      # Set defaults
      host = alarm[:parameters]
      host['scheduleExpression'] ||= "* * * * ? *"

      Resource("NrpeLambdaExecutionRole#{hostHash}") do
        Condition "Condition#{hostHash}" if alarm[:environments] != ['all']
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
          PolicyName: 'NRPE',
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

      Resource("SecurityGroup#{hostHash}") {
        Condition "Condition#{hostHash}" if alarm[:environments] != ['all']
        Type 'AWS::EC2::SecurityGroup'
        Property('VpcId', host['vpdId'])
        Property('GroupDescription', "Monitoring Security Group #{hostHash}")
      }

      Resource("NrpeCheckFunction#{hostHash}") do
        Condition "Condition#{hostHash}" if alarm[:environments] != ['all']
        Type 'AWS::Lambda::Function'
        Property('Code', { S3Bucket: FnJoin('.',['base2.lambda',Ref('AWS::Region')]), S3Key: 'nrpe.zip' })
        Property('Handler', 'nrpe')
        Property('MemorySize', 128)
        Property('Runtime', 'go1.x')
        Property('Timeout', 300)
        Property('Role', FnGetAtt("NrpeLambdaExecutionRole#{hostHash}",'Arn'))
        Property('VpcConfig', {
          SecurityGroupIds: [ Ref("SecurityGroup#{hostHash}") ],
          SubnetIds: host['subnetIds']
        })
      end

      Resource("NrpeCheckPermissions#{hostHash}") do
        Condition "Condition#{hostHash}" if alarm[:environments] != ['all']
        Type 'AWS::Lambda::Permission'
        Property('FunctionName', Ref("NrpeCheckFunction#{hostHash}"))
        Property('Action', 'lambda:InvokeFunction')
        Property('Principal', 'events.amazonaws.com')
      end

      cmds = host['cmds']
      if !cmds.kind_of?(Array) then cmds = cmds.split end
      cmds.each do |cmd|

        # Create payload
        payload = {}
        payload['host'] = alarm[:resource]
        payload['environment'] = "${env}"
        payload['region'] = "${region}"
        payload['cmd'] = cmd

        cmdHash = Digest::MD5.hexdigest cmd
        Resource("NrpeCheckSchedule#{hostHash}#{cmdHash}") do
          Condition "Condition#{hostHash}" if alarm[:environments] != ['all']
          Type 'AWS::Events::Rule'
          Property('Description', FnSub( "${env}-#{alarm[:resource]} #{cmd}", env: Ref('EnvironmentName') ) )
          Property('ScheduleExpression', "cron(#{host['scheduleExpression']})")
          Property('State', 'ENABLED')
          Property('Targets', [
            {
              Arn: FnGetAtt("NrpeCheckFunction#{hostHash}",'Arn'),
              Id: hostHash,
              Input: FnSub( payload.to_json, env: Ref('EnvironmentName'), region: Ref("AWS::Region") )
            }
          ])
        end
      end
    end
  end

end

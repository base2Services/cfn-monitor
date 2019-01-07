require 'cfndsl'
require_relative '../ext/alarms'

CloudFormation do
  Description("CloudWatch Alarms #{template_number}")

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
  }
  Parameter("EnvironmentType"){
    Type 'String'
  }
  Parameter("EnvironmentName"){
    Type 'String'
  }

  Condition('MonitoringDisabled', FnEquals(Ref("MonitoringDisabled"),'true'))
  Condition('CritSNS', FnNot(FnEquals(Ref("SnsTopicCrit"),'')))
  Condition('WarnSNS', FnNot(FnEquals(Ref("SnsTopicWarn"),'')))
  Condition('TaskSNS', FnNot(FnEquals(Ref("SnsTopicTask"),'')))

  actionsEnabledMap = {
    crit: FnIf('CritSNS',[ Ref('SnsTopicCrit') ], [ ]),
    warn: FnIf('WarnSNS',[ Ref('SnsTopicWarn') ], [ ]),
    task: FnIf('TaskSNS',[ Ref('SnsTopicTask') ], [ ])
  }

  alarms.each do |alarm|

    # Should create or disable the alarms?
    next if (defined? alarm[:parameters]['CreateAlarm']) and alarm[:parameters]['CreateAlarm'] == false

    if (defined? alarm[:parameters]['DisableAlarm']) and alarm[:parameters]['DisableAlarm'] == true then
      alarm[:parameters]['ActionsEnabled'] = 'false'
      alarm[:parameters].delete('DisableAlarm')  # Remove the key from the CFN output
    end

    resourceGroup = alarm[:resource]
    resources = resourceGroup.split('/')
    type = alarm[:type]
    template = alarm[:template]
    name = alarm[:alarm]
    params = alarm[:parameters]
    cmd = params['cmd'] || ''

    alarmHash = Digest::MD5.hexdigest "#{resourceGroup}#{template}#{name}#{cmd}"

    # Set defaults for optional parameters
    params['TreatMissingData']  ||= 'missing'
    params['AlarmDescription']  ||= FnJoin(' ', [ Ref('MonitoredStack'), "#{template}", "#{name}", FnSub(resourceGroup, env: Ref('EnvironmentName')) ])
    params['ActionsEnabled']    = 'true' if !params.key?('ActionsEnabled')
    params['Period']            ||= 60

    # Replace variables in parameters
    params.each do |k,v|
      replace_vars(params[k],'${name}',resourceGroup)
      replace_vars(params[k],'${metric}',resourceGroup)
      replace_vars(params[k],'${resource}',resourceGroup)
      replace_vars(params[k],'${endpoint}',resourceGroup)
      replace_vars(params[k],'${templateName}',template)
      replace_vars(params[k],'${alarmName}',name)
      replace_vars(params[k],'${cmd}',cmd)
    end

    # Alarm action defaults
    if !params['AlarmActions'].nil?
      alarmActions = actionsEnabledMap[ params['AlarmActions'].downcase.to_sym ]
    else
      alarmActions = actionsEnabledMap['crit']
    end

    if !params['InsufficientDataActions'].nil?
      insufficientDataActions = actionsEnabledMap[ params['InsufficientDataActions'].downcase.to_sym ]
    elsif !params['AlarmActions'].nil? && params['AlarmActions'].downcase.to_sym == :task
      insufficientDataActions = []
    elsif !params['AlarmActions'].nil?
      insufficientDataActions = actionsEnabledMap[ params['AlarmActions'].downcase.to_sym ]
    else
      insufficientDataActions = actionsEnabledMap['crit']
    end

    if !params['OKActions'].nil?
      oKActions = actionsEnabledMap[ params['OKActions'].downcase.to_sym ]
    elsif !params['AlarmActions'].nil? && params['AlarmActions'].downcase.to_sym == :task
      oKActions = []
    elsif !params['AlarmActions'].nil?
      oKActions = actionsEnabledMap[ params['AlarmActions'].downcase.to_sym ]
    else
      oKActions = actionsEnabledMap['crit']
    end

    conditions = []

    # Configure resource parameters
    if type == 'resource'
      # Configure physical resource inputs
      dimensionsNames = params['DimensionsName'].split('/')
      dimensions = []
      resources.each_with_index do |resource,index|
        resourceHash =  Digest::MD5.hexdigest resource
        # Create parameters for incoming physical resource IDs
        Parameter("GetPhysicalId#{resourceHash}") do
          Type 'String'
        end
        # Transform physical resource IDs into dimension values if required
        dimensionValue = Ref("GetPhysicalId#{resourceHash}")
        dimensionValue = FnSelect('5',FnSplit(':',Ref("GetPhysicalId#{resourceHash}"))) if dimensionsNames[index] == 'TargetGroup'
        dimensionValue = FnSelect('1',FnSplit('loadbalancer/',Ref("GetPhysicalId#{resourceHash}"))) if dimensionsNames[index] == 'LoadBalancer'
        dimensionValue = FnSelect('1',FnSplit('service/',Ref("GetPhysicalId#{resourceHash}"))) if dimensionsNames[index] == 'ServiceName'
        dimensionValue = FnJoin('', [Ref("GetPhysicalId#{resourceHash}"),'-001']) if dimensionsNames[index] == 'CacheClusterId'
        # Prepare conditions based on physical resource ID values
        conditions << FnNot(FnEquals(Ref("GetPhysicalId#{resourceHash}"),'null'))
        dimensions << { Name: dimensionsNames[index], Value: dimensionValue }
      end
      params['Dimensions'] = dimensions
    end

    # Add environment conditions if needed
    if alarm[:environments] != ['all']
      envConditions = []
      alarm[:environments].each do | env |
        envConditions << FnEquals(Ref("EnvironmentName"),env)
      end
      if envConditions.length > 1
        conditions << FnOr(envConditions)
      elsif envConditions.length == 1
        conditions << envConditions[0]
      end
    end

    # Create conditions
    if conditions.length > 1
      Condition("Condition#{alarmHash}", FnAnd(conditions))
    elsif conditions.length == 1
      Condition("Condition#{alarmHash}", conditions[0])
    end

    # Create parameter mappings
    create_param_mappings(params,template_envs,alarmHash)

    # Create alarms
    Resource("Alarm#{alarmHash}") do
      Condition "Condition#{alarmHash}" if conditions.length > 0
      Type('AWS::CloudWatch::Alarm')
      Property('ActionsEnabled', FnIf('MonitoringDisabled', false, FnFindInMap("#{alarmHash}",'ActionsEnabled',Ref('EnvironmentType'))))
      Property('AlarmActions', alarmActions)
      Property('AlarmDescription', params['AlarmDescription'])
      Property('ComparisonOperator', FnFindInMap("#{alarmHash}",'ComparisonOperator',Ref('EnvironmentType')))
      Property('Dimensions', params['Dimensions'])
      Property('EvaluateLowSampleCountPercentile', params['EvaluateLowSampleCountPercentile']) unless params['EvaluateLowSampleCountPercentile'].nil?
      Property('EvaluationPeriods', FnFindInMap("#{alarmHash}",'EvaluationPeriods',Ref('EnvironmentType')))
      Property('ExtendedStatistic', params['ExtendedStatistic']) unless params['ExtendedStatistic'].nil?
      Property('InsufficientDataActions', insufficientDataActions)
      Property('MetricName', FnFindInMap("#{alarmHash}",'MetricName',Ref('EnvironmentType')))
      Property('Namespace', FnFindInMap("#{alarmHash}",'Namespace',Ref('EnvironmentType')))
      Property('OKActions', oKActions)
      Property('Period', FnFindInMap("#{alarmHash}",'Period',Ref('EnvironmentType')))
      Property('Statistic', FnFindInMap("#{alarmHash}",'Statistic',Ref('EnvironmentType')))
      Property('Threshold', FnFindInMap("#{alarmHash}",'Threshold',Ref('EnvironmentType')))
      Property('TreatMissingData',FnFindInMap("#{alarmHash}",'TreatMissingData',Ref('EnvironmentType')))
      Property('Unit', params['Unit']) unless params['Unit'].nil?
    end

end

end

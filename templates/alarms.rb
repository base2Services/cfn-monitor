require 'cfndsl'

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

  Condition('MonitoringDisabled', FnEquals(Ref("MonitoringDisabled"),'true'))

  actionsEnabledMap = {
    crit: Ref('SnsTopicCrit'),
    warn: Ref('SnsTopicWarn'),
    task: Ref('SnsTopicTask')
  }

  mappings = {}

  alarms.each do |alarm|
    resourceGroup = alarm.keys[0]
    resources = resourceGroup.split('/')
    template = alarm.values[0][0].tr('::', '')
    name = alarm.values[0][1]
    params = alarm.values[0][2]
    alarmHash = Digest::MD5.hexdigest "#{resourceGroup}#{template}#{name}"
    dimensionsNames = params['DimensionsName'].split('/')

    # Set defaults for optional properties
    params['TreatMissingData'] ||= 'missing'

    # Create mappings
    mappings["#{alarmHash}"] = {}
    params.each do |key,value|
      if !key.include? '.'
        mappings["#{alarmHash}"][key] = {}
        template_envs.each do |env|
          if !params["#{key}.#{env}"].nil?
            mappings["#{alarmHash}"][key][env] = params["#{key}.#{env}"]
          else
            mappings["#{alarmHash}"][key][env] = value
          end
        end
      end
    end
    Mapping("#{alarmHash}", mappings["#{alarmHash}"])

    # Set default property values
    if !params['ActionsEnabled'].nil?
      actionsEnabled = params['ActionsEnabled']
    else
      actionsEnabled = true
    end

    if !params['AlarmActions'].nil?
      alarmActions = [ actionsEnabledMap[ params['AlarmActions'].downcase.to_sym ] ]
    else
      alarmActions = [ Ref('SnsTopicCrit') ]
    end

    if !params['InsufficientDataActions'].nil?
      insufficientDataActions = [ actionsEnabledMap[ params['InsufficientDataActions'].downcase.to_sym ] ]
    elsif !params['AlarmActions'].nil? && params['AlarmActions'].downcase.to_sym == :task
      insufficientDataActions = []
    elsif !params['AlarmActions'].nil?
      insufficientDataActions = [ actionsEnabledMap[ params['AlarmActions'].downcase.to_sym ] ]
    else
      insufficientDataActions = [ Ref('SnsTopicCrit') ]
    end

    if !params['OKActions'].nil?
      oKActions = [ actionsEnabledMap[ params['OKActions'].downcase.to_sym ] ]
    elsif !params['AlarmActions'].nil? && params['AlarmActions'].downcase.to_sym == :task
      oKActions = []
    elsif !params['AlarmActions'].nil?
      oKActions = [ actionsEnabledMap[ params['AlarmActions'].downcase.to_sym ] ]
    else
      oKActions = [ Ref('SnsTopicCrit') ]
    end

    # Configure physical resource inputs
    conditions = []
    dimensions = []
    resources.each_with_index do |resource,index|
      resourceHash =  Digest::MD5.hexdigest resource

      # Create parameters for incoming physical resource IDs
      Parameter("GetPhysicalId#{resourceHash}") do
        Type 'String'
      end

      # Transform physical resource IDs into dimension values if required
      dimensionValue = Ref("GetPhysicalId#{resourceHash}")

      if dimensionsNames[index] == 'TargetGroup'
        dimensionValue = FnSelect('5',FnSplit(':',Ref("GetPhysicalId#{resourceHash}")))
      end

      if dimensionsNames[index] == 'LoadBalancer'
        dimensionValue = FnSelect('1',FnSplit('loadbalancer/',Ref("GetPhysicalId#{resourceHash}")))
      end

      # Prepare conditions based on physical resource ID values
      conditions << FnNot(FnEquals(Ref("GetPhysicalId#{resourceHash}"),'null'))
      dimensions << { Name: dimensionsNames[index], Value: dimensionValue }
    end

    # Create conditions
    if conditions.length > 1
      Condition("Condition#{alarmHash}", FnAnd(conditions))
    else
      Condition("Condition#{alarmHash}", conditions[0])
    end

    # Create alarms
    Resource("Alarm#{alarmHash}") do
      Condition "Condition#{alarmHash}"
      Type('AWS::CloudWatch::Alarm')
      Property('ActionsEnabled', FnIf('MonitoringDisabled', false, actionsEnabled))
      Property('AlarmActions', alarmActions)
      Property('AlarmDescription', FnJoin( '', [ Ref('MonitoredStack'), " #{template} #{name} Alarm" ] ))
      Property('ComparisonOperator', params['ComparisonOperator'])
      Property('Dimensions', dimensions)
      Property('EvaluateLowSampleCountPercentile', params['EvaluateLowSampleCountPercentile']) unless params['EvaluateLowSampleCountPercentile'].nil?
      Property('EvaluationPeriods', FnFindInMap("#{alarmHash}",'EvaluationPeriods',Ref('EnvironmentType')))
      Property('ExtendedStatistic', params['ExtendedStatistic']) unless params['ExtendedStatistic'].nil?
      Property('InsufficientDataActions', insufficientDataActions)
      Property('MetricName', params['MetricName'])
      Property('Namespace', params['Namespace'])
      Property('OKActions', oKActions)
      Property('Period', params['Period'] || 60)
      Property('Statistic', params['Statistic'])
      Property('Threshold', FnFindInMap("#{alarmHash}",'Threshold',Ref('EnvironmentType')))
      Property('TreatMissingData',FnFindInMap("#{alarmHash}",'TreatMissingData',Ref('EnvironmentType')))
      Property('Unit', params['Unit']) unless params['Unit'].nil?
    end

  end

end

require 'cfndsl'

CloudFormation do
  Description("CloudWatch Resources #{template_number}")

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
  Parameter("SnsTopicSlack"){
    Type 'String'
  }
  Parameter("MonitoringDisabled"){
    Type 'String'
  }
  Parameter("EnvironmentType"){
    Type 'String'
  }
  Parameter("GetPhysicalIdFunctionArn"){
    Type 'String'
  }
  Parameter("EnvironmentName"){
    Type 'String'
  }
  Parameter("ConfigToggle"){
    Type 'String'
  }

  Condition('MonitoringDisabled', FnEquals(Ref("MonitoringDisabled"),'true'))

  # Create CloudFormation Custom Resources
  customResources = []
  alarms.each do |alarm|
    type = alarm[:type]
    if type == 'resource'
      # Split resources for multi-dimension alarms
      resources = alarm[:resource].split('/')
      resources.each_with_index do |resource,index|
        resourceHash =  Digest::MD5.hexdigest resource
        Resource("GetPhysicalId#{resourceHash}") do
          Type 'Custom::GetResourcePhysicalId'
          Property('ServiceToken', Ref('GetPhysicalIdFunctionArn'))
          Property('StackName', Ref('MonitoredStack'))
          if resource.include? "::"
            Property('LogicalResourceId', resource.gsub('::','.') )
          else
            Property('LogicalResourceId', FnJoin( '.', [ Ref('MonitoredStack'), resource ] ))
          end
          Property('Region', Ref('AWS::Region'))
          Property('ConfigToggle', Ref('ConfigToggle'))
        end
        customResources << "GetPhysicalId#{resourceHash}"
        # Create outputs for user reference
        Output("#{resource.delete('.').delete('-').delete('::')}") { Value(FnGetAtt("GetPhysicalId#{resourceHash}",'PhysicalResourceId')) }
      end
    end
  end

  params = {
    MonitoredStack: Ref('MonitoredStack'),
    SnsTopicCrit: Ref('SnsTopicCrit'),
    SnsTopicWarn: Ref('SnsTopicWarn'),
    SnsTopicTask: Ref('SnsTopicTask'),
    SnsTopicSlack: Ref('SnsTopicSlack'),
    MonitoringDisabled: Ref('MonitoringDisabled'),
    EnvironmentType: Ref('EnvironmentType'),
    EnvironmentName: Ref('EnvironmentName')
  }

  # Add custom resources to nested stack params
  customResources.each do |cr|
    params.merge!( cr => FnGetAtt(cr, 'PhysicalResourceId' ))
  end

  Resource("AlarmsStack#{template_number}") do
    Type 'AWS::CloudFormation::Stack'
    Property('TemplateURL', "https://#{source_bucket}.s3.amazonaws.com/#{upload_path}/alarms#{template_number}.json")
    Property('TimeoutInMinutes', 5)
    Property('Parameters', params)
  end

end

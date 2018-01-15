# cloudwatch-monitoring
CloudWatch Monitoring

## Configuration
Create a symlink named "ciinaboxes" with a target of your base2-ciinabox repo (similar to ciinabox-jenkins)

Example (with cloudwatch-monitoring and base2-ciinabox in the same directory):
```bash
cd cloudwatch-monitoring
ln -s ../base2-ciinabox ciinaboxes
```

## Usage
```bash
rake cfn:generate [ciinabox-name]
```

## Alarm configuration
All configuration takes place in the base2-ciinabox repo under the customer's ciinabox directory.
Create a directory name "monitoring" (similar to the "jenkins" directory for ciinabox-jenkins), this directory will contain the "alarms.yml" file and optional "templates.yml" file.

### alarms.yml
This file is used to configure the AWS resources you want to monitor with CloudWatch. Resources are referenced by the CloudFormation logical resource ID used to create them. Nested stacks are also referenced by their CloudFormation logical resource ID.

```YAML
source_bucket: [Name of S3 bucket where CloudFormation templates will be deployed]

resources:
  [nested stack name].[resource name]: [template name]
```

Example:

```YAML
source_bucket: source.customer.com

resources:
  RDSStack.RDS: RDSInstance
```

#### Target group configuration:
Target group alarms in CloudWatch require dimensions for both the target group and its associated load balancer.
To configure a target group alarm provide the logical ID of the target group (including any stacks it's nested under) followed by "/", followed by the logical ID of the load balancer (also including any stacks it's nested under).

Example:
```YAML
resources:
  LoadBalancerStack.WebDefTargetGroup/LoadBalancerStack.WebLoadBalancer: ApplicationELBTargetGroup
```

#### Templates
The "template" value you specify for a resource refers to either a default template in the `config/templates.yml` file of this repo, or a custom/override template in the `monitoring/templates.yml` file of the customer's ciinabox monitoring directory. This template can contain multiple alarms. The example below shows the default `RDSInstance` template, which has 2 alarms (`FreeStorageSpaceCrit` and `FreeStorageSpaceTask`). Using the `RDSInstance` template in this example will create 2 CloudWatch alarms for the `RDS` resource in the `RDSStack` nested stack.

Example: `alarms.yml`
```YAML
resources:
  RDSStack.RDS: RDSInstance
```
Example: `templates.yml`
```YAML
templates:
  RDSInstance: # AWS::RDS::DBInstance
    FreeStorageSpaceCrit:
      AlarmActions: crit
      Namespace: AWS/RDS
      MetricName: FreeStorageSpace
      ComparisonOperator: LessThanThreshold
      DimensionsName: DBInstanceIdentifier
      Statistic: Minimum
      Threshold: 50000000000
      Threshold.development: 10000000000
      EvaluationPeriods: 1
    FreeStorageSpaceTask:
      AlarmActions: task
      Namespace: AWS/RDS
      MetricName: FreeStorageSpace
      ComparisonOperator: LessThanThreshold
      DimensionsName: DBInstanceIdentifier
      Statistic: Minimum
      Threshold: 100000000000
      Threshold.development: 20000000000
      EvaluationPeriods: 1
```

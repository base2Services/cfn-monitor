# cloudwatch-monitoring
CloudWatch Monitoring

## Configuration
Create a symlink named "ciinaboxes" with a target of your base2-ciinabox repo (similar to ciinabox-jenkins)

## Usage
```bash
rake cfn:generate [ciinabox-name]
```

## Alarm configuration
All configuration takes place in the base2-ciinabox repo under the customers ciinabox directory.
Create a directory name "monitoring" (similar to the "jenkins" directory for ciinabox-jenkins), this directory will contain the "alarms.yml" file and optional "templates.yml" file

### alarms.yml
This file is used to configure the AWS resources you want to monitor with CloudWatch

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

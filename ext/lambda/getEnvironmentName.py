import json
import cfnresponse
import boto3
from botocore.exceptions import ClientError
import time

def getEnvironmentName(client,stackName):
    time.sleep(5)
    max_retries = 10
    sleep_time = 1
    for i in range(max_retries):
        try:
            response = client.describe_stacks(StackName=stackName)
        except ClientError as e:
            print e
            time.sleep(sleep_time)
            sleep_time += sleep_time
            continue
        else:
            break
    else:
        return "Error"
    for r in response['Stacks'][0]['Parameters']:
        if r['ParameterKey'] == 'EnvironmentName':
            return r['ParameterValue']
    return stackName


def handler(event, context):
    stackName = event['ResourceProperties']['StackName']
    region = event['ResourceProperties']['Region']
    client = boto3.client('cloudformation',region_name=region)

    responseData = {}
    responseData['EnvironmentName'] = getEnvironmentName(client,stackName)
    cfnresponse.send(event, context, cfnresponse.SUCCESS, responseData, "CustomResourcePhysicalID")

import boto3
import os
import requests
from boto3.dynamodb.conditions import Key

"""
        Gets LOB ACCOUNT from the table for a specific LOB.
        params: 
        - User_id: User which just signed up.
       
        returns: 
         - The data about the requested presigned domain url.
"""
def lambda_handler(event, context):
    userid = event["pathParameters"]["user_id"]
    
    dynamodb = boto3.resource('dynamodb')
    user_table = dynamodb.Table(os.environ['USER_LOB_TABLE_NAME'])
    accounts_table = dynamodb.Table(os.environ['LOB_URLS_TABLE_NAME'])

    ACCESS_ROLE_NAME = os.environ['ACCESS_ROLE_NAME']

    # We get the LOB of the user
    lob = user_table.get_item(
            Key={
                'PK': userid
            }
        )['Item']['LOB']

    # we get the sagemker api to retrieve the account of the lob
    account = accounts_table.get_item(
        Key={
            'PK': lob
        }
    )['Item']['ACCOUNT_ID']

    # account = account_response['Items'][0]['ACCOUNT_ID']

    sts_client = boto3.client("sts")
    role = "arn:aws:iam::{}:role/{}".format(account, ACCESS_ROLE_NAME)

    sagemaker_account = sts_client.assume_role(
        RoleArn=role,
        RoleSessionName='CreatePresignedDomainUrlRole'
    )

    ACCESS_KEY = sagemaker_account['Credentials']['AccessKeyId']
    SECRET_KEY = sagemaker_account['Credentials']['SecretAccessKey']
    SESSION_TOKEN = sagemaker_account['Credentials']['SessionToken']

    sagemaker_client = boto3.client(
        "sagemaker",
        aws_access_key_id=ACCESS_KEY,
        aws_secret_access_key=SECRET_KEY,
        aws_session_token=SESSION_TOKEN,
    )

    domains = sagemaker_client.list_domains()["Domains"]
    for domain in domains:
        if domain["Status"] == 'InService':
            domain_id = domain["DomainId"]

    presigned_domain_url = sagemaker_client.create_presigned_domain_url(
        DomainId = domain_id,
        UserProfileName = userid,
        ExpiresInSeconds = 20
    )["AuthorizedUrl"]

    return {
        'statusCode': 302,
        'headers': {
            'Location': presigned_domain_url
            }
    }
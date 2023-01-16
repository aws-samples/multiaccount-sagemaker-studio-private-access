# MultiAccount Sagemaker Studio Private Access

This repository demonstrates the solution presented in the following [blog](link to be provided after blog publication).

It shows how to create an accessing solution for Sagemaekr Studio Domains in a multi account environment in a private and secure way by using presigned domain urls.

![BlogArchitecture](images/BlogArchitecture.png)

## Requirements
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) to run the commands
- [SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html) installed
- 3 Accounts and permissions in the accounts for deployments:
    - Networking and Access resources -> Shared Services Account
    - Sagemaker Account A
    - Sagemaker Account B

## Deployment steps

Set up your region and account profiles. Fill in the region and your profiles

```
export AWS_DEFAULT_REGION=us-east-1
export SHARED_SERVICES_PROFILE=<your-shared-services-account-profile>
export SAGEMAKER_LOB_A_PROFILE=<your-sagemaker-lob-a-profile>
export SAGEMAKER_LOB_B_PROFILE=<your-sagemaker-lob-b-profile>
export SAGEMAKER_LOB_A_ACCOUNT=$(aws sts get-caller-identity --profile $SAGEMAKER_LOB_A_PROFILE | jq -r .Account)
export SAGEMAKER_LOB_B_ACCOUNT=$(aws sts get-caller-identity --profile $SAGEMAKER_LOB_B_PROFILE | jq -r .Account)
export SHARED_SERVICES_ACCOUNT=$(aws sts get-caller-identity --profile $SHARED_SERVICES_PROFILE | jq -r .Account)

```

### Deploy networking resources

From root of the repository. To deploy the shared service account network resources run the following command:

```
aws cloudformation deploy \
    --template-file shared-services-account/networking-resources/template.yml \
    --stack-name networking \
    --profile $SHARED_SERVICES_PROFILE \
    --parameter-overrides \
        AccountsList="$SAGEMAKER_LOB_A_ACCOUNT,$SAGEMAKER_LOB_B_ACCOUNT"

```

---
**NOTE**

The following outputs are outputed in the deployment and must be saved for later templates:
- Transit gateway Id
- API Gateway VPC Endpoint Id
- Sagemaker API VPC Endpoint Id
- Sagemaker Studio VPC Endpoint Id
- The Private Hosted Zones (PHZ) IDs

You can use the following command to assign the values to the parameters that we will use for later deployments:

```
source setup/get-networking-outputs.sh

```

### Share the transit gateway with the other accounts
Transit gateway is automatically shared with the Sagemaker accounts

If the account are in the same OU and auto accept resource shares is enabled there is no need to accept the resource. Otherwise, acceptance in the receiver accounts will be needed.

More informacion about this approach in [Automating AWS Transit Gateway attachments to a transit gateway in a central account](https://aws.amazon.com/blogs/networking-and-content-delivery/automating-aws-transit-gateway-attachments-to-a-transit-gateway-in-a-central-account/)


## Deploy the Access Resources

From root of the repository move to the access-account folder:

Make sure you are using a profile from your chosen Shared Services Account and run the following commands:

```
sam build \
    --profile $SHARED_SERVICES_PROFILE \
    --template-file shared-services-account/access-proxy-app/template.yml
```

```
sam deploy \
    --profile $SHARED_SERVICES_PROFILE \
    --stack-name access \
    --resolve-s3 \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides TGWId=${TransitGatewayId} \
        APIGatewayVpcEndpoint=${VPCEndpointAPIGateway}
    --template-file shared-services-account/access-proxy-app/template.yml
```

This template deploys: 
- The lambdas and API needed for the solution
    - Presigned URL generator Lambda
    - Custom Authorizer Lambda
- The dynamodb tables to store the information
- The cognito user pool to simulate the corporate idp

---
**NOTE**

The following outputs from the deployment must be saved for later templates:
- The Cognito Pool Id
- The Cognito App Client Id
- The ARN of the role for the Lambda Presigned Url generator function
- Name of the dynamodb tables used for the users and lobs data

You can use the following command to assign the values to the paramters that we will use for later configurations:

```
source setup/get-access-outputs.sh
```

## Deploy Sagemaker Accounts


### Account LOB A

From root of the repository run the following command with a user profile from your chosen Sagemaker A Account:

```
setup/deploy-sagemaker.sh -f sagemaker-account/blog-launch-parameters/parameters-sagemaker-account-lob-a.json -s sagemaker-lob-a -p $SAGEMAKER_LOB_A_PROFILE -t file://sagemaker-account/template.yml -r $AWS_DEFAULT_REGION

```

### Account LOB B

```
setup/deploy-sagemaker.sh -f sagemaker-account/blog-launch-parameters/parameters-sagemaker-account-lob-b.json -s sagemaker-lob-b -p $SAGEMAKER_LOB_B_PROFILE -t file://sagemaker-account/template.yml -r $AWS_DEFAULT_REGION
```

This cloudformation templates create a Sagemaker Domain with a user.

## Once all accounts are deployed

We have to associate the Access VPC with the API Gateway and Sagemaker API PHZ:

```
aws route53 associate-vpc-with-hosted-zone \
    --profile $SHARED_SERVICES_PROFILE \
    --hosted-zone-id $StsHostedZoneId \
    --vpc VPCRegion=$AWS_DEFAULT_REGION,VPCId=$VpcAccessId

aws route53 associate-vpc-with-hosted-zone \
    --profile $SHARED_SERVICES_PROFILE \
    --hosted-zone-id $SagemakerApiHostedZoneId \
    --vpc VPCRegion=$AWS_DEFAULT_REGION,VPCId=$VpcAccessId

```

## Filling the dynamodb tables

With a profile from the shared services account.

### Adding users

```

aws dynamodb put-item \
    --profile $SHARED_SERVICES_PROFILE \
    --table-name $UsersMapDynamoDbTable \
    --item "{\"PK\":{\"S\":\"user-lob-a\"},\"LOB\":{\"S\":\"lob-a\"}}"

aws dynamodb put-item \
    --profile $SHARED_SERVICES_PROFILE \
    --table-name $UsersMapDynamoDbTable \
    --item "{\"PK\":{\"S\":\"user-lob-b\"},\"LOB\":{\"S\":\"lob-b\"}}"

```

### Adding LOBs

With a profile from the shared services account

```
aws dynamodb put-item \
    --profile $SHARED_SERVICES_PROFILE \
    --table-name $LobsMapDynamoDbTable \
    --item "{\"PK\":{\"S\":\"lob-a\"},\"ACCOUNT_ID\":{\"S\":\"${SAGEMAKER_LOB_A_ACCOUNT}\"}}"

aws dynamodb put-item \
    --profile $SHARED_SERVICES_PROFILE \
    --table-name $LobsMapDynamoDbTable \
    --item "{\"PK\":{\"S\":\"lob-b\"},\"ACCOUNT_ID\":{\"S\":\"${SAGEMAKER_LOB_B_ACCOUNT}\"}}"
```

### Adding users to cognito

The following parameters are used from the access-proxy-app:
- cognito-user-pool-id (from the outputs of the access stack)
- cognito-client-id (from the outputs of the access stack)

#### Adding the LOB A user

```
aws cognito-idp admin-create-user \
    --profile $SHARED_SERVICES_PROFILE \
    --user-pool-id $CognitoUserPoolId \
    --username user-lob-a

aws cognito-idp admin-set-user-password \
    --profile $SHARED_SERVICES_PROFILE \
    --user-pool-id $CognitoUserPoolId \
    --username user-lob-a \
    --password Userloba1! \
    --permanent
```

#### Adding the LOB B user

```
aws cognito-idp admin-create-user \
    --profile $SHARED_SERVICES_PROFILE \
    --user-pool-id $CognitoUserPoolId \
    --username user-lob-b \

aws cognito-idp admin-set-user-password \
    --profile $SHARED_SERVICES_PROFILE \
    --user-pool-id $CognitoUserPoolId \
    --username user-lob-b \
    --password Userlobb1! \
    --permanent
```

Make sure that the user names match the user names in the sagemaker domain and the user names in the DynamoDb users table

# Extra:

## On premise deployment

![OnPremiseArchitecture](images/OnPremiseArchitecture.png)

For simplicity we will deploy the on premise simulator in the Central Account

First, create a key-pair in the central account. You can use the instructions in [Create key pairs](https://docs.aws.amazon.com/AWSEC2/latest/UserGuide/create-key-pairs.html)

Then run the following command with a profile from the shared services account, providing the following values:
- YOUR_KEY_PAIR_NAME -> name of the key pair you created before
- YOUR_IP_TO_CONNECT_TO_BASTION -> the ip of your instance 

```
export KEY_PAIR_NAME=<YOUR_KEY_PAIR_NAME>
export IP_TO_CONNECT=<YOUR_IP_TO_CONNECT_TO_BASTION>
```

```
aws cloudformation create-stack \
    --profile $SHARED_SERVICES_PROFILE \
    --template-body file://on-premise/template.yml \
    --stack-name on-premise \
    --parameters \
        ParameterKey=EC2KeyPair,ParameterValue=$KEY_PAIR_NAME \
        ParameterKey=PublicIp,ParameterValue=$IP_TO_CONNECT

```

To simulate the connectivity of the on-premise environment and the cloud we will use VPC Peering between the On-premise VPC and the Central Networking VPC. [Intructions to create VPC Peering](https://docs.aws.amazon.com/vpc/latest/peering/create-vpc-peering-connection.html)

**Don´t forget to accept the peering connection**

Remember to update the route tables of on-prem and central networking private subnet route tables to point the respective CIDRs to the peering connection.

Once both VPCs have been peered we can use the solution for DNS proposed in [Part 1](https://aws.amazon.com/blogs/machine-learning/secure-amazon-sagemaker-studio-presigned-urls-part-1-foundational-infrastructure/) of this series. However, in this case we will take advantage of the previously created PHZs and associate the Sageamker Studio and API Gateway PHZs with our On-premise VPC, as with did for the Access VPC.

Run:

```
source setup/get-on-premise-outputs.sh
```

Then run the following commands to set up the PHZs

```
aws route53 associate-vpc-with-hosted-zone \
    --profile $SHARED_SERVICES_PROFILE \
    --hosted-zone-id $ApiGatewayHostedZoneId \
    --vpc VPCRegion=$AWS_DEFAULT_REGION,VPCId=$OnPremiseVpcId

aws route53 associate-vpc-with-hosted-zone \
    --profile $SHARED_SERVICES_PROFILE \
    --hosted-zone-id $SagemakerStudioHostedZoneId \
    --vpc VPCRegion=$AWS_DEFAULT_REGION,VPCId=$OnPremiseVpcId
```

## Testing the solution

Once deploy and set up we have to use the bastion host to RDP into the instance in the private subnet

The following command can be used to retrieve the command that must be launched:

```
aws cloudformation describe-stacks --query 'Stacks[?StackName==`on-premise`][].Outputs[?OutputKey==`TunnelCommand`].OutputValue' --output text
```

In a terminal and with the previously created ec2 key pair run the command

This will create an RDP connection between our localhost and the private windows instance.

And then use an rdp client like Windows Remote Desktop to connect to the instance.
- Username: Administrator
- Password: Can be retrieved with the KeyPair from the Windows instance

More information about connecting to your windows instance in AWS documentation [Connect To Your Windows Instance](https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/connecting_to_windows_instance.html) official documentation

Once in the instance (if it is not installed) we will install firefox -> [Link to install firefox in the instance](https://gmusumeci.medium.com/unattended-install-of-firefox-browser-using-powershell-6841a7742f9a)

### Testing the PresignedUrl

If we just want to test the presigned url this can easily be done by:

- Go into the [API Gateway console](https://us-east-1.console.aws.amazon.com/apigateway/main/apis?region=us-east-1)
- Under APIs, find and click on the access API
- Under resources go to the access api {user_id+} get method
- Then click on test
- Enter one of `lob-user-a` or `lob-user-b` as the user_id path
- Click on the test button
- Copy the presigned url returned in the response
- Consume it in our simulated on-premise windows app

![ApiGatewayTesting](images/TestingApiGatewayConsole.png)

This presigned url must be consumed through the central Studio VPC Endpoint and will expire in 20 seconds, as defined in the Access Lambda function.

If we try to consume it through our browser a message saying: "Auth token containing insufficient permissions" will be shown.

### Testing End to End

To test the end to end we will need to get tokens for the users, so that we can consume the access API.

To get the access tokens run the following commands substuting the cognito client id which can be retrieved from the access stack:

```
aws cognito-idp initiate-auth \
    --auth-flow USER_PASSWORD_AUTH \
    --client-id $CognitoAppClientId \
    --auth-parameters USERNAME=user-lob-a,PASSWORD=Userloba1!
```
```
aws cognito-idp initiate-auth \
    --auth-flow USER_PASSWORD_AUTH \
    --client-id $CognitoAppClientId \
    --auth-parameters USERNAME=user-lob-b,PASSWORD=Userlobb1!
```

Now to test we need the API´s URL which we retrieved from the access-stack outputs and we can get it by running this command:

```
echo $(aws cloudformation describe-stacks --query 'Stacks[?StackName==`access`][].Outputs[?OutputKey==`ApiBasePath`].OutputValue' --output text)

```

To call for user a the api call will look as follows:

https://{API_ID}.execute-api.{REGION}.amazonaws.com/dev/user-lob-a

Once we have all this information, we can try to call the API Gateway api from within our windows app, however we should get the following error: {message: Unauthorize}

Therefore we will add the tokens to the request header.

1. Got to Firefox inspection tools and network tab
2. Right click on the failed API with File as user-lob-a call and click Edit and Resend
3. Scroll down on the headers side and add a new header

- Header Key: Authorization
- Header Value: Bearer <access-token-of-user-to-make-request>

And click send

![End2EndTesting](images/TestingE2E.png)

In the return response you will get the Location and if you click on it it will open up your Jupyter Lab

Click it fast as you only get 20 seconds to consume it

First time it will take some time, as Sagemaker is creating the application for the user, but next attemps will be faster.

In a real world scenario this action will be perform by an access application which will authomatically understand the 302 redirect and send the user to the Sagemaker App

If we try to edit the request to send all the same information but for the user-lob-b URL we will get the following error in the response:

x-amzn-ErrorType: AccessDeniedException

This same process could be repeated changing eveything of user-lob-a to user-lob-b and the access would be granted for the LOB B domain

## Clean up

1. [Delete the VPC Peering Connection](https://docs.aws.amazon.com/vpc/latest/peering/delete-vpc-peering-connection.html)
2. Remove the associated VPCs from the PHZs. You can use the following command

```
setup/remove-associated-vpcs.sh

```
3. Delete the on-premise stack
```
aws cloudformation delete-stack \
    --profile $SHARED_SERVICES_PROFILE \
    --stack-name on-premise
```
4. Delete the EFS Volumes for the Sagemaker Domains. See [Deleting an Amazon EFS file system](https://docs.aws.amazon.com/efs/latest/ug/delete-efs-fs.html)
5. Delete any opened applications from the Sagemaker Domains as explained in [Delete an Amazon Sagemaker Domain](https://docs.aws.amazon.com/sagemaker/latest/dg/gs-studio-delete-domain.html)
5. Delete the Sagemaker Studio Cloudformation templates from the Sagemaker Accounts.

```
aws cloudformation delete-stack \
    --profile $SAGEMAKER_LOB_A_PROFILE \
    --stack-name sagemaker-lob-a

aws cloudformation delete-stack \
    --profile $SAGEMAKER_LOB_B_PROFILE \
    --stack-name sagemaker-lob-b

```
6. Delete the Access Cloudformation template from the Central Account
```
aws cloudformation delete-stack \
    --profile $SHARED_SERVICES_PROFILE \
    --stack-name access
```
7. Delete the Networking template from the Central Account 

```
aws cloudformation delete-stack \
    --profile $SHARED_SERVICES_PROFILE \
    --stack-name networking
```
## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the LICENSE file.


# MultiAccount Sagemaker Studio Private Access

This repository demonstrates the solution presented in the following [blog](link).

It shows how to create an accessing solution for Sagemaekr Studio Domains in a multi account environment in a private and secure way by using presigned domain urls.

![BlogArchitecture](images/BlogArchitecture.png)

## Requirements
- [AWS CLI](https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html) to run the commands
- [SAM CLI](https://docs.aws.amazon.com/serverless-application-model/latest/developerguide/install-sam-cli.html) installed
- 3 Accounts and admin permissions in the accounts for deployments:
    - Networking and Access resources -> Shared Services Account
    - Sagemaker Account A
    - Sagemaker Account B

## Deployment steps

Set up your region

```
export AWS_DEFAULT_REGION=<your-region>
```

### Deploy networking resources

From root of the repository move to the networking-account folder:
```
cd networking-account
```

Run the following command with a user profile from your chosen Shared Services Account and run:

```
aws cloudformation deploy \
    --template-file template.yml \
    --stack-name networking

```

---
**NOTE**

The following outputs are exported in the deployment and must be saved for later templates:
- Transit gateway Id
- API Gateway VPC Endpoint Id
- Sagemaker API VPC Endpoint Id
- Sagemaker Studio VPC Endpoint Id

### Share the transit gateway with the other accounts
Go to the Shared Services Account where networking stack was deployed and:
- Go to [Resource Access Manager](https://us-west-2.console.aws.amazon.com/ram/home).
- In **Shared by me** go to Resource Shares.
- Click create resource share.
- Chose a name (i.e. tgw-resource-share).
- Add the previously created TGW to the resource share.
- Optional: Add any Resolver Rules for private sagemaker domains to reach the central endpoints from Sagemaker Accounts.
- Select the two Sagemaker Accounts to share the resource with.
- Click Create Resource Share.
- If the account are in the same OU and auto accept resource shares is enabled there is no need to accept the resource. Otherwise, acceptance in the receiver accounts will be needed.

More informacion about this approach in [Automating AWS Transit Gateway attachments to a transit gateway in a central account](https://aws.amazon.com/blogs/networking-and-content-delivery/automating-aws-transit-gateway-attachments-to-a-transit-gateway-in-a-central-account/)


## Deploy the Access Resources

From root of the repository move to the access-account folder:
```
cd access-account
```
Make sure you are using a profile from your chosen Shared Services Account and run:

```
sam build
```
In the following command substitute:
- The Transit Gateway Id from the networking stack
- The Api Gateway VPC Endpoint Id from the networking stack

```
sam deploy \
    --stack-name access \
    --resolve-s3 \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides ParameterKey=TGWId,ParameterValue={YOUR_TGW_ID} \
        ParameterKey=APIGatewayVpcEndpoint,ParameterValue={YOUR_APIGW_VPCEndpoint_Id}
```

This template deploys: 
- The lambdas and API needed for the solution
    - Presigned URL generator Lambda
    - Custom Authorizer Lambda
- The dynamodb tables to store the information
- The cognito user pool to simulate the corporate idp

---
**NOTE**

The following outputs are exported in the deployment and must be saved for later templates:
- The Cognito Pool Id
- The Cognito App Client Id
- The ARN of the role for the Lambda Presigned Url generator function

## Deploy Sagemaker Accounts

Inside the sagemaker-account folder.

Make sure to adapt your parameters to your case in the files:
- blog-launch-parameters/parameters-sagemaker-account-lob-a.json
- blog-launch-parameters/parameters-sagemaker-account-lob-b.json

Fill the required values in both of them:
- Sagemaker Studio VPC Endpoint (from networking stack)
- Sagemaker API VPC Endpoint (from networking stack)
- Transit Gateway Id (from networking stack)
- Lambda Presigned Url Role Arn (from access stack)

### Account LOB A

From root of the repository move to the access-account folder:
```
cd sagemaker-account
```

Run the following command with a user profile from your chosen Sagemaker A Account:

```
aws cloudformation deploy \
    --template-file template.yml \
    --stack-name sagemaker-lob-a \
    --parameter-overrides file://blog-launch-parameters/parameters-sagemaker-account-lob-a.json \
    --capabilities CAPABILITY_NAMED_IAM
```

### Account LOB B
From root of the repository move to the sagemaker-account folder:
```
cd sagemaker-account
```

Run the following command with a user profile from your chosen Sagemaker B Account:

aws cloudformation deploy \
    --template-file template.yml \
    --stack-name sagemaker-lob-b \
    --parameter-overrides file://blog-launch-parameters/parameters-sagemaker-account-lob-b.json \
    --capabilities CAPABILITY_NAMED_IAM

This cloudformation templates create a Sagemaker Domain with a user.

## Once all accounts are deployed

We have to associate the Access VPC with the API Gateway and Sagemaker API PHZ:

Steps:
- Go to [Route 53 Service Console](https://us-east-1.console.aws.amazon.com/route53/v2/hostedzones#)
- Select PHZs
- Click in the STS PHZ and Select edit
- Scroll down to VPCs to Associate and select Add VPC
- Find the access VPC and add it
- Click on Save Changes

Repeat for the Sagemaker API PHZ

## Filling the dynamodb tables

Select a profile from the central account.

From root of the repository move to the access-account folder:
```
cd access-account
```

### Adding users

```
aws dynamodb put-item \
    --table-name sagemaker-users-map-table \
    --item file://dynamo-schemas/user-lob-a.json
```
```
aws dynamodb put-item \
    --table-name sagemaker-users-map-table \
    --item file://dynamo-schemas/user-lob-b.json
```

### Adding LOBs

Make sure to adapt your account to your case in the files:
- dynamo-schemas/lob-a.json
- dynamo-schemas/lob-b.json

```
aws dynamodb put-item \
    --table-name sagemaker-lob-accounts-table \
    --item file://dynamo-schemas/lob-a.json
```
```
aws dynamodb put-item \
    --table-name sagemaker-lob-accounts-table \
    --item file://dynamo-schemas/lob-b.json
```

### Adding users to cognito

The following parameters are needed:
- cognito-user-pool-id (from the outputs of the access stack)
- cognito-client-id (from the outputs of the access stack)

#### Adding the LOB A user

```
aws cognito-idp admin-create-user \
    --user-pool-id <your-cognito-user-pool> \
    --username user-lob-a
```
```
aws cognito-idp admin-set-user-password \
    --user-pool-id <your-cognito-user-pool> \
    --username user-lob-a \
    --password Userloba1! \
    --permanent
```

#### Adding the LOB B user

```
aws cognito-idp admin-create-user \
    --user-pool-id <your-cognito-user-pool> \
    --username user-lob-b \
    --region <your-region>
```
```
aws cognito-idp admin-set-user-password \
    --user-pool-id <your-cognito-user-pool> \
    --username user-lob-b \
    --password Userlobb1! \
    --permanent \
    --region <your-region>
```

Make sure that the user names match the user names in the sagemaker domain and the user names in the DynamoDb users table

# Extra:

## On premise deployment

![OnPremiseArchitecture](images/OnPremiseArchitecture.png)

For simplicity we will deploy the on premise simulator in the Central Account

First, create a key-pair in the central account.

Then run the following command with a profile from the central account and from the on-premise folder

```
aws cloudformation deploy \
    --template-file template.yml \
    --stack-name on-premise \
    --parameter-overrides ParameterKey=EC2KeyPair,ParameterValue={YOUR_KEY_PAIR_NAME} \
         ParameterKey=PublicIp,ParameterValue={YOUR_IP_TO_CONNECT_TO_BASTION}

```

To simulate the connectivity of the on-premise environment and the cloud we will use VPC Peering between the On-premise VPC and the Central Networking VPC.

**Don´t forget to accept the peering connection**

Remember to update the route tables of on-prem and central networking private subnet route tables to point the respective CIDRs to the peering connection. [Intructions to create VPC Peering](https://docs.aws.amazon.com/vpc/latest/peering/create-vpc-peering-connection.html)

Once both VPCs have been peered we can use the solution for DNS proposed in [Part 1](https://aws.amazon.com/blogs/machine-learning/secure-amazon-sagemaker-studio-presigned-urls-part-1-foundational-infrastructure/) of this series. However, in this case we will take advantage of the previously created PHZs and associate the Sageamker Studio and API Gateway PHZs with our On-premise VPC, as with did for the Access VPC.

## Testing the solution

Once deploy and set up we have to use the bastion host to RDP into the instance in the private subnet

In a terminal and with the previously created ec2 key pair run:

```
ssh -i ec2-kp.pem -A -N -L localhost:3389:<windows-private-ip>:3389 ec2-user@<bastion-ip>

```


This will create an RDP connection between our localhost and the private windows instance.

And then use an rdp client like Windows Remote Desktop to connect to the instance.
- Username: Administrator
- Password: Can be retrieved with the KeyPair from the Windows instance

Once in the instance we will install firefox -> [Link to install firefox in the instance](https://www.snel.com/support/install-firefox-in-windows-server/)

### Testing the PresignedUrl

If we just want to test the presigned url this can easily be done by:

- Go into the API Gateway console
- Go to the access API
- Under resources go to the access api {user_id+} get method
- Select test
- Enter one of lob-user-a or lob-user-b as the user_id path
- Click test
- Copy the presigned url returned in the response
- Consume it in our simulated on-premise windows app to consume it

This presigned url must be consumed through the central Studio VPC Endpoint and will expire in 20 seconds, as defined in the Access Lambda function.

If we try to consume it through our browser a message saying: "Auth token containing insufficient permissions" will be shown.

### Testing End to End

To test the end to end we will need to get tokens for the users, so that we can consume the access API.

To get the access tokens run the following commands substuting the cognito client id which can be retrieved from the access stack:

```
aws cognito-idp initiate-auth \
    --auth-flow USER_PASSWORD_AUTH \
    --client-id <your-cognito-client-id> \
    --auth-parameters USERNAME=user-lob-a,PASSWORD=Userloba1!
```
```
aws cognito-idp initiate-auth \
    --auth-flow USER_PASSWORD_AUTH \
    --client-id <your-cognito-client-id> \
    --auth-parameters USERNAME=user-lob-b,PASSWORD=Userlobb1!
```

Now to test we need the API´s URL which we retrieved from the access-stack outputs and would look like this:

https://{api-id}.execute-api.{region}.amazonaws.com/dev/


To call for user a the api call will look as follows:

https://{API_ID}.execute-api.{REGION}.amazonaws.com/dev/user-lob-a

Once we have all this information, we can try to call the API Gateway api from within our windows app, however we should get the following error: {message: Unauthorize}

Therefore we will add the tokens to the request header.

1. Got to Firefox inspection tools and network tab
2. Right click on the failed API with File as user-lob-a call and click Edit and Resend
3. Scroll down on the headers side and add a new header

Header Key: Authorization
Header Value: Bearer <token-of-user-to-make-request>

And click send

In the return response you will get the Location and if you click on it it will open up your Jupyter Lab

Click it fast as you only get 20 seconds to consume it and don´t miss it like I did :)

In a real world scenario this action will be perform by an access application which will authomatically understand the 302 redirect and send the user to the Sagemaker App

If we try to edit the request to send all the same information but for the user-lob-b URL we will get the following error in the response:

x-amzn-ErrorType: AccessDeniedException

This same process could be repeated changing eveything of user-lob-a to user-lob-b and the access would be granted for the LOB B domain

## Clean up

1. Delete the VPC Peering Connection
2. Remove the associated VPCs from the PHZs
3. Delete the Sagemaker Studio Cloudformation templates from the Sagemaker Accounts
4. Delete the Access Cloudformation template from the Central Account
5. Delete the Networking template from the Central Account 

## Security

See [CONTRIBUTING](CONTRIBUTING.md#security-issue-notifications) for more information.

## License

This library is licensed under the MIT-0 License. See the LICENSE file.


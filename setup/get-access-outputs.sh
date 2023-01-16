#!/bin/bash

export VpcAccessId=$(aws cloudformation describe-stacks --query 'Stacks[?StackName==`access`][].Outputs[?OutputKey==`VPCAccess`].OutputValue' --output text)
echo "Saved as VpcAccessId: ${VpcAccessId}"
export CognitoUserPoolId=$(aws cloudformation describe-stacks --query 'Stacks[?StackName==`access`][].Outputs[?OutputKey==`CognitoUserPoolId`].OutputValue' --output text)
echo "Saved as CognitoUserPoolId: ${CognitoUserPoolId}"
export CognitoAppClientId=$(aws cloudformation describe-stacks --query 'Stacks[?StackName==`access`][].Outputs[?OutputKey==`CognitoAppClientId`].OutputValue' --output text)
echo "Saved as CognitoAppClientId: ${CognitoAppClientId}"
export LambdaPresignedFunctionArn=$(aws cloudformation describe-stacks --query 'Stacks[?StackName==`access`][].Outputs[?OutputKey==`LambdaPresignedFunctionArn`].OutputValue' --output text)
echo "Saved as LambdaPresignedFunctionArn: ${LambdaPresignedFunctionArn}"
export UsersMapDynamoDbTable=$(aws cloudformation describe-stacks --query 'Stacks[?StackName==`access`][].Outputs[?OutputKey==`UsersMapDynamoDbTable`].OutputValue' --output text)
echo "Saved as UsersMapDynamoDbTable: ${UsersMapDynamoDbTable}"
export LobsMapDynamoDbTable=$(aws cloudformation describe-stacks --query 'Stacks[?StackName==`access`][].Outputs[?OutputKey==`LobsMapDynamoDbTable`].OutputValue' --output text)
echo "Saved as LobsMapDynamoDbTable: ${LobsMapDynamoDbTable}"
#!/bin/bash

export VpcCentralId=$(aws cloudformation describe-stacks --query 'Stacks[?StackName==`networking`][].Outputs[?OutputKey==`VPCCentral`].OutputValue' --output text)
echo "Saved as VpcCentralId: ${VpcCentralId}"
export TransitGatewayId=$(aws cloudformation describe-stacks --query 'Stacks[?StackName==`networking`][].Outputs[?OutputKey==`TransitGatewayId`].OutputValue' --output text)
echo "Saved as TransitGatewayId: ${TransitGatewayId}"
export VPCEndpointAPIGateway=$(aws cloudformation describe-stacks --query 'Stacks[?StackName==`networking`][].Outputs[?OutputKey==`VPCEndpointAPIGateway`].OutputValue' --output text)
echo "Saved as VPCEndpointAPIGateway: ${VPCEndpointAPIGateway}"
export VPCEndpointSagemakerApi=$(aws cloudformation describe-stacks --query 'Stacks[?StackName==`networking`][].Outputs[?OutputKey==`VPCEndpointSagemakerApi`].OutputValue' --output text)
echo "Saved as VPCEndpointSagemakerApi: ${VPCEndpointSagemakerApi}"
export VPCEndpointSagemakerStudio=$(aws cloudformation describe-stacks --query 'Stacks[?StackName==`networking`][].Outputs[?OutputKey==`VPCEndpointSagemakerStudio`].OutputValue' --output text)
echo "Saved as VPCEndpointSagemakerStudio: ${VPCEndpointSagemakerStudio}"
export SagemakerApiHostedZoneId=$(aws cloudformation describe-stacks --query 'Stacks[?StackName==`networking`][].Outputs[?OutputKey==`SagemakerApiHostedZoneId`].OutputValue' --output text)
echo "Saved as SagemakerApiHostedZoneId: ${SagemakerApiHostedZoneId}"
export SagemakerStudioHostedZoneId=$(aws cloudformation describe-stacks --query 'Stacks[?StackName==`networking`][].Outputs[?OutputKey==`SagemakerStudioHostedZoneId`].OutputValue' --output text)
echo "Saved as SagemakerStudioHostedZoneId: ${SagemakerStudioHostedZoneId}"
export ApiGatewayHostedZoneId=$(aws cloudformation describe-stacks --query 'Stacks[?StackName==`networking`][].Outputs[?OutputKey==`ApiGatewayHostedZoneId`].OutputValue' --output text)
echo "Saved as ApiGatewayHostedZoneId: ${ApiGatewayHostedZoneId}"
export StsHostedZoneId=$(aws cloudformation describe-stacks --query 'Stacks[?StackName==`networking`][].Outputs[?OutputKey==`StsHostedZoneId`].OutputValue' --output text)
echo "Saved as StsHostedZoneId: ${StsHostedZoneId}"
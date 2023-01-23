#!/bin/bash

echo "Fetching parameters..."

DIRNAME=$(pwd)

# Params files
GENERAL_PARAMS_FILE="${DIRNAME}/scripts/setup/parameters/general-parameters.json"

# AWS Profiles 
SHARED_SERVICES_PROFILE=$(jq -r '.[] | select(.ParameterKey == "pSharedServicesProfile") | .ParameterValue' ${GENERAL_PARAMS_FILE})

REGION=$(jq -r '.[] | select(.ParameterKey == "region") | .ParameterValue' ${GENERAL_PARAMS_FILE})

# Templates file names
NETWORK_INFRA_STACK_NAME=$(jq -r '.[] | select(.ParameterKey == "pNetworkingStackName") | .ParameterValue' ${GENERAL_PARAMS_FILE})
ACCESS_INFRA_STACK_NAME=$(jq -r '.[] | select(.ParameterKey == "pAccessAppStackName") | .ParameterValue' ${GENERAL_PARAMS_FILE})
ON_PREMISE_STACK_NAME=$(jq -r '.[] | select(.ParameterKey == "pOnPremiseStackName") | .ParameterValue' ${GENERAL_PARAMS_FILE})

########### REMOVE PHZ ASSOCIATED VPCs ############

VPC_ACCESS_ID=$(aws --profile ${SHARED_SERVICES_PROFILE} --region ${REGION} cloudformation describe-stacks --query "Stacks[?StackName=='${ACCESS_INFRA_STACK_NAME}'][].Outputs[?OutputKey=='VPCAccess'].OutputValue" --output text)
STS_HOSTED_ZONE_ID=$(aws --profile ${SHARED_SERVICES_PROFILE} --region ${REGION} cloudformation describe-stacks --query "Stacks[?StackName=='${NETWORK_INFRA_STACK_NAME}'][].Outputs[?OutputKey=='StsHostedZoneId'].OutputValue" --output text)
SAGEMAKER_API_HOSTED_ZONE_ID=$(aws --profile ${SHARED_SERVICES_PROFILE} --region ${REGION} cloudformation describe-stacks --query "Stacks[?StackName=='${NETWORK_INFRA_STACK_NAME}'][].Outputs[?OutputKey=='SagemakerApiHostedZoneId'].OutputValue" --output text)

VPC_ON_PREMISE_ID=$(aws --profile ${SHARED_SERVICES_PROFILE} --region ${REGION} cloudformation describe-stacks --query "Stacks[?StackName=='${ON_PREMISE_STACK_NAME}'][].Outputs[?OutputKey=='OnPremiseVpcId'].OutputValue" --output text)
API_GW_HOSTED_ZONE_ID=$(aws --profile ${SHARED_SERVICES_PROFILE} --region ${REGION} cloudformation describe-stacks --query "Stacks[?StackName=='${NETWORK_INFRA_STACK_NAME}'][].Outputs[?OutputKey=='ApiGatewayHostedZoneId'].OutputValue" --output text)
SAGEMAKER_STUDIO_HOSTED_ZONE_ID=$(aws --profile ${SHARED_SERVICES_PROFILE} --region ${REGION} cloudformation describe-stacks --query "Stacks[?StackName=='${NETWORK_INFRA_STACK_NAME}'][].Outputs[?OutputKey=='SagemakerStudioHostedZoneId'].OutputValue" --output text)

echo $VPC_ACCESS_ID
echo $STS_HOSTED_ZONE_ID
aws route53 disassociate-vpc-from-hosted-zone \
    --profile $SHARED_SERVICES_PROFILE \
    --hosted-zone-id $STS_HOSTED_ZONE_ID \
    --vpc VPCRegion=$REGION,VPCId=$VPC_ACCESS_ID

aws route53 disassociate-vpc-from-hosted-zone \
    --profile $SHARED_SERVICES_PROFILE \
    --hosted-zone-id $SAGEMAKER_API_HOSTED_ZONE_ID \
    --vpc VPCRegion=$REGION,VPCId=$VPC_ACCESS_ID

aws route53 disassociate-vpc-from-hosted-zone \
    --profile $SHARED_SERVICES_PROFILE \
    --hosted-zone-id $API_GW_HOSTED_ZONE_ID \
    --vpc VPCRegion=$REGION,VPCId=$VPC_ON_PREMISE_ID

aws route53 disassociate-vpc-from-hosted-zone \
    --profile $SHARED_SERVICES_PROFILE \
    --hosted-zone-id $SAGEMAKER_STUDIO_HOSTED_ZONE_ID \
    --vpc VPCRegion=$REGION,VPCId=$VPC_ON_PREMISE_ID
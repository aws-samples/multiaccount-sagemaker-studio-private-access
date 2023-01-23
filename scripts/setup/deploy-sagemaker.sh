#!/bin/bash

DIRNAME=$(pwd)
echo "Deploying stack..."
#Setting the refresh time for SAM deploy
function usage {
    echo "Usage: ./deploy.sh"
    echo "-f params-file                  (mandatory)" 
    echo "-s stack-name                   (mandatory)"
    echo "-p profile                      (mandatory)"
    echo "-t template-file                (mandatory)"
    echo "-r region                       (mandatory)"
}

while getopts f:s:p:t:r: flag
do
    case "${flag}" in
        f) PARAMS_FILE=${OPTARG};;
        s) STACK_NAME=${OPTARG};;
        p) PROFILE=${OPTARG};;
        t) TEMPLATE_FILE=${OPTARG};;
        r) REGION=${OPTARG};;
        #\? ) usage;;

    esac
done

GENERAL_PARAMS_FILE="${DIRNAME}/scripts/setup/parameters/general-parameters.json"
# Creates a CloudFormation stack only if is not already been deployed
# Arguments:
#   - $1: Stack name
#   - $2: Template file
#   - $3: AWS Credentials profile
#   - $4: AWS Region
#   - $5: "parameters" parameter contents (optional)
function create_stack_if_not_exist {
  if [ $# -lt 4 ]; then
    echo "Not enough arguments supplied calling create_stack_if_not_exist"
    exit 1
  fi

  echo "Creating $1 stack in $3 account ($4)"
  export STACK_NAME=$1
  CHECK_STACK=$(aws --profile ${3} --region ${4} cloudformation list-stacks | jq -r '.StackSummaries[] | select(.StackStatus != "DELETE_COMPLETE") | select(.StackName == env.STACK_NAME) | .StackName')
  if [ "$STACK_NAME" = "$CHECK_STACK" ]; then
    STACK_STATUS=$(aws --profile ${3} --region ${4} cloudformation list-stacks | jq -r '.StackSummaries[] | select(.StackStatus != "DELETE_COMPLETE") | select(.StackName == env.STACK_NAME) | .StackStatus')
    if [ "$STACK_STATUS" != "CREATE_COMPLETE" ]; then
      echo "The stack is not created successfully"
    else
      echo "The stack is already created. Skipping!"
    fi
  else
    if [ -z "$5" ]; then
      PARAMETERS=""
    else
      PARAMETERS="--parameters ${5}"
    fi
    aws cloudformation create-stack \
        --stack-name ${STACK_NAME} \
        --template-body $2 \
        --capabilities "CAPABILITY_NAMED_IAM" "CAPABILITY_AUTO_EXPAND" \
        --region ${4} \
        --profile ${3} \
        ${PARAMETERS}
    if [ $? -eq 0 ]; then
      echo "Waiting for stack to be created ..."
      aws cloudformation wait stack-create-complete --profile ${3} --region ${4} --stack-name ${STACK_NAME}
      if [ $? -eq 0 ]; then
        echo "${STACK_NAME} stack created successfully"
      else
        echo "The stack was created but it failed at some point"
      fi
    else
      echo "Failed to create the stack"
    fi
  fi
}

# Shared services profile to get outputs from stacks
SHARED_SERVICES_PROFILE=$(jq -r '.[] | select(.ParameterKey == "pSharedServicesProfile") | .ParameterValue' ${GENERAL_PARAMS_FILE})

# Templates file names
NETWORK_INFRA_STACK_NAME=$(jq -r '.[] | select(.ParameterKey == "pNetworkingStackName") | .ParameterValue' ${GENERAL_PARAMS_FILE})
ACCESS_INFRA_STACK_NAME=$(jq -r '.[] | select(.ParameterKey == "pAccessAppStackName") | .ParameterValue' ${GENERAL_PARAMS_FILE})

# Getting the template parameters
VPC_CIDR=$(jq -r '.[] | select(.ParameterKey == "VpcCidr") | .ParameterValue' ${DIRNAME}/${PARAMS_FILE})
PRIVATE_SUBNET_A_CIDR=$(jq -r '.[] | select(.ParameterKey == "PrivateSubnetACidr") | .ParameterValue' ${DIRNAME}/${PARAMS_FILE})
PRIVATE_SUBNET_B_CIDR=$(jq -r '.[] | select(.ParameterKey == "PrivateSubnetBCidr") | .ParameterValue' ${DIRNAME}/${PARAMS_FILE})
ATTACH_SUBNET_A_CIDR=$(jq -r '.[] | select(.ParameterKey == "AttachSubnetACidr") | .ParameterValue' ${DIRNAME}/${PARAMS_FILE})
ATTACH_SUBNET_B_CIDR=$(jq -r '.[] | select(.ParameterKey == "AttachSubnetBCidr") | .ParameterValue' ${DIRNAME}/${PARAMS_FILE})
SAGEMAKER_DOMAIN_NAME=$(jq -r '.[] | select(.ParameterKey == "SagemakerDomainName") | .ParameterValue' ${DIRNAME}/${PARAMS_FILE})
USER_ID=$(jq -r '.[] | select(.ParameterKey == "UserId") | .ParameterValue' ${DIRNAME}/${PARAMS_FILE})

# Getting the shared services stacks parameters
VPC_ENDPOINT_SAGEMAKER_STUDIO=$(aws cloudformation describe-stacks --profile ${SHARED_SERVICES_PROFILE} --region ${REGION} --query "Stacks[?StackName=='${NETWORK_INFRA_STACK_NAME}'][].Outputs[?OutputKey=='VPCEndpointSagemakerStudio'].OutputValue" --output text)
VPC_ENDPOINT_SAGEMAKER_API=$(aws cloudformation describe-stacks --profile ${SHARED_SERVICES_PROFILE} --region ${REGION} --query "Stacks[?StackName=='${NETWORK_INFRA_STACK_NAME}'][].Outputs[?OutputKey=='VPCEndpointSagemakerApi'].OutputValue" --output text)
TRANSIT_GATEWAY_ID=$(aws cloudformation describe-stacks --profile ${SHARED_SERVICES_PROFILE} --region ${REGION} --query "Stacks[?StackName=='${NETWORK_INFRA_STACK_NAME}'][].Outputs[?OutputKey=='TransitGatewayId'].OutputValue" --output text)
LAMBDA_PRESIGNED_FUNCTION_ARN=$(aws cloudformation describe-stacks --profile ${SHARED_SERVICES_PROFILE} --region ${REGION} --query "Stacks[?StackName=='${ACCESS_INFRA_STACK_NAME}'][].Outputs[?OutputKey=='LambdaPresignedFunctionArn'].OutputValue" --output text)

TEMPLATE_PARAMETERS="ParameterKey=VpcCidr,ParameterValue=${VPC_CIDR} \
        ParameterKey=PrivateSubnetACidr,ParameterValue=${PRIVATE_SUBNET_A_CIDR} \
        ParameterKey=PrivateSubnetBCidr,ParameterValue=${PRIVATE_SUBNET_B_CIDR} \
        ParameterKey=AttachSubnetACidr,ParameterValue=${ATTACH_SUBNET_A_CIDR} \
        ParameterKey=AttachSubnetBCidr,ParameterValue=${ATTACH_SUBNET_B_CIDR} \
        ParameterKey=SagemakerDomainName,ParameterValue=${SAGEMAKER_DOMAIN_NAME} \
        ParameterKey=UserId,ParameterValue=${USER_ID} \
        ParameterKey=SagemakerStudioVpce,ParameterValue=${VPC_ENDPOINT_SAGEMAKER_STUDIO} \
        ParameterKey=SagemakerApiVpce,ParameterValue=${VPC_ENDPOINT_SAGEMAKER_API} \
        ParameterKey=LambdaPresignedUrlRoleArn,ParameterValue=${LAMBDA_PRESIGNED_FUNCTION_ARN} \
        ParameterKey=TGWId,ParameterValue=${TRANSIT_GATEWAY_ID}"

create_stack_if_not_exist ${STACK_NAME} ${TEMPLATE_FILE} ${PROFILE} ${REGION} "${TEMPLATE_PARAMETERS}"

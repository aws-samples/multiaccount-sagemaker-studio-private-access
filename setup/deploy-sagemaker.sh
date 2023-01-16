#!/bin/bash

DIRNAME=$(pwd)
PARAMS_FILE="sagemaker-account/blog-launch-parameters/parameters-sagemaker-account-lob-b.json"

#Setting the refresh time for SAM deploy
SAM_CLI_POLL_DELAY=5
function usage {
    echo "Usage: ./deploy.sh"
    echo "-b artefact_bucket              (mandatory)" 
    echo "[-r aws_region]                 (default is eu-west-1)"
    echo "[-p aws_cli_profile]            (default is default profile)"
    echo "[-s stack_name]                 (default is CF-my-stack)"
    echo "[-c create_bucket y/n]          (default is n)"
    echo "[-t template_file y/n]          (default is ./Infra/main.yml)"
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

# Getting the template parameters

VPC_CIDR=$(jq -r '.[] | select(.ParameterKey == "VpcCidr") | .ParameterValue' ${DIRNAME}/${PARAMS_FILE})
PRIVATE_SUBNET_A_CIDR=$(jq -r '.[] | select(.ParameterKey == "PrivateSubnetACidr") | .ParameterValue' ${DIRNAME}/${PARAMS_FILE})
PRIVATE_SUBNET_B_CIDR=$(jq -r '.[] | select(.ParameterKey == "PrivateSubnetBCidr") | .ParameterValue' ${DIRNAME}/${PARAMS_FILE})
ATTACH_SUBNET_A_CIDR=$(jq -r '.[] | select(.ParameterKey == "AttachSubnetACidr") | .ParameterValue' ${DIRNAME}/${PARAMS_FILE})
ATTACH_SUBNET_B_CIDR=$(jq -r '.[] | select(.ParameterKey == "AttachSubnetBCidr") | .ParameterValue' ${DIRNAME}/${PARAMS_FILE})
SAGEMAKER_DOMAIN_NAME=$(jq -r '.[] | select(.ParameterKey == "SagemakerDomainName") | .ParameterValue' ${DIRNAME}/${PARAMS_FILE})
USER_ID=$(jq -r '.[] | select(.ParameterKey == "UserId") | .ParameterValue' ${DIRNAME}/${PARAMS_FILE})

TEMPLATE_PARAMETERS="ParameterKey=VpcCidr,ParameterValue=${VPC_CIDR} \
        ParameterKey=PrivateSubnetACidr,ParameterValue=${PRIVATE_SUBNET_A_CIDR} \
        ParameterKey=PrivateSubnetBCidr,ParameterValue=${PRIVATE_SUBNET_B_CIDR} \
        ParameterKey=AttachSubnetACidr,ParameterValue=${ATTACH_SUBNET_A_CIDR} \
        ParameterKey=AttachSubnetBCidr,ParameterValue=${ATTACH_SUBNET_B_CIDR} \
        ParameterKey=SagemakerDomainName,ParameterValue=${SAGEMAKER_DOMAIN_NAME} \
        ParameterKey=UserId,ParameterValue=${USER_ID} \
        ParameterKey=SagemakerStudioVpce,ParameterValue=${VPCEndpointSagemakerStudio} \
        ParameterKey=SagemakerApiVpce,ParameterValue=${VPCEndpointSagemakerApi} \
        ParameterKey=LambdaPresignedUrlRoleArn,ParameterValue=${LambdaPresignedFunctionArn} \
        ParameterKey=TGWId,ParameterValue=${TransitGatewayId}"

create_stack_if_not_exist ${STACK_NAME} ${TEMPLATE_FILE} ${PROFILE} ${REGION} "${TEMPLATE_PARAMETERS}"

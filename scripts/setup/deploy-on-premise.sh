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

REGION=$(jq -r '.[] | select(.ParameterKey == "region") | .ParameterValue' ${GENERAL_PARAMS_FILE})

# Templates file names
ON_PREMISE_STACK_NAME=$(jq -r '.[] | select(.ParameterKey == "pOnPremiseStackName") | .ParameterValue' ${GENERAL_PARAMS_FILE})
NETWORK_INFRA_STACK_NAME=$(jq -r '.[] | select(.ParameterKey == "pNetworkingStackName") | .ParameterValue' ${GENERAL_PARAMS_FILE})

# Getting the template parameters
KEY_PAIR_NAME=$(jq -r '.[] | select(.ParameterKey == "pKeyPairName") | .ParameterValue' ${GENERAL_PARAMS_FILE})
IP_TO_CONNECT=$(jq -r '.[] | select(.ParameterKey == "pLocalIpAddress") | .ParameterValue' ${GENERAL_PARAMS_FILE})

ON_PREMISE_PARAMS="ParameterKey=EC2KeyPair,ParameterValue=${KEY_PAIR_NAME} \
  ParameterKey=PublicIp,ParameterValue=${IP_TO_CONNECT}
  "

create_stack_if_not_exist ${ON_PREMISE_STACK_NAME} file://on-premise/template.yml ${SHARED_SERVICES_PROFILE} ${REGION} "${ON_PREMISE_PARAMS}"

########### ASSOCIATE PHZS ############
VPC_ON_PREMISE_ID=$(aws --profile ${SHARED_SERVICES_PROFILE} --region ${REGION} cloudformation describe-stacks --query "Stacks[?StackName=='${ON_PREMISE_STACK_NAME}'][].Outputs[?OutputKey=='OnPremiseVpcId'].OutputValue" --output text)
API_GW_HOSTED_ZONE_ID=$(aws --profile ${SHARED_SERVICES_PROFILE} --region ${REGION} cloudformation describe-stacks --query "Stacks[?StackName=='${NETWORK_INFRA_STACK_NAME}'][].Outputs[?OutputKey=='ApiGatewayHostedZoneId'].OutputValue" --output text)
SAGEMAKER_STUDIO_HOSTED_ZONE_ID=$(aws --profile ${SHARED_SERVICES_PROFILE} --region ${REGION} cloudformation describe-stacks --query "Stacks[?StackName=='${NETWORK_INFRA_STACK_NAME}'][].Outputs[?OutputKey=='SagemakerStudioHostedZoneId'].OutputValue" --output text)

aws route53 associate-vpc-with-hosted-zone \
    --profile $SHARED_SERVICES_PROFILE \
    --hosted-zone-id $API_GW_HOSTED_ZONE_ID \
    --vpc VPCRegion=$REGION,VPCId=$VPC_ON_PREMISE_ID

aws route53 associate-vpc-with-hosted-zone \
    --profile $SHARED_SERVICES_PROFILE \
    --hosted-zone-id $SAGEMAKER_STUDIO_HOSTED_ZONE_ID \
    --vpc VPCRegion=$REGION,VPCId=$VPC_ON_PREMISE_ID
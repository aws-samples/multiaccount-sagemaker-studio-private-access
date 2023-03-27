#!/bin/bash

DIRNAME=$(pwd)

cflag=false
dflag=false

usage () { echo "
    -h -- Opens up this help message
    -c -- Create stacks. Allowed values 'all'
    -d -- Delete stacks. Allowed values 'all'
"; }
options=':c:d:h'
while getopts $options option
do
    case "$option" in
        c  ) cflag=true; STACK_TO_CREATE=${OPTARG};;
        d  ) dflag=true; STACK_TO_DELETE=${OPTARG};;
        h  ) usage; exit;;
        \? ) echo "Unknown option: -$OPTARG" >&2; exit 1;;
        :  ) echo "Missing option argument for -$OPTARG" >&2; exit 1;;
        *  ) echo "Unimplemented option: -$OPTARG" >&2; exit 1;;
    esac
done

# Params files
GENERAL_PARAMS_FILE="${DIRNAME}/scripts/setup/parameters/general-parameters.json"

# AWS Profiles 
SHARED_SERVICES_PROFILE=$(jq -r '.[] | select(.ParameterKey == "pSharedServicesProfile") | .ParameterValue' ${GENERAL_PARAMS_FILE})
SAGEMAKER_LOB_A_PROFILE=$(jq -r '.[] | select(.ParameterKey == "pSagemakerLobAProfile") | .ParameterValue' ${GENERAL_PARAMS_FILE})
SAGEMAKER_LOB_B_PROFILE=$(jq -r '.[] | select(.ParameterKey == "pSagemakerLobBProfile") | .ParameterValue' ${GENERAL_PARAMS_FILE})

REGION=$(jq -r '.[] | select(.ParameterKey == "region") | .ParameterValue' ${GENERAL_PARAMS_FILE})

# Templates file names
NETWORK_INFRA_STACK_NAME=$(jq -r '.[] | select(.ParameterKey == "pNetworkingStackName") | .ParameterValue' ${GENERAL_PARAMS_FILE})
ACCESS_INFRA_STACK_NAME=$(jq -r '.[] | select(.ParameterKey == "pAccessAppStackName") | .ParameterValue' ${GENERAL_PARAMS_FILE})

# Getting account IDs based on profiles
SAGEMAKER_LOB_A_ACCOUNT=$(aws sts get-caller-identity --profile $SAGEMAKER_LOB_A_PROFILE | jq -r .Account)
SAGEMAKER_LOB_B_ACCOUNT=$(aws sts get-caller-identity --profile $SAGEMAKER_LOB_B_PROFILE | jq -r .Account)
SHARED_SERVICES_ACCOUNT=$(aws sts get-caller-identity --profile $SHARED_SERVICES_PROFILE | jq -r .Account)

# CloudFormation resource tags

MANDATORY_TAGS="CostCenter=0000"

# Creates or updates a CloudFormation stack
# Arguments:
#   - $1: Stack name
#   - $2: Template file
#   - $3: AWS Credentials profile
#   - $4: AWS Region
#   - $5: Tags (required)
#   - $6: "parameters" parameter contents (optional)

function deploy_stack {
  if [ $# -lt 6 ]; then
    echo "Not enough arguments supplied calling deploy_stack"
    exit 1
  fi  

  if [ -z "${6}" ]; then
    PARAMETERS=""
  else
    PARAMETERS="--parameter-overrides ${6}"
  fi

  echo "Deploying ${1} stack in ${4} with profile (${3})"
  aws cloudformation deploy \
      --stack-name ${1} \
      --template-file ${2} \
      --tags ${5} \
      --capabilities "CAPABILITY_NAMED_IAM" "CAPABILITY_AUTO_EXPAND" \
      --profile ${3} \
      --region ${4} \
      ${PARAMETERS}
}

if [[ $cflag ]] && [[ $STACK_TO_CREATE = 'all' ]]
then

  ########### SHARED_SERVICES INFRA ############
  # Stacks created in Shared Services Account

  NETWORKING_PARAMS="\
  AccountsList="$SAGEMAKER_LOB_A_ACCOUNT,$SAGEMAKER_LOB_B_ACCOUNT"
  "
  deploy_stack $NETWORK_INFRA_STACK_NAME shared-services-account/networking-resources/template.yml ${SHARED_SERVICES_PROFILE} ${REGION} "${MANDATORY_TAGS}" "${NETWORKING_PARAMS}"

  # Creating the access application
  TRANSIT_GATEWAY_ID=$(aws --profile ${SHARED_SERVICES_PROFILE} --region ${REGION} cloudformation describe-stacks --query "Stacks[?StackName=='${NETWORK_INFRA_STACK_NAME}'][].Outputs[?OutputKey=='TransitGatewayId'].OutputValue" --output text)
  VPC_ENDPOINT_API_GATEWAY=$(aws --profile ${SHARED_SERVICES_PROFILE} --region ${REGION} cloudformation describe-stacks --query "Stacks[?StackName=='${NETWORK_INFRA_STACK_NAME}'][].Outputs[?OutputKey=='VPCEndpointAPIGateway'].OutputValue" --output text)

  ACCESS_PARAMS="\
  TGWId=${TRANSIT_GATEWAY_ID} \
  APIGatewayVpcEndpoint=${VPC_ENDPOINT_API_GATEWAY}
  "
  sam build \
    --profile $SHARED_SERVICES_PROFILE \
    --region $REGION \
    --template-file shared-services-account/access-proxy-app/template.yml

  sam deploy \
    --profile $SHARED_SERVICES_PROFILE \
    --region $REGION \
    --stack-name $ACCESS_INFRA_STACK_NAME \
    --resolve-s3 \
    --capabilities CAPABILITY_NAMED_IAM \
    --parameter-overrides ${ACCESS_PARAMS}

  ########### Associating PHZ ############
  VPC_ACCESS_ID=$(aws --profile ${SHARED_SERVICES_PROFILE} --region ${REGION} cloudformation describe-stacks --query "Stacks[?StackName=='${ACCESS_INFRA_STACK_NAME}'][].Outputs[?OutputKey=='VPCAccess'].OutputValue" --output text)
  STS_HOSTED_ZONE_ID=$(aws --profile ${SHARED_SERVICES_PROFILE} --region ${REGION} cloudformation describe-stacks --query "Stacks[?StackName=='${NETWORK_INFRA_STACK_NAME}'][].Outputs[?OutputKey=='StsHostedZoneId'].OutputValue" --output text)
  SAGEMAKER_API_HOSTED_ZONE_ID=$(aws --profile ${SHARED_SERVICES_PROFILE} --region ${REGION} cloudformation describe-stacks --query "Stacks[?StackName=='${NETWORK_INFRA_STACK_NAME}'][].Outputs[?OutputKey=='SagemakerApiHostedZoneId'].OutputValue" --output text)
  
  aws route53 associate-vpc-with-hosted-zone \
      --profile $SHARED_SERVICES_PROFILE \
      --hosted-zone-id $STS_HOSTED_ZONE_ID \
      --vpc VPCRegion=$REGION,VPCId=$VPC_ACCESS_ID

  aws route53 associate-vpc-with-hosted-zone \
      --profile $SHARED_SERVICES_PROFILE \
      --hosted-zone-id $SAGEMAKER_API_HOSTED_ZONE_ID \
      --vpc VPCRegion=$REGION,VPCId=$VPC_ACCESS_ID
fi
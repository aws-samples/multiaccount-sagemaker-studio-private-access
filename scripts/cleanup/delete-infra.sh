#!/bin/bash

echo "Fetching parameters"

DIRNAME=$(pwd)

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
ON_PREMISE_STACK_NAME=$(jq -r '.[] | select(.ParameterKey == "pOnPremiseStackName") | .ParameterValue' ${GENERAL_PARAMS_FILE})
SAGEMAKER_LOB_A_STACK_NAME=$(jq -r '.[] | select(.ParameterKey == "pSagemakerLobAStackName") | .ParameterValue' ${GENERAL_PARAMS_FILE})
SAGEMAKER_LOB_B_STACK_NAME=$(jq -r '.[] | select(.ParameterKey == "pSagemakerLobBStackName") | .ParameterValue' ${GENERAL_PARAMS_FILE})

# Getting account IDs based on profiles
SAGEMAKER_LOB_A_ACCOUNT=$(aws sts get-caller-identity --profile $SAGEMAKER_LOB_A_PROFILE | jq -r .Account)
SAGEMAKER_LOB_B_ACCOUNT=$(aws sts get-caller-identity --profile $SAGEMAKER_LOB_B_PROFILE | jq -r .Account)
SHARED_SERVICES_ACCOUNT=$(aws sts get-caller-identity --profile $SHARED_SERVICES_PROFILE | jq -r .Account)

# Deletes a CloudFormation if exists
# Arguments:
#   - $1: Stack name
#   - $2: AWS Credentials profile
#   - $3: AWS Region
#   - $4: CloudWatch logGroups prefix

function delete_stack_if_exists {
  if [ $# -lt 3 ]; then
    echo "Not enough arguments supplied calling delete_stack_if_exists"
    exit 1
  fi

  echo "Deleting ${1} stack in ${2} account region (${3})"
  export STACK_NAME=$1
  CHECK_STACK=$(aws --profile ${2} --region ${3} cloudformation list-stacks | jq -r '.StackSummaries[] | select(.StackStatus != "DELETE_COMPLETE") | select(.StackName == env.STACK_NAME) | .StackName')
  if [ "${STACK_NAME}" = "${CHECK_STACK}" ]; then
    echo "Deleting stack ${STACK_NAME}"
    aws cloudformation delete-stack \
        --profile ${2}  \
        --region ${3} \
        --stack-name ${STACK_NAME}
    if [ $? -eq 0 ]; then
      echo "Waiting for stack ${STACK_NAME} to be deleted ..."
      aws cloudformation wait stack-delete-complete --profile ${2} --region ${3} --stack-name ${STACK_NAME}
      if [ $? -eq 0 ]; then
        echo "${STACK_NAME} stack deleted successfully"
        # Delete CloudWatch logGroups if exist
        LOG_GROUPS=$(aws --profile ${2} --region ${3} logs describe-log-groups --query "logGroups[?contains(logGroupName, '${4}')][].logGroupName[]" --output text)
        if [ -z "${4}" ]; then
         echo "No LogGroup to delete"
        else
          for LOG_GROUP in ${LOG_GROUPS}
          do
            echo "Deleting LogGroup ${LOG_GROUP}"
            DELETE_RESULT=$(aws --profile ${2} --region ${3} logs delete-log-group --log-group-name ${LOG_GROUP})
          done
        fi
      else
        echo "Failed to delete the stack"
      fi
    else
      echo "Failed to delete the stack"
    fi
  else
    echo "The stack ${STACK_NAME} does not exist"
  fi
}

########### DELETE STACKS ############

delete_stack_if_exists $ON_PREMISE_STACK_NAME $SHARED_SERVICES_PROFILE $REGION
delete_stack_if_exists $SAGEMAKER_LOB_A_STACK_NAME $SAGEMAKER_LOB_A_PROFILE $REGION
delete_stack_if_exists $SAGEMAKER_LOB_B_STACK_NAME $SAGEMAKER_LOB_B_PROFILE $REGION
delete_stack_if_exists $ACCESS_INFRA_STACK_NAME $SHARED_SERVICES_PROFILE $REGION
delete_stack_if_exists $NETWORK_INFRA_STACK_NAME $SHARED_SERVICES_PROFILE $REGION

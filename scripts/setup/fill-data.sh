DIRNAME=$(pwd)
echo "Fetching parameters..."
# Params files
GENERAL_PARAMS_FILE="${DIRNAME}/scripts/setup/parameters/general-parameters.json"

# AWS Profiles 
SHARED_SERVICES_PROFILE=$(jq -r '.[] | select(.ParameterKey == "pSharedServicesProfile") | .ParameterValue' ${GENERAL_PARAMS_FILE})
SAGEMAKER_LOB_A_PROFILE=$(jq -r '.[] | select(.ParameterKey == "pSagemakerLobAProfile") | .ParameterValue' ${GENERAL_PARAMS_FILE})
SAGEMAKER_LOB_B_PROFILE=$(jq -r '.[] | select(.ParameterKey == "pSagemakerLobBProfile") | .ParameterValue' ${GENERAL_PARAMS_FILE})

REGION=$(jq -r '.[] | select(.ParameterKey == "region") | .ParameterValue' ${GENERAL_PARAMS_FILE})

# Getting account IDs based on profiles
SAGEMAKER_LOB_A_ACCOUNT=$(aws sts get-caller-identity --profile $SAGEMAKER_LOB_A_PROFILE | jq -r .Account)
SAGEMAKER_LOB_B_ACCOUNT=$(aws sts get-caller-identity --profile $SAGEMAKER_LOB_B_PROFILE | jq -r .Account)

# Templates file names
ACCESS_INFRA_STACK_NAME=$(jq -r '.[] | select(.ParameterKey == "pAccessAppStackName") | .ParameterValue' ${GENERAL_PARAMS_FILE})

USERS_DYNAMO_DB_TABLE=$(aws --profile ${SHARED_SERVICES_PROFILE} --region ${REGION} cloudformation describe-stacks --query "Stacks[?StackName=='${ACCESS_INFRA_STACK_NAME}'][].Outputs[?OutputKey=='UsersMapDynamoDbTable'].OutputValue" --output text)
LOBS_DYNAMO_DB_TABLE=$(aws --profile ${SHARED_SERVICES_PROFILE} --region ${REGION} cloudformation describe-stacks --query "Stacks[?StackName=='${ACCESS_INFRA_STACK_NAME}'][].Outputs[?OutputKey=='LobsMapDynamoDbTable'].OutputValue" --output text)
COGNITO_USER_POOL_ID=$(aws --profile ${SHARED_SERVICES_PROFILE} --region ${REGION} cloudformation describe-stacks --query "Stacks[?StackName=='${ACCESS_INFRA_STACK_NAME}'][].Outputs[?OutputKey=='CognitoUserPoolId'].OutputValue" --output text)

########### Filling Dynamo DB Tables ############

### Adding users

echo "Adding users to respective Table"

aws dynamodb put-item \
    --profile $SHARED_SERVICES_PROFILE \
    --region $REGION \
    --table-name $USERS_DYNAMO_DB_TABLE \
    --item "{\"PK\":{\"S\":\"user-lob-a\"},\"LOB\":{\"S\":\"lob-a\"}}"

aws dynamodb put-item \
    --profile $SHARED_SERVICES_PROFILE \
    --region $REGION \
    --table-name $USERS_DYNAMO_DB_TABLE \
    --item "{\"PK\":{\"S\":\"user-lob-b\"},\"LOB\":{\"S\":\"lob-b\"}}"

### Adding LOBs

echo "Adding LOBs to respective table"

aws dynamodb put-item \
    --profile $SHARED_SERVICES_PROFILE \
    --region $REGION \
    --table-name $LOBS_DYNAMO_DB_TABLE \
    --item "{\"PK\":{\"S\":\"lob-a\"},\"ACCOUNT_ID\":{\"S\":\"${SAGEMAKER_LOB_A_ACCOUNT}\"}}"

aws dynamodb put-item \
    --profile $SHARED_SERVICES_PROFILE \
    --region $REGION \
    --table-name $LOBS_DYNAMO_DB_TABLE \
    --item "{\"PK\":{\"S\":\"lob-b\"},\"ACCOUNT_ID\":{\"S\":\"${SAGEMAKER_LOB_B_ACCOUNT}\"}}"


########### Filling Cognito IDP ############

echo "Filling cognito user pool"

#### Adding the LOB A user

aws cognito-idp admin-create-user \
    --profile $SHARED_SERVICES_PROFILE \
    --region $REGION \
    --user-pool-id $COGNITO_USER_POOL_ID \
    --username user-lob-a

aws cognito-idp admin-set-user-password \
    --profile $SHARED_SERVICES_PROFILE \
    --region $REGION \
    --user-pool-id $COGNITO_USER_POOL_ID \
    --permanent \
    --username user-lob-a \
    --password UserLobA1!

#### Adding the LOB B user

aws cognito-idp admin-create-user \
    --profile $SHARED_SERVICES_PROFILE \
    --region $REGION \
    --user-pool-id $COGNITO_USER_POOL_ID \
    --username user-lob-b \

aws cognito-idp admin-set-user-password \
    --profile $SHARED_SERVICES_PROFILE \
    --region $REGION \
    --user-pool-id $COGNITO_USER_POOL_ID \
    --permanent \
    --username user-lob-b \
    --password UserLobB1!

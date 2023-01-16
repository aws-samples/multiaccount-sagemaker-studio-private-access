#!/bin/bash

export OnPremiseVpcId=$(aws cloudformation describe-stacks --query 'Stacks[?StackName==`on-premise`][].Outputs[?OutputKey==`OnPremiseVpcId`].OutputValue' --output text)
echo "Saved as OnPremiseVpcId: ${OnPremiseVpcId}"
aws route53 disassociate-vpc-from-hosted-zone \
    --profile $SHARED_SERVICES_PROFILE \
    --hosted-zone-id $StsHostedZoneId \
    --vpc VPCRegion=$AWS_DEFAULT_REGION,VPCId=$VpcAccessId

aws route53 disassociate-vpc-from-hosted-zone \
    --profile $SHARED_SERVICES_PROFILE \
    --hosted-zone-id $SagemakerApiHostedZoneId \
    --vpc VPCRegion=$AWS_DEFAULT_REGION,VPCId=$VpcAccessId

aws route53 disassociate-vpc-from-hosted-zone \
    --profile $SHARED_SERVICES_PROFILE \
    --hosted-zone-id $ApiGatewayHostedZoneId \
    --vpc VPCRegion=$AWS_DEFAULT_REGION,VPCId=$OnPremiseVpcId

aws route53 disassociate-vpc-from-hosted-zone \
    --profile $SHARED_SERVICES_PROFILE \
    --hosted-zone-id $SagemakerStudioHostedZoneId \
    --vpc VPCRegion=$AWS_DEFAULT_REGION,VPCId=$OnPremiseVpcId
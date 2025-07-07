#!/bin/bash

#########################################################################################
# HOW TO USE THIS SCRIPT:                                                               #
# -Go to az-weu-gl-aks-dev-dxp-core cluster                                             #
# -Run ./new-namespace-pre-prod-dew.sh <new-ns-name> pre-prod                           #
#                                                                                       #
# NOTE!                                                                                 #
# The name supplied in <new-ns-name> will be the default namespace name, appended       #
# with 'dew'. This will also be the default hostname. Please modify the hostname if     #
# you prefer a different one.                                                           #
#                                                                                       #
# Expected Outputs:                                                                     #
#   namespace: <new-ns-name>-dew                                                        #
#   host: eu-ecom-<new-ns-name>.inchcapedigital.com                                     #
#########################################################################################

NEW_NS="germany-west-central-$1"
REF_NS="germany-west-central-$2"

# Create new namespace
NAMESPACE="$1-dew"
kubectl create namespace "$NAMESPACE"
kubectl annotate namespace "$NAMESPACE" scheduler.alpha.kubernetes.io/node-selector='app=dev'
kubectl annotate namespace "$NAMESPACE" scheduler.alpha.kubernetes.io/defaultTolerations='[{"operator": "Equal", "value": "qa", "effect": "NoSchedule", "key": "app"}]'

# Create new directory for the new environment based on an existing environment
cd uk-tenant/environments-prod
mkdir -pv $NEW_NS/markets

# Copy and rename argocd app file
cp -v "$REF_NS.yml" "$NEW_NS.yml"

# Copy and rename application files
cp -v $REF_NS/"configuration-management-$2.yml" $NEW_NS/"configuration-management-$1.yml"
# cp -v $REF_NS/"finance-gateway-api-$2.yml" $NEW_NS/"finance-gateway-api-$1.yml"
cp -v $REF_NS/"psql-client-$2.yml" $NEW_NS/"psql-client-$1.yml"
cp -v $REF_NS/"x15-platform-api-$2.yml" $NEW_NS/"x15-platform-api-$1.yml"
cp -v $REF_NS/"kustomization.yaml" $NEW_NS/"kustomization.yaml"

# Copy and rename files in markets folder
cp -v $REF_NS/markets/"cms-mock-$2-eu-ee-jag-dis.yml" $NEW_NS/markets/"cms-mock-$1-eu-ee-jag-dis.yml"
cp -v $REF_NS/markets/"dxp-widgets-$2-eu-ee-jag-dis.yml" $NEW_NS/markets/"dxp-widgets-$1-eu-ee-jag-dis.yml"
cp -v $REF_NS/markets/"widgets-$2-eu-ee-jag-dis.yml" $NEW_NS/markets/"widgets-$1-eu-ee-jag-dis.yml"
CMS="cms-mock-$1-eu-ee-jag-dis.yml"
DXP="dxp-widgets-$1-eu-ee-jag-dis.yml"
WIDGETS="widgets-$1-eu-ee-jag-dis.yml"

# Modify argocd app file
yq e ".metadata.name = \"$NEW_NS\"" -i "$NEW_NS.yml"
PATH_ARGOCD="uk-tenant/environments-prod/$NEW_NS"
yq e ".spec.source.path = \"$PATH_ARGOCD\"" -i "$NEW_NS.yml"
# Apply argocd
kubectl apply -f "$NEW_NS.yml"

# NEW ENV FOLDER
cd $NEW_NS
REF_HOST="eu-ecom-preprod.inchcapedigital.com"
NEW_HOST="eu-ecom-$1.inchcapedigital.com"
#Applications
yq e 'del(.resources[] | select(. == "*.yml"))' -i kustomization.yaml
for app in "x15-platform-api" "psql-client" "configuration-management"; do
    METADATA_NAME="${app}-$1-dew"
    FILE="${app}-$1.yml"
    yq e ".metadata.name = \"$METADATA_NAME\"" -i $FILE
    yq e ".spec.destination.namespace = \"$NAMESPACE\"" -i $FILE
    yq e ".resources += \"$FILE\"" -i kustomization.yaml

    if [[ "$app" == "x15-platform-api" || "$app" == "configuration-management" ]]; then
        yq e ".spec.source.helm.values |= sub(\"$REF_HOST\", \"$NEW_HOST\")" -i $FILE
    fi

    if [[ "$app" == "x15-platform-api" ]]; then
        REF_APPCONFIG="http://configuration-management-$2-dew:8086"
        NEW_APPCONFIG="http://configuration-management-$1-dew:8086"
        yq e ".spec.source.helm.values |= sub(\"$REF_APPCONFIG\", \"$NEW_APPCONFIG\")" -i $FILE
    fi
done
#kustomization
RESOURCE_FILES=("markets/$CMS" "markets/$DXP" "markets/$WIDGETS")
yq e ".resources += [\"${RESOURCE_FILES[0]}\", \"${RESOURCE_FILES[1]}\", \"${RESOURCE_FILES[2]}\"]" -i kustomization.yaml
echo "app files modified"

# MARKETS FOLDER
cd markets
for app in "cms-mock" "dxp-widgets" "widgets"; do
    FILE=$(find -type f -name "${app}*.yml")
    METADATA_NAME="${app}-$1-dew-eu-ee-jag-dis"
    yq e ".metadata.name = \"$METADATA_NAME\"" -i "$FILE"
    yq e ".spec.destination.namespace = \"$NAMESPACE\"" -i "$FILE"
    yq e ".spec.source.helm.values |= sub(\"$REF_HOST\", \"$NEW_HOST\")" -i "$FILE"

    if [[ "$app" == "cms-mock" ]]; then
        REF_AUTH_SECRET="cms-mock-$2-dew-eu-ee-jag-dis"
        yq e ".spec.source.helm.values |= sub(\"$REF_AUTH_SECRET\", \"$METADATA_NAME\")" -i "$FILE"
    fi

    if [[ "$app" == "dxp-widgets" ]]; then
        VALUE="dxp-widgets-$1-dew"
        yq e ".spec.source.helm.parameters[1].value = \"$VALUE\"" -i "$FILE"
    fi

    if [[ "$app" == "widgets" ]]; then
        VALUE="automotive-inchcape-widgets-$1-dew"
        yq e ".spec.source.helm.parameters[1].value = \"$VALUE\"" -i "$FILE"
    fi
done
echo "markets modified"

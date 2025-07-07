#!/bin/bash

#########################################################################################
# HOW TO USE THIS SCRIPT:                                                               #
# -Go to az-weu-gl-aks-dev-dxp-core cluster                                             #
# -Run ./new-namespace-dev.sh <new-ns-name> <reference-ns-name>                         #
#                                                                                       #
# NOTE!                                                                                 #
# The name supplied in <new-ns-name> will be the default namespace name, this will      #
# also be the default hostname. Please modify the hostname if you prefer a different    #
# one.                                                                                  #
#                                                                                       #
# Valid inputs for <reference-ns-name>:                                                 #
#   dev, dev-hk, sit, sit-hk, uat & uat-hk                                              #
#                                                                                       #
# Expected outputs:                                                                     #
#   namespace: <new-ns-name>                                                            #
#   host: au-ecom-<new-ns-name>.inchcapedigital.com                                     #
#########################################################################################

NEW_NS="australia-east-$1"
REF_NS="australia-east-$2"

# Create new namespace
kubectl create namespace $1
kubectl annotate namespace $1 scheduler.alpha.kubernetes.io/node-selector='app=qa'
kubectl annotate namespace $1 scheduler.alpha.kubernetes.io/defaultTolerations='[{"operator": "Equal", "value": "dev", "effect": "NoSchedule", "key": "app"}]'

# Create new directory for the new environment based on an existing environment
cd uk-tenant/environments
mkdir -pv $NEW_NS/{markets,patches}

# Copy and rename argocd app file
cp -v "$REF_NS.yml" "$NEW_NS.yml"

# Copy and rename application files
cp -v $REF_NS/"configuration-management-$2.yml" $NEW_NS/"configuration-management-$1.yml"
cp -v $REF_NS/"finance-gateway-api-$2.yml" $NEW_NS/"finance-gateway-api-$1.yml"
cp -v $REF_NS/"psql-client-$2.yml" $NEW_NS/"psql-client-$1.yml"
cp -v $REF_NS/"x15-platform-api-$2.yml" $NEW_NS/"x15-platform-api-$1.yml"
cp -v $REF_NS/"kustomization.yaml" $NEW_NS/"kustomization.yaml"

# Copy and rename files in patches folder
cp -v $REF_NS/patches/"cms-mock-$2.yml" $NEW_NS/patches/"cms-mock-$1.yml"
cp -v $REF_NS/patches/"dxp-widgets-$2.yml" $NEW_NS/patches/"dxp-widgets-$1.yml"
cp -v $REF_NS/patches/"widgets-$2.yml" $NEW_NS/patches/"widgets-$1.yml"

# Copy and rename files in markets folder
ENV=$2
if [[ $ENV == "dev-hk" || $ENV == "sit-hk" || $ENV == "uat-hk" ]]; then
    cp -v $REF_NS/markets/"cms-mock-$2-au-hk-toy-dis.yml" $NEW_NS/markets/"cms-mock-$1-au-hk-toy-dis.yml"
    cp -v $REF_NS/markets/"dxp-widgets-$2-au-hk-toy-dis.yml" $NEW_NS/markets/"dxp-widgets-$1-au-hk-toy-dis.yml"
    cp -v $REF_NS/markets/"widgets-$2-au-hk-toy-dis.yml" $NEW_NS/markets/"widgets-$1-au-hk-toy-dis.yml"
    CMS="cms-mock-$1-au-hk-toy-dis.yml"
    DXP="dxp-widgets-$1-au-hk-toy-dis.yml"
    WIDGETS="widgets-$1-au-hk-toy-dis.yml"
else [[ $ENV == "dev" || $ENV == "sit" || $ENV == "uat" ]]
    cp -v $REF_NS/markets/"cms-mock-$2-latam-cl-sub-dis.yml" $NEW_NS/markets/"cms-mock-$1-latam-cl-sub-dis.yml"
    cp -v $REF_NS/markets/"dxp-widgets-$2-latam-cl-sub-dis.yml" $NEW_NS/markets/"dxp-widgets-$1-latam-cl-sub-dis.yml"
    cp -v $REF_NS/markets/"widgets-$2-latam-cl-sub-dis.yml" $NEW_NS/markets/"widgets-$1-latam-cl-sub-dis.yml"
    CMS="cms-mock-$1-latam-cl-sub-dis.yml"
    DXP="dxp-widgets-$1-latam-cl-sub-dis.yml"
    WIDGETS="widgets-$1-latam-cl-sub-dis.yml"
fi

# Modify argocd app file
yq e ".metadata.name = \"$NEW_NS\"" -i "$NEW_NS.yml"
PATH_ARGOCD="uk-tenant/environments/$NEW_NS"
yq e ".spec.source.path = \"$PATH_ARGOCD\"" -i "$NEW_NS.yml"
# Apply argocd
kubectl apply -f "$NEW_NS.yml"

# NEW ENV FOLDER
cd $NEW_NS
REF_HOST="au-ecom-$2.inchcapedigital.com"
NEW_HOST="au-ecom-$1.inchcapedigital.com"
#Applications
yq e 'del(.resources[] | select(. == "*.yml"))' -i kustomization.yaml
for app in "x15-platform-api" "psql-client" "finance-gateway-api" "configuration-management"; do
    METADATA_NAME="${app}-$1"
    FILE="$METADATA_NAME.yml"
    yq e ".metadata.name = \"$METADATA_NAME\"" -i $FILE
    yq e ".spec.destination.namespace = \"$1\"" -i $FILE
    yq e ".resources += \"$FILE\"" -i kustomization.yaml

    if [[ "$app" == "x15-platform-api" || "$app" == "finance-gateway-api" || "$app" == "configuration-management" ]]; then
        yq e ".spec.source.helm.values |= sub(\"$REF_HOST\", \"$NEW_HOST\")" -i $FILE
    fi

    if [[ "$app" == "x15-platform-api" ]]; then
        REF_APPCONFIG="http://configuration-management-$2:8086"
        NEW_APPCONFIG="http://configuration-management-$1:8086"
        yq e ".spec.source.helm.values |= sub(\"$REF_APPCONFIG\", \"$NEW_APPCONFIG\")" -i $FILE
    fi
done
#kustomization
PATH_WIDGETS="patches/widgets-$1.yml"
PATH_DXP="patches/dxp-widgets-$1.yml"
PATH_CMS="patches/cms-mock-$1.yml"
yq e ".patches[0].path = \"$PATH_WIDGETS\"" -i kustomization.yaml
yq e ".patches[1].path = \"$PATH_DXP\"" -i kustomization.yaml
yq e ".patches[2].path = \"$PATH_CMS\"" -i kustomization.yaml
RESOURCE_FILES=("markets/$CMS" "markets/$DXP" "markets/$WIDGETS")
yq e ".resources += [\"${RESOURCE_FILES[0]}\", \"${RESOURCE_FILES[1]}\", \"${RESOURCE_FILES[2]}\"]" -i kustomization.yaml
echo "app files modified"

# PATCHES FOLDER
cd patches
DXP_WIDGETS="dxp-widgets-"
yq e ".spec.source.helm.parameters[1].value = \"$DXP_WIDGETS$1\"" -i "dxp-widgets-$1.yml"
WIDGETS="automotive-inchcape-widgets-"
yq e ".spec.source.helm.parameters[1].value = \"$WIDGETS$1\"" -i "widgets-$1.yml"
echo "patches modified"

# MARKETS FOLDER
cd ../markets
if [[ $ENV == "dev-hk" || $ENV == "sit-hk" || $ENV == "uat-hk" ]]; then
    for app in "cms-mock" "dxp-widgets" "widgets"; do
        FILE=$(find -type f -name "${app}*.yml")
        METADATA_NAME="${app}-$1-au-hk-toy-dis"
        yq e ".metadata.name = \"$METADATA_NAME\"" -i "$FILE"
        yq e ".spec.destination.namespace = \"$1\"" -i "$FILE"
        yq e ".spec.source.helm.values |= sub(\"$REF_HOST\", \"$NEW_HOST\")" -i "$FILE"

        if [[ "$app" == "cms-mock" ]]; then
            REF_AUTH_SECRET="cms-mock-$2-au-hk-toy-dis"
            yq e ".spec.source.helm.values |= sub(\"$REF_AUTH_SECRET\", \"$METADATA_NAME\")" -i "$FILE"
        fi
    done
else [[ $ENV == "dev" || $ENV == "sit" || $ENV == "uat" ]]
    for app in "cms-mock" "dxp-widgets" "widgets"; do
        FILE=$(find -type f -name "${app}*.yml")
        METADATA_NAME="${app}-$1-latam-cl-sub-dis"
        yq e ".metadata.name = \"$METADATA_NAME\"" -i "$FILE"
        yq e ".spec.destination.namespace = \"$1\"" -i "$FILE"
        yq e ".spec.source.helm.values |= sub(\"$REF_HOST\", \"$NEW_HOST\")" -i "$FILE"

        if [[ "$app" == "cms-mock" ]]; then
            REF_AUTH_SECRET="cms-mock-$2-latam-cl-sub-dis"
            yq e ".spec.source.helm.values |= sub(\"$REF_AUTH_SECRET\", \"$METADATA_NAME\")" -i "$FILE"
        fi
    done
fi
echo "markets modified"

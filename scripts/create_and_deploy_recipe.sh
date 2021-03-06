#!/bin/bash

# create_and_deploy_recipe.sh - Generates deployed network configuration (based on a recipe) and private build and pushes to S3
#
# Syntax:   create_and_deploy_recipe.sh -c <channel/network> [-n network] --recipe <recipe file> -r <rootdir> [--nodeploy] [--force] [-m genesisVersionModifier]"
#
# Outputs:  <errors or warnings>
#
# ExitCode: 0 = Success - config generated and uploaded, and new version built and uploaded
#
# Usage:    Generates deployed network configuration (nodecfg package) and cloudspec.config (for TF/algonet),
#           sends it to S3, then uses the deploy_private_version script to build the private version with the
#           correct genesis file and uploads it to S3 (if --nodeply specified only the config is build and uploaded).
#
# Examples: create_and_deploy_recipe.sh -c TestCatchup --recipe test/testdata/deployednettemplates/recipes/devnet-like.config -r ~/networks/gen
#
# Notes:    If you're running on a Mac, this will attempt to use docker to build for linux.

set -e

if [[ "${S3_UPLOAD_ID}" = "" || "${S3_UPLOAD_SECRET}" = "" || "${S3_UPLOAD_BUCKET}" = "" ]]; then
    echo "You need to export S3_UPLOAD_ID, S3_UPLOAD_SECRECT and S3_UPLOAD_BUCKET for this to work"
    exit 1
fi

SCRIPTPATH="$( cd "$(dirname "$0")" ; pwd -P )"
export GOPATH=$(go env GOPATH)
export SRCPATH=${GOPATH}/src/github.com/algorand/go-algorand

CHANNEL=""
NETWORK=""
RECIPEFILE=""
ROOTDIR=""
NO_DEPLOY=""
FORCE_OPTION=""
SCHEMA_MODIFIER=""

while [ "$1" != "" ]; do
    case "$1" in
        -c)
            shift
            CHANNEL=$1
            ;;
        -n)
            shift
            NETWORK=$1
            ;;
        -m)
            shift
            SCHEMA_MODIFIER=$1
            ;;
        --recipe)
            shift
            RECIPEFILE=$1
            ;;
        -r)
            shift
            ROOTDIR=$1
            ;;
        --force)
            FORCE_OPTION="--force"
            ;;
        --nodeploy)
            NO_DEPLOY="true"
            ;;
        *)
            echo "Unknown option" "$1"
            exit 1
            ;;
    esac
    shift
done

if [[ -z "${CHANNEL}" || -z "${RECIPEFILE}" || -z "${ROOTDIR}" ]]; then
    echo "Syntax: create_and_deploy_recipe.sh -c <channel/network> [-n network] --recipe <recipe file> -r <rootdir> [--nodeploy] [--force]"
    echo "e.g. create_and_deploy_recipe.sh -c TestCatchup --recipe test/testdata/deployednettemplates/recipes/devnet-like.config -r ~/networks/<channel>/gen"
    exit 1
fi

# if Network isn't specified, use the same string as Channel
if [[ "${NETWORK}" = "" ]]; then
    NETWORK=${CHANNEL}
fi

# Build so we've got up-to-date binaries
(cd ${SRCPATH} && make)

# Generate the nodecfg package directory
${GOPATH}/bin/netgoal build -r "${ROOTDIR}" -n "${NETWORK}" --recipe "${RECIPEFILE}" "${FORCE_OPTION}" -m "${SCHEMA_MODIFIER}"

# Package and upload the config package
${SRCPATH}/scripts/upload_config.sh "${ROOTDIR}" "${CHANNEL}"

if [ "${NO_DEPLOY}" = "" ]; then
    # Now generate a private build using our custom genesis.json and deploy it to S3 also
    ${SRCPATH}/scripts/deploy_private_version.sh -c "${CHANNEL}" -f "${ROOTDIR}/genesisdata/genesis.json" -n "${NETWORK}"
fi

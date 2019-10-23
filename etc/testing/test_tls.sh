#!/bin/bash

set -euo pipefail

address=$(pachctl config get context `pachctl config get active-context` | jq -r .pachd_address)
if [[ "${address}" = "null" ]]; then
  echo "pachd_address must be set on the active context"
  exit 1
fi
hostport=$(echo $address | sed -e 's/grpcs:\/\///g' -e 's/grpc:\/\///g')

# Generate self-signed cert and private key
etc/deploy/gen_pachd_tls.sh $hostport ""

# Restart pachyderm with the given certs
etc/deploy/restart_with_tls.sh $hostport ${PWD}/pachd.pem ${PWD}/pachd.key

set +x
# Don't log our activation code when running this script in Travis
pachctl enterprise activate "$(aws s3 cp s3://pachyderm-engineering/test_enterprise_activation_code.txt -)" && echo
set -x

# Make sure the pachyderm client can connect, write data, and create pipelines
go test -v ./src/server -run TestPipelineWithParallelism

# Make sure that config's pachd_address isn't disfigured by pachctl cmds (bug
# fix)
echo admin | pachctl auth activate
otp="$(pachctl auth get-otp admin)"
echo "${otp}" | pachctl auth login --one-time-password
pachctl auth whoami | grep -q admin # will fail if pachctl can't connect
echo yes | pachctl auth deactivate

# Undeploy TLS
yes | pachctl undeploy || true
pachctl deploy local -d

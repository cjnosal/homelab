#!/usr/bin/env bash
# source from vm-specific generate.sh scripts

command -v ytt > /dev/null || (echo "ytt required" ; exit 1)

function write_snippet {
	FILENAME=$1
	shift
	EXTRA_YTT_ARGS=$@

	echo '#cloud-config' > /var/lib/vz/snippets/$FILENAME # ytt can't write comments

	CA_ARGS=""
	if [[ -f ${SCRIPT_DIR}/../step_root_ca.pem ]]
	then
		CA_ARGS="$CA_ARGS --data-value-file step_root_ca=${SCRIPT_DIR}/../step_root_ca.pem"
	fi
	if [[ -f ${SCRIPT_DIR}/../step_intermediate_ca.pem ]]
	then
		CA_ARGS="$CA_ARGS --data-value-file step_intermediate_ca=${SCRIPT_DIR}/../step_intermediate_ca.pem"
	fi

	VAULT_ARGS=""
	if [[ -f ${SCRIPT_DIR}/../vault_host_ssh_ca.pem ]]
	then
		VAULT_ARGS="$VAULT_ARGS --data-value-file vault_host_ssh_ca=${SCRIPT_DIR}/../vault_host_ssh_ca.pem"
	fi
	if [[ -f ${SCRIPT_DIR}/../vault_client_ssh_ca.pem ]]
	then
		VAULT_ARGS="$VAULT_ARGS --data-value-file vault_client_ssh_ca=${SCRIPT_DIR}/../vault_client_ssh_ca.pem"
	fi
	if [[ -f ${SCRIPT_DIR}/../ssh_host_role_id ]]
	then
		VAULT_ARGS="$VAULT_ARGS --data-value-file ssh_host_role_id=${SCRIPT_DIR}/../ssh_host_role_id"
	fi

	ytt -f ${SCRIPT_DIR}/../base-user-data.yml \
	  --data-values-env YTT \
	  --data-value-file ssh_authorized_keys=/root/.ssh/vm.pub \
	  --data-value-file runcmd=${SCRIPT_DIR}/runcmd \
	  $CA_ARGS $VAULT_ARGS $EXTRA_YTT_ARGS >> /var/lib/vz/snippets/$FILENAME

	echo wrote /var/lib/vz/snippets/$FILENAME
}
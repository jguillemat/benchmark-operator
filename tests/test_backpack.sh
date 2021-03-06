#!/usr/bin/env bash
set -xeEo pipefail

source tests/common.sh

function finish {
  if [ $? -eq 1 ] && [ $ERRORED != "true" ]
  then
    error
  fi

  echo "Cleaning up backpack"
  kubectl delete -f resources/backpack_role.yaml
  wait_clean
}

trap error ERR
trap finish EXIT

function functional_test_backpack {
  backpack_requirements
  cr=$1
  delete_benchmark $cr
  kubectl apply -f $cr
  benchmark_name=$(get_benchmark_name $cr)
  long_uuid=$(get_uuid $benchmark_name)
  uuid=${long_uuid:0:8}

  if [[ $1 == "tests/test_crs/valid_backpack_daemonset.yaml" ]]
  then
    wait_for_backpack $uuid
  else
    byowl_pod=$(get_pod "app=byowl-$uuid" 300)
    wait_for "kubectl -n benchmark-operator wait --for=condition=Initialized pods/$byowl_pod --timeout=500s" "500s" $byowl_pod
    wait_for "kubectl -n benchmark-operator  wait --for=condition=complete -l app=byowl-$uuid jobs --timeout=500s" "500s" $byowl_pod
  fi
  
  indexes="cpu_vulnerabilities-metadata cpuinfo-metadata dmidecode-metadata k8s_nodes-metadata lspci-metadata meminfo-metadata sysctl-metadata ocp_network_operator-metadata ocp_install_config-metadata ocp_kube_apiserver-metadata ocp_dns-metadata ocp_kube_controllermanager-metadata"
  if check_es "${long_uuid}" "${indexes}"
  then
    echo "Backpack test: Success"
  else
    echo "Failed to find data in ES"
    exit 1
  fi
  delete_benchmark $cr
}

figlet $(basename $0)
functional_test_backpack tests/test_crs/valid_backpack_daemonset.yaml
functional_test_backpack tests/test_crs/valid_backpack_init.yaml

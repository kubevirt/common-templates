#!/usr/bin/bash

set -e

K6T_VER=$1

bold() { echo -e "\e[1m$@\e[0m" ; }
red() { echo -e "\e[31m$@\e[0m" ; }
green() { echo -e "\e[32m$@\e[0m" ; }

PASS() { green PASS ; }

condTravisFold() {
  [[ -n "$TRAVIS" ]] && echo "travis_fold:start:SCRIPT folding starts" || :
  eval "$@"
  [[ -n "$TRAVIS" ]] && echo "travis_fold:end:SCRIPT folding ends" || :
}

timeout_while() { timeout $1 sh -c "while true; do $2 && break || : ; sleep 1 ; done" ; }

k_wait_all_running() { while [[ "$(kubectl get $1 --all-namespaces --field-selector=status.phase!=Running | wc -l)" -gt 1 ]]; do kubectl get $1 --all-namespaces ; sleep 6; done ; }

{
  set -xe

  kubectl create configmap -n kube-system kubevirt-config --from-literal debug.allowEmulation=true || :

  kubectl apply -f https://github.com/kubevirt/kubevirt/releases/download/$K6T_VER/kubevirt.yaml ;

  kubectl api-versions | grep kubevirt.io

  condTravisFold k_wait_all_running pods

  make test-functional
}

#curl -Lo virtctl https://github.com/kubevirt/kubevirt/releases/download/v$K6T_VER/virtctl-v$K6T_VER-linux-amd64 && chmod +x virtctl && sudo mv virtctl /usr/local/bin

PASS

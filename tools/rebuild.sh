#!/bin/bash

# Copyright 2017 Univa Corporation
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -x

# remove docker image
rmi() {
  local nm=$1
  local img=$(docker images | awk "/$nm/ {print \$3}")
  local containers=$(docker ps -a | awk "/$img/ {print \$1}")
  if [ ! -z "$containers" ]; then
    docker rm $containers  
  fi
  docker rmi $img
}

# remove <none> docker images
rmi_none() {
  docker rmi $(docker images | awk "/^<none>/ {print \$3}")
}

# set minikube docker environment
set_minikube_env() {
  eval $(minikube docker-env)
}

# clear minikube docker environment
clear_minikube_env() {
  unset DOCKER_HOST
  unset DOCKER_API_VERSION
  unset DOCKER_TLS_VERIFY
  unset DOCKER_CERT_PATH
}

# delete k8s objects by type and pattern
delete_wait() {
  local obj=$1
  local pattern=$2
  local list=$(kubectl get $obj -a | awk "/$pattern/ {print \$1}")
  if [ ! -z "$list" ]; then
    kubectl delete $obj $list
    cnt_max=20
    cnt=0
    while [ $cnt -le $cnt_max ]; do
      if ! kubectl get $obj -a | grep $pattern ; then
        break
      fi
      cnt=$((cnt+1))
      sleep 1
    done
    if [ $cnt -ge $cnt_max ]; then
      echo "WARNING: not all $obj $pattern were deleted within $cnt_max sec"
    fi
  fi
}

set_minikube_env

# clean
kubectl delete job cpp-framework python-framework urb-exec
kubectl delete deployment,service urb-master
delete_wait jobs urb-exec
kubectl get pods -a
delete_wait pods urb-exec

rmi "local\/urb-service"
rmi "local\/urb-cpp-framework"
rmi "local\/urb-python-framework"
rmi "local\/urb-executor-runner"
rmi_none

# rebuild URB artifacts
clear_minikube_env
pushd urb-core/vagrant
SYNCED_FOLDER=../.. vagrant ssh -- "cd /scratch/urb; rm -rf source/python/build source/python/dist urb-core/dist urb-core/source/python/dist urb-core/source/python/build && make && make dist"
popd

# create docker images
set_minikube_env
make images

# start URB master
kubectl create -f source/urb-master.yaml
kubectl get pods


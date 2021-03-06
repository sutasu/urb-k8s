#/bin/bash

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
RET=0

# wait for framework run completion
framework_wait() {
  local fr=$1
  local pattern=$2
  local sec=$3
  local sl=2
  local max=$((sec/sl))
  local cnt=0
  local pod=$(kubectl get pods | awk "/$fr.*Running/ || /$fr.*Container/ || /$fr.*Pending/ {print \$1}")
  if [ -z "$pod" ]; then
    echo "Cannot get pod name for framework $fr"
    RET=1
    exit 1
  fi
  sleep 5
  echo "Starting to wait for framework $fr on pod $pod for $sec sec"
  while ! kubectl logs $pod | tail -1 | grep "$pattern" && [ $cnt -le $max ]; do
    let cnt=cnt+1
    sleep $sl
  done
  if [ $cnt -ge $max ]; then
    echo "ERROR: Timeout waiting for framework $fr completion"
    RET=1
  fi
}

urb_wait() {
  local max=10
  local cnt=0
  while ! kubectl get pods | grep "urb-master.*Running" && [ $cnt -le $max ]; do
    let cnt=cnt+1
    sleep 3
  done
  if [ $cnt -ge $max ]; then
    echo "ERROR: Timeout waiting for URB service pod to start"
    RET=1
  fi
  cnt=0
  local pod=$(kubectl get pods | awk "/urb-master.*Running/ {print \$1}")
  while ! kubectl logs $pod urb-service | grep 'Instantiating handler: MesosHandler'; do
    let cnt=cnt+1
    sleep 3
  done
  sleep 5
}

# create URB artifacts to be used in k8s persistent volume
prepare_urb_pv() {
  local root=/tmp/urb-k8s-volume/urb
  rm -rf $root
  mkdir -p $root/bin
  cp urb-core/dist/urb-*-linux-x86_64/bin/linux-x86_64/fetcher \
    urb-core/dist/urb-*-linux-x86_64/bin/linux-x86_64/command-executor \
    urb-core/dist/urb-*-linux-x86_64/bin/linux-x86_64/redis-cli \
    $root/bin
  mkdir -p $root/lib
  cp urb-core/dist/urb-*-linux-x86_64/lib/linux-x86_64/liburb* $root/lib
  cp -r urb-core/dist/urb-*/share $root
}

# create frameworks artifacts to be used in k8s persistent volume
prepare_example_pv() {
  local root=/tmp/urb-k8s-volume/example
  rm -rf $root
  mkdir -p $root/bin
  # add cpp test framework
  cp urb-core/dist/urb-*-linux-x86_64/share/examples/frameworks/linux-x86_64/example_*.test $root/bin
  # add python test framework
  #cp urb-core/dist/urb-*/share/examples/frameworks/python/*.py $root/bin
}

# clean k8s cluster
clean() {
  kubectl delete -f source/urb-master.yaml
  kubectl delete -f test/example-frameworks/cpp-framework.yaml
  kubectl delete -f test/example-frameworks/python-framework.yaml
  kubectl delete jobs $(kubectl get jobs -a|awk '/urb-exec/ {print $1}')
  kubectl delete pods $(kubectl get pods -a|awk '/urb-exec/ {print $1}')
  kubectl delete -f test/example-frameworks/pvc.yaml
  kubectl delete -f test/example-frameworks/pv.yaml
  kubectl delete -f test/urb-pvc.yaml
  kubectl delete -f test/urb-pv.yaml
}

# create URB persistent volume
create_urb_pv() {
  local mount_cmd="minikube mount --msize 1048576 /tmp/urb-k8s-volume/urb:/urb"
  pkill -f "$mount_cmd"
  $mount_cmd &
  mount_pid=$!

  kubectl create -f test/urb-pv.yaml
  kubectl create -f test/urb-pvc.yaml
}

# create example persistent volume
create_example_pv() {
  local mount_cmd="minikube mount --msize 1048576 /tmp/urb-k8s-volume/example:/example"
  pkill -f "$mount_cmd"
  $mount_cmd &
  mount_pid=$!

  kubectl create -f test/example-frameworks/pv.yaml
  kubectl create -f test/example-frameworks/pvc.yaml
}

configmap() {
  kubectl get configmap urb-config 2> /dev/null
  if [ $? -ne 0 ]; then
    kubectl create configmap urb-config --from-file=etc/urb.conf
  else
    kubectl create configmap urb-config --from-file=etc/urb.conf --dry-run -o yaml | kubectl replace -f -
  fi
}

prepare_urb_pv
prepare_example_pv
clean
create_urb_pv
create_example_pv

configmap
kubectl create -f source/urb-master.yaml
urb_wait
kubectl create -f test/example-frameworks/cpp-framework.yaml
#kubectl create -f test/example-frameworks/python-framework.yaml

#framework_wait python-framework "exiting with status 0" 60
framework_wait cpp-framework "example_framework: ~TestScheduler()" 60

#if [ ! -z "$mount_pid" ]; then
#  kill $mount_pid
#fi

exit $RET

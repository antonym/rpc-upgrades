#!/usr/bin/env bash

# Copyright 2018, Rackspace US, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -evu

export RPC_BRANCH=${RPC_BRANCH:-'r17.1.0'}
export OSA_SHA="stable/queens"

pushd /opt/rpc-openstack
  git clean -df
  git reset --hard HEAD
  rm -rf openstack-ansible
  rm -rf scripts/artifacts-building/
  git checkout ${RPC_BRANCH}
# checkout openstack-ansible-ops
popd

if [ ! -d "/opt/openstack-ansible" ]; then
  git clone --recursive https://github.com/openstack/openstack-ansible /opt/openstack-ansible
else
  pushd /opt/openstack-ansible
    git reset --hard HEAD
    git fetch --all
  popd
fi

if [ -f "/etc/openstack_deploy/user_secrets.yml" ]; then
  if ! grep "^osa_secrets_file_name" /etc/openstack_deploy/user_rpco_upgrade.yml; then
    echo 'osa_secrets_file_name: "user_secrets.yml"' >> /etc/openstack_deploy/user_rpco_upgrade.yml
  fi
elif [ -f "/etc/openstack_deploy/user_osa_secrets.yml" ]; then
  if ! grep "^osa_secrets_file_name" /etc/openstack_deploy/user_rpco_upgrade.yml; then
    echo 'osa_secrets_file_name: "user_osa_secrets.yml"' >> /etc/openstack_deploy/user_rpco_upgrade.yml
  fi
fi

pushd /opt/openstack-ansible
  git checkout ${OSA_SHA}

  # remove once https://review.openstack.org/#/c/604804/ merges
  sed -i '/- name: os_keystone/,+3d' /opt/openstack-ansible/ansible-role-requirements.yml
  cat <<EOF >> /opt/openstack-ansible/ansible-role-requirements.yml
- name: os_keystone
  scm: git
  src: https://github.com/antonym/openstack-ansible-os_keystone.git
  version: 2c735e1a1fecb50fe73a065437e572c82639a53d
EOF

  scripts/bootstrap-ansible.sh
  source /usr/local/bin/openstack-ansible.rc
  export TERM=linux
  export I_REALLY_KNOW_WHAT_I_AM_DOING=true
  echo "YES" | bash scripts/run-upgrade.sh
popd

# ensure inventory is cleaned up from old containers and reset ansible_facts cache
pushd /opt/rpc-upgrades/playbooks
  openstack-ansible cleanup-queens-inventory.yml
popd

#!/usr/bin/env bash
# Uncomment set command below for code debugging bash
#set -x

#################################################################################
# Copyright 2020 by F5 Networks, Inc.
#
#Licensed under the Apache License, Version 2.0 (the "License");
#you may not use this file except in compliance with the License.
#You may obtain a copy of the License at
#
#    http://www.apache.org/licenses/LICENSE-2.0
#
#Unless required by applicable law or agreed to in writing, software
#distributed under the License is distributed on an "AS IS" BASIS,
#WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#See the License for the specific language governing permissions and
#limitations under the License.
#################################################################################

# 07/30/2020: v1.0  r.jouhannet@f5.com    Initial version

# Usage:
#./f5_dcd_health_checks.sh [<BIG-IQ DCD sshuser>]

# Download the script with curl:
# curl https://raw.githubusercontent.com/f5devcentral/f5-big-iq-pm-team/master/f5-bigiq-dcd-health-checks/f5_dcd_health_checks.sh > f5_dcd_health_checks.sh

#################################################################################

bigiqsshuser="$1"
if [ -z "$bigiqsshuser" ]; then
  bigiqsshuser="root"
fi

PROG=${0##*/}
set -u

logname="f5data_$(date +"%m-%d-%Y_%H%M").log"
rm -f $logname > /dev/null 2>&1
exec 3>&1 1>>$logname 2>&1

echo -e "\n*** CHECK BIG-IQ DCD(s) Health" | tee /dev/fd/3
echo -e "********************************" | tee /dev/fd/3

dcdip=($(restcurl /shared/resolver/device-groups/cm-esmgmt-logging-group/devices | jq '.items[]|{log:.properties.isLoggingNode,add:.address}' -c | grep true | jq -r .add))

echo -e "DCD(s):"
echo -e "${dcdip[@]}\n"

arraylengthdcdip=${#dcdip[@]}

echo -e "Number of DCD(s): $arraylengthdcdip\n"

#################################################################################

if [[ $arraylengthdcdip -gt 0 ]]; then

  for (( i=0; i<${arraylengthdcdip}; i++ ));
  do
    echo -e "# BIG-IQ DCD ${dcdip[$i]} $bigiqsshuser password" | tee /dev/fd/3

ssh -o StrictHostKeyChecking=no $bigiqsshuser@${dcdip[$i]} <<'ENDSSH'
bash
curl -s localhost:9200/_cat/nodes?h=ip | while read ip ; do ping -s120 -ni 0.3 -c 5 $ip ; done 2>&1
curl -s localhost:9200/_cluster/health?pretty
curl -s localhost:9200/_cat/allocation?v
curl -s localhost:9200/_cat/nodes?v
curl -s localhost:9200/_cat/indices?v
curl -s localhost:9200/_cat/shards?v
curl -s localhost:9200/_cat/aliases?v
curl -s localhost:9200/_cat/tasks?v
curl -s localhost:9200/_all/_settings | jq .
ENDSSH

    echo
  done

fi

echo -e "\nBIG-IQ DCD cluster status:" | tee /dev/fd/3
cat $logname | grep -B 1 '"status"' | tee /dev/fd/3

echo -e "\nBIG-IQ DCD red indice(s) if any:" | tee /dev/fd/3
cat $logname | grep red | grep -v BIG-IQ | tee /dev/fd/3
c=$(cat $logname | grep red | grep -v BIG-IQ | wc -l)
if [[ $c  == 0 ]]; then
       echo -e "n/a" | tee /dev/fd/3
fi

echo -e "\nOutput located in $logname.\n" | tee /dev/fd/3
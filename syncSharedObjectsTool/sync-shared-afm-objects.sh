#!/bin/bash
# Uncomment set command below for code debugging bash
#set -x

#################################################################################
# Copyright 2019 by F5 Networks, Inc.
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

# 01/17/2019: v1.0  r.jouhannet@f5.com     Initial version

# Install the script under /shared/scripts in BIG-IQ 1.
# The script will be running on BIG-IQ 1 where the export is done.

RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

if [[ -z $1 || -z $2 || -z $3 ]]; then

    echo -e "\nThe script will:\n\t1. Create a AFM snapshot on BIG-IQ source\n \t2. Export from the snapshot port lists, address lists, rule lists, policies and policy rules\n \t3. Import in BIG-IQ target objects exported previously"
    echo -e "\n${RED}=> No Target BIG-IQ, login and password specified ('set-basic-auth on' on target BIG-IQ)${NC}\n\n"
    echo -e "Usage: ${BLUE}./sync-shared-afm-objects.sh 10.1.1.6 admin password${NC}\n"
    exit 1;

else

    bigiqIpTarget=$1
    bigiqAdminTarget=$2
    bigiqPasswordTarget=$3

    send_to_bigiq_target () {
        # parameter 1 is the URL, parameter 2 is the JSON payload
        # we remove the id at the end for the POST
        url=$(echo $1 | sed "s#http://localhost:8100#https://$bigiqIpTarget/mgmt#g" | cut -f1-$(IFS=/; set -f; set -- $1; echo $#) -d"/")
        if [[ $url == *"address-lists"* ]]; then
            # The Address-List must be configured via /mgmt/cm/adc-core/working-config/net/ip-address-lists
            url="https://$bigiqIpTarget/mgmt/cm/adc-core/working-config/net/ip-address-lists"
        fi
        json=$2
        method=$3
        if [[ $method == "PUT" ]]; then
            url=$(echo $1 | sed "s#http://localhost:8100#https://$bigiqIpTarget/mgmt#g")
        fi
        echo -e "\n\n====>>>${RED} $method ${NC}in${GREEN} $url ${NC}"
        curl -k -u "$bigiqAdminTarget:$bigiqPasswordTarget" -H "Content-Type: application/json" -X $method -d $json $url
        echo
    }

    snapshotName="snapshot-firewall-$(date +'%Y%H%M')"

    # Create the snapshot
    echo -e "\n- Create snapshot${RED} $snapshotName ${NC}"
    snapSelfLink=$(curl -s -H "Content-Type: application/json" -X POST -d "{'name':'$snapshotName'}" http://localhost:8100/cm/firewall/tasks/snapshot-config | jq '.selfLink')

    # Check Snapshot "currentStep": "DONE"
    snapSelfLink=$(echo $snapSelfLink | sed 's#https://localhost/mgmt#http://localhost:8100#g')
    snapSelfLink=${snapSelfLink:1:${#snapSelfLink}-2}
    snapCurrentStep=$(curl -s -H "Content-Type: application/json" -X GET $snapSelfLink | jq '.currentStep')
    while [ "$snapCurrentStep" != "DONE" ]
    do
        #echo $snapCurrentStep
        snapCurrentStep=$(curl -s -H "Content-Type: application/json" -X GET $snapSelfLink | jq '.currentStep')
        snapCurrentStep=${snapCurrentStep:1:${#snapCurrentStep}-2}
    done

    era=$(curl -s -H "Content-Type: application/json" -X GET $snapSelfLink | jq '.era')
    echo -e "\n- Snapshot${RED} $snapshotName ${NC}creation completed: era = ${RED} $era ${NC}"

    # Export policy
    policy=$(curl -s -H "Content-Type: application/json" -X GET http://localhost:8100/cm/firewall/working-config/policies?era=$era)
    echo $policy | jq .
    send_to_bigiq_target http://localhost:8100/cm/firewall/working-config/policies $policy PUT

    policyRuleslink=( $(curl -s -H "Content-Type: application/json" -X GET http://localhost:8100/cm/firewall/working-config/policies?era=$era | jq -r ".items[].rulesCollectionReference.link") )
    for plink in "${policyRuleslink[@]}"
    do
        echo -e "\n- policyRuleslink:${GREEN} $plink ${NC}"
        # Export policy rule
        plink=$(echo $plink | sed 's#https://localhost/mgmt#http://localhost:8100#g')
        policyRules=$(curl -s -H "Content-Type: application/json" -X GET $plink?era=$era)
        echo $policyRules | jq .
        send_to_bigiq_target $plink $policyRules PUT

        # Export port list destination
        portListlink=( $(curl -s -H "Content-Type: application/json" -X GET $plink?era=$era | jq -r ".items[].destination.portListReferences[].link") )
        for link in "${portListlink[@]}"
        do
            echo -e "\n\n\t- portListlink dest:${GREEN} $link ${NC}"
            # Export port list
            link=$(echo $link | sed 's#https://localhost/mgmt#http://localhost:8100#g')
            if [[ "$link" != "null" ]]; then
                portLists_d=$(curl -s -H "Content-Type: application/json" -X GET $link?era=$era)
                echo $portLists_d | jq .
                send_to_bigiq_target $link $portLists_d POST
            fi
        done

        # Export port list source
        portListlink=( $(curl -s -H "Content-Type: application/json" -X GET $plink?era=$era | jq -r ".items[].source.portListReferences[].link") )
        for link in "${portListlink[@]}"
        do
            echo -e "\n\n\t- portListlink src:${GREEN} $link ${NC}"
            # Export port list
            link=$(echo $link | sed 's#https://localhost/mgmt#http://localhost:8100#g')
            if [[ "$link" != "null" ]]; then
                portLists_s=$(curl -s -H "Content-Type: application/json" -X GET $link?era=$era)
                echo $portLists_s | jq .
                send_to_bigiq_target $link $portLists_s POST
            fi
        done

        # Export address list destination
        addressListlink=( $(curl -s -H "Content-Type: application/json" -X GET $plink?era=$era | jq -r ".items[].destination.addressListReferences[].link") )
        for link in "${addressListlink[@]}"
        do
            echo -e "\n\n\t- addressListlink dest:${GREEN} $link ${NC}"
            # Export address list
            link=$(echo $link | sed 's#https://localhost/mgmt#http://localhost:8100#g')
            if [[ "$link" != "null" ]]; then
                addressLists_d=$(curl -s -H "Content-Type: application/json" -X GET $link?era=$era)
                echo $addressLists_d | jq .
                send_to_bigiq_target $link $addressLists_d POST
            fi
        done

        # Export address list source
        addressListlink=( $(curl -s -H "Content-Type: application/json" -X GET $plink?era=$era | jq -r ".items[].source.addressListReferences[].link") )
        for link in "${addressListlink[@]}"
        do
            echo -e "\n\n\t- addressListlink src:${GREEN} $link ${NC}"
            # Export address list
            link=$(echo $link | sed 's#https://localhost/mgmt#http://localhost:8100#g')
            if [[ "$link" != "null" ]]; then
                addressLists_s=$(curl -s -H "Content-Type: application/json" -X GET $link?era=$era)
                echo $addressLists_s | jq .
                send_to_bigiq_target $link $addressLists_s POST
            fi
        done

        
        ruleListslink=( $(curl -s -H "Content-Type: application/json" -X GET $plink?era=$era | jq -r ".items[].ruleListReference.link") )
        for link in "${ruleListslink[@]}"
        do
            # Export rule list
            echo -e "\n\n\t- ruleListslink:${GREEN} $link ${NC}"
            link=$(echo $link | sed 's#https://localhost/mgmt#http://localhost:8100#g')
            if [[ "$link" != "null" ]]; then
                ruleLists=$(curl -s -H "Content-Type: application/json" -X GET $link?era=$era)
                echo $ruleLists | jq .
                send_to_bigiq_target $link $ruleLists POST
            fi

            # Export rules
            ruleslink=( $(curl -s -H "Content-Type: application/json" -X GET $link?era=$era | jq -r ".rulesCollectionReference.link") )
            for link2 in "${ruleslink[@]}"
            do
                echo -e "\n\n\t\t- ruleslink:${GREEN} $link2 ${NC}"
                link2=$(echo $link2 | sed 's#https://localhost/mgmt#http://localhost:8100#g')
                if [[ "$link2" != "null" ]]; then
                    rules=$(curl -s -H "Content-Type: application/json" -X GET $link2?era=$era)
                    echo $rules | jq .
                    send_to_bigiq_target $link2 $rules PUT
                fi
            done 
        done
    done

    # Delete the snapshot
    echo -e "\n- Delete snapshot${RED} $snapshotName ${NC}"
    curl -s -H "Content-Type: application/json" -X DELETE $snapSelfLink

    echo

    exit 0;
fi
#!/usr/bin/env bash

#/*******************************************************************************
# Copyright (c) 2012 IBM Corp.

# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at

#     http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#/*******************************************************************************

source $(echo $0 | sed -e "s/\(.*\/\)*.*/\1.\//g")/cb_common.sh

LOAD_PROFILE=$1
LOAD_LEVEL=$2
LOAD_DURATION=$3
LOAD_ID=$4
SLA_RUNTIME_TARGETS=$5

if [[ -z "$LOAD_PROFILE" || -z "$LOAD_LEVEL" || -z "$LOAD_DURATION" || -z "$LOAD_ID" ]]
then
    syslog_netcat "Usage: cb_netperf.sh <load profile> <load level> <load duration> <load_id>"
    exit 1
fi

LOAD_GENERATOR_IP=$(get_my_ai_attribute load_generator_ip)
LOAD_GENERATOR_TARGET_IP=$(get_my_ai_attribute load_generator_target_ip)

netperf=$(which netperf)

LOAD_PROFILE=$(echo ${LOAD_PROFILE} | tr '[:upper:]' '[:lower:]')

SEND_BUFFER_SIZE=$(get_my_ai_attribute_with_default send_buffer_size auto)
RECV_BUFFER_SIZE=$(get_my_ai_attribute_with_default recv_buffer_size auto)
CLIENT_BUFFER_SIZE=$(get_my_ai_attribute_with_default client_buffer_size auto)
SERVER_BUFFER_SIZE=$(get_my_ai_attribute_with_default server_buffer_size auto)
REQUEST_RESPONSE_SIZE=$(get_my_ai_attribute_with_default request_response_size auto)
IF_MTU=$(get_my_ai_attribute_with_default if_mtu auto)
EXTERNAL_TARGET=$(get_my_ai_attribute_with_default external_target none)
    
if [[ ${IF_MTU} != "auto" ]]
then
    sudo ifconfig $my_if mtu ${IF_MTU}
fi

declare -A CMDLINE_START

CMDLINE_START["tcp_stream"]="-t TCP_STREAM"
CMDLINE_START["tcp_maerts"]="-t TCP_MAERTS"
CMDLINE_START["udp_stream"]="-t UDP_STREAM"
CMDLINE_START["tcp_rr"]="-t TCP_RR"
CMDLINE_START["tcp_cc"]="-t TCP_CC"
CMDLINE_START["tcp_crr"]="-t TCP_CRR"
CMDLINE_START["udp_rr"]="-t UDP_RR"

if [[ $SEND_BUFFER_SIZE != "auto" || $RECV_BUFFER_SIZE != "auto" || $CLIENT_BUFFER_SIZE != "auto" || $SERVER_BUFFER_SIZE != "auto" || $REQUEST_RESPONSE_SIZE != auto ]]
then
    PROFILE_SPECIFIC="--"
else
    PROFILE_SPECIFIC=""    
fi

if [[ $(echo $LOAD_PROFILE | grep -c rr) -ne 0 ]]
then
    CMDLINE_END="-D 10 -H ${LOAD_GENERATOR_TARGET_IP} -l ${LOAD_DURATION} $PROFILE_SPECIFIC "

    if [[ $REQUEST_RESPONSE_SIZE != "auto" ]]
    then
        CMDLINE_END=$CMDLINE_END" -r "$REQUEST_RESPONSE_SIZE
    fi    
            
else
    CMDLINE_END="-D 10 -f m -H ${LOAD_GENERATOR_TARGET_IP} -l ${LOAD_DURATION} $PROFILE_SPECIFIC "
    
    if [[ $SEND_BUFFER_SIZE != "auto" ]]
    then
        CMDLINE_END=$CMDLINE_END" -s "$SEND_BUFFER_SIZE
    fi
    
    if [[ $RECV_BUFFER_SIZE != "auto" ]]
    then
        CMDLINE_END=$CMDLINE_END" -S "$RECV_BUFFER_SIZE
    fi            
fi

if [[ $CLIENT_BUFFER_SIZE != "auto" ]]
then
    CMDLINE_END=$CMDLINE_END" -s "$CLIENT_BUFFER_SIZE
fi            

if [[ $SERVER_BUFFER_SIZE != "auto" ]]
then
    CMDLINE_END=$CMDLINE_END" -S "$SERVER_BUFFER_SIZE
fi            

if [[ x"${CMDLINE_START[${LOAD_PROFILE}]}" == x ]]
then
    CMDLINE="$netperf ${CMDLINE_START["tcp_stream"]} $CMDLINE_END"
else 
    CMDLINE="$netperf ${CMDLINE_START[${LOAD_PROFILE}]} $CMDLINE_END"
fi

if [[ ${EXTERNAL_TARGET} != "none" ]]
then            
    LOAD_GENERATOR_TARGET_IP=${EXTERNAL_TARGET} 
fi

source ~/cb_barrier.sh start

syslog_netcat "Benchmarking netperf SUT: NET_CLIENT=${LOAD_GENERATOR_IP} -> NET_SERVER=${LOAD_GENERATOR_TARGET_IP} with LOAD_LEVEL=${LOAD_LEVEL} and LOAD_DURATION=${LOAD_DURATION} (LOAD_ID=${LOAD_ID} and LOAD_PROFILE=${LOAD_PROFILE})"

OUTPUT_FILE=$(mktemp)

execute_load_generator "${CMDLINE}" ${OUTPUT_FILE} ${LOAD_DURATION}

syslog_netcat "netperf run complete. Will collect and report the results"

if [[ $LOAD_PROFILE == "tcp_stream" || $LOAD_PROFILE == "tcp_maerts" ]]
then
    bw=$(tail -1 ${OUTPUT_FILE} | awk '{ print $5 }' | tr -d ' ')
elif [[ $LOAD_PROFILE == "udp_stream" ]]
then
    bw=$(tail -2 ${OUTPUT_FILE} | head -1 | awk '{ print $4 }' | tr -d ' ')
else
    tp=$(tail -2 ${OUTPUT_FILE} | head -1 | awk '{ print $6 }' | tr -d ' ')
fi

~/cb_report_app_metrics.py load_id:${LOAD_ID}:seqnum \
load_level:${LOAD_LEVEL}:load \
load_profile:${LOAD_PROFILE}:name \
load_duration:${LOAD_DURATION}:sec \
errors:$(update_app_errors):num \
completion_time:$(update_app_completiontime):sec \
datagen_time:$(update_app_datagentime):sec \
datagen_size:$(update_app_datagensize):records \
quiescent_time:$(update_app_quiescent):sec \
throughput:$tp:tps \
bandwidth:$bw:Mbps \
${SLA_RUNTIME_TARGETS}

rm ${OUTPUT_FILE}

exit 0
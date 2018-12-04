#!/bin/bash

# Set this to the folder where you have this script located.
HOME=
# Set this to the folder where jq is installed if it is not already
# part of your path.
PATH=${PATH}

SUB_MSG_FOLDER=${HOME}/subtxtmsg
# delete subscriber individual text message folder before each run.
if [ -d "${SUB_MSG_FOLDER}" ]; then
  rm -fr ${SUB_MSG_FOLDER}
fi

# Logging stuff
LOG_DATE_TIME=`date +"%Y%m%d_%H%M%S"`
PRETTY_DATE_TIME=`date +"%m/%d/%Y %H:%M"`
[[ -d ${HOME}/logs ]] || mkdir logs
LOG_FILE=${HOME}/logs/attdata.${LOG_DATE_TIME}.log

# Program Parameters
PROGRAM_PARAMS=${HOME}/parameters
[[ -d ${HOME}/data_report ]] || mkdir ${HOME}/data_report
EMAIL_OUTPUT_FILE=${HOME}/data_report/email_output_${LOG_DATE_TIME}

# These fields are defaults. Can be overwritten in the parameters file.
EMAIL=
SEND_TEXT_TO_SUB=N
SUB_ADDITIONAL_MSG=

log_writer()
{
        echo "$(date '+%m/%d/%Y %H:%M:%S:%N') - $1" | tee -a ${LOG_FILE}
}

email_output()
{
        echo "$1" >> ${EMAIL_OUTPUT_FILE}
}

send_email_notification()
{
        echo "$1" | mail -inN -s "AT&T Data Check" $2
}

send_mms_nofification()
{
        echo "$1" | mail -inN $2@mms.att.net
}

# Check to see if the required programs are installed.
command -v jq >/dev/null 2>&1 || { echo >&2 "jq is required for this script to work. Make sure it is installed and in your PATH. https://stedolan.github.io/jq"; exit 1; }
command -v bc >/dev/null 2>&1 || { echo >&2 "bc is required for this script to work. Make sure it is installed and in your PATH"; exit 1; }
command -v curl >/dev/null 2>&1 || { echo >&2 "curl is required for this script to work. Make sure it is installed and in your PATH"; exit 1; }
command -v tee >/dev/null 2>&1 || { echo >&2 "tee is required for this script to work. Make sure it is installed and in your PATH"; exit 1; }


if [ -f ${PROGRAM_PARAMS} ];
then
  source ${PROGRAM_PARAMS}
else
  echo "Missing the parameters file. One will be created for you. Make sure to edit this file before running again."

  echo "# Input your AT&T username" > ${PROGRAM_PARAMS}
  echo "USERNAME=" >> ${PROGRAM_PARAMS}
  echo "" >> ${PROGRAM_PARAMS}
  echo "# Input your AT&T password" >> ${PROGRAM_PARAMS}
  echo "PASSWORD=" >> ${PROGRAM_PARAMS}
  echo "" >> ${PROGRAM_PARAMS}
  echo "# Input your total data available in MB. ie. 20000 for 20 gigs." >> ${PROGRAM_PARAMS}
  echo "TOTALDATAAVAILABLE=" >> ${PROGRAM_PARAMS}
  echo "" >> ${PROGRAM_PARAMS}
  echo "# Change from \"N\" to \"Y\" if you want a sms message sent to each user on your plan" >> ${PROGRAM_PARAMS}
  echo "# of their data usage and sent sms messages." >> ${PROGRAM_PARAMS}
  echo "SEND_TEXT_TO_SUB=\"N\"" >> ${PROGRAM_PARAMS}
  echo "" >> ${PROGRAM_PARAMS}
  echo "# Email address if you want a summary of all data/text usage sent." >> ${PROGRAM_PARAMS}
  echo "EMAIL=" >> ${PROGRAM_PARAMS}
  echo "" >> ${PROGRAM_PARAMS}
  echo "# If you want to include an additional message in the sms sent to each use, you can put that here." >> ${PROGRAM_PARAMS}
  echo "SUB_ADDITIONAL_MSG=" >> ${PROGRAM_PARAMS}
  exit 1
fi

if [ -z ${USERNAME} ]
then
  echo "Make sure to input your AT&T username in the secrets file."
  exit 1
fi

if [ -z ${PASSWORD} ]
then
  echo "Make sure to input your AT&T password in the secrets file."
  exit 1
fi

if [ -z ${TOTALDATAAVAILABLE} ]
then
  echo "Make sure to input how much data you are allowed on your plan."
  exit 1
fi

log_writer "################################################################"
log_writer "#"
log_writer "# Starting AT&T Data Check Process"
log_writer "#"
log_writer "################################################################"

RUNTIME=`date +"%m/%d/%Y %T"`

# Check to see if the process is already running.
if [ -f ${HOME}/processing ]
then
  log_writer "Processing running already"
  RUNCOUNT=`sed -n '$=' ${HOME}/processing`
  if [ ${RUNCOUNT} -ge 3 ]
  then
    log_writer "Send email..."
    sendNotification "The AT&T Data Check process has been running for a while. Please check the process."
  fi
  echo ${RUNTIME} >> ${HOME}/processing
  exit 0
else
  echo ${RUNTIME} > ${HOME}/processing
fi

# cURL stuff
ACCEPT="Accept: application/json"
ACCEPT_ENCODING="Accept-Encoding: gzip, deflate, br"
ACCEPT_LANGUAGE="Accept-Language: en-US,en;q=0.9,de;q=0.8"
CACHE_CONTROL="Cache-Control: no-cache=set-cookie"
FORM_CONTENT_TYPE="Content-Type: application/x-www-form-urlencoded"
CONTENT_TYPE="Content-Type: application/json"
ORIGIN="Origin: https://www.att.com"
REFERER="Referer: https://www.att.com/my"
USER_AGENT="User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/70.0.3538.110 Safari/537.36"
XRB_MYATT="x-requested-by: MYATT"

LOGIN_JSON='{"CommonData":{"AppName":"R-MYATT"},"UserId":"'${USERNAME}'","Password":"'${PASSWORD}'","RememberMe":"Y"}'

log_writer "Logging into initial homepage to store required cookies."

curl -s -X POST -L 'https://www.att.com/myatt/lgn/resources/unauth/login/tguard/authenticateandlogin'\
  -H "HOST: www.att.com"\
  -H ''"${ORIGIN}"''\
  -H ''"${ACCEPT_ENCODING}"''\
  -H ''"${ACCEPT_LANGUAGE}"''\
  -H ''"${XRB_MYATT}"''\
  -H ''"$USER_AGENT"''\
  -H ''"${CONTENT_TYPE}"''\
  -H ''"${ACCEPT}"''\
  -H ''"${CACHE_CONTROL}"''\
  -H ''"${REFERER}"''\
  --data-binary $LOGIN_JSON\
  --cookie-jar att-cookies\
  -o authenticateandlogin

log_writer "Finished logging into initial homepage. Cookies saved."

LOGIN_DATA='userid='${USERNAME}'&password='${PASSWORD}'&lang=en&persist=Y&targetURL=https%3A%2F%2Fcprodx.att.com%2FTokenService%2FnxsATS%2FWATokenService%3FappID%3Dm14910%26returnURL%3Dhttps%253A%252F%252Fwww.att.com%252Folam%252FIdentitySuccessAction.olamexecute%253FisReferredFromRWD%253Dtrue&cancelURL=https%3A%2F%2Fwww.att.com%2Folam%2FloginAction.olamexecute&loginURL=https%3A%2F%2Fwww.att.com%2Folam%2FIdentityFailureAction.olamexecute&urlParameters=tGuardLoginActionEvent%3DLoginWidget_Login_Sub%26friendlyPageName%3DmyATT%20Login%20RWD%20Pg%26lgnSource%3Dolam&remember_me=Y&vhname=www.att.com&rootPath=%2Folam%2FEnglish&source=MYATT2FA&flow_ind=LGN&isSlidLogin=true&myATTIntercept=true'

log_writer "Running through second login page to store/update login cookies."

curl -s -L --url https://cprodmasx.att.com/commonLogin/igate_wam/multiLogin.do\
  -H ''"${ACCEPT_LANGUAGE}"''\
  -H ''"${FORM_CONTENT_TYPE}"''\
  -H "Accept: */*"\
  -H "Cache-Control: no-cache"\
  --data ''$LOGIN_DATA''\
  --cookie att-cookies\
  --cookie-jar att-cookies\
  -o multiLogin

log_writer "Finished second login page. Cookies saved/updated."

DATA_JSON='{"CommonData":{"AppName":"D-MYATT"},"ResourceRequestDetails":[{"URI":"auth/usage/unbilled/data/summary","Async":false,"SequenceNumber":0,"ResourceInput":{"CommonData":{"AppName":"D-MYATT","WirelessAccountData":[{"WirelessSubscriberData":[{"SubscriberNumber":"8173004236"}]}]}}}]}'

log_writer "Trying to get data statistics from AT&T."

curl -s -L --url https://www.att.com/myatt/com/resources/unauth/common/concurrent/resource/invoke\
  -H ''"${XRB_MYATT}"''\
  -H ''"${CONTENT_TYPE}"''\
  --data-binary ''$DATA_JSON''\
  --cookie att-cookies\
  --cookie-jar att-cookies\
  -o data-response

log_writer "Finished getting data statistics."

log_writer "Checking for errors."
RESPONSE_ERROR=`cat data-response | jq '.Result.Status'`
if [[ ! $RESPONSE_ERROR == "null" ]]
then
  log_writer "There was a response error from AT&T. Response : ${RESPONSE_ERROR}"
  log_writer ""
  rm -fr ${HOME}/processing
  exit 1
fi

log_writer "Parsing JSON data."
cat data-response | jq '.UnbilledDataSummaryResponse.GroupDataUsage.GroupSubscriberDataUsage[]' > data-usage

email_output "AT&T Data Usage ${PRETTY_DATE_TIME} "
BILLING_DAYS_LEFT=`cat data-response | jq '.UnbilledDataSummaryResponse.NoOfDaysLeft'`
BILLING_DAYS_LEFT=${BILLING_DAYS_LEFT//\"}

BILL_END_DATE=`cat data-response | jq '.UnbilledDataSummaryResponse.CurrentBillCycleEndDate'`
BILL_END_DATE=${BILL_END_DATE//\"}
BED_YEAR=`echo "${BILL_END_DATE}" | cut -c1-4`
BED_MONTH=`echo "${BILL_END_DATE}" | cut -c6-7`
BED_DAY=`echo "${BILL_END_DATE}" | cut -c9-10`
BILL_END_DATE=${BED_MONTH}/${BED_DAY}/${BED_YEAR}

BILL_START_DATE=`cat data-response | jq '.UnbilledDataSummaryResponse.CurrentBillCycleStartDate'`
BILL_START_DATE=${BILL_START_DATE//\"}
BST_YEAR=`echo "${BILL_START_DATE}" | cut -c1-4`
BST_MONTH=`echo "${BILL_START_DATE}" | cut -c6-7`
BST_DAY=`echo "${BILL_START_DATE}" | cut -c9-10`
BILL_START_DATE=${BST_MONTH}/${BST_DAY}/${BST_YEAR}

email_output ""
email_output " For Billing Cycle"
email_output "   Start Date : ${BILL_START_DATE}"
email_output "     End Date : ${BILL_END_DATE}"
SUB_PIPE_DATA=`cat data-usage | jq '. | [.FirstName, .WebUsage[].Used, .TextUsage[].Used, .SubscriberNumber] | join("|")'`
TOTAL_USED=0
while read -r line; do
  IFS='|' read -r -a array <<< "$line"
  email_output "${array[0]//\"} used ${array[1]} MB of data and sent ${array[2]//\"} sms messages."
  TOTAL_USED=`echo "$TOTAL_USED + ${array[1]}" | bc`
done <<< "${SUB_PIPE_DATA}"
email_output ""
email_output "Total Data Used : ${TOTAL_USED} MB"
email_output "Total Available : ${TOTALDATAAVAILABLE} MB"
TOTAL_LEFT=`echo "${TOTALDATAAVAILABLE} - ${TOTAL_USED}" | bc`
email_output "Total Left      : ${TOTAL_LEFT} MB"

# If EMAIL is populated, send message to it
if [ ! -z $EMAIL ]
then
  EMAIL_OUTPUT=`cat ${EMAIL_OUTPUT_FILE}`
  send_email_notification "$EMAIL_OUTPUT" "$EMAIL"
fi

# Create file for sending output to Subscriber
if [ "${SEND_TEXT_TO_SUB}" == "Y" ];then
  mkdir ${SUB_MSG_FOLDER}
  SUB_PIPE_DATA=`cat data-usage | jq '. | [.FirstName, .WebUsage[].Used, .TextUsage[].Used, .SubscriberNumber] | join("|")'`
  while read -r line; do
    IFS='|' read -r -a array <<< "$line"
    echo "You have used ${array[1]} MB of data with ${TOTAL_LEFT} MB available until ${BILL_END_DATE}. ${SUB_ADDITIONAL_MSG}" > ${SUB_MSG_FOLDER}/${array[3]//\"}
  done <<< "${SUB_PIPE_DATA}"

	# For every file in the subscriber text folder, send it to their phone via mms
  SUBMSG=`ls ${SUB_MSG_FOLDER}`
  for subphone in ${SUBMSG};do
    USER_MSG=`cat ${SUB_MSG_FOLDER}/$subphone`
    log_writer "Sending MMS to ${subphone} about their data usage"
    send_mms_nofification "$USER_MSG" ${subphone}
  done
fi

log_writer "Finished AT&T Data Usage process."

rm ${HOME}/att-cookies ${HOME}/authenticateandlogin ${HOME}/data-response ${HOME}/multiLogin ${HOME}/data-usage
rm -fr ${HOME}/processing

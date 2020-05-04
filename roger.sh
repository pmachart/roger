#!/usr/bin/env bash
#
#  Roger : CLI tool to accelerate front-end developer daily tasks.
#    Works great in a multiple project environment thanks to individual config files.
#    Opens merge requests, runs jenkins jobs, updates jira tickets.
#
#  Project home : https://github.com/pmachart/roger
#  Release under MIT License
#


##### Disable specific shellcheck rules and stating the reasons why :
# shellcheck disable=SC2046 disable=SC2086
#   "quote to remove word splitting" because sometimes it's the expected behaviour.
# shellcheck disable=SC1090
#   "Can't follow non-constant source" sourced files are config files in the user's home directory.
# shellcheck disable=SC2162
#   "read without -r will mangle backslashes" not relevant here
#####


# TODO : normalize exit and return codes
# TODO : if build successful, offer to update jira ticket
# TODO : get the list of contributors from the gitlab api (see line 23)


set_user_config() {
  ################## USER CONFIG ##################

  CONFIG_DIR="${HOME}/.config/roger"
  ALIAS_FILE="${HOME}/.bashrc"
  CLIPBOARD_CMD='xclip'
  DEBUG=0 # verbose debug output / += to not override environment variable

  ################### END USER CONFIG ##################
  ######## PLEASE UPDATE CONTRIBUTOR LIST BELOW ########
}

function get_assignee() { # associate contributor names with gitlab ids below for easy autocomplete
  for OPT in "${OPTS[@]}" ; do
    case ${OPT} in # to find your ID, look at your avatar image url on gitlab ¯\_(ツ)_/¯
      'dan')  ASSIGNEE='dsmthin' ; ASSIGNEE_ID='123' ;;
      'manu') ASSIGNEE='mwaddev' ; ASSIGNEE_ID='456' ;;
    esac
  done
}

display_help() {
cat << 'EOF'

  Roger : CLI tool to accelerate front-end developer daily tasks.
  Project home : https://github.com/pmachart/roger
  (See readme there for additional information)

--------------------------------------

  Usage:

    roger
      mr : creates a merge request
      jenkins : runs a jenkins build
      jira : updates the corresponding jira ticket
      roger : all of the above, in that order

      [branch name (default: current)] [target branch (default: MR_TARGET)] [assignee (default: self)]

      help
        (Displays this)

      install : adds alias in your ~/.bashrc
        You can change the alias name with the option `--alias=something`
      autocompletion
        (Sets up autocompletion for this script. Needs admin rights.)


  Dependencies:

    cURL: a command-line tool for getting or sending data including files using URL syntax.
      linux: sudo apt-get install curl
      macOs: brew install curl

    jq: a command-line JSON processor
      linux: sudo apt-get install jq
      macOs: brew install jq

EOF

exit 0
}

function require_dependencies() {
  local RET=0
  local MSG

  [[ -z $(command -v curl) ]] && { MSG+='\n    curl' ;  RET=11 ; }
  [[ -z $(command -v jq) ]]   && { MSG+='\n    jq' ;    RET=12 ; }

  ((RET)) && {
    echo -e "\\n  Missing dependency list:${MSG}\\n\\n  For more information, see 'dependencies' in '${SCRIPT_NAME} help'\\n\\n  Exiting.\\n"
    exit $(RETURNER ${RET})
  }
}

############# GENERAL CONFIGURATION #############

function init_conf() {
  mkdir -p ${CONFIG_DIR}
  echo -e "GITLAB_URL=''
    GITLAB_USER=''
    GITLAB_TOKEN=''

    JENKINS_URL=''
    JENKINS_USER='' # email
    JENKINS_TOKEN=''
    DEPLOY_DOMAIN=''

    JIRA_URL=''
    JIRA_USER='' # email
    JIRA_TOKEN=''

    SLACK_TOKEN='' # optional" \
    | sed 's/^[ ]*//' \
  > ${CONFIG_DIR}/config
}

function require_conf() {
  local RET=0

  if [[ -f ${CONFIG_DIR}/config ]] ; then
    local MSG
    source ${CONFIG_DIR}/config
    [[ -z ${GITLAB_URL} ]]    && { MSG+=' GITLAB_URL' ;    RET=21 ; }
    [[ -z ${GITLAB_USER} ]]   && { MSG+=' GITLAB_USER' ;   RET=21 ; }
    [[ -z ${GITLAB_TOKEN} ]]  && { MSG+=' GITLAB_TOKEN' ;  RET=21 ; }
    [[ -z ${JENKINS_URL} ]]   && { MSG+=' JENKINS_URL' ;   RET=22 ; }
    [[ -z ${JENKINS_USER} ]]  && { MSG+=' JENKINS_USER' ;  RET=22 ; }
    [[ -z ${JENKINS_TOKEN} ]] && { MSG+=' JENKINS_TOKEN' ; RET=22 ; }
    [[ -z ${DEPLOY_DOMAIN} ]] && { MSG+=' DEPLOY_DOMAIN' ; RET=22 ; }
    [[ -z ${JIRA_URL} ]]      && { MSG+=' JIRA_URL' ;      RET=23 ; }
    [[ -z ${JIRA_USER} ]]     && { MSG+=' JIRA_USER' ;     RET=23 ; }
    [[ -z ${JIRA_TOKEN} ]]    && { MSG+=' JIRA_TOKEN' ;    RET=23 ; }
  else
    echo -e "  Missing config file !
      Do you want to create and edit it now ?
      Please take the time to thoroughly review all fields.\\n"
    require_confirmation "This will open the config file in your default editor (${EDITOR})" || return $(RETURNER 20)
    init_conf
    eval ${EDITOR} ${CONFIG_DIR}/config
    RET=20
  fi

  ((RET)) && {
    echo "  Some required variables are unset : ${MSG}"
    require_confirmation "Edit config in your default editor (${EDITOR}) or exit ?" || exit $(RETURNER -e ${RET})
    eval ${EDITOR} ${CONFIG_DIR}/config
  }
}

############# PROJECT CONFIGURATION #############

function init_project_conf() {
  mkdir -p ${CONFIG_DIR}/projects
  echo -e "PROJECT_ID='' # from gitlab project homepage
    PROJECT_PREFIX='JIR' # if your jira tickets are called JIR-123
    DEFAULT_DEPLOY_ENV='preprod'
    PROTECTED_BRANCHES='' # branch names separated by spaces

    MR_TARGET='devel'
    MR_SLACK_CHANNEL='channel-name-without-leading-hashsign' # optional
    MR_SLACK_MESSAGE_PREFIX=':gitlab:' # optional (eg: slack emojis)
    MR_SLACK_MESSAGE_SUFFIX=':mergerequest:' # optional
    MR_WIP_PREFIX='WIP: ' # might depend on your gitlab integration
    MR_PEOPLE='foo bar baz' # used for auto-completion

    JENKINS_PROJECT=''
    JENKINS_SLACK_CHANNEL='channel-name-without-leading-hashsign' # optional
    JENKINS_SLACK_MESSAGE_PREFIX=':jenkins:' # optional
    JENKINS_SLACK_MESSAGE_SUFFIX=':heavy_check_mark:' # optional
    JENKINS_ENVIRONMENTS='preprod beta production' # used for auto-completion

    JIRA_FORM_FIELD='customfield_12345'" \
    | sed 's/^[ ]*//' \
  > ${CONFIG_DIR}/projects/${PROJECT_NAME}
}

function require_project_conf() {
  local RET=0

  if [[ -f ${CONFIG_DIR}/projects/${PROJECT_NAME} ]] ; then
    source ${CONFIG_DIR}/projects/${PROJECT_NAME}
    [[ -z ${PROJECT_ID} ]]            && { MSG+=' PROJECT_ID' ;            RET=31 ; }
    [[ -z ${PROJECT_PREFIX} ]]        && { MSG+=' PROJECT_PREFIX' ;        RET=31 ; }
    [[ -z ${DEFAULT_DEPLOY_ENV} ]]    && { MSG+=' DEFAULT_DEPLOY_ENV' ;    RET=31 ; }
    [[ -z ${PROTECTED_BRANCHES} ]]    && { MSG+=' PROTECTED_BRANCHES' ;    RET=31 ; }
    [[ -z ${MR_TARGET} ]]             && { MSG+=' MR_TARGET' ;             RET=31 ; }
    [[ -z ${JENKINS_PROJECT} ]]       && { MSG+=' JENKINS_PROJECT' ;       RET=32 ; }
    [[ -z ${JENKINS_ENVIRONMENTS} ]]  && { MSG+=' JENKINS_ENVIRONMENTS' ;  RET=32 ; }
    [[ -z ${JIRA_FORM_FIELD} ]]       && { MSG+=' JIRA_FORM_FIELD' ;       RET=33 ; }
  else
    echo -e "  Missing config file for this project !
      Do you want to create and edit it now ?
      Please take the time to thoroughly review all fields.
      Slack-related fields are optional.
      Config files are found here : ${CONFIG_DIR}\\n"
    require_confirmation "This will open the config file in your default editor (${EDITOR})" || return $(RETURNER 30)
    init_project_conf
    eval ${EDITOR} ${CONFIG_DIR}/projects/${PROJECT_NAME}
    return $(RETURNER 30)
  fi

  ((RET)) && {
    echo "  Some required variables are unset : ${MSG}"
    require_confirmation "Edit project config in your default editor (${EDITOR}) or exit ?" || exit $(RETURNER -e ${RET})
    eval ${EDITOR} ${CONFIG_DIR}/projects/${PROJECT_NAME}
  }
}

function require_remote_branch() {
  LOGGER -n 'Checking for remote branch...'

  local REMOTE='origin'
  local REMOTES
    REMOTES=$(git remote)

  [[ $(wc -w <<< "${REMOTES}") -gt 1 ]] && REMOTE='upstream'
  git ls-remote --exit-code --heads ${REMOTE} ${BRANCH}
  [[ ${?} -eq 2 ]] && { echo -e "There is no branch '${BRANCH}' on the remote '${REMOTE}'\\nExiting." ; exit 0 ; }

  LOGGER ' ok'
}
function require_confirmation() {
  local YN
  local MSGYES
  local MSGNO
  [[ -z ${2} ]] && MSGYES='Proceeding.' || MSGYES=${2}
  [[ -z ${3} ]] && MSGNO='Aborting.'    || MSGNO=${3}
  while true; do
    read -p "${1} (y/n) > " YN
    YN=$(echo "${YN}" | awk '{print tolower($0)}')
    case ${YN} in
      y|yes) echo "${MSGYES}";  return 0 ;;
      n|no)  echo "${MSGNO}";   return 2 ;;
      *) echo "Please answer with yes or no". ;;
    esac
  done
}

function hr() {
  printf '━%.0s' $(seq $(tput cols))
}

function LOGGER() {
  ((! DEBUG)) && return 0
  local OPT
  [[ ${1} == '--clear' ]] && { shift ; clear ; }
  [[ ${1} == '-h' ]] && { shift ; echo ; hr ; }
  [[ ${1} == '-n' ]] && { OPT='-n' ; }
  echo -e ${OPT} "${@}"
}

function RETURNER() { # everything returns 0 when not in debug mode.
  local THRESHOLD=80 # errorcode threshold to fail even when not in debug mode

  RET=${1}
  ((! DEBUG)) && [[ ${1} -lt ${THRESHOLD} ]] && RET=0

  return ${RET}
}


function POST_slack_msg() { # $CHANNEL $TEXT
  local -r CHANNEL=${1}
  shift
  curl -s \
    -X POST \
    -H "Authorization: Bearer ${SLACK_TOKEN}" \
    -H 'Content-type: application/json' \
    --data "{\"channel\": \"${CHANNEL}\", \"text\": \"${*}\", \"as_user\":true}" \
    https://slack.com/api/chat.postMessage \
  > /dev/null
}


##############################################################################################
##########################################  JIRA  ############################################
##############################################################################################

function PUT_jira_issue() {
  curl -s \
    -X PUT \
    -u ${JIRA_USER}:${JIRA_TOKEN} \
    -H 'Content-Type: application/json' \
    -d "{\"fields\":{\"${JIRA_FORM_FIELD}\":\"${DEPLOY_LINK}\"}}" \
    ${JIRA_URL}/rest/api/3/issue/${BRANCH}
}

##############################################################################################

function run_jira() {
  LOGGER -h '\n### JIRA ###\n'

  [[ ${JIRA_ISSUE_TITLE} == 'null' ]] && { echo 'No matching jira issue. Exiting.' ; return $(RETURNER 120) ; }

  if [[ $(PUT_jira_issue) ]] ; then
    echo 'Could not update Jira issue.'
    return $(RETURNER 113)
  else
    echo "Jira issue ${BRANCH} successfully updated with sandbox_url=${DEPLOY_LINK}"
  fi
}

##############################################################################################
########################################  JENKINS  ###########################################
##############################################################################################

function POST_jenkins_job() {
  curl -s \
    -X POST \
    -u ${JENKINS_USER}:${JENKINS_TOKEN} \
    --data-urlencode json="{ \
      \"parameter\": [
        { \"name\": \"version\", \"value\": \"${BRANCH}\" }, \
        { \"name\": \"deploy_message\", \"value\": \"${MSG}\" } \
      ] }" \
    ${JENKINS_URL}/job/${JOB}/build
}

function POST_lisa_jenkins_job() {
  local JENKINS_BASE_URL

  JENKINS_BASE_URL=$(echo "${BRANCH}" | awk '{print tolower($0)}')
  if [[ ${BRANCH} == master || ${BRANCH} =~ ^dev || ${BRANCH} =~ ^release ]] ; then
    JENKINS_BASE_URL=''
  fi

  curl -s \
    -X POST \
    -u ${JENKINS_USER}:${JENKINS_TOKEN} \
    --data-urlencode json="{ \
      \"parameter\": [
        { \"name\": \"PROJECT\", \"value\": \"${PROJECT_NAME}\" }, \
        { \"name\": \"BRANCH\", \"value\": \"${BRANCH}\" }, \
        { \"name\": \"BASE_URL\", \"value\": \"${JENKINS_BASE_URL}\" } \
      ] }" \
    ${JENKINS_URL}/job/${JOB}/build
}

function get_jenkins_build() {
  curl -s \
    -X POST \
    -u ${JENKINS_USER}:${JENKINS_TOKEN} \
    ${JENKINS_URL}/job/${JOB}/${BUILD_ID}/api/json
  # adding ?tree=actions,building might boost performance but sometimes doesn't work
}

##############################################################################################

function run_jenkins() {
  LOGGER -h '\n### JENKINS ###\n'
  local RET=0
  local AUTHOR
  local BUILD
  local BUILD_ID
  local IS_BUILDING
  local BUILD_RESULT=''
  local BUILD_RESULT_MSG
  local LAST_BUILD_ID
  local NOTIF_URGENCY='normal'
  local LAST_MERGES

  require_remote_branch

  ((IS_PROTECTED)) && LAST_MERGES=$(git log --pretty=format:"%ad\\ %s" --date=short | \grep "into 'develop'" | head -n 5 | awk '{print $4}' | tr -d \' | tr '\n' ' ')

  local JOB="deploy-${DEFAULT_DEPLOY_ENV}-${PROJECT_NAME}"
  local MSG="${JIRA_ISSUE_TITLE}"
  ((! IS_PROTECTED)) && MSG+=" (${JIRA_ISSUE_URL})"
  ((IS_PROTECTED)) && MSG="${LAST_MERGES}"
  local -r SLACK_MESSAGE="Successfully deployed \\'${BRANCH}\\' : ${JIRA_ISSUE_TITLE}"

  if [[ ${JENKINS_PROJECT} == single-page-app ]] ; then
    JOB="deploy-single-page-app"
    if [[ $(POST_lisa_jenkins_job) ]] ; then
      echo -e "\\nError:\\n Could not start job '${JOB}' for project '${PROJECT_NAME}' with branch '${BRANCH}'"
      return $(RETURNER 123)
    else
      echo -n "Launching Jenkins job (${JOB} for project ${PROJECT_NAME} with branch ${BRANCH})"
    fi
  else
    if [[ $(POST_jenkins_job) ]] ; then
      echo -e "\\nError:\\n Could not start job '${JOB}' for '${BRANCH}'"
      return $(RETURNER 124)
    else
      echo -n "Launching Jenkins job (${JOB} for branch ${BRANCH})"
    fi
  fi
  sleep 2 && echo -n .
  sleep 2 && echo -n .
  sleep 2 && echo -n .
  sleep 2 && echo -n .
  sleep 2 && echo -n .

  LAST_BUILD_ID=$(curl -s \
    -X GET \
    -u ${JENKINS_USER}:${JENKINS_TOKEN} \
    ${JENKINS_URL}/job/${JOB}/lastBuild/api/json?tree=number \
    | jq --raw-output '.number')
  LOGGER "Last build id on ${JOB} : ${LAST_BUILD_ID}"

  BUILD_ID=${LAST_BUILD_ID}
  ((BUILD_ID+=1)) # TODO refactor this
  while [[ "${AUTHOR}" != "${JENKINS_USER}" ]] ; do
    ((BUILD_ID-=1))
    BUILD=$(get_jenkins_build)

    AUTHOR=$(echo ${BUILD} | jq --raw-output '.actions[].causes[]?.userId? | select (.)')

    LOGGER "Build id : ${BUILD_ID}\\nAuthor : ${AUTHOR}"
  done

  LOGGER -h "Your last build is : ${BUILD_ID}"
  IS_BUILDING=$(echo ${BUILD} | jq -r '.building')

  if [[ ${IS_BUILDING} != 'true' ]] ; then
    echo 'Something went wrong. It seems this job is already built.'
    return $(RETURNER 133)
  else
    echo -n "Build under progress .."

    while [[ ${IS_BUILDING} == 'true' ]] ; do # while is building
      BUILD=$(get_jenkins_build)
      IS_BUILDING=$(echo ${BUILD} | jq -r '.building')

      sleep 2;
      echo -n .
    done
  fi

  BUILD_RESULT=$(echo ${BUILD} | jq -r '.result')
  BUILD_RESULT_MSG="Build result : ${BUILD_RESULT}"
  echo -e "\\n${BUILD_RESULT_MSG}"

  if [[ ${RESULT} == 'SUCCESS' && -n ${SLACK_TOKEN} && -n ${JENKINS_SLACK_CHANNEL} ]] ; then
    POST_slack_msg "${JENKINS_SLACK_CHANNEL}" "${JENKINS_SLACK_MESSAGE_PREFIX} ${BUILD_URL} ${JENKINS_SLACK_MESSAGE_SUFFIX} ${SLACK_MESSAGE}"
  else
    NOTIF_URGENCY='critical'
    RET=132
  fi

  notify-send -u ${NOTIF_URGENCY} ${BUILD_RESULT_MSG}

  return $(RETURNER ${RET})
}

##############################################################################################
##########################################  GITLAB  ##########################################
##############################################################################################

function POST_gitlab_mr() {
  curl -s \
    -X POST \
    -H "PRIVATE-TOKEN: ${GITLAB_TOKEN}" \
    -H 'Content-type: application/json' \
    --data "{\"target_project_id\": \"${PROJECT_ID}\",\
      \"source_branch\": \"${BRANCH}\",\
      \"target_branch\": \"${MR_TARGET}\",\
      \"title\": \"${MR_TITLE}\",\
      \"assignee\": \"${ASSIGNEE_ID}\",\
      \"remove_source_branch\": true,\
      \"squash\": true}" \
    ${GITLAB_URL}/api/v4/projects/${PROJECT_ID}/merge_requests \
    | jq -r '.web_url'
}

##############################################################################################

function run_mr() {
  LOGGER -h '\n### MR ###\n'

  require_remote_branch

  if ((IS_PROTECTED)) ; then
    echo -e '\n  ERROR:\n  Cannot create MR on a protected branch.'
    return $(RETURNER 44)
  fi

  local MR_TITLE="${BRANCH} ${JIRA_ISSUE_TITLE}"
  [[ ${JIRA_ISSUE_TITLE} == 'null' ]] && { MR_TITLE="${BRANCH} ${LAST_COMMIT_MESSAGE}" ; JIRA_ISSUE_TITLE='(No Jira issue provided)' ; }
  ((IS_WIP)) && MR_TITLE="${MR_WIP_PREFIX} ${MR_TITLE}"

  local ASSIGNEE
  local ASSIGNEE_ID='161'
  get_assignee ${OPTS}

  if [[ -z ${ASSIGNEE} ]] ; then
    require_confirmation "No assignee. Assign to yourself (${GITLAB_USER}) or exit ?" \
      && ASSIGNEE=${GITLAB_USER} \
      || return $(RETURNER 90)
  fi

  local MR_URL # don't declare and assign on the same line because 'local' always returns 0
  MR_URL=$(POST_gitlab_mr || return 88) || { echo -e '  Failed creating MR. Maybe it already exists ?\n\n  Exiting.' ; return $(RETURNER 88) ; }
  # if you prefer to use the `lab` cli client for gitlab:
  # you can use this hack to get the mr's url without stopping to type the mr's title, which is autogenerated anyway
  # but if you like being able to edit the title anyway, just remove `EDITOR="cat"`
  # MR_URL=$(EDITOR="cat" lab merge-request ${MR_OPTIONS} --base ${BRANCH} --target ${MR_TARGET} --message "${MR_TITLE}" -a ${ASSIGNEE} || return 88) || return 88

  ((! IS_WIP)) && [[ -n ${SLACK_TOKEN} && -n ${MR_SLACK_CHANNEL} ]] && POST_slack_msg "${MR_SLACK_CHANNEL}" "${MR_SLACK_MESSAGE_PREFIX} ${MR_URL} ${MR_SLACK_MESSAGE_SUFFIX} \`${BRANCH}\` ${JIRA_ISSUE_TITLE} [Last commit : _${LAST_COMMIT_MESSAGE}_]"
  echo "Merge request successfully opened : ${MR_URL}"

  [[ -n ${CLIPBOARD_CMD} && -n $(command -v ${CLIPBOARD_CMD}) ]] && echo "${MR_URL}" | ${CLIPBOARD_CMD} 1>/dev/null
}

############################################################################################
########################################## MAIN ############################################
############################################################################################

function roger() {
  [[ ${1} == 'help' ]] && display_help

  ((DEBUG)) && local ENV_DEBUG=1 # store environment variable

  local SCRIPT_NAME='roger'
  [[ -n ${ROGER_SCRIPT_NAME} ]] && SCRIPT_NAME=${ROGER_SCRIPT_NAME}

  [[ ! $(git rev-parse --show-toplevel 2>/dev/null) ]] \
    && echo -e '\n  ERROR:\n  You are not in a git repository.\n\n  Exiting.' \
    && return $(RETURNER 80)

  # Declare user config variables
  local DEBUG
  local CONFIG_DIR
  local CLIPBOARD_CMD
  set_user_config # initialize user config variables

  ((ENV_DEBUG)) && DEBUG=1 # override user config with environment variable

  # Declare general config variables
  local GITLAB_URL
  local GITLAB_USER
  local GITLAB_TOKEN
  local JENKINS_URL
  local JENKINS_USER
  local JENKINS_TOKEN
  local DEPLOY_DOMAIN
  local JIRA_URL
  local JIRA_USER
  local JIRA_TOKEN
  local SLACK_TOKEN
  require_conf # initialize general config variables

  local PROJECT_NAME
  PROJECT_NAME=$(basename ${PWD})

  # Declare  project config variables
  local PROJECT_ID
  local PROJECT_PREFIX
  local PROJECT_PREFIX_LC
  local DEFAULT_DEPLOY_ENV
  local PROTECTED_BRANCHES
  local MR_TARGET
  local MR_PEOPLE
  local MR_SLACK_CHANNEL
  local MR_SLACK_MESSAGE_PREFIX
  local MR_SLACK_MESSAGE_SUFFIX
  local JIRA_FORM_FIELD
  local JENKINS_PROJECT
  local JENKINS_SLACK_CHANNEL
  local JENKINS_SLACK_MESSAGE_PREFIX
  local JENKINS_SLACK_MESSAGE_SUFFIX
  require_project_conf # initialize project config variables

  PROJECT_PREFIX_LC=$(echo "${PROJECT_PREFIX}" | awk '{print tolower($0)}')

  require_dependencies

  local BRANCH
  BRANCH=$(git rev-parse --abbrev-ref HEAD)

  local ACTION_MR=0
  local ACTION_JENKINS=0
  local ACTION_JIRA=0
  local IS_WIP=0
  local OPTS
  local IS_PROTECTED=0


  while [[ ${#} != 0 ]] ; do
    case ${1} in
      'debug')   DEBUG=1 ;;

      'mr')      ACTION_MR=1 ;;
      'wip')     ACTION_MR=1 ; IS_WIP=1 ;;
      'jenkins') ACTION_JENKINS=1 ;;
      'jira')    ACTION_JIRA=1;;
      'roger')   ACTION_MR=1 ; ACTION_JENKINS=1 ; ACTION_JIRA=1 ;;

      'install')
        [[ ${2} =~ '--alias=' ]] && { SCRIPT_NAME=$(echo ${1} | cut --fields=2 --delimiter='=') ; shift ; }
        echo alias ${SCRIPT_NAME}=\"ROGER_SCRIPT_NAME=${SCRIPT_NAME} ${0}\" >> ${ALIAS_FILE}
        return 0
        ;;
      'uninstall')
        local SED_OPT='-i""'
        [[ ${OSTYPE} == 'macos' ]] && SED_OPT='-i ""'
        sed "${SED_OPT}" '/ROGER_SCRIPT_NAME/d' ${ALIAS_FILE}
        ;;
      'autocompletion')
        local COMPLETION="mr jira jenkins ${MR_PEOPLE} ${MR_TARGET} ${JENKINS_ENVIRONMENTS}"
        echo -e "complete -W \"${COMPLETION}\" ${SCRIPT_NAME}" > /etc/bash_completion.d/mr.autocompletion.sh \
          && echo -e '  Autocompletion successfully set !\n  Restart your terminal for this to take effect.' \
          && return 0
        echo '  Autocompletion could not be installed. Are you root ?'
        return $(RETURNER 82)
        ;;

      ${PROJECT_PREFIX}-* | ${PROJECT_PREFIX_LC}-*) BRANCH=${1} ;;
      [0-9]*) BRANCH="${PROJECT_PREFIX}-${1}" ;;

      *) OPTS+=${1} ;;
    esac
    shift
  done

  LOGGER --clear 'Running in debug mode.'

  if [[ -n ${PROTECTED_BRANCHES} ]] ; then
    [[ ${BRANCH} =~ ${PROTECTED_BRANCHES} ]] && IS_PROTECTED=1
  else
    [[ ${BRANCH} =~ ^(dev|master|release) ]] && IS_PROTECTED=1
  fi

  local -r JENKINS_SUBDOMAIN=$(echo "${BRANCH}" | awk '{print tolower($0)}' | tr -d '-')
  local -r DEPLOY_LINK="https://${JENKINS_SUBDOMAIN}.${PROJECT_NAME}.${DEFAULT_DEPLOY_ENV}.${DEPLOY_DOMAIN}"
  local -r LAST_COMMIT_MESSAGE=$(git log -1 --format=%s)

  local -r JIRA_ISSUE_URL="${JIRA_URL}/browse/${BRANCH}"
  local JIRA_ISSUE_TITLE
  JIRA_ISSUE_TITLE=$(curl -s \
    -X GET \
    -u ${JIRA_USER}:${JIRA_TOKEN} \
    -H "Content-Type: application/json" \
    ${JIRA_URL}/rest/api/3/issue/${BRANCH} \
    | jq --raw-output '.fields.summary' || return 87) || { LOGGER 'Getting Issue Title Failed' ; return $(RETURNER 87) ; }

  ((! ACTION_MR )) && ((! ACTION_JENKINS)) && ((! ACTION_JIRA)) && { ACTION_MR=1 ; ACTION_JENKINS=1 ; ACTION_JIRA=1 ; }

  ((ACTION_MR))      && { run_mr ${OPTS} || return ${?} ; }
  ((ACTION_JENKINS)) && { run_jenkins    || return ${?} ; }
  ((ACTION_JIRA))    && { run_jira       || return ${?} ; }
}

roger "${@}"

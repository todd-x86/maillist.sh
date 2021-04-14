#!/bin/bash

# maillist.sh
# A Mail List Manager written in Bash for MTAs

# Configuration directory
ml_cfg_dir="/etc/maillist"

function print_usage()
{
   echo "Usage: ${0} <action>"
   echo ""
   echo "Available actions:"
   echo "  help       - prints this message and exits"
   echo "  setup      - performs setup of Maillist"
   echo "  process    - processes a request from the MTA (message read from stdin)"
   echo "               (list name arg required)"
   echo "  check      - validates environment setup is correct"
}

function log()
{
   echo "$(date "+%Y-%m-%d %H:%M:%S") [${1}] ${@:2}"
   return 0
}

function send_message_to()
{
   local sender="${1}"
   local msg="${2}"

   local list_email="Mail List Server <${ml_reply}@${ml_domain}>"
   local response_file="$(mktemp -p "${ml_work_dir}")"
   
   echo "From: ${list_email}" >"${response_file}"
   echo "Reply-To: ${list_email}" >>"${response_file}"
   echo "To: ${sender}" >>"${response_file}"
   echo "Subject: Mail Server Error" >>"${response_file}"
   echo -e "\r\n\r\n${msg}\r\n${ml_signature}" >>"${response_file}"

   cat "${response_file}" | ${ml_sendmail} -t
   local sendmail_status=$?
   rm -f "${response_file}"

   return 0  #${sendmail_status}
}


function send_message()
{
   local msg="${1}"

   local sender=
   
   IFS=''
   while read line; do
      if [[ -z "${sender}" ]] && [[ "${line}" =~ ^From: ]]; then
         sender="${line:5}"
      fi
   done

   # Bad email, bad...
   [ -z "${sender}" ] && log error "couldn't find 'From' in message header" && return 1

   send_message_to "${sender}" "${msg}"
   return $?
}

function is_sender_rejected()
{
   local accept_anon="${1}"
   local sender="${2}"
   local sub_list="${3}"

   # Check if allowing anons to send e-mails
   [[ "${accept_anon}" == true ]] && return 1

   # Crappy way of extracting e-mail address in "From:" header
   local sender="$(echo "${sender}" | sed -e 's/^.*<\(.*\)>\s*$/\1/g' | tr '[:upper:]' '[:lower:]')"

   IFS=''
   while read line; do
      local sub_email="$(echo "${line}" | sed -e 's/^.*<\(.*\)>\s*$/\1/g' | tr '[:upper:]' '[:lower:]')"
      # Check user is in subscription list
      [[ "${sender}" == "${sub_email}" ]] && return 1
   done < "${sub_list}"

   # Rejected
   return 0
}

function process_message()
{
   local local_dir="${1}"
   local list_name="$(echo "${2}" | tr '$~/\\:' '-')"   # primitive safety to avoid possible security issues (yeah, this is big brain right here)

   # This shouldn't happen if you setup your MTA correctly, or maybe your MTA doesn't let you pass args
   [ -z "${list_name}" ] && log error "'process' command requires mail list name argument" && return 1

   local list_cfg_file="${ml_cfg_dir}/lists/${list_name}/list.cfg"
   local list_sub_file="${ml_cfg_dir}/lists/${list_name}/users.txt"
   ( [ ! -f "${list_cfg_file}" ] || [ ! -f "${list_sub_file}" ] ) \
	   && log warn "requested mailing list \"${list_name}\" does not exist" \
	   && send_message "The mailing list you've requested does not exist." && return 0

   # Load config file (if everything goes alright)
   source "${list_cfg_file}" || log error "failed to load config file \"${list_cfg_file}\""
   
   # Create temp files for processing messages
   local hdr_file="$(mktemp -p "${ml_work_dir}")"
   local msg_file="$(mktemp -p "${ml_work_dir}")"
   local response_file="$(mktemp -p "${ml_work_dir}")"
   
   local timestamp="$(date +%Y%m%d.%H%M%S.%N)"
   local raw_msg_file="${ml_work_dir}/msg.${timestamp:0:-3}.txt"
   local hdr=true
   local subject=
   local sender=
   local action=

   # Consume message passed by MTA
   IFS=''
   while read line; do
      echo "${line}" >>"${raw_msg_file}"

      # TODO: simplify this
      if [[ "${hdr}" == true ]] && [[ "${line}" == "" ]]; then
         hdr=false
      fi
      if [[ "${hdr}" == true ]]; then
         # Parse header segments - 'skip' handles multi-line headers
	 if [[ "${line}" =~ ^From: ]]; then
            # Track sender
	    sender="${line:5}"
         elif [[ "${line}" =~ ^Subject: ]]; then
            # Track subject
	    subject="${line:9}"
         fi

         # Track multi-line headers
	 if [[ "${line}" =~ ^[^\ ]*: ]]; then
            # Allow or skip
	    action="$(echo "${line}" | egrep -q '^(Content-Type|Importance|Date):' && echo "keep")"
         fi
         [[ "${action}" == "keep" ]] && echo "${line}" >>"${hdr_file}"
      else
        # Message body data
        echo "${line}" >>"${msg_file}"
      fi
   done

   # If sender isn't on list, reject them
   is_sender_rejected "${anonymous:-false}" "${sender}" "${list_sub_file}" \
	   && log warn "sender \"${sender}\" does not have permission to send messages to \"${list_name}\"" \
	   && send_message_to "${sender}" "You do not have permission to send messages to this mailing list.  Please contact the mail list administrator." \
	   && return 0

   # Compose e-mail for subscribers
   local list_email="${list_name}@${ml_domain}"
   local group_name="${name:-${list_name}}"
   local list_owner="${owner:-no-owner@${ml_domain}}"
   # Ignore if group name is already in subject
   if [[ ! "${subject}" =~ \[${group_name}\] ]]; then
      subject="[${group_name}] ${subject}"
   fi

   # Determine mailing rule 
   log info "dispatching email from \"${sender}\" to \"${list_name}\""
   if [[ "${mail_each}" != true ]]; then
      # Mail all in BCC
      local list_users="$(paste -sd, "${list_sub_file}")"
      if [[ "${rewrite_from}" == true ]]; then
         echo "From: ${list_email}" >"${response_file}"
      else
         echo "From: ${sender}" >"${response_file}"
      fi
      echo "Reply-To: ${list_email}" >>"${response_file}"
      echo "To: ${list_owner}" >>"${response_file}"
      echo "Bcc: ${list_users}" >>"${response_file}"
      echo "Subject: ${subject}" >>"${response_file}"
   
      cat "${hdr_file}" >>"${response_file}"
      rm -f "${hdr_file}"
      cat "${msg_file}" >>"${response_file}"
      rm -f "${msg_file}"

      # Send mail to all users BCC'd
      cat "${response_file}" | ${ml_sendmail} -t
      rm -f "${response_file}"
   else
      # Mail each individually
      IFS=''
      while read user_email; do
         if [[ "${rewrite_from}" == true ]]; then
            echo "From: ${list_email}" >"${response_file}"
         else
            echo "From: ${sender}" >"${response_file}"
         fi
         echo "Reply-To: ${list_email}" >>"${response_file}"
         echo "To: ${user_email}" >>"${response_file}"
         echo "Subject: ${subject}" >>"${response_file}"
   
         cat "${hdr_file}" >>"${response_file}"
         cat "${msg_file}" >>"${response_file}"

	 # Send mail to one user
         cat "${response_file}" | ${ml_sendmail} -t
      done < "${list_sub_file}"
      
      rm -f "${msg_file}"
      rm -f "${hdr_file}"
      rm -f "${response_file}"
   fi

   return 0
}

# Main entry point

local_dir="$(dirname "$(readlink -f "${BASH_SOURCE}")")"
action="${1}"

# Source main configuration file
source "${ml_cfg_dir}/maillist.cfg"

case "${action}" in
   help | "-h" | "--help")
     print_usage
     ;;
   check)
     ;;
   process)
     process_message "${local_dir}" "${@:2}" &>>"${ml_log_file}" || exit 1
     ;;
   setup)
     # Check working directory
     echo "[+] Setting up working directory (\"${ml_work_dir}\")"
     [ -d "${ml_work_dir}" ] || mkdir -p "${ml_work_dir}" || (echo "FATAL: cannot setup working directory" && exit 1) || exit 1
     echo "Setup complete."
     ;;
   *)
     echo "ERROR: invalid or no command specified" && exit 1
     ;;
esac

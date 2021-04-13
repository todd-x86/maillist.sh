#!/bin/bash

# maillist.sh
# A Mail List Manager written in Bash for MTAs

# Configuration
ml_cfg_dir="/etc/maillist"
ml_work_dir="/var/local/maillist"

mail_cmd="/usr/bin/mail"

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

function process_message()
{
   local local_dir="${1}"
   local list_name="${2}"

   local hdr_file="${local_dir}/hdr1.txt"
   local msg_file="${local_dir}/msg1.txt"
   local raw_msg_file="${local_dir}/raw_msg1.txt"
   local response_file="${local_dir}/response1.txt"
   local hdr=true
   local action=

   cat /dev/null >"${hdr_file}"
   cat /dev/null >"${msg_file}"
   cat /dev/null >"${response_file}"

   IFS=''
   while read line; do
      echo "${line}" >>"${raw_msg_file}"
      if [[ "${hdr}" == true ]] && [[ "${line}" == "" ]]; then
         hdr=false
      fi
      if [[ "${hdr}" == true ]]; then
         # Parse header segments - 'skip' handles multi-line headers
	 if [[ "${line}" =~ ^[^\ ]*: ]]; then
            # Allow or skip
	    action="$(echo "${line}" | egrep -q '^(Content-Type|Importance|Subject|Date):' && echo "keep")"
         fi
         if [[ "${action}" == "keep" ]]; then
            echo "${line}" >>"${hdr_file}"
         fi
      else
        echo "${line}" >>"${msg_file}"
      fi
   done

   local list_sub_file="users.txt"
   local list_email="list@list.appitizor.com"
   local list_owner="noreply@appitizor.com"

   local list_users="$(paste -sd, "${list_sub_file}")"
   
   echo "From: ${list_email}" >"${response_file}"
   echo "Reply-To: ${list_email}" >>"${response_file}"
   echo "To: ${list_owner}" >>"${response_file}"
   echo "Bcc: ${list_users}" >>"${response_file}"
   cat "${hdr_file}" >>"${response_file}"
   cat "${msg_file}" >>"${response_file}"

   cat "${response_file}" | /usr/sbin/sendmail -t

   return 0
}

local_dir="$(dirname "$(readlink -f "${BASH_SOURCE}")")"
action="${1}"

case "${action}" in
   help | "-h" | "--help")
     print_usage
     ;;
   check)
     ;;
   process)
     process_message "${local_dir}" "$@" || exit 1
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


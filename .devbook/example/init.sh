#!/usr/bin/env sh

# Set stop on error / enable debug
set -euo pipefail
DEVBOOK_VERBOSE="${DEVBOOK_VERBOSE:-}"
if [[ "$DEVBOOK_VERBOSE" == "1" ]]; then
  set -o verbose
fi

############################################################################
# INSTALL LUCIDITI CONFIG
############################################################################

##{{{#######################################################################
############################################################################
# FUNCTIONS
############################################################################

# Clean Upon Exit
cleanup() {
  # Exit safely for private config
  exit 0
}
if [[ "${BASH_SOURCE[0]}" = "$0" ]]; then
  trap cleanup EXIT
fi

# Print a string line wrapped in "===" headers
printline() {
  printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' =
  printf "%s\n" "$1"
  printf '%*s\n' "${COLUMNS:-$(tput cols)}" '' | tr ' ' =
}

#  Logging functions
readonly LOG_FILE="/tmp/$(basename "$0").log"
info()    { echo "[INFO]    $*" | tee -a "$LOG_FILE" >&2 ; }
warning() { echo "[WARNING] $*" | tee -a "$LOG_FILE" >&2 ; }
error()   { echo "[ERROR]   $*" | tee -a "$LOG_FILE" >&2 ; }
fatal()   { echo "[FATAL]   $*" | tee -a "$LOG_FILE" >&2 ; exit 1 ; }

# Accept Message & Error Code
quit() {
  if [[ -z $1 ]]; then MESSAGE="An error has occurred"; else MESSAGE=$1; fi
  if [[ -z $2 ]]; then ERROR_CODE=1; else ERROR_CODE=$2; fi
  echo "$MESSAGE" 1>&2; exit "$ERROR_CODE";
}

# Retrieve an Ansible var in playbook.
ansible_var() {
  if [[ ! -z "$1" ]]; then
    VAR="$1"
    echo $(ansible-playbook main.yml -i inventory --tags "get-var" --extra-vars "var_name=$VAR" | grep "$VAR" | sed -e 's/[[:space:]]*"\([^"]*\)"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\2/g' | sed -e "s/\"$VAR\": null//g" | sed -e "s/VARIABLE IS NOT DEFINED!//g" )
  fi
}

# Retrieve optional --tags param
devbook_do_tags() {
  if [[ -f "$DEVBOOK_LIST_FILE" ]]; then
    TAGS=$(paste -sd "," - < "$DEVBOOK_LIST_FILE")
    echo "--tags $TAGS"
  else
    echo ""
  fi
}

# Retrieve the list of skipped and/or finished tags.
devbook_skip_tags() {
  if [[ -f "$DEVBOOK_TAG_FILE" && ! -f "$DEVBOOK_SKIP_FILE" ]]; then
    sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/,/g' "$DEVBOOK_TAG_FILE"
  elif [[ ! -f "$DEVBOOK_TAG_FILE" && -f "$DEVBOOK_SKIP_FILE" ]]; then
    sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/,/g' "$DEVBOOK_SKIP_FILE"
  elif [[ -f "$DEVBOOK_TAG_FILE" && -f "$DEVBOOK_SKIP_FILE" ]]; then
    MERGE=$(mktemp)
    cat "$DEVBOOK_TAG_FILE" "$DEVBOOK_SKIP_FILE" > "$MERGE"
    sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/,/g' "$MERGE"
    rm "$MERGE"
  fi
}

# Get verbosity
devbook_verbosity() {
  if [[ "$DEVBOOK_VERBOSE" == "1" ]]; then
    echo "-vvv"
  else
    echo ""
  fi
}

############################################################################
# VARS
############################################################################
# Output colors.
C_HIL="\033[36m"
C_WAR="\033[33m"
C_SUC="\033[32m"
C_ERR="\033[31m"
C_RES="\033[0m"

ANSIBLE_SUDO="-K"
DEVBOOK_NOTES="NOTES.md"
DEVBOOK_LIST_FILE=".devbook.list"
DEVBOOK_TAG_FILE=".devbook.tags"
DEVBOOK_SKIP_FILE=".devbook.skip"
SCRIPTS_DIRECTORY="$(dirname $0)"

##}}}#######################################################################

#/ Usage: $SCRIPT [CONFIG_URL]
#/
#/   <CONFIG_URL>: An HTTP URL containing a config.yml to use.
#/ Examples:
#/ Options:
#/   --help: Display this help message
SCRIPT=$(basename "$0")
usage() { grep '^#/' "$0" | cut -c4- | sed -e 's/\$SCRIPT/'"$SCRIPT"'/g' ; exit 0 ; }
expr "$*" : ".*--help" > /dev/null && usage

############################################################################
# MAIN
############################################################################

# Handle options
# Add options x: - required arg
while getopts 'fh' FLAG; do
  case "${FLAG}" in
    h) usage; exit 1 ;;
    f)
      ANSIBLE_SUDO=""
      DEVBOOK_EXT_OPTS="-f"
      shift $((OPTIND -1))
      ;;
    *) : ;;
  esac
done
VERBOSE_OPT=$(devbook_verbosity)

# Add Ansible requirements...
if [[ -f "requirements.yml" ]]; then
  echo ""
  echo "${C_HIL}Installing Luciditi Requirements...${C_RES}"
  ansible-galaxy install $VERBOSE_OPT -r requirements.yml
fi


# Start Ansible playbook
if [[ -f "main.yml" ]]; then
  echo ""
  echo "${C_HIL}Installing example config...${C_RES}"
  SKIP_TAGS=$(devbook_skip_tags)
  LIST_TAGS=$(devbook_do_tags)
  ansible-playbook main.yml $VERBOSE_OPT -i inventory $ANSIBLE_SUDO --skip-tags "$SKIP_TAGS" $LIST_TAGS
fi


# Cleanup
echo ""
if [[ -f "$DEVBOOK_TAG_FILE" ]]; then
  echo "${C_HIL}Cleanup...${C_RES}"
  rm "$DEVBOOK_TAG_FILE"
fi


# Notes
if [[ -f "$DEVBOOK_NOTES" ]]; then
  if [[ -x $(command -v "$HOME/.bin/vcat") ]]; then
    "$HOME/.bin/vcat" "$DEVBOOK_NOTES"
  else
    cat "$DEVBOOK_NOTES"
  fi
fi

exit 0

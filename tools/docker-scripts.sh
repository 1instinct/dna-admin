#!/bin/bash
#A variable
VAR="VAR inside the script"
# print INFO message to stdout
# Argument: 
#    $1: INFO message to print
log_info() {
    local MSG="$1"
    printf "%s - [INFO] %s\n" "$(date)" "$MSG"
}

# print ERROR message to stderr
# Argument: 
#    $1: ERROR message to print
log_error() {
    local MSG="$1"
    printf "%s - [ERROR] %s\n" "$(date)" "$MSG" >&2
}

reload_db() {
  printf "%s - %s\n" "$(date)" "Reloading DB"
  docker-compose exec web rails db:schema:load db:migrate &&\
  docker-compose exec -e ADMIN_EMAIL=spree@example.com -e ADMIN_PASSWORD=spree123 web rails db:seed &&\
  docker-compose exec web rails spree_sample:load &&\
  docker-compose restart
}

case "$1" in
    "") ;;
    log_info) "$@"; exit;;
    log_error) "$@"; exit;;
    reload_db) "$@"; exit;;
    *) log_error "Unkown function: $1()"; exit 2;;
esac
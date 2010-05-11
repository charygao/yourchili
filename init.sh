#!/bin/bash

. ./library/redcloud.sh


HOSTNAME="cori-celesti.org"
DB_PASSWORD="password"
NGINX_USER="www-data"
NGINX_GROUP="www-data"


upgrade_system
better_bash_prompt 1
set_hostname "$HOSTNAME"
set_open_ports 22 80 443 25 110 587
add_user "eric" "password" "1"


mysql_install "$DB_PASSWORD"
mysql_tune


nginx_install "$NGINX_USER" "$NGINX_GROUP" "1" "1"
nginx_delete_site default
nginx_create_site "www.salamander-linux.com" "www.salamander-linux.com salamander-linux.com www.salamanderlinux.com salamanderlinux.com" 0 "" "1"
nginx_create_site "www.thisisnotmyfacebook.com" "www.thisisnotmyfacebook.com thisisnotmyfacebook.com" 0 "" "1"
nginx_ensite "www.salamander-linux.com"
nginx_ensite "www.thisisnotmyfacebook.com"



#create_svn_project "$DB_PASSWORD" "miner" "1" "admin" "password" "super" "user" "superuser@mydomain.com"
#enable_svn_project_for_vhost "www.salamander-linux.com" "miner" "1" "0"

#create_git_project "$DB_PASSWORD" "miner" "1" "admin" "password" "super" "user" "superuser@mydomain.com" "1"
#enable_git_project_for_vhost "www.salamander-linux.com" "miner" "0" "0"

create_redmine_project "$DB_PASSWORD" "miner" "miner" "1" "git" "Miner" "admin" "password" "super" "user" "superuser@mydomain.com" "1"

create_redmine_project "$DB_PASSWORD" "miner2" "miner2" "1" "svn" "Miner2" "admin" "password" "super" "user" "superuser@mydomain.com" "1"

enable_git_project_for_vhost "www.salamander-linux.com" "miner"  "miner" "0" "0" "0"
enable_svn_project_for_vhost "www.salamander-linux.com" "miner2" "1" "0"








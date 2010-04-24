#!/bin/bash


export LIBEVENT_VER=1.4.13-stable
export PHP_FPM_VER=0.6
export PHP_VER=5.3.2
export SUHOSIN_PATCH_VER=0.9.9.1
export SUHOSIN_VER=0.9.29
#PHP-FPM for specific PHP versions are no longer, so using the latest applicable which seems to work fine (read: I use it in production)
export PHP_VER_IND=5.3.1

export RUBY_PREFIX="/usr/local/ruby"

export NGINX_VER=0.7.65
export NGINX_PREFIX="/srv/www"
export NGINX_SBIN_PATH="/usr/local/sbin/nginx"
export NGINX_CONF_PATH="/etc/nginx"
export NGINX_PID_PATH="/var/run/nginx.pid"
export NGINX_ERROR_LOG_PATH="/srv/www/nginx_logs/error.log"
export NGINX_HTTP_LOG_PATH="/srv/www/nginx_logs"
export LOGRO_FREQ="monthly"
export LOGRO_ROTA="12"



###########################################################
# misc. functions
###########################################################



function add_user
{
	USER="$1"
	PASS="$2"
	ADMIN="$3"


	if [ "$ADMIN" = "1" ] ; then
		aptitude -y install sudo
		admin_exists=$(grep "^admin:" /etc/group)
		if [ -z "$admin_exists" ] ; then
			groupadd admin
			chmod 777 /etc/sudoers
			cat /etc/sudoers | grep -v admin > /etc/sudoers.tmp
			echo "%admin ALL=(ALL) ALL" >>/etc/sudoers.tmp
			mv /etc/sudoers.tmp /etc/sudoers
			chmod 0440 /etc/sudoers
		fi
		useradd "$USER" -m -s /bin/bash -G admin >/dev/null 2>&1
	else
		useradd "$USER" -m -s /bin/bash >/dev/null 2>&1
	fi
	printf "$PASS\n$PASS\n" | passwd "$USER" >/dev/null 2>&1
}

function setup_backup_cronjob
{
	curr_dir=$(pwd)
	cat /etc/crontab | grep -v "&&.*do_backup.sh" > /etc/crontab.tmp
	echo '3  23	* * *   root	cd '$curr_dir' && ./do_backup.sh' >>/etc/crontab.tmp
	mv /etc/crontab.tmp /etc/crontab
	restart cron
}




###########################################################
# upgrade functions
###########################################################


better_bash_prompt()
{
	USE_DETAILED=$1


	for bashfile in /root/.bashrc /etc/skel/.bashrc ; do
		already_added=$(cat $bashfile | egrep "^root.*egrep")
		if [ -z "$already_added" ] ; then
			cat <<'EOF' >>$bashfile

color_red='\[\033[01;31m\]'
color_orange='\[\033[00;33m\]'
color_green='\[\033[00;32m\]'
color_blue='\[\033[01;34m\]'
color_purple='\[\033[01;35m\]'
color_cyan='\[\033[01;36m\]'
color_white='\[\033[01;37m\]'
color_default='\[\033[00m\]'

root=$(groups | egrep "root")
admin=$(groups | egrep "wheel|admin")
color_user=$color_green
if [ -n "$root" ] ; then
	color_user=$color_red
elif [ -n "$admin" ] ; then
	color_user=$color_orange
fi

########################################################################
# VCS part mostly shamelessly ripped off from acdha's bash prompt:     #
# http://github.com/acdha/unix_tools/blob/master/etc/bash_profile      #
########################################################################

# Utility function so we can test for things like .git/.hg without firing
# up a separate process
__has_parent_dir()
{
	test -d "$1" && return 0;
	current="."
	while [ !"$current" -ef "$current/.." ] ; do
		if [ -d "$current/$1" ]; then 
			return 0 
		fi
		current="$current/.."
	done
	return 1;
}
__vcs_prompt_part()
{
	name=""
	if [ -d .svn ] ; then 
 		name="svn" ; 
	elif [ -d RCS ] ; then 
		echo "RCS" ; 
	elif __has_parent_dir ".git" ; then
		local git_branch=$(git symbolic-ref HEAD 2>/dev/null)
		if [ -n "$git_branch" ] ; then
			name="git $git_branch" ;
		fi	
	elif __has_parent_dir ".hg" ; then
		local hg_branch=$(hg branch 2>/dev/null)
		if [ -n "$hg_branch" ] ; then
			name="hg $hg_branch"
		fi
	else
		name=""
	fi
	if [ -n "$name" ] ; then
		echo -e '-(\033[01;35m'$name'\033[01;37m)' #purple
	else
		echo ""
	fi
}




detailed='${debian_chroot:+($debian_chroot)}'$color_default'\n('$color_user'\u@\h'$color_default')-('$color_cyan'\d \@'$color_default')$(__vcs_prompt_part)\n'$color_default'('$color_blue'\w'$color_default')\$ '
short='${debian_chroot:+($debian_chroot)}'$color_user'\u@\h'$color_default':'$color_blue'\w'$color_default'$ '

PS1=$short

EOF
		fi
	
	
		if [ "$USE_DETAILED" = "1" ] ; then
			sed -i -e 's/^PS1=\$short[\t ]*$/PS1=$detailed/' $bashfile 
		fi


		sed -i -e "s/^#alias ll='ls -l'/alias ll='ls -al'/" $bashfile # enable ll list long alias <3
	done

}


function better_stuff
{
	aptitude -y install unzip wget vim less imagemagick sudo
	better_bash_prompt
}

function upgrade_system
{
	cat /etc/apt/sources.list | sed 's/^#*deb/deb/g' >/tmp/new_src_list.tmp
	mv /tmp/new_src_list.tmp /etc/apt/sources.list
	aptitude update
	aptitude -y full-upgrade #only sissies use safe-upgrade. ARE YOU A SISSY?
	
	better_stuff
}


###########################################################
# mysql-server
###########################################################

function mysql_install {
	# $1 - the mysql root password

	if [ ! -n "$1" ]; then
		echo "mysql_install() requires the root pass as its first argument"
		return 1;
	fi

	echo "mysql-server-5.1 mysql-server/root_password password $1" | debconf-set-selections
	echo "mysql-server-5.1 mysql-server/root_password_again password $1" | debconf-set-selections
	apt-get -y install mysql-server mysql-client libmysqld-dev libmysqlclient-dev

	echo "Sleeping while MySQL starts up for the first time..."
	sleep 5
}

function mysql_tune {
	# Tunes MySQL's memory usage to utilize the percentage of memory you specify, defaulting to 40%

	# $1 - the percent of system memory to allocate towards MySQL

	if [ ! -n "$1" ];
		then PERCENT=30
		else PERCENT="$1"
	fi

	sed -i -e 's/^#skip-innodb/skip-innodb/' /etc/mysql/my.cnf # disable innodb - saves about 100M

	MEM=$(awk '/MemTotal/ {print int($2/1024)}' /proc/meminfo) # how much memory in MB this system has
	MYMEM=$((MEM*PERCENT/100)) # how much memory we'd like to tune mysql with
	MYMEMCHUNKS=$((MYMEM/4)) # how many 4MB chunks we have to play with

	# mysql config options we want to set to the percentages in the second list, respectively
	OPTLIST=(key_buffer sort_buffer_size read_buffer_size read_rnd_buffer_size myisam_sort_buffer_size query_cache_size)
	DISTLIST=(75 1 1 1 5 15)

	for opt in ${OPTLIST[@]}; do
		sed -i -e "/\[mysqld\]/,/\[.*\]/s/^$opt/#$opt/" /etc/mysql/my.cnf
	done

	for i in ${!OPTLIST[*]}; do
		val=$(echo | awk "{print int((${DISTLIST[$i]} * $MYMEMCHUNKS/100))*4}")
		if [ $val -lt 4 ]
			then val=4
		fi
		config="${config}\n${OPTLIST[$i]} = ${val}M"
	done

	sed -i -e "s/\(\[mysqld\]\)/\1\n$config\n/" /etc/mysql/my.cnf

	/etc/init.d/mysql restart
}

function mysql_create_database {
	# $1 - the mysql root password
	# $2 - the db name to create

	if [ ! -n "$1" ]; then
		echo "mysql_create_database() requires the root pass as its first argument"
		return 1;
	fi
	if [ ! -n "$2" ]; then
		echo "mysql_create_database() requires the name of the database as the second argument"
		return 1;
	fi

	echo "CREATE DATABASE $2;" | mysql -u root -p$1
}

function mysql_create_user {
	# $1 - the mysql root password
	# $2 - the user to create
	# $3 - their password
	

	if [ ! -n "$1" ]; then
		echo "mysql_create_user() requires the root pass as its first argument"
		return 1;
	fi
	if [ ! -n "$2" ]; then
		echo "mysql_create_user() requires username as the second argument"
		return 1;
	fi
	if [ ! -n "$3" ]; then
		echo "mysql_create_user() requires a password as the third argument"
		return 1;
	fi

	echo "CREATE USER '$2'@'localhost' IDENTIFIED BY '$3';" | mysql -u root -p$1
}

function mysql_grant_user {
	# $1 - the mysql root password
	# $2 - the user to bestow privileges 
	# $3 - the database

	if [ ! -n "$1" ]; then
		echo "mysql_grant_user() requires the root pass as its first argument"
		return 1;
	fi
	if [ ! -n "$2" ]; then
		echo "mysql_grant_user() requires username as the second argument"
		return 1;
	fi
	if [ ! -n "$3" ]; then
		echo "mysql_grant_user() requires a database as the third argument"
		return 1;
	fi

	echo "GRANT ALL PRIVILEGES ON $3.* TO '$2'@'localhost';" | mysql -u root -p$1
	echo "FLUSH PRIVILEGES;" | mysql -u root -p$1

}

function backup_mysql
{
	if [ ! -n "$1" ]; then
		echo "backup_mysql() requires the database user as its first argument"
		return 1;
	fi
	if [ ! -n "$2" ]; then
		echo "backup_mysql) requires the database password as its second argument"
		return 1;
	fi
	if [ ! -n "$3" ]; then
		echo "backup_mysql() requires the output file path as its third argument"
		return 1;
	fi
	USER="$1"
	PASS="$2"
	BACKUP_DIR="$3"
	DBNAMES="$4"


	fname=""
	if [ -n "$DBNAMES" ] ; then
		fname=$(echo "$DBNAMES" | sed 's/ /_/g')
		mysqldump --single-transaction --add-drop-table --add-drop-database -h localhost --user="$USER" --password="$PASS" --databases $DBNAMES > "/tmp/$fname-db.sql"
		

	else
		fname="all"
		mysqldump --single-transaction --add-drop-table --add-drop-database -h localhost --user="$USER" --password="$PASS" --all-databases  > "/tmp/$fname-db.sql"
	fi

	mkdir -p "$BACKUP_DIR"

	curdir=$(pwd)
	cd /tmp
	rm -rf "$BACKUP_DIR/$fname-db.tar.bz2"
	tar cjf	"$BACKUP_DIR/$fname-db.tar.bz2" "$fname-db.sql"
	rm -rf "$fname-db.sql"
	cd "$curdir"

}


function restore_mysql
{
	if [ ! -n "$1" ]; then
		echo "restore_mysql() requires the database user as its first argument"
		return 1;
	fi
	if [ ! -n "$2" ]; then
		echo "restore_mysql) requires the database password as its second argument"
		return 1;
	fi
	if [ ! -n "$3" ]; then
		echo "restore_mysql() requires the backup directory as its third argument"
		return 1;
	fi
	
	USER="$1"
	DB_PASSWORD="$2"
	BACKUP_DIR="$3"



	rm -rf "/tmp/tmp.db" "/tmp/tmp.db.all.sql"
	mkdir "/tmp/tmp.db"
	
	db_zips=$(ls "$BACKUP_DIR/"*-db.tar.bz2)
	for dbz in $db_zips ; do
		tar -C "/tmp/tmp.db" -xjf "$dbz"
		cat /tmp/tmp.db/* >> "/tmp/tmp.db.all.sql"
		rm -rf /tmp/tmp.db/*
	done

	#ensure that current user (usually root) and debian-sys-maint have same password as before, and that they still have all permissions
	old_debian_pw=$(echo $(cat /etc/mysql/debian.cnf | grep password | sed 's/^.*=[\t ]*//g') | awk ' { print $1 } ')
	echo "USE mysql ;"                                                                            >> "/tmp/tmp.db.all.sql"
	echo "GRANT ALL ON *.* TO 'debian-sys-maint'@'localhost' ;"                                   >> "/tmp/tmp.db.all.sql"
	echo "GRANT ALL ON *.* TO '$USER'@'localhost' ;"                                              >> "/tmp/tmp.db.all.sql"
	echo "UPDATE user SET password=PASSWORD(\"$old_debian_pw\") WHERE User='debian-sys-maint' ;"  >> "/tmp/tmp.db.all.sql"
	echo "UPDATE user SET password=PASSWORD(\"$DB_PASSWORD\") WHERE User='$USER' ;"               >> "/tmp/tmp.db.all.sql"
	echo "FLUSH PRIVILEGES ;"                                                                     >> "/tmp/tmp.db.all.sql"


	mysql --user="$USER" --password="$DB_PASSWORD" < "/tmp/tmp.db.all.sql"
	rm -rf "/tmp/tmp.db" "/tmp/tmp.db.all.sql"


	touch /tmp/restart-mysql
	
}


#################################
#	PHP-FPM			#
#################################


function nginx_php-fpm
{
	#check for versions of: libevent; php-fpm; php; suhosin; suhosin patch.
	#the naming conventions php-fpm have changed at random in the past. be careful.
	#
	# http://monkey.org/~provos/libevent/
	# http://launchpad.net/php-fpm/
	# http://php.net/
	# http://www.hardened-php.net/suhosin/download.html
	#
	#and alter variables as necessary

	curdir=$(pwd)
	
	#dependencies for all the crap to be included with php
	aptitude install -y libcurl4-openssl-dev libjpeg62-dev libpng12-dev libxpm-dev libfreetype6-dev libt1-dev libmcrypt-dev libxslt1-dev libbz2-dev libxml2-dev

	#not php specific deps
	aptitude install -y wget build-essential autoconf

	#create directory to play in
	mkdir /tmp/phpcrap
	cd /tmp/phpcrap

	#need stable libevent.
	wget "http://www.monkey.org/~provos/libevent-$LIBEVENT_VER.tar.gz"
	tar -xzvf "libevent-$LIBEVENT_VER.tar.gz"
	cd "libevent-$LIBEVENT_VER"
	./configure
	make
	DESTDIR=$PWD make install
	export LIBEVENT_SEARCH_PATH="$PWD/usr/local"

	#don't want to build in libevent directory
	cd ../

	#grab php.
	wget "http://us.php.net/get/php-$PHP_VER.tar.bz2/from/us.php.net/mirror"
	tar -xjvf "php-$PHP_VER.tar.bz2"

	#grab suhosin.
	wget "http://download.suhosin.org/suhosin-patch-$PHP_VER-$SUHOSIN_PATCH_VER.patch.gz"
	gunzip "suhosin-patch-$PHP_VER-$SUHOSIN_PATCH_VER.patch.gz"

	#patch php with suhosin.
	cd "php-$PHP_VER"
	patch -p 1 -i "../suhosin-patch-$PHP_VER-$SUHOSIN_PATCH_VER.patch"

	#build php
	mkdir php-build
	cd php-build
	../configure --with-config-file-path=/usr/local/lib/php --with-curl --enable-exif --with-gd --with-jpeg-dir --with-png-dir --with-zlib --with-xpm-dir --with-freetype-dir --with-t1lib --with-mcrypt --with-mhash --with-mysql=mysqlnd --with-mysqli=mysqlnd --with-pdo-mysql=mysqlnd --with-mysql-sock=/var/run/mysqld/mysqld.sock --with-openssl --enable-sysvmsg --enable-wddx --with-xsl --enable-zip --with-bz2 --enable-bcmath --enable-calendar --enable-ftp --enable-mbstring --enable-soap --enable-sockets --enable-sqlite-utf8 --with-gettext --enable-shmop --with-xmlrpc
	make

	#grab php-fpm and build
	wget "http://launchpad.net/php-fpm/master/$PHP_FPM_VER/+download/php-fpm-$PHP_FPM_VER~$PHP_VER_IND.tar.gz"
	tar -xzvf "php-fpm-$PHP_FPM_VER~$PHP_VER_IND.tar.gz"
	cd "php-fpm-$PHP_FPM_VER-$PHP_VER_IND"
	mkdir fpm-build
	cd fpm-build
	../configure --srcdir=../ --with-php-src="../../../" --with-php-build="../../" --with-libevent="$LIBEVENT_SEARCH_PATH" --with-fpm-bin=/usr/local/sbin/php-fpm  --with-fpm-init=/etc/init.d/php-fpm --with-fpm-user="$NGINX_USER" --with-fpm-group="$NGINX_GROUP"
	make

	#install php
	cd ../../
	make install

	#move php.ini to where php-fpm looks for it
	cp "/tmp/phpcrap/php-$PHP_VER/php.ini-production" /usr/local/lib/php/php.ini

	#set permissions
	chmod 644 /usr/local/lib/php/php.ini

	#install php-fpm
	cd "php-fpm-$PHP_FPM_VER-$PHP_VER_IND"
	cd fpm-build
	make install

	#grab and install suhosin extension.
	cd ../../../../
	wget "http://download.suhosin.org/suhosin-$SUHOSIN_VER.tgz"
	tar -xzvf "suhosin-$SUHOSIN_VER.tgz"
	cd "suhosin-$SUHOSIN_VER"
	/usr/local/bin/phpize
	./configure
	make
	make install

	#make php use it.
	echo "extension = suhosin.so" >> /usr/local/lib/php/php.ini

	#have /etc/init.d/php-fpm run on boot
	update-rc.d php-fpm defaults

	#/etc/php-fpm.conf stuff
	#sockets > ports. Using the 127.0.0.1:9000 stuff needlessly introduces TCP/IP overhead.
	sed -i 's/<value\ name="listen_address">127.0.0.1:9000<\/value>/<value\ name="listen_address">\/var\/run\/php-fpm.sock<\/value>/' /etc/php-fpm.conf
	
	#nice strict permissions
	sed -i 's/<value\ name="mode">0666<\/value>/<value\ name="mode">0600<\/value>/' /etc/php-fpm.conf
	
	#matches available processors. Will not make a 360 melt.
	sed -i 's/<value\ name="max_children">5<\/value>/<value\ name="max_children">4<\/value>/' /etc/php-fpm.conf
	
	#i like to know when scripts are slow.
	sed -i 's/<value\ name="request_slowlog_timeout">0s<\/value>/<value name="request_slowlog_timeout">2s<\/value>/' /etc/php-fpm.conf

	#edited to include PHP path
	sed -i 's/<value\ name="PATH">\/usr\/local\/bin:\/usr\/bin:\/bin<\/value>/<value\ name="PATH">\/usr\/local\/bin:\/usr\/bin:\/bin:\/usr\/local\/sbin<\/value>/' /etc/php-fpm.conf

	#Engage.
        /etc/init.d/php-fpm start

	cd "$curdir"

	#remove build crap
	rm -rf /tmp/phpcrap

}

function nginx_ruby
{
	curdir=$(pwd)
	
	ruby_ee_source_url=$(echo $(wget -O-  http://www.rubyenterpriseedition.com/download.html 2>/dev/null ) | egrep -o 'href="[^\"]*\.tar\.gz' | sed 's/^href="//g')
	mkdir /tmp/ruby
	cd /tmp/ruby

	aptitude install -y build-essential zlib1g-dev libssl-dev libreadline5-dev
	wget "$ruby_ee_source_url"
	tar xvzf *.tar.gz
	rm -rf *.tar.gz
	cd ruby*
	./installer --auto "$RUBY_PREFIX"

	for ex in erb gem irb rackup rails rake rdoc ri ruby ; do
		ln -s "$RUBY_PREFIX/bin/$ex" "/usr/bin/$ex"
	done

	gem install mysql
	gem install rails

	cd "$curdir"
	rm -rf /tmp/ruby
}

#################################
#	nginx			#
#################################

function nginx_create_site
{
	server_id="$1"
	server_name_list="$2"
	is_ssl="$3"
	rails_paths="$4"
	enable_php="$5"

	port="80"
	ssl_cert=""
	ssl_ckey=""
	if [ "$is_ssl" = "1" ] ; then
		port="443 default ssl";
		ssl_cert="ssl_certificate      $NGINX_CONF_PATH/ssl/nginx.pem;"
		ssl_ckey="ssl_certificate_key  $NGINX_CONF_PATH/ssl/nginx.key;"
		if [ ! -e "$NGINX_CONF_PATH/ssl/nginx.pem" ] || [ ! -e "$NGINX_CONF_PATH/ssl/nginx.key"  ] ; then
			aptitude -y install ssl-cert
			mkdir -p "$NGINX_CONF_PATH/ssl"
			make-ssl-cert generate-default-snakeoil --force-overwrite
			cp /etc/ssl/certs/ssl-cert-snakeoil.pem    "$NGINX_CONF_PATH/ssl/nginx.pem"
			cp /etc/ssl/private/ssl-cert-snakeoil.key  "$NGINX_CONF_PATH/ssl/nginx.key"
		fi
	fi

	config_path="$NGINX_CONF_PATH/sites-available/$server_id"
	cat << EOF >"$config_path"
server
{
	listen               $port;
	server_name          $server_name_list;
	access_log           $NGINX_PREFIX/$server_id/logs/access.log;
	root                 $NGINX_PREFIX/$server_id/public_html;
	index                index.html index.htm index.php index.cgi;
	$ssl_cert
	$ssl_ckey

	#rails
EOF


	if [ -z "$rails_paths" ] ; then
		cat << EOF >>"$config_path"
	#passenger_enabled   on;
	#passenger_base_uri  rails_app; ##should be symlink to public dir of actual rails_app location
EOF
	else
		echo '	passenger_enabled   on;' >>"$config_path"
		if [ "$rails_paths" != '.' ] ; then
			for rp in $rails_paths ; do
				echo "	passenger_base_uri  $rp; " >> "$config_path"
			done
		fi	
	fi

	if [ "$php_enabled" != '0' ] ; then
		cat << EOF >>"$config_path"

	#php
	location ~ \.php\$
	{
		fastcgi_pass   unix:/var/run/php-fpm.sock ;
		include        $NGINX_CONF_PATH/fastcgi_params;
	}
EOF
	fi

	echo "}" >> "$config_path"
	

	mkdir -p "$NGINX_PREFIX/$server_id/public_html"
	mkdir -p "$NGINX_PREFIX/$server_id/logs"
	cat << EOF >"$NGINX_PREFIX/$server_id/public_html/index.html"
<html>
	<head>
		<title>Nothing To See Here</title>
	</head>
	<body style="background:#FFBBBB;">
		<center>
			<p>Nginx is running on $server_id</p>
			<p>Please disregard the pink <a href="http://xkcd.com/636/">brontosaurus</a>.</p>
			<p>Move along, nothing to see here...</p>
		</center>
	</body>
</html>
EOF
	chown -R www-data:www-data "$NGINX_PREFIX/$server_id"

}
function nginx_ensite
{
	server_id="$1"
	ln -s "$NGINX_CONF_PATH/sites-available/$server_id" "$NGINX_CONF_PATH/sites-enabled/$server_id" 
	/etc/init.d/nginx restart
}
function nginx_dissite
{
	rm -rf "$NGINX_CONF_PATH/sites-enabled/$server_id"
	/etc/init.d/nginx restart
}
function nginx_delete_site
{
	server_id="$1"
	rm -rf "$NGINX_CONF_PATH/sites-enabled/$server_id"
	rm -rf "$NGINX_CONF_PATH/sites-available/$server_id"
	rm -rf "$NGINX_PREFIX/$server_id"
	/etc/init.d/nginx restart
}

function nginx_install
{
	curdir=$(pwd)

	#theres a couple dependencies.
	aptitude install -y libpcre3-dev libcurl4-openssl-dev libssl-dev

	#not nginx specific deps
	aptitude install -y wget build-essential

	#need dpkg-dev for no headaches when apt-get source nginx
	aptitude install -y dpkg-dev

	#directory to play in
	mkdir /tmp/nginx
	cd /tmp/nginx

	#grab and extract
	wget "http://nginx.org/download/nginx-$NGINX_VER.tar.gz"
	tar -xzvf "nginx-$NGINX_VER.tar.gz"

	#Oh?  So you think it's Apache?  I wonder why those exploits you're tyring aren't working.... BUWHAHAHAHAH!
	cat "nginx-$NGINX_VER/src/http/ngx_http_header_filter_module.c" | sed 's/\"Server: nginx\"/\"Server: Apache\"/g' > /tmp/ngx_h1.tmp
	cat /tmp/ngx_h1.tmp | sed 's/\"Server: \".*NGINX_VER/\"Server: Apache\/2.2.3\"/g' > "nginx-$NGINX_VER/src/http/ngx_http_header_filter_module.c"


	#maek eet
	cd "nginx-$NGINX_VER"

	#adjust as you please
	passenger_root=`$RUBY_PREFIX/bin/passenger-config --root`
	passenger_path="$passenger_root/ext/nginx"
	nginx_conf_file="$NGINX_CONF_PATH/nginx.conf"
	nginx_http_log_file="$NGINX_HTTP_LOG_PATH/access.log"
	./configure --prefix="$NGINX_PREFIX" --sbin-path="$NGINX_SBIN_PATH" --conf-path="$nginx_conf_file" --pid-path="$NGINX_PID_PATH" --error-log-path="$NGINX_ERROR_LOG_PATH" --http-log-path="$nginx_http_log_file" --user="$NGINX_USER" --group="$NGINX_GROUP" --with-http_ssl_module --with-debug --add-module="$passenger_path"
	make
	make install

	#grab source for ready-made scripts
	apt-get source nginx
	
	#alter init to match sbin path specified in configure. add to init.d
	sed -i "s@DAEMON=/usr/sbin/nginx@DAEMON=$NGINX_SBIN_PATH@" nginx-*/debian/init.d
	cp nginx-*/debian/init.d /etc/init.d/nginx
	chmod 744 /etc/init.d/nginx
	update-rc.d nginx defaults

	#use provided logrotate file. adjust as you please
	sed -i "s/daily/$LOGRO_FREQ/" nginx-*/debian/nginx.logrotate
	sed -i "s/52/$LOGRO_ROTA/" nginx-*/debian/nginx.logrotate
	cp nginx*/debian/nginx.logrotate /etc/logrotate.d/nginx



	#setup default nginx config files
	echo "fastcgi_param  SCRIPT_FILENAME   \$document_root\$fastcgi_script_name;" >> "$NGINX_CONF_PATH/fastcgi_params";
	cat <<EOF >$NGINX_CONF_PATH/nginx.conf

worker_processes 4;

events
{
	worker_connections 1024;
}
http
{
	include             mime.types;
	default_type        application/octet-stream;

	server_names_hash_max_size       4096;
	server_names_hash_bucket_size    4096;

	passenger_root                   $passenger_root;
	passenger_max_pool_size          1;
	passenger_pool_idle_time         1;
	passenger_max_instances_per_app  1;
		
	
	keepalive_timeout   65;
	sendfile            on;

	#gzip               on;
	#tcp_nopush         on;
	
	include $NGINX_CONF_PATH/sites-enabled/*;
}
EOF


	mkdir -p "$NGINX_CONF_PATH/sites-enabled"
	mkdir -p "$NGINX_CONF_PATH/sites-available"

	#create default site & start nginx
	nginx_create_site "default" "default" "0" "" "1"
	nginx_ensite      "default"
	

	#delete build directory
	rm -rf /tmp/nginx

	chown -R www-data:www-data /srv/www


	#return to original directory
	cd "$curdir"
}



#TRAC & SVN via apache
function apache_install {

	if [ -z "$1" ] ; then
		echo "First argument of apache_install must be default apache port"
		return 1
	fi
	PORT=$1
	SSL_PORT=443

	if [ -n "$2" ] ; then
		SSL_PORT=$2
	fi


	# installs the system default apache2 MPM
	aptitude -y install apache2

	a2dissite default # disable the interfering default virtualhost

	cat << EOF >/etc/apache2/ports.conf

NameVirtualHost *:$PORT
Listen          $PORT

<Ifmodule mod_ssl.c>
	Listen  $SSL_PORT
</IfModule>
EOF

}

function apache_tune {
	# Tunes Apache's memory to use the percentage of RAM you specify, defaulting to 40%

	# $1 - the percent of system memory to allocate towards Apache

	if [ ! -n "$1" ]; then 
		PERCENT=10
	else 
		PERCENT="$1"
	fi

	#Install & Configure MPM-prefork
	aptitude -y install apache2-mpm-prefork
	PERPROCMEM=32   # the amount of memory in MB each apache process is likely to utilize, assume apache processes will explode in size like they always do
	MAXREQUESTS=100 # number of sessions served before apache process is refreshed, 0 for unlimited
	MEM=$(grep MemTotal /proc/meminfo | awk '{ print int($2/1024) }') # how much memory in MB this system has
	MAXCLIENTS=$(( 1+(MEM*PERCENT/100/PERPROCMEM) )) # calculate MaxClients
	MAXCLIENTS=${MAXCLIENTS/.*} # cast to an integer
	sed -i -e "s/\(^[ \t]*StartServers[ \t]*\)[0-9]*/\1$MAXCLIENTS/" /etc/apache2/apache2.conf
	sed -i -e "s/\(^[ \t]*MinSpareServers[ \t]*\)[0-9]*/\11/" /etc/apache2/apache2.conf
	sed -i -e "s/\(^[ \t]*MaxSpareServers[ \t]*\)[0-9]*/\1$MAXCLIENTS/" /etc/apache2/apache2.conf
	sed -i -e "s/\(^[ \t]*MaxClients[ \t]*\)[0-9]*/\1$MAXCLIENTS/" /etc/apache2/apache2.conf
	sed -i -e "s/\(^[ \t]*MaxRequestsPerChild[ \t]*\)[0-9]*/\1$MAXREQUESTS/" /etc/apache2/apache2.conf

	#turn off KeepAlive
	sed -i -e "s/\(^[ \t]*KeepAlive[ \t]*\)On/\1Off/" /etc/apache2/apache2.conf
	/etc/init.d/apache2 restart >/dev/null 2>&1
}

function install_svn_deps
{
	#install apache
	apache_install "8080" "443"
	apache_tune 
	aptitude -y install ssl-cert wget subversion subversion-tools libapache2-svn libapache-dbi-perl libapache2-mod-perl2 libdbd-mysql-perl libdigest-sha1-perl libapache2-mod-wsgi

	#enable necessary apache modules	
	a2enmod rewrite
	a2enmod ssl
	a2enmod dav_svn
	a2enmod perl
}


function setup_svn_with_apache
{
	#arguments
	PROJECT_ID="$1"
	ANONYMOUS_CHECKOUT="$2"
	ADMIN_USER="$3"
	ADMIN_PASSWORD="$4"

	curdir=$(pwd)
	
	install_svn_deps

	#create SSL certificate, if one doesn't already exist in /etc/apache2/ssl/apache.pem
	mkdir /etc/apache2/ssl
	if [ ! -e "/etc/apache2/ssl/apache.pem" ] || [ ! -e "/etc/apache2/ssl/apache.key" ] ; then
		if [ -d "$NGINX_CONF_PATH/ssl" ] ; then
			mkdir /etc/apache2/ssl
			cp "$NGINX_CONF_PATH/ssl/nginx.pem" "/etc/apache2/ssl/apache.pem"
			cp "$NGINX_CONF_PATH/ssl/nginx.key" "/etc/apache2/ssl/apache.key"
		else
			make-ssl-cert generate-default-snakeoil --force-overwrite
			cp /etc/ssl/certs/ssl-cert-snakeoil.pem /etc/apache2/ssl/apache.pem
			cp /etc/ssl/private/ssl-cert-snakeoil.key /etc/apache2/ssl/apache.key
		fi
	fi


#create SSL virtual host
	mkdir -p /srv/www/apache_ssl/public_html /srv/www/apache_ssl/logs
	mkdir -p /srv/www/apache_nossl/public_html /srv/www/apache_nossl/logs
	

	cat <<'EOF' >/etc/apache2/sites-available/apache_ssl
<IfModule mod_ssl.c>
<VirtualHost _default_:443>
    DocumentRoot             /srv/www/apache_ssl/public_html/
    ErrorLog                 /srv/www/apache_ssl/logs/error.log
    CustomLog                /srv/www/apache_ssl/logs/access.log combined
    SSLEngine                on
    SSLCertificateFile       /etc/apache2/ssl/apache.pem
    SSLCertificateKeyFile    /etc/apache2/ssl/apache.key
    SSLProtocol              all
    SSLCipherSuite           HIGH:MEDIUM
    <FilesMatch "\.(cgi|shtml|phtml|php)$">
        SSLOptions           +StdEnvVars
    </FilesMatch>
    <Directory /usr/lib/cgi-bin>
        SSLOptions           +StdEnvVars
    </Directory> 
    BrowserMatch ".*MSIE.*" \
        nokeepalive          ssl-unclean-shutdown \
        downgrade-1.0        force-response-1.0
</VirtualHost>
</IfModule>
EOF

	a2ensite apache_ssl

	#create trac & svn root directories
	mkdir -p "/srv/projects/svn"
	mkdir -p "/srv/projects/auth/$PROJECT_ID"
	
	#create svn repository
	svnadmin create "/srv/projects/svn/$PROJECT_ID"

	web_auth_file="/srv/projects/auth/$PROJECT_ID/$PROJECT_ID.htpasswd"
	svn_auth_file="/srv/projects/auth/$PROJECT_ID/svn_auth_$PROJECT_ID"
	web_auth_enable="/etc/apache2/sites-available/auth_$PROJECT_ID"
	
	htpasswd -bc "$web_auth_file" "$ADMIN_USER" "$ADMIN_PASSWORD"
	
	if [ "$ANONYMOUS_CHECKOUT" = "1" ] ; then
		echo '[/]' >               "$svn_auth_file"
		echo "$ADMIN_USER = rw" >> "$svn_auth_file"
		echo '* = r' >>            "$svn_auth_file"
	
	else		
		echo '[/]' >               "$svn_auth_file"
		echo "$ADMIN_USER = rw" >> "$svn_auth_file"
	fi
	
	echo "<Location /svn/$PROJECT_ID>">>               "$web_auth_enable"
	echo '    DAV svn'>>                               "$web_auth_enable"
	echo "    SVNPath /srv/projects/svn/$PROJECT_ID">> "$web_auth_enable"
	
	if [ "$FORCE_SSL_FOR_SVN" = "1" ] ; then
		echo '    RewriteEngine on'>>                                    "$web_auth_enable"
		echo '    RewriteCond %{HTTPS} off'>>                            "$web_auth_enable"
		echo '    RewriteRule (.*) https://%{HTTP_HOST}%{REQUEST_URI}'>> "$web_auth_enable"
	fi
	echo '    AuthType Basic'>>                          "$web_auth_enable"
	echo "    AuthName \"$PROJECT_ID SVN Repository\"">> "$web_auth_enable"
	echo "    AuthUserFile $web_auth_file">>             "$web_auth_enable"
	echo "    AuthzSVNAccessFile $svn_auth_file">>       "$web_auth_enable"
	echo '    Satisfy any'>>                             "$web_auth_enable"
	echo '    Require valid-user'>>                      "$web_auth_enable"
	echo '</Location>'>>                                 "$web_auth_enable"
	a2ensite "auth_$PROJECT_ID"

	#grant permissions to apache for necessary directories
	chown -R www-data "/srv/projects/"
	

	#initialize SVN structure
	cd /tmp
	svn checkout  "file:///srv/projects/svn/$PROJECT_ID/"
	cd "$PROJECT_ID"
	mkdir branches tags trunk
	svn add branches tags trunk
	svn commit -m "Create Initial Repository Structure"
	cd ..
	rm -rf "$PROJECT_ID"

	#restart apache
	/etc/init.d/apache2 restart

	cd "$curdir"

	return 0
}




function setup_svn_with_redmine
{
	#arguments
	PROJ_NAME="$1"
	ANONYMOUS_CHECKOUT="$2"
	PROJ_USER="$3"
	PROJ_PW="$4"
	DB_PASSWORD="$5"
	
	setup_svn_with_apache "$PROJ_NAME" "$ANONYMOUS_CHECKOUT" "$PROJ_USER" "$PROJ_PW"

	curdir=$(pwd)


	db="$PROJ_NAME"_rm
	mysql_create_database "$DB_PASSWORD" "$db"
	mysql_create_user     "$DB_PASSWORD" "$db" "$PROJ_PW"
	mysql_grant_user      "$DB_PASSWORD" "$db" "$db"

	mkdir -p /srv/projects/redmine
	cd /srv/projects/redmine
	svn checkout http://redmine.rubyforge.org/svn/branches/0.9-stable "$PROJ_NAME"
	cd "$PROJ_NAME"

	cat << EOF >config/database.yml
production:
  adapter: mysql
  database: $db
  host: localhost
  username: $db
  password: $PROJ_PW
EOF

	if [ -e config/initializers/session_store.rb ] ; then
		RAILS_ENV=production rake config/initializers/session_store.rb
	else
		rake generate_session_store
	fi
	RAILS_ENV=production rake db:migrate
	echo "en" | RAILS_ENV=production rake redmine:load_default_data
	mkdir tmp public/plugin_assets
	sudo chmod -R 755 files log tmp public/plugin_assets

	#initialize redmine project data with create.rb script
	cat << EOF >create.rb
# Adapted From: http://github.com/edavis10/redmine_data_generator/blob/37b8acb63a4302281641090949fb0cb87e8b1039/app/models/data_generator.rb#L36
project = Project.create(
					:name => "$PROJ_NAME",
					:description => "",
					:identifier => "$PROJ_NAME",
					:is_public =>$ANONYMOUS_CHECKOUT
					)

repo = Repository::Subversion.create(
					:project_id=>project.id,
					:url=>"file:///srv/projects/svn/$PROJ_NAME"
					)
enmod = EnabledModule.create(
					:project_id=>project.id,
					:name=>"repository"
					)

@user = User.new( 
					:language => Setting.default_language,
					:firstname=>"-",
					:lastname=>"-",
					:mail=>"none@none.com"
					)
@user.admin = true
@user.login = "$PROJ_USER"
@user.password = "$PROJ_PW"
@user.password_confirmation = "$PROJ_PW"
@user.save

@membership = Member.new(
			:principal=>@user,
			:project_id=>project.id,
			:role_ids=>[3]
			)
@membership.save


puts project.errors.full_messages
puts repo.errors.full_messages
puts enmod.errors.full_messages
puts @user.errors.full_messages
puts @membership.errors.full_messages

EOF

	#delete original admin user & update info by running create script
	echo "DELETE FROM users WHERE login=\"admin\" ; " | mysql -u root -p"$DB_PASSWORD" "$db"
	ruby script/console production < create.rb
	rm -rf create.rb



	chown -R www-data:www-data /srv/projects

	nginx_delete_site "default"
	nginx_delete_site "localhost"
	nginx_create_site "localhost" "localhost" "0" "/$PROJ_NAME" "1"
	cd /srv/www/localhost/public_html
	ln -s /srv/projects/redmine/$PROJ_NAME/public $PROJ_NAME
	nginx_ensite      "localhost"

	#use redmine authentication
	rm -rf projects/auth/
	cat << EOF >"/etc/apache2/sites-available/auth_$PROJ_NAME"
PerlLoadModule Apache::Authn::Redmine
<Location /svn/$PROJ_NAME>
	DAV               svn
	SVNPath           /srv/projects/svn/$PROJ_NAME
	Order             deny,allow
	Deny from         all
	Satisfy           any
	PerlAccessHandler Apache::Authn::Redmine::access_handler	
	PerlAuthenHandler Apache::Authn::Redmine::authen_handler
	AuthType          Basic
	AuthName	  "$PROJ_NAME SVN Repository"

EOF
	if [ "$ANONYMOUS_CHECKOUT" == "1" ] ; then
	cat << EOF >>"/etc/apache2/sites-available/auth_$PROJ_NAME"
	<Limit GET PROPFIND OPTIONS>
		Require     valid-user
	</Limit>

EOF
	fi

	cat << EOF >>"/etc/apache2/sites-available/auth_$PROJ_NAME"
	<LimitExcept GET PROPFIND OPTIONS>
		Require   valid-user
	</LimitExcept>

	RedmineDSN        "DBI:mysql:database=$db;host=localhost"
	RedmineDbUser     "$db"
	RedmineDbPass     "$PROJ_PW"

</Location>
EOF

	#default Redmine.pm only works with SVNParentPath, not SVNPath
	#Dump a better version that fixes this (still works with SVNParentPath too)
	mkdir -p /usr/lib/perl5/Apache/Authn
	cat << 'EOF' >/usr/lib/perl5/Apache/Authn/Redmine.pm
package Apache::Authn::Redmine;

=head1 Apache::Authn::Redmine

Redmine - a mod_perl module to authenticate webdav subversion users
against redmine database

=head1 SYNOPSIS

This module allow anonymous users to browse public project and
registred users to browse and commit their project. Authentication is
done against the redmine database or the LDAP configured in redmine.

This method is far simpler than the one with pam_* and works with all
database without an hassle but you need to have apache/mod_perl on the
svn server.

=head1 INSTALLATION

For this to automagically work, you need to have a recent reposman.rb
(after r860) and if you already use reposman, read the last section to
migrate.

Sorry ruby users but you need some perl modules, at least mod_perl2,
DBI and DBD::mysql (or the DBD driver for you database as it should
work on allmost all databases).

On debian/ubuntu you must do :

  aptitude install libapache-dbi-perl libapache2-mod-perl2 libdbd-mysql-perl

If your Redmine users use LDAP authentication, you will also need
Authen::Simple::LDAP (and IO::Socket::SSL if LDAPS is used):

  aptitude install libauthen-simple-ldap-perl libio-socket-ssl-perl

=head1 CONFIGURATION

   ## This module has to be in your perl path
   ## eg:  /usr/lib/perl5/Apache/Authn/Redmine.pm
   PerlLoadModule Apache::Authn::Redmine
   <Location /svn>
     DAV svn
     SVNParentPath "/var/svn"

     AuthType Basic
     AuthName redmine
     Require valid-user

     PerlAccessHandler Apache::Authn::Redmine::access_handler
     PerlAuthenHandler Apache::Authn::Redmine::authen_handler
  
     ## for mysql
     RedmineDSN "DBI:mysql:database=databasename;host=my.db.server"
     ## for postgres
     # RedmineDSN "DBI:Pg:dbname=databasename;host=my.db.server"

     RedmineDbUser "redmine"
     RedmineDbPass "password"
     ## Optional where clause (fulltext search would be slow and
     ## database dependant).
     # RedmineDbWhereClause "and members.role_id IN (1,2)"
     ## Optional credentials cache size
     # RedmineCacheCredsMax 50
  </Location>

To be able to browse repository inside redmine, you must add something
like that :

   <Location /svn-private>
     DAV svn
     SVNParentPath "/var/svn"
     Order deny,allow
     Deny from all
     # only allow reading orders
     <Limit GET PROPFIND OPTIONS REPORT>
       Allow from redmine.server.ip
     </Limit>
   </Location>

and you will have to use this reposman.rb command line to create repository :

  reposman.rb --redmine my.redmine.server --svn-dir /var/svn --owner www-data -u http://svn.server/svn-private/

=head1 MIGRATION FROM OLDER RELEASES

If you use an older reposman.rb (r860 or before), you need to change
rights on repositories to allow the apache user to read and write
S<them :>

  sudo chown -R www-data /var/svn/*
  sudo chmod -R u+w /var/svn/*

And you need to upgrade at least reposman.rb (after r860).

=cut

use strict;
use warnings FATAL => 'all', NONFATAL => 'redefine';

use DBI;
use Digest::SHA1;
# optional module for LDAP authentication
my $CanUseLDAPAuth = eval("use Authen::Simple::LDAP; 1");

use Apache2::Module;
use Apache2::Access;
use Apache2::ServerRec qw();
use Apache2::RequestRec qw();
use Apache2::RequestUtil qw();
use Apache2::Const qw(:common :override :cmd_how);
use APR::Pool ();
use APR::Table ();


 use Apache2::Directive qw();

my @directives = (
  {
    name => 'RedmineDSN',
    req_override => OR_AUTHCFG,
    args_how => TAKE1,
    errmsg => 'Dsn in format used by Perl DBI. eg: "DBI:Pg:dbname=databasename;host=my.db.server"',
  },
  {
    name => 'RedmineDbUser',
    req_override => OR_AUTHCFG,
    args_how => TAKE1,
  },
  {
    name => 'RedmineDbPass',
    req_override => OR_AUTHCFG,
    args_how => TAKE1,
  },
  {
    name => 'RedmineDbWhereClause',
    req_override => OR_AUTHCFG,
    args_how => TAKE1,
  },
  {
    name => 'RedmineCacheCredsMax',
    req_override => OR_AUTHCFG,
    args_how => TAKE1,
    errmsg => 'RedmineCacheCredsMax must be decimal number',
  },
  {
    name => 'SVNPath',
    req_override => OR_AUTHCFG,
    args_how => TAKE1,
  }
);

sub SVNPath { set_val('SVNPath', @_); }


sub RedmineDSN { 
  my ($self, $parms, $arg) = @_;
  $self->{RedmineDSN} = $arg;
  my $query = "SELECT 
                 hashed_password, auth_source_id, permissions
              FROM members, projects, users, roles, member_roles
              WHERE 
                projects.id=members.project_id
                AND member_roles.member_id=members.id
                AND users.id=members.user_id 
                AND roles.id=member_roles.role_id
                AND users.status=1 
                AND login=? 
                AND identifier=? ";
  $self->{RedmineQuery} = trim($query);
}

sub RedmineDbUser { set_val('RedmineDbUser', @_); }
sub RedmineDbPass { set_val('RedmineDbPass', @_); }
sub RedmineDbWhereClause { 
  my ($self, $parms, $arg) = @_;
  $self->{RedmineQuery} = trim($self->{RedmineQuery}.($arg ? $arg : "")." ");
}

sub RedmineCacheCredsMax { 
  my ($self, $parms, $arg) = @_;
  if ($arg) {
    $self->{RedmineCachePool} = APR::Pool->new;
    $self->{RedmineCacheCreds} = APR::Table::make($self->{RedmineCachePool}, $arg);
    $self->{RedmineCacheCredsCount} = 0;
    $self->{RedmineCacheCredsMax} = $arg;
  }
}

sub trim {
  my $string = shift;
  $string =~ s/\s{2,}/ /g;
  return $string;
}

sub set_val {
  my ($key, $self, $parms, $arg) = @_;
  $self->{$key} = $arg;
}

Apache2::Module::add(__PACKAGE__, \@directives);


my %read_only_methods = map { $_ => 1 } qw/GET PROPFIND REPORT OPTIONS/;

sub access_handler {
  my $r = shift;

  unless ($r->some_auth_required) {
      $r->log_reason("No authentication has been configured");
      return FORBIDDEN;
  }

  my $method = $r->method;
  return OK unless defined $read_only_methods{$method};

  my $project_id = get_project_identifier($r);

  $r->set_handlers(PerlAuthenHandler => [\&OK])
      if is_public_project($project_id, $r);

  return OK
}

sub authen_handler {
  my $r = shift;
  
  my ($res, $redmine_pass) =  $r->get_basic_auth_pw();
  return $res unless $res == OK;
  
  if (is_member($r->user, $redmine_pass, $r)) {
      return OK;
  } else {
      $r->note_auth_failure();
      return AUTH_REQUIRED;
  }
}

sub is_public_project {
    my $project_id = shift;
    my $r = shift;

    my $dbh = connect_database($r);
    my $sth = $dbh->prepare(
        "SELECT is_public FROM projects WHERE projects.identifier = ?;"
    );

    $sth->execute($project_id);
    my $ret = 0;
    if (my @row = $sth->fetchrow_array) {
    	if ($row[0] eq "1" || $row[0] eq "t") {
    		$ret = 1;
    	}
    }
    $sth->finish();
    undef $sth;
    $dbh->disconnect();
    undef $dbh;

    $ret;
}

# perhaps we should use repository right (other read right) to check public access.
# it could be faster BUT it doesn't work for the moment.
# sub is_public_project_by_file {
#     my $project_id = shift;
#     my $r = shift;

#     my $tree = Apache2::Directive::conftree();
#     my $node = $tree->lookup('Location', $r->location);
#     my $hash = $node->as_hash;

#     my $svnparentpath = $hash->{SVNParentPath};
#     my $repos_path = $svnparentpath . "/" . $project_id;
#     return 1 if (stat($repos_path))[2] & 00007;
# }

sub is_member {
  my $redmine_user = shift;
  my $redmine_pass = shift;
  my $r = shift;

  my $dbh         = connect_database($r);
  my $project_id  = get_project_identifier($r);

  my $pass_digest = Digest::SHA1::sha1_hex($redmine_pass);

  my $cfg = Apache2::Module::get_config(__PACKAGE__, $r->server, $r->per_dir_config);
  my $usrprojpass;
  if ($cfg->{RedmineCacheCredsMax}) {
    $usrprojpass = $cfg->{RedmineCacheCreds}->get($redmine_user.":".$project_id);
    return 1 if (defined $usrprojpass and ($usrprojpass eq $pass_digest));
  }
  my $query = $cfg->{RedmineQuery};
  my $sth = $dbh->prepare($query);
  $sth->execute($redmine_user, $project_id);

  my $ret;
  while (my ($hashed_password, $auth_source_id, $permissions) = $sth->fetchrow_array) {

      unless ($auth_source_id) {
	  my $method = $r->method;
          if ($hashed_password eq $pass_digest && ((defined $read_only_methods{$method} && $permissions =~ /:browse_repository/) || $permissions =~ /:commit_access/) ) {
              $ret = 1;
              last;
          }
      } elsif ($CanUseLDAPAuth) {
          my $sthldap = $dbh->prepare(
              "SELECT host,port,tls,account,account_password,base_dn,attr_login from auth_sources WHERE id = ?;"
          );
          $sthldap->execute($auth_source_id);
          while (my @rowldap = $sthldap->fetchrow_array) {
            my $ldap = Authen::Simple::LDAP->new(
                host    =>      ($rowldap[2] eq "1" || $rowldap[2] eq "t") ? "ldaps://$rowldap[0]" : $rowldap[0],
                port    =>      $rowldap[1],
                basedn  =>      $rowldap[5],
                binddn  =>      $rowldap[3] ? $rowldap[3] : "",
                bindpw  =>      $rowldap[4] ? $rowldap[4] : "",
                filter  =>      "(".$rowldap[6]."=%s)"
            );
            $ret = 1 if ($ldap->authenticate($redmine_user, $redmine_pass));
          }
          $sthldap->finish();
          undef $sthldap;
      }
  }
  $sth->finish();
  undef $sth;
  $dbh->disconnect();
  undef $dbh;

  if ($cfg->{RedmineCacheCredsMax} and $ret) {
    if (defined $usrprojpass) {
      $cfg->{RedmineCacheCreds}->set($redmine_user.":".$project_id, $pass_digest);
    } else {
      if ($cfg->{RedmineCacheCredsCount} < $cfg->{RedmineCacheCredsMax}) {
        $cfg->{RedmineCacheCreds}->set($redmine_user.":".$project_id, $pass_digest);
        $cfg->{RedmineCacheCredsCount}++;
      } else {
        $cfg->{RedmineCacheCreds}->clear();
        $cfg->{RedmineCacheCredsCount} = 0;
      }
    }
  }

  $ret;
}

sub get_project_identifier
{
	my $r = shift;
	my $cfg = Apache2::Module::get_config(__PACKAGE__, $r->server, $r->per_dir_config);
	my $identifier = "";
	if(defined($cfg->{SVNPath}))
	{
		#SVNPath
		$identifier = $r->location;
		$identifier =~ s/\/+$//g;
		$identifier =~ s/^.*\///g;
	}
	else 
	{
		#SVNParentPath
		my $location = $r->location;
		($identifier) = $r->uri =~ m{$location/*([^/]+)};
	}
	return $identifier;

}

sub connect_database {
    my $r = shift;
    
    my $cfg = Apache2::Module::get_config(__PACKAGE__, $r->server, $r->per_dir_config);
    return DBI->connect($cfg->{RedmineDSN}, $cfg->{RedmineDbUser}, $cfg->{RedmineDbPass});
}

1;

EOF


	/etc/init.d/apache2 restart
	
	cd "$curdir"

}
	
function backup_sites
{
	if [ ! -n "$1" ]; then
		echo "backup_sites() requires the backup directory as its first argument"
		return 1;
	fi
	BACKUP_DIR="$1";
	
	curdir=$(pwd)

	mkdir -p "$BACKUP_DIR/sites"
	mkdir -p "$BACKUP_DIR/nginx_site_configs"
	mkdir -p "$BACKUP_DIR/nginx_configs"
	mkdir -p "$BACKUP_DIR/apache_site_configs"
	mkdir -p "$BACKUP_DIR/apache_configs"

	cp /etc/nginx/*.conf "$BACKUP_DIR/nginx_configs"
	cp -r /etc/nginx/ssl "$BACKUP_DIR/nginx_configs"
	cp /etc/apache2/*.conf "$BACKUP_DIR/apache_configs"
	cp -r /etc/apache2/ssl "$BACKUP_DIR/apache_configs"


	if [ -d /srv/www/logs ] ; then
		tar cjfp "$BACKUP_DIR/sites/logs.tar.bz2" "/srv/www/logs"
	fi
	
	if [ -d "/etc/nginx/sites-enabled" ] ; then
		cp /etc/nginx/sites-enabled/* "$BACKUP_DIR/nginx_site_configs"
		nginx_site_roots=$(cat /etc/nginx/sites-enabled/* 2>/dev/null | grep root | awk '{ print $2 }' | sed 's/;//g')
		for site_root in $nginx_site_roots ; do
			if [ -e "$site_root" ] ; then
				site_dir=$(echo "$site_root" | sed 's/\/public_html.*$//g')
				site_name=$(echo "$site_dir" | sed 's/^.*\///g')
				cd "$site_dir"/..
				echo $(pwd)
				tar cjfp "$BACKUP_DIR/sites/$site_name.tar.bz2" "$site_name"
			fi
		done
	fi
	if [ -d "/etc/apache2/sites-enabled" ] ; then
		cp /etc/apache2/sites-enabled/* "$BACKUP_DIR/apache_site_configs"
		apache_site_roots=$(cat /etc/apache2/sites-enabled/* 2>/dev/null | grep DocumentRoot  | awk '{ print $2 }')
		for site_root in $apache_site_roots ; do
			if [ -e "$site_root" ] ; then
				site_dir=$(echo "$site_root" | sed 's/\/public_html.*$//g')
				site_name=$(echo "$site_dir" | sed 's/^.*\///g')
				cd "$site_dir"/..
				echo $(pwd)
				
				tar cjfp "$BACKUP_DIR/sites/$site_name.tar.bz2" "$site_name"
			fi
		done
	fi

	cd "$curdir"
}

function restore_sites
{
	if [ ! -n "$1" ]; then
		echo "restore_sites() requires the backup directory as its first argument"
		return 1;
	fi
	BACKUP_DIR="$1";
	
	curdir=$(pwd)

	if [ -d "/etc/nginx/" ]  && [ -d "$BACKUP_DIR/nginx_configs" ] ; then
		cp -r "$BACKUP_DIR"/nginx_configs/* /etc/nginx/
	fi
	if [ -d "/etc/apache2/" ]  && [ -d "$BACKUP_DIR/apache2_configs" ] ; then
		cp -r "$BACKUP_DIR"/apache_configs/* /etc/apache2/
	fi

	if [ -d "/etc/nginx/sites-available" ]  && [ -d "$BACKUP_DIR/nginx_site_configs" ] ; then
		configs=$(ls $BACKUP_DIR/nginx_site_configs/* | sed 's/^.*\///g')
		for config in $configs ; do
			cp "$BACKUP_DIR/nginx_site_configs/$config" "/etc/nginx/sites-available/$config"
			nginx_ensite "$config"
			site_root=$(cat "$BACKUP_DIR/nginx_site_configs/$config" 2>/dev/null | grep root | awk '{ print $2 }' | sed 's/;//g')
			echo "site_root = $site_root"
			if [ -n "$site_root" ] ; then
				site_dir=$(echo "$site_root" | sed 's/\/public_html.*$//g')
				site_name=$(echo "$site_dir" | sed 's/^.*\///g')
				echo "site_name = $site_name"
				if [ -e "$BACKUP_DIR/sites/$site_name.tar.bz2" ] ; then
					site_parent_dir=$(echo "$site_root" | sed 's/\/.*$//g')
					cd "$site_parent_dir"
					tar xjfp "$BACKUP_DIR/sites/$site_name.tar.bz2"
				else
					mkdir -p "$site_dir/public_html"
					mkdir -p "$site_dir/logs"
					chown -R www-data:www-data "$site_dir"
				fi
			fi
		done
	fi
	
	if [ -d "/etc/apache2/sites-available" ]  && [ -d "$BACKUP_DIR/apache_site_configs" ] ; then
		configs=$(ls $BACKUP_DIR/apache_site_configs/* | sed 's/^.*\///g')
		for config in $configs ; do
			cp "$BACKUP_DIR/apache_site_configs/$config" "/etc/apache2/sites-available/$config"
			a2ensite "$config"
			site_root=$(cat "$BACKUP_DIR/apache_site_configs/$config" 2>/dev/null | grep DocumentRoot | awk '{ print $2 }' )
			if [ -n "$site_root" ] ; then
				site_dir=$(echo "$site_root" | sed 's/\/public_html.*$//g')
				site_name=$(echo "$site_dir" | sed 's/^.*\///g')
				if [ -e "$BACKUP_DIR/sites/$site_name.tar.bz2" ] ; then
					site_parent_dir=$(echo "$site_root" | sed 's/\/.*$//g')
					cd "$site_parent_dir"
					tar xjfp "$BACKUP_DIR/sites/$site_name.tar.bz2"
				else
					mkdir -p "$site_dir/public_html"
					mkdir -p "$site_dir/logs"
					chown -R www-data:www-data "$site_dir"
				fi
			fi
		done
	fi
	
	if [ -e /etc/init.d/nginx ] ; then
		/etc/init.d/nginx restart 
	fi
	if [ -e /etc/init.d/apache2 ] ; then
		/etc/init.d/apache2 restart
	fi
	
	cd "$curdir"
}

function backup_projects
{
	if [ ! -n "$1" ]; then
		echo "backup_projects() requires the backup directory as its first argument"
		return 1;
	fi
	BACKUP_DIR="$1"

	curdir=$(pwd)
	rm -rf   /tmp/projects
	mkdir -p /tmp/projects
	cd       /tmp/projects

	cp -r /srv/projects/redmine .
	mkdir svn

	proj_list=$(ls /srv/projects/redmine)
	for proj in $proj_list ; do
		if [ -e "/var/projects/svn/$proj" ] ; then
			svnadmin hotcopy "/var/projects/svn/$proj" "./svn/$proj"
		fi
	done

	cd ..
	tar cjfp "$BACKUP_DIR/projects.tar.bz2" projects
	rm -rf projects

	cd "$curdir"
}

function restore_projects
{
	if [ ! -n "$1" ]; then
		echo "restore_projects() requires the backup directory as its first argument"
		return 1;
	fi
	BACKUP_DIR="$1"

	curdir=$(pwd)
	
	if [ -e "$BACKUP_DIR/projects.tar.bz2" ] ; then
		mkdir -p /srv/
		cd /srv
		tar xjfp "$BACKUP_DIR/projects.tar.bz2"
	fi

	cd "$curdir"

}


#################################
#	Mail Functions          #
#################################


function initialize_mail_server
{
	TEST_USER_DOMAIN="$1"
	TEST_USER_PASS="$2"
	PORT_587_ENABLED="$3"

	upgrade_system

	if [ -d	"/home/vmail" ] ; then
		echo "ERROR: mail server already initialized"
		return 1;
	fi
	
	#install postfix
	echo "postfix_2.6.5 postfix/destinations     string localhost" | debconf-set-selections
	echo "postfix_2.6.5 postfix/mailname         string localhost" | debconf-set-selections
	echo "postfix_2.6.5 postfix/main_mailer_type select Internet Site" | debconf-set-selections
	aptitude -y install postfix mailx dovecot-common dovecot-imapd dovecot-pop3d whois sasl2-bin
	
	postconf -e "mailbox_command = "
	postconf -e "home_mailbox = Maildir/"
	postconf -e "inet_interfaces = all"
	postconf -e "myhostname = localhost"
	
	postconf -e "virtual_mailbox_domains = /etc/postfix/vhosts"
	postconf -e "virtual_mailbox_base = /home/vmail"
	postconf -e "virtual_mailbox_maps = hash:/etc/postfix/vmaps"
	postconf -e "virtual_minimum_uid = 1000"
	postconf -e "virtual_uid_maps = static:5000"
	postconf -e "virtual_gid_maps = static:5000"
	
	postconf -e "smtp_tls_security_level = may"
	postconf -e "smtpd_tls_security_level = may"
	postconf -e "smtpd_tls_auth_only = no"
	postconf -e "smtp_tls_note_starttls_offer = yes"
	postconf -e "smtpd_tls_key_file = /etc/postfix/ssl/smtp_cert_key.pem"
	postconf -e "smtpd_tls_cert_file = /etc/postfix/ssl/smtp_cert.pem"
	postconf -e "smtpd_tls_CAfile_file = /etc/postfix/ssl/cacert.pem"
	postconf -e "smtpd_tls_loglevel = 1"
	postconf -e "smtpd_tls_received_header = yes"
	postconf -e "smtpd_tls_session_cache_timeout = 3600s"
	postconf -e "tls_random_source = dev:/dev/urandom"
	
	
	
	#configure tls
	curdir=$(pwd)
	rm -rf /etc/postfix/ssl /tmp/tmp_cert
	mkdir -p /etc/postfix/ssl
	mkdir -p /tmp/tmp_cert
	cd /tmp/tmp_cert
	mkdir demoCA
	mkdir demoCA/newcerts
	mkdir demoCA/private
	touch demoCA/index.txt
	echo "01" >> demoCA/serial
	ca_pass=$(randomString 10)
	cat /etc/ssl/openssl.cnf | sed 's/supplied/optional/g' > openssl.cnf
	openssl req -new -x509 -keyout cakey.pem -out cacert.pem -days 99999 -passout "pass:$ca_pass" -batch
	openssl req -nodes -new -x509 -keyout newreq.pem -out newreq.pem -days 99999 -batch
	openssl x509 -x509toreq -in newreq.pem -signkey newreq.pem -out tmp.pem
	openssl ca -batch -passin "pass:$ca_pass" -keyfile ./cakey.pem -cert ./cacert.pem -config ./openssl.cnf -policy policy_anything -out newcert.pem -infiles tmp.pem
	grep -B 100 "END RSA PRIVATE KEY" newreq.pem > newcertkey.pem
	mv cacert.pem /etc/postfix/ssl/cacert.pem
	mv newcert.pem /etc/postfix/ssl/smtp_cert.pem
	mv newcertkey.pem /etc/postfix/ssl/smtp_cert_key.pem
	cd "$curdir"
	rm -rf /tmp/tmp_cert
	
	cat <<'EOF' >/etc/default/saslauthd
#
# Settings for saslauthd daemon
# Please read /usr/share/doc/sasl2-bin/README.Debian for details.
#

# Should saslauthd run automatically on startup? (default: no)
START=yes

PWDIR="/var/spool/postfix/var/run/saslauthd"
PARAMS="-m ${PWDIR}"
PIDFILE="${PWDIR}/saslauthd.pid"


# Description of this saslauthd instance. Recommended.
# (suggestion: SASL Authentication Daemon)
DESC="SASL Authentication Daemon"

# Short name of this saslauthd instance. Strongly recommended.
# (suggestion: saslauthd)
NAME="saslauthd"

# Which authentication mechanisms should saslauthd use? (default: pam)
#
# Available options in this Debian package:
# getpwent  -- use the getpwent() library function
# kerberos5 -- use Kerberos 5
# pam       -- use PAM
# rimap     -- use a remote IMAP server
# shadow    -- use the local shadow password file
# sasldb    -- use the local sasldb database file
# ldap      -- use LDAP (configuration is in /etc/saslauthd.conf)
#
# Only one option may be used at a time. See the saslauthd man page
# for more information.
#
# Example: MECHANISMS="pam"
MECHANISMS="pam"

# Additional options for this mechanism. (default: none)
# See the saslauthd man page for information about mech-specific options.
MECH_OPTIONS=""

# How many saslauthd processes should we run? (default: 5)
# A value of 0 will fork a new process for each connection.
THREADS=5

# Other options (default: -c -m /var/run/saslauthd)
# Note: You MUST specify the -m option or saslauthd won't run!
#
# WARNING: DO NOT SPECIFY THE -d OPTION.
# The -d option will cause saslauthd to run in the foreground instead of as
# a daemon. This will PREVENT YOUR SYSTEM FROM BOOTING PROPERLY. If you wish
# to run saslauthd in debug mode, please run it by hand to be safe.
#
# See /usr/share/doc/sasl2-bin/README.Debian for Debian-specific information.
# See the saslauthd man page and the output of 'saslauthd -h' for general
# information about these options.
#
# Example for postfix users: "-c -m /var/spool/postfix/var/run/saslauthd"
OPTIONS="-c -m /var/spool/postfix/var/run/saslauthd"
EOF
	
	dpkg-statoverride --force --update --add root sasl 755 /var/spool/postfix/var/run/saslauthd
	
	
	
	
	#configure virtual mailboxes
	
	groupadd -g 5000 vmail
	useradd -m -u 5000 -g 5000 -s /bin/bash vmail
	cat <<'EOF' >/etc/dovecot/dovecot.conf
base_dir = /var/run/dovecot/
disable_plaintext_auth = no
protocols = imap pop3
shutdown_clients = yes
log_path = /var/log/dovecot
info_log_path = /var/log/dovecot.info
log_timestamp = "%Y-%m-%d %H:%M:%S "
ssl_disable = no
login_dir = /var/run/dovecot/login
login_chroot = yes
login_user = dovecot
login_greeting = Dovecot ready.
mail_location = maildir:/home/vmail/%d/%n
mmap_disable = no
valid_chroot_dirs = /var/spool/vmail

protocol pop3 {
  login_executable = /usr/lib/dovecot/pop3-login
  mail_executable = /usr/lib/dovecot/pop3
  pop3_uidl_format = %08Xu%08Xv
}
  
protocol imap {
  login_executable = /usr/lib/dovecot/imap-login
  mail_executable = /usr/lib/dovecot/imap
}
auth_executable = /usr/lib/dovecot/dovecot-auth
auth_verbose = yes
auth default {
  mechanisms = plain  digest-md5
  passdb passwd-file {
    args = /etc/dovecot/passwd
  }
  userdb passwd-file {
    args = /etc/dovecot/users
  }
  user = root
}
EOF
	
	cat <<'EOF' >/usr/sbin/add_dovecot_user
#!/bin/sh
if [ -z "$1" ] ; then
	echo "You must specify email address (full username) as first parameter"
fi
if [ -z "$2" ] ; then
	echo "You must specify password as second parameter"
fi

echo "$1" > /tmp/user
user=`cat /tmp/user | cut -f1 -d "@"`
domain=`cat /tmp/user | cut -f2 -d "@"`

touch /etc/dovecot/users
cat /etc/dovecot/users | grep -v "^$user@$domain:" > /etc/dovecot/users.tmp
echo "$user@$domain::5000:5000::/home/vmail/$domain/:/bin/false::" >>/etc/dovecot/users.tmp
mv /etc/dovecot/users.tmp /etc/dovecot/users

touch /etc/postfix/vhosts
cat /etc/postfix/vhosts | grep -v "$domain" > /etc/postfix/vhosts.tmp
echo $domain >> /etc/postfix/vhosts.tmp
mv /etc/postfix/vhosts.tmp /etc/postfix/vhosts

touch /etc/postfix/vmaps
cat /etc/postfix/vmaps | grep -v "$1" >/etc/postfix/vmaps.tmp
echo $1 $domain/$user/ >>/etc/postfix/vmaps.tmp
mv /etc/postfix/vmaps.tmp /etc/postfix/vmaps

/usr/bin/maildirmake.dovecot /home/vmail/$domain/$user 5000:5000
chown -R vmail /home/vmail/*
chgrp -R vmail /home/vmail/*

mkpasswd --hash=md5 $2 >/tmp/hash
echo "$1:`cat /tmp/hash`" >> /etc/dovecot/passwd

postmap /etc/postfix/vmaps
/etc/init.d/postfix restart
EOF
	chmod +x /usr/sbin/add_dovecot_user
	
	touch /etc/postfix/vhosts
	touch /etc/postfix/vmaps
	touch /etc/dovecot/passwd
	touch /etc/dovecot/users
	chmod 640 /etc/dovecot/users /etc/dovecot/passwd
	
	/usr/sbin/add_dovecot_user "test_user@$TEST_USER_DOMAIN" "$TEST_USER_PASS"
	
	
	#set ports smtp server will run on
	if [ "$PORT_587_ENABLED" = "0" ] ; then
		cat /etc/postfix/master.cf | sed 's/^submission.*inet/#submission inet/g' > /etc/postfix/master.cf.tmp
	else
		cat /etc/postfix/master.cf | sed 's/^#submission.*inet/submission inet/g' > /etc/postfix/master.cf.tmp
	fi
	mv /etc/postfix/master.cf.tmp /etc/postfix/master.cf
	
	
	#restart
	/etc/init.d/saslauthd restart
	/etc/init.d/dovecot restart
	/etc/init.d/postfix restart
}


function backup_mail_config
{
	if [ ! -n "$1" ]; then
		echo "backup_mail_config() requires the backup directory as its first argument"
		return 1;
	fi
	BACKUP_DIR="$1"

	rm -rf	 /tmp/mail_backup
	mkdir -p /tmp/mail_backup
	cp -rp /etc/postfix /tmp/mail_backup/
	cp -rp /etc/dovecot /tmp/mail_backup/
	cp -rp /home/vmail  /tmp/mail_backup/
	curdir=$(pwd)	
	cd /tmp
	tar cjfp "$BACKUP_DIR/mail_backup.tar.bz2" mail_backup
	cd "$curdir"
	rm -rf /tmp/mail_backup
}

function restore_mail_config
{
	if [ ! -n "$1" ]; then
		echo "restore_mail_config() requires the backup directory as its first argument"
		return 1;
	fi
	BACKUP_DIR="$1"

	if [ ! -e /home/vmail ] ; then
		initialize_mail_server "dummy.com" "dummy_pass" "0" "1"
	fi

	if [ -e "$BACKUP_DIR/mail_backup.tar.bz2" ] ; then
		rm -rf /tmp/mail_backup
		tar -C /tmp -xjf $BACKUP_DIR/mail_backup.tar.bz2
		rm -rf /etc/postfix /etc/dovecot /home/vmail/*
		mv /tmp/mail_backup/postfix /etc/
		mv /tmp/mail_backup/dovecot /etc/
		mv /tmp/mail_backup/vmail/* /home/vmail
		chown -R vmail /home/vmail/*
		chgrp -R vmail /home/vmail/*
		rm -rf /tmp/mail_backup
	
		/etc/init.d/saslauthd restart
		/etc/init.d/dovecot restart
		/etc/init.d/postfix restart
	fi
}


#################################
#	Hostname                #
#################################

function set_hostname
{
	if [ ! -n "$1" ]; then
		echo "set_hostname() requires hostname as its first argument"
		return 1;
	fi

	HOSTNAME="$1"
	echo "$HOSTNAME" > /etc/hostname
	echo "$HOSTNAME" > /proc/sys/kernel/hostname
	
	touch /etc/hosts
	cat /etc/hosts | grep -v "$HOSTNAME" > /etc/hosts.tmp
	echo -e "\n127.0.0.1 $HOSTNAME\n" >> /etc/hosts.tmp
	mv /etc/hosts.tmp /etc/hosts

}

function backup_hostname
{
	if [ ! -n "$1" ]; then
		echo "backup_hostname() requires the backup directory as its first argument"
		return 1;
	fi
	
	BACKUP_DIR="$1"

	if [ -e /etc/hostname ] ; then
		cp /etc/hostname "$BACKUP_DIR/"
	fi
	if [ -e /etc/hosts ] ; then
		cp /etc/hosts "$BACKUP_DIR/"
	fi
	if [ -e /etc/mailname ] ; then
		cp /etc/mailname "$BACKUP_DIR/"
	fi
}

function restore_hostname
{
	if [ ! -n "$1" ]; then
		echo "restore_hostname() requires the backup directory as its first argument"
		return 1;
	fi
	
	BACKUP_DIR="$1"

	if [ -e "$BACKUP_DIR/hostname" ] ; then
		cp "$BACKUP_DIR/hostname" /etc/hostname 
		hostname $(cat /etc/hostname)
	fi
	if [ -e "$BACKUP_DIR/hosts" ] ; then
		cp "$BACKUP_DIR/hosts" /etc/hosts
	fi
	if [ -e "$BACKUP_DIR/mailname" ] ; then
		cp "$BACKUP_DIR/mailname" /etc/mailname
	fi
}


#################################
#	Security                #
#################################

function set_open_ports
{
	#set open ports using ufw, and 
	#install fail2ban too while we're at it... 
	#(fail2ban temporarily blocks IPs that make a bunch of failed login attempts via ssh)
	aptitude -y install  fail2ban ufw
	
	#up the max fail2ban attempts, since I can be a bit dimwitted at times...
	cat /etc/fail2ban/jail.conf | sed 's/maxretry.*/maxretry = 12/g' > /etc/fail2ban/jail.conf.tmp
	mv /etc/fail2ban/jail.conf.tmp /etc/fail2ban/jail.conf 

	#always allow ssh
	ufw default deny
	ufw allow ssh

	#set allowed ports
	while [ -n "$1" ] ; do
		ufw allow "$1"
		shift
	done
	
	#enable firewall
	ufw logging on 
	ufw enable
}
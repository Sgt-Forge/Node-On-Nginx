#!/bin/bash
# Don't include the ".com" at the end of the name
if [ "$#" -ne 3 ] || ! [ -d "$1" ]; then
  echo "Usage: $0 relative_path_to_node_app website_name certbot_email" >&2
  exit 1
fi

nodeapp_path="$1"
website_name="$2"
email_arg="$3"
domain_arg="$website_name.com"
nginx_directory=$(pwd)
echo $website_name
echo $email_arg
echo $domain_arg
rsa_key_size=4096

function logger {
    function_name=$1
    message=$2
    log="$(date) | $function_name | $message"
    echo $log
}

function arch_install {
    sudo pacman -Sy
    sudo pacman -S docker docker-compose openssl
    sudo systemctl enable docker
    sudo systemctl start docker
    openssl dhparam -out ./config/nginx/dhparam.pem 2048

    sed -i "s/website/$website_name/g" ./config/nginx/sites-available/nodeapp.conf
    sed -i "s/website/$website_name/g" ./config/nginx/sites-enabled/nodeapp.conf

    sed -i -r 's/(listen .*443)/\1; #/g; s/(ssl_(certificate|certificate_key|trusted_certificate) )/#;#\1/g; s/(server \{)/\1\n    ssl off;/g' ./config/nginx/sites-available/nodeapp.conf
    sed -i -r 's/(listen .*443)/\1; #/g; s/(ssl_(certificate|certificate_key|trusted_certificate) )/#;#\1/g; s/(server \{)/\1\n    ssl off;/g' ./config/nginx/sites-enabled/nodeapp.conf

    echo "### Starting node app ..."
    docker-compose up --build -d nodeapp
    echo

    echo "### Starting nginx ..."
    docker-compose up --build -d nginx
    echo

    docker-compose run --rm --entrypoint "\
        certbot certonly --webroot -w /var/www/letsencrypt \
            $email_arg \
            $domain_args \
            --rsa-key-size $rsa_key_size \
            --agree-tos \
            --force-renewal" certbot

    sed -i -r -z 's/#?; ?#//g; s/(server \{)\n    ssl off;/\1/g' ./config/nginx/sites-available/nodeapp.conf
    sed -i -r -z 's/#?; ?#//g; s/(server \{)\n    ssl off;/\1/g' ./config/nginx/sites-available/nodeapp.conf

    echo "### Reloading nginx ..."
    docker-compose exec nginx nginx -s reload
}

function centos_install {
    function_name="centos_install"
    echo "==============================================================================="
    echo "                      BEGIN INSTALL ON CENTOS"
    echo "==============================================================================="
    logger $function_name "Installing yum-utils"
    sudo yum install -y yum-utils

    sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    sudo yum install -y docker-ce docker-ce-cli containerd.io
    logger $function_name "Installing docker-compose"
    sudo curl -L "https://github.com/docker/compose/releases/download/1.29.2/docker-compose-$(uname -s)-$(uname -m)" -o /usr/bin/docker-compose
    logger $function_name "Giving exacutable permissions to docker-compose"
    sudo chmod +x /usr/bin/docker-compose
    logger $function_name "Enabling Docker as a service"
    sudo systemctl enable docker
    logger $function_name "Starting Docker service"
    sudo systemctl start docker
    
    logger $function_name "Installing Nodejs 12"
    curl -sL https://rpm.nodesource.com/setup_12.x | sudo bash -
    sudo yum install -y nodejs
    cd $nodeapp_path
    npm init -y
    npm i
    cd $nginx_directory

    logger $function_name "Creating dhparam.pem with openssl"
    openssl dhparam -out ./config/nginx/dhparam.pem 2048

    logger $function_name "Changing the name of the website in ./config/nginx/sites-enabled/nodeapp.conf to $website_name"
    sed -i "s/website/$website_name/g" ./config/nginx/sites-available/nodeapp.conf
    sed -i "s/website/$website_name/g" ./config/nginx/sites-enabled/nodeapp.conf

    logger $function_name "Commenting out ssl configuration in ./config/nginx/sites-available/nodeapp for certbot"
    sed -i -r 's/(listen .*443)/\1; #/g; s/(ssl_(certificate|certificate_key|trusted_certificate) )/#;#\1/g; s/(server \{)/\1\n    ssl off;/g' ./config/nginx/sites-available/nodeapp.conf
    sed -i -r 's/(listen .*443)/\1; #/g; s/(ssl_(certificate|certificate_key|trusted_certificate) )/#;#\1/g; s/(server \{)/\1\n    ssl off;/g' ./config/nginx/sites-enabled/nodeapp.conf

    logger $function_name "Replacing nodeapp path in docker-compose.yml"
    sed -i -r "s/..\/nodeapp/..\/$nodeapp_path/g" ./config/nginx/sites-available/nodeapp.conf

    logger $function_name "Starting nodeapp with docker-compose"
    sudo docker-compose up --force-recreate -d nodeapp

    logger $function_name "Starting nginx with docker-compose"
    sudo docker-compose up --force-recreate -d nginx

    logger $function_name "Starting certbot with docker-compose and attempting to get an SSL certificate"
    sudo docker-compose run --rm --entrypoint="certbot certonly --webroot -w /var/www/letsencrypt --email $email_arg -d $domain_arg --rsa-key-size $rsa_key_size -n --agree-tos --force-renewal" certbot

    logger $function_name "Reenabling SSL options in ./config/ngnix/sites-enabled/nodeapp.con" 
    sed -i -r -z 's/#?; ?#//g; s/(server \{)\n    ssl off;/\1/g' ./config/nginx/sites-available/nodeapp.conf
    sed -i -r -z 's/#?; ?#//g; s/(server \{)\n    ssl off;/\1/g' ./config/nginx/sites-enabled/nodeapp.conf

    logger $function_name "Creating a service for docker-compose"
    sed -i "s/\/home\/temp_directory\/Node-On-Nginx/$nginx_directory/g" ./config/nginx/sites-available/nodeapp.conf
    sudo cp ./config/docker-compose.service /etc/systemd/system/multi-user.target.wants
    sudo systemctl enable docker-compose.service

    logger $function_name "Restarting nginx with docker-compose" 
    sudo docker-compose exec nginx nginx -s reload 

    echo "==============================================================================="
    echo "                      END INSTALL ON CENTOS"
    echo "==============================================================================="
}

if [ -f /etc/os-release ]; then
    # freedesktop.org and systemd
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID
    ID=$ID
elif type lsb_release >/dev/null 2>&1; then
    # linuxbase.org
    OS=$(lsb_release -si)
    VER=$(lsb_release -sr)
elif [ -f /etc/lsb-release ]; then
    # For some versions of Debian/Ubuntu without lsb_release command
    . /etc/lsb-release
    OS=$DISTRIB_ID
    VER=$DISTRIB_RELEASE
elif [ -f /etc/debian_version ]; then
    # Older Debian/Ubuntu/etc.
    OS=Debian
    VER=$(cat /etc/debian_version)
else
    # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
    OS=$(uname -s)
    VER=$(uname -r)
fi

if [ "$ID" == "arch" ] ; then
    arch_install
elif [ "$ID" == "centos" ] ; then
    centos_install
fi

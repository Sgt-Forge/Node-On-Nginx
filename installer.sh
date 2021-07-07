#!/bin/bash
# Don't include the ".com" at the end of the name
website_name="newname"
email_arg="email@example.com"
domain_arg="$website_name.com"
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
    docker-compose up --force-recreate -d nodeapp
    echo

    echo "### Starting nginx ..."
    docker-compose up --force-recreate -d nginx
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
    # sudo yum install -y yum-utils
    # sudo yum-config-manager --add-repo https://download.docker.com/linux/centos/docker-ce.repo
    # sudo yum install -y docker-ce docker-ce-cli containerd.io
    # sudo systemctl enable docker
    # sudo systemctl start docker
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

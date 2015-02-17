#!/usr/bin/env bash

# ---------------------------------- Create SSL Certification ----------------------------------
echo ">>> Creating & Installing SSL Certificate"

SSL_DIR="/etc/nginx/ssl"
PASSPHRASE="secret"

sudo mkdir -p "$SSL_DIR"

for i in `ls /etc/nginx/sites-available`
do
    DOMAIN=$i

SUBJ="
C=DO
ST=SantoDomingo
O=Eslabs
localityName=SantoDomingo
commonName=$DOMAIN
organizationalUnitName=HQ
emailAddress=development@esd.com.do
"

    sudo openssl genrsa -out "$SSL_DIR/$DOMAIN.key" 1024 >/dev/null 2>&1
    sudo openssl req -new -subj "$(echo -n "$SUBJ" | tr "\n" "/")" -key "$SSL_DIR/$DOMAIN.key" -out "$SSL_DIR/$DOMAIN.csr" -passin pass:$PASSPHRASE >/dev/null 2>&1
    sudo openssl x509 -req -days 365 -in "$SSL_DIR/$DOMAIN.csr" -signkey "$SSL_DIR/$DOMAIN.key" -out "$SSL_DIR/$DOMAIN.crt" >/dev/null 2>&1

    sed -i "/listen 80;/a \\\n    listen 443 ssl;\n    ssl_certificate /etc/nginx/ssl/$i.crt;\n    ssl_certificate_key /etc/nginx/ssl/$i.key;\n\n" /etc/nginx/sites-available/$i

done

service nginx restart
service php5-fpm restart

# --------------------------------------- Installing MongoDB ---------------------------------------
echo ">>> Installing MongoDB"

# Get key and add to sources
sudo apt-key adv --keyserver hkp://keyserver.ubuntu.com:80 --recv 7F0CEB10
echo 'deb http://downloads-distro.mongodb.org/repo/ubuntu-upstart dist 10gen' | sudo tee /etc/apt/sources.list.d/mongodb.list

# Update
sudo apt-get update

# Install MongoDB
# -qq implies -y --force-yes
sudo apt-get install -qq mongodb-org

# Make MongoDB connectable from outside world without SSH tunnel
if [ $1 == "true" ]; then
    # enable remote access
    # setting the mongodb bind_ip to allow connections from everywhere
    sed -i "s/bind_ip = */bind_ip = 0.0.0.0/" /etc/mongod.conf
fi

# Test if PHP is installed
php -v > /dev/null 2>&1
PHP_IS_INSTALLED=$?

if [ $PHP_IS_INSTALLED -eq 0 ]; then
    # install dependencies
    sudo apt-get -y install php-pear php5-dev

    # install php extension
    echo "no" > answers.txt
    sudo pecl install mongo < answers.txt
    rm answers.txt

    # add extension file and restart service
    echo 'extension=mongo.so' | sudo tee /etc/php5/mods-available/mongo.ini

    ln -s /etc/php5/mods-available/mongo.ini /etc/php5/fpm/conf.d/mongo.ini
    ln -s /etc/php5/mods-available/mongo.ini /etc/php5/cli/conf.d/mongo.ini
    sudo service php5-fpm restart
fi

ls

# ----------------------------------- Installing Elasticsearch -----------------------------------
echo ">>> Installing Elasticsearch"

# Set some variables
ELASTICSEARCH_VERSION=1.4.3 # Check http://www.elasticsearch.org/download/ for latest version

# Install prerequisite: Java
# -qq implies -y --force-yes
sudo apt-get install -qq openjdk-7-jre-headless

wget --quiet https://download.elasticsearch.org/elasticsearch/elasticsearch/elasticsearch-$ELASTICSEARCH_VERSION.deb
sudo dpkg -i elasticsearch-$ELASTICSEARCH_VERSION.deb
rm elasticsearch-$ELASTICSEARCH_VERSION.deb

# Configure Elasticsearch for development purposes (1 shard/no replicas, don't allow it to swap at all if it can run without swapping)
sudo sed -i "s/# index.number_of_shards: 1/index.number_of_shards: 1/" /etc/elasticsearch/elasticsearch.yml
sudo sed -i "s/# index.number_of_replicas: 0/index.number_of_replicas: 0/" /etc/elasticsearch/elasticsearch.yml
sudo sed -i "s/# bootstrap.mlockall: true/bootstrap.mlockall: true/" /etc/elasticsearch/elasticsearch.yml
sudo service elasticsearch restart

# Configure to start up Elasticsearch automatically
sudo update-rc.d elasticsearch defaults 95 10

# ---------------------------------- Disabling Postgresql Service ---------------------------------
echo ">>> Disable Postgresql"

sudo update-rc.d postgresql disable
sudo service postgresql stop

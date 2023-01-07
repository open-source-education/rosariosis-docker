

FROM ubuntu:18.04

ARG DEBIAN_FRONTEND=noninteractive

# set shell options (see documentation for more details)
RUN set -eux

# --fix-missing
RUN apt-get update
RUN apt-get install -y software-properties-common
RUN LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
# RUN apt-get update -y

RUN apt-get install -y curl
RUN apt-get install -y git
RUN apt-get install -y apache2 sendmail
RUN apt-get install -y php7.4 libapache2-mod-php7.4 php7.4-cli php7.4-common php7.4-mbstring php7.4-gd php7.4-intl php7.4-xml php7.4-mysql php7.4-mcrypt php7.4-zip

RUN php -v
# enable Apache2 rewrite module
RUN a2enmod rewrite

# set the work directory to /var/www/html (this is the webroot)
# when someone connects, this will be the starting-point
#COPY . /var/www/html
WORKDIR /var/www/
RUN git clone https://github.com/francoisjacquet/rosariosis.git -b v10.6.3
RUN rm -rf /var/www/rosariosis/.git
RUN rm -rf /var/www/html
RUN mv /var/www/rosariosis /var/www/html
RUN cp /var/www/html/config.inc.sample.php /var/www/html/config.inc.php
RUN find /var/www/

# enable env variables usage
ENV CONFIG_FILE=/var/www/html/config.inc.php
RUN sed -i "s/= 'postgresql'/= getenv('DB_ENGINE')/g"  $CONFIG_FILE
RUN sed -i "s/'localhost'/getenv('DB_HOST')/g"  $CONFIG_FILE
RUN sed -i "s/'username_here'/getenv('DB_USER')/g"  $CONFIG_FILE
RUN sed -i "s/'password_here'/getenv('DB_PASSWORD')/g"  $CONFIG_FILE
RUN sed -i "s/'database_name_here'/getenv('DB_NAME')/g"  $CONFIG_FILE
RUN sed -i "s/'en_US.utf8'/getenv('LOCALE')/g"  $CONFIG_FILE
RUN cat $CONFIG_FILE

WORKDIR /var/www/html

# copy the customized Apache2 vhost file from the project to the image
COPY ./000-default.conf /etc/apache2/sites-available/

# copy the custom startup-script into the image
COPY ./startup-script.sh /usr/local/bin/startup-script
RUN chmod +x /usr/local/bin/startup-script
RUN chmod 744 /usr/local/bin/startup-script

# fix warning : Could not reliably determine the server's fully qualified domain name ...
RUN echo "ServerName localhost" >> /etc/apache2/apache2.conf

# for other languages
RUN locale -a
RUN apt-get install language-pack-es

# database is already installed
RUN rm -rf /var/www/html/InstallDatabase.php

# allow read & write access
RUN chown www-data:www-data /var/www/html/ -R

CMD ["startup-script"]


# Choix de la distribution (e.g. debian, ubuntu...)
FROM debian:12.5

# Désactivation du mode intéractif
ENV DEBIAN_FRONTEND noninteractive

#Installation des dépendances, d'Apache2, des modules PHP8.3 et de ses extensions, et de Cron
RUN apt update \
&& apt install --yes ca-certificates apt-transport-https lsb-release wget curl \
&& curl -sSLo /usr/share/keyrings/deb.sury.org-php.gpg https://packages.sury.org/php/apt.gpg \ 
&& sh -c 'echo "deb [signed-by=/usr/share/keyrings/deb.sury.org-php.gpg] https://packages.sury.org/php/ $(lsb_release -sc) main" > /etc/apt/sources.list.d/php.list' \
&& apt update \
&& apt install --yes --no-install-recommends \
apache2 \
php8.3 \
php8.3-mysql \
php8.3-ldap \
php8.3-xmlrpc \
php8.3-imap \
php8.3-curl \
php8.3-gd \
php8.3-cli \
php8.3-mbstring \
php8.3-xml \
php-cas \
php8.3-intl \
php8.3-zip \
php8.3-bz2 \
php8.3-redis \
git \
unzip \
cron \
jq \
libldap-2.5-0 \
libldap-common \
libsasl2-2 \
libsasl2-modules \
libsasl2-modules-db \
&& curl -sS https://getcomposer.org/installer -o composer-setup.php \
&& php composer-setup.php --install-dir=/usr/local/bin --filename=composer \
&& rm -rf /var/lib/apt/lists/*

# Copie et execution du script pour l'installation de GLPI
COPY glpi_install.sh /opt/
RUN chmod +x /opt/glpi_install.sh
ENTRYPOINT ["/opt/glpi_install.sh"]

# Ouverture des ports 80 (HTTP) et 443 (HTTPS)
EXPOSE 80 443
#!/bin/bash

# Vérifie si la variable VERSION_GLPI est définie. Si non, récupère la dernière version de GLPI depuis GitHub
[[ ! "$VERSION_GLPI" ]] \
        && VERSION_GLPI=10.0.17

# Vérifie si la variable TIMEZONE est définie. Si non, affiche un message d'erreur
if [[ -z "${TIMEZONE}" ]]; then echo "TIMEZONE n'est pas renseignée"; 
else 
    # Définit le fuseau horaire pour PHP (Apache et CLI) en utilisant la valeur de TIMEZONE
    echo "date.timezone = \"$TIMEZONE\"" > /etc/php/8.3/apache2/conf.d/timezone.ini;
    echo "date.timezone = \"$TIMEZONE\"" > /etc/php/8.3/cli/conf.d/timezone.ini;
fi

# Active l'option session.cookie_httponly dans le fichier de configuration PHP pour Apache
sed -i 's,session.cookie_httponly = *\(on\|off\|true\|false\|0\|1\)\?,session.cookie_httponly = on,gi' /etc/php/8.3/apache2/php.ini

# Définition des dossiers pour GLPI et le répertoire web
FOLDER_GLPI=glpi/
FOLDER_WEB=/var/www/html/

# Vérifie si TLS_REQCERT est présent dans la configuration LDAP. Si non, l'ajoute avec la valeur "never"
if !(grep -q "TLS_REQCERT" /etc/ldap/ldap.conf)
then
        echo "TLS_REQCERT n'existe pas"
    echo -e "TLS_REQCERT\tnever" >> /etc/ldap/ldap.conf
fi

# Télécharge et extrait les sources de GLPI si elles ne sont pas déjà installées
if [ "$(ls ${FOLDER_WEB}${FOLDER_GLPI}/bin)" ];
then
        echo "GLPI est déjà installé"
else
    # Récupère l'URL de téléchargement de la version spécifiée de GLPI
        SRC_GLPI=$(curl -s https://api.github.com/repos/glpi-project/glpi/releases/tags/${VERSION_GLPI} | jq .assets[0].browser_download_url | tr -d \")
        TAR_GLPI=$(basename ${SRC_GLPI})

    # Télécharge l'archive de GLPI et l'extrait dans le répertoire web
        wget -P ${FOLDER_WEB} ${SRC_GLPI}
        tar -xzf ${FOLDER_WEB}${TAR_GLPI} -C ${FOLDER_WEB}
        rm -Rf ${FOLDER_WEB}${TAR_GLPI}
        chown -R www-data:www-data ${FOLDER_WEB}${FOLDER_GLPI}
fi

# Adapte la configuration du serveur Apache selon la version de GLPI installée
## Extraction de la version locale installée de GLPI
LOCAL_GLPI_VERSION=$(ls ${FOLDER_WEB}/${FOLDER_GLPI}/version)

## Extraction du numéro de version
LOCAL_GLPI_MAJOR_VERSION=$(echo $LOCAL_GLPI_VERSION | cut -d. -f1)

## Suppression des points (.) dans le numéro de version pour faciliter une comparaison
LOCAL_GLPI_VERSION_NUM=${LOCAL_GLPI_VERSION//./}

## Définition de la version cible de GLPI
TARGET_GLPI_VERSION="10.0.7"
TARGET_GLPI_VERSION_NUM=${TARGET_GLPI_VERSION//./}
TARGET_GLPI_MAJOR_VERSION=$(echo $TARGET_GLPI_VERSION | cut -d. -f1)

# Compare la version locale de GLPI avec la version cible et adapte la configuration d'Apache en conséquence
if [[ $LOCAL_GLPI_VERSION_NUM -lt $TARGET_GLPI_VERSION_NUM || $LOCAL_GLPI_MAJOR_VERSION -lt $TARGET_GLPI_MAJOR_VERSION ]]; then
    # Configuration pour les versions de GLPI inférieures à 10.0.7
  echo -e "<VirtualHost *:80>\n\tDocumentRoot /var/www/html/glpi\n\n\t<Directory /var/www/html/glpi>\n\t\tAllowOverride All\n\t\tOrder Allow,Deny\n\t\tAllow from all\n\t</Directory>\n\n\tErrorLog /var/log/apache2/error-glpi.log\n\tLogLevel warn\n\tCustomLog /var/log/apache2/access-glpi.log combined\n</VirtualHost>" > /etc/apache2/sites-available/000-default.conf
else
    # Configuration pour les versions de GLPI 10.0.7 et supérieures
  set +H
  echo -e "<VirtualHost *:80>\n\tDocumentRoot /var/www/html/glpi/public\n\n\t<Directory /var/www/html/glpi/public>\n\t\tRequire all granted\n\t\tRewriteEngine On\n\t\tRewriteCond %{REQUEST_FILENAME} !-f\n\t\n\t\tRewriteRule ^(.*)$ index.php [QSA,L]\n\t</Directory>\n\n\tErrorLog /var/log/apache2/error-glpi.log\n\tLogLevel warn\n\tCustomLog /var/log/apache2/access-glpi.log combined\n</VirtualHost>" > /etc/apache2/sites-available/000-default.conf
fi

# Ajoute une tâche planifiée (cron) pour exécuter le script de cron de GLPI toutes les 2 minutes
echo "*/2 * * * * www-data /usr/bin/php /var/www/html/glpi/front/cron.php &>/dev/null" > /etc/cron.d/glpi

# Démarre le service cron.
service cron start

# Active le module rewrite d'Apache et redémarre le service Apache
a2enmod rewrite && service apache2 restart && service apache2 stop

# Force l'arrêt d'Apache pour s'assurer qu'il est bien arrêté
pkill -9 apache

# Lance le service Apache au premier plan.
/usr/sbin/apache2ctl -D FOREGROUND
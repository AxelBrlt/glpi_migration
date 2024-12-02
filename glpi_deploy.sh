#!/bin/bash

# Installe et configure Docker, puis crée et déploie GLPI via Docker Compose.
# Configure MariaDB en chargeant les variables depuis un fichier d'environnement.
# Gère les migrations et l'importation de sauvegardes SQL pour GLPI.

# Variables
GLPI_IMAGE_NAME="company-glpi"
GLPI_DOCKERFILE="Dockerfile"
DOCKER_COMPOSE_FILE="docker-compose.yml"
MARIADB_CONTAINER_NAME="mariadb"
GLPI_CONTAINER_NAME="glpi"
LOCAL_TEMP_DIR="/tmp/glpi_backup"

backup_remote_db() {
  sudo mkdir -p "$LOCAL_TEMP_DIR"

  # Demande les informations nécessaires à l'utilisateur
  read -p "Adresse IP du serveur MVLGLPI01 : " REMOTE_SERVER
  read -p "Nom de la base de données distante : " REMOTE_DB_NAME
  read -sp "Mot de passe de la base de données distante : " REMOTE_DB_PASSWORD
  echo "Munissez-vous du mot de passe SSH de MVLGLPI01 sur le KeyPass..."
  sleep 3

  DUMP_FILE="/tmp/$REMOTE_DB_NAME.sql"

  # Crée un dump de la base de données distante via SSH
  echo "Création du dump de la base de données distante..."
  ssh "root@$REMOTE_SERVER" "mysqldump -u root -p$REMOTE_DB_PASSWORD $REMOTE_DB_NAME > $DUMP_FILE"

  # Vérifie si la commande s'est bien exécutée
  if [ $? -ne 0 ]; then
    echo "Erreur lors de la création du dump."
    return 1
  fi

  # Transfert du dump vers le serveur local
  echo "Transfert du dump vers le serveur local..."
  sudo scp "root@$REMOTE_SERVER:$DUMP_FILE" $LOCAL_TEMP_DIR

  # Vérifie si le transfert a réussi
  if [ $? -ne 0 ]; then
    echo "Échec du transfert du dump."
    return 1
  fi

  # Définit la variable SQL_BACKUP_PATH avec le chemin du fichier de sauvegarde transféré
  SQL_BACKUP_PATH="$LOCAL_TEMP_DIR/$REMOTE_DB_NAME.sql"
  echo "Le dump a été transféré avec succès et est maintenant disponible à ${SQL_BACKUP_PATH}."
}

configure_mariadb() {
    # Vérifie si le fichier mariadb.env existe et le charge
    if [ -f "mariadb.env" ]; then
        # Charge les variables depuis le fichier
        source mariadb.env
    else
        echo "Le fichier mariadb.env est introuvable. Veuillez vérifier qu'il existe."
        return
    fi

    # Vérifie que les variables nécessaires sont définies
    if [ -z "$MARIADB_ROOT_PASSWORD" ] || [ -z "$MARIADB_DATABASE" ] || [ -z "$MARIADB_USER" ] || [ -z "$MARIADB_PASSWORD" ]; then
        echo "Certaines variables dans mariadb.env sont manquantes. Veuillez vérifier les valeurs."
        return
    fi

    # Écrit ces valeurs dans le fichier mariadb.env
    echo "Configuration de MariaDB avec les variables chargées."
    echo "MARIADB_ROOT_PASSWORD=$MARIADB_ROOT_PASSWORD"
    echo "MARIADB_DATABASE=$MARIADB_DATABASE"
    echo "MARIADB_USER=$MARIADB_USER"
    echo "MARIADB_PASSWORD=$MARIADB_PASSWORD"
}

# Installe Docker Engine
install_docker() {
  echo "Docker n'est pas installé. Installation de Docker Engine..."

  # Met à jour les paquets
  sudo apt-get update

  # Installe les dépendances permettant d'utiliser le dépôt de Docker
  sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

  # Ajoute la clé GPG officielle de Docker
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc

  # Configure le dépôt de Docker
    echo \
        "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
        $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

  # Met à jour les paquets avec le dépôt de Docker
  sudo apt-get update

  # Installe Docker Engine, CLI et containerd
  sudo apt-get install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

  # Démarre le service Docker et configure son démarrage automatique
  sudo systemctl start docker
  sudo systemctl enable docker

  echo "Docker Engine s'est installé avec succès."
}

# Vérifie si Docker est installé.
check_docker() {
  if ! command -v docker > /dev/null 2>&1; then
    echo "Docker n'est pas installé. Lancement de l'installation..."
    install_docker

  # Vérifie si Docker est en cours d'exécution
  elif ! sudo systemctl is-active --quiet docker; then
    echo "Docker est installé mais ne fonctionne pas. Tentative de démarrage du service Docker..."
    sudo systemctl start docker
    if ! sudo systemctl is-active --quiet docker; then
      echo "Impossible de démarrer Docker. Veuillez vérifier l'état du service."
      return
    else
      echo "Docker a été démarré avec succès."
    fi
  else
    echo "Docker est déjà installé et en cours d'exécution."
  fi
}

# Construit l'image Docker de GLPI
build_glpi_image() {
  echo "Construction de l'image Docker GLPI..."
  sudo docker build -t $GLPI_IMAGE_NAME -f $GLPI_DOCKERFILE .
  if [ $? -ne 0 ]; then
    echo "Échec de la construction de l'image Docker GLPI. Veuillez vérifier le Dockerfile."
    return
  fi
  echo "Image Docker GLPI construite avec succès."
}

# Démarre le déploiemment avec Docker Compose
start_docker_compose() {
  echo "Démarrage du déploiement Docker Compose..."
  sudo docker compose up -d
  if [ $? -ne 0 ]; then
    echo "Échec du démarrage des services Docker Compose. Veuillez vérifier le fichier docker-compose.yml."
    return
  fi
  echo "Le stack a été démarré avec succès."
}

import_sql_backup() {
# Importe la sauvegarde directement dans la base de données du conteneur MariaDB
  # Vérifie si le fichier de sauvegarde existe
  if [ -f "$SQL_BACKUP_PATH" ]; then
    SQL_BASENAME=$(basename "$SQL_BACKUP_PATH")
    # Copie et importe le fichier de sauvegarde dans le conteneur MariaDB
    echo "Copie et importation de la sauvegarde dans la base de données '$MARIADB_DATABASE' (Cela peut prendre du temps)..."
    sudo docker cp "$SQL_BACKUP_PATH" "$MARIADB_CONTAINER_NAME:/tmp/"
    sleep 10
    echo "Veuillez patienter..."
    sleep 10
    sudo docker exec -i "$MARIADB_CONTAINER_NAME" bash -c "mariadb -u root -p"$MARIADB_ROOT_PASSWORD" "$MARIADB_DATABASE" < "/tmp/$SQL_BASENAME""

    if [ $? -ne 0 ]; then
      echo "Erreur : Échec de la copie ou de l'importation de la sauvegarde."
      return 1
    else
      echo "Importation réussie."
    fi
  else
    echo "Erreur : Le fichier spécifié '$SQL_BACKUP_PATH' n'existe pas."
    return 1
  fi
}

# Exécute les commandes SQL suivantes à l'intérieur du conteneur MariaDB
execute_sql_command() {
  ## Désactive temporairement les contrôles des clés étrangères
  ## Supprime une table spécifiée si elle existe déjà
  ## Réactive les contrôles des clés étrangères
  local sql_command="
  SET FOREIGN_KEY_CHECKS = 0;
  DROP TABLE IF EXISTS table_name;
  SET FOREIGN_KEY_CHECKS = 1;
  "
  echo "Exécution de la commande à l'intérieur du conteneur MariaDB..."
  sudo docker exec -i $MARIADB_CONTAINER_NAME mariadb -u root -p$MARIADB_ROOT_PASSWORD $MARIADB_DATABASE -e "$sql_command"
}

# Transfére les dossiers 'config' et 'files'
transfer_glpi_folders() {
  echo "Transfert du dossier 'config' depuis le serveur $REMOTE_SERVER..."
  sudo scp -q -r "root@$REMOTE_SERVER:/var/www/glpi_it/config" "$LOCAL_TEMP_DIR"
  if [ $? -eq 0 ]; then
    echo "Dossier 'config' transféré avec succès."
    sudo docker cp "$LOCAL_TEMP_DIR/config" $GLPI_CONTAINER_NAME:/var/www/html/glpi/
    echo "Dossier 'config' copié dans le conteneur GLPI."
  else
    echo "Échec du transfert du dossier 'config'."
  fi

  echo "Transfert du dossier 'files' depuis le serveur $REMOTE_SERVER... (Cela peut prendre un moment...)"
  sudo scp -q -r "root@$REMOTE_SERVER:/var/www/glpi_it/files" "$LOCAL_TEMP_DIR"
  if [ $? -eq 0 ]; then
    echo "Dossier 'files' transféré avec succès."
    sudo docker cp "$LOCAL_TEMP_DIR/files" $GLPI_CONTAINER_NAME:/var/www/html/glpi/
    echo "Dossier 'files' copié dans le conteneur GLPI."
  else
    echo "Échec du transfert du dossier 'files'."
  fi

  echo "Nettoyage du répertoire temporaire..."
  sudo rm -rf "$LOCAL_TEMP_DIR"
}

# Exécute les migrations à l'intérieur du conteneur GLPI
glpi_migrations() {
  echo "Exécution des migrations GLPI à l'intérieur du conteneur GLPI..."

  # Octroie les droits au répertoire de GLPI
  sleep 2
  sudo docker exec -i $GLPI_CONTAINER_NAME bash -c "chown -R www-data:www-data /var/www/html/glpi"

  # Renseigne les identifiants de $MARIADB_DATABASE pour GLPI
  sleep 2
  sudo docker exec -i $GLPI_CONTAINER_NAME bash -c "cd /var/www/html/glpi && php bin/console db:install -r -n -L fr_FR -H $MARIADB_CONTAINER_NAME -d $MARIADB_DATABASE -u $MARIADB_USER -p $MARIADB_PASSWORD"

  # Exécute la mise à jour de $MARIADB_DATABASE
  sleep 2
  sudo docker exec -i $GLPI_CONTAINER_NAME bash -c "cd /var/www/html/glpi && php bin/console db:update --no-telemetry -n -s -f"

  # Exécute la migration utf8mb4
  sleep 2
  sudo docker exec -i $GLPI_CONTAINER_NAME bash -c "cd /var/www/html/glpi && php bin/console migration:utf8mb4 --no-interaction"

  # Exécute la migration unsigned_keys
  sleep 2
  sudo docker exec -i $GLPI_CONTAINER_NAME bash -c "cd /var/www/html/glpi && php bin/console migration:unsigned_keys --no-interaction"

  # Défini une nouvelle clé de chiffrement
  sleep 2
  sudo docker exec -i $GLPI_CONTAINER_NAME bash -c "cd /var/www/html/glpi && php bin/console glpi:security:change_key --no interaction"

  # Octroie les droits au répertoire de GLPI une dernière fois pour être sûr.
  sleep 2
  sudo docker exec -i $GLPI_CONTAINER_NAME bash -c "chown -R www-data:www-data /var/www/html/glpi"

  # Supprime le fichier d'installation 'install.php'
  sleep 2
  sudo docker exec -i $GLPI_CONTAINER_NAME bash -c "cd /var/www/html/glpi && rm -Rf install/install.php"
}

glpi_success_message() {
  sleep 3
  clear
  echo "Vous avez mis à jour GLPI avec succès, vous pouvez désormais vous y connecter à l'adresse http://<server-ip>/"
  echo "Connectez-vous avec l'utilisateur <glpi> avec le mot de passe disponible dans le KeyPass et synchronisez GLPI avec l'Active Directory."
  echo "Référencez-vous sur le OneNote 'Serveurs > GLPI - Mise à jour' pour configurer notre instance de GLPI."
  read -p "Appuyez sur une touche pour continuer..."
}

# Exécution principale
main() {
  backup_remote_db
  configure_mariadb
  check_docker
  build_glpi_image
  start_docker_compose
  import_sql_backup
  execute_sql_command
  transfer_glpi_folders
  glpi_migrations
  glpi_success_message
}

# Démarre l'exécution principale.
main
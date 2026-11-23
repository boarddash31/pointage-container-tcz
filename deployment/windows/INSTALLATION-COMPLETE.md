# Runtime complet — Zenata Port Sec

Version : **zps-shift-reports-20261120**. Cible : **http://172.17.18.208:9091/**.

Le paquet comprend le moteur Node portable 22.14.0 signé OpenJS, l’interface web compilée, le serveur HTTP, les logs et la rubrique administrateur Rapports programmés. Flutter, IIS et Java ne sont pas nécessaires pour démarrer cette interface. Les données et les comptes utilisent encore Supabase ZENATA : ce paquet ne termine pas la migration vers SQL Server et n’inclut pas le connecteur JMS Java.

## Intégrer sur le serveur 208

1. Transférer cette archive sur **172.17.18.208** puis l’extraire dans un dossier temporaire.
2. Arrêter l’ancien runtime avec **Ctrl+C**. Sauvegarder son dossier d’installation, notamment **`.state`**, **`runtime.env`** et **`logs`**, s’ils existent. Ne jamais remplacer ou perdre la clé `smtp-master.key` d’une installation existante.
3. Copier les fichiers extraits dans le dossier du runtime, par exemple **`C:\Apps\ZenataRuntime`**. Remplacer les fichiers livrés et le dossier **`web`** par ceux de cette version. Conserver les dossiers privés et la configuration existante. L’archive ne contient aucune configuration secrète ni données de production.
4. Lancer **`LANCER-9091.cmd`**, situé à côté de **`node.exe`**, **`http-runtime.cjs`**, **`reports`** et **`web`**.
5. Ouvrir **http://172.17.18.208:9091/**, puis se connecter avec son compte habituel. Vérifier **http://172.17.18.208:9091/release.json** : `release` doit être `zps-shift-reports-20261120`.

Le compte d’exécution doit pouvoir écrire dans les dossiers privés `.state` et `logs`, hors de `web`. Faire autoriser TCP **9091** par l’IT depuis les postes concernés. Le lanceur n’installe aucun service et ne modifie pas le pare-feu. Pour les tâches programmées, maintenir le processus actif et prévoir un démarrage supervisé avec l’IT ; une session RDP ouverte ne remplace pas cette supervision.

## Rapports et envois e-mail

La rubrique **Rapports → Configuration e-mail** permet de renseigner plus tard le serveur SMTP, le port, l’expéditeur et les identifiants éventuels. Les aperçus Excel et les brouillons sont disponibles avant activation des envois.

**Prérequis e-mail restant :** le paquet ne contient pas Nodemailer, dont le téléchargement a été bloqué par le proxy de l’entreprise. L’IT doit fournir **Nodemailer 10.6.1** via son circuit approuvé dans `reports/node_modules/nodemailer`. La version et l’intégrité attendues sont fixées dans `reports/package-lock.json`. Aucun contournement du blocage n’est prévu.

L’IT doit également copier **`runtime.env.example`** en **`runtime.env`** et configurer `REPORTS_SUPABASE_SECRET_KEY` avec la clé serveur du seul projet ZENATA. Conserver ce fichier hors de `web`, limiter ses droits NTFS et ne jamais communiquer sa valeur dans le chat. Redémarrer le runtime après modification. Ne pas remplacer un `runtime.env` déjà configuré par l’exemple vide.

Les envois restent désactivés tant que ces prérequis et le SMTP ne sont pas configurés. La notice détaillée **`INSTALLATION-RAPPORTS.md`** explique les calendriers, les états, les sauvegardes, la protection des paramètres SMTP sur l’accès HTTP et les limites des données. Les événements applicatifs sont écrits dans `logs/zenata-*.jsonl` ; les paramètres, tâches et pièces jointes sont dans `.state/reports/`.

## Vérifications après intégration

- Connexion, rôles, recherche Data, entrée/sortie et impression des bons.
- Avec un administrateur : ouvrir Rapports et télécharger un aperçu Excel avant tout envoi réel.
- Une fois le relais et la clé configurés : vérifier le SMTP sans e-mail puis effectuer un envoi de recette vers une adresse autorisée et contrôler l’historique.

Les comptes et les règles backend ne sont pas modifiés par la copie de cette archive. Les migrations métier ops et les fonctions PDF distantes nécessitent leur activation séparée si elle n’a pas déjà été effectuée.

En cas de problème, arrêter cette version et restaurer la sauvegarde de l’installation, en conservant ensemble la base privée et sa clé de chiffrement. Aucun déploiement distant n’est effectué par la préparation du paquet.

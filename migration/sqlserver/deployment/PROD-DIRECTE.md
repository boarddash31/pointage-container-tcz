# Mise à jour directe du socle SQL toszps

Choix explicite du propriétaire : passer directement sur la base cible sans créer `toszps_Test`. La compilation et les contrôles locaux du lot Gate ont été déclarés réussis sur208 ; **les neuf scénarios SQL de recette n’ont pas été exécutés**. Ce paquet prépare uniquement la mise à jour du schéma, pas la bascule de l’application ni un import.

## Action dans DBeaver

1. Extraire le paquet dans un nouveau dossier. Ouvrir une **nouvelle connexion en auto-commit** à `PRD-DB-ZENATA\MMSQL01`, port54013, base active **toszps**, avec le compte de déploiement propriétaire.
2. Ouvrir **APPLIQUER_GATE_PROD_DBEAVER.sql**. Sélectionner tout puis **Ctrl+Entrée** pour envoyer le bloc en une seule exécution. Il ne nécessite ni SQLCMD ni chemin de fichiers locaux.
3. Le script vérifie la cible et les versions1/2/3, puis crée une sauvegarde complète **COPY_ONLY avec CHECKSUM** dans le répertoire de sauvegarde par défaut de l’instance SQL. Le nom du fichier contient un UUID pour ne pas écraser une sauvegarde existante. Il ne change pas le modèle de récupération ni la collation.
4. La sauvegarde est écrite sur le **serveur SQL209**, pas sur le poste DBeaver ou le serveur208. Son chemin est retourné dans un résultat : le conserver. Si le répertoire par défaut est inaccessible, demander sa configuration à l’IT ; le script s’arrête avant le changement de schéma. Le rôle `db_owner` dispose normalement du droit BACKUP ; le compte de service SQL doit pouvoir écrire dans ce dossier.
5. Si la sauvegarde réussit, la version4 est appliquée sous transaction. Le résultat final attendu est **GATE VERSION4 INSTALLEE - application non basculee**. Une erreur indique l’étape et annule la transaction de schéma si elle est ouverte. En cas de déconnexion/annulation, fermer la session puis vérifier les versions depuis une nouvelle connexion avant de relancer.

Aucune restauration n’est exécutée ou testée par le paquet. La sauvegarde et les transactions n’attestent pas de la correction des règles métier ; la recette a été différée au choix du propriétaire. Le script n’ajoute aucun profil fictif, aucune commande de suppression de tables ni aucun transfert de données. Il refuse de rejouer une version4 déjà installée.

## Après le succès

L’application sur9091 continue de fonctionner avec Supabase. Le raccordement de Flutter, les PDF, Data, CODECO, les rapports et la reprise complète des données restent à terminer. Les anciens outils de transfert à22tables ne doivent pas être utilisés pour cette destination version4 ; le manifeste doit intégrer les blocages et détails opérationnels. Ne pas modifier simplement une chaîne de connexion du runtime pour tenter une bascule.

Références : [sauvegarde et permissions SQL](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/create-a-full-database-backup-sql-server?view=sql-server-ver17), [répertoire de sauvegarde de l’instance](https://learn.microsoft.com/en-us/sql/t-sql/functions/serverproperty-transact-sql?view=sql-server-ver17).

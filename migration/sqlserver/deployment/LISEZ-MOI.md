# Premier déploiement du socle SQL — 21 novembre 2026

**Destination confirmée par l’IT :** `PRD-DB-ZENATA\MMSQL01`, TCP **54013**, base **toszps**, compte de déploiement SQL **toszps** avec `db_owner`. Le nom résout vers **172.17.18.209** depuis le poste de préparation ; le port répond. La connexion SQL authentifiée et les scripts T-SQL n’ont pas été exécutés sur cette instance par la préparation du paquet.

## Étape 1 — connexion et diagnostic sans modification

**Correction v3 :** le diagnostic transmis par l’utilisateur affiche `toszps`, `PRD-DB-ZENATA\MMSQL01`, `-11523`, `TCP`. La valeur négative correspond exactement au port **54013** dans une représentation signée 16 bits (`-11523 + 65536`). Les deux scripts de contrôle conservent le port brut et normalisent uniquement les valeurs de **-32768 à -1** avant comparaison stricte à 54013. Les autres ports et une valeur NULL restent refusés. Le composant à l’origine de cette représentation n’a pas été établi ; aucune reconfiguration de SQL Server ou du pare-feu n’est demandée pour corriger l’affichage.

Si le contrôle signale un port inattendu, exécuter **00_DIAGNOSTIC_RESEAU.sql** dans la même connexion. Il affiche la base, l’instance, le transport et le port vu côté SQL Server. `local_tcp_port` est nullable : une valeur NULL ne signifie pas que le port 54013 est fermé. Un port serveur différent du port saisi côté client peut nécessiter une vérification de redirection avec l’IT. Les gardes d’initialisation restent actifs jusqu’à résolution ; ne pas les supprimer. [Propriétés de connexion Microsoft](https://learn.microsoft.com/en-us/sql/t-sql/functions/connectionproperty-transact-sql?view=sql-server-ver17).

Depuis le serveur applicatif **172.17.18.208**, ouvrir **SSMS**. Serveur : **`tcp:PRD-DB-ZENATA,54013`** (le port fixe cible l’instance sans dépendre de SQL Browser). Choisir l’authentification SQL Server, utilisateur **toszps**, et saisir le mot de passe uniquement dans SSMS. Sélectionner la base **toszps** dans les propriétés de connexion. Ne pas enregistrer le mot de passe dans le script ou l’archive.

Pour la connexion SQL, demander le chiffrement obligatoire et valider le certificat fourni par l’IT. Si le certificat n’est pas reconnu ou ne correspond pas au nom, faire préciser le FQDN/certificat approuvé ; ne pas désactiver sa vérification. L’accès HTTP actuel au site sur 208 est indépendant du chiffrement de la connexion SQL.

Ouvrir **00_CONTROLE_CONNEXION.sql**, vérifier la base sélectionnée puis exécuter. Ce fichier est en lecture seule : instance, port, version, droits, compatibilité et présence éventuelle de tables. Il ne prouve pas que tous les correctifs SQL sont installés et ne lit aucune ligne métier. Conserver les résultats pour la recette. Si les coordonnées diffèrent ou si des tables existent déjà, arrêter l’initialisation et examiner l’état avec le DBA.

## Étape 2 — initialisation d’une base vide

**Correction v5 pour une base French_CI_AS :** les colonnes texte renvoyées par `api.parse_items` depuis le JSON sont explicitement alignées sur `Latin1_General_100_BIN2`, comme les identifiants armateur/ISO des tables qu’elles rejoignent. La collation globale de **toszps** n’est pas modifiée. Le script DBeaver conserve l’annulation en cas d’erreur et indique désormais le fichier/lot, la procédure, la ligne et le numéro SQL d’origine dans son message. Les tests d’ordres existants sont prévus dans l’exemple CI privé pour les deux collations (exemple inactif, non exécuté ici). Avant relance, ouvrir une nouvelle session et vérifier que l’échec précédent n’a laissé aucune table ; si des tables existent, ne pas les supprimer et faire examiner l’état.

### Option DBeaver (paquet v4)

Si SSMS n’est pas disponible, utiliser **01_INITIALISER_SOCLE_DBEAVER.sql**. Ce fichier unique contient les mêmes sources de schéma, ordres et comptes, embarquées dans des lots SQL fixes. Il ne nécessite ni SQLCMD ni chemins d’inclusion. Les gardes de cible, port normalisé, base vide, droits et compatibilité sont conservés.

Après la sauvegarde DBA, ouvrir une **nouvelle session SQL** sur **toszps**, en mode auto-commit sans transaction déjà ouverte. Ouvrir le fichier, sélectionner **tout son contenu (Ctrl+A)** puis **exécuter la sélection en une fois (Ctrl+Entrée)**. Le bloc gère sa propre transaction SQL et son TRY/CATCH ; en cas d’erreur interceptée, il annule et renvoie l’erreur. En cas de déconnexion/annulation, fermer la session pour ne pas laisser de transaction ouverte, puis contrôler l’état depuis une nouvelle connexion avant toute relance. Ne pas exécuter les instructions une par une. Un succès termine par `SOCLE INITIAL CREE ET VALIDE : application encore sur Supabase`.

Ce fichier est généré depuis les trois SQL locaux ; son exécution réelle sur votre SQL Server reste à valider. Aucun mot de passe ni données ne sont intégrés. Cette option remplace uniquement le lancement du script SQLCMD ; elle ne remplace pas les validations IT ni le portage restant de l’application. [Exécution d’une sélection dans DBeaver](https://dbeaver.com/docs/dbeaver/SQL-Execution/).

### Option SSMS / SQLCMD

Cette étape **crée uniquement le premier socle préparé** : 22 tables métier, comptes/sessions locaux et premières procédures EDO/ERO. **Elle n’achève pas le portage des règles récentes et ne rend pas le runtime actuel compatible SQL Server.** Le schéma, l’API et les outils étaient préparés localement ; les contrôles SQL d’intégration nécessitent encore SQL Server/.NET sur la machine de validation IT.

1. Faire effectuer et vérifier par le DBA la sauvegarde initiale de **toszps**, avec un chemin de sauvegarde autorisé et une procédure de restauration. Le dossier de sauvegarde est situé côté serveur SQL, pas sur 208. Ne pas changer le modèle de récupération ni la rétention automatiquement.
2. Extraire le dossier **ZENATA-SQL-20261121** dans **C:\Temp**, ou adapter `PackageRoot` en tête du script.
3. Ouvrir **01_INITIALISER_SOCLE.sql** dans une **nouvelle fenêtre SSMS**, connexion TCP approuvée. Activer **Requête → Mode SQLCMD**. Exécuter le fichier complet, sans sélectionner seulement certaines lignes.
4. Le script refuse une autre machine/instance/base/port, une base non vide ou un niveau de compatibilité différent de 170. Il n’exécute ni DROP, ni import, ni test fictif, ni création de login SQL, ni création de compte applicatif. Ne pas enlever ces gardes pour forcer une relance.
5. Les trois fichiers sont exécutés sous une transaction externe. En cas d’erreur, arrêter et fermer cette connexion afin d’annuler toute transaction ouverte. Ne pas poursuivre manuellement les fichiers suivants. Ouvrir une nouvelle connexion et contrôler l’état avant nouvelle tentative. Les scripts ne sont pas des mises à niveau d’un socle existant.
6. Après succès, **02_VERIFIER_SOCLE.sql** contrôle les versions 1/2/3 et les procédures attendues. **Ne pas exécuter les tests `_Test` dans toszps.** Ils sont réservés à une base de recette séparée et vide.

Ce lot ne requiert pas le SDK .NET pour ouvrir les SQL dans SSMS. La compilation et la validation de l’API/importeur nécessitent le **SDK .NET 10**, fourni par l’IT via son circuit autorisé : il est absent du poste de préparation et son ancien téléchargement a été bloqué par la politique d’entreprise. Aucun contournement n’est tenté.

## Après le socle, avant tout transfert réel ou bascule

- Mettre à jour le schéma et le manifeste de transfert pour les derniers détails opérationnels et blocages de conteneurs. Les RPC Gate entrée/sortie, restitution double et clôture automatique, annulation et rapprochement doivent être portés et testés. Le garde 24 h initial ne remplace pas ce portage complet.
- Adapter l’API et Flutter : comptes, sessions, Data, génération/archive/téléchargement PDF, tableau superviseur, CODECO et rapports. Les rapports planifiés actuels utilisent encore une lecture Supabase et une persistance locale privée ; ces éléments sont à inclure dans le plan de bascule.
- Valider sur une base de recette distincte le schéma courant, les procédures, les droits et les imports. Le lot ne contient aucune donnée de production ni mot de passe. Ne pas exporter/importer les données réelles avec le manifeste antérieur tant que les écarts de schéma ne sont pas traités.
- Organiser un export cohérent, transférer les fichiers PDF séparément, rapprocher comptes/lignes/quantités/stock et préparer les comptes locaux. Les anciens mots de passe Supabase ne sont pas repris. Le premier Admin sera initialisé par l’outil sécurisé après import et validation.
- Pour le futur backend, demander un **compte d’exécution distinct**, membre du rôle `pointage_api`, sans `db_owner`. Le compte propriétaire **toszps** convient au déploiement mais ne doit pas devenir le compte courant de l’application. Sa création et son affectation ne sont pas exécutées par ce lot.
- Conserver l’environnement actuel pendant la recette et prévoir sauvegarde/retour arrière avant la fenêtre de bascule. Ne pas changer la configuration de l’application vers SQL Server à ce stade.

Références : [connexion sqlcmd et instance nommée](https://learn.microsoft.com/en-us/sql/tools/sqlcmd/sqlcmd-use-utility?view=sql-server-ver17), [sauvegarde complète SQL Server](https://learn.microsoft.com/en-us/sql/relational-databases/backup-restore/create-a-full-database-backup-sql-server?view=sql-server-ver17). La recette SSMS reste nécessaire même si les contrôles locaux de conversion et d’intégrité du paquet passent.

# Transfert ZENATA : préparation du schéma et des identifiants

Le diagnostic .NET sur 208 réussit avec authentification SQL et lecture de `toszps`, instance `MMSQL01`, version 4. Ce mode chiffre le trafic mais ne vérifie pas le certificat. Il ne configure pas le backend de production. Les versions 1 à 4 sont déjà installées : ne pas rejouer leur initialisation.

La structure de la source ZENATA `iparzfqxopcvwqelxlad` a été relue le 21/11/2026, sans lecture des lignes métier. Elle contient 22 tables, avec un nouveau champ `public.profiles.username` absent du socle SQL initial. Le complément 011 le conserve dans `dbo.profiles.username`. Il s'agit de métadonnées historiques ; la connexion continue d'utiliser les comptes créés par l'Admin dans `internal.local_accounts`. Aucun compte ou mot de passe n'est créé ou copié par cette étape.

La source n'a actuellement ni `operational_details` ni `container_blocks`. Le transfert conserve les 22 tables et les identifiants ; les détails opérationnels des visites historiques prennent `{}` et les blocages restent vides. Tout ajout ultérieur de table, colonne, changement de type ou de nullabilité arrête l'export jusqu'à mise à jour du manifeste. Les mots de passe Supabase et `profiles.initial_password` sont exclus.

## Utilisation du paquet sur208

1. Extraire dans un nouveau dossier de `C:\Temp`, séparé du runtime9091.
2. Lancer `VALIDER-TRANSFERT.cmd`. Il compile uniquement l'importeur et vérifie un transfert fictif, sans appeler les bases. Résultat attendu : `VALIDATION TRANSFERT V5 REUSSIE - AUCUNE CONNEXION BASE`. Cette nouvelle compilation reste à réaliser sur208.
3. Dans DBeaver, connexion à `PRD-DB-ZENATA:54013`, sélectionner `toszps`, ouvrir une nouvelle session en auto-commit puis `SQL/14_COMPLETER_IDENTIFIANTS_DBEAVER.sql`. Sélectionner tout et exécuter avec `Ctrl+A`, puis `Ctrl+Entrée`.

Le SQL vérifie la cible et les versions, effectue une sauvegarde `COPY_ONLY` avec `CHECKSUM` sur209, puis ajoute une colonne nullable dans une transaction et enregistre la version5. En cas d'échec de sauvegarde, aucun changement de schéma. Conserver le chemin `.bak` affiché ; la restauration n'a pas été testée. Aucun import ni démarrage d'API dans ce script. Ne pas le rejouer s'il affiche `COMPLEMENT IDENTIFIANTS VERSION5 INSTALLE`.

## Transfert réel et bascule, à effectuer ensuite

Depuis une machine de migration autorisée, les outils du dépôt acceptent désormais explicitement le nouveau manifeste :

```text
node migration/sqlserver/tools/export-source.cjs --out .migration-data/snapshot-FINAL --manifest v5
```

La connexion PostgreSQL se configure localement dans `POINTAGE_SOURCE_CONNECTION`, jamais dans le chat ou les arguments. L'export utilise une seule transaction en lecture seule et vérifie le catalogue avant de sélectionner les colonnes. Aucun export réel n'a été exécuté lors de la préparation.

Depuis `backend/`, le contrôle des fichiers réels reste sans connexion à SQL :

```text
dotnet run --project Pointage.Migration -c Release -- --snapshot ../.migration-data/snapshot-FINAL --check --manifest v5
```

Le mode `--apply` est une étape distincte d'écriture. Il exige la version5, toutes les tables métier vides, aucun compte local, aucune session et aucun blocage préexistant. Il vérifie les empreintes, charge dans l'ordre des clés étrangères dans une transaction, conserve les valeurs NULL/UUID/identités/horodatages, vérifie les quantités et les contraintes, puis valide ou annule l'ensemble. Les déclencheurs métier ne sont pas rejoués sur l'historique. La vérification du certificat SQL reste obligatoire dans cet outil et dans l'API ; le lanceur diagnostic précédent ne la désactive pas.

Éviter un import anticipé dans la base finale pendant que le site écrit encore sur Supabase : il deviendrait obsolète et l'importeur refuse de remplacer des données existantes. Le transfert final devra être coordonné avec l'arrêt des écritures et le raccordement effectif de l'interface, des documents/PDF, des états et de l'EDI au backend SQL. Le paquet actuel prépare le transfert ; l'application reste sur Supabase et la bascule complète n'est pas terminée.

Après l'import et les contrôles, l'outil Admin permettra de rattacher le premier compte au profil historique conservé. Ne pas le créer avant l'import. Les fichiers PDF dans Storage constituent un transfert séparé des références présentes dans la base.

Référence : [options Microsoft SqlBulkCopy : identités, NULL, contraintes et déclencheurs](https://learn.microsoft.com/en-us/dotnet/api/microsoft.data.sqlclient.sqlbulkcopyoptions?view=sqlclient-dotnet-core-7.1).

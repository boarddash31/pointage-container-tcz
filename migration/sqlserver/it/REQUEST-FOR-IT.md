# Validation IT — Pointage TCZ / SQL Server

Décisions retenues le 27/10/2026 : **Windows Server**, **SQL Server 2025**, **comptes propres à l’application créés uniquement par Admin**, **lot conservé localement**. L’option AD/Entra a été annulée. Aucune publication sur le dépôt public n’est autorisée.

## Informations à fournir par l’IT

| Sujet | Informations attendues |
| --- | --- |
| Machine | Version de Windows Server, FQDN, accès de déploiement et site IIS |
| SQL Server | Instance/port, base de test vide (`TCZ_Pointage_Test`), certificat TLS et compte DBA de préparation |
| API | FQDN HTTPS, certificat approuvé par les postes et compte de service |
| Application | URL interne HTTPS et origine autorisée pour les appels API |
| PDF/impression | Stockage privé des PDF, droits du service, poste d’impression et imprimante de recette |
| Sauvegarde | RPO/RTO, rétention et emplacement séparé pour base, PDF et configuration |

La machine de compilation/validation doit disposer du **SDK .NET 10** et du dépôt NuGet approuvé par l’IT ou de son miroir. Le serveur IIS nécessite le **Hosting Bundle .NET 10** ; le SDK n’y est pas indispensable. Prévoir `sqlcmd` ou SSMS pour la préparation DBA.

## Comptes normaux de l’application

- Aucun raccordement AD, Entra, Kerberos ou compte de domaine n’est requis pour les utilisateurs.
- L’administrateur crée les comptes, attribue les rôles et active/désactive les utilisateurs. Le guichetier ne crée pas de comptes.
- Un compte peut utiliser un identifiant/téléphone ; une adresse professionnelle n’est pas exigée.
- Lot local préparé : hachage Identity V3 (PBKDF2 600 000 itérations), sessions opaques vérifiées en base à chaque requête, expiration, changement initial obligatoire, réinitialisation Admin et journalisation sans secrets. Ces composants ne sont pas encore compilés/exécutés ici.
- Aucun mot de passe partagé, compte administrateur par défaut ni ancien champ `initial_password` n’est copié par le transfert.
- La création initiale du premier administrateur doit être organisée avec le responsable métier/IT ; son mot de passe ne sera pas placé dans le code ou les archives.

Le module local de comptes/login est préparé sous `backend/Pointage.Api` et `005_application_accounts.sql`, avec un outil DBA interactif `backend/Pointage.Admin` pour le premier Admin. La compilation, les tests SQL/HTTP et la recette IT sont requis avant activation. La connexion Flutter actuelle reste Supabase jusqu’à l’adaptation du client. Aucun fournisseur AD/Entra/OIDC externe n’est à provisionner.

## Conservation de l’historique

Les profils et leurs UUID sont conservés pour les créateurs, agents et derniers modificateurs. Les rôles sont stockés dans `dbo.user_roles`. Les comptes applicatifs peuvent être reliés à un profil existant via son UUID ; aucun nom historique n’est écrasé. Importer et contrôler les données avant de créer les comptes. Le premier Admin peut reprendre l’UUID du profil Admin conservé.

## Validation demandée

1. Compiler les quatre projets sous `backend/` avec .NET 10 et lancer `Pointage.Checks`.
2. Préparer une base de test vide, appliquer `001_schema.sql`, puis `002_order_api.sql`.
3. Exécuter `003_smoke_test.sql`, appliquer `005_application_accounts.sql`, puis exécuter `006_account_smoke_test.sql` sur cette base `_Test` vide ; les données des tests sont annulées.
4. Valider le transfert fictif et, ensuite, un export réel contrôlé avec les outils et contrôles d’intégrité du guide principal.
5. Valider le module de comptes en HTTPS : création Admin uniquement, rôle insuffisant, compte désactivé, réinitialisation, révocation/expiration des sessions, changement initial obligatoire, dernier Admin et tentative d’accès anonyme. Valider les seuils de limitation avec les postes derrière NAT/IIS.

Le guide `migration/sqlserver/README.md` précise les commandes. La migration Gate complète, la validation des comptes, les PDF, le raccordement Flutter et la bascule restent à terminer. `it/ci-example.yml` est un exemple inactif pour une CI **privée approuvée** ; aucun workflow distant n’a été exécuté.

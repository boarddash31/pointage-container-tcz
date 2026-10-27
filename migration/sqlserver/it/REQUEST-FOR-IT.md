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
- Prévoir le hachage des mots de passe, la protection des sessions, le changement/rétablissement du mot de passe par un processus administrateur et la journalisation des opérations.
- Aucun mot de passe partagé, compte administrateur par défaut ni ancien champ `initial_password` n’est copié par le transfert.
- La création initiale du premier administrateur doit être organisée avec le responsable métier/IT ; son mot de passe ne sera pas placé dans le code ou les archives.

Le module local de comptes/login reste à implémenter dans le lot backend suivant. Le premier lot comporte un contrat de validation de jetons et les procédures métier ; il ne constitue pas encore un service de comptes prêt à déployer. La connexion Flutter actuelle reste Supabase jusqu’à l’adaptation du client. Aucun fournisseur AD/Entra/OIDC externe n’est à provisionner.

## Conservation de l’historique

Les profils et leurs UUID sont conservés pour les créateurs, agents et derniers modificateurs. Les rôles sont stockés dans `dbo.user_roles`. Les futurs comptes applicatifs devront être reliés à ces profils sans modifier les identifiants des opérations historiques.

## Validation demandée

1. Compiler les trois projets sous `backend/` avec .NET 10 et lancer `Pointage.Checks`.
2. Préparer une base de test vide, appliquer `001_schema.sql`, puis `002_order_api.sql`.
3. Exécuter `003_smoke_test.sql` sur cette base `_Test` vide ; ses données sont annulées.
4. Valider le transfert fictif et, ensuite, un export réel contrôlé avec les outils et contrôles d’intégrité du guide principal.
5. Valider le futur module de comptes : création Admin uniquement, rôle insuffisant, compte désactivé, réinitialisation et tentative d’accès anonyme.

Le guide `migration/sqlserver/README.md` précise les commandes. La migration Gate complète, les comptes, les PDF, le raccordement Flutter et la bascule sont les lots suivants. `it/ci-example.yml` est un exemple inactif pour une CI **privée approuvée** ; aucun workflow distant n’a été exécuté.

# Validation IT — Pointage TCZ / SQL Server

Décisions confirmées le 27/10/2026 : **Windows Server**, **SQL Server 2025**, **comptes d’entreprise AD/Entra ID**, **lot conservé localement**. Aucune publication du lot sur le dépôt public n’est autorisée.

## Informations à fournir par l’IT

| Sujet | Informations attendues |
| --- | --- |
| Machine | Version de Windows Server, FQDN, accès de déploiement et nom du site IIS |
| SQL Server | Instance/port, nom d’une base de test vide (`TCZ_Pointage_Test`), certificat TLS et compte DBA de préparation |
| API | FQDN HTTPS, certificat approuvé par les postes et compte de service (idéalement gMSA) |
| Application | URL interne HTTPS et origine autorisée pour les appels API |
| Authentification | Choisir le mécanisme disponible : **AD Windows intégré sous IIS** ou **Entra ID** |
| Impression/PDF | Emplacement du stockage privé des PDF, droits du service, serveur/poste d’impression et imprimante de recette |
| Sauvegarde | RPO/RTO attendus, rétention et emplacement séparé pour base, PDF et configuration |

La machine de compilation/validation doit disposer du **SDK .NET 10** et de l’accès au dépôt NuGet approuvé par l’IT (ou à son miroir interne). Le serveur de production IIS nécessite le **Hosting Bundle .NET 10** ; le SDK n’y est pas indispensable. L’outil `sqlcmd` ou SSMS est requis sur le poste DBA.

## Option A — Entra ID

L’API est préparée pour des jetons d’accès Entra v2, d’un seul tenant. L’IT doit fournir :

- `TenantId` : identifiant du tenant de l’entreprise.
- `ApiClientId` : inscription de l’API, configurée pour émettre des access tokens v2.
- `AllowedClientIds` : inscription du client web, puis éventuellement des clients mobiles approuvés.
- Une permission déléguée exposée par l’API, par exemple `access_as_user`, accordée au client web.
- Les URL de retour du futur client web/MSAL et les paramètres de consentement/accès conditionnel.

Configuration serveur :

```text
Authentication__Mode=EntraId
Authentication__EntraId__TenantId=<tenant GUID>
Authentication__EntraId__ApiClientId=<API GUID>
Authentication__EntraId__AllowedClientIds__0=<web client GUID>
Authentication__EntraId__RequiredScope=access_as_user
```

L’identité métier est liée au tenant et au `oid` Entra immuable. L’e-mail, le nom et le `sub` propre au client ne sont pas utilisés comme identifiants de profil. Les jetons d’un autre tenant/client ou sans permission déléguée sont refusés. IIS doit laisser l’API recevoir les requêtes Bearer (authentification anonyme IIS autorisée, protection réalisée par l’API).

## Option B — AD Windows intégré

Prévoir l’adhésion de la machine au domaine, le service de rôle **IIS Windows Authentication**, le compte de service et les SPN/Kerberos adaptés au nom HTTPS. Activer Windows Authentication et désactiver l’authentification anonyme sur le site API. Prévoir l’accès du navigateur à la zone intranet et tester le mode d’hébergement IIS choisi.

```text
Authentication__Mode=Windows
Authentication__Windows__DirectoryId=<identifiant stable convenu pour le domaine, par ex. corp.example>
```

L’API utilise le SID Windows authentifié par IIS/Negotiate, avec un issuer de configuration `urn:pointage:ad:<DirectoryId en minuscules>`. Aucun en-tête `X-User`, e-mail ou nom de connexion envoyé par le navigateur ne vaut authentification. En cas de proxy, prévoir une intégration Windows supportée ; ne pas ajouter de confiance automatique aux en-têtes utilisateur. Un même nom d’origine application/API est préférable pour la recette Windows. Les origines HTTPS autorisées restent explicites si CORS est nécessaire.

Le traitement Windows doit être testé sur la machine Windows/IIS réelle. Le contrôle de santé est lui aussi soumis à la politique d’authentification imposée par IIS.

## Rôles et conservation de l’historique

Une fois l’identité d’entreprise vérifiée par l’IT, un DBA doit créer sa correspondance vers le profil attendu dans `internal.identity_accounts`. Le `user_id` correspond à l’UUID conservé du profil métier. Les rôles Admin/Entrée/Engin/Sortie/Consultation sont lus dans `dbo.user_roles` ; aucune appartenance à un groupe AD ou claim `roles=admin` n’accorde automatiquement des droits applicatifs.

Pour Entra : issuer `https://login.microsoftonline.com/<tenant>/v2.0`, subject `<oid en GUID minuscules>`. Pour Windows : issuer `urn:pointage:ad:<DirectoryId>`, subject `<SID du compte>`. Les correspondances et changements de rôles doivent être approuvés par les responsables métier/IT. Aucun compte administrateur par défaut ni ancien mot de passe Supabase n’est créé/copié par ce lot.

## Validation demandée

1. Compiler les trois projets sous `backend/` avec .NET 10 et lancer `Pointage.Checks`.
2. Préparer une base de test vide, appliquer `001_schema.sql`, puis `002_order_api.sql`.
3. Exécuter `003_smoke_test.sql` sur cette base `_Test` vide ; ses données sont annulées.
4. Valider le transfert fictif et, ensuite, un export réel contrôlé avec les outils et les contrôles d’intégrité du guide principal.
5. Tester le mode AD/Entra retenu : identité autorisée, identité non mappée, rôle insuffisant, compte désactivé, changement de nom et tentative d’accès anonyme.

Le guide `migration/sqlserver/README.md` précise les commandes et le périmètre. La migration Gate complète, les PDF, le raccordement Flutter/SSO et la bascule restent les lots suivants. Le fichier `it/ci-example.yml` est un exemple inactif pour une plateforme CI **privée approuvée**, pas un workflow exécuté ou publié sur GitHub.

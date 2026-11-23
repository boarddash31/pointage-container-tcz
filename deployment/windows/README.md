# Zenata — déploiement sur deux serveurs

**Mise à jour du 20 novembre 2026 : le propriétaire choisit d’abord un runtime autonome HTTP sur 172.17.18.208, sans IIS ni HTTPS. Suivre [la procédure HTTP actuelle](HTTP-RUNTIME.md). Les sections HTTPS ci-dessous décrivent la cible préparée précédemment et ne sont pas requises pour cette phase. SQL Server reste sur 172.17.18.209 ; son raccordement n’est pas encore terminé.**

Architecture confirmée par le propriétaire le 16 novembre 2026 :

| Machine | Adresse | Rôle cible |
| --- | --- | --- |
| Serveur applicatif | **172.17.18.208** | Interface web, API métier, génération des PDF et connecteur EDI/JMS séparé |
| Serveur de données | **172.17.18.209** | SQL Server 2025, données applicatives, comptes applicatifs et historique ; sauvegardes SQL sous responsabilité DBA |

Les postes métier accèdent à `https://172.17.18.208/`. L’API du serveur applicatif utilise SQL Server sur `172.17.18.209` ; aucune connexion SQL ni aucun identifiant SQL n’est envoyé au navigateur. Aucun nom DNS applicatif n’a encore été attribué.

## Flux à préparer avec l’IT

| Source | Destination | Protocole / port | État |
| --- | --- | --- | --- |
| Postes métier autorisés | 172.17.18.208 | HTTPS / TCP 443 | Certificat et règle réseau à préparer |
| 172.17.18.208 | 172.17.18.209 | SQL Server chiffré / port TCP fixe à confirmer | Instance, port et certificat SQL attendus |
| Postes DBA approuvés | 172.17.18.209 | Accès d’administration séparé, selon politique IT | À organiser par l’IT |

Pour les connexions applicatives, limiter la règle SQL entrante à l’adresse du serveur applicatif. Le port habituel d’une instance par défaut est 1433, mais il n’est **pas considéré comme confirmé** ici : une instance nommée ou configurée autrement peut utiliser un autre port. Aucun besoin d’activer SQL Browser n’est déduit ; préférer le port fixe fourni par l’IT. [Documentation Microsoft sur les ports et le pare-feu SQL Server](https://learn.microsoft.com/en-us/sql/sql-server/install/configure-the-windows-firewall-to-allow-sql-server-access?view=sql-server-ver17).

Le certificat HTTPS doit couvrir l’adresse d’accès applicative ; le certificat SQL doit couvrir le nom ou l’adresse utilisés pour la connexion SQL et être approuvé sur le serveur applicatif. Conserver le chiffrement et `TrustServerCertificate=False`. Les certificats des deux services sont à traiter séparément.

## Configuration préparée

- `target.json` retient les deux IP et laisse le nom d’instance, le port et le nom de base non renseignés. Ce fichier est un plan d’infrastructure, pas une configuration interprétée automatiquement par l’application.
- `appsettings.Api.example.json` fournit le futur hôte/origine de l’API et les comptes normaux de l’application. La chaîne SQL est volontairement vide ; la configuration active du dépôt n’est pas remplacée.
- Sur le serveur applicatif, définir `ConnectionStrings__Pointage` dans la configuration protégée du service ou du pool IIS. La forme, **sans identifiant ni mot de passe**, est :

```text
Server=tcp:172.17.18.209,<PORT_SQL>;Database=<NOM_BASE>;Encrypt=True;TrustServerCertificate=False;Persist Security Info=False;
```

L’IT complète les paramètres et l’authentification du compte technique hors du dépôt et de la racine web. Ce compte appartient au rôle de base `pointage_api` ; le runtime n’utilise pas le compte DBA pour les opérations métier. Les comptes métier restent créés uniquement par Admin ; aucun AD/Entra pour les utilisateurs n’est requis.

## Mise en service par étapes

1. DBA : préparer sur **172.17.18.209** une base de recette vide, le certificat TLS, le compte technique et son rôle, puis appliquer et valider les scripts SQL Server depuis le poste d’administration approuvé. Ne pas appliquer les modèles PostgreSQL `.sql.in` à SQL Server.
2. Depuis **172.17.18.208**, contrôler la résolution éventuelle du nom SQL, l’accès au port confirmé et la connexion TLS avec les droits de runtime. Aucun test réseau vers ces deux machines n’a été exécuté par cette préparation.
3. Terminer puis valider l’API, les opérations Gate, les PDF, les nouvelles règles ops et le raccordement Flutter. Publier les fichiers et le service sur **172.17.18.208**, avec démarrage automatique et journaux protégés. Le mode IIS ou service Windows reste à finaliser avec l’IT ; les sources actuelles ne constituent pas encore un exécutable autonome complet.
4. Exécuter la recette métier et la réconciliation des données/documents avant la bascule. Organiser sauvegarde et restauration de la base côté serveur SQL, ainsi que des PDF et de la configuration côté applicatif ou sur un stockage privé prévu par l’IT. Ne pas utiliser la machine SQL comme unique destination de ses propres sauvegardes.

**État actuel : préparation locale.** L’interface compilée du lot ops utilise encore Supabase ; placer ses fichiers sur 172.17.18.208 ne la raccorde pas à SQL Server. Aucune base, règle réseau, identité technique ou installation distante n’a été créée. L’archive ops précédente reste un lot de revue, à compléter par ce plan d’infrastructure.

Voir aussi [la demande IT](../../migration/sqlserver/it/REQUEST-FOR-IT.md) et [la revue ops](../../changes/ops-20261116/README.md). La future migration doit inclure `operational_details`, les blocages/audits de conteneurs et les compléments CODECO préparés après le manifeste initial des 22 tables.

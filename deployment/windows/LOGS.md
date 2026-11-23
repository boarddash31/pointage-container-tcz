# Journaux du runtime HTTP — port 9091

## Appliquer la mise à jour au paquet déjà installé

1. Arrêter le runtime avec Ctrl+C dans sa fenêtre.
2. Conserver une copie de l’ancien `http-runtime.cjs` hors du dossier `web`.
3. Extraire la petite archive de mise à jour et copier **ensemble** `http-runtime.cjs` et `runtime-logs.cjs` dans `C:\Apps\ZenataRuntime`, à côté de `node.exe`. Copier également `LANCER-9091.cmd` si nécessaire. Ne pas remplacer `web`, les données ou les autres fichiers du runtime.
4. Relancer **LANCER-9091.cmd**. L’adresse reste **http://172.17.18.208:9091/**.

Le compte qui lance Node doit pouvoir écrire dans le sous-dossier `logs`. Réserver l’accès à ces fichiers aux personnes chargées de l’exploitation. Le runtime refuse de placer ses journaux dans le dossier public `web`.

## Emplacement et format

Par défaut : `C:\Apps\ZenataRuntime\logs\zenata-AAAA-MM-JJ-NNNNNN.jsonl`.

Une ligne est un événement JSON, horodaté en **UTC**, avec l’identifiant du processus. Un nouveau fichier est créé au démarrage, au changement de date UTC ou après environ **5 Mio**. Les **14 derniers fichiers** sont conservés ; il s’agit d’un nombre de fichiers, pas d’une garantie de 14 jours. Seuls les fichiers portant le nom généré par ce logger sont supprimés lors de la rotation. Prévoir une collecte/sauvegarde séparée si l’IT demande une conservation plus longue.

Événements disponibles :

- `startup`, `shutdown` : lancement et arrêt normal ; un arrêt brutal de Windows/processus peut ne pas produire d’événement de fermeture.
- `server_error`, `fatal_error` : port occupé, erreur d’écoute ou erreur fatale ; les messages et piles d’exception bruts ne sont pas enregistrés.
- `http_request`, `http_aborted` : méthode, catégorie de ressource, statut HTTP, durée en millisecondes et identifiant de requête créé par le serveur. Ce même identifiant est renvoyé dans `X-Request-Id` pour faciliter les diagnostics.
- `request_error` : échec de lecture ou d’envoi d’une ressource.

Les URL complètes, paramètres de requête, chemins inconnus, en-têtes Authorization/Cookie, mots de passe, jetons, corps de requête et contenus métier ne sont pas consignés. Les chemins inconnus apparaissent seulement comme `static_or_unknown`. Une erreur d’écriture des logs est signalée dans la console ; vérifier l’espace disque et les permissions.

Pour consulter les derniers événements sur le serveur, par exemple :

```powershell
$zenataLog = Get-ChildItem C:\Apps\ZenataRuntime\logs\zenata-*.jsonl |
    Sort-Object Name -Descending | Select-Object -First 1
Get-Content -LiteralPath $zenataLog.FullName -Tail 30 -Wait
```

`LOG_DIR` peut définir un autre répertoire privé avant de lancer le runtime. Ne pas sélectionner le dossier `web` ni un emplacement exposé par un autre serveur web.

## Périmètre

Ces fichiers suivent **le serveur de l’interface statique**. Les appels du navigateur à Supabase ne traversent pas ce runtime : ces logs ne prouvent donc ni une connexion utilisateur réussie ni la création d’une restitution/livraison. Les actions métier et leurs auteurs restent dans l’historique/audit en base ; les erreurs du backend se consultent dans le service qui les exécute. Le futur backend SQL Server aura sa journalisation API dédiée.

Validation locale : service des fichiers, accès refusés, codes 200/404/405, identifiant de corrélation, rotation taille/date, rétention et exclusion des secrets. Aucune mise à jour n’a été exécutée sur 172.17.18.208 par la préparation de cette archive.

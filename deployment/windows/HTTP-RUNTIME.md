# Lancement autonome HTTP sur 172.17.18.208

Journaux techniques ajoutés : voir [la mise à jour et l’utilisation des logs](LOGS.md). Le paquet initial doit recevoir `http-runtime.cjs` et `runtime-logs.cjs` ensemble pour activer ces journaux.

**Port choisi ensuite par le propriétaire : 9091.** Pour le paquet déjà installé, copier `LANCER-9091.cmd` à côté de `node.exe`, arrêter l’ancien processus avec Ctrl+C, puis lancer ce nouveau fichier. Adresse : **http://172.17.18.208:9091/**. Faire autoriser TCP 9091 depuis les postes concernés. Les instructions port 80 ci-dessous décrivent le paquet initial ; il n’est pas nécessaire de le retélécharger pour changer de port.

Décision du propriétaire, 20 novembre 2026 : HTTP avec l’adresse IP, sans IIS et sans certificat pour cette phase. Cette décision remplace la préparation HTTPS de l’interface. Le chiffrement de la future connexion SQL vers 172.17.18.209 reste distinct et inchangé.

Le ZIP portable contient `node.exe`, sa licence, `http-runtime.cjs`, `LANCER.cmd` et le dossier public `web`. Aucun npm, Flutter, Java ou IIS n’est nécessaire sur le serveur pour lancer cette interface. Le binaire inclus est le Node **22.14.0** déjà disponible et testé localement, signature OpenJS valide vérifiée à la préparation. Il sert à cette recette ; l’IT doit valider sa version et ses correctifs avant une mise en production. [Versions Node LTS](https://nodejs.org/en/about/previous-releases).

## Démarrer

1. Transférer le ZIP par le moyen approuvé et l’extraire dans `C:\Apps\ZenataRuntime`, en gardant tous les fichiers et `web` au même niveau. Ne pas mélanger avec une ancienne release.
2. Dans la session Bureau à distance sur **172.17.18.208**, ouvrir ce dossier et lancer **LANCER.cmd**. Il démarre le serveur uniquement sur l’adresse 172.17.18.208 et le port 80 par défaut.
3. Ouvrir **http://172.17.18.208/** dans le navigateur. La connexion doit afficher Gestion des flux et le logo ZPS ; `/release.json` identifie `zps-ops-20261116`.
4. Faire autoriser TCP 80 depuis les postes de recette concernés par l’IT. Aucun changement de pare-feu n’est exécuté par le lanceur.

Conserver le processus en fonctionnement : fermer sa fenêtre ou terminer la session Windows peut arrêter le serveur. Ctrl+C l’arrête. Le paquet n’installe pas automatiquement un service et ne configure pas de tâche planifiée. Pour fonctionner après fermeture de session et après redémarrage Windows, l’IT pourra créer une tâche au démarrage avec un compte technique approprié et des droits de lecture sur ce dossier, sans mot de passe dans le lanceur.

Si le port 80 est occupé, notamment par IIS, ne pas arrêter automatiquement un site existant. Examiner ses liaisons avec l’IT. Pour un premier essai sur un autre port, dans PowerShell :

```powershell
Set-Location C:\Apps\ZenataRuntime
$env:PORT = '8080'
.\LANCER.cmd
```

L’adresse de cet essai devient `http://172.17.18.208:8080/`. `HOST` permet un essai local sur `127.0.0.1`, sans changer le code. Ne pas le définir à une adresse que le serveur ne possède pas.

## Périmètre de cette version

- Le runtime sert uniquement l’interface et ses ressources publiques. Ce n’est ni l’API SQL Server ni le connecteur JMS. Il ne fournit aucun proxy pour contourner les règles réseau de l’entreprise.
- Comptes, données et PDF utilisent encore Supabase. Les navigateurs des postes doivent disposer des accès réseau nécessaires ; le tableau superviseur garde aussi ses dépendances CDN existantes.
- Les nouveaux RPC ops et le générateur PDF ne sont pas activés sur la base distante par ce paquet. Il faut les appliquer sur le backend de recette avant de tester les nouveaux passages métier. Ne pas exécuter le modèle PostgreSQL sur SQL Server.
- L’API .NET préparatoire conserve ses validations HTTPS ; `appsettings.Api.example.json` ne configure pas ce runtime HTTP et ne constitue pas une API SQL Server prête à démarrer sur HTTP.
- Une nouvelle origine nécessite une nouvelle connexion. Tester sur un poste réel la connexion, les rôles, les bons, l’impression, le presse-papiers et la récupération : certaines API navigateur ont des restrictions hors contexte sécurisé. Aucun contrôle navigateur n’est désactivé dans le paquet. La redirection de récupération Supabase devra autoriser l’origine HTTP exacte utilisée pour la recette, port compris ; aucun réglage distant n’a été changé.

Validation locale : GET/HEAD, MIME Wasm, absence de cache, refus des écritures, des fichiers privés, des scripts et des chemins de traversée. La connexion sur le serveur réel et ses règles réseau ne sont pas validées par ce test.

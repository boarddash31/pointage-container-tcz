# Installation technique sur 172.17.18.208 — 20 novembre 2026

**Procédure remplacée pour la phase actuelle : le propriétaire a choisi le [runtime autonome HTTP](HTTP-RUNTIME.md), sans IIS ni HTTPS. Conserver ce document seulement pour une éventuelle installation IIS ultérieure.**

À exécuter par l’administrateur dans sa session Bureau à distance sur **172.17.18.208**, pas sur son poste de travail ni sur le serveur SQL **172.17.18.209**. Aucune installation distante n’a été exécutée par la préparation locale.

Le lot disponible est une **version de revue de l’interface**, encore reliée à Supabase. L’API SQL Server et le raccordement Flutter restent incomplets. Les nouveaux RPC ops et le générateur PDF doivent être activés sur le backend de recette avant les essais de passages métier. Ce démarrage prépare IIS et les fichiers ; il n’ouvre pas l’application aux agents et ne migre aucune donnée.

## 1. Installer les composants IIS

Ouvrir Windows PowerShell en tant qu’administrateur sur 208 :

```powershell
if (-not (Get-NetIPAddress -AddressFamily IPv4 | Where-Object IPAddress -eq '172.17.18.208')) {
    throw 'Exécuter ces commandes dans la session du serveur applicatif 172.17.18.208.'
}
Install-WindowsFeature Web-Server,Web-Static-Content,Web-Default-Doc,Web-Http-Logging,Web-Filtering -IncludeManagementTools
Get-WindowsFeature Web-Server,Web-Static-Content,Web-Default-Doc,Web-Http-Logging,Web-Filtering
```

Vérifier `Success=True` et l’état Installed des composants. Si un redémarrage est demandé, l’organiser avec l’IT avant de continuer. Ne pas modifier la politique d’exécution des scripts. [Installation IIS et outils de gestion, Microsoft](https://learn.microsoft.com/en-us/windows-server/networking/core-network-guide/cncg/server-certs/install-the-web-server-web1).

## 2. Transférer et contrôler le lot

Copier `pointage-zps-ops-20261116-it-review.zip` depuis le poste de préparation vers `C:\Temp` sur 208, par le moyen de transfert approuvé par l’IT. Puis :

```powershell
$zenataArchive = 'C:\Temp\pointage-zps-ops-20261116-it-review.zip'
$zenataExpectedHash = 'd7edfd2122d3c8288cc336fd590bf4e43a0538bbe4c6953dab1bdaaa3c03d5bd'
if ((Get-FileHash -LiteralPath $zenataArchive -Algorithm SHA256).Hash.ToLowerInvariant() -ne $zenataExpectedHash) {
    throw 'Archive incorrecte ou transfert incomplet.'
}
$zenataReleasePath = 'C:\Apps\Zenata\releases\ops-20261116'
if (Test-Path -LiteralPath $zenataReleasePath) {
    throw 'Ce répertoire existe déjà : vérifier la release existante avant toute modification.'
}
Expand-Archive -LiteralPath $zenataArchive -DestinationPath $zenataReleasePath
Get-Item -LiteralPath "$zenataReleasePath\web\index.html", "$zenataReleasePath\web\web.config"
```

Ne pas déployer la racine de l’archive : seuls les fichiers de **`C:\Apps\Zenata\releases\ops-20261116\web`** doivent être exposés par IIS. Les dossiers source, SQL et revue restent hors de la racine web.

## 3. Préparer le site HTTPS dédié

Dans le Gestionnaire des services Internet (IIS) :

1. Inventorier les sites et liaisons existants ; ne pas remplacer un site ou un certificat déjà utilisé.
2. Créer un pool dédié `ZenataRecette`, sans code managé, identité ApplicationPoolIdentity.
3. Donner à `IIS AppPool\ZenataRecette` uniquement Lecture et exécution sur le dossier `web`. Ne pas accorder de droit d’écriture ou de modification pour ce site statique.
4. Faire installer par l’IT un certificat HTTPS approuvé par les postes, couvrant **172.17.18.208 comme SAN IP**. Sans certificat approprié, laisser cette étape en attente ; ne pas désactiver les contrôles TLS.
5. Créer un site `ZenataRecette`, avec le pool dédié et le chemin `web` ci-dessus, sur une liaison HTTPS disponible `172.17.18.208:443`. Aucun nom d’hôte n’est encore attribué. Si la liaison est déjà utilisée, faire définir une liaison distincte par l’IT avant création.
6. Faire autoriser TCP 443 depuis les réseaux de recette concernés selon les règles IT ; ne pas créer une ouverture générale sans périmètre défini.

## 4. Vérifier puis préparer les essais métier

Depuis un poste de recette approuvé, ouvrir `https://172.17.18.208/`. La connexion doit afficher **Gestion des flux** et le logo ZPS. Vérifier le certificat et `https://172.17.18.208/release.json` : release `zps-ops-20261116`, empreinte du bundle `0f2b02a9c7bd82d012863ab321bd6b55662250b65d90420c54e79278b0556568`.

L’accès au backend Supabase depuis les navigateurs, les redirections de récupération, les nouveaux RPC ops et le générateur PDF restent des prérequis avant une recette métier. Voir `changes/ops-20261116/README.md` dans le dépôt ou `changes/README.md` dans l’archive. Le simple affichage de la connexion ne valide pas la migration SQL Server ni un passage camion.

Pour la cible entièrement interne, suivre [le plan à deux serveurs](README.md) : adresse SQL **172.17.18.209**, instance/port et nom de base encore à confirmer. Les modèles PostgreSQL `.sql.in` de la revue ops ne s’exécutent pas dans SQL Server.

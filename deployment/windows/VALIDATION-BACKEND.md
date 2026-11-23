# Validation du backend SQL sur 208 — 21 novembre 2026

Le propriétaire confirme que le SDK .NET 10 est installé sur **172.17.18.208**, que son test réseau vers **PRD-DB-ZENATA:54013** réussit et que le premier backend comptes/ordres a été compilé et contrôlé avec succès. Le socle SQL initial est déclaré créé avec succès dans **toszps**. Ne pas réexécuter l’initialisation du socle.

**Paquet v3 :** ce lot ajoute le code des entrées, restitutions doubles avec clôture automatique, livraisons contrôlées, annulations et blocages Admin. Relancer **VALIDER-BACKEND.cmd** dans cette nouvelle extraction pour compiler ce nouveau code et analyser les nouveaux SQL. Ce lanceur n’applique toujours aucun SQL. Les étapes de recette séparées et les limites restantes sont dans **ETAPES-GATE.md**. Ne pas appliquer le fichier de mise à jour `toszps` avant cette recette.

## À faire maintenant

**Paquet v2 — correction de la restauration NuGet :** l’exécution sur 208 a signalé les avis `GHSA-2fmv-rv2c-59x7` et `GHSA-846f-f764-76mx` sur la dépendance transitive `System.Security.Cryptography.Pkcs` **9.0.18**. Les projets API et Migration référencent désormais explicitement **10.0.15**, compatible avec .NET 10 et postérieure aux correctifs 10.0.13 indiqués par les deux avis Microsoft. Les projets Checks/Admin reçoivent cette référence via l’API. `TreatWarningsAsErrors` et l’audit NuGet restent actifs ; aucun avertissement n’est ignoré.

Extraire ce nouveau paquet dans un dossier séparé de la première extraction puis lancer son `VALIDER-BACKEND.cmd`. Il n’est pas nécessaire de réinstaller le SDK 10.0.404 ni SQL Server. La restauration et la compilation corrigées restent à vérifier sur 208 : le poste de préparation ne dispose pas du SDK. Références : [avis Microsoft 1](https://github.com/advisories/GHSA-2fmv-rv2c-59x7), [avis Microsoft 2](https://github.com/advisories/GHSA-846f-f764-76mx), [package 10.0.15](https://www.nuget.org/packages/System.Security.Cryptography.Pkcs/10.0.15).

1. Extraire entièrement le dossier **ZENATA-BACKEND-VALIDATION** dans **C:\Temp**, séparément du runtime Node actuellement en service.
2. Dans ce dossier, double-cliquer sur **VALIDER-BACKEND.cmd**. Le script ne nécessite aucun mot de passe SQL.
3. Attendre la fin. Il affiche soit **VALIDATION BACKEND REUSSIE**, soit **VALIDATION BACKEND EN ECHEC**, avec le chemin du journal `validation-….log`.
4. Communiquer le résultat final et, en cas d’échec, les lignes d’erreur utiles du journal. Ne pas transmettre de mots de passe, de clés ou d’URL de dépôt comportant un secret.

Le SDK sélectionné est défini par `backend/global.json` : .NET **10.0.400**, avec recherche d’une version de fonctionnalité 10.0 plus récente installée. Si seule une version 10.0 antérieure est présente, utiliser le SDK récent approuvé par l’IT. La commande `dotnet --version`, lancée depuis le dossier `backend`, explique cette sélection.

## Ce que fait le script

- Compile l’API et les contrôles (`Pointage.Checks` référence `Pointage.Api`).
- Compile les outils de migration et d’administration **sans les exécuter**.
- Exécute les contrôles locaux : syntaxe T-SQL SQL Server 2025, règles EDO/ERO, validation des comptes, hachage de mots de passe fictifs et jetons de session fictifs.
- Enregistre les sorties de compilation et de contrôle dans un journal local au paquet.

Les fichiers SQL fournis sont lus par le parseur ; le script ne les applique pas au serveur. Les contrôles ne nécessitent aucune chaîne de connexion. Ils ne prouvent pas encore le bon fonctionnement des procédures sur l’instance réelle, ni la migration complète des parcours métier.

La première compilation restaure les dépendances NuGet épinglées dans les projets. Utiliser le dépôt ou miroir approuvé configuré sur la machine. Si la politique d’entreprise bloque un téléchargement, faire fournir la dépendance par l’IT ; ne pas désactiver les contrôles TLS ou contourner le proxy. Aucun fichier `NuGet.Config` avec des identifiants n’est inclus.

## Périmètre exact

Ce lot prépare **les comptes, les ordres et le premier portage Gate**. Les tests locaux ne remplacent pas la recette SQL, les tests HTTP authentifiés et les tests de concurrence. Le raccordement Flutter/PDF, CODECO et rapports, les reprises de visites historiques non liées à un ordre et les prises forcées/régularisations restent à compléter avant bascule. Le backend préparatoire impose encore des origines HTTPS ; il n’est pas à démarrer tel quel sur l’URL HTTP de l’application.

Le paquet ne lance pas d’API, ne publie rien, n’importe rien et ne remplace pas les fichiers de l’application sur **9091**. Il ne crée pas de compte Admin et ne contient ni données métier ni secrets. Le runtime actuellement utilisé reste sur Supabase.

Après cette validation de compilation, le lot suivant pourra être construit et testé sur la base de recette avant toute mise à jour du socle ou bascule de l’application. Conserver les fichiers et le journal pour la suite.

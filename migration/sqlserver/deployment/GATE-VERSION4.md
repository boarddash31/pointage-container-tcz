# Lot Gate SQL — version de schéma 4

Le premier socle est déjà installé dans **toszps** et le propriétaire a validé la compilation du backend comptes/ordres sur 208. Ce nouveau lot ajoute du code : il doit être compilé et testé à son tour. Aucun script de ce paquet n’a été exécuté sur le serveur par sa préparation locale.

## 1. Compilation sur 208 — action immédiate

Extraire le paquet v3 dans un nouveau dossier de **C:\Temp**, séparé de l’application en service. Lancer **VALIDER-BACKEND.cmd**. Il compile les nouvelles routes Gate, vérifie les règles C# et analyse la syntaxe SQL des scripts 008/009/010. Il ne lance aucune API et ne se connecte pas à la base.

## 2. Base de recette séparée

Faire créer une **base vide `toszps_Test`** sur la même instance `PRD-DB-ZENATA\MMSQL01`. Lui donner la collation **French_CI_AS** comme la cible et le niveau de compatibilité **170**. Le compte de recette doit pouvoir y déployer le schéma. Le compte `toszps` avec seulement `db_owner` dans `toszps` ne dispose pas nécessairement du droit de créer une autre base : cette préparation relève du DBA/compte SQL autorisé, pas des droits administrateur Windows seuls.

Le DBA peut créer cette base dans une nouvelle session auto-commit, si elle n’existe pas déjà :

```sql
IF DB_ID(N'toszps_Test') IS NOT NULL
    THROW 51100, 'La base de recette existe deja : examiner son contenu.', 1;
CREATE DATABASE [toszps_Test] COLLATE French_CI_AS;
```

Ne pas renommer, vider ou recréer `toszps`. Ne pas transférer de données réelles dans cette base de recette.

## 3. Recette dans DBeaver

Après réussite de la compilation, sélectionner **toszps_Test**. Pour chacun des trois fichiers suivants, ouvrir une nouvelle session sans transaction déjà ouverte, sélectionner tout et envoyer le bloc en une fois avec **Ctrl+A puis Ctrl+Entrée** :

1. **SQL-RECETTE/10_INITIALISER_RECETTE_DBEAVER.sql** : installe seulement le socle initial dans la base de recette vide. Le garde refuse `toszps`.
2. **SQL-RECETTE/11_GATE_RECETTE_DBEAVER.sql** : ajoute la version Gate 4 dans cette base de recette. Les changements sont transactionnels ; aucun passage historique n’est automatiquement clôturé par l’installation.
3. **SQL-RECETTE/13_TESTER_GATE_DBEAVER.sql** : neuf scénarios avec données fictives, annulées après chaque scénario. Ce fichier refuse la base `toszps` et toute base de recette contenant déjà des profils, comptes, visites ou armateurs.

Résultat attendu du dernier fichier : **RECETTE GATE REUSSIE - 9 scenarios, donnees fictives annulees**. Un échec indique le contrôle et la ligne concernés ; arrêter et examiner le message. Aucun de ces scripts ne contient de mot de passe.

## 4. Mise à jour du socle cible — après recette et sauvegarde

Après compilation, recette SQL réussie et sauvegarde DBA, sélectionner **toszps** et utiliser **SQL-MISE-A-JOUR/12_GATE_TOSZPS_DBEAVER.sql**. Le script requiert les versions 1/2/3, refuse de rejouer la version 4, contrôle le serveur/instance/port normalisé et applique les deux nouveaux SQL dans une transaction. Il conserve les tables/données existantes et n’importe aucune ligne métier.

Résultat attendu : **GATE VERSION4 INSTALLEE - application non basculee**. Cela n’active pas le nouveau backend et ne modifie pas le runtime Node sur **9091**.

## Comportements préparés et contrôles

- Entrée avec article d’ordre obligatoire par emplacement ; ISO, armateur, référence et client viennent de l’ordre. Aucun champ d’affectation client n’est offert au guichetier par cette API.
- Quantités réservées sous verrou, deux conteneurs distincts de 20 pieds pour un twin, contrôles ISO 6346 et rejet des doublons actifs.
- Restitution : deux insertions au stock dans la même transaction, puis clôture automatique après dépôt effectif ; aucun camion n’est clôturé lors de sa simple entrée.
- Livraison : stock présent, ISO et armateur identiques à l’article, catalogue cohérent, absence de blocage et 24 heures écoulées depuis **l’entrée du camion de restitution**, pas depuis le dépôt au stock.
- Sortie à vide sans prise : annulation de la réservation ; annulation normale Admin uniquement avant mouvement physique. Aucune annulation d’un mouvement déjà effectué.
- Blocage/déblocage Admin versionné et audité ; un blocage du second conteneur empêche le twin complet. Nouveau déclencheur de protection du stock, en plus du garde des 24 heures existant.
- Documents : instantanés JSON immuables d’entrée/dépôt/prise/sortie/annulation, agent figé, scellés et réserves conservés, événements et audit dans la même transaction. Le rendu/stockage des PDF n’est pas implémenté par ces procédures.
- Lecture des visites, stock et événements par pagination sur identifiant, droits vérifiés en SQL à chaque opération. Les mutations exigent la version attendue.

Les opérations Gate sont sérialisées par un verrou applicatif transactionnel commun, puis les parents d’ordre et articles sont verrouillés dans le même ordre que l’éditeur EDO/ERO. Ce premier modèle privilégie la cohérence ; mesurer débit et concurrence avant production. Le premier scénario exécute la restitution via un utilisateur fictif du rôle `pointage_api` pour vérifier l’accès par procédures sans droits directs sur les tables. Les tests SQL fournis couvrent les scénarios métier, pas un banc multi-utilisateur ni les routes HTTP.

## Limites avant bascule

Les historiques sans liaison contrôlée à un article restent consultables ; leurs opérations physiques doivent être réconciliées avant utilisation du nouveau backend. Les prises forcées/régularisations, Data consolidée, PDF, interface Flutter, CODECO et rapports SQL nécessitent encore un portage/une recette. Aucun calcul de surestaries n’est ajouté.

Le manifeste de transfert existant couvre 22 tables et ne contient pas les blocages ni les détails opérationnels récents. L’ancien importeur est donc bloqué sur une destination version 4 ; l’exporteur refuse les ajouts de tables/champs non couverts. Actualiser et valider le manifeste source avant tout transfert réel. Les nouvelles tables et champs ne doivent pas être perdus au profit d’un import ancien.

Le runtime actuel reste relié à Supabase. Cette mise à jour SQL ne suffit pas à le raccorder à la nouvelle API ; conserver l’environnement actuel jusqu’à une recette complète de bout en bout. Le compte d’exécution API devra rester distinct du compte DBA et utiliser `pointage_api`, sans `db_owner`.

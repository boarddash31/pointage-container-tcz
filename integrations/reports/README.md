# Rapports programmés — Zenata

Rubrique web réservée aux administrateurs actifs. L’API vérifie chaque session auprès de Supabase puis contrôle `profiles.active` et `user_roles`. Les métadonnées modifiables du compte ne donnent aucun droit.

## Utilisation

### Rapports dédiés par armateur et fin de shift

Le modèle fourni `Report (34).xls` a été consulté en lecture seule : stock vide réparti en 20 DV, 40 DV ST, 40 DV HC, 45 DV, FRIGO 20/40, types spéciaux et RECAP. Les données du modèle ne sont pas importées dans l’application.

Pour un envoi MSC, choisir **Présentation Excel → Rapport client : stock par type + RECAP**, puis **Armateur destinataire → MSC**. Créer un autre rapport pour CMA CGM avec ses propres adresses. L’armateur est obligatoire dans ce modèle. Le filtre s’applique individuellement à chaque conteneur, y compris aux deux emplacements d’un mouvement double, aux entrées, aux sorties et au stock. Le filtre facultatif client métier reste indépendant et s’applique en plus. Les anciens rapports consolidés restent compatibles.

Choisir **Période des mouvements → Dernier shift terminé**, saisir librement **Début du shift** et **Fin du shift**, puis programmer l’envoi à cette fin ou quelques minutes après. Aucun horaire de shift n’est imposé : les champs sont initialement vides. Exemple de fonctionnement uniquement : un shift 22:00–06:00 couvre la nuit et se termine le lendemain. Un clic manuel ou un envoi décalé sélectionne le dernier shift entièrement terminé, pas un shift encore en cours. Créer une programmation par shift et par armateur. Les heures sont celles du Maroc ; une borne locale inexistante à un changement d’heure provoque un échec explicite à contrôler.

Le classeur dédié ajoute **RECAP** et huit onglets de stock par catégorie aux cinq onglets existants. Les colonnes reprennent CONTENEUR, LIGNE, ISO, TP, LG, HT, DATE et HEURE D’ARRIVÉE AU TERMINAL. La catégorie, la longueur et les facteurs EVP viennent des règles versionnées `iso_report_types` et `evp_rules` déjà enregistrées. Un code sans règle reste dans **NON CLASSES** et un EVP absent est signalé séparément ; aucun classement ni EVP n’est déduit arbitrairement du numéro de conteneur. La colonne HT reste vide car la hauteur n’est pas enregistrée dans ces règles. Le format produit est `.xlsx`.

Ouvrir **Rapports → Configuration e-mail** : nom/IP du relais, port, adresse expéditrice, STARTTLS/TLS ou relais interne sans authentification. Ajouter identifiant et mot de passe seulement si le relais les exige. Enregistrer puis **Vérifier le SMTP** : cette vérification ne transmet aucun e-mail.

Créer un rapport avec ses destinataires et ses clients métier. Une liste de clients vide signifie tous les clients, y compris les mouvements sans attribution. Les armateurs ne servent jamais à déduire un client. Les destinataires reçoivent le même classeur consolidé pour tous les clients sélectionnés ; créer des rapports distincts pour des listes de diffusion distinctes.

Fréquences : une fois, toutes les 5 à 10 080 minutes, quotidienne, hebdomadaire ou mensuelle. Les heures sont celles d’**Africa/Casablanca**, avec les changements d’heure du Maroc. Jour mensuel `0` = dernier jour ; une date absente du mois est sautée. Une heure inexistante lors d’un changement d’heure est sautée ; une heure répétée est exécutée à sa première occurrence.

Périodes : journée précédente, mois précédent ou dernières 1 à 744 heures. Le stock est pris juste avant la fin exclue de la période. L’aperçu Excel n’envoie rien. **Envoyer maintenant** utilise la période calculée à l’instant du clic et fonctionne aussi pour un rapport en pause.

Le classeur `.xlsx` contient Synthèse, Entrées, Sorties, Stock et Période. Les entrées sont les arrivées de conteneurs sur camion chargé ; les sorties sont les livraisons de conteneurs sur camion entré vide. Chaque conteneur d’un mouvement double compte séparément. Un camion de restitution qui repart vide ne crée pas une sortie de conteneur. Aucun CIN, téléphone ou nom de chauffeur n’est exporté. Les textes du classeur ne sont jamais interprétés comme des formules.

## Installation sur 172.17.18.208:9091

Le paquet de mise à jour contient `web/`, le runtime, `reports/`, les lanceurs et cette notice. Il **ne contient pas** de données de production ni de secrets. Conserver le `node.exe` portable existant (22.14.0, testé avec `node:sqlite`). Arrêter le runtime, sauvegarder l’installation, remplacer les fichiers du paquet puis relancer **LANCER-9091.cmd**. Ne pas effacer `.state/`, `runtime.env` ou `logs/` lors des mises à jour.

Prérequis restant : **Nodemailer 10.6.1**. Le téléchargement local a été refusé par le proxy d’entreprise (« File Transfer Blocked »). Aucun contournement n’a été tenté. Faire fournir/installer cette dépendance par l’IT via son circuit autorisé, dans `reports/node_modules/nodemailer`. Le `package-lock.json` fixe la version et son intégrité. Si le registre est autorisé par l’IT, l’installation standard est `npm ci --omit=dev --ignore-scripts` depuis `reports/`. Ne pas copier les `node_modules` incomplets du poste de développement. L’interface signale l’absence du connecteur et interdit les envois tant qu’il manque.

Pour permettre la lecture sans navigateur connecté, l’IT doit créer `runtime.env` à côté du lanceur, depuis `runtime.env.example`, et y configurer **REPORTS_SUPABASE_SECRET_KEY** : clé serveur du seul projet ZENATA `iparzfqxopcvwqelxlad` (`sb_secret_…` ou ancienne clé `service_role` de ce projet). Ne jamais mettre cette clé dans le build Flutter, `web/`, Git, une URL ou un e-mail. Le runtime lit ce fichier au démarrage ; redémarrer après modification. La clé serveur est un secret privilégié : limiter les droits NTFS au compte d’exécution et aux administrateurs autorisés.

Autoriser depuis 208 : HTTPS vers `iparzfqxopcvwqelxlad.supabase.co:443` et connexion au relais SMTP sur le port fourni par l’IT. Les certificats SMTP sont vérifiés ; aucune option de désactivation de cette vérification n’est prévue. Le mode relais interne est sans authentification et sans chiffrement : choisir ce mode uniquement pour un relais prévu ainsi par l’IT. Sur l’accès HTTP choisi pour l’application, les paramètres SMTP saisis ne sont pas chiffrés pendant leur transit : effectuer cette configuration depuis la session locale du serveur ou le réseau d’administration approprié.

## Persistance et exploitation

Cette première version lit la base **Supabase existante**. Elle n’achève pas la migration métier vers SQL Server. Les programmations, paramètres, tentatives et traces d’administration sont persistés localement sous `.state/reports/reports.sqlite` (SQLite avec WAL), hors du répertoire publié. Le mot de passe SMTP est chiffré AES-256-GCM avec `.state/reports/smtp-master.key`, jamais renvoyé par l’API. Restreindre les ACL NTFS du dossier privé : la clé et la base ensemble permettent de déchiffrer ce mot de passe.

Sauvegarder ensemble `.state/reports/`, sa clé, les pièces jointes et `runtime.env`. Pour une copie cohérente simple, arrêter le runtime avant sauvegarde/restauration (inclure les fichiers SQLite WAL/SHM s’ils existent). Ne jamais remplacer la clé seule. Les pièces jointes sont conservées dans `.state/reports/artifacts/` et accessibles uniquement après contrôle administrateur. L’écran affiche les 200 dernières tentatives ; aucun nettoyage automatique des archives ou de l’audit n’est effectué. Prévoir sauvegarde, suivi de l’espace disque et politique de rétention avec l’IT.

Le moteur interroge les échéances toutes les 15 secondes, un envoi à la fois. Les échéances manquées pendant un arrêt sont rattrapées progressivement, par lots de 10, avec une file plafonnée à 1 000 tâches programmées. Une modification ou une mise en pause annule les tâches de ce rapport encore en attente/extraction ; elle ne rappelle pas un e-mail déjà en cours d’envoi. Les créneaux sont uniques et une tâche ne peut être prise que par un worker à la fois. Après interruption, une extraction échouée est relançable ; une transmission potentiellement acceptée est marquée **envoi incertain** et n’est jamais répétée automatiquement. Une acceptation partielle nécessite également un contrôle du relais. Le SMTP ne garantit pas une livraison « exactement une fois ».

**Accepté par le relais** signifie accepté par SMTP, pas reçu dans la boîte finale. Consulter les rejets/bounces côté messagerie. Les événements `report_started`, `report_finished`, `report_failed` sont dans les logs runtime avec l’identifiant d’exécution et un code, sans contenu du rapport ni mot de passe.

Le runtime doit rester actif même sans navigateur. Cette mise à jour n’installe aucun service Windows : prévoir avec l’IT un démarrage supervisé au redémarrage de 208. Une simple fenêtre ouverte dans une session RDP n’offre pas cette supervision.

## Données et limites de cette version

Les mouvements viennent des instantanés `generated_documents` ENTREE/SORTIE et le stock de `container_stock_intervals`. Pagination par identifiant au-delà de 1 000 lignes, sans troncature silencieuse ; plus de 100 000 lignes par source ou pièce jointe supérieure à 20 Mio provoque un échec explicite. Une présence de stock double/incohérente provoque un échec. L’inventaire d’ouverture doit exister dans les données pour apparaître au stock.

Les lectures REST successives ne constituent pas un instantané transactionnel global. Une correction/annulation rétroactive ou un ancien mouvement importé avec une date de document différente de sa date effective peut nécessiter une réconciliation. La période est d’abord filtrée sur la création du document puis sur la date effective ; les enregistrements ordinaires de l’application créent document et mouvement dans la même transaction. Les rapports sont des états opérationnels ; le contrôle de clôture reste à valider avec le métier.

Validation locale : tests calendriers, clients, mouvements doubles, bornes temporelles, chiffrement, persistance, verrouillage, reprise, API administrateur et transport SMTP simulé. Le classeur est relu avec la bibliothèque Dart Excel indépendante. Aucun test SMTP réel ni publication sur le serveur 208 n’a été effectué depuis le poste.

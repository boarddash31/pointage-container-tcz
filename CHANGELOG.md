# Changelog

## v3.1.0 — 2026-10-26

- Ordres EDO/ERO modifiables : référence unique, articles par armateur et ISO, ajout de quantité, protection des réservations et historique des modifications.
- Type automatique et grisé : ERO pour la restitution, EDO pour la livraison. Recherche d’armateur au clavier et formulaire espacé.
- Livraison bloquée avant 24 heures depuis l’entrée du camion de restitution ; contrôle des formats ISO à la sortie, y compris deux conteneurs.
- Data regroupée par client et ordre, avec numéro de transaction, créateur et dernier modificateur.
- Bons Charge/Décharge Marsa Maroc, auteur archivé et correction du cache d’impression.
- Version applicative `3.1.0+2`, publication GitHub avec tag `v3.1.0`.

## 2026-10-26 — Type d’ordre automatique

- À la création, type grisé et déterminé par le mouvement : ERO pour une restitution, EDO pour une livraison. Le survol ne permet plus de changer le type ; la recherche d’armateur reste disponible.
- 10 tests du formulaire passent, y compris les deux directions et le verrouillage au survol. Analyse des fichiers modifiés sans remarque.

## 2026-10-26 — Création EDO/ERO et choix au clavier

- Espacement ajouté entre le type d’ordre et la référence, et entre le titre d’article et son armateur ; retrait du texte d’aide « Référence unique dans tout le système ».
- Retrait de Booking des choix de création et des libellés du sélecteur d’ordres. EDO et ERO sont disponibles ; EDO crée un ordre de livraison et ERO un ordre de restitution.
- Ouverture du choix EDO/ERO au survol sur ordinateur, avec clic et clavier disponibles.
- Liste d’armateurs filtrée dès la première lettre, par code ou nom, sans distinction de casse ; validation au clic ou avec Entrée. Une recherche non confirmée ne peut pas enregistrer l’ancien armateur par erreur.

## 2026-10-26 — Ordres EDO/ERO modifiables

- Référence unique dans tout le système, avec articles distincts par armateur et code ISO sous un seul ordre.
- Modification des quantités totales, ajout d’articles et bouton d’ajout de quantité, y compris pour les articles épuisés. Une référence existante ouvre son ordre au lieu de créer un doublon.
- Conservation des articles utilisés et des liens de visites ; refus d’une quantité inférieure aux réservations et mouvements. Verrouillage et version empêchent une modification concurrente d’écraser une autre.
- Migration ZENATA appliquée : doublon compatible regroupé sans perdre les articles, historique et anciens identifiants conservés. 37 tests Flutter et contrôles SQL isolés/réels réussis. Version web à tester localement ; aucun déploiement Netlify pour ce changement.

## 2026-10-26 — Préparation de publication Netlify

- Version publique reconstruite avec les derniers bons Marsa Maroc et les ordres Booking/EDO/ERO ; mots de passe d'authentification retirés du programme client.
- Conservation des sessions et des raccourcis de profils ; le mot de passe doit être saisi ou fourni par le gestionnaire du navigateur.
- Règles Netlify corrigées pour préserver l'autorisation du lecteur et les routes de l'application. Archive de publication prête, déploiement externe en attente d'un accès Netlify utilisable.

## 2026-10-23 — Correction de l'ancien bon sur localhost

- Attendre la suppression de l'ancien cache Flutter avant de charger l'application, conserver la session et servir un programme versionné.
- Aperçu local sur `/marsa-bons-v1/` ; le repli PDF refuse le modèle TCZ archivé et exige le nouveau modèle Marsa.
- Générateur Supabase version 2 publié ; nouveaux chemins de PDF par format. 33 tests Flutter et les tests Node de cache passent.

## 2026-10-23 — Bons Marsa Maroc

- Reprise du modèle fourni pour les bons Charge et Décharge : logo, visite, immatriculation/CIN, tableau sans bordures pour un ou deux conteneurs, agent, date et pied de page.
- Les réimpressions préservent les données de l'événement archivé ; le nom de l'auteur est enregistré sur les nouveaux bons. Date de Casablanca et identité de visite accessibles aux lecteurs autorisés sans ouvrir les profils privés.
- 31 tests Flutter passent, ainsi que les vérifications SQL isolées et réelles. Rendu serveur vérifié localement sur une page A5. Compilation web locale ; pas de publication du site ou de la fonction serveur.

## 2026-10-23 — Restitution, livraison et ordres

- Livraison bloquée en base avant 24 heures depuis l’entrée du camion de restitution, y compris les deux conteneurs Twin et les anciens RPC de sortie.
- Libellés Restituer 1/2 conteneurs et Livraison de 1/2 conteneurs.
- Création par le guichetier de Booking, EDO et ERO avec articles ISO, quantités autorisées, réservées, effectuées et disponibles ; contrôle atomique des dépassements.
- Proposition de bon de livraison A5 simplifié, avec références, conteneurs et signatures.
- 28 tests Flutter et les contrôles SQL isolés et réels passent. Migration ZENATA appliquée ; interface compilée localement, non publiée. Obligation générale des ordres à activer après publication.

## System-managed client orders — 2026-10-23

- Client/order attribution is reserved for an active Admin or trusted server-side service role. Gate clerks cannot assign, replace or clear it through current or legacy entry APIs.
- Gate entry keeps the current booking-entry workflow with no client/order selection controls. Data provides read-only Client + Order groups, then Armateur + Booking, preserving individual transactions.
- Grouping is ready to display supplied reference data; automatic EDI message ingestion and matching are not connected yet. Unassigned visits remain unassigned.
- Validation: 25 Flutter tests, SQL smoke tests and rolled-back live TCZ authorization tests pass. Static analysis reports two existing style notices and no errors or warnings. Web release rebuilt locally; not published.

## After v3 — 2026-10-20

- Gate-out now checks the booked ISO container length before accepting a pickup: 20-foot visits cannot take 40-foot containers, or vice versa.
- Validates the entered ISO, registered container ISO and open stock ISO before making changes; both twin containers must be 20-foot.
- Shows the reserved ISO on the gate-out form and explains size mismatches. Matching lengths with different heights remain allowed.
- Validated with 11 Flutter tests, database rejection/rollback tests and a rolled-back check on TCZ.

## v3 — 2026-10-20

- Data table with permanent transaction number, Réception/Livraison type, creator and last changer.
- Creation/change timestamps, transaction search, displayed counts and visit history.
- Both containers, bookings and armateurs shown for twin visits; canceled visits labeled correctly.
- Authorized transaction summary deployed to TCZ with restricted operator-name access.
- Updated web release; Android APK unchanged.

Validation: nine Flutter tests and extended database smoke tests pass. Static analysis reports only six existing style notices.

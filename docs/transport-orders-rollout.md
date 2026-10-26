# Restitution, livraison et ordres de transport

La migration `20261023144404_transport_orders_and_24h_delivery.sql` est appliquée au projet TCZ `iparzfqxopcvwqelxlad`, connexion ZENATA.

Le délai minimum de livraison est actif immédiatement : 24 heures depuis `truck_visits.entered_at` de la visite qui a restitué le conteneur (`container_stock_intervals.start_visit_id`). Il ne part ni de l'arrivée au stock ni du camion qui demande la livraison. Chaque conteneur du twin est vérifié. Une livraison sans stock, y compris par l'ancienne sortie forcée, est refusée. Les anciens chemins Engin et Gate sont contrôlés par les mêmes triggers.

## EDO et ERO

- `EDO` : livraison ; type automatique et grisé à la création depuis une livraison.
- `ERO` : restitution ; type automatique et grisé à la création depuis une restitution.
- L’interface crée uniquement EDO/ERO. Les anciens ordres `BOOKING` restent compatibles avec les API existantes.
- Une référence est unique dans tout le système, indépendamment du type, du sens ou de l’armateur. Un seul ordre contient plusieurs articles, identifiés par armateur et code ISO, avec une quantité entière positive par article.
- L'entrée réserve une unité par conteneur ; un twin réserve deux unités, éventuellement sur deux articles ou armateurs différents. Une même visite n'est pas comptée deux fois dans les groupes Data.
- Le mouvement effectif consomme la réservation. Une annulation avant mouvement libère la quantité ; après mouvement elle est refusée pour les visites liées à un ordre.
- Le verrouillage des ordres puis des articles dans un ordre déterministe sérialise les réservations et modifications concurrentes. Le contrôle de quantité, la visite, le stock, les événements et les bons restent dans la transaction PostgreSQL.
- Le guichetier peut créer les références et les articles. L'affectation client/ordre client demeure réservée à l'administrateur ou au service EDI, puis est reprise automatiquement sur la visite. Aucun connecteur EDI n'est livré : les RPC constituent seulement le point d'intégration.

Les migrations `20261026125117_editable_globally_unique_transport_orders.sql` et `20261026125249_transport_order_message_encoding.sql` ajoutent l’édition des articles et l’augmentation atomique de quantité. `update_transport_order` exige la version affichée et refuse un formulaire périmé ; `increase_transport_order_quantity` ajoute une quantité à l’article existant, même épuisé. La quantité totale ne peut pas être inférieure aux réservations et mouvements déjà effectués. Un article utilisé, même sur une visite annulée, conserve son ISO, son armateur et son identifiant.

Les doublons de référence compatibles sont regroupés sous le plus ancien ordre, avec conservation des identifiants d’articles et des liens de visites. Les anciens identifiants d’en-tête sont archivés dans `private.transport_order_aliases` et résolus lors des modifications. Les changements de quantité et d’articles sont audités.

## Déploiement progressif

La nouvelle application utilise `enter_transport_visit` et exige un article pour chaque conteneur. Les anciennes applications peuvent encore appeler leurs RPC d'entrée pendant la publication. Le contrôle de 24 heures s'applique aussi à ces visites.

Après publication et vérification de la nouvelle application sur l'adresse de production autorisée, exécuter avec une session administrateur :

```sql
select public.require_transport_orders(true);
```

Cette activation bloque les nouvelles entrées sans article par les anciens RPC. Les visites déjà créées peuvent terminer leur parcours, sous contrôle des 24 heures. Le changement est audité. Ne pas activer avant publication : l'ancien écran ne permet pas de choisir/créer les articles. En cas de retour à l'ancienne application, `require_transport_orders(false)` rétablit cette compatibilité ; les visites déjà liées conservent leurs contrôles de quantité.

Les dossiers `site/` et `app/build/web/` contiennent la compilation web ; `site/` est versionné avec le code source. La publication GitHub et le déploiement Netlify sont des opérations distinctes. La fonction `generate-bon` version 2 a été publiée sur ZENATA pour fournir le même format en repli ; la nouvelle application génère normalement le bon A5 localement via `BonPdfBuilder`.

## Vérifications

`tests/sql_smoke.cjs` teste les migrations et règles dans PostgreSQL/PGlite. `tests/transport_rules_live.sql` et `tests/editable_orders_live.sql` testent les RPC de la base réelle dans une transaction intégralement annulée. Les tests Flutter couvrent le filtrage des ordres, les articles épuisés, la création ERO multi-articles, le type grisé pour les deux mouvements, la recherche d’armateur, l’édition et ses conflits, le PDF twin et les parcours existants.

Le modèle Marsa Maroc fourni ensuite par l'utilisateur est repris pour les bons ordinaires : logo et titre « Bon Décharge » pour la restitution ou « Bon Charge » pour la livraison, visite, immatriculation, CIN, tableau sans bordures VOIE/Hnd/P-V/Conteneur/Ligne/ISO/Lg/Ht/Tp, agent du terminal, date et pied de page du modèle. Une deuxième ligne représente le deuxième conteneur ; les références Booking/EDO/ERO figurent sous le tableau. Les valeurs VOIE, P/V, Lg, Ht et Tp ne sont renseignées que lorsqu'elles figurent dans le snapshot ; l'état plein/vide n'est pas déduit du chargement du camion.

La migration `20261023151708_document_author_and_print_context.sql`, appliquée via ZENATA, conserve le nom de l'auteur dans les nouveaux snapshots et fournit au rendu un contexte de lecture autorisé (`document_print_context`) : auteur, numéro de visite issu de l'événement d'entrée et date convertie avec la zone IANA Africa/Casablanca. Les informations archivées priment sur les modifications ultérieures de la visite. Les réimpressions d'anciens bons utilisent le profil de l'auteur si le snapshot ne contient pas encore son nom. Cette lecture ne donne pas accès aux autres champs privés des profils.

Le rendu Flutter et le générateur serveur utilisent le même modèle et le même logo officiel embarqué. La fonction publiée version 2 réutilise uniquement un PDF du format demandé ; les autres sont régénérés sous un chemin `*-marsa-v1.pdf`, sans écraser l'ancien fichier. Le repli du client exige aussi ce format, afin de ne pas imprimer silencieusement l'ancien modèle après une erreur de rendu local. Exemples locaux : `.qa/bon-charge-modele.pdf` et `.qa/bon-decharge-modele.pdf`.

Lancer l'aperçu avec `node scripts/preview_web.cjs`, puis ouvrir `http://localhost:8787/marsa-bons-v1/`. L'adresse versionnée évite le document racine éventuellement conservé par un ancien worker. Le démarrage attend le nettoyage des caches Flutter concernés, sans effacer la session Supabase, et ne réenregistre pas le worker obsolète.

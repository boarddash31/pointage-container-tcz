# Pointage Container — progress

## v3.1.1 — 2026-10-27

- Bon de Sortie A4 TCZ / Marsa Maroc : présentation douanière, identification, données camion/chauffeur/agent, cadres ECOR et sortie du terminal.
- Conservation des faits archivés, prise en charge de deux conteneurs et du camion vide après restitution ; aucune supposition sur les champs douaniers ou le poids.
- Cache PDF SORTIE versionné gate-out-v1 ; l'ancien modèle est refusé en repli. Le générateur serveur nécessite un déploiement séparé.
- 49 tests Flutter réussis et compilation web vérifiée. Publication GitHub uniquement.

## Version GitHub v3.1.0 (2026-10-26)

- Demande utilisateur : pousser les dernières modifications avec un commit et une version. Branche `main`, nouveau tag annoté `v3.1.0` ; le tag historique `v3` est conservé. Version applicative `3.1.0+2` et documentation du fonctionnement actuel mises à jour.
- Validation finale : 41 tests Flutter réussis, contrôles SQL/PGlite, démarrage web, cache PDF, gardes de déploiement Netlify et 2 tests du pont d’impression réussis. Bundle web de version reconstruit et synchronisé dans `site/`, métadonnées `version.json` et `release.json` alignées sur v3.1.0.
- Le commit porte `[skip ci]` pour éviter le déploiement Cloudflare déclenché par le workflow actuel lors d’un push sur `main`. Cette demande porte sur GitHub ; aucune nouvelle publication Netlify/Cloudflare n’est lancée. Secrets `.env*`, archives et `.qa/` restent exclus de Git.
- L’accès au compte Admin reste à établir : l’utilisateur n’a pas le mot de passe ni accès à l’adresse préremplie. Une adresse e-mail contrôlée lui a été demandée, sans réponse avant sa demande de publication Git. Aucun compte ni mot de passe modifié.

## Publication demandée sur stalwart-travesseiro-1e8045 (2026-10-26)

- Publication de la version actuelle explicitement demandée sur `https://stalwart-travesseiro-1e8045.netlify.app/`. Le domaine et l’API Netlify sont résolus ; la page publique répond HTTP 200. Aucun plugin Netlify disponible dans la recherche.
- Contrôles ciblés autorisés : NETLIFY_AUTH_TOKEN absent du processus et de `.env.local`. Aucun secret/variable NETLIFY dans le dépôt GitHub `boarddash31/pointage-container-tcz` (deux secrets existants) ni dans son environnement `production`. Aucune valeur de secret affichée.
- Une première vérification élargie a été refusée automatiquement parce qu’elle associait recherche de jetons dans plusieurs sources et lecture brute de `.qa/gh-repo-state.json`, susceptible de contenir des secrets. Cette commande n’a pas été exécutée. Vérification plus sûre ensuite autorisée, limitée au nom NETLIFY_AUTH_TOKEN dans le processus et `.env.local`, puis métadonnées GitHub uniquement. Aucun contournement ni lecture de fichiers de sessions/navigateurs.
- Archive finale prête : `.qa/netlify-v3-fixed-order-c79dc072.zip` (60 fichiers, 15 152 150 octets), staging `.qa/netlify-ready-b556da28e4`. Métadonnées `.qa/netlify-package.json`. Programme SHA256 `219b6001631f9b7a117cd66a91f955f58818d7269064db195776eb9362680d9c`. Pas d’APK, worker Cloudflare, fichier .env ou démonstration dans l’archive. Archive vérifiée avec index/programme/redirections à la racine et chemins ZIP conformes.
- Nouveau déploiement Node `scripts/deploy_netlify.cjs`, sans téléchargement de CLI ni désactivation TLS : lit uniquement NETLIFY_AUTH_TOKEN dans le processus ou `.env.local`, vérifie le nom exact du site avant tout POST, refuse le site alternatif, vérifie l’empreinte de l’archive et du programme, attend le résultat puis vérifie l’empreinte publique. Tests des gardes de cible et contrôle de l’archive réussis. L’ancien script PowerShell conserve une cible par défaut différente ; ne pas l’utiliser pour cette publication.
- Aucune publication, aucun push ou autre hébergeur utilisé. Question envoyée pour configurer le jeton dans `.env.local` ou choisir une publication manuelle de l’archive. L’accès Netlify reste nécessaire ; ne pas prétendre le déploiement effectué.

## Création limitée à EDO/ERO et listes interactives (2026-10-26)

- Dernière demande : le type de création est désormais automatique et grisé, ERO pour RESTITUTION, EDO pour LIVRAISON. Retrait de l’ouverture au survol du champ de type ; la direction envoyée reste celle du mouvement choisi. Les armateurs conservent leur recherche au clavier. Les 10 tests du formulaire passent, analyse des fichiers modifiés sans remarque ; compilation web finale réussie, build et `site/` synchronisés. Version `v3-fixed-order-type-20261026` vérifiée via HTTP sur localhost:8787 : programme servi identique au build final. Aucun déploiement externe.
- Ajustements visuels demandés : 32 px entre Type d’ordre et Référence, retrait du texte d’aide d’unicité, 24 px entre le titre de chaque article et Armateur, puis entre Armateur et ISO/Quantité pour éviter les chevauchements. Articles séparés par une marge verticale de 10 px, intérieur de 16 px et champs ISO/Quantité séparés de 20 px. Dernière demande « plus d’espace entre les tabs » interprétée dans le contexte du formulaire après demande de précision sans réponse. Les 9 tests du formulaire passent après ces ajustements.
- Demande utilisateur : retirer Booking de la création, réagir aux lettres saisies dans la liste déroulante et ouvrir le choix EDO/ERO au survol. Interface de création et libellés d’entrée/sélection mis à jour ; les données historiques et API de réservation restent compatibles.
- Création initialisée à EDO pour la livraison et ERO pour la restitution. Les deux types sont proposés au survol/clic/clavier et la direction envoyée suit le type effectivement choisi. L’édition conserve le type et la référence existants.
- Armateurs via DropdownMenuFormField filtrable par code/nom, casse ignorée, focus clavier et validation Entrée. Validation du texte par rapport à l’élément sélectionné pour empêcher de soumettre une recherche inachevée avec un ancien identifiant. Les articles utilisés restent protégés.
- 40 tests Flutter passent, dont 9 tests du formulaire : survol avec souris simulée, absence de Booking, changement de type/direction, filtrage à la première lettre, validation Entrée et refus de recherche non confirmée. Analyse des fichiers modifiés sans remarque. Compilation web finale réussie et `site/` synchronisé, version locale `v3-edo-ero-ui-20261026`. Aperçu sur `http://localhost:8787/marsa-bons-v1/` vérifié via HTTP : programme identique au build final et nouvelle saisie d’armateur présente. Aucun déploiement externe.

## Ordres EDO/ERO modifiables et référence unique (2026-10-26)

- Confirmation utilisateur : référence unique partout, indépendamment du type et de l’armateur. Un ordre contient désormais des articles armateur + ISO ; les formulaires permettent de modifier le total, ajouter des articles et ajouter une quantité à un article existant même épuisé. Le type et la référence d’un ordre existant restent stables.
- Migrations ZENATA `20261026125117` et `20261026125249` appliquées. Deux ERO MEDU123456 regroupés sous le plus ancien ; deux articles conservés (MAE et MSC), visite liée conservée. Identifiants des articles inchangés et ancien identifiant d’ordre archivé/résolu pour les appels de modification.
- Les RPC autorisent le guichetier d’entrée, l’administrateur et l’EDI via service_role. Pas de modification directe des tables ni d’accès anonyme. Audit des changements, verrouillage ordre puis articles, incréments atomiques et contrôle de version de l’éditeur. Identité/suppression des articles utilisés protégées, quantité minimale réservée/effectuée contrôlée en base.
- 37 tests Flutter passent (6 tests EDO/ERO), contrôles SQL PGlite, cache du démarrage, cache PDF et 2 tests bridge réussis. Le test réel `tests/editable_orders_live.sql` valide les API dans une transaction annulée. La migration de correction des accents utilise WIN1252, indisponible dans PGlite ; vérifiée sur PostgreSQL ZENATA. Les avis Supabase sur les nouvelles fonctions definer correspondent aux API authentifiées avec contrôle interne ; archives privées volontairement sans politique d’accès client.
- Compilation web locale et publication Netlify distinctes : aucun push ni déploiement public demandé/exécuté pour ce changement. L’ancienne archive `.qa/netlify-v3-marsa-20261026.zip` ne contient pas les nouveaux ordres modifiables ; elle ne représente plus le bundle courant.
- Aperçu local vérifié sur `http://localhost:8787/marsa-bons-v1/` : HTTP 200, cache no-store, empreinte du programme identique au build final, nouvelles API présentes ; navigateur Edge isolé démarré avec vue Flutter. Build et `site/` synchronisés, version `v3-editable-orders-20261026`, SHA256 `a9615376174a4ab9d3835ea6825d4fb70bf8f013c05f68ca3c8bb6fab9afe427`. Analyse des fichiers modifiés sans remarque ; deux infos de style préexistantes dans pointage_screens.dart.

## Préparation de publication Netlify autorisée (2026-10-26)

- Cible explicitement demandée : `https://stalwart-travesseiro-1e8045.netlify.app/`. Aucune publication vers un autre projet/hébergeur n'a été lancée.
- Retrait des mots de passe d'authentification intégrés à l'écran public et des boutons qui les soumettaient automatiquement. Raccourcis de profils conservés, mot de passe masqué et vide, sessions existantes conservées. 33 tests Flutter passent ; analyse Dart sans erreur/avertissement (deux infos préexistantes), SQL et contrôles de cache passent.
- Recompilation web avec AUTH_SITE_URL égal à la cible demandée. Bundle courant vérifié : modèle Marsa, contexte d'impression et ordres présents, ancien mot de passe de test absent. Les règles Netlify transmettent le JWT du lecteur au lieu de le remplacer par un JWT anonyme ; règles de navigation incluses dans `_redirects` pour les déploiements manuels.
- Archive prête `.qa/netlify-v3-marsa-20261026.zip` (14,44 Mio, 60 fichiers), sans APK, ressources de démonstration ni worker Cloudflare. `site/release.json` décrit cette version et son empreinte JS. Empreinte du bundle : `e06ea6a62616f3d28ac88f7ecc406b5883b1ab11ebaf1db6d2b26e88a4421827`.
- Publication en attente d'un accès externe utilisable. Aucun NETLIFY_AUTH_TOKEN trouvé dans l'environnement de processus/utilisateur/machine, les fichiers locaux ou les emplacements de configuration CLI vérifiés. GitHub expose seulement les secrets Cloudflare et un environnement production sans secret Netlify ; les déploiements visibles sont Cloudflare. L'utilisateur indique que le jeton est déjà sur le projet Netlify/GitHub, mais son emplacement utilisable n'est pas identifié. Aucun ancien token n'a été récupéré dans l'historique.
- La découverte de plugins n'a pas trouvé de connecteur Netlify. La tentative de récupération du CLI officiel 27.14.2 via npm a été refusée par la politique de transfert de fichiers de l'entreprise. Aucun contournement de ce blocage n'a été tenté. Le site cible n'était pas résolu par le DNS local lors de la vérification initiale.

## Ancien bon encore imprimé sur localhost (2026-10-23)

- L'utilisateur a précisé `http://localhost:8787`. Le serveur fournissait bien le bundle Marsa et son logo ; le HTML lançait toutefois le nettoyage du cache sans l'attendre, puis le bootstrap Flutter réenregistrait un worker. Nouveau bootstrap : suppression attendue des seuls caches/workers Flutter concernés, conservation de la session Supabase et URL de programme versionnée ; pas de réenregistrement du worker.
- Serveur local redémarré depuis `scripts/preview_web.cjs`. Nouvelle adresse `http://localhost:8787/marsa-bons-v1/` : base et ressources versionnées pour éviter le document racine conservé par un ancien worker. La racine redirige vers cette adresse. Bundle, bootstrap et logo vérifiés via HTTP.
- Le repli PDF exige le format `marsa-v1` et ne télécharge plus l'ancien PDF archivé si le rendu local échoue. Générateur Supabase `generate-bon` version 2 publié sur TCZ via ZENATA, JWT conservé. Les bons ordinaires prennent un nouveau chemin `*-marsa-v1.pdf`, sans écraser les anciens fichiers ; les annulations conservent leur format.
- 33 tests Flutter passent ; tests Node du démarrage et du cache PDF passent. L'ancien PDF est refusé par le repli, le PDF régénéré est accepté. Web recompilé ; site public non publié, conformément au diagnostic local.
- Le test distant authentifié n'a pas été exécuté : la validation automatique a refusé l'utilisation du mot de passe de test lu dans le code pour ouvrir une session et générer/téléverser un bon. Aucune tentative indirecte ni nouvelle visite n'a été effectuée. Les vérifications locales et le déploiement authentifié du générateur via ZENATA sont indépendants de ce test.

## Modèle de bon Marsa Maroc fourni par l'utilisateur (2026-10-23)

- Modèle reçu : capture intitulée « Bon Charge ». Application du format aux bons ordinaires avec « Bon Décharge » pour la restitution et « Bon Charge » pour la livraison. Logo officiel Marsa Maroc embarqué sans modification, provenance conservée dans `app/assets/brand/MARSA-MAROC-SOURCE.md`. Tableau sans bordures à 1/2 lignes, visite, plaque/CIN, agent du terminal, dates et pied de page du modèle ; références d'ordre sous le tableau.
- Nouveau modèle de présentation `TerminalSlip` : snapshot prioritaire sur la visite actuelle, conteneurs effectifs de l'événement PRISE, aucune supposition sur le plein/vide ou la voie lorsqu'ils ne sont pas enregistrés.
- Migration `20261023151708_document_author_and_print_context` appliquée sur ZENATA : nom figé sur les futurs snapshots, lecture autorisée de l'auteur/numéro de visite/date Africa/Casablanca. Les essais réels ont été annulés intégralement. Le service PDF récupère ce contexte pour qu'une réimpression par un autre agent conserve son auteur.
- 31 tests Flutter passent ; tests SQL/PGlite et `tests/document_printing_live.sql` passent. Analyse Dart sans erreur/avertissement (deux infos de style préexistantes). Générateur serveur contrôlé en syntaxe TypeScript et exécuté localement avec pdf-lib 1.17.1 : logo, accents et deux conteneurs sur une page A5.
- Exemples `.qa/bon-charge-modele.pdf` et `.qa/bon-decharge-modele.pdf`. Source Edge Function mise à jour mais pas redéployée. Interface compilée localement ; aucun push/déploiement public pour ce changement, APK inchangé.

## Restitution, livraison et ordres avec quantités (2026-10-23)

- Confirmations utilisateur : les 24 heures partent de l'entrée du camion de restitution ; le guichetier peut aussi créer Booking/EDO/ERO et leurs articles/quantités.
- Migration `20261023144404_transport_orders_and_24h_delivery` appliquée sur TCZ via ZENATA. Triggers actifs sur stock et visite : 24 heures par conteneur, absence de stock/ancien forçage refusés, contrôle des deux slots et de l'armateur, rollback complet en cas de refus.
- Nouvel écran de création et sélection Booking/EDO/ERO avec plusieurs articles ISO et quantités autorisées, réservées, effectuées, restantes. Nouvelle entrée liée aux articles ; verrous de réservation déterministes, twin compté deux fois, annulation avant mouvement libérant la réservation. L'identité client provient uniquement d'un ordre administrateur/EDI ; aucun sélecteur client au guichet.
- Déploiement progressif : `private.transport_order_controls.required=false` pour conserver l'ancien écran en ligne. Après publication de la nouvelle application, `require_transport_orders(true)` sous session admin impose les articles sur tous les nouveaux appels historiques. La nouvelle application exige déjà les articles. La documentation de bascule est dans `docs/transport-orders-rollout.md`.
- Noms d'opération changés et bon de livraison A5 simplifié proposé. Exemple local `.qa/bon-livraison-exemple.pdf`. Aucun modèle utilisateur n'étant joint, le format n'est pas présenté comme une reproduction. Edge Function modifiée dans les sources uniquement ; pas redéployée.
- Validation : 28 tests Flutter passent ; SQL/PGlite étendu passe, y compris second twin trop récent, refus atomique, frontière exacte de 24h, quotas, rôles et attribution dérivée. Test réel `tests/transport_rules_live.sql` réussi dans une transaction annulée (aucune donnée QA conservée). Analyse Dart sans erreur/avertissement, deux infos de style préexistantes. Web release compilée, copiée dans `site/`, disponible sur `http://localhost:8787` ; aucun push/publication pour ce changement. APK inchangé.

Updated: 2026-10-23 (Africa/Casablanca)

## Source audit

- Read `README_START_HERE.md` and `05_codex_instructions/PROMPT_FOR_CODEX.md`.
- Inspected V6 HTML, V2 reference, truck artwork, UI montage, six spreadsheet reports, 95 armateurs in `02_operator_logos/operators.json`, and the separate real-logo source pack. V6 is a localStorage demo, not a production backend. Every archive logo manifest entry is an unverified placeholder; keep text fallback.
- Parsed XLSX report layouts, including `REP_FREE_POOL`/`FREEPOOL JOURNALIER`. Original XLS formula-level review and reconciliation remain open.
- The TCZ Supabase project `iparzfqxopcvwqelxlad` had no public tables or Auth users before deployment. Six migrations (including the 95-armateur catalog) were applied on 2026-10-20; the Table Editor now lists the created tables. Both Edge Functions were deployed. The existing public schema was empty, but a database dump was unavailable because Docker/Podman is not installed.

## Milestones

| ID | Deliverable | Status | Verification |
|---|---|---|---|
| M0 | Source audit, architecture, executable plan | Partial | Source inventory and XLSX layouts reviewed; legacy XLS formulas pending |
| M1 | Supabase schema, roles, RLS, transactional Entrée/Engin/Sortie, 95 armateurs | Deployed to TCZ; authenticated E2E pending | Six migrations applied. Table Editor lists tables; service-role count is 95 armateurs, anonymous read returns zero; anonymous function calls return 401. Isolated PGlite lifecycle/RLS tests pass. Authenticated live workflow and concurrency tests pending |
| M2 | Flutter Entrée/Engin/Sortie + Auth, FIFO and checksum | Web release tested; Android out of current scope | Flutter 3.47.2 analyze and 22 tests pass. Web release succeeds. Android/iOS device runs remain outside the current web-only delivery request |
| M3 | Data, Bons PDF + private Storage and safe print flow | Partial | `generate-bon` deployed and anonymous calls denied. UI, Flutter-to-Node authenticated bridge, preferred-printer direct-print path and document-action audit present; two bridge tests pass. Authenticated PDF generation/share/printer verification pending |
| M4 | Web admin, clients, RBAC, assignments, analytics | Partial | Admin UI can invite agents with initial role through deployed `invite-user` Edge Function; first admin invitation and role created. Role matrix and browser acceptance pending |
| M5 | Freepool historical stock and Excel export | Partial | SQL report and workbook source present; synthetic XLSX round-trip test passes. Historical opening stock and source-report reconciliation pending |
| M6 | Deployment hardening and end-to-end acceptance | Web deployed; custom domain DNS pending | Public Cloudflare Pages production URL returns HTTP 200; API health returns 200 and retired APK paths return 404. `marsa.digital` is attached to Pages but public DNS does not resolve until registrar nameservers point to Cloudflare. Authenticated workflow and printer acceptance remain open |

## Architecture and implementation

Flutter widgets for Android/iOS and web. Supabase Auth authenticates each operator. RLS scopes reads; SQL RPCs make each state transition atomic and write visit events/audit. The client uses a publishable key only. Container master is separate from truck visits and container stock intervals. Entrée loaded -> Engin Dépose -> Sortie camion, or Entrée empty booking -> Engin Prise -> Sortie loaded. Sortie may complete a missing Engin step. A private Storage bucket holds generated PDFs; browser printing uses the normal dialog. Freepool distinguishes end-of-day stock from any-time presence and does not invent billing rates.

Generated Android, iOS and web platform projects with Flutter 3.47.2. Resolved a `printing`/`excel` dependency conflict by pinning `printing` to 5.14.3, fixed analyzer findings and a SQL reserved-word error in `freepool_rows`, and repaired stale lookup feedback/ISO form refresh on Entrée. Added admin-only forced pickup with reconciliation queue, active-carrier uniqueness, document access audit, audited manual container registration and optional automatic printing to a locally selected system printer. The Windows native-assets hook fails when SDK/project paths contain spaces; no-space junctions `E:\flutter_sdk_tcz` and `E:\pointage_tcz` enabled successful tests and build. `app/README.md` and `.env.example` document local setup without secrets.

On 2026-10-20, fixed the widget navigation fixture by disabling Supabase token auto-refresh; it had left a timer running after the test. Re-ran the full Flutter suite (3 passing), Flutter analyze (no issues), database smoke test, and two Node bridge tests. Rebuilt Flutter web successfully. The build still reports a non-blocking Wasm dry-run warning from the transitive `image` package and an icon-font warning; generated JavaScript web output succeeds.

Release work on 2026-10-20: created an ignored release keystore outside Git, replaced debug signing and example Android package ID, and built a v2-signed APK. The first Android build hit a Kotlin incremental-cache error; disabling Kotlin incremental compilation and using the in-process compiler resolved it. The configured web build and APK are copied into `site/` for Netlify. The release keystore at `E:\pointage_release_secrets` must be backed up securely before future updates.

## Open acceptance blockers

- The TCZ database is now migrated, but Auth invitation acceptance, authenticated workflow and private PDF Storage have not been exercised on a real client. No database dump is available because Docker/Podman is absent; the schema was empty before migration.
- The PDF Edge Function is deployed but no authenticated PDF has been generated. The authenticated Node bridge is implemented and tested for Supabase-authenticated shared-folder archiving, document audit and optional Windows printer submission; Flutter invokes it after save or from Bons when configured. It is not configured or deployed. `\\172.16.3.98\TCR PrintM` is an installed, reachable Windows **printer share**, not a PDF folder. The separate `\\172.17.18.218\pdf` archive share was read-only checked as reachable. A temporary write/read/delete probe was automatically rejected by environment policy, so archive write permissions remain unverified; real printer output is also unverified. Preferred local-system-printer direct printing is also untested with hardware. Browser silent printing is unsupported.
- TCR/port versus departed external lifecycle states and synchronization with the other operational database are not implemented; the current stock model tracks TCZ yard presence and truck visits. The exact event mapping and write authority need confirmation against Navis/other system before adding transitions.
- Freepool workbook has not been reconciled to supplied source figures. Unknown historical opening stock, EVP/billing policy, legal PDF footer, actual booking authority, and licensed logos require domain validation.
- iOS build needs macOS/Xcode; Android SDK and real devices are not configured here. Flutter web build succeeded with a non-blocking Wasm dry-run warning in a transitive `image` package; JS output was built.
- Private GitHub repository `boarddash31/pointage-container-tcz` has source on `main`. Netlify site `https://stalwart-travesseiro-1e8045.netlify.app/` was made public after user approval. External page GET and APK HEAD returned HTTP 200; downloading the full 58,854,286-byte APK produced SHA-256 `bbdb0bc1082919cde48e52a444ed503748d2a735e8a792af3727d9eb52691a00`, matching the local signed release. The public Flutter login renders and exposes the APK download button. Supabase Auth Site URL and the `/**` redirect are configured. A password-recovery email was sent to the first admin after the URL change; Supabase reports it is valid for 60 minutes. Human activation is still pending.

## Next action

Have the first admin open the recovery email within 60 minutes and set a password, then verify authenticated workflows, private PDF Storage, print bridge and Freepool reconciliation. Flutter tests (3), analyze, SQL smoke and bridge tests (2) passed again on 2026-10-20. Do not label this production-ready before these checks pass.

## Auth recovery follow-up (2026-10-20)

## Enregistrement entrée & Authentification résolus (2026-10-20)

- Identifié la cause du blocage initial ("enregistrer mkhdamach") :
  1. L'envoi des e-mails Supabase Auth était bloqué par le quota d'envoi du tier gratuit Supabase (`429 over_email_send_rate_limit`), empêchant la réinitialisation du mot de passe admin par e-mail.
  2. Comptes de test admin et agent activés via l'API Supabase Admin ; les JWT et accès RLS ont été vérifiés. Les anciens mots de passe ayant été publiés dans le code et l'historique Git, leur rotation est obligatoire avant usage en production.
  3. Les anciens boutons d'accès en un clic et les identifiants affichés sur la page de connexion ont été retirés du code courant.
- Résolution des blocages sur l'enregistrement de l'entrée (`EntryScreen`) :
  - Support du collage du numéro de conteneur complet (bouton "Coller" dédié et raccourci Ctrl+V / Cmd+V) distribuant les 11 caractères dans les cases respectives.
  - Calcul dynamique du chiffre de contrôle ISO 6346 (`ContainerNumber.expectedCheckDigit`) avec suggestion en temps réel ("Appliquer X" dès que 10 caractères sont saisis, badge vert "Numéro ISO 6346 conforme et vérifié", ou "Corriger en X" en cas d'erreur de saisie).
  - Suppression de la validation silencieuse sur la case 0 qui bloquait l'envoi sans message lisible.
  - Présélection automatique de l'armateur par défaut (Maersk `MAE`) pour ne plus bloquer la soumission.
  - Gestion explicite des erreurs SQL / contraintes de terminal (ex. conteneur déjà présent dans le terminal via `one_active_container_on_truck`).
- Tests et compilation :
  - Suite de tests Flutter (4 tests unitaires et widgets) validée à 100%.
  - `flutter analyze` : 0 avertissement, 0 erreur.
  - Build complet release exécuté : APK signée v2 (`site/downloads/pointage-tcz.apk`) et build Web de production (`site/`) prêts pour déploiement Netlify.









## Data transaction traceability (2026-10-20)

- Added a searchable Data table with transaction number, Reception/Livraison type, truck, both containers/bookings/armateurs, status, creator, last changer and creation/change timestamps. Clicking a transaction number opens the visit history. Counts describe the loaded window of the 500 newest visits.
- Numbers reuse the permanent ENTREE event identity; visits without an entry event fall back to their UUID. Creator comes from entered_by; last changer and timestamp come from the latest truck_visit audit record, with creator/entry time as fallback. Missing display names fall back to user UUIDs.
- Applied transaction_data to TCZ through ZENATA as migration 20261020155355. The guarded read-only RPC returns names only for readers authorized by can_do('read'); it does not grant general access to other profiles. Added a partial index for latest-visit audit lookup. Live authenticated summary returned seven rows with complete identity fields.
- Nine Flutter tests and extended isolated SQL smoke tests pass. SQL checks verify stable numbers, preserved creators, updated changer identity, authorized agent access, profile isolation and denial for unassigned users. Dart analysis has no errors/warnings and the same six existing style notices.
- Supabase Advisor flags data_transactions as an authenticated SECURITY DEFINER RPC; this is intentional for the limited profile-name lookup, with explicit read authorization and no anonymous execution. Existing unrelated advisor findings remain.
- Source and backend updated; the web release and APK have not been rebuilt or published for this change.

## v3 release (2026-10-20)

- Rebuilt the web release with the TCZ publishable configuration and copied it to site/. Verified local HTTP 200 for the page and compiled bundle; the bundle contains the transaction-summary endpoint. Opened the app at http://localhost:8787/.
- GitHub release marker: annotated tag v3. The Android APK is unchanged because this machine has no release signing configuration.

## Gate-out ISO length validation (2026-10-20)

- Added migration 20261020162717_gate_out_iso_length_check to TCZ through ZENATA. Pickup checks compare the original visit length code against submitted ISO, registered container ISO and open stock ISO before any upsert or movement. Twin pickups require two 20-foot containers; missing pickup details are rejected unless a previous Engin movement already completed. Empty cancellation and loaded deposit remain available.
- Added matching Flutter validation and reserved-ISO guidance. This checks container length, allowing different heights/types of the same length (for example 42G1 and 45G1 are both 40-foot).
- Eleven Flutter tests pass. Extended isolated database tests cover both mismatch directions, false ISO declarations, second twin mismatch, missing pickup, unchanged records after failure, valid same-length pickups, valid twins and empty cancellation. A live rolled-back authenticated test confirmed that a 20-foot visit rejects a 40-foot pickup.

## Gate truck visual and role separation update (2026-10-21)

- Added a responsive truck preview for Entrée and queue/action cards. It renders a dark container label with container number (or `?` when not yet entered), ISO code and armateur/line; Twin mode renders two labels side-by-side.
- Added Moroccan truck plate validation and normalization (`12345-A-06`, with scanner-friendly `12345A06` input). Invalid plate formats are rejected before the Entrée RPC.
- Role enforcement already scopes the shell and backend RPCs: an account with `entree` sees Entrée, an account with `sortie` sees Sortie, and an admin can assign either role from Admin > Profils. Separate one-click test accounts still need to be created in Supabase Auth and assigned their single role.
- Tests: full Flutter suite 13 tests passed; `flutter analyze --no-pub` completed with the existing six style infos and no errors.

## Truck diagram release (2026-10-21)

- Entrée now offers four horizontally scrolling truck choices: loaded mono/twin and empty mono/twin. A live diagram draws each container or empty slot above the chassis. Loaded containers are red with white number, ISO and line text; the truck plate appears on the cab. Missing required container details receive a yellow outline. Tapping the cab or either slot focuses the relevant form field.
- Single-role agents land directly on their permitted gate. Removed public one-click credential buttons and passwords from the current web and mobile code and this document. Previously published bundles and Git history exposed those credentials, so both Supabase Auth passwords still require rotation; removal from code alone is insufficient.
- Flutter analyze passed without issues; all 15 tests passed. Release script built the signed Android APK and production Flutter Web output. APK SHA-256: `b26b86a261f210b16fa09d09d0d46fd69ddb36bb7054e710535189863af4e696`.
- Authenticated end-to-end operation, private PDF output, archive writing and physical printing remain unverified. Do not mark production acceptance complete until these checks and credential rotation pass.

## Agent accounts and responsive truck cards (2026-10-21)

- Invited two initial Supabase Auth accounts using aliases of the owner's Gmail mailbox: one for Entrée and one for Sortie. Verified that each has exactly its intended role in `public.user_roles`; the profile display names were set accordingly and role setup was audited. Invitation acceptance remains pending. Replace the aliases with the actual operators' email addresses before handing out access.
- Disabled the legacy shared agent profile in Supabase and verified `active=false`; its old multi-role login can no longer pass app role checks or the backend `can_do` guard. The exposed admin password still requires rotation by the account owner.
- Redrew the truck as Flutter vector artwork with clearer cab/plate, chassis, wheels, red corrugated containers and outlined empty slots. The selected card now shows the live plate, container/booking, ISO and armateur, including missing-field highlighting and tap-to-focus. Removed the separate truck preview below the choice row; the four larger cards remain horizontally scrollable.
- Twin entry details use two columns on wide web screens and stack on mobile. Added a responsive widget test for both layouts. Flutter analyze passed and all 16 tests passed. The signed APK and production Web release both built successfully; APK SHA-256: `2710e2b673291e7b521338fece8b7008784ecb126d54ae959547ea5cffa55432`.
- Live browser review after disabling the exposed shared agent revealed that a disabled session landed on an access screen without a logout action. Added a visible sign-out button and a widget test so the operator can switch to a valid account. Flutter analyze and all 17 tests passed; rebuilt the signed APK and production Web release. New APK SHA-256: `d0470b6e95bbf2fbaa65f1412b422d2f0e44eb5c754cbab7d4d4863d16655c4f`.

## Safe quick access profiles (2026-10-21)

- Restored three prominent login shortcuts for Admin, Entrée and Sortie. Each selects the corresponding email and focuses the password field; it never stores or submits a public password. Agents can still edit the email to use their eventual individual account. A widget test checks all three shortcuts and verifies the password remains blank.
- The previous password-based one-click login cannot be safely restored because its credentials remain visible in historic public builds. The new invitations must be accepted before the two agent shortcuts can authenticate. Flutter analyze and all 18 tests passed; signed APK and production Web builds succeeded. APK SHA-256: `466f4e0a4becd7725d32dc05247d2dc5a42d55891b29d93d8aa427fd70e4f782`.

## Device sign-in convenience (2026-10-21)

- Supabase Flutter already persists the authenticated session on each device by default, so reopening the app resumes the user's assigned workflow without entering credentials again. Added platform autofill hints for the first sign-in and clarified this on the login screen. The public role shortcuts still require their own credentials; embedding Admin or agent passwords in a public build would give every visitor those roles.
- Flutter analyze and all 18 tests passed. Signed APK and production Web builds succeeded. APK SHA-256: `3a88be1a082731de14fa1a1ea5af26fd0bc73e89f12f484d0114cff254cc9766`.

## TCZ identity and gate illustrations (2026-10-21)

- Created an original navy/cyan TCZ identity with a port crane, suspended container and wave; vector masters and reproducible raster generation are in `app/assets/brand/` and `scripts/generate_brand.cjs`. Applied it to login, the application header, web loading screen, favicon, PWA icons and Android/iOS launcher assets. iOS assets are supplied; no iOS build was run on Windows.
- Redrew the truck cab, plate, trailer and red corrugated containers. Live container/booking, ISO and line values sit inside the container; empty slots use pale cyan outlines. Required data uses an amber marker and readable prompts. The selected gate card expands, remains in the horizontal row, and scrolls into view. Tap-to-focus and Twin layouts are preserved.
- Reviewed rendered desktop (1320 px) and mobile (390 px) previews with live plate, container and ISO values. Fixed card overflow; Flutter analyze and all 20 tests passed. Retained the existing character-editing changes already present in the working tree.
- Release build and publication verification are in progress. This visual update does not establish production-security readiness: the current branch contains pre-existing test-account shortcuts.

## Web-only release and marsa.digital (2026-10-23)

- Per the latest request, stopped the Android/APK release path and focused delivery on the web app. Removed the APK download action from login and removed the old APK and checksum from `site/`; the Cloudflare worker now explicitly returns 404 for `/downloads/*`.
- Restored the Admin, Entrée and Sortie quick-profile buttons. Each selects its account email and focuses the password field; the password stays blank and is never embedded or submitted by the shortcut. Authenticated sessions continue to persist on the device.
- Fixed the `/dashboard` redirect loop: the worker now lets Cloudflare Pages resolve the clean URL to `dashboard.html`. Rebuilt and deployed the Flutter web bundle with the quick-profile shortcuts; the GitHub Actions deployment completed successfully for commit `34aab87`. Live checks returned 200 for `/`, `/dashboard`, `/admin`, and `/api/health`; the retired APK path still returns 404.
- The web-only release script now runs Flutter analyze, the full 22-test suite and a web release build, then stages only web files. `flutter analyze --no-pub` passed with no issues; all 22 Flutter tests passed; the production web build succeeded. Flutter's optional WebAssembly dry run reports the existing transitive `image` package lint incompatibility, while JavaScript web output still compiles successfully; the script skips that non-blocking dry run.
- Deployed to Cloudflare Pages. The stable `https://pointage-container-tcz.pages.dev/` URL returned HTTP 200; `/api/health` returned HTTP 200; `/downloads/pointage-tcz.apk` returned HTTP 404. Added the Cloudflare Pages deployment credentials as GitHub Actions secrets so future pushes can deploy the web files.
- Attached `marsa.digital` to the Pages project; Cloudflare reports the domain status as `initializing`. Public DNS currently returns no records. The Cloudflare zone is active and requires registrar delegation to `arturo.ns.cloudflare.com` and `holly.ns.cloudflare.com` before the custom domain can resolve. Until then, use the stable `pages.dev` URL.
- The legacy Netlify URL remains a separate stale deployment; Netlify previously reported exhausted operational credits. The current supported web release is the Cloudflare Pages deployment.

## Admin dashboard access and compact Groupage (2026-10-23)

- Secured the legacy admin dashboard with a persistent Supabase Auth session and an Admin-role check. Dashboard RPC calls now forward the signed-in access token through the Cloudflare worker; the matching SQL wrappers restrict dashboard, agent and groupage operations to authenticated Admins.
- Replaced the oversized Groupage cards with compact searchable Armateur and Client tables. Desktop supports dragging an Armateur row onto a Client; touch/mobile also has a direct assignment control and quick-assign dialog. Assignment, removal, client creation and refresh continue to use Supabase RPCs.
- Hid dashboard content until the Admin session is verified and removed the old supervisor PIN from the public dashboard HTML and fallback labels. Kept the source and packaged dashboard copies identical.
- Verification: `npm run test:db` passed (lifecycle, stock, roles, RLS and 95 operators); `npm run test:bridge` passed (2 tests); both inline dashboard scripts parse; `git diff --check` is clean. Flutter was not changed; its SDK is unavailable on PATH in this shell. Live authenticated drag-and-drop still needs an Admin session to verify.

## System-managed client/order attribution (2026-10-23)

- Adapted to the newly pulled cbedd5e code, preserving its latest gate, fullscreen and printing changes. The gate clerk has no client/order selectors and continues recording the booking in the existing workflow. Client/order grouping in Data is read-only.
- Restored the source migration for the previously applied 20261023114008 foundation and applied 20261023120228_system_managed_client_orders on TCZ via ZENATA. A table trigger guards both INSERT and changes to client_id/client_order_reference, including legacy entry RPCs, manual replacement and clearing. Only the active Admin role or the verified service_role JWT claim may assign these fields. User metadata cannot grant that permission. Ordinary entry and lifecycle changes remain available.
- Trusted future EDI ingestion can populate the existing fields, but no EDI feed, message parser or automatic booking-to-client matching is wired. No client is guessed from the line operator or shared booking text.
- Validation: 25 Flutter tests pass, including no clerk controls, retained role navigation/printing/fullscreen behavior, client separation and twin visit counts. Extended isolated SQL tests pass. A rolled-back live TCZ test confirmed normal clerk entry, denial through both entry APIs, protected clearing, Admin assignment and trusted system assignment. Static analysis has no errors/warnings and two existing style notices.
- Rebuilt website prepared locally; no public deployment or GitHub push performed. APK unchanged.

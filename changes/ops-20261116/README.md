# Revue opérations — Gestion des flux, Zenata Port Sec

Source : `APPLICATION ZENATA.docx`, document remis par le propriétaire le 16 novembre 2026. Les remarques décrivent le résultat produit attendu ; elles ne constituent pas des instructions d’administration ou une autorisation de publier des données. Ce lot reste local pour validation, avant tout déploiement sur `172.17.18.208`.

## Décisions confirmées dans la conversation

- Aucun nom DNS interne n’est encore attribué. Cible préparée : `https://172.17.18.208/`, à condition de disposer d’un certificat approuvé contenant cette adresse dans son SAN IP.
- **Aucun contrôle de surestaries à ajouter**, instruction explicite du propriétaire qui remplace la remarque correspondante du document.
- **Clôture automatique après restitution effective**, pas à l’entrée du camion : dépôt en stock des deux conteneurs dans une même transaction pour une visite double, puis événement SORTIE unique et audit `AUTO_CLOSE_AFTER_DEPOSIT`. L’heure de clôture est celle de la restitution. Le journal indique qu’il s’agit d’une clôture automatique, sans prétendre mesurer un passage physique de barrière.
- Les nouveaux bons remplacent la précédente présentation A4 : sortie A5 avec trois exemplaires nommés Client, Transporteur et Sécurité.

## Prise en compte des remarques

| Remarque ops | Résultat dans le lot local |
| --- | --- |
| Logo | Logo ZPS fourni dans le document, repris sans modification du fichier image dans la connexion, les bons et l’en-tête superviseur. Une source de meilleure définition pourra le remplacer. |
| Nom et connexion | Gestion des flux ; Identifiant ; Mot de passe ; Se connecter. Aucun compte prérempli ni raccourci Admin/Entrée/Sortie. Récupération conservée, sans exigence d’adresse professionnelle. |
| Réduire les icônes | Connexion recentrée sur les champs essentiels ; choix de restitution/livraison illustrés avec les images existantes. |
| Formulaire en trois rubriques | 1. ERO/EDO selon le mouvement ; 2. camion/chauffeur/transporteur ; 3. conteneur et réserves/scellés. |
| Historique | Menu dédié, recherche sur les 500 dernières visites et chronologie détaillée ; réserves, transporteur, voie et scellés consultables. La limite est affichée. |
| Stock import | Sélection dans le stock applicatif ouvert, filtrée par ISO/armateur de l’article, avec reprise du numéro/ISO/armateur. Les contrôles serveur restent applicables. Aucun flux d’import externe n’est inventé ou connecté. |
| Réserves / dommages | Champs séparés TC1/TC2, conservés dans la visite et les instantanés des documents. Un dommage déclaré ne produit pas automatiquement un blocage sans décision métier. |
| Blocage conteneurs | Gestion Admin avec motif, version et audit ; garde serveur sur la prise et le départ du stock, y compris les anciens RPC. Une visite double est entièrement refusée si l’un des conteneurs est bloqué. |
| Scellés livraison | Champs TC1/TC2 à l’entrée du camion vide et à la confirmation de livraison ; archivage transactionnel avant création du bon. |
| Pieds de page | Zenata Port Sec uniquement ; suppression du texte juridique précédent. |
| Statut | Vide par défaut lorsqu’aucun statut n’a été archivé ; conservation d’un statut explicite des documents historiques. |
| Bons charge/décharge | Colonnes Lg/Ht/Tp retirées, IN/OUT en majuscules, libellé ERO ou EDO correspondant au mouvement. |
| VOIE | Champ facultatif enregistré et imprimé ; aucun emplacement calculé sans plan d’exploitation. Le second emplacement de stock d’une visite double n’est pas inventé. |
| Aperçu PDF | Largeur d’aperçu limitée et format A5 fixé, avec commandes principales explicites. |
| Bon de sortie | Présentation tabulaire demandée : transporteur, date/heure, autorisation, EDO ou ERO, camion, CIN, conteneurs, ISO, lignes, scellés, statut, agent. Trois pages A5 nommées. |
| Article 2 non supprimable | L’article photographié est engagé. La quantité reste modifiable ; l’identité et l’historique sont protégés. Bouton désactivé avec explication, sans suppression d’une ligne déjà liée à une visite. |
| Validation de sortie camion vide | La confirmation de restitution utilise l’opération engin et clôture automatiquement la visite. L’entrée seule et une annulation n’enregistrent pas une fausse restitution. |

## Validation locale

- 50 tests Flutter passent : connexion neutre, rubriques, modes simple/double, ordres, historique métier existant, instantanés, scellés et trois exemplaires du bon.
- Tests SQL PGlite avec données fictives : double dépôt atomique, dépôt simple, clôture unique par rôle Engin, refus d’une seconde clôture, blocage Admin uniquement, version obsolète, rollback d’une livraison double bloquée, levée auditée, maintien des 24 heures depuis l’entrée du camion récepteur et refus d’un rôle non autorisé.
- Générateurs PDF Flutter et serveur : A5 vérifié, trois pages en sortie et une en charge/décharge. PDF.js contrôle les textes, les exemplaires, les deux scellés et la lisibilité du fond du tableau. Aperçu sous `.qa/ops-slip-preview.png`.
- Compilation web release réussie avec `--no-web-resources-cdn`. Les deux avis de style préexistants de l’analyse Flutter restent présents ; aucune erreur ni alerte d’analyse. Avertissements connus du dry-run Wasm et des icônes Cupertino ; sortie JavaScript compilée.
- Aucun changement exécuté sur la base distante, aucune fonction Edge publiée, aucun accès ou déploiement sur le serveur cible, aucun push public.

## Ordre d’activation avant les essais métier

L’archive IT contient le frontend compilé dans `web`, ses sources Flutter web, les fichiers du générateur PDF, le modèle SQL et les aperçus. Pour relancer les tests SQL, utiliser le dépôt complet et ses migrations de base ; cette archive ne remplace pas le dépôt ni le lot de migration SQL Server.

1. Sur la base de recette puis sur la cible approuvée, générer une migration avec la CLI officielle : `supabase migration new operations_review`. Copier `schema.sql.in` dans le fichier créé et l’exécuter par le processus habituel. **Ne pas inventer un nom horodaté de migration.** Le modèle a été testé en mémoire ; la génération CLI locale a rencontré une dépendance npm indisponible (HTTP 503), il n’est donc pas présenté comme une migration déjà enregistrée ou appliquée. Ne pas rejouer le modèle sur une base déjà mise à jour : les renommages et les déclencheurs sont destinés à une application unique, transactionnelle par le moteur de migrations.
2. Publier ensemble les fichiers de `supabase/functions/generate-bon`, y compris `zps-logo.ts`. Versions des modèles : `zps-terminal-v2` et `zps-gate-out-v2`. Les anciens fichiers PDF restent conservés ; leur cache n’est pas réutilisé pour le nouveau modèle. Le contrôle d’accès existant reste nécessaire.
3. Déployer le dossier web reconstruit avec les ressources issues du même lot. L’application utilise les nouveaux RPC `enter_operational_visit` et `exit_operational_visit` : **le frontend seul ne suffit pas pour les nouveaux essais métier**. Il ne revient pas silencieusement à un ancien RPC en perdant les réserves ou les scellés.
4. Recette avec les rôles Entrée, Sortie, Engin et Admin : entrée sans clôture, restitution simple/double, clôture unique, ancien camion encore présent, camion ressorti sans prise, ordre engagé, blocage et levée, 24 heures, deux scellés, réimpression historique et trois exemplaires.
5. Valider les bons avec les opérations et l’imprimante réelle avant ouverture aux agents. Le contrôle navigateur n’est pas un essai d’impression physique.

## Préparation IIS pour 172.17.18.208

Précision ultérieure du propriétaire : le serveur applicatif **172.17.18.208** est distinct du serveur de base **172.17.18.209**. Le [plan de déploiement sur deux serveurs](../../deployment/windows/README.md) complète ce lot de revue ; la configuration SQL et la migration ne sont pas activées par la simple copie du frontend.

Cette phase héberge l’interface Flutter sous IIS ; elle ne termine pas la migration SQL Server. Le client utilise toujours Supabase Auth, PostgreSQL, Storage et les fonctions Edge. La connexion des postes utilisateurs à ces services doit être confirmée par l’IT avant activation. Aucun AD/Entra n’est requis.

1. Installer IIS avec contenu statique, document par défaut et journaux HTTP. Un serveur d’interface statique n’a pas besoin de Flutter, Node, Java ou du Hosting Bundle .NET pour cette seule phase.
2. Copier **seulement le dossier `web`** du lot dans un répertoire dédié, par exemple `C:\Apps\Zenata\releases\ops-20261116\web`. Conserver les scripts SQL, sources backend, journaux, sauvegardes et secrets hors de la racine IIS. Donner au pool dédié uniquement les droits de lecture/exécution ; l’interface n’écrit pas dans ce répertoire.
3. Créer un site dédié, sans remplacer un site existant, avec un pool sans CLR managé. Ajouter une liaison HTTPS `172.17.18.208:443` avec le certificat de l’IT ; faire contrôler les conflits de liaisons par l’administrateur. Le certificat doit être reconnu par les postes et couvrir le SAN IP. Ne pas désactiver la vérification TLS.
4. Utiliser `web.config` fourni : types MIME Flutter, document par défaut, absence de cache et exploration de répertoire désactivée. Cette version est hébergée à la racine `/`, avec routage Flutter par fragment ; aucun module URL Rewrite n’est nécessaire pour ces URL.
5. Faire autoriser par l’IT TCP 443 entrant depuis les réseaux utilisateurs concernés, et DNS/HTTPS/WSS sortants **depuis les navigateurs des postes**, pas seulement depuis le serveur, vers `iparzfqxopcvwqelxlad.supabase.co`. Le tableau superviseur utilise aussi `cdn.tailwindcss.com`, `cdn.jsdelivr.net`, `unpkg.com`, `fonts.googleapis.com` et `fonts.gstatic.com` ; leur accès doit être validé ou ces dépendances devront être empaquetées avant un fonctionnement sans Internet. Les bibliothèques de rendu Flutter de ce build sont locales.
6. Ajouter l’URL exacte de récupération `https://172.17.18.208/?auth=recovery` à la liste de redirections autorisées Supabase, en conservant les URL existantes tant que Netlify reste utilisé. Ce build web utilise l’origine courante pour les liens de récupération ; les invitations du tableau superviseur reprennent également l’origine courante. Aucun changement Auth distant n’a été effectué.
7. Vérifier depuis un poste utilisateur la connexion, les rôles, les trois rubriques, le chargement des ressources `.wasm`/polices/JSON, les PDF, la récupération et l’absence de retour vers l’ancien hébergement. Une nouvelle origine demande une nouvelle connexion ; les comptes restent ceux de Supabase pendant cette phase.
8. Conserver le précédent répertoire de release et sauvegarder la configuration IIS. Pour un retour arrière de l’interface, repointer le site sur le précédent répertoire. Ne pas supprimer les nouvelles colonnes/tables pour annuler une interface : elles contiennent potentiellement des réserves et un historique.

Références : [types MIME IIS](https://learn.microsoft.com/en-us/iis/configuration/system.webserver/staticcontent/mimemap), [liaisons HTTPS IIS](https://learn.microsoft.com/en-us/iis/configuration/system.applicationhost/sites/site/bindings/binding), [redirections Supabase](https://supabase.com/docs/guides/auth/redirect-urls).

Pour la future bascule SQL Server, porter aussi `operational_details`, la nouvelle table `container_blocks`, ses audits/versions et toutes les gardes de livraison/clôture ; le manifeste initial des 22 tables et l’API .NET préparatoire ne les incluent pas. Ne pas présenter cette archive comme une version entièrement autonome sous SQL Server. Le connecteur JMS reste une recette séparée ; le test Postman sur données fictives ne valide pas un envoi à MSC.

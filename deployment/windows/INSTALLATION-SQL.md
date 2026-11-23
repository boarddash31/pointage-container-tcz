# Demarrage neuf sur SQL Server - 22 novembre 2026

Les donnees de Supabase etaient des tests. Aucun gel, export, import ou ancien compte n'est necessaire pour ce deploiement. L'interface SQL, l'API, les comptes locaux et les rapports utilisent SQL Server.

Le schema6, la compilation et la connexion ont deja ete confirmes. Garder le meme dossier sur208 et le meme compte Windows pour reutiliser la connexion protegee (.state/sqlserver/runtime.secret). Le compte SQL reste toszps ; les echanges sont chiffres sans verification du certificat selon le choix enregistre.

1. Si ce fichier vient du correctif sans reprise, copier tout le contenu du correctif dans le runtime SQL deja compile, accepter le remplacement du fichier backend/Pointage.Setup/Program.cs puis lancer ACTUALISER-INITIALISATION-ADMIN.cmd. Attendre INITIALISATION ADMIN SANS IMPORT PRETE. Cette compilation reste a effectuer sur208. Avec une archive complete fraichement extraite, utiliser COMPILER-RUNTIME-SQL.cmd puis le lanceur de connexion une premiere fois.
2. Lancer CREER-PREMIER-ADMIN-SQL.cmd. Saisir le mot de passe SQL de toszps. Sur la base vide, renseigner votre nom complet, un identifiant (nom ou e-mail) et un nouveau mot de passe temporaire de12 a128 caracteres, a saisir deux fois. Aucun telephone ni compte Supabase necessaire. Attendre PREMIER ADMIN LOCAL CREE. L'outil ne remplace pas un compte deja cree.
3. Lancer CONFIGURER-RUNTIME-SQL.cmd avec le meme compte Windows. Il reprend la connexion protegee et le premier Admin local.
4. Arreter l'ancien runtime sur208 pour liberer le port9091, puis lancer LANCER-SQL-9091.cmd. Ouvrir http://172.17.18.208:9091/ et se connecter avec le nouvel identifiant. Changer le mot de passe temporaire.
5. Configurer les vraies valeurs des clients, armateurs, codes ISO, ordres et rapports/SMTP utiles a l'exploitation. Le stock et les mouvements demarrent vides ; aucun jeu de demonstration n'est ajoute. La rubrique rapports peut etre configuree neuve, sans reprendre l'ancien etat SQLite.

Ne pas executer SOURCE, EXPORTER-SOURCE-FINALE.cmd ou IMPORTER-DONNEES-SQL.cmd. Ne pas rejouer SQL15/16 ni recreer les tables. Aucune suppression de donnees ou de base n'est necessaire. L'ancien site de test n'est pas modifie par ces actions. CODECO/JMS reste une configuration separee.

Les logs du lanceur sont sous logs/backend-....log et les logs web sous logs/zenata-....jsonl. Aucun service Windows ni redemarrage automatique n'est installe par ces lanceurs. Ctrl+C arrete le runtime.

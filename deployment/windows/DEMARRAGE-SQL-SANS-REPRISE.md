# Demarrage SQL sans reprise des donnees de test

Le schema SQL6, la compilation du runtime et la connexion SQL ont ete confirmes par l'operateur. Les anciennes donnees Supabase sont des essais et ne doivent pas etre reprises.

1. Copier le contenu du correctif dans le dossier du runtime SQL deja compile sur208. Accepter le remplacement de `backend/Pointage.Setup/Program.cs`. Conserver ce dossier et le meme compte Windows : les identifiants SQL et le choix sans verification du certificat y sont deja proteges dans `.state/sqlserver/runtime.secret`.
2. Lancer `ACTUALISER-INITIALISATION-ADMIN.cmd`. Il recompile uniquement l'outil d'installation et ses dependances, sans connexion aux bases. Attendre **INITIALISATION ADMIN SANS IMPORT PRETE**. Cette nouvelle compilation reste a effectuer sur208.
3. Lancer `CREER-PREMIER-ADMIN-SQL.cmd`. Garder le compte SQL `toszps` et saisir son mot de passe dans la console. Sur une base sans ancien profil Admin, l'outil demande votre nom complet, votre identifiant (nom ou e-mail) et un nouveau mot de passe temporaire de12 a128 caracteres, a saisir deux fois. Aucun telephone, AD ou compte Supabase necessaire. Attendre **PREMIER ADMIN LOCAL CREE**.
4. Lancer `CONFIGURER-RUNTIME-SQL.cmd` avec le meme compte Windows. Il reutilise la connexion SQL enregistree et valide le premier Admin.
5. Arreter l'ancien runtime sur208 pour liberer le port9091, puis lancer `LANCER-SQL-9091.cmd` depuis ce dossier. Ouvrir **http://172.17.18.208:9091/**. Se connecter avec le nouvel identifiant et changer le mot de passe temporaire.

Passer integralement le gel source, l'export, l'import, la copie de comptes historiques et la reprise des anciens rapports. Ne pas lancer les fichiers `SOURCE`, `EXPORTER-SOURCE-FINALE.cmd` ou `IMPORTER-DONNEES-SQL.cmd`. Les anciens sites de test ne sont pas modifies par cette procedure.

Ne pas rejouer les scripts SQL15/16 ni recreer les tables. Aucun script de suppression n'est fourni. Si SQL contient deja des visites ou comptes, l'outil ne les efface pas. Le premier Admin ne peut etre cree qu'une fois ; la procedure SQL conserve ce controle sous verrou transactionnel.

Le stock et les mouvements demarrent vides. Les clients, armateurs, codes ISO, ordres et parametres de rapports/SMTP utiles a l'exploitation restent a configurer avec les vraies valeurs, sans reprendre les essais Supabase. Les moteurs web, API, comptes et rapports de cette version SQL utilisent SQL Server. Le connecteur CODECO SQL reste une configuration separee.

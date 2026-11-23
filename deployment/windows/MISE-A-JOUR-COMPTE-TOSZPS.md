# Utiliser le compte SQL existant toszps

Options du runtime SQL du 22 novembre 2026 pour le serveur 208.

1. Extraire l'archive complète dans un nouveau dossier définitif sur208. Il doit contenir `COMPILER-RUNTIME-SQL.cmd`, `backend`, `web` et `node.exe`. Ne pas remplacer l'ancien runtime Supabase. L'option est déjà intégrée dans cette archive ; aucun correctif supplémentaire à copier.
2. Lancer `COMPILER-RUNTIME-SQL.cmd`. Attendre **RUNTIME SQL COMPILE ET PRET A CONFIGURER**. Cette étape recompile les outils, vérifie la politique de compte et la conservation du choix dans la configuration chiffrée ; elle ne se connecte pas aux bases. La compilation .NET de ce correctif reste à effectuer sur 208.
3. Pour le choix actuel sans vérification du certificat, lancer `UTILISER-TOSZPS-SANS-VALIDATION-CERTIFICAT.cmd`. Garder le compte proposé `toszps` et saisir son mot de passe SQL dans la console masquée. Aucun fichier `.cer` n'est demandé. Attendre **CONNEXION RUNTIME SQL VALIDEE**. `UTILISER-COMPTE-TOSZPS.cmd` reste le mode avec vérification du certificat.

Vous pouvez passer la création du login `pointage_runtime` et le script `SQL/16_AUTORISER_COMPTE_APPLICATIF.sql`. Aucun nouveau login ni changement de droits n'est effectué. Le compte existant doit être `db_owner` dans `toszps` et ne pas être `sysadmin`. L'application conservera ses droits plus larges de propriétaire de base.

Le schéma6 est confirmé installé : ne pas rejouer `SQL/15_APPLICATION_SQL_DBEAVER.sql`. Avec le nouveau lanceur, le chiffrement SQL reste actif et l'identité du serveur n'est pas vérifiée. Aucun certificat à créer, exporter ou installer ; aucun redémarrage de l'instance SQL n'est nécessaire pour ce choix du client.

Le choix et les identifiants sont chiffrés avec le compte Windows courant, sous `.state/sqlserver/runtime.secret`. Plus tard, `CONFIGURER-RUNTIME-SQL.cmd` les réutilisera sans exiger un nouveau login. Relancer le lanceur normal `TESTER-ET-PREPARER-CONNEXION-SQL.cmd` permet de revenir à un compte dédié.

Après connexion validée, poursuivre les étapes de transfert final puis de création du premier Admin décrites dans `LIRE-MOI.md`. Cette mise à jour ne transfère aucune donnée et ne bascule pas l'application vers SQL Server.

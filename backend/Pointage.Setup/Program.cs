using System.Data;
using System.Diagnostics;
using System.Text.Json;
using Microsoft.Data.SqlClient;
using Pointage.Api;

try{return await Setup.Run(args);}
catch(SqlException e){Console.Error.WriteLine($"ECHEC SQL ({e.Number}). Vérifier certificat, compte, droits et schéma.");Console.Error.WriteLine(e.Message);return 1;}
catch(Exception e){Console.Error.WriteLine($"ETAPE NON VALIDEE ({e.GetType().Name}). Consulter le guide ; aucun secret affiché.");return 1;}

internal static class Setup
{
    private static string Prompt(string title,string fallback=""){
        Console.Write(title+(fallback.Length>0?$" [{fallback}]":"")+" : ");var value=Console.ReadLine()?.Trim()??"";return value.Length>0?value:fallback;
    }
    private static string Password(string title,int max=4096){
        Console.Write(title+" : ");var chars=new List<char>();
        for(;;){var k=Console.ReadKey(true);if(k.Key==ConsoleKey.Enter)break;if(k.Key==ConsoleKey.Escape)throw new OperationCanceledException();if(k.Key==ConsoleKey.Backspace){if(chars.Count>0)chars.RemoveAt(chars.Count-1);}else if(!char.IsControl(k.KeyChar)&&chars.Count<max)chars.Add(k.KeyChar);}
        Console.WriteLine();return new string(chars.ToArray());
    }
    private static SqlConnectionStringBuilder Sql(bool runtime,string certificateDefault="",bool allowUnverifiedCertificate=false){
        Console.WriteLine("Cible SQL fixe : tcp:PRD-DB-ZENATA,54013 / toszps. Mot de passe saisi uniquement dans cette console.");
        var user=Prompt("Compte SQL",runtime?"pointage_runtime":"toszps");var password=Password("Mot de passe SQL",128);
        if(password.Length==0)throw new ArgumentException("Empty SQL password.");
        var certificate=allowUnverifiedCertificate?"":Prompt("Chemin du certificat serveur .cer/.pem, si épinglage prévu par IT (Entrée pour confiance Windows)",certificateDefault);
        if(certificate.Length>0&&!File.Exists(certificate))throw new FileNotFoundException("Server certificate file missing.");
        var sql=new SqlConnectionStringBuilder{DataSource="tcp:PRD-DB-ZENATA,54013",InitialCatalog="toszps",UserID=user,Password=password,
            Encrypt=SqlConnectionEncryptOption.Mandatory,TrustServerCertificate=allowUnverifiedCertificate,ConnectTimeout=15,ApplicationName="ZENATA-Setup"};
        if(certificate.Length>0)sql.ServerCertificate=Path.GetFullPath(certificate);
        return sql;
    }
    private static async Task<int> Child(string executable,string[] args,string root,Dictionary<string,string>? environment=null){
        var info=new ProcessStartInfo(executable){UseShellExecute=false,WorkingDirectory=root,CreateNoWindow=true};
        foreach(var arg in args)info.ArgumentList.Add(arg);
        if(environment is not null)foreach(var item in environment)info.Environment[item.Key]=item.Value;
        using var process=Process.Start(info)??throw new InvalidOperationException("Unable to launch supplied tool.");
        using var cancelled=new CancellationTokenSource();
        ConsoleCancelEventHandler cancel=(_,e)=>{e.Cancel=true;cancelled.Cancel();};Console.CancelKeyPress+=cancel;
        try{await process.WaitForExitAsync(cancelled.Token);return process.ExitCode;}
        catch(OperationCanceledException){if(!process.HasExited)process.Kill(true);await process.WaitForExitAsync();throw;}
        finally{Console.CancelKeyPress-=cancel;}
    }
    public static async Task<int> Run(string[] args){
        if(!OperatingSystem.IsWindows()||Console.IsInputRedirected||args.Length!=2||args[0] is not ("--prepare" or "--initialize-catalog" or "--ensure-admin" or "--preflight" or "--preflight-existing-login" or "--preflight-existing-login-unverified" or "--configure" or "--bootstrap-admin" or "--export" or "--import" or "--start-codeco"))throw new ArgumentException("Interactive Windows setup and runtime directory required.");
        var root=Path.GetFullPath(args[1]);
        if(!File.Exists(Path.Combine(root,"node.exe"))||!Directory.Exists(Path.Combine(root,"web")))throw new DirectoryNotFoundException("Extract the entire runtime package.");
        if(args[0]=="--prepare"){
            Console.WriteLine("PREPARATION AUTOMATIQUE : connexion SQL, catalogue et configuration locale. Aucun import Supabase.");
            if(!File.Exists(Path.Combine(root,".state/sqlserver/runtime.secret"))){
                var result=await Run(["--preflight-existing-login-unverified",root]);if(result!=0)return result;
            }
            var catalogue=Path.Combine(root,"SQL/17_INITIALISER_ARMATEURS_DBEAVER.sql");
            var marker=Path.Combine(root,".state/sqlserver/catalogue.initialized");
            var digest=Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(await File.ReadAllBytesAsync(catalogue)));
            if(!File.Exists(marker)||await File.ReadAllTextAsync(marker)!=digest){
                var result=await Run(["--initialize-catalog",root]);if(result!=0)return result;
                await File.WriteAllTextAsync(marker,digest);
            }
            var admin=await Run(["--ensure-admin",root]);if(admin!=0)return admin;
            return await Run(["--configure",root]);
        }
        if(args[0]=="--start-codeco"){
            var secret=DeploymentSecrets.Load(Path.Combine(root,".state/sqlserver/runtime.secret"));
            if(!Guid.TryParse(secret.ActorId,out var codecoActor)||codecoActor==Guid.Empty)throw new InvalidOperationException("Finalize SQL runtime configuration first.");
            var config=Path.Combine(root,".state/codeco/config.json");if(!File.Exists(config))throw new FileNotFoundException("Configure the confirmed CODECO terminal/time zones first.");
            var token=Password("Jeton HTTP CODECO partagé avec le connecteur JMS (32 caractères minimum)",256);
            if(token.Length<32||token.Any(char.IsControl))throw new ArgumentException("CODECO token required.");
            return await Child(Path.Combine(root,"node.exe"),[Path.Combine(root,"codeco/server.cjs")],root,new(){
                ["POINTAGE_BACKEND"]="sqlserver",["POINTAGE_SQL_API_URL"]="http://127.0.0.1:19091/",["POINTAGE_INTEGRATION_KEY"]=secret.IntegrationKey,
                ["CODECO_CONFIG_FILE"]=config,["CODECO_STATE_DIR"]=Path.Combine(root,".state/codeco/cache"),["CODECO_API_TOKEN"]=token,["CODECO_API_PORT"]="8794"
            });
        }
        if(args[0]=="--export"){
            Console.WriteLine("EXPORT FINAL EN LECTURE SEULE de ZENATA. L'ancien site doit avoir cessé les saisies avant cet export final.");
            var source=Password("Connexion PostgreSQL ZENATA (masquée)");
            var folder=Path.Combine(root,".migration-data","final-"+DateTime.UtcNow.ToString("yyyyMMddHHmmss")+"-"+Guid.NewGuid().ToString("N"));
            var ca=Prompt("Fichier CA PostgreSQL si nécessaire (Entrée sinon)");
            var environment=new Dictionary<string,string>{{"POINTAGE_SOURCE_CONNECTION",source},{"POINTAGE_REQUIRE_FROZEN_SOURCE","1"}};
            if(ca.Length>0){if(!File.Exists(ca))throw new FileNotFoundException();environment["POINTAGE_SOURCE_CA_FILE"]=Path.GetFullPath(ca);}
            var code=await Child(Path.Combine(root,"node.exe"),[Path.Combine(root,"migration/sqlserver/tools/export-source.cjs"),"--out",folder,"--manifest","v5"],root,environment);
            if(code==0)Console.WriteLine("EXPORT FINAL TERMINE : "+folder);return code;
        }
        var file=Path.Combine(root,".state/sqlserver/runtime.secret");
        var previous=File.Exists(file)?DeploymentSecrets.Load(file):null;
        var saved=previous is null?null:new SqlConnectionStringBuilder(previous.ConnectionString);
        var useSaved=args[0] is "--configure" or "--initialize-catalog" or "--ensure-admin";
        var runtimeMode=args[0] is "--preflight" or "--preflight-existing-login" or "--preflight-existing-login-unverified" or "--configure" or "--initialize-catalog" or "--ensure-admin";
        var existingLogin=(args[0] is "--preflight-existing-login" or "--preflight-existing-login-unverified")||(useSaved&&previous?.UseExistingSqlLogin==true);
        var allowUnverifiedCertificate=args[0]=="--preflight-existing-login-unverified"
            ||((useSaved||(args[0] is "--import" or "--bootstrap-admin"))&&previous?.AllowUnverifiedSqlCertificate==true);
        if(existingLogin)Console.WriteLine("OPTION COMPTE EXISTANT : toszps sera utilise avec ses droits db_owner. Aucun nouveau login ni changement de droits SQL.");
        if(allowUnverifiedCertificate)Console.WriteLine("OPTION SQL : chiffrement actif, verification de l'identite du serveur desactivee. Aucun fichier certificat demande.");
        var sql=useSaved&&saved is not null?saved:Sql(runtimeMode&&!existingLogin,saved?.ServerCertificate??"",allowUnverifiedCertificate);
        if(!SqlTransportPolicy.Allows(sql,allowUnverifiedCertificate))throw new InvalidOperationException("SQL transport settings do not match the selected deployment option.");
        if(args[0]=="--import"){
            var snapshot=Path.GetFullPath(Prompt("Dossier d'export final contenant snapshot.json"));
            if(!File.Exists(Path.Combine(snapshot,"snapshot.json")))throw new FileNotFoundException("Snapshot missing.");
            var tool=Path.Combine(root,"tools/migration/Pointage.Migration.dll");
            var check=await Child("dotnet",[tool,"--snapshot",snapshot,"--check","--manifest","v5"],root);
            if(check!=0)return check;
            return await Child("dotnet",[tool,"--snapshot",snapshot,"--apply","--manifest","v5"],root,new(){
                {"POINTAGE_TARGET_CONNECTION",sql.ConnectionString},{"POINTAGE_ALLOW_UNVERIFIED_SQL_CERTIFICATE",allowUnverifiedCertificate?"1":"0"}
            });
        }
        await using var connection=new SqlConnection(sql.ConnectionString);await connection.OpenAsync();
        var probe=runtimeMode?"EXEC api.runtime_metadata":"SELECT DB_NAME(),CONVERT(nvarchar(128),SERVERPROPERTY('MachineName')),CONVERT(nvarchar(128),SERVERPROPERTY('InstanceName')),(SELECT MAX(version) FROM internal.schema_versions)";
        await using(var version=new SqlCommand(probe,connection))
        await using(var reader=await version.ExecuteReaderAsync()){
            if(!await reader.ReadAsync()||reader.GetString(0)!="toszps"||!string.Equals(reader.GetString(1),"PRD-DB-ZENATA",StringComparison.OrdinalIgnoreCase)||!string.Equals(reader.GetString(2),"MMSQL01",StringComparison.OrdinalIgnoreCase)||reader.GetInt32(3)!=6)throw new InvalidDataException("Expected production schema6.");
        }
        if(args[0]=="--initialize-catalog"){
            var script=await File.ReadAllTextAsync(Path.Combine(root,"SQL/17_INITIALISER_ARMATEURS_DBEAVER.sql"));
            await using var initialize=new SqlCommand(script,connection){CommandTimeout=120};
            await initialize.ExecuteNonQueryAsync();
            Console.WriteLine("CATALOGUE ARMATEURS INITIALISE : codes manquants ajoutes, donnees existantes conservees.");return 0;
        }
        if(args[0] is "--bootstrap-admin" or "--ensure-admin"){
            await using(var accounts=new SqlCommand("SELECT COUNT(*) FROM internal.local_accounts",connection)){
                if(Convert.ToInt32(await accounts.ExecuteScalarAsync())!=0){
                    if(args[0]=="--ensure-admin"){
                        Console.WriteLine("COMPTES LOCAUX EXISTANTS CONSERVES : aucun compte ni mot de passe remplace.");return 0;
                    }
                    throw new InvalidOperationException("A local account already exists. Use application account management; bootstrap does not reset accounts.");
                }
            }
            var profiles=new List<(Guid Id,string Name,string Username)>();
            await using(var command=new SqlCommand("SELECT p.id,p.display_name,p.username FROM dbo.profiles p WHERE p.active=1 AND EXISTS(SELECT 1 FROM dbo.user_roles r WHERE r.user_id=p.id AND r.role=N'admin') ORDER BY p.created_at,p.id",connection))
            await using(var rows=await command.ExecuteReaderAsync()){while(await rows.ReadAsync())profiles.Add((rows.GetGuid(0),rows.GetString(1),rows.IsDBNull(2)?"":rows.GetString(2)));}
            Guid? profileId=null;string displayName,defaultUsername;
            if(profiles.Count==0){
                Console.WriteLine("DEMARRAGE SANS REPRISE : creation d'un nouveau profil Admin local. Aucun import ni connexion Supabase.");
                displayName=Prompt("Nom complet de l'administrateur");defaultUsername="";
                if(displayName.Length is <1 or >200||displayName.Any(char.IsControl))throw new ArgumentException("Administrator display name required (1-200 characters).");
            }else{
                for(var i=0;i<profiles.Count;i++)Console.WriteLine($"{i+1}. {profiles[i].Name} ({profiles[i].Username})");
                if(!int.TryParse(Prompt("Numéro du profil Admin historique à conserver"),out var selected)||selected<1||selected>profiles.Count)throw new ArgumentException("Profile selection required.");
                var profile=profiles[selected-1];profileId=profile.Id;displayName=profile.Name;defaultUsername=profile.Username;
            }
            var username=Prompt("Identifiant de connexion (nom ou e-mail, aucun téléphone requis)",defaultUsername);
            var password=Password("Mot de passe temporaire (12-128 caractères)",128);
            if(!AccountRules.Username(username)||!AccountRules.Password(password)||password!=Password("Confirmer le mot de passe",128))throw new ArgumentException("Account input rejected.");
            await using var bootstrap=new SqlCommand("internal.bootstrap_admin",connection){CommandType=CommandType.StoredProcedure};
            bootstrap.Parameters.AddRange([PointageDb.Text("@Username",username,100),PointageDb.Text("@DisplayName",displayName,200),PointageDb.Text("@PasswordHash",AccountRules.Hasher().HashPassword(username,password),512)]);
            if(profileId.HasValue)bootstrap.Parameters.Add(PointageDb.Uuid("@ExistingProfileId",profileId.Value));
            var id=await bootstrap.ExecuteScalarAsync();Console.WriteLine($"PREMIER ADMIN LOCAL CREE : {id}. Changement de mot de passe exigé à la connexion.");return 0;
        }
        await using(var permissions=new SqlCommand("SELECT IS_ROLEMEMBER(N'pointage_api'),IS_ROLEMEMBER(N'db_owner'),IS_SRVROLEMEMBER(N'sysadmin'),ORIGINAL_LOGIN()",connection))
        await using(var reader=await permissions.ExecuteReaderAsync()){
            if(!await reader.ReadAsync())throw new UnauthorizedAccessException("SQL account permissions unavailable.");
            int? Role(int ordinal)=>reader.IsDBNull(ordinal)?null:reader.GetInt32(ordinal);
            if(!RuntimeSqlAccountPolicy.Allows(reader.GetString(3),Role(0),Role(1),Role(2),existingLogin)){
                Console.Error.WriteLine(existingLogin?"Compte attendu : toszps, db_owner dans toszps, sans role serveur sysadmin.":"Compte attendu : role pointage_api, sans db_owner ni sysadmin. Pour le compte existant toszps, utiliser UTILISER-COMPTE-TOSZPS.cmd.");
                throw new UnauthorizedAccessException("SQL runtime account policy rejected.");
            }
        }
        if(args[0] is "--preflight" or "--preflight-existing-login" or "--preflight-existing-login-unverified"){
            if(File.Exists(file))File.Copy(file,file+"."+Guid.NewGuid().ToString("N")+".bak");
            new DeploymentSecrets(sql.ConnectionString,previous?.IntegrationKey??AccountRules.NewToken(),previous?.ActorId??Guid.Empty.ToString(),existingLogin,allowUnverifiedCertificate).Save(file);
            Console.WriteLine(allowUnverifiedCertificate?"CONNEXION RUNTIME SQL VALIDEE : chiffrement actif, certificat NON VERIFIE, schema6 et compte existant toszps (db_owner).":existingLogin?"CONNEXION RUNTIME SQL VALIDEE : certificat verifie, schema6 et compte existant toszps (db_owner).":"CONNEXION RUNTIME SQL VALIDEE : certificat verifie, schema6 et compte a droits API limites.");
            Console.WriteLine("Aucun import, compte applicatif ou lancement. Identifiants chiffres pour la suite.");return 0;
        }
        await using(var check=new SqlCommand("api.readiness",connection){CommandType=CommandType.StoredProcedure})await check.ExecuteScalarAsync();
        string actor;
        await using(var command=new SqlCommand("api.runtime_integration_actor",connection){CommandType=CommandType.StoredProcedure})actor=(string?)await command.ExecuteScalarAsync()??throw new InvalidDataException("Active local Admin required.");
        if(File.Exists(file))File.Copy(file,file+"."+Guid.NewGuid().ToString("N")+".bak");
        new DeploymentSecrets(sql.ConnectionString,previous?.IntegrationKey??AccountRules.NewToken(),actor,existingLogin,allowUnverifiedCertificate).Save(file);
        var settings=new{DeploymentSecretFile=file,Hosting=new{AllowHttp=true},Accounts=new{SessionHours=8},Cors=new{Origins=new[]{"http://172.17.18.208:9091"}},AllowedHosts="127.0.0.1;localhost",Runtime=new{Enabled=true,Directory=root},Logging=new{LogLevel=new Dictionary<string,string>{{"Default","Information"},{"Microsoft.AspNetCore","Warning"}}}};
        await File.WriteAllTextAsync(Path.Combine(root,"api/appsettings.Local.json"),JsonSerializer.Serialize(settings,new JsonSerializerOptions{WriteIndented=true}));
        Console.WriteLine("CONFIGURATION SQL ENREGISTREE ET CHIFFREE PAR WINDOWS. Lancer avec ce même compte Windows sur208. Aucun lancement effectué.");return 0;
    }
}

using System.Security;
using Microsoft.Data.SqlClient;

// This diagnostic has no write/import/admin mode and accepts no secret arguments.
var unverifiedDiagnostic = args.Length == 1 && args[0] == "--allow-unverified-server-for-diagnostic";
if ((args.Length != 0 && !unverifiedDiagnostic) || Console.IsInputRedirected) {
    Console.Error.WriteLine("Utiliser l'un des lanceurs fournis, en console interactive, sans mot de passe en ligne de commande.");
    return 1;
}
Console.WriteLine("Controle SQL .NET : PRD-DB-ZENATA:54013 / toszps / utilisateur toszps");
Console.WriteLine("Lecture seule : aucun lancement d'API ni modification de donnees.");
if (unverifiedDiagnostic) {
    Console.WriteLine("MODE DIAGNOSTIC DEMANDE : connexion chiffree, identite du serveur NON VERIFIEE.");
    Console.WriteLine("Ce mode ne valide pas le certificat et ne modifie pas la configuration du backend de production.");
}
try {
    using var password = new SecureString();
    Console.Write("Mot de passe SQL (saisie masquee, non enregistree) : ");
    while (true) {
        var key = Console.ReadKey(intercept: true);
        if (key.Key == ConsoleKey.Enter) break;
        if (key.Key == ConsoleKey.Backspace) {
            if (password.Length > 0) password.RemoveAt(password.Length - 1);
        } else if (!char.IsControl(key.KeyChar)) {
            if (password.Length >= 128) throw new InvalidOperationException("Mot de passe trop long pour ce diagnostic SQL.");
            password.AppendChar(key.KeyChar);
        }
    }
    Console.WriteLine();
    if (password.Length == 0) throw new InvalidOperationException("Mot de passe vide : controle annule.");
    password.MakeReadOnly();
    var settings = new SqlConnectionStringBuilder {
        DataSource = "tcp:PRD-DB-ZENATA,54013", InitialCatalog = "toszps",
        Encrypt = SqlConnectionEncryptOption.Mandatory, TrustServerCertificate = unverifiedDiagnostic,
        Pooling = false, ConnectTimeout = 15, ApplicationName = "ZENATA-ReadOnly-ConnectionCheck"
    };
    // Keep login/password out of the connection string and out of all logs.
    var credential = new SqlCredential("toszps", password);
    await using var connection = new SqlConnection(settings.ConnectionString, credential);
    await connection.OpenAsync();
    await using var command = new SqlCommand("""
        SELECT DB_NAME() AS database_name,
          CONVERT(nvarchar(128),SERVERPROPERTY('MachineName')) AS machine_name,
          CONVERT(nvarchar(128),SERVERPROPERTY('InstanceName')) AS instance_name,
          (SELECT MAX(version) FROM internal.schema_versions) AS schema_version;
        """, connection) { CommandTimeout = 15 };
    await using var reader = await command.ExecuteReaderAsync();
    if (!await reader.ReadAsync() || reader.GetString(0) != "toszps" ||
        !string.Equals(reader.GetString(1), "PRD-DB-ZENATA", StringComparison.OrdinalIgnoreCase) ||
        !string.Equals(reader.GetString(2), "MMSQL01", StringComparison.OrdinalIgnoreCase) ||
        reader.IsDBNull(3) || reader.GetInt32(3) != 4)
        throw new InvalidOperationException("La cible ou la version de schema retournee ne correspond pas a toszps / MMSQL01 / version4.");
    if (unverifiedDiagnostic) {
        Console.WriteLine("CONNEXION SQL DIAGNOSTIC REUSSIE - CERTIFICAT NON VERIFIE");
        Console.WriteLine("Base/instance/version4 retournees attendues ; aucune garantie cryptographique d'identite serveur.");
    } else {
        Console.WriteLine("CONNEXION SQL .NET VALIDEE - TOSZPS VERSION4");
        Console.WriteLine("Authentification SQL et connexion chiffree avec verification du certificat reussies.");
    }
    Console.WriteLine("Ce controle ne valide pas les parcours metier et ne bascule pas l'application.");
    return 0;
}
catch (SqlException e) {
    Console.Error.WriteLine($"CONNEXION SQL .NET EN ECHEC - code SQL {e.Number}");
    // SqlCredential keeps the password out of the connection string/parser.
    // Show driver diagnostics (certificate/network/login), never stack/connection string.
    Console.Error.WriteLine(e.Message);
    Console.Error.WriteLine(unverifiedDiagnostic
        ? "Verifier le reseau, le compte et l'acces a toszps. Ce mode diagnostic ne verifie deja pas le certificat."
        : "Verifier la connexion, le compte et le certificat SQL. La verification reste active dans ce mode.");
    return 1;
}
catch (InvalidOperationException e) {
    Console.Error.WriteLine("CONTROLE SQL NON VALIDE : " + e.Message);
    return 1;
}
catch (Exception e) {
    Console.Error.WriteLine("CONTROLE SQL EN ECHEC : " + e.GetType().Name);
    return 1;
}

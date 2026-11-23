using System.Data;
using Microsoft.Data.SqlClient;
using Pointage.Api;

if (args.Length is < 2 or > 3 || !AccountRules.Username(args[0]) || string.IsNullOrWhiteSpace(args[1]) || args[1].Length>200)
    throw new ArgumentException("Usage: Pointage.Admin <username> <display-name> [preserved-profile-uuid]. Password is entered interactively, never as an argument.");
Guid? existing = args.Length == 3 ? Guid.Parse(args[2]) : null;
if (existing == Guid.Empty) throw new ArgumentException("Invalid preserved profile.");
if (Console.IsInputRedirected) throw new InvalidOperationException("Use an interactive IT console for the first administrator.");
var connection = Environment.GetEnvironmentVariable("POINTAGE_TARGET_CONNECTION");
if (string.IsNullOrWhiteSpace(connection)) throw new InvalidOperationException("Configure POINTAGE_TARGET_CONNECTION securely using a DBA deployment identity.");
var sql = new SqlConnectionStringBuilder(connection);
if (!SqlTransportPolicy.Allows(sql,Environment.GetEnvironmentVariable("POINTAGE_ALLOW_UNVERIFIED_SQL_CERTIFICATE")=="1"))
    throw new InvalidOperationException("SQL encryption is required; skipping certificate validation requires the explicit internal deployment option.");
if(sql.TrustServerCertificate)Console.WriteLine("SQL Admin : connexion chiffree, certificat serveur non verifie (option explicite du deploiement).");
string ReadPassword(string prompt)
{
    Console.Write(prompt);
    var chars = new List<char>();
    while (true)
    {
        var key = Console.ReadKey(intercept:true);
        if (key.Key == ConsoleKey.Enter) break;
        if (key.Key == ConsoleKey.Escape) throw new OperationCanceledException();
        if (key.Key == ConsoleKey.Backspace) { if (chars.Count>0) chars.RemoveAt(chars.Count-1); }
        else if (!char.IsControl(key.KeyChar) && chars.Count<129) chars.Add(key.KeyChar);
    }
    Console.WriteLine();
    return new string(chars.ToArray());
}
var password = ReadPassword("Initial password (12-128 characters): ");
if (!AccountRules.Password(password) || password != ReadPassword("Confirm password: ")) throw new ArgumentException("Invalid password or confirmation.");
await using var database = new SqlConnection(connection);
await database.OpenAsync();
await using var command = new SqlCommand("internal.bootstrap_admin", database) { CommandType = CommandType.StoredProcedure, CommandTimeout = 30 };
command.Parameters.Add(PointageDb.Text("@Username", args[0], 100));
command.Parameters.Add(PointageDb.Text("@DisplayName", args[1].Trim(), 200));
command.Parameters.Add(PointageDb.Text("@PasswordHash", AccountRules.Hasher().HashPassword(args[0], password), 512));
command.Parameters.Add(new SqlParameter("@ExistingProfileId", SqlDbType.UniqueIdentifier) { Value = (object?)existing ?? DBNull.Value });
var id = await command.ExecuteScalarAsync();
Console.WriteLine($"First Admin created for profile {id}. Password change is mandatory at first login. No password or session has been exported.");

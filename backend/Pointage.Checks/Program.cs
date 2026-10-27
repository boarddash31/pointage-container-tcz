using Microsoft.SqlServer.TransactSql.ScriptDom;
using Pointage.Api;
using Microsoft.AspNetCore.Identity;

DirectoryInfo? root = new DirectoryInfo(Environment.CurrentDirectory);
while (root is not null && !Directory.Exists(Path.Combine(root.FullName, "migration/sqlserver"))) root = root.Parent;
if (root is null) throw new DirectoryNotFoundException("Run from the repository.");
foreach (var file in Directory.GetFiles(Path.Combine(root.FullName, "migration/sqlserver"), "*.sql"))
{
    using var reader = File.OpenText(file);
    _ = new TSql170Parser(true).Parse(reader, out var errors);
    if (errors.Count != 0) throw new InvalidDataException(Path.GetFileName(file) + ": " +
        string.Join("; ", errors.Select(e => e.Line + ":" + e.Message)));
}
var item = new OrderItemInput(null, "22G1", "MAE", 1);
void Check(bool condition, string name) { if (!condition) throw new Exception(name); }
Check(OrderRules.Create(new("ERO", "REF-1", [item])).Length == 0, "valid ERO");
Check(OrderRules.Create(new("EDO", "REF-2", [item])).Length == 0, "valid EDO");
Check(OrderRules.Create(new("BOOKING", "REF-3", [item])).Length > 0, "no new Booking");
Check(OrderRules.Create(new("ERO", " ", [item])).Length > 0, "required reference");
Check(OrderRules.Items([item with { Quantity = 0 }]).Length > 0, "positive quantity");
Check(OrderRules.Items([item with { Quantity = 1000001 }]).Length > 0, "maximum quantity");
Check(OrderRules.Items([item, item with { IsoCode = "22g1" }]).Length > 0, "carrier+ISO duplicate");
Check(OrderRules.Items([item, item with { ArmateurId = "MSC" }]).Length == 0, "different carriers");
Check(OrderRules.Items([item with { ArmateurId = "MAE " }]).Length > 0, "no padded carrier identifiers");
Check(OrderRules.Items([item with { IsoCode = "é2G1" }]).Length > 0, "ASCII ISO");
Check(OrderRules.Create(new("ERO", "REF-4", [item with { Id = Guid.NewGuid() }])).Length > 0, "no existing ID on create");
Check(OrderRules.Items(Enumerable.Repeat(item, 51).ToArray()).Length > 0, "item count limit");
Console.WriteLine("PASS: SQL Server 2025 syntax parsing and API order validation. SQL execution/integration remains a separate server check.");
Check(AccountRules.Username("agent01"), "normal identifier without email");
Check(AccountRules.Username("+212600000000"), "phone identifier");
Check(!AccountRules.Username("agent 01") && !AccountRules.Username("ab") && !AccountRules.Username("équipe"), "unambiguous ASCII identifier");
Check(!AccountRules.Username("agent01\n"), "reject trailing newline in identifier");
Check(AccountRules.Normalize("Agent01") == "AGENT01", "case-insensitive account identifier");
Check(AccountRules.Password("A long normal password"), "long passphrase");
Check(!AccountRules.Password("short") && !AccountRules.Password(new string('x',129)), "password bounds");
Check(AccountRules.Roles(["admin","entree"]), "allowed roles");
Check(!AccountRules.Roles(["admin","admin"]) && !AccountRules.Roles(["owner"]) && !AccountRules.Roles([]), "reject invalid roles");
var hasher=AccountRules.Hasher();
var hash=hasher.HashPassword("fixture","A long normal password");
Check(hash!=hasher.HashPassword("fixture","A long normal password"), "per-password random salt");
Check(hasher.VerifyHashedPassword("fixture",hash,"A long normal password")!=PasswordVerificationResult.Failed, "password verification");
Check(hasher.VerifyHashedPassword("fixture",hash,"A different password")==PasswordVerificationResult.Failed, "reject wrong password");
var token=AccountRules.NewToken();
Check(token.Length==43 && AccountRules.TokenHash(token) is {Length:32}, "256-bit opaque session token");
Check(token!=AccountRules.NewToken() && AccountRules.TokenHash("invalid")==null, "independent sessions and malformed token rejection");
Check(AccountRules.TokenHash(token+"\n")==null, "reject trailing newline in token");
var actors=new ActorResolver();
try { await actors.Resolve(new System.Security.Claims.ClaimsPrincipal(),CancellationToken.None); throw new Exception("anonymous actor accepted"); }
catch(UnauthorizedAccessException) { }
var temporary=new System.Security.Claims.ClaimsPrincipal(new System.Security.Claims.ClaimsIdentity([
    new(System.Security.Claims.ClaimTypes.NameIdentifier,Guid.NewGuid().ToString()),new("must_change_password","true")],ApplicationSessionHandler.SchemeName));
try { await actors.Resolve(temporary,CancellationToken.None); throw new Exception("temporary password accessed business operations"); }
catch(PasswordChangeRequiredException) { }
Console.WriteLine("PASS: account rules, salted password hashing, session token generation, anonymous and temporary-password restrictions.");

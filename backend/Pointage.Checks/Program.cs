using Microsoft.SqlServer.TransactSql.ScriptDom;
using Pointage.Api;
using System.Security.Claims;

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
var tenant = Guid.Parse("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa");
var api = Guid.Parse("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb");
var client = Guid.Parse("cccccccc-cccc-4ccc-8ccc-cccccccccccc");
var oid = Guid.Parse("dddddddd-dddd-4ddd-8ddd-dddddddddddd");
var entra = new CorporateAuthentication("EntraId", tenant, api, [client], "access_as_user", "");
ClaimsPrincipal Principal(params Claim[] claims) => new(new ClaimsIdentity(claims, "synthetic-test-only"));
Claim[] validClaims = [new("iss", entra.Authority), new("tid", tenant.ToString()), new("oid", oid.ToString()),
    new("azp", client.ToString()), new("scp", "openid access_as_user"), new("sub", "pairwise-subject")];
void Denied(ClaimsPrincipal user, CorporateAuthentication mode, string test)
{
    try { _ = CorporateIdentity.Resolve(user, mode); }
    catch (UnauthorizedAccessException) { return; }
    throw new Exception(test);
}
var identity = CorporateIdentity.Resolve(Principal(validClaims), entra);
Check(identity.Subject == oid.ToString() && identity.Issuer == entra.Authority, "stable tenant/oid mapping");
Check(CorporateIdentity.Resolve(Principal(validClaims.Where(c => c.Type != "sub").ToArray()), entra) == identity, "no dependency on pairwise sub");
Check(CorporateIdentity.Resolve(Principal(validClaims.Concat([new Claim("roles", "admin"), new Claim("email", "renamed@example.invalid")]).ToArray()), entra) == identity, "role and email claims do not change the profile key");
Denied(Principal(validClaims.Where(c => c.Type != "scp").ToArray()), entra, "app-only token must be denied");
Denied(Principal(validClaims.Where(c => c.Type != "oid").ToArray()), entra, "object ID required");
Denied(Principal(validClaims.Select(c => c.Type == "tid" ? new Claim("tid", Guid.NewGuid().ToString()) : c).ToArray()), entra, "wrong tenant denied");
Denied(Principal(validClaims.Select(c => c.Type == "azp" ? new Claim("azp", Guid.NewGuid().ToString()) : c).ToArray()), entra, "unapproved client denied");
Denied(new ClaimsPrincipal(new ClaimsIdentity(validClaims)), entra, "unauthenticated claims denied");
var windows = new CorporateAuthentication("Windows", Guid.Empty, Guid.Empty, [], "", "CORP.EXAMPLE");
var sid = "S-1-5-21-111-222-333-1001";
Check(CorporateIdentity.Resolve(Principal(new Claim(ClaimTypes.PrimarySid, sid)), windows) == new CorporateIdentity("urn:pointage:ad:corp.example", sid), "stable AD SID mapping");
Denied(Principal(new Claim(ClaimTypes.Name, "CORP\\someone")), windows, "username alone cannot establish identity");
Console.WriteLine("PASS: SQL Server 2025 syntax, API order validation and corporate identity checks. SQL/AD integration remains a separate server check.");

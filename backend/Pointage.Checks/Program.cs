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
Check(GateRules.Container("CSQU3054383") && GateRules.Container(" csqu3054383 "), "ISO6346 valid check digit and normalization");
Check(!GateRules.Container("CSQU3054384") && !GateRules.Container("CSQU3054383X"), "ISO6346 wrong checksum and overlong identity");
var gate = new EnterVisitInput("12345-A-06", "AB123456", "loaded", Guid.NewGuid(), Container: "CSQU3054383");
Check(GateRules.Enter(gate), "valid controlled receiving visit");
Check(!GateRules.Enter(gate with { OrderItemId = Guid.Empty }), "entry requires an order item");
Check(!GateRules.Enter(gate with { IsTwin = true, OrderItemId2 = Guid.NewGuid(), Container2 = "CSQU3054383" }), "twin cannot reuse container");
Check(GateRules.Enter(gate with { EntryKind = "empty", Container = null }), "delivery visit starts with empty truck");
Check(!GateRules.Enter(gate with { EntryKind = "empty" }), "no pickup container assignment at entry");
Check(!GateRules.Details(new() { ["client_id"] = "forged" }), "client attribution cannot enter operational JSON");
Check(!GateRules.Details(new() { ["seal_number"] = new string('x', 61) }), "seal length enforced");
Check(GateRules.Details(new() { ["seal_number_2"] = "SEAL2", ["damage_reservations"] = "Door scratch" }), "twin seals and damage accepted");
Check(!GateRules.Move(new(0)) && GateRules.Move(new(1)), "movement requires positive expected version");
Console.WriteLine("PASS: gate identity, order binding, twin, operational field and version validation. SQL integration is separate.");
var wire=new System.Text.Json.JsonSerializerOptions{
    PropertyNamingPolicy=System.Text.Json.JsonNamingPolicy.SnakeCaseLower,
    PropertyNameCaseInsensitive=false,UnmappedMemberHandling=System.Text.Json.Serialization.JsonUnmappedMemberHandling.Disallow
};
var twinWire=System.Text.Json.JsonSerializer.Deserialize<EnterVisitInput>("""
{"plate":"12345-A-06","cin":"BK12365","entry_kind":"loaded","order_item_id":"11111111-1111-4111-8111-111111111111","is_twin":true,"order_item_id2":"22222222-2222-4222-8222-222222222222","container":"CSQU3054383","container2":"MSCU6639870","operational_details":{"seal_number_2":"SEAL2"},"request_id":"33333333-3333-4333-8333-333333333333"}
""",wire);
Check(twinWire is not null&&GateRules.Enter(twinWire)&&twinWire.OrderItemId2==Guid.Parse("22222222-2222-4222-8222-222222222222"),"Flutter JSON contract for numeric second-slot property names");
Check(twinWire!.RequestId==Guid.Parse("33333333-3333-4333-8333-333333333333"),"Flutter JSON idempotent entry request ID");
Check(RuntimeSqlAccountPolicy.Allows("pointage_runtime",1,0,0,false),"dedicated runtime account accepted");
Check(!RuntimeSqlAccountPolicy.Allows("toszps",1,1,0,false),"owner login requires explicit existing-account mode");
Check(RuntimeSqlAccountPolicy.Allows("toszps",0,1,0,true),"existing toszps owner does not require new login or role grant");
Check(!RuntimeSqlAccountPolicy.Allows("another_owner",1,1,0,true),"existing-account mode is limited to toszps");
Check(!RuntimeSqlAccountPolicy.Allows("toszps",1,1,1,true),"existing-account mode rejects sysadmin");
Check(!RuntimeSqlAccountPolicy.Allows("toszps",1,1,null,true),"unknown server permissions rejected");
Check(!RuntimeSqlAccountPolicy.Allows("pointage_runtime",1,null,0,false),"unknown database permissions rejected");
var legacySecret=System.Text.Json.JsonSerializer.Deserialize<DeploymentSecrets>("""
{"ConnectionString":"synthetic","IntegrationKey":"synthetic","ActorId":"synthetic"}
""");
Check(legacySecret is not null&&!legacySecret.UseExistingSqlLogin&&!legacySecret.AllowUnverifiedSqlCertificate,"older protected configuration keeps dedicated-account and verified-certificate policy");
var transport=new Microsoft.Data.SqlClient.SqlConnectionStringBuilder{
    DataSource="tcp:PRD-DB-ZENATA,54013",InitialCatalog="toszps",
    Encrypt=Microsoft.Data.SqlClient.SqlConnectionEncryptOption.Mandatory,TrustServerCertificate=false
};
Check(SqlTransportPolicy.Allows(transport),"verified encrypted SQL remains the default");
transport.Encrypt=Microsoft.Data.SqlClient.SqlConnectionEncryptOption.Strict;
Check(SqlTransportPolicy.Allows(transport),"verified strict SQL remains supported");
transport.Encrypt=Microsoft.Data.SqlClient.SqlConnectionEncryptOption.Optional;
Check(!SqlTransportPolicy.Allows(transport,true),"encryption remains required even with verified certificate settings");
transport.Encrypt=Microsoft.Data.SqlClient.SqlConnectionEncryptOption.Mandatory;
transport.TrustServerCertificate=true;
Check(!SqlTransportPolicy.Allows(transport),"unverified certificate requires explicit deployment selection");
Check(SqlTransportPolicy.Allows(transport,true),"explicit internal selection keeps encrypted SQL without certificate validation");
transport.Encrypt=Microsoft.Data.SqlClient.SqlConnectionEncryptOption.Optional;
Check(!SqlTransportPolicy.Allows(transport,true),"explicit certificate exception cannot disable encryption");
transport.Encrypt=Microsoft.Data.SqlClient.SqlConnectionEncryptOption.Strict;
Check(!SqlTransportPolicy.Allows(transport,true),"strict mode cannot be labelled certificate-unverified");
transport.Encrypt=Microsoft.Data.SqlClient.SqlConnectionEncryptOption.Mandatory;
transport.DataSource="tcp:other-server,54013";
Check(!SqlTransportPolicy.Allows(transport,true),"certificate exception is limited to known internal SQL endpoints");
transport.DataSource="tcp:172.17.18.209,54013";
Check(SqlTransportPolicy.Allows(transport,true),"explicit internal certificate exception supports known SQL IP");
transport.InitialCatalog="master";
Check(!SqlTransportPolicy.Allows(transport,true),"certificate exception cannot target system databases");
transport.InitialCatalog="toszps";transport.ServerCertificate="synthetic.cer";
Check(!SqlTransportPolicy.Allows(transport,true),"certificate-unverified mode cannot claim a certificate pin");
Console.WriteLine("PASS: SQL transport requires encryption, supports explicit internal certificate exception, and defaults to certificate verification. No database access.");
if(OperatingSystem.IsWindows()){
    var parent=Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar);
    var folder=Path.GetFullPath(Path.Combine(parent,"zenata-dpapi-fixture-"+Guid.NewGuid().ToString("N")));
    var secretFile=Path.Combine(folder,"fixture.secret");
    try{
        var secret=new DeploymentSecrets("synthetic-connection-no-server","synthetic-key-no-runtime","00000000-0000-0000-0000-000000000000");
        secret.Save(secretFile);Check(DeploymentSecrets.Load(secretFile)==secret,"Windows current-user secret roundtrip");
        var existingSecret=secret with { UseExistingSqlLogin=true,AllowUnverifiedSqlCertificate=true };
        existingSecret.Save(secretFile);Check(DeploymentSecrets.Load(secretFile)==existingSecret,"existing-account selection persists in Windows protected configuration");
        Check(!System.Text.Encoding.UTF8.GetString(File.ReadAllBytes(secretFile)).Contains("synthetic-connection"),"no plaintext connection in protected file");
        File.WriteAllBytes(secretFile,new byte[]{1,2,3,4});var rejected=false;
        try{_ = DeploymentSecrets.Load(secretFile);}catch(System.Security.Cryptography.CryptographicException){rejected=true;}
        Check(rejected,"modified deployment secret is rejected");
    }finally{
        // Remove only this freshly generated fixture directory directly under the known temp root.
        if(Path.GetDirectoryName(folder)!=parent||!Path.GetFileName(folder).StartsWith("zenata-dpapi-fixture-",StringComparison.Ordinal))throw new InvalidOperationException("Fixture cleanup path escaped its root.");
        if(Directory.Exists(folder))Directory.Delete(folder,true);
    }
}
Console.WriteLine("PASS: Flutter/API second-slot JSON contract and Windows deployment secret checks (Windows only). No database access.");

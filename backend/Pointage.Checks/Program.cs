using Microsoft.SqlServer.TransactSql.ScriptDom;
using Pointage.Api;

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

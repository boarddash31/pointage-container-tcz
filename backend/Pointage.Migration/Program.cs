using System.Data;
using System.Data.SqlTypes;
using System.Globalization;
using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;

try { await Migration.Run(args); }
catch { Console.Error.WriteLine("Migration stopped. No success is recorded. Credentials and row values are intentionally omitted; review configuration and validation on the secure migration workstation."); Environment.ExitCode = 1; }

internal static partial class Migration
{
    [GeneratedRegex("^[a-z_][a-z0-9_]*$", RegexOptions.CultureInvariant)]
    private static partial Regex Identifier();
    private static string Q(string value) => Identifier().IsMatch(value) ? "[" + value + "]" : throw new InvalidDataException("Invalid identifier.");
    private static string Hash(byte[] bytes) => Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
    private static string Full(Table table) => Q(table.TargetSchema) + "." + Q(table.TargetTable);
    private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower };

    public static async Task Run(string[] args)
    {
        if (args.Length != 3 || args[0] != "--snapshot" || args[2] is not ("--check" or "--apply"))
            throw new ArgumentException("Usage: --snapshot SNAPSHOT_FOLDER --check|--apply");
        var root = FindRoot();
        var manifestFile = Path.Combine(root, "migration/sqlserver/manifest.json");
        var manifest = JsonSerializer.Deserialize<Manifest>(File.ReadAllText(manifestFile), JsonOptions)
            ?? throw new InvalidDataException("Missing manifest.");
        var tables = manifest.Tables;
        var snapshotPath = Path.GetFullPath(args[1]);
        using var snapshot = JsonDocument.Parse(File.ReadAllText(Path.Combine(snapshotPath, "snapshot.json")));
        if (snapshot.RootElement.GetProperty("format").GetInt32() != 1 || snapshot.RootElement.GetProperty("source_project").GetString() != manifest.SourceProject ||
            snapshot.RootElement.GetProperty("manifest_sha256").GetString() != Hash(System.Text.Encoding.UTF8.GetBytes(File.ReadAllText(manifestFile).Replace("\r\n", "\n"))))
            throw new InvalidDataException("Snapshot is incompatible with this schema.");
        var files = snapshot.RootElement.GetProperty("files").EnumerateArray().ToArray();
        if (files.Length != tables.Length || files.Select(f => f.GetProperty("name").GetString()).Distinct().Count() != files.Length)
            throw new InvalidDataException("Missing or repeated snapshot files.");
        // Preflight every file before opening a destination connection or inserting any data.
        foreach (var table in tables)
        {
            var file = FileFor(table, files);
            var filename = PathFor(snapshotPath, file);
            using var stream = File.OpenRead(filename);
            if (Convert.ToHexString(await SHA256.HashDataAsync(stream)).ToLowerInvariant() != file.GetProperty("sha256").GetString())
                throw new InvalidDataException("Snapshot integrity failure.");
            long count = 0;
            foreach (var line in File.ReadLines(filename)) { using var row = JsonDocument.Parse(line); _ = ConvertRow(table, row.RootElement); count++; }
            if (count != file.GetProperty("rows").GetInt64()) throw new InvalidDataException("Snapshot count mismatch.");
            Console.WriteLine(table.SourceTable + ": validated " + count + " rows");
        }
        if (args[2] == "--check") { Console.WriteLine("Snapshot validation passed. Destination untouched."); return; }
        var connectionString = Environment.GetEnvironmentVariable("POINTAGE_TARGET_CONNECTION");
        if (string.IsNullOrWhiteSpace(connectionString)) throw new InvalidOperationException("Set POINTAGE_TARGET_CONNECTION securely.");
        var config = new SqlConnectionStringBuilder(connectionString);
        if (config.TrustServerCertificate || !(SqlConnectionEncryptOption.Mandatory.Equals(config.Encrypt) || SqlConnectionEncryptOption.Strict.Equals(config.Encrypt)) ||
            string.IsNullOrWhiteSpace(config.InitialCatalog) || new[] { "master", "model", "msdb", "tempdb" }.Contains(config.InitialCatalog.ToLowerInvariant()))
            throw new InvalidOperationException("A dedicated, encrypted destination with a trusted certificate is required.");
        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync();
        var initialized = Convert.ToInt32(await Scalar(connection, null, "SELECT COUNT(*) FROM internal.schema_versions WHERE version IN (1,2)"));
        if (initialized != 2) throw new InvalidOperationException("Apply schema versions 1 and 2 first.");
        await using var transaction = (SqlTransaction)await connection.BeginTransactionAsync(IsolationLevel.Serializable);
        try
        {
            foreach (var table in tables)
                if (await Scalar(connection, transaction, "SELECT TOP(1) 1 FROM " + Full(table) + " WITH(TABLOCKX,HOLDLOCK)") is not null)
                    throw new InvalidOperationException("Destination already contains business data.");
            // FK graph order is embedded in manifest import_order; no disabling of FK/check constraints.
            var order = tables.OrderBy(t => t.ImportOrder).ToArray();
            foreach (var table in order)
            {
                var file = FileFor(table, files);
                var filename = PathFor(snapshotPath, file);
                using var batch = DataTableFor(table);
                foreach (var line in File.ReadLines(filename))
                {
                    using var row = JsonDocument.Parse(line);
                    batch.Rows.Add(ConvertRow(table, row.RootElement));
                    if (batch.Rows.Count >= 1000) { await Write(connection, transaction, table, batch); batch.Clear(); }
                }
                if (batch.Rows.Count > 0) await Write(connection, transaction, table, batch);
                var count = Convert.ToInt64(await Scalar(connection, transaction, "SELECT COUNT_BIG(*) FROM " + Full(table)));
                if (count != file.GetProperty("rows").GetInt64()) throw new InvalidDataException("Destination count mismatch.");
                if (table.Columns.Any(c => c.Identity))
                {
                    var max = await Scalar(connection, transaction, "SELECT MAX([id]) FROM " + Full(table));
                    if (max is not null and not DBNull)
                        await Scalar(connection, transaction, "DBCC CHECKIDENT (N'" + table.TargetSchema + "." + table.TargetTable + "',RESEED," +
                            Convert.ToInt64(max).ToString(CultureInfo.InvariantCulture) + ") WITH NO_INFOMSGS");
                }
                Console.WriteLine(table.TargetTable + ": loaded " + count + " rows");
            }
            await using (var check = new SqlCommand("DBCC CHECKCONSTRAINTS WITH ALL_CONSTRAINTS", connection, transaction) { CommandTimeout = 120 })
            await using (var reader = await check.ExecuteReaderAsync())
                if (reader.HasRows) throw new InvalidDataException("Destination constraint validation failed.");
            await transaction.CommitAsync();
            Console.WriteLine("Import committed. Identity accounts, PDF transfer and business acceptance remain separate steps.");
        }
        catch { await transaction.RollbackAsync(); throw; }
    }

    private static string FindRoot()
    {
        for (DirectoryInfo? current = new DirectoryInfo(Environment.CurrentDirectory); current is not null; current = current.Parent)
            if (File.Exists(Path.Combine(current.FullName, "migration/sqlserver/manifest.json"))) return current.FullName;
        throw new DirectoryNotFoundException("Run from the repository.");
    }
    private static JsonElement FileFor(Table table, JsonElement[] files)
    {
        var file = files.Single(f => f.GetProperty("schema").GetString() == table.SourceSchema && f.GetProperty("table").GetString() == table.SourceTable);
        if (file.GetProperty("name").GetString() != table.SourceSchema + "." + table.SourceTable + ".ndjson") throw new InvalidDataException("Unexpected snapshot filename.");
        return file;
    }
    private static string PathFor(string directory, JsonElement file)
    {
        var name = file.GetProperty("name").GetString() ?? throw new InvalidDataException();
        if (name != Path.GetFileName(name)) throw new InvalidDataException("Invalid snapshot filename.");
        return Path.Combine(directory, name);
    }
    private static DataTable DataTableFor(Table table)
    {
        var result = new DataTable();
        foreach (var col in table.Columns)
            result.Columns.Add(col.Name, col.Type switch {
                "uuid" => typeof(Guid), "bool" => typeof(bool), "int4" => typeof(int), "int8" => typeof(long),
                "numeric" => typeof(SqlDecimal), "date" => typeof(DateTime), "timestamptz" => typeof(DateTimeOffset), _ => typeof(string)
            });
        return result;
    }
    private static object[] ConvertRow(Table table, JsonElement row)
    {
        var names = table.Columns.Select(c => c.Name).ToHashSet(StringComparer.Ordinal);
        if (row.ValueKind != JsonValueKind.Object || row.EnumerateObject().Any(p => !names.Contains(p.Name))) throw new InvalidDataException("Unexpected column.");
        return table.Columns.Select<Column, object>(col => {
            if (!row.TryGetProperty(col.Name, out var value) || value.ValueKind == JsonValueKind.Null)
            {
                if (!col.Nullable) throw new InvalidDataException("Required column missing.");
                return (object)DBNull.Value;
            }
            return col.Type switch {
                "uuid" => Guid.Parse(value.GetString()!),
                "bool" => value.GetBoolean(),
                "int4" => value.GetInt32(),
                "int8" => long.Parse(value.GetString()!, CultureInfo.InvariantCulture),
                "numeric" => SqlDecimal.Parse(value.GetString()!),
                "date" => DateTime.ParseExact(value.GetString()!, "yyyy-MM-dd", CultureInfo.InvariantCulture),
                "timestamptz" => DateTimeOffset.Parse(value.GetString()!, CultureInfo.InvariantCulture),
                "jsonb" => ValidJson(value.GetString()!),
                "text" => BoundedText(col, value.GetString()!),
                _ => throw new InvalidDataException("Unsupported type.")
            };
        }).ToArray();
    }
    private static string ValidJson(string text) { using var _ = JsonDocument.Parse(text); return text; }
    private static string BoundedText(Column col, string text)
    {
        var match = Regex.Match(col.SqlType, @"^nvarchar\((\d+)\)");
        if (match.Success && (text.Length > int.Parse(match.Groups[1].Value, CultureInfo.InvariantCulture) || text != text.Trim()))
            throw new InvalidDataException("Text would truncate or change key comparisons.");
        return text;
    }
    private static async Task Write(SqlConnection connection, SqlTransaction transaction, Table table, DataTable rows)
    {
        // Historical rows are restored without replaying business triggers; all FK/check constraints are checked.
        using var copy = new SqlBulkCopy(connection, SqlBulkCopyOptions.KeepIdentity | SqlBulkCopyOptions.CheckConstraints, transaction)
            { DestinationTableName = Full(table), BatchSize = 1000, BulkCopyTimeout = 120 };
        foreach (var col in table.Columns) copy.ColumnMappings.Add(col.Name, col.Name);
        await copy.WriteToServerAsync(rows);
    }
    private static async Task<object?> Scalar(SqlConnection connection, SqlTransaction? transaction, string sql)
    {
        await using var command = new SqlCommand(sql, connection, transaction) { CommandTimeout = 120 };
        var result = await command.ExecuteScalarAsync();
        return result is DBNull ? null : result;
    }
    internal sealed record Manifest(string SourceProject, Table[] Tables);
    internal sealed record Table(string SourceSchema, string SourceTable, string TargetSchema, string TargetTable, int ImportOrder, Column[] Columns);
    internal sealed record Column(string Name, string Type, bool Nullable, string SqlType, bool Identity);
}

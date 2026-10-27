using System.Data;
using System.Security.Claims;
using Microsoft.Data.SqlClient;

namespace Pointage.Api;

public sealed class PointageDb(string connectionString)
{
    public static SqlParameter Uuid(string name, Guid value) => new(name, SqlDbType.UniqueIdentifier) { Value = value };
    public static SqlParameter Text(string name, string? value, int length = -1) => new(name, SqlDbType.NVarChar, length) { Value = (object?)value ?? DBNull.Value };
    public static SqlParameter Number(string name, int value) => new(name, SqlDbType.Int) { Value = value };

    public async Task<object?> Scalar(string procedure, CancellationToken cancellation, params SqlParameter[] parameters)
    {
        await using var connection = new SqlConnection(connectionString);
        await connection.OpenAsync(cancellation);
        await using var command = new SqlCommand(procedure, connection) { CommandType = CommandType.StoredProcedure, CommandTimeout = 30 };
        command.Parameters.AddRange(parameters);
        return await command.ExecuteScalarAsync(cancellation);
    }

    public async Task<string> Json(string procedure, Guid actor, CancellationToken cancellation, params SqlParameter[] parameters)
    {
        var all = new[] { Uuid("@ActorId", actor) }.Concat(parameters).ToArray();
        return (await Scalar(procedure, cancellation, all)) as string ?? "[]";
    }
}

public sealed class ActorResolver(PointageDb database)
{
    public async Task<Guid> Resolve(ClaimsPrincipal principal, CancellationToken cancellation)
    {
        var issuer = principal.FindFirst("iss")?.Value;
        var subject = principal.FindFirst("sub")?.Value;
        if (string.IsNullOrWhiteSpace(issuer) || string.IsNullOrWhiteSpace(subject) || issuer.Length > 256 || subject.Length > 256)
            throw new UnauthorizedAccessException();
        // Map validated external identity to a server-managed profile. Ignore role/user-id claims.
        var result = await database.Scalar("api.resolve_actor", cancellation,
            PointageDb.Text("@Issuer", issuer, 256), PointageDb.Text("@Subject", subject, 256));
        return result is Guid actor ? actor : throw new UnauthorizedAccessException();
    }
}

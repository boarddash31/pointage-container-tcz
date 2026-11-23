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
        if(procedure=="api.app_read"&&parameters.Any(p=>p.ParameterName=="@Operation"&&p.Value is string s&&s is "report-snapshot" or "codeco")){
            await using var connection=new SqlConnection(connectionString);await connection.OpenAsync(cancellation);
            await using var transaction=(SqlTransaction)await connection.BeginTransactionAsync(IsolationLevel.Serializable,cancellation);
            await using var command=new SqlCommand(procedure,connection,transaction){CommandType=CommandType.StoredProcedure,CommandTimeout=30};command.Parameters.AddRange(all);
            var result=await command.ExecuteScalarAsync(cancellation);
            await transaction.CommitAsync(cancellation);return result as string??"[]";
        }
        return (await Scalar(procedure, cancellation, all)) as string ?? "[]";
    }
}

public sealed class ActorResolver
{
    public Task<Guid> Resolve(ClaimsPrincipal principal, CancellationToken cancellation)
    {
        cancellation.ThrowIfCancellationRequested();
        if (principal.Identity?.IsAuthenticated != true ||
            principal.Identity.AuthenticationType != ApplicationSessionHandler.SchemeName ||
            !Guid.TryParse(principal.FindFirstValue(ClaimTypes.NameIdentifier), out var actor))
            throw new UnauthorizedAccessException();
        if (principal.FindFirstValue("must_change_password") != "false") throw new PasswordChangeRequiredException();
        // Only the server session handler supplies this identity. Roles are checked in SQL on every operation.
        return Task.FromResult(actor);
    }
}

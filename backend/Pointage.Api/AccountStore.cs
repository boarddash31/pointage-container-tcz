using System.Data;
using System.Text.Json;
using Microsoft.AspNetCore.Identity;
using Microsoft.Data.SqlClient;

namespace Pointage.Api;

public sealed class AccountStore(PointageDb database, IConfiguration configuration)
{
    private readonly PasswordHasher<string> hasher = AccountRules.Hasher();
    // An unknown identifier still performs password verification. This is not an account or usable credential.
    private readonly string dummyHash = AccountRules.Hasher().HashPassword("unknown", AccountRules.NewToken());
    private static SqlParameter Hash(string name, byte[] value) => new(name, SqlDbType.VarBinary, 32) { Value = value };
    private static bool ReadFlag(JsonElement element, string key) => element.TryGetProperty(key, out var value) && value.GetBoolean();
    private async Task<JsonDocument?> Read(string procedure, CancellationToken ct, params SqlParameter[] parameters)
    {
        var result = await database.Scalar(procedure, ct, parameters);
        if (result is not string json || string.IsNullOrWhiteSpace(json)) return null;
        var document = JsonDocument.Parse(json);
        if (document.RootElement.ValueKind == JsonValueKind.Object) return document;
        document.Dispose();
        return null;
    }
    public async Task<object?> Login(LoginInput input, CancellationToken ct)
    {
        if (!AccountRules.Username(input.Username) || input.Password is not { Length: >= 1 and <= 128 }) return null;
        using var credentials = await Read("api.account_credentials", ct,
            PointageDb.Text("@Username", AccountRules.Normalize(input.Username), 100));
        var root = credentials?.RootElement;
        var user = root?.GetProperty("user_id").GetGuid() ?? Guid.Empty;
        var passwordHash = root?.GetProperty("password_hash").GetString() ?? dummyHash;
        var verified = hasher.VerifyHashedPassword(user.ToString(), passwordHash, input.Password);
        if (root is null) return null;
        var token = AccountRules.NewToken();
        var replacement = verified == PasswordVerificationResult.SuccessRehashNeeded
            ? hasher.HashPassword(user.ToString(), input.Password) : null;
        using var result = await Read("api.account_login", ct,
            PointageDb.Uuid("@UserId", user), PointageDb.Number("@ExpectedVersion", root.Value.GetProperty("version").GetInt32()),
            PointageDb.Text("@ExpectedHash", passwordHash, 512),
            new SqlParameter("@Verified", SqlDbType.Bit) { Value = verified != PasswordVerificationResult.Failed },
            PointageDb.Text("@ReplacementHash", replacement, 512), Hash("@TokenHash", AccountRules.TokenHash(token)!),
            PointageDb.Number("@SessionHours", configuration.GetValue<int>("Accounts:SessionHours")));
        if (result is null) return null;
        return new { access_token = token, token_type = "Bearer",
            expires_at = result.RootElement.GetProperty("expires_at").GetDateTimeOffset(),
            must_change_password = ReadFlag(result.RootElement, "must_change_password"), user_id = user };
    }
    public async Task<(Guid UserId, bool MustChange)?> Resolve(byte[] hash, CancellationToken ct)
    {
        using var result = await Read("api.account_session", ct, Hash("@TokenHash", hash));
        return result is null ? null : (result.RootElement.GetProperty("user_id").GetGuid(), ReadFlag(result.RootElement, "must_change_password"));
    }
    public Task<object?> Logout(byte[] hash, CancellationToken ct) => database.Scalar("api.account_logout", ct, Hash("@TokenHash", hash));
    public async Task<bool> ChangePassword(Guid user, byte[] sessionHash, ChangePasswordInput input, CancellationToken ct)
    {
        using var credentials = await Read("api.account_own_credentials", ct, PointageDb.Uuid("@ActorId", user));
        if (credentials is null) return false;
        var root = credentials.RootElement;
        var oldHash = root.GetProperty("password_hash").GetString()!;
        if (hasher.VerifyHashedPassword(user.ToString(), oldHash, input.CurrentPassword) == PasswordVerificationResult.Failed) return false;
        var result = await database.Scalar("api.account_change_password", ct, PointageDb.Uuid("@ActorId", user),
            PointageDb.Number("@ExpectedVersion", root.GetProperty("version").GetInt32()),
            PointageDb.Text("@PasswordHash", hasher.HashPassword(user.ToString(), input.NewPassword), 512),
            Hash("@TokenHash", sessionHash));
        return result is int changed && changed == 1;
    }
    public Task<string> Create(Guid actor, CreateAccountInput input, CancellationToken ct) => database.Json("api.account_create", actor, ct,
        PointageDb.Text("@Username", input.Username, 100),
        PointageDb.Text("@DisplayName", input.DisplayName.Trim(), 200),
        PointageDb.Text("@PasswordHash", hasher.HashPassword(input.Username, input.Password), 512),
        PointageDb.Text("@Roles", JsonSerializer.Serialize(input.Roles)),
        new SqlParameter("@ExistingProfileId", SqlDbType.UniqueIdentifier) { Value = (object?)input.ExistingProfileId ?? DBNull.Value });
    public Task<string> Update(Guid actor, Guid user, UpdateAccountInput input, CancellationToken ct) => database.Json("api.account_update", actor, ct,
        PointageDb.Uuid("@UserId", user), PointageDb.Number("@ExpectedVersion", input.ExpectedVersion),
        new SqlParameter("@Active", SqlDbType.Bit) { Value = (object?)input.Active ?? DBNull.Value }, PointageDb.Text("@Roles", JsonSerializer.Serialize(input.Roles)));
    public Task<string> Reset(Guid actor, Guid user, ResetPasswordInput input, CancellationToken ct) => database.Json("api.account_reset_password", actor, ct,
        PointageDb.Uuid("@UserId", user), PointageDb.Number("@ExpectedVersion", input.ExpectedVersion),
        PointageDb.Text("@PasswordHash", hasher.HashPassword(user.ToString(), input.Password), 512));
}

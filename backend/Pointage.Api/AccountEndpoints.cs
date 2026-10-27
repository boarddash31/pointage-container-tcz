using System.Security.Claims;

namespace Pointage.Api;

public static class AccountEndpoints
{
    private static Guid User(ClaimsPrincipal user) => Guid.Parse(user.FindFirstValue(ClaimTypes.NameIdentifier)!);
    private static byte[] Session(ClaimsPrincipal user) => Convert.FromHexString(user.FindFirstValue("session_hash")!);
    private static IResult Invalid() => Results.BadRequest(new { error = "invalid_account_input" });
    public static void Map(WebApplication app)
    {
        var auth = app.MapGroup("/api/auth");
        auth.MapPost("/login", async (LoginInput input, AccountStore accounts, HttpContext context, CancellationToken ct) => {
            context.Response.Headers.CacheControl = "no-store";
            var result = await accounts.Login(input, ct);
            return result is null ? Results.Json(new { error = "invalid_credentials" }, statusCode: 401) : Results.Ok(result);
        }).RequireRateLimiting("login");
        auth.MapPost("/logout", async (ClaimsPrincipal user, AccountStore accounts, CancellationToken ct) => {
            await accounts.Logout(Session(user), ct); return Results.NoContent();
        }).RequireAuthorization();
        auth.MapPost("/password", async (ChangePasswordInput input, ClaimsPrincipal user, AccountStore accounts, CancellationToken ct) => {
            if (!AccountRules.Password(input.NewPassword) || input.CurrentPassword is not { Length: >= 1 and <= 128 } || input.CurrentPassword == input.NewPassword) return Invalid();
            return await accounts.ChangePassword(User(user), Session(user), input, ct)
                ? Results.NoContent() : Results.Json(new { error = "invalid_credentials" }, statusCode: 401);
        }).RequireAuthorization().RequireRateLimiting("login");
        var admin = app.MapGroup("/api/users").RequireAuthorization();
        admin.MapGet("/", async (ClaimsPrincipal user, ActorResolver actors, PointageDb db, CancellationToken ct) =>
            Results.Content(await db.Json("api.account_list", await actors.Resolve(user, ct), ct), "application/json"));
        admin.MapPost("/", async (CreateAccountInput input, ClaimsPrincipal user, ActorResolver actors, AccountStore accounts, CancellationToken ct) => {
            if (!AccountRules.Username(input.Username) || !AccountRules.Password(input.Password) || !AccountRules.Roles(input.Roles) ||
                string.IsNullOrWhiteSpace(input.DisplayName) || input.DisplayName.Length > 200 || input.ExistingProfileId == Guid.Empty) return Invalid();
            return Results.Content(await accounts.Create(await actors.Resolve(user, ct), input, ct), "application/json", statusCode: 201);
        });
        admin.MapPut("/{id:guid}", async (Guid id, UpdateAccountInput input, ClaimsPrincipal user, ActorResolver actors, AccountStore accounts, CancellationToken ct) => {
            if (input.ExpectedVersion < 1 || input.Active is null || !AccountRules.Roles(input.Roles)) return Invalid();
            return Results.Content(await accounts.Update(await actors.Resolve(user, ct), id, input, ct), "application/json");
        });
        admin.MapPost("/{id:guid}/password", async (Guid id, ResetPasswordInput input, ClaimsPrincipal user, ActorResolver actors, AccountStore accounts, CancellationToken ct) => {
            if (input.ExpectedVersion < 1 || !AccountRules.Password(input.Password)) return Invalid();
            return Results.Content(await accounts.Reset(await actors.Resolve(user, ct), id, input, ct), "application/json");
        });
    }
}

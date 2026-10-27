using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Encodings.Web;
using System.Text.RegularExpressions;
using Microsoft.AspNetCore.Authentication;
using Microsoft.AspNetCore.Identity;
using Microsoft.AspNetCore.WebUtilities;
using Microsoft.Extensions.Options;

namespace Pointage.Api;

public sealed record LoginInput(string Username, string Password);
public sealed record ChangePasswordInput(string CurrentPassword, string NewPassword);
public sealed record CreateAccountInput(string Username, string Password, string DisplayName, string[] Roles, Guid? ExistingProfileId);
public sealed record UpdateAccountInput(int ExpectedVersion, bool? Active, string[] Roles);
public sealed record ResetPasswordInput(int ExpectedVersion, string Password);
public sealed class PasswordChangeRequiredException : Exception { }

public static partial class AccountRules
{
    [GeneratedRegex("\\A[A-Za-z0-9@._+\\-]{3,100}\\z", RegexOptions.CultureInvariant)]
    private static partial Regex Identifier();
    [GeneratedRegex("\\A[A-Za-z0-9_-]{43}\\z", RegexOptions.CultureInvariant)]
    private static partial Regex SessionToken();
    public static bool Username(string? value) => value is not null && Identifier().IsMatch(value);
    public static bool Password(string? value) => value is { Length: >= 12 and <= 128 } && !string.IsNullOrWhiteSpace(value);
    public static bool Roles(string[]? roles) => roles is { Length: >= 1 and <= 5 } &&
        roles.Distinct(StringComparer.Ordinal).Count() == roles.Length &&
        roles.All(r => r is "admin" or "entree" or "engin" or "sortie" or "viewer");
    public static string Normalize(string username) => username.ToUpperInvariant();
    public static string NewToken() => WebEncoders.Base64UrlEncode(RandomNumberGenerator.GetBytes(32));
    public static byte[]? TokenHash(string? token) => token is not null && SessionToken().IsMatch(token)
        ? SHA256.HashData(Encoding.ASCII.GetBytes(token)) : null;
    public static PasswordHasher<string> Hasher() => new(Options.Create(new PasswordHasherOptions
        { CompatibilityMode = PasswordHasherCompatibilityMode.IdentityV3, IterationCount = 600000 }));
}

public sealed class ApplicationSessionHandler(
    IOptionsMonitor<AuthenticationSchemeOptions> options, ILoggerFactory logger,
    UrlEncoder encoder, AccountStore accounts) : AuthenticationHandler<AuthenticationSchemeOptions>(options, logger, encoder)
{
    public const string SchemeName = "ApplicationSession";
    protected override async Task<AuthenticateResult> HandleAuthenticateAsync()
    {
        var header = Request.Headers.Authorization.ToString();
        if (header.Length == 0) return AuthenticateResult.NoResult();
        if (!header.StartsWith("Bearer ", StringComparison.OrdinalIgnoreCase)) return AuthenticateResult.Fail("Invalid credentials.");
        var hash = AccountRules.TokenHash(header[7..]);
        if (hash is null) return AuthenticateResult.Fail("Invalid credentials.");
        var session = await accounts.Resolve(hash, Context.RequestAborted);
        if (session is null) return AuthenticateResult.Fail("Invalid credentials.");
        var claims = new[] { new Claim(ClaimTypes.NameIdentifier, session.Value.UserId.ToString()),
            new Claim("session_hash", Convert.ToHexString(hash)),
            new Claim("must_change_password", session.Value.MustChange ? "true" : "false") };
        return AuthenticateResult.Success(new AuthenticationTicket(
            new ClaimsPrincipal(new ClaimsIdentity(claims, SchemeName)), SchemeName));
    }
    protected override Task HandleChallengeAsync(AuthenticationProperties properties)
    {
        Response.StatusCode = 401;
        Response.Headers.WWWAuthenticate = "Bearer";
        return Response.WriteAsJsonAsync(new { error = "authentication_required" });
    }
}

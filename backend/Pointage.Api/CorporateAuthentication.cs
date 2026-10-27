using System.Security.Claims;
using System.Security.Principal;
using System.Text.RegularExpressions;

namespace Pointage.Api;

public sealed record CorporateAuthentication(string Mode, Guid TenantId, Guid ApiClientId,
    Guid[] AllowedClientIds, string RequiredScope, string DirectoryId)
{
    public string Authority => $"https://login.microsoftonline.com/{TenantId:D}/v2.0";
    public string Audience => ApiClientId.ToString("D");
    public string WindowsIssuer => "urn:pointage:ad:" + DirectoryId.ToLowerInvariant();

    public static CorporateAuthentication Load(IConfiguration configuration)
    {
        var mode = configuration["Authentication:Mode"];
        if (mode == "Windows")
        {
            var directory = configuration["Authentication:Windows:DirectoryId"] ?? "";
            if (!Regex.IsMatch(directory, @"^[a-zA-Z0-9][a-zA-Z0-9.-]{0,120}$", RegexOptions.CultureInvariant))
                throw new InvalidOperationException("Configure the AD directory identifier approved by IT.");
            return new(mode, Guid.Empty, Guid.Empty, [], "", directory);
        }
        if (mode != "EntraId") throw new InvalidOperationException("Authentication:Mode must be EntraId or Windows.");
        static Guid Identifier(string? value) => Guid.TryParse(value, out var id) && id != Guid.Empty
            ? id : throw new InvalidOperationException("Configure the Entra tenant, API and allowed client application IDs.");
        var tenant = Identifier(configuration["Authentication:EntraId:TenantId"]);
        var api = Identifier(configuration["Authentication:EntraId:ApiClientId"]);
        var clients = (configuration.GetSection("Authentication:EntraId:AllowedClientIds").Get<string[]>() ?? []).Select(Identifier).ToArray();
        var scope = configuration["Authentication:EntraId:RequiredScope"] ?? "access_as_user";
        if (clients.Length == 0 || !Regex.IsMatch(scope, @"^[a-zA-Z0-9_.-]{1,100}$", RegexOptions.CultureInvariant))
            throw new InvalidOperationException("Configure allowed Entra clients and one delegated API scope.");
        return new(mode, tenant, api, clients, scope, "");
    }
}

public sealed record CorporateIdentity(string Issuer, string Subject)
{
    public static CorporateIdentity Resolve(ClaimsPrincipal principal, CorporateAuthentication authentication)
    {
        if (principal.Identity?.IsAuthenticated != true) throw new UnauthorizedAccessException();
        if (authentication.Mode == "Windows")
        {
            // Only a principal produced by the registered Windows/Negotiate handler reaches here.
            // No proxy username header, email address or browser-supplied user ID is accepted.
            var sid = principal.FindFirst(ClaimTypes.PrimarySid)?.Value;
            if (OperatingSystem.IsWindows() && principal.Identity is WindowsIdentity windows) sid = windows.User?.Value;
            if (string.IsNullOrWhiteSpace(sid) || sid.Length > 184 || !Regex.IsMatch(sid, @"^S-1-(?:\d+-)+\d+$", RegexOptions.CultureInvariant))
                throw new UnauthorizedAccessException();
            return new(authentication.WindowsIssuer, sid);
        }
        if (authentication.Mode != "EntraId") throw new UnauthorizedAccessException();
        static Guid Claim(ClaimsPrincipal user, string name) => Guid.TryParse(user.FindFirst(name)?.Value, out var id) && id != Guid.Empty
            ? id : throw new UnauthorizedAccessException();
        var tenant = Claim(principal, "tid");
        var actor = Claim(principal, "oid");
        var client = Claim(principal, "azp");
        if (tenant != authentication.TenantId || !authentication.AllowedClientIds.Contains(client) ||
            principal.FindFirst("iss")?.Value != authentication.Authority ||
            !(principal.FindFirst("scp")?.Value ?? "").Split(' ', StringSplitOptions.RemoveEmptyEntries).Contains(authentication.RequiredScope, StringComparer.Ordinal))
            throw new UnauthorizedAccessException();
        // oid is stable across client applications; sub and email are deliberately not used as profile IDs.
        return new(authentication.Authority, actor.ToString("D"));
    }
}

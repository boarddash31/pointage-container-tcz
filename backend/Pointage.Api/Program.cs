using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Authentication;
using System.Threading.RateLimiting;
using Microsoft.Data.SqlClient;
using Pointage.Api;

var builder = WebApplication.CreateBuilder(args);
var origins = builder.Configuration.GetSection("Cors:Origins").Get<string[]>() ?? [];
if (builder.Configuration.GetValue<int>("Accounts:SessionHours") is < 1 or > 12)
    throw new InvalidOperationException("Configure Accounts:SessionHours between 1 and 12.");
if (origins.Length == 0 || origins.Any(o => !Uri.TryCreate(o, UriKind.Absolute, out var u) || u.Scheme != "https" || u.AbsolutePath != "/"))
    throw new InvalidOperationException("Configure explicit HTTPS Cors:Origins.");
var connectionString = builder.Configuration.GetConnectionString("Pointage");
if (string.IsNullOrWhiteSpace(connectionString))
    throw new InvalidOperationException("Configure ConnectionStrings:Pointage through a protected environment variable.");
var sql = new SqlConnectionStringBuilder(connectionString);
if (sql.TrustServerCertificate || !(SqlConnectionEncryptOption.Mandatory.Equals(sql.Encrypt) || SqlConnectionEncryptOption.Strict.Equals(sql.Encrypt)))
    throw new InvalidOperationException("SQL Server certificate verification and encryption are required.");

builder.WebHost.ConfigureKestrel(o => o.Limits.MaxRequestBodySize = 65536);
builder.Services.ConfigureHttpJsonOptions(o => {
    o.SerializerOptions.PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower;
    o.SerializerOptions.PropertyNameCaseInsensitive = false;
    o.SerializerOptions.UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow;
});
builder.Services.AddAuthentication(ApplicationSessionHandler.SchemeName)
    .AddScheme<AuthenticationSchemeOptions, ApplicationSessionHandler>(ApplicationSessionHandler.SchemeName, _ => { });
builder.Services.AddAuthorization();
builder.Services.AddRateLimiter(options => {
    options.RejectionStatusCode = 429;
    options.AddPolicy("login", context => RateLimitPartition.GetFixedWindowLimiter(
        context.Connection.RemoteIpAddress?.ToString() ?? "unknown", _ => new FixedWindowRateLimiterOptions {
            PermitLimit = 10, Window = TimeSpan.FromMinutes(1), QueueLimit = 0, AutoReplenishment = true
        }));
});
builder.Services.AddCors(o => o.AddDefaultPolicy(p => p.WithOrigins(origins).AllowAnyMethod().AllowAnyHeader()));
builder.Services.AddSingleton(new PointageDb(connectionString));
builder.Services.AddScoped<ActorResolver>();
builder.Services.AddSingleton<AccountStore>();
var app = builder.Build();
app.UseExceptionHandler(errors => errors.Run(async context => {
    var error = context.Features.Get<Microsoft.AspNetCore.Diagnostics.IExceptionHandlerFeature>()?.Error;
    var (status, code) = error switch {
        PasswordChangeRequiredException => (403, "password_change_required"),
        UnauthorizedAccessException => (403, "access_denied"),
        BadHttpRequestException => (400, "invalid_request"),
        SqlException e when e.Number == 51003 => (403, "access_denied"),
        SqlException e when e.Number == 51002 => (404, "not_found"),
        SqlException e when e.Number is 51009 or 2601 or 2627 or 1205 => (409, "conflict_refresh_required"),
        SqlException e when e.Number is 51004 or 547 or 515 or 245 or 8169 => (400, "invalid_operation"),
        SqlException => (503, "database_unavailable"),
        _ => (500, "unexpected_error")
    };
    context.Response.StatusCode = status;
    await context.Response.WriteAsJsonAsync(new { error = code, trace_id = context.TraceIdentifier });
}));
app.UseHttpsRedirection();
app.UseRouting();
app.UseCors();
app.UseRateLimiter();
app.UseAuthentication();
app.UseAuthorization();
app.MapGet("/health/live", () => Results.Ok(new { service = "pointage-api", migration_phase = 2 }));
AccountEndpoints.Map(app);
OrderEndpoints.Map(app);
app.Run();

public partial class Program { }

using System.Text.Json;
using System.Text.Json.Serialization;
using Microsoft.AspNetCore.Authentication.JwtBearer;
using Microsoft.Data.SqlClient;
using Pointage.Api;

var builder = WebApplication.CreateBuilder(args);
var authority = builder.Configuration["Authentication:Authority"];
var audience = builder.Configuration["Authentication:Audience"];
var origins = builder.Configuration.GetSection("Cors:Origins").Get<string[]>() ?? [];
if (!Uri.TryCreate(authority, UriKind.Absolute, out var issuer) || issuer.Scheme != "https" ||
    string.IsNullOrWhiteSpace(audience))
    throw new InvalidOperationException("Configure an HTTPS Authentication:Authority and Authentication:Audience.");
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
builder.Services.AddAuthentication(JwtBearerDefaults.AuthenticationScheme).AddJwtBearer(o => {
    o.Authority = authority; o.Audience = audience; o.RequireHttpsMetadata = true; o.MapInboundClaims = false;
    o.TokenValidationParameters.ValidateIssuer = true;
    o.TokenValidationParameters.ValidateAudience = true;
    o.TokenValidationParameters.ValidateLifetime = true;
    o.TokenValidationParameters.ClockSkew = TimeSpan.FromSeconds(30);
});
builder.Services.AddAuthorization();
builder.Services.AddCors(o => o.AddDefaultPolicy(p => p.WithOrigins(origins).AllowAnyMethod().AllowAnyHeader()));
builder.Services.AddSingleton(new PointageDb(connectionString));
builder.Services.AddScoped<ActorResolver>();
var app = builder.Build();
app.UseExceptionHandler(errors => errors.Run(async context => {
    var error = context.Features.Get<Microsoft.AspNetCore.Diagnostics.IExceptionHandlerFeature>()?.Error;
    var (status, code) = error switch {
        UnauthorizedAccessException => (403, "access_denied"),
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
app.UseCors();
app.UseAuthentication();
app.UseAuthorization();
app.MapGet("/health/live", () => Results.Ok(new { service = "pointage-api", migration_phase = 1 }));
OrderEndpoints.Map(app);
app.Run();

public partial class Program { }

using System.Security.Claims;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;
using System.Data;
using System.Security.Cryptography;

namespace Pointage.Api;

public sealed record EnterVisitInput(string Plate, string Cin, string EntryKind, Guid OrderItemId,
    bool IsTwin = false, Guid? OrderItemId2 = null, string? Container = null, string? Container2 = null,
    Dictionary<string, string>? OperationalDetails = null,Guid? RequestId=null);
public sealed record MoveVisitInput(int ExpectedVersion, string? Container = null, string? Container2 = null,
    string? Position = null, string? Position2 = null, Dictionary<string, string>? OperationalDetails = null);
public sealed record CancelVisitInput(int ExpectedVersion, string Reason);
public sealed record BlockContainerInput(int ExpectedVersion, bool Blocked, string Reason);

public static partial class GateRules
{
    private static readonly Dictionary<string, int> Fields = new(StringComparer.Ordinal) {
        ["haulier"] = 100, ["lane"] = 40, ["lane_2"] = 40, ["seal_number"] = 60,
        ["seal_number_2"] = 60, ["damage_reservations"] = 1000, ["damage_reservations_2"] = 1000
    };
    [GeneratedRegex("^[A-Z]{4}[0-9]{7}$", RegexOptions.CultureInvariant)]
    private static partial Regex ContainerPattern();
    public static string Normalize(string? value) => value?.Trim().ToUpperInvariant() ?? "";
    public static bool Container(string? value)
    {
        var number = Normalize(value);
        if (!ContainerPattern().IsMatch(number)) return false;
        var sum = 0;
        for (var i = 0; i < 10; i++) {
            var code = (int)number[i];
            var digit = i >= 4 ? code - 48 : 10 + code - 65 + (10 + code - 65 - 1) / 10;
            sum += digit * (1 << i);
        }
        return sum % 11 % 10 == number[10] - '0';
    }
    public static bool Details(Dictionary<string, string>? values) => values is null || values.All(
        pair => Fields.TryGetValue(pair.Key, out var max) && pair.Value is not null && pair.Value.Length <= max);
    public static bool Enter(EnterVisitInput r) => !string.IsNullOrWhiteSpace(r.Plate) && r.Plate.Trim().Length is >= 2 and <= 100 &&
        !string.IsNullOrWhiteSpace(r.Cin) && r.Cin.Trim().Length is >= 2 and <= 100 &&
        (r.EntryKind is "loaded" or "empty") && r.OrderItemId != Guid.Empty &&
        (r.IsTwin ? r.OrderItemId2 is Guid second && second != Guid.Empty : r.OrderItemId2 is null && string.IsNullOrWhiteSpace(r.Container2)) &&
        (r.EntryKind == "loaded" ? Container(r.Container) && (!r.IsTwin || Container(r.Container2) && Normalize(r.Container) != Normalize(r.Container2)) :
            string.IsNullOrWhiteSpace(r.Container) && string.IsNullOrWhiteSpace(r.Container2)) && Details(r.OperationalDetails);
    public static bool Move(MoveVisitInput r) => r.ExpectedVersion > 0 &&
        (string.IsNullOrWhiteSpace(r.Container) || Container(r.Container)) &&
        (string.IsNullOrWhiteSpace(r.Container2) || Container(r.Container2)) &&
        (r.Position?.Length ?? 0) <= 1000 && (r.Position2?.Length ?? 0) <= 1000 && Details(r.OperationalDetails);
    public static bool Reason(string? reason) => !string.IsNullOrWhiteSpace(reason) && reason.Trim().Length is >= 3 and <= 1000;
}

public static class GateEndpoints
{
    private static SqlParameter NullableUuid(string name, Guid? value) => new(name, SqlDbType.UniqueIdentifier) { Value = (object?)value ?? DBNull.Value };
    private static SqlParameter Flag(string name, bool value) => new(name, SqlDbType.Bit) { Value = value };
    private static string Details(Dictionary<string, string>? value) => JsonSerializer.Serialize(value ?? new Dictionary<string, string>());
    public static void Map(WebApplication app)
    {
        var api = app.MapGroup("/api").RequireAuthorization();
        api.MapGet("/visits", async Task<IResult> (Guid? afterId, int? pageSize, bool? insideOnly, ClaimsPrincipal user, ActorResolver actors, PointageDb db, CancellationToken ct) => {
            if ((pageSize ?? 200) is < 1 or > 1000) return Results.BadRequest(new { error = "invalid_page" });
            return Results.Content(await db.Json("api.gate_visits", await actors.Resolve(user, ct), ct,
                NullableUuid("@AfterId", afterId), PointageDb.Number("@PageSize", pageSize ?? 200), Flag("@InsideOnly", insideOnly ?? true)), "application/json");
        });
        api.MapGet("/stock", async Task<IResult> (Guid? afterId, int? pageSize, string? iso, string? line, ClaimsPrincipal user, ActorResolver actors, PointageDb db, CancellationToken ct) => {
            if ((pageSize ?? 200) is < 1 or > 1000 || iso is not null && (iso.Length != 4 || !iso.All(c => c is >= '0' and <= '9' or >= 'A' and <= 'Z')) || (line?.Length ?? 0) > 64)
                return Results.BadRequest(new { error = "invalid_stock_filter" });
            return Results.Content(await db.Json("api.gate_stock", await actors.Resolve(user, ct), ct, NullableUuid("@AfterId", afterId),
                PointageDb.Number("@PageSize", pageSize ?? 200), PointageDb.Text("@Iso", iso, 4), PointageDb.Text("@Line", line, 64)), "application/json");
        });
        api.MapGet("/visits/{id:guid}/events", async Task<IResult> (Guid id, long? afterId, int? pageSize, ClaimsPrincipal user, ActorResolver actors, PointageDb db, CancellationToken ct) => {
            if ((pageSize ?? 200) is < 1 or > 1000 || (afterId ?? 0) < 0) return Results.BadRequest(new { error = "invalid_page" });
            return Results.Content(await db.Json("api.gate_events", await actors.Resolve(user, ct), ct, PointageDb.Uuid("@VisitId", id),
                new SqlParameter("@AfterId", SqlDbType.BigInt) { Value = afterId ?? 0 }, PointageDb.Number("@PageSize", pageSize ?? 200)), "application/json");
        });
        api.MapPost("/visits", async Task<IResult> (EnterVisitInput request, ClaimsPrincipal user, ActorResolver actors, PointageDb db, CancellationToken ct) => {
            if (!GateRules.Enter(request)||request.RequestId is not Guid requestId||requestId==Guid.Empty) return Results.BadRequest(new { error = "invalid_visit" });
            return Results.Content(await db.Json("api.enter_visit_once", await actors.Resolve(user, ct), ct,
                PointageDb.Uuid("@RequestId",requestId),new SqlParameter("@PayloadHash",SqlDbType.Binary,32){Value=SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(request))},
                PointageDb.Text("@Plate", request.Plate), PointageDb.Text("@Cin", request.Cin), PointageDb.Text("@EntryKind", request.EntryKind, 8),
                PointageDb.Uuid("@OrderItemId", request.OrderItemId), Flag("@IsTwin", request.IsTwin), NullableUuid("@OrderItemId2", request.OrderItemId2),
                PointageDb.Text("@Container", GateRules.Normalize(request.Container), 64), PointageDb.Text("@Container2", GateRules.Normalize(request.Container2), 64),
                PointageDb.Text("@Details", Details(request.OperationalDetails))), "application/json", statusCode: 201);
        });
        api.MapPost("/visits/{id:guid}/yard", (Guid id, MoveVisitInput request, ClaimsPrincipal user, ActorResolver actors, PointageDb db, CancellationToken ct) => Move(id, "YARD", request, null, user, actors, db, ct));
        api.MapPost("/visits/{id:guid}/exit", (Guid id, MoveVisitInput request, ClaimsPrincipal user, ActorResolver actors, PointageDb db, CancellationToken ct) => Move(id, "EXIT", request, null, user, actors, db, ct));
        api.MapPost("/visits/{id:guid}/empty-exit", (Guid id, MoveVisitInput request, ClaimsPrincipal user, ActorResolver actors, PointageDb db, CancellationToken ct) => Move(id, "EMPTY_EXIT", request, null, user, actors, db, ct));
        api.MapPost("/visits/{id:guid}/cancel", (Guid id, CancelVisitInput request, ClaimsPrincipal user, ActorResolver actors, PointageDb db, CancellationToken ct) => {
            if (!GateRules.Reason(request.Reason)) return Task.FromResult<IResult>(Results.BadRequest(new { error = "invalid_reason" }));
            return Move(id, "CANCEL", new(request.ExpectedVersion), request.Reason.Trim(), user, actors, db, ct);
        });
        api.MapGet("/container-blocks", async Task<IResult> (string? after, int? pageSize, ClaimsPrincipal user, ActorResolver actors, PointageDb db, CancellationToken ct) => {
            if ((pageSize ?? 200) is < 1 or > 1000 || (after?.Length ?? 0) > 11) return Results.BadRequest(new { error = "invalid_page" });
            return Results.Content(await db.Json("api.container_blocks", await actors.Resolve(user, ct), ct, PointageDb.Text("@After", after, 11), PointageDb.Number("@PageSize", pageSize ?? 200)), "application/json");
        });
        api.MapPut("/container-blocks/{number}", async Task<IResult> (string number, BlockContainerInput request, ClaimsPrincipal user, ActorResolver actors, PointageDb db, CancellationToken ct) => {
            if (!GateRules.Container(number) || !GateRules.Reason(request.Reason) || request.ExpectedVersion < 0) return Results.BadRequest(new { error = "invalid_block" });
            return Results.Content(await db.Json("api.set_container_block", await actors.Resolve(user, ct), ct, PointageDb.Text("@Container", GateRules.Normalize(number), 64),
                Flag("@Blocked", request.Blocked), PointageDb.Text("@Reason", request.Reason.Trim()), PointageDb.Number("@ExpectedVersion", request.ExpectedVersion)), "application/json");
        });
    }
    private static async Task<IResult> Move(Guid id, string mode, MoveVisitInput request, string? reason,
        ClaimsPrincipal user, ActorResolver actors, PointageDb db, CancellationToken ct)
    {
        if (!GateRules.Move(request)) return Results.BadRequest(new { error = "invalid_movement" });
        return Results.Content(await db.Json("api.move_visit", await actors.Resolve(user, ct), ct, PointageDb.Uuid("@VisitId", id),
            PointageDb.Number("@ExpectedVersion", request.ExpectedVersion), PointageDb.Text("@Mode", mode, 16),
            PointageDb.Text("@Container", GateRules.Normalize(request.Container), 64), PointageDb.Text("@Container2", GateRules.Normalize(request.Container2), 64),
            PointageDb.Text("@Position", request.Position), PointageDb.Text("@Position2", request.Position2), PointageDb.Text("@Reason", reason),
            PointageDb.Text("@Details", Details(request.OperationalDetails))), "application/json");
    }
}

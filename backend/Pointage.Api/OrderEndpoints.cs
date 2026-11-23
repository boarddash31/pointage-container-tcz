using System.Security.Claims;
using System.Text.Json;
using System.Text.RegularExpressions;
using Microsoft.Data.SqlClient;

namespace Pointage.Api;

public sealed record OrderItemInput(Guid? Id, string IsoCode, string ArmateurId, int Quantity);
public sealed record CreateOrderInput(string Kind, string Reference, OrderItemInput[] Items);
public sealed record UpdateOrderInput(int ExpectedVersion, OrderItemInput[] Items);
public sealed record IncreaseQuantityInput(int Quantity);

public static partial class OrderRules
{
    [GeneratedRegex("^[A-Z0-9]{4}$", RegexOptions.CultureInvariant)]
    private static partial Regex Iso();
    public static string[] Items(OrderItemInput[]? items)
    {
        var errors = new List<string>();
        if (items is null || items.Length is < 1 or > 50) return ["Provide 1 to 50 items."];
        var keys = new HashSet<string>(StringComparer.Ordinal);
        var ids = new HashSet<Guid>();
        foreach (var item in items)
        {
            if (item is null) { errors.Add("Item is required."); continue; }
            var iso = item.IsoCode?.Trim().ToUpperInvariant() ?? "";
            if (!Iso().IsMatch(iso)) errors.Add("ISO must contain four ASCII letters or digits.");
            if (string.IsNullOrWhiteSpace(item.ArmateurId) || item.ArmateurId.Length > 64 || item.ArmateurId != item.ArmateurId.Trim()) errors.Add("Carrier is required without surrounding spaces.");
            if (item.Quantity is < 1 or > 1000000) errors.Add("Quantity must be between 1 and 1000000.");
            if (!keys.Add(item.ArmateurId + "|" + iso)) errors.Add("Duplicate carrier and ISO.");
            if (item.Id is Guid id && (id == Guid.Empty || !ids.Add(id))) errors.Add("Invalid or repeated item ID.");
        }
        return errors.Distinct().ToArray();
    }
    public static string[] Create(CreateOrderInput request)
    {
        var errors = Items(request.Items).ToList();
        if (request.Kind is not ("EDO" or "ERO")) errors.Add("Only EDO and ERO can be created.");
        if (string.IsNullOrWhiteSpace(request.Reference) || request.Reference.Trim().Length > 150) errors.Add("Reference is required, up to 150 characters.");
        if (request.Items?.Any(i => i?.Id is not null) == true) errors.Add("New items cannot supply existing IDs.");
        return errors.ToArray();
    }
}

public static class OrderEndpoints
{
    private static readonly JsonSerializerOptions Json = new() { PropertyNamingPolicy = JsonNamingPolicy.SnakeCaseLower };
    public static void Map(WebApplication app)
    {
        var api = app.MapGroup("/api").RequireAuthorization();
        api.MapGet("/me", async (ClaimsPrincipal user, ActorResolver actors, PointageDb db, CancellationToken ct) =>
            Results.Content(await db.Json("api.user_context", await actors.Resolve(user, ct), ct), "application/json"));
        api.MapGet("/operators", async (ClaimsPrincipal user, ActorResolver actors, PointageDb db, CancellationToken ct) =>
            Results.Content(await db.Json("api.operators", await actors.Resolve(user, ct), ct), "application/json"));
        api.MapGet("/orders/items", ReadItems);
        api.MapPost("/orders", Create);
        api.MapPut("/orders/{id:guid}", Update);
        api.MapPost("/orders/items/{id:guid}/quantity", Increase);
    }
    private static async Task<IResult> ReadItems(string? direction, ClaimsPrincipal user, ActorResolver actors, PointageDb db, CancellationToken ct)
    {
        if (direction is not (null or "LIVRAISON" or "RESTITUTION")) return Results.BadRequest(new { error = "invalid_direction" });
        return Results.Content(await db.Json("api.order_items_status", await actors.Resolve(user, ct), ct,
            PointageDb.Text("@Direction", direction, 16)), "application/json");
    }
    private static async Task<IResult> Create(CreateOrderInput request, ClaimsPrincipal user, ActorResolver actors, PointageDb db, CancellationToken ct)
    {
        var errors = OrderRules.Create(request);
        if (errors.Length != 0) return Results.ValidationProblem(new Dictionary<string, string[]> { ["order"] = errors });
        try { return Results.Content(await db.Json("api.create_order", await actors.Resolve(user, ct), ct,
            PointageDb.Text("@Kind", request.Kind, 32), PointageDb.Text("@Reference", request.Reference.Trim().ToUpperInvariant()),
            PointageDb.Text("@Items", JsonSerializer.Serialize(request.Items, Json))), "application/json", statusCode: 201); }
        catch(SqlException e) when(e.Number is 2601 or 2627){return Results.Conflict(new{error="duplicate_reference"});}
    }
    private static async Task<IResult> Update(Guid id, UpdateOrderInput request, ClaimsPrincipal user, ActorResolver actors, PointageDb db, CancellationToken ct)
    {
        var errors = OrderRules.Items(request.Items);
        if (request.ExpectedVersion < 1 || errors.Length != 0)
            return Results.ValidationProblem(new Dictionary<string, string[]> { ["order"] = errors.Length != 0 ? errors : ["Expected version must be positive."] });
        return Results.Content(await db.Json("api.update_order", await actors.Resolve(user, ct), ct,
            PointageDb.Uuid("@OrderId", id), PointageDb.Number("@ExpectedVersion", request.ExpectedVersion),
            PointageDb.Text("@Items", JsonSerializer.Serialize(request.Items, Json))), "application/json");
    }
    private static async Task<IResult> Increase(Guid id, IncreaseQuantityInput request, ClaimsPrincipal user, ActorResolver actors, PointageDb db, CancellationToken ct)
    {
        if (request.Quantity is < 1 or > 1000000) return Results.BadRequest(new { error = "invalid_quantity" });
        return Results.Content(await db.Json("api.increase_order_quantity", await actors.Resolve(user, ct), ct,
            PointageDb.Uuid("@ItemId", id), PointageDb.Number("@Quantity", request.Quantity)), "application/json");
    }
}

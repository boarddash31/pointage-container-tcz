using System.Data;
using System.Security.Claims;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using Microsoft.Data.SqlClient;

namespace Pointage.Api;

public sealed record ForcedPickupInput(int ExpectedVersion,string Container,string Reason);
public static class ApplicationEndpoints
{
    private static readonly string[] Reads=["clients","operators","container","profiles","audit","forced","visits","transactions","documents","document-context","hourly","dashboard","freepool","report-snapshot"];
    private static readonly Dictionary<string,string[]> Writes=new() {
        ["client"]=["code","name"], ["assignment"]=["client","armateur","from"], ["container"]=["number","iso","armateur"],
        ["profile"]=["id","expected_version","first_name","last_name","avatar_url"], ["reconcile"]=["id","external_reference"], ["document-action"]=["id","action"]
    };
    private static SqlParameter Id(string name,Guid? value)=>new(name,SqlDbType.UniqueIdentifier){Value=(object?)value??DBNull.Value};
    private static SqlParameter At(string name,DateTimeOffset? value)=>new(name,SqlDbType.DateTimeOffset){Value=(object?)value??DBNull.Value};
    private static Task<string> Read(string operation,HttpRequest request,Guid actor,PointageDb db,CancellationToken ct)
    {
        var q=request.Query;
        var idText=q["id"].FirstOrDefault()??q["visitId"].FirstOrDefault()??q["documentId"].FirstOrDefault()??q["clientId"].FirstOrDefault();
        Guid? id=null;DateTime? day=null;DateTimeOffset? from=null,to=null;
        if(idText is not null){if(!Guid.TryParse(idText,out var parsed)||parsed==Guid.Empty)throw new BadHttpRequestException("Invalid identifier.");id=parsed;}
        if(q["day"].FirstOrDefault() is string d){if(!DateTime.TryParseExact(d,"yyyy-MM-dd",System.Globalization.CultureInfo.InvariantCulture,System.Globalization.DateTimeStyles.None,out var parsed))throw new BadHttpRequestException("Invalid day.");day=parsed;}
        if(q["from"].FirstOrDefault() is string f){if(!DateTimeOffset.TryParse(f,out var parsed))throw new BadHttpRequestException("Invalid window.");from=parsed;}
        if(q["to"].FirstOrDefault() is string t){if(!DateTimeOffset.TryParse(t,out var parsed))throw new BadHttpRequestException("Invalid window.");to=parsed;}
        var limit=500;
        if(q["limit"].FirstOrDefault() is string n&&(!int.TryParse(n,out limit)||limit is <1 or >1000))throw new BadHttpRequestException("Invalid limit.");
        var text=q["number"].FirstOrDefault()??q["plate"].FirstOrDefault()??q["kind"].FirstOrDefault();
        if(text?.Length>150)throw new BadHttpRequestException("Invalid filter.");
        return db.Json("api.app_read",actor,ct,PointageDb.Text("@Operation",operation,40),Id("@Id",id),PointageDb.Text("@Text",text,150),
            new SqlParameter("@Day",SqlDbType.Date){Value=(object?)day??DBNull.Value},PointageDb.Number("@Limit",limit),
            new SqlParameter("@AnyTime",SqlDbType.Bit){Value=q["anyTime"]=="true"},At("@From",from),At("@To",to));
    }
    public static void Map(WebApplication app)
    {
        app.MapGet("/api/data/{operation}",async Task<IResult>(string operation,HttpRequest request,ClaimsPrincipal user,ActorResolver actors,PointageDb db,CancellationToken ct)=>{
            if(!Reads.Contains(operation))return Results.NotFound();
            return Results.Content(await Read(operation,request,await actors.Resolve(user,ct),db,ct),"application/json");
        }).RequireAuthorization();
        app.MapPost("/api/settings/{operation}",async Task<IResult>(string operation,JsonElement payload,ClaimsPrincipal user,ActorResolver actors,PointageDb db,CancellationToken ct)=>{
            if(!Writes.TryGetValue(operation,out var fields)||payload.ValueKind!=JsonValueKind.Object||payload.EnumerateObject().Any(p=>!fields.Contains(p.Name))||payload.EnumerateObject().Select(p=>p.Name).Distinct().Count()!=payload.EnumerateObject().Count())return Results.BadRequest(new{error="invalid_operation"});
            if(payload.TryGetProperty("avatar_url",out var avatar)&&avatar.ValueKind!=JsonValueKind.Null){
                if(avatar.ValueKind!=JsonValueKind.String)return Results.BadRequest(new{error="invalid_operation"});
                var value=avatar.GetString()!;
                if(value.Length>2000||value.Length>0&&!(value.StartsWith("/assets/",StringComparison.Ordinal)||Uri.TryCreate(value,UriKind.Absolute,out var uri)&&uri.Scheme=="https"&&uri.UserInfo.Length==0))return Results.BadRequest(new{error="invalid_operation"});
            }
            return Results.Content(await db.Json("api.app_write",await actors.Resolve(user,ct),ct,PointageDb.Text("@Operation",operation,40),PointageDb.Text("@Payload",payload.GetRawText())),"application/json");
        }).RequireAuthorization();
        app.MapPost("/api/visits/{id:guid}/force-pickup",async Task<IResult>(Guid id,ForcedPickupInput input,ClaimsPrincipal user,ActorResolver actors,PointageDb db,CancellationToken ct)=>{
            if(input.ExpectedVersion<1||!GateRules.Container(input.Container)||input.Reason?.Trim().Length is not (>=10 and <=1000))return Results.BadRequest(new{error="invalid_movement"});
            return Results.Content(await db.Json("api.force_pickup",await actors.Resolve(user,ct),ct,PointageDb.Uuid("@VisitId",id),PointageDb.Number("@ExpectedVersion",input.ExpectedVersion),PointageDb.Text("@Container",GateRules.Normalize(input.Container),64),PointageDb.Text("@Reason",input.Reason.Trim())),"application/json");
        }).RequireAuthorization();
        // This key grants only these fixed read routes. It never becomes a browser session or authorizes writes.
        app.MapGet("/internal/source/{operation}",async Task<IResult>(string operation,HttpContext context,IConfiguration config,PointageDb db,CancellationToken ct)=>{
            var expected=config["Integrations:Key"];
            var supplied=context.Request.Headers["X-Pointage-Integration-Key"].ToString();
            if(operation is not ("report-snapshot" or "clients" or "operators" or "codeco")||expected is null||expected.Length<43||supplied.Length>256||
                !CryptographicOperations.FixedTimeEquals(SHA256.HashData(Encoding.UTF8.GetBytes(expected)),SHA256.HashData(Encoding.UTF8.GetBytes(supplied)))||
                !Guid.TryParse(config["Integrations:ActorId"],out var actor))return Results.Unauthorized();
            return Results.Content(await Read(operation,context.Request,actor,db,ct),"application/json");
        });
    }
}

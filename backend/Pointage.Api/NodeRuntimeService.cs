using System.Diagnostics;

namespace Pointage.Api;

public sealed class NodeRuntimeService(IConfiguration config,IHostApplicationLifetime lifetime,PointageDb db,ILogger<NodeRuntimeService> logger):BackgroundService
{
    protected override async Task ExecuteAsync(CancellationToken stoppingToken)
    {
        if(!config.GetValue<bool>("Runtime:Enabled"))return;
        var started=new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        using var ready=lifetime.ApplicationStarted.Register(()=>started.TrySetResult());
        await started.Task.WaitAsync(stoppingToken);
        var root=Path.GetFullPath(config["Runtime:Directory"]??throw new InvalidOperationException("Runtime directory required."));
        Process? node=null;
        try{
            await db.Scalar("api.readiness",stoppingToken);
            var info=new ProcessStartInfo(Path.Combine(root,"node.exe")){
                WorkingDirectory=root,UseShellExecute=false,CreateNoWindow=true
            };
            info.ArgumentList.Add(Path.Combine(root,"http-runtime.cjs"));
            foreach(var name in new[]{"POINTAGE_SOURCE_CONNECTION","POINTAGE_TARGET_CONNECTION","ConnectionStrings__Pointage","REPORTS_SUPABASE_SECRET_KEY","NETLIFY_AUTH_TOKEN"})info.Environment.Remove(name);
            info.Environment["POINTAGE_BACKEND"]="sqlserver";
            info.Environment["POINTAGE_SQL_API_URL"]="http://127.0.0.1:19091/";
            info.Environment["POINTAGE_INTEGRATION_KEY"]=config["Integrations:Key"];
            info.Environment["HOST"]="172.17.18.208";info.Environment["PORT"]="9091";
            node=Process.Start(info)??throw new InvalidOperationException("Unable to launch web runtime.");
            logger.LogInformation("SQL web runtime started on port9091. Backend logs are written by the .NET host.");
            await node.WaitForExitAsync(stoppingToken);
            if(!stoppingToken.IsCancellationRequested){logger.LogError("Web runtime stopped with code {ExitCode}.",node.ExitCode);Environment.ExitCode=1;lifetime.StopApplication();}
        }catch(OperationCanceledException)when(stoppingToken.IsCancellationRequested){ }
        catch(Exception error){logger.LogError("SQL runtime could not start ({ErrorType}). Check SQL readiness, certificate and runtime configuration.",error.GetType().Name);Environment.ExitCode=1;lifetime.StopApplication();}
        finally{if(node is not null){if(!node.HasExited)node.Kill(true);node.Dispose();}}
    }
}

using System.Security.Cryptography;
using System.Text.Json;
using System.Security.AccessControl;
using System.Security.Principal;

namespace Pointage.Api;

public sealed record DeploymentSecrets(string ConnectionString,string IntegrationKey,string ActorId,bool UseExistingSqlLogin=false,bool AllowUnverifiedSqlCertificate=false)
{
    public override string ToString()=>"DeploymentSecrets(redacted)";
    public static DeploymentSecrets Load(string file)
    {
        if(!OperatingSystem.IsWindows())throw new PlatformNotSupportedException("The internal runtime uses Windows DPAPI.");
        var bytes=ProtectedData.Unprotect(File.ReadAllBytes(file),null,DataProtectionScope.CurrentUser);
        try{return JsonSerializer.Deserialize<DeploymentSecrets>(bytes)??throw new InvalidDataException("Invalid protected configuration.");}
        finally{CryptographicOperations.ZeroMemory(bytes);}
    }
    public void Save(string file)
    {
        if(!OperatingSystem.IsWindows())throw new PlatformNotSupportedException("Windows is required.");
        var folder=Path.GetDirectoryName(Path.GetFullPath(file))!;Directory.CreateDirectory(folder);
        var user=WindowsIdentity.GetCurrent().User??throw new InvalidOperationException("Windows identity required.");
        var acl=new DirectorySecurity();acl.SetAccessRuleProtection(true,false);
        foreach(var sid in new[]{user,new SecurityIdentifier(WellKnownSidType.LocalSystemSid,null),new SecurityIdentifier(WellKnownSidType.BuiltinAdministratorsSid,null)})
            acl.AddAccessRule(new FileSystemAccessRule(sid,FileSystemRights.FullControl,InheritanceFlags.ContainerInherit|InheritanceFlags.ObjectInherit,PropagationFlags.None,AccessControlType.Allow));
        new DirectoryInfo(folder).SetAccessControl(acl);
        var bytes=JsonSerializer.SerializeToUtf8Bytes(this);
        try{
            var encrypted=ProtectedData.Protect(bytes,null,DataProtectionScope.CurrentUser);
            var temporary=file+"."+Guid.NewGuid().ToString("N")+".tmp";
            File.WriteAllBytes(temporary,encrypted);File.Move(temporary,file,true);
        }finally{CryptographicOperations.ZeroMemory(bytes);}
    }
}

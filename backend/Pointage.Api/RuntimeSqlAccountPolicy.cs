namespace Pointage.Api;

public static class RuntimeSqlAccountPolicy
{
    public static bool Allows(string login,int? apiRole,int? dbOwner,int? sysadmin,bool useExistingLogin)
        =>sysadmin==0&&(useExistingLogin
            ? string.Equals(login,"toszps",StringComparison.OrdinalIgnoreCase)&&dbOwner==1
            : apiRole==1&&dbOwner==0);
}

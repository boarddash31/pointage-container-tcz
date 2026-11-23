using Microsoft.Data.SqlClient;

namespace Pointage.Api;

public static class SqlTransportPolicy
{
    public static bool Allows(SqlConnectionStringBuilder sql,bool allowUnverifiedCertificate=false)
    {
        if(!sql.TrustServerCertificate)
            return SqlConnectionEncryptOption.Mandatory.Equals(sql.Encrypt)||SqlConnectionEncryptOption.Strict.Equals(sql.Encrypt);
        // The explicit exception is restricted to the company SQL endpoint and keeps full TLS encryption.
        return allowUnverifiedCertificate&&SqlConnectionEncryptOption.Mandatory.Equals(sql.Encrypt)
            &&string.IsNullOrEmpty(sql.ServerCertificate)
            &&string.Equals(sql.InitialCatalog,"toszps",StringComparison.OrdinalIgnoreCase)
            &&(string.Equals(sql.DataSource,"tcp:PRD-DB-ZENATA,54013",StringComparison.OrdinalIgnoreCase)
                ||string.Equals(sql.DataSource,"tcp:172.17.18.209,54013",StringComparison.OrdinalIgnoreCase));
    }
}

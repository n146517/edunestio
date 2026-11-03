using Npgsql;
using NpgsqlTypes;

namespace EduNestIO.Common.Data;

/// <summary>
/// Builds NpgsqlCommand objects for calling PostgreSQL stored functions, mirroring
/// the reference project's DBUtil.CreateCommand usage. All DA classes declare their
/// stored-function signatures once in a dictionary and create reusable command
/// templates from them.
///
/// Convention (matches reference + our /database functions): every tenant-scoped
/// function takes (IN p_tenant_id integer, IN p_payload jsonb) and RETURNS jsonb,
/// so DA code sets two parameters and reads a single JSON scalar result.
/// </summary>
public static class DBUtil
{
    /// <summary>
    /// Creates a command that invokes a stored function returning a scalar jsonb.
    /// We call via "select schema.func(@p0, @p1)" which works for Npgsql without
    /// relying on CommandType.StoredProcedure semantics.
    /// </summary>
    public static NpgsqlCommand CreateJsonFunctionCommand(string qualifiedFunctionName, int parameterCount)
    {
        var placeholders = string.Join(", ", Enumerable.Range(0, parameterCount).Select(i => $"@p{i}"));
        var cmd = new NpgsqlCommand($"select {qualifiedFunctionName}({placeholders})");
        for (var i = 0; i < parameterCount; i++)
        {
            cmd.Parameters.Add(new NpgsqlParameter($"p{i}", DBNull.Value));
        }
        return cmd;
    }

    /// <summary>Creates a tenant+json function command: func(p_tenant_id int, p_payload jsonb).</summary>
    public static NpgsqlCommand CreateTenantJsonCommand(string qualifiedFunctionName)
    {
        var cmd = new NpgsqlCommand($"select {qualifiedFunctionName}(@p0, @p1)");
        cmd.Parameters.Add(new NpgsqlParameter("p0", NpgsqlDbType.Integer) { Value = DBNull.Value });
        cmd.Parameters.Add(new NpgsqlParameter("p1", NpgsqlDbType.Jsonb) { Value = DBNull.Value });
        return cmd;
    }
}

using EduNestIO.Common.Data;
using EduNestIO.Common.DTOs;
using EduNestIO.Common.Logging;
using Newtonsoft.Json;
using Npgsql;
using NpgsqlTypes;

namespace EduNestIO.WebServices.DataAccess;

/// <summary>
/// Shared execution helper for DA classes. Centralizes the "call a stored function
/// that takes (tenant_id, jsonb) and returns a jsonb envelope" pattern, so each DA
/// method stays a thin one-liner, exactly like the reference project's DA methods.
/// </summary>
public static class DAHelper
{
    /// <summary>
    /// Executes a stored function returning a jsonb envelope and deserializes it to DbResult.
    /// payloadObject is serialized with Newtonsoft (PascalCase) to match the function's
    /// expected keys. Opens the connection on the supplied DbMaster.
    /// </summary>
    public static DbResult ExecuteTenantJson(DbMaster db, string qualifiedFunction, int tenantId, object? payloadObject)
    {
        db.Connect();
        var settings = new JsonSerializerSettings { DateFormatString = "yyyy-MM-ddTHH:mm:ss.fffZ" };
        var payloadJson = payloadObject is null ? "{}" : JsonConvert.SerializeObject(payloadObject, settings);

        using var cmd = new NpgsqlCommand($"select {qualifiedFunction}(@p0, @p1)", db.Connection);
        cmd.Parameters.Add(new NpgsqlParameter("p0", NpgsqlDbType.Integer) { Value = tenantId });
        cmd.Parameters.Add(new NpgsqlParameter("p1", NpgsqlDbType.Jsonb) { Value = payloadJson });

        try
        {
            var output = Convert.ToString(cmd.ExecuteScalar());
            if (string.IsNullOrWhiteSpace(output))
            {
                return new DbResult { result_code = (int)Common.ResultCodes.DB_RESPONSE_NULL, message = "Empty DB response" };
            }
            return JsonConvert.DeserializeObject<DbResult>(output!)
                   ?? new DbResult { result_code = (int)Common.ResultCodes.DB_RESPONSE_NULL, message = "Null envelope" };
        }
        catch (Exception ex)
        {
            db.CheckError(ex);
            LogWriter.WriteLog(new LogDTO
            {
                FunctionName = nameof(ExecuteTenantJson),
                ClassName = nameof(DAHelper),
                LogStringLevel = LoggingLevel.Exceptional,
                ExceptionString = ex.Message,
                StackTrace = ex.StackTrace,
                Message = $"Function {qualifiedFunction} failed"
            });
            throw;
        }
    }
}

using EduNestIO.Common;
using EduNestIO.Common.DTOs;
using EduNestIO.Common.Logging;
using EduNestIO.Common.Security;
using EduNestIO.WebServices.DataAccess;
using Newtonsoft.Json.Linq;
using static EduNestIO.WebServices.Business.DBManagerDA;

namespace EduNestIO.WebServices.Business;

/// <summary>
/// Authentication business logic. Verifies credentials with PBKDF2 (framework
/// standard), then mints an opaque server-side session token. Returns a single
/// generic failure for unknown-user and wrong-password to prevent account
/// enumeration. Session tokens are validated on every request by the auth handler.
/// </summary>
public class AuthBL
{
    private const int SessionMinutes = 480;

    public (ResultCodes code, LoginResultDTO? result) Login(LoginVO vo)
    {
        LogWriter.WriteLog(new LogDTO { FunctionName = nameof(Login), ClassName = GetType().Name, AdditionalInfo = "Start -", Message = vo.Username });
        AuthDA? da = null;
        try
        {
            da = (AuthDA)GetDBObject(DAType.Auth)!;

            var authEnv = da.Authenticate(0, vo.Username);
            if (authEnv.result_code != 0 || authEnv.data is null)
            {
                return (ResultCodes.UNAUTHORIZED, null); // generic
            }

            var u = (JObject)authEnv.data;
            var isActive = u.Value<bool?>("is_active") ?? false;
            var lockedUntil = u.Value<DateTime?>("locked_until");
            if (!isActive || (lockedUntil.HasValue && lockedUntil.Value > DateTime.UtcNow))
            {
                return (ResultCodes.UNAUTHORIZED, null);
            }

            var hash = u.Value<string>("password_hash") ?? "";
            var salt = u.Value<string>("password_salt") ?? "";
            if (!PasswordHasher.Verify(vo.Password, hash, salt))
            {
                return (ResultCodes.UNAUTHORIZED, null);
            }

            var userId = u.Value<long>("user_id");
            var tenantId = u.Value<int?>("tenant_id") ?? 0;
            var token = PasswordHasher.NewSessionToken();

            var sessEnv = da.CreateSession(tenantId, userId, token, SessionMinutes);
            if (sessEnv.result_code != 0)
            {
                return (ResultCodes.DB_ERROR, null);
            }

            var result = new LoginResultDTO
            {
                Token = token,
                ExpiresAtUtc = DateTime.UtcNow.AddMinutes(SessionMinutes),
                UserId = userId,
                TenantId = tenantId,
                Username = u.Value<string>("username") ?? vo.Username,
                Email = u.Value<string>("email"),
                FullName = u.Value<string>("full_name"),
                TenantName = u.Value<string>("tenant_name"),
                StudentId = u.Value<long?>("student_id"),
                Roles = (u["roles"] as JArray)?.Select(x => x.ToString()).ToList() ?? new(),
                Permissions = (u["permissions"] as JArray)?.Select(x => x.ToString()).ToList() ?? new()
            };
            return (ResultCodes.SUCCESS, result);
        }
        finally
        {
            ReleaseDBObject(da);
            LogWriter.WriteLog(new LogDTO { FunctionName = nameof(Login), ClassName = GetType().Name, AdditionalInfo = "End -" });
        }
    }

    /// <summary>Validates a bearer token and returns the caller's security context, or null.</summary>
    public UserContext? ValidateToken(string token)
    {
        AuthDA? da = null;
        try
        {
            da = (AuthDA)GetDBObject(DAType.Auth)!;
            var env = da.ValidateSession(token);
            if (env.result_code != 0 || env.data is null)
            {
                return null;
            }

            var u = (JObject)env.data;
            return new UserContext
            {
                UserId = u.Value<long>("user_id"),
                TenantId = u.Value<int?>("tenant_id") ?? 0,
                Username = u.Value<string>("username") ?? "",
                Email = u.Value<string>("email"),
                StudentId = u.Value<long?>("student_id"),
                Roles = (u["roles"] as JArray)?.Select(x => x.ToString()).ToList() ?? new(),
                Permissions = (u["permissions"] as JArray)?.Select(x => x.ToString()).ToList() ?? new()
            };
        }
        finally
        {
            ReleaseDBObject(da);
        }
    }
}

using EduNestIO.Common.Data;
using EduNestIO.Common.DTOs;

namespace EduNestIO.WebServices.DataAccess;

/// <summary>
/// Data access for authentication/session. Password verification itself happens in
/// the Business layer (PBKDF2); this DA only reads the stored hash/salt and manages
/// session tokens via stored functions.
/// </summary>
public class AuthDA : DBBase
{
    public AuthDA(string connectionString = "") : base(connectionString) { }

    public DbResult Authenticate(int tenantId, string username) =>
        DAHelper.ExecuteTenantJson(DbMaster, "core.fn_authenticate", tenantId, new { username });

    public DbResult CreateSession(int tenantId, long userId, string token, int minutes) =>
        DAHelper.ExecuteTenantJson(DbMaster, "core.fn_create_session", tenantId,
            new { user_id = userId, token, minutes });

    public DbResult ValidateSession(string token) =>
        DAHelper.ExecuteTenantJson(DbMaster, "core.fn_validate_session", 0, new { token });
}

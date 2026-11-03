using System.Security.Claims;
using EduNestIO.Common.Security;

namespace EduNestIO.WebServices.RestAPI.Auth;

/// <summary>
/// Builds a <see cref="UserContext"/> from the authenticated ClaimsPrincipal.
/// Controllers call this to obtain the tenant id and permissions — always from the
/// validated token, never from request input.
/// </summary>
public static class CurrentUserAccessor
{
    public static UserContext FromPrincipal(ClaimsPrincipal user)
    {
        long.TryParse(user.FindFirstValue(ClaimTypes.NameIdentifier), out var userId);
        int.TryParse(user.FindFirst("tenant_id")?.Value, out var tenantId);
        long? studentId = long.TryParse(user.FindFirst("student_id")?.Value, out var sid) ? sid : null;

        return new UserContext
        {
            UserId = userId,
            TenantId = tenantId,
            StudentId = studentId,
            Username = user.FindFirstValue(ClaimTypes.Name) ?? string.Empty,
            Email = user.FindFirstValue(ClaimTypes.Email),
            Roles = user.FindAll(ClaimTypes.Role).Select(c => c.Value).ToList(),
            Permissions = user.FindAll("permission").Select(c => c.Value).ToList()
        };
    }
}

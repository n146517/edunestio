namespace EduNestIO.Common.Security;

/// <summary>
/// The authenticated caller's security context for a request. Populated by the
/// authentication handler from validated credentials/claims — NEVER from request
/// body or client-supplied headers. The tenant id here is the authority used for
/// all tenant scoping; controllers/BLs pass UserContext.TenantId to the DA layer.
/// </summary>
public sealed class UserContext
{
    public long UserId { get; init; }
    public int TenantId { get; init; }
    public string Username { get; init; } = string.Empty;
    public string? Email { get; init; }
    /// <summary>The student this login represents, when the user is a linked Student/Guardian.</summary>
    public long? StudentId { get; init; }
    public IReadOnlyList<string> Roles { get; init; } = Array.Empty<string>();
    public IReadOnlyList<string> Permissions { get; init; } = Array.Empty<string>();

    /// <summary>Platform SaaS super admins are not bound to a single tenant.</summary>
    public bool IsPlatformAdmin => Roles.Contains(Common.Security.Roles.SaaSSuperAdmin);

    public bool HasPermission(string permission) =>
        IsPlatformAdmin || Permissions.Contains(permission);
}

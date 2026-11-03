using EduNestIO.WebServices.RestAPI.Auth;
using Microsoft.AspNetCore.Mvc;
using Microsoft.AspNetCore.Mvc.Filters;

namespace EduNestIO.WebServices.RestAPI.Filters;

/// <summary>
/// Server-side permission check. Apply to actions: [RequirePermission(Permissions.StudentCreate)].
/// Returns 403 when the authenticated user lacks the permission. This is the real
/// authorization boundary; frontend guards are UX only.
/// </summary>
[AttributeUsage(AttributeTargets.Method | AttributeTargets.Class, AllowMultiple = true)]
public sealed class RequirePermissionAttribute : Attribute, IAuthorizationFilter
{
    private readonly string[] _permissions;

    /// <summary>
    /// Allow the action when the caller has ANY ONE of the listed permissions (OR).
    /// Passing a single permission preserves the original single-permission behaviour.
    /// </summary>
    public RequirePermissionAttribute(params string[] permissions) => _permissions = permissions;

    public void OnAuthorization(AuthorizationFilterContext context)
    {
        var principal = context.HttpContext.User;
        if (principal?.Identity?.IsAuthenticated != true)
        {
            context.Result = new UnauthorizedResult();
            return;
        }

        var ctx = CurrentUserAccessor.FromPrincipal(principal);
        if (!_permissions.Any(ctx.HasPermission))
        {
            context.Result = new ObjectResult(new { message = "Forbidden: missing permission " + string.Join(" or ", _permissions) })
            {
                StatusCode = StatusCodes.Status403Forbidden
            };
        }
    }
}

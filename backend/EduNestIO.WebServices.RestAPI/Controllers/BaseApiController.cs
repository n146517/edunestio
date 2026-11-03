using EduNestIO.Common;
using EduNestIO.Common.DTOs;
using EduNestIO.Common.Security;
using EduNestIO.WebServices.RestAPI.Auth;
using Microsoft.AspNetCore.Mvc;

namespace EduNestIO.WebServices.RestAPI.Controllers;

/// <summary>
/// Base controller providing the current user context and a consistent mapping of
/// the DB envelope (DbResult) to HTTP + ApiResponse. Reused by all module controllers.
/// </summary>
public abstract class BaseApiController : ControllerBase
{
    protected string? Cid => HttpContext.Items.TryGetValue("CorrelationId", out var c) ? c?.ToString() : null;

    protected UserContext CurrentUser => CurrentUserAccessor.FromPrincipal(User);

    protected ActionResult Map(DbResult env, bool created = false)
    {
        var code = (ResultCodes)env.result_code;
        if (code == ResultCodes.SUCCESS)
        {
            var body = ApiResponse.Ok(env.data, Cid);
            return created ? StatusCode(StatusCodes.Status201Created, body) : Ok(body);
        }

        var status = code switch
        {
            ResultCodes.NOT_FOUND => StatusCodes.Status404NotFound,
            ResultCodes.VALIDATION_ERROR => StatusCodes.Status400BadRequest,
            ResultCodes.DUPLICATE => StatusCodes.Status409Conflict,
            ResultCodes.TENANT_MISMATCH => StatusCodes.Status404NotFound, // no cross-tenant existence leak
            ResultCodes.FORBIDDEN => StatusCodes.Status403Forbidden,
            _ => StatusCodes.Status400BadRequest
        };
        return StatusCode(status, ApiResponse.Fail(code, env.message, Cid));
    }
}

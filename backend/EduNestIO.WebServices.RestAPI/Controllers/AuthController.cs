using EduNestIO.Common;
using EduNestIO.Common.DTOs;
using EduNestIO.Common.Logging;
using EduNestIO.WebServices.Business;
using EduNestIO.WebServices.RestAPI.Auth;
using EduNestIO.WebServices.RestAPI.Filters;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace EduNestIO.WebServices.RestAPI.Controllers;

[ApiController]
[Route("api/auth")]
[ServiceExceptionFilter]
public sealed class AuthController : ControllerBase
{
    /// <summary>Exchanges username/password for an opaque bearer session token.</summary>
    [HttpPost("login")]
    [AllowAnonymous]
    public ActionResult Login([FromBody] LoginVO vo)
    {
        var cid = HttpContext.Items.TryGetValue("CorrelationId", out var c) ? c?.ToString() : null;
        if (string.IsNullOrWhiteSpace(vo.Username) || string.IsNullOrWhiteSpace(vo.Password))
        {
            return BadRequest(ApiResponse.Fail(ResultCodes.VALIDATION_ERROR, "Username and password are required.", cid));
        }

        var (code, result) = new AuthBL().Login(vo);
        if (code != ResultCodes.SUCCESS || result is null)
        {
            // Generic failure (no enumeration): always 401 with the same message.
            return Unauthorized(ApiResponse.Fail(ResultCodes.UNAUTHORIZED, "Invalid credentials.", cid));
        }

        return Ok(ApiResponse.Ok(result, cid));
    }

    /// <summary>Returns the current authenticated user's context (from the validated token).</summary>
    [HttpGet("me")]
    [Authorize]
    public ActionResult Me()
    {
        var cid = HttpContext.Items.TryGetValue("CorrelationId", out var c) ? c?.ToString() : null;
        var ctx = CurrentUserAccessor.FromPrincipal(User);
        return Ok(ApiResponse.Ok(new
        {
            user_id = ctx.UserId,
            tenant_id = ctx.TenantId,
            username = ctx.Username,
            email = ctx.Email,
            roles = ctx.Roles,
            permissions = ctx.Permissions
        }, cid));
    }
}

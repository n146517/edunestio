using EduNestIO.Common.DTOs;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace EduNestIO.WebServices.RestAPI.Controllers;

/// <summary>Public health/status endpoint consumed by the frontend to prove connectivity.</summary>
[ApiController]
[Route("api/status")]
public sealed class StatusController : ControllerBase
{
    [HttpGet]
    [AllowAnonymous]
    public ActionResult Get()
    {
        var cid = HttpContext.Items.TryGetValue("CorrelationId", out var c) ? c?.ToString() : null;
        return Ok(ApiResponse.Ok(new
        {
            status = "ok",
            service = "EduNestIO API",
            server_time_utc = DateTime.UtcNow
        }, cid));
    }
}

using EduNestIO.Common;
using EduNestIO.Common.DTOs;
using EduNestIO.Common.Security;
using EduNestIO.WebServices.Business;
using EduNestIO.WebServices.RestAPI.Filters;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace EduNestIO.WebServices.RestAPI.Controllers;

[ApiController]
[Route("api/leave")]
[Authorize]
[ServiceExceptionFilter]
public sealed class LeaveController : BaseApiController
{
    private readonly LeaveBL _bl = new();

    /// <summary>
    /// Apply for leave. A self-service student can only apply for themselves (the
    /// server uses their linked student id); staff with leave.manage may apply on
    /// behalf of any student by passing StudentId.
    /// </summary>
    [HttpPost]
    [RequirePermission(Permissions.LeaveApply, Permissions.LeaveManage)]
    public ActionResult Apply([FromBody] LeaveApplyVO vo)
    {
        long? effective = CurrentUser.StudentId ?? vo.StudentId;
        if (CurrentUser.StudentId is null && !CurrentUser.HasPermission(Permissions.LeaveManage))
        {
            // A non-linked caller without manage rights cannot target an arbitrary student.
            return StatusCode(StatusCodes.Status403Forbidden,
                ApiResponse.Fail(ResultCodes.FORBIDDEN, "No linked student for this account.", Cid));
        }
        if (effective is null)
        {
            return StatusCode(StatusCodes.Status400BadRequest,
                ApiResponse.Fail(ResultCodes.VALIDATION_ERROR, "A student is required.", Cid));
        }
        return Map(_bl.Apply(CurrentUser.TenantId, CurrentUser.UserId, effective.Value, vo), created: true);
    }

    /// <summary>The signed-in student's own leave history.</summary>
    [HttpGet("mine")]
    [RequirePermission(Permissions.LeaveApply, Permissions.PortalSelf)]
    public ActionResult Mine()
    {
        if (CurrentUser.StudentId is null)
        {
            return StatusCode(StatusCodes.Status403Forbidden,
                ApiResponse.Fail(ResultCodes.FORBIDDEN, "No linked student for this account.", Cid));
        }
        return Map(_bl.Mine(CurrentUser.TenantId, CurrentUser.StudentId.Value));
    }

    /// <summary>Staff review list with optional status/class/search filters.</summary>
    [HttpGet]
    [RequirePermission(Permissions.LeaveManage)]
    public ActionResult List([FromQuery] string? status, [FromQuery] long? classId, [FromQuery] string? search)
        => Map(_bl.List(CurrentUser.TenantId, status, classId, search));

    /// <summary>Cancel a pending leave. A student may only cancel their own.</summary>
    [HttpPost("{leaveId:long}/cancel")]
    [RequirePermission(Permissions.LeaveApply, Permissions.LeaveManage)]
    public ActionResult Cancel(long leaveId)
        => Map(_bl.Cancel(CurrentUser.TenantId, leaveId, CurrentUser.StudentId));

    /// <summary>Approve or reject a pending leave (staff only).</summary>
    [HttpPost("{leaveId:long}/decide")]
    [RequirePermission(Permissions.LeaveManage)]
    public ActionResult Decide(long leaveId, [FromBody] LeaveDecisionVO vo)
        => Map(_bl.Decide(CurrentUser.TenantId, CurrentUser.UserId, leaveId, vo));
}

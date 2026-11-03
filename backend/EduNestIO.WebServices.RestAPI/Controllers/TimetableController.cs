using EduNestIO.Common;
using EduNestIO.Common.DTOs;
using EduNestIO.Common.Security;
using EduNestIO.WebServices.Business;
using EduNestIO.WebServices.RestAPI.Filters;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace EduNestIO.WebServices.RestAPI.Controllers;

[ApiController]
[Route("api/timetable")]
[Authorize]
[ServiceExceptionFilter]
public sealed class TimetableController : BaseApiController
{
    private readonly TimetableBL _bl = new();

    /// <summary>Teachers of this school (for the slot teacher dropdown).</summary>
    [HttpGet("teachers")]
    [RequirePermission(Permissions.TimetableManage, Permissions.AssignmentManage)]
    public ActionResult Teachers() => Map(_bl.Teachers(CurrentUser.TenantId));

    /// <summary>Slots for a class (optionally a section).</summary>
    [HttpGet]
    [RequirePermission(Permissions.TimetableView, Permissions.TimetableManage)]
    public ActionResult List([FromQuery] long classId, [FromQuery] long? sectionId)
        => Map(_bl.List(CurrentUser.TenantId, classId, sectionId));

    /// <summary>The signed-in student's own class timetable.</summary>
    [HttpGet("mine")]
    [RequirePermission(Permissions.TimetableView)]
    public ActionResult Mine()
    {
        if (CurrentUser.StudentId is null)
            return StatusCode(StatusCodes.Status403Forbidden, ApiResponse.Fail(ResultCodes.FORBIDDEN, "No linked student.", Cid));
        return Map(_bl.ForStudent(CurrentUser.TenantId, CurrentUser.StudentId.Value));
    }

    /// <summary>Create or update one slot.</summary>
    [HttpPost]
    [RequirePermission(Permissions.TimetableManage)]
    public ActionResult Save([FromBody] TimetableSlotVO vo) => Map(_bl.Save(CurrentUser.TenantId, vo));

    /// <summary>Delete a slot.</summary>
    [HttpDelete("{slotId:long}")]
    [RequirePermission(Permissions.TimetableManage)]
    public ActionResult Delete(long slotId) => Map(_bl.Delete(CurrentUser.TenantId, slotId));
}

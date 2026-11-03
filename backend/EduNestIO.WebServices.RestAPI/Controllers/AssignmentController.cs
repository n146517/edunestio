using EduNestIO.Common;
using EduNestIO.Common.DTOs;
using EduNestIO.Common.Security;
using EduNestIO.WebServices.Business;
using EduNestIO.WebServices.RestAPI.Filters;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace EduNestIO.WebServices.RestAPI.Controllers;

[ApiController]
[Route("api/assignments")]
[Authorize]
[ServiceExceptionFilter]
public sealed class AssignmentController : BaseApiController
{
    private readonly AssignmentBL _bl = new();

    /// <summary>Staff list (filters: class/section/subject) with submission counts.</summary>
    [HttpGet]
    [RequirePermission(Permissions.AssignmentManage, Permissions.AssignmentView)]
    public ActionResult List([FromQuery] long? classId, [FromQuery] long? sectionId, [FromQuery] long? subjectId)
        => Map(_bl.List(CurrentUser.TenantId, classId, sectionId, subjectId));

    /// <summary>The signed-in student's assignments (with their own submission state).</summary>
    [HttpGet("mine")]
    [RequirePermission(Permissions.AssignmentView)]
    public ActionResult Mine()
    {
        if (CurrentUser.StudentId is null)
            return StatusCode(StatusCodes.Status403Forbidden, ApiResponse.Fail(ResultCodes.FORBIDDEN, "No linked student.", Cid));
        return Map(_bl.ForStudent(CurrentUser.TenantId, CurrentUser.StudentId.Value));
    }

    /// <summary>All students' submissions for one assignment (teacher review).</summary>
    [HttpGet("{assignmentId:long}/submissions")]
    [RequirePermission(Permissions.AssignmentManage)]
    public ActionResult Submissions(long assignmentId)
        => Map(_bl.Submissions(CurrentUser.TenantId, assignmentId));

    /// <summary>Create or update an assignment.</summary>
    [HttpPost]
    [RequirePermission(Permissions.AssignmentManage)]
    public ActionResult Save([FromBody] AssignmentVO vo) => Map(_bl.Save(CurrentUser.TenantId, vo));

    /// <summary>Student submits their work for an assignment.</summary>
    [HttpPost("submit")]
    [RequirePermission(Permissions.AssignmentSubmit)]
    public ActionResult Submit([FromBody] AssignmentSubmitVO vo)
    {
        if (CurrentUser.StudentId is null)
            return StatusCode(StatusCodes.Status403Forbidden, ApiResponse.Fail(ResultCodes.FORBIDDEN, "No linked student.", Cid));
        return Map(_bl.Submit(CurrentUser.TenantId, CurrentUser.StudentId.Value, vo));
    }

    /// <summary>Teacher grades a submission.</summary>
    [HttpPost("grade")]
    [RequirePermission(Permissions.AssignmentManage)]
    public ActionResult Grade([FromBody] AssignmentGradeVO vo)
        => Map(_bl.Grade(CurrentUser.TenantId, CurrentUser.UserId, vo));

    /// <summary>Delete an assignment.</summary>
    [HttpDelete("{assignmentId:long}")]
    [RequirePermission(Permissions.AssignmentManage)]
    public ActionResult Delete(long assignmentId) => Map(_bl.Delete(CurrentUser.TenantId, assignmentId));
}

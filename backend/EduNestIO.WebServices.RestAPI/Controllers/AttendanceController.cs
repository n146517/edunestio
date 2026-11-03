using EduNestIO.Common.DTOs;
using EduNestIO.Common.Security;
using EduNestIO.WebServices.Business;
using EduNestIO.WebServices.RestAPI.Filters;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace EduNestIO.WebServices.RestAPI.Controllers;

/// <summary>
/// Attendance: class-wise daily marking, monthly register, per-student history and
/// a today summary for dashboards. Tenant-scoped; student ids are re-validated
/// server-side in the stored function so cross-tenant marking is impossible.
/// </summary>
[ApiController]
[Route("api/attendance")]
[Authorize]
[ServiceExceptionFilter]
public sealed class AttendanceController : BaseApiController
{
    private readonly AttendanceBL _bl = new();

    /// <summary>Roster for a class on a date with each student's current status.</summary>
    [HttpGet("sheet")]
    [RequirePermission(Permissions.AttendanceView)]
    public ActionResult Sheet([FromQuery] long classId, [FromQuery] string date,
        [FromQuery] long? sectionId, [FromQuery] long? subjectId)
        => Map(_bl.Sheet(CurrentUser.TenantId, classId, date, sectionId, subjectId));

    /// <summary>Bulk mark/correct attendance for a class+date.</summary>
    [HttpPost("mark")]
    [RequirePermission(Permissions.AttendanceMark)]
    public ActionResult Mark([FromBody] AttendanceMarkVO vo)
        => Map(_bl.Mark(CurrentUser.TenantId, CurrentUser.UserId, vo));

    /// <summary>Monthly register for a class.</summary>
    [HttpGet("register")]
    [RequirePermission(Permissions.AttendanceView)]
    public ActionResult Register([FromQuery] long classId, [FromQuery] int year, [FromQuery] int month)
        => Map(_bl.Register(CurrentUser.TenantId, classId, year, month));

    /// <summary>Attendance history for one student.</summary>
    [HttpGet("history/{studentId:long}")]
    [RequirePermission(Permissions.AttendanceView)]
    public ActionResult History(long studentId, [FromQuery] int limit = 60)
        => Map(_bl.History(CurrentUser.TenantId, studentId, limit));

    /// <summary>Today's attendance summary (dashboard KPI).</summary>
    [HttpGet("today")]
    [RequirePermission(Permissions.AttendanceView)]
    public ActionResult Today([FromQuery] string? date)
        => Map(_bl.TodaySummary(CurrentUser.TenantId, date));
}

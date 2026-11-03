using EduNestIO.Common.DTOs;
using EduNestIO.Common.Security;
using EduNestIO.WebServices.Business;
using EduNestIO.WebServices.RestAPI.Filters;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace EduNestIO.WebServices.RestAPI.Controllers;

/// <summary>
/// Academic Setup: academic years, classes, sections, subjects. All actions are
/// authenticated, permission-gated and tenant-scoped (tenant from token).
/// </summary>
[ApiController]
[Route("api/academic")]
[Authorize]
[ServiceExceptionFilter]
public sealed class AcademicController : BaseApiController
{
    private readonly AcademicBL _bl = new();

    // ---- Academic years ----
    [HttpGet("years")]
    [RequirePermission(Permissions.AcademicView)]
    public ActionResult ListYears() => Map(_bl.AcademicYearList(CurrentUser.TenantId));

    [HttpPost("years")]
    [RequirePermission(Permissions.AcademicManage)]
    public ActionResult SaveYear([FromBody] AcademicYearVO vo)
    {
        var created = vo.AcademicYearId is null;
        return Map(_bl.AcademicYearSave(CurrentUser.TenantId, vo), created);
    }

    // ---- Classes ----
    [HttpGet("classes")]
    [RequirePermission(Permissions.AcademicView)]
    public ActionResult ListClasses() => Map(_bl.ClassList(CurrentUser.TenantId));

    [HttpPost("classes")]
    [RequirePermission(Permissions.AcademicManage)]
    public ActionResult SaveClass([FromBody] ClassVO vo)
    {
        var created = vo.ClassId is null;
        return Map(_bl.ClassSave(CurrentUser.TenantId, vo), created);
    }

    // ---- Sections ----
    [HttpGet("sections")]
    [RequirePermission(Permissions.AcademicView)]
    public ActionResult ListSections([FromQuery] long? classId) => Map(_bl.SectionList(CurrentUser.TenantId, classId));

    [HttpPost("sections")]
    [RequirePermission(Permissions.AcademicManage)]
    public ActionResult SaveSection([FromBody] SectionVO vo)
    {
        var created = vo.SectionId is null;
        return Map(_bl.SectionSave(CurrentUser.TenantId, vo), created);
    }

    // ---- Subjects ----
    [HttpGet("subjects")]
    [RequirePermission(Permissions.AcademicView)]
    public ActionResult ListSubjects() => Map(_bl.SubjectList(CurrentUser.TenantId));

    [HttpPost("subjects")]
    [RequirePermission(Permissions.AcademicManage)]
    public ActionResult SaveSubject([FromBody] SubjectVO vo)
    {
        var created = vo.SubjectId is null;
        return Map(_bl.SubjectSave(CurrentUser.TenantId, vo), created);
    }
}

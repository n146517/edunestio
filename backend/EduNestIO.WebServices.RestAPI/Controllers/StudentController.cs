using EduNestIO.Common;
using EduNestIO.Common.DTOs;
using EduNestIO.Common.Security;
using EduNestIO.WebServices.Business;
using EduNestIO.WebServices.RestAPI.Auth;
using EduNestIO.WebServices.RestAPI.Filters;
using EduNestIO.WebServices.RestAPI.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace EduNestIO.WebServices.RestAPI.Controllers;

/// <summary>
/// Student Records module. Every action requires authentication + an explicit
/// permission, and operates strictly within the caller's tenant (resolved from the
/// validated token). The controller is thin: it delegates to StudentBL and shapes
/// the response. Business/data rules live in the BL/DB function layers.
/// </summary>
[ApiController]
[Route("api/students")]
[Authorize]
[ServiceExceptionFilter]
public sealed class StudentController : BaseApiController
{
    [HttpGet]
    [RequirePermission(Permissions.StudentView)]
    public ActionResult List([FromQuery] StudentQueryVO query)
        => Map(new StudentBL().List(CurrentUser.TenantId, query));

    /// <summary>Tenant-scoped counts by status for the list summary cards.</summary>
    [HttpGet("summary")]
    [RequirePermission(Permissions.StudentView)]
    public ActionResult Summary()
        => Map(new StudentBL().Summary(CurrentUser.TenantId));

    [HttpGet("{id:long}")]
    [RequirePermission(Permissions.StudentView)]
    public ActionResult Get(long id)
        => Map(new StudentBL().Get(CurrentUser.TenantId, id));

    [HttpPost]
    [RequirePermission(Permissions.StudentCreate)]
    public ActionResult Create([FromBody] StudentVO vo)
    {
        vo.StudentId = null; // force create
        return Map(new StudentBL().Save(CurrentUser.TenantId, CurrentUser.UserId, vo), created: true);
    }

    [HttpPut("{id:long}")]
    [RequirePermission(Permissions.StudentUpdate)]
    public ActionResult Update(long id, [FromBody] StudentVO vo)
    {
        vo.StudentId = id; // force update of the routed id
        return Map(new StudentBL().Save(CurrentUser.TenantId, CurrentUser.UserId, vo));
    }

    /// <summary>
    /// Explicit, audited status change (Active, Inactive, Graduated, Withdrawn).
    /// Distinct from a plain deactivate so graduation/withdrawal are not conflated.
    /// </summary>
    [HttpPost("{id:long}/status")]
    [RequirePermission(Permissions.StudentStatus)]
    public ActionResult SetStatus(long id, [FromBody] StudentStatusVO vo)
        => Map(new StudentBL().SetStatus(CurrentUser.TenantId, CurrentUser.UserId, id, vo));

    /// <summary>Per-class enrollment history for one student (Grade 1 Promoted, Grade 2 Active, ...).</summary>
    [HttpGet("{id:long}/enrollments")]
    [RequirePermission(Permissions.StudentView)]
    public ActionResult Enrollments(long id)
        => Map(new StudentBL().Enrollments(CurrentUser.TenantId, id));

    /// <summary>
    /// Bulk promote: close each student's current enrollment as Promoted and open a
    /// new Active enrollment in the target class. The student record stays Active.
    /// </summary>
    [HttpPost("promote")]
    [RequirePermission(Permissions.StudentPromote)]
    public ActionResult Promote([FromBody] PromoteVO vo)
        => Map(new StudentBL().Promote(CurrentUser.TenantId, CurrentUser.UserId, vo));

    /// <summary>Bulk graduate (terminal): enrollment Graduated + student status Graduated.</summary>
    [HttpPost("graduate")]
    [RequirePermission(Permissions.StudentPromote)]
    public ActionResult Graduate([FromBody] GraduateVO vo)
        => Map(new StudentBL().Graduate(CurrentUser.TenantId, CurrentUser.UserId, vo));

    /// <summary>Bulk withdraw (terminal): enrollment Withdrawn + student status Withdrawn.</summary>
    [HttpPost("withdraw")]
    [RequirePermission(Permissions.StudentPromote)]
    public ActionResult Withdraw([FromBody] WithdrawVO vo)
        => Map(new StudentBL().Withdraw(CurrentUser.TenantId, CurrentUser.UserId, vo));

    [HttpDelete("{id:long}")]
    [RequirePermission(Permissions.StudentDelete)]
    public ActionResult Delete(long id)
        => Map(new StudentBL().Delete(CurrentUser.TenantId, CurrentUser.UserId, id));

    // ---- Bulk import (Excel) ----

    /// <summary>
    /// Download the student-import Excel template with in-cell dropdowns (Gender,
    /// Blood Group, Class, Section, Academic Year) sourced from this school's data.
    /// </summary>
    [HttpGet("import/template")]
    [RequirePermission(Permissions.StudentCreate)]
    public ActionResult ImportTemplate()
    {
        var academic = new AcademicBL();
        var tenantId = CurrentUser.TenantId;

        var classes = NamesFrom(academic.ClassList(tenantId), "name");
        var sections = DistinctNamesFrom(academic.SectionList(tenantId, null), "name");
        var years = NamesFrom(academic.AcademicYearList(tenantId), "name");

        var genders = new[] { "Male", "Female", "Other" };
        var bloodGroups = new[] { "A+", "A-", "B+", "B-", "AB+", "AB-", "O+", "O-" };
        var relationships = new[] { "Father", "Mother", "Guardian", "Grandfather", "Grandmother", "Uncle", "Aunt", "Other" };

        var bytes = StudentImportExcel.BuildTemplate(genders, bloodGroups, classes, sections, years, relationships);
        return File(bytes, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            "student_import_template.xlsx");
    }

    private static List<string> NamesFrom(DbResult res, string key)
    {
        var list = new List<string>();
        if (res.data?["items"] is Newtonsoft.Json.Linq.JArray items)
            foreach (var i in items)
            {
                var v = (string?)i[key];
                if (!string.IsNullOrWhiteSpace(v)) list.Add(v.Trim());
            }
        return list;
    }

    private static List<string> DistinctNamesFrom(DbResult res, string key)
        => NamesFrom(res, key).Distinct(StringComparer.OrdinalIgnoreCase).OrderBy(x => x).ToList();

    /// <summary>Parse an uploaded template into a validated preview (names resolved, no DB write).</summary>
    [HttpPost("import")]
    [RequirePermission(Permissions.StudentCreate)]
    public async Task<ActionResult> ImportPreview(IFormFile? file)
    {
        if (file is null || file.Length == 0)
            return StatusCode(StatusCodes.Status400BadRequest, ApiResponse.Fail(ResultCodes.VALIDATION_ERROR, "No file uploaded.", Cid));

        using var ms = new MemoryStream();
        await file.CopyToAsync(ms);

        List<StudentImportExcel.RawRow> raw;
        try { raw = StudentImportExcel.Parse(ms.ToArray()); }
        catch { return StatusCode(StatusCodes.Status400BadRequest, ApiResponse.Fail(ResultCodes.VALIDATION_ERROR, "Could not read the file. Use the provided .xlsx template.", Cid)); }

        var rows = raw.Select(r => new StudentImportRow
        {
            RowNumber = r.RowNumber,
            FirstName = r.FirstName, MiddleName = r.MiddleName, LastName = r.LastName,
            Gender = r.Gender, DateOfBirth = r.DateOfBirth, Nationality = r.Nationality, BloodGroup = r.BloodGroup,
            ClassName = r.ClassName, SectionName = r.SectionName, AcademicYear = r.AcademicYear,
            RollNumber = r.RollNumber, AdmissionDate = r.AdmissionDate,
            GuardianName = r.GuardianName, Relationship = r.Relationship, GuardianPhone = r.GuardianPhone,
            GuardianEmail = r.GuardianEmail, Email = r.Email, Phone = r.Phone,
            AddressLine1 = r.AddressLine1, City = r.City, State = r.State, PostalCode = r.PostalCode, Country = r.Country
        }).ToList();

        var preview = new StudentBL().ValidateImport(CurrentUser.TenantId, rows);
        return Ok(ApiResponse.Ok(preview, Cid));
    }

    /// <summary>Create the validated rows as new students. Returns created/failed counts + errors.</summary>
    [HttpPost("import/commit")]
    [RequirePermission(Permissions.StudentCreate)]
    public ActionResult ImportCommit([FromBody] StudentImportCommitVO vo)
    {
        if (vo.Rows.Count == 0)
            return StatusCode(StatusCodes.Status400BadRequest, ApiResponse.Fail(ResultCodes.VALIDATION_ERROR, "No rows to import.", Cid));

        var (created, failed, errors) = new StudentBL().CommitImport(CurrentUser.TenantId, CurrentUser.UserId, vo.Rows);
        return Ok(ApiResponse.Ok(new { created, failed, errors }, Cid));
    }
}

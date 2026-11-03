using EduNestIO.Common;
using EduNestIO.Common.DTOs;
using EduNestIO.Common.Security;
using EduNestIO.WebServices.Business;
using EduNestIO.WebServices.RestAPI.Filters;
using EduNestIO.WebServices.RestAPI.Services;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace EduNestIO.WebServices.RestAPI.Controllers;

/// <summary>
/// Exams and Report Cards: create exams per class, attach subjects with max and
/// pass marks, enter marks in bulk, publish results, and render a computed report
/// card (percentage, grade from the tenant grade scheme, pass or fail). Tenant
/// scoped; student and subject ids are re-validated inside the stored functions.
/// </summary>
[ApiController]
[Route("api/exams")]
[Authorize]
[ServiceExceptionFilter]
public sealed class ExamController : BaseApiController
{
    private readonly ExamBL _bl = new();

    /// <summary>List exams with filters (search, class, year, status, type).</summary>
    [HttpGet]
    [RequirePermission(Permissions.ExamView, Permissions.ExamMarks, Permissions.ExamReportcard)]
    public ActionResult List([FromQuery] ExamQueryVO query)
        => Map(_bl.ExamList(CurrentUser.TenantId, query));

    /// <summary>Get one exam with its classes (for edit / the create wizard).</summary>
    [HttpGet("{examId:long}")]
    [RequirePermission(Permissions.ExamView)]
    public ActionResult Get(long examId)
        => Map(_bl.ExamGet(CurrentUser.TenantId, examId));

    /// <summary>Create or update an exam.</summary>
    [HttpPost]
    [RequirePermission(Permissions.ExamManage)]
    public ActionResult Save([FromBody] ExamVO vo)
        => Map(_bl.ExamSave(CurrentUser.TenantId, vo), created: vo.ExamId is null);

    /// <summary>Attach a single subject (legacy) to an exam.</summary>
    [HttpPost("subjects")]
    [RequirePermission(Permissions.ExamManage)]
    public ActionResult AddSubject([FromBody] ExamSubjectVO vo)
        => Map(_bl.SubjectAdd(CurrentUser.TenantId, vo), created: true);

    /// <summary>Save the full subject configuration for one class of an exam (wizard step 2).</summary>
    [HttpPost("class-subjects")]
    [RequirePermission(Permissions.ExamManage)]
    public ActionResult SaveClassSubjects([FromBody] ExamClassSubjectsVO vo)
        => Map(_bl.ClassSubjectsSave(CurrentUser.TenantId, vo));

    /// <summary>List subject configuration for an exam (optionally one class).</summary>
    [HttpGet("{examId:long}/class-subjects")]
    [RequirePermission(Permissions.ExamView)]
    public ActionResult ClassSubjects(long examId, [FromQuery] long? classId)
        => Map(_bl.ClassSubjectsList(CurrentUser.TenantId, examId, classId));

    /// <summary>Save per-subject schedule (date/time/room) for an exam (wizard step 3).</summary>
    [HttpPost("schedule")]
    [RequirePermission(Permissions.ExamManage)]
    public ActionResult SaveSchedule([FromBody] ExamScheduleSaveVO vo)
        => Map(_bl.ScheduleSave(CurrentUser.TenantId, vo));

    /// <summary>List the exam schedule (optionally one class).</summary>
    [HttpGet("{examId:long}/schedule")]
    [RequirePermission(Permissions.ExamView)]
    public ActionResult Schedule(long examId, [FromQuery] long? classId)
        => Map(_bl.ScheduleList(CurrentUser.TenantId, examId, classId));

    /// <summary>Subjects configured for an exam+class (populates the marks-entry dropdown).</summary>
    [HttpGet("{examId:long}/classes/{classId:long}/subjects")]
    [RequirePermission(Permissions.ExamView, Permissions.ExamMarks)]
    public ActionResult SubjectsForClass(long examId, long classId)
        => Map(_bl.SubjectsForClass(CurrentUser.TenantId, examId, classId));

    /// <summary>Resolve (exam, class, subject) to an exam_subject for marks entry.</summary>
    [HttpGet("{examId:long}/classes/{classId:long}/subjects/{subjectId:long}/resolve")]
    [RequirePermission(Permissions.ExamView, Permissions.ExamMarks)]
    public ActionResult ResolveExamSubject(long examId, long classId, long subjectId)
        => Map(_bl.ResolveExamSubject(CurrentUser.TenantId, examId, classId, subjectId));

    /// <summary>Marks entry sheet (class roster) for one exam subject; optional section filter.</summary>
    [HttpGet("subjects/{examSubjectId:long}/sheet")]
    [RequirePermission(Permissions.ExamView, Permissions.ExamMarks)]
    public ActionResult MarksSheet(long examSubjectId, [FromQuery] long? sectionId)
        => Map(_bl.MarksSheet(CurrentUser.TenantId, examSubjectId, sectionId));

    /// <summary>Bulk save marks for an exam subject.</summary>
    [HttpPost("marks")]
    [RequirePermission(Permissions.ExamMarks)]
    public ActionResult SaveMarks([FromBody] ExamMarksSaveVO vo)
        => Map(_bl.MarksSave(CurrentUser.TenantId, CurrentUser.UserId, vo));

    /// <summary>Download an Excel marks template (roster rows for one exam subject).</summary>
    [HttpGet("subjects/{examSubjectId:long}/template")]
    [RequirePermission(Permissions.ExamView, Permissions.ExamMarks)]
    public ActionResult MarksTemplate(long examSubjectId, [FromQuery] long? sectionId)
    {
        var sheet = _bl.MarksSheet(CurrentUser.TenantId, examSubjectId, sectionId);
        if ((ResultCodes)sheet.result_code != ResultCodes.SUCCESS)
            return Map(sheet);

        var rows = ExamMarksExcel.RosterRows(sheet.data);
        var bytes = ExamMarksExcel.BuildTemplate(rows, ExamMarksExcel.MaxMarks(sheet.data));
        return File(bytes, "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet",
            $"marks_template_{examSubjectId}.xlsx");
    }

    /// <summary>
    /// Parse an uploaded Excel file into marks entries (preview). Matches rows to the
    /// roster by admission number and validates the marks range. Does NOT persist —
    /// the client reviews, then calls POST /marks to commit.
    /// </summary>
    [HttpPost("subjects/{examSubjectId:long}/import")]
    [RequirePermission(Permissions.ExamMarks)]
    public async Task<ActionResult> ImportMarks(long examSubjectId, IFormFile? file, [FromQuery] long? sectionId)
    {
        if (file is null || file.Length == 0)
            return StatusCode(StatusCodes.Status400BadRequest, ApiResponse.Fail(ResultCodes.VALIDATION_ERROR, "No file uploaded.", Cid));

        var sheet = _bl.MarksSheet(CurrentUser.TenantId, examSubjectId, sectionId);
        if ((ResultCodes)sheet.result_code != ResultCodes.SUCCESS)
            return Map(sheet);

        using var stream = new MemoryStream();
        await file.CopyToAsync(stream);
        var preview = ExamMarksExcel.Parse(stream.ToArray(), sheet.data, ExamMarksExcel.MaxMarks(sheet.data));
        return Ok(ApiResponse.Ok(preview, Cid));
    }

    /// <summary>Class-wide result preview (totals, grade, result, Ready/Missing status).</summary>
    [HttpGet("{examId:long}/classes/{classId:long}/results")]
    [RequirePermission(Permissions.ExamView)]
    public ActionResult ResultPreview(long examId, long classId, [FromQuery] long? sectionId)
        => Map(_bl.ResultPreview(CurrentUser.TenantId, examId, classId, sectionId));

    /// <summary>Publish or unpublish an exam's results (blocked on missing marks unless Force).</summary>
    [HttpPost("publish")]
    [RequirePermission(Permissions.ExamPublish)]
    public ActionResult Publish([FromBody] ExamPublishVO vo)
        => Map(_bl.Publish(CurrentUser.TenantId, vo));

    /// <summary>Computed report card for a student in an exam (incl. school/student header).</summary>
    [HttpGet("{examId:long}/report-card/{studentId:long}")]
    [RequirePermission(Permissions.ExamView, Permissions.ExamReportcard)]
    public ActionResult ReportCard(long examId, long studentId)
        => Map(_bl.ReportCard(CurrentUser.TenantId, examId, studentId, requirePublished: false));

    /// <summary>Class/section roster with result summary + published flag (report-cards screen).</summary>
    [HttpGet("{examId:long}/classes/{classId:long}/report-cards")]
    [RequirePermission(Permissions.ExamView, Permissions.ExamReportcard)]
    public ActionResult ReportCardClassList(long examId, long classId, [FromQuery] long? sectionId)
        => Map(_bl.ReportCardClassList(CurrentUser.TenantId, examId, classId, sectionId));
}

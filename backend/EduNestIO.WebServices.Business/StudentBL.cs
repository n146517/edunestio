using System.Globalization;
using EduNestIO.Common.DTOs;
using EduNestIO.Common.Logging;
using EduNestIO.WebServices.DataAccess;
using Newtonsoft.Json.Linq;
using static EduNestIO.WebServices.Business.DBManagerDA;

namespace EduNestIO.WebServices.Business;

/// <summary>
/// Business logic for the Student module. Follows the reference pattern: obtain the
/// DA from the factory, call it, release in finally. All methods receive the tenant
/// id resolved from the authenticated UserContext (never from client input).
/// </summary>
public class StudentBL
{
    public DbResult Save(int tenantId, long actorUserId, StudentVO vo)
    {
        LogWriter.WriteLog(new LogDTO { FunctionName = nameof(Save), ClassName = GetType().Name, AdditionalInfo = "Start -" });
        StudentDA? da = null;
        try
        {
            da = (StudentDA)GetDBObject(DAType.Student)!;
            // Build the payload the stored function expects (PascalCase + ActorUserId).
            // Dates serialized as yyyy-MM-dd so the function's ::date cast is unambiguous.
            var payload = new
            {
                vo.StudentId, vo.AdmissionNumber, vo.FirstName, vo.MiddleName, vo.LastName,
                vo.Gender,
                DateOfBirth = vo.DateOfBirth?.ToString("yyyy-MM-dd"),
                vo.Nationality, vo.BloodGroup, vo.PhotoUrl,
                vo.Email, vo.Phone,
                vo.AddressLine1, vo.AddressLine2, vo.City, vo.State, vo.PostalCode, vo.Country,
                vo.ClassId, vo.SectionId, vo.AcademicYearId, vo.RollNumber,
                AdmissionDate = vo.AdmissionDate?.ToString("yyyy-MM-dd"),
                vo.Status,
                vo.GuardianName, vo.GuardianRelation, vo.GuardianPhone, vo.GuardianAltPhone, vo.GuardianEmail,
                ActorUserId = actorUserId
            };
            return da.Save(tenantId, payload);
        }
        finally
        {
            ReleaseDBObject(da);
            LogWriter.WriteLog(new LogDTO { FunctionName = nameof(Save), ClassName = GetType().Name, AdditionalInfo = "End -" });
        }
    }

    public DbResult Get(int tenantId, long studentId)
    {
        StudentDA? da = null;
        try
        {
            da = (StudentDA)GetDBObject(DAType.Student)!;
            return da.Get(tenantId, studentId);
        }
        finally { ReleaseDBObject(da); }
    }

    public DbResult List(int tenantId, StudentQueryVO query)
    {
        StudentDA? da = null;
        try
        {
            da = (StudentDA)GetDBObject(DAType.Student)!;
            var payload = new
            {
                search = query.Search,
                class_id = query.ClassId,
                section_id = query.SectionId,
                academic_year_id = query.AcademicYearId,
                status = query.Status,
                page = query.Page,
                page_size = query.PageSize,
                sort_by = query.SortBy,
                sort_dir = query.SortDir
            };
            return da.List(tenantId, payload);
        }
        finally { ReleaseDBObject(da); }
    }

    public DbResult Delete(int tenantId, long actorUserId, long studentId)
    {
        StudentDA? da = null;
        try
        {
            da = (StudentDA)GetDBObject(DAType.Student)!;
            return da.Delete(tenantId, studentId, actorUserId);
        }
        finally { ReleaseDBObject(da); }
    }

    public DbResult SetStatus(int tenantId, long actorUserId, long studentId, StudentStatusVO vo)
    {
        StudentDA? da = null;
        try
        {
            da = (StudentDA)GetDBObject(DAType.Student)!;
            var payload = new
            {
                student_id = studentId,
                status = vo.Status,
                reason = vo.Reason,
                ActorUserId = actorUserId
            };
            return da.SetStatus(tenantId, payload);
        }
        finally { ReleaseDBObject(da); }
    }

    public DbResult Summary(int tenantId)
    {
        StudentDA? da = null;
        try
        {
            da = (StudentDA)GetDBObject(DAType.Student)!;
            return da.Summary(tenantId);
        }
        finally { ReleaseDBObject(da); }
    }

    public DbResult Enrollments(int tenantId, long studentId)
    {
        StudentDA? da = null;
        try
        {
            da = (StudentDA)GetDBObject(DAType.Student)!;
            return da.Enrollments(tenantId, studentId);
        }
        finally { ReleaseDBObject(da); }
    }

    public DbResult Promote(int tenantId, long actorUserId, PromoteVO vo)
    {
        StudentDA? da = null;
        try
        {
            da = (StudentDA)GetDBObject(DAType.Student)!;
            var payload = new
            {
                student_ids = vo.StudentIds,
                to_class_id = vo.ToClassId,
                to_section_id = vo.ToSectionId,
                academic_year_id = vo.AcademicYearId,
                note = vo.Note,
                ActorUserId = actorUserId
            };
            return da.Promote(tenantId, payload);
        }
        finally { ReleaseDBObject(da); }
    }

    public DbResult Graduate(int tenantId, long actorUserId, GraduateVO vo)
    {
        StudentDA? da = null;
        try
        {
            da = (StudentDA)GetDBObject(DAType.Student)!;
            var payload = new { student_ids = vo.StudentIds, note = vo.Note, ActorUserId = actorUserId };
            return da.Graduate(tenantId, payload);
        }
        finally { ReleaseDBObject(da); }
    }

    public DbResult Withdraw(int tenantId, long actorUserId, WithdrawVO vo)
    {
        StudentDA? da = null;
        try
        {
            da = (StudentDA)GetDBObject(DAType.Student)!;
            var payload = new { student_ids = vo.StudentIds, reason = vo.Reason, ActorUserId = actorUserId };
            return da.Withdraw(tenantId, payload);
        }
        finally { ReleaseDBObject(da); }
    }

    // ---- Bulk import ----

    private sealed record Lookup(
        Dictionary<string, long> Classes,
        Dictionary<string, (long id, long classId)> Sections,
        Dictionary<string, long> Years);

    /// <summary>Load the tenant's classes/sections/years so import rows can resolve names to ids.</summary>
    private Lookup LoadLookups(int tenantId)
    {
        var academic = new AcademicBL();
        var classes = new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);
        var sections = new Dictionary<string, (long, long)>(StringComparer.OrdinalIgnoreCase);
        var years = new Dictionary<string, long>(StringComparer.OrdinalIgnoreCase);

        var cRes = academic.ClassList(tenantId);
        if (cRes.data?["items"] is JArray cls)
            foreach (var c in cls)
                classes[(c["name"]?.Value<string>() ?? "").Trim()] = c["class_id"]!.Value<long>();

        var sRes = academic.SectionList(tenantId, null);
        if (sRes.data?["items"] is JArray secs)
            foreach (var s in secs)
            {
                // Key sections by "ClassName|SectionName" so a bare 'A' is unambiguous per class.
                var key = $"{(s["class_name"]?.Value<string>() ?? "").Trim()}|{(s["name"]?.Value<string>() ?? "").Trim()}";
                sections[key] = (s["section_id"]!.Value<long>(), s["class_id"]!.Value<long>());
            }

        var yRes = academic.AcademicYearList(tenantId);
        if (yRes.data?["items"] is JArray yrs)
            foreach (var y in yrs)
                years[(y["name"]?.Value<string>() ?? "").Trim()] = y["academic_year_id"]!.Value<long>();

        return new Lookup(classes, sections, years);
    }

    private static string? ParseDate(string raw)
    {
        if (string.IsNullOrWhiteSpace(raw)) return null;
        var formats = new[] { "yyyy-MM-dd", "dd-MM-yyyy", "dd/MM/yyyy", "MM/dd/yyyy", "yyyy/MM/dd" };
        if (DateTime.TryParseExact(raw.Trim(), formats, CultureInfo.InvariantCulture, DateTimeStyles.None, out var d)
            || DateTime.TryParse(raw.Trim(), CultureInfo.InvariantCulture, DateTimeStyles.None, out d))
            return d.ToString("yyyy-MM-dd");
        return null; // caller flags invalid
    }

    /// <summary>Validate + resolve import rows (names→ids). No DB writes. Returns a preview.</summary>
    public StudentImportPreview ValidateImport(int tenantId, List<StudentImportRow> rows)
    {
        var look = LoadLookups(tenantId);
        var preview = new StudentImportPreview();

        foreach (var row in rows)
        {
            var errors = new List<string>();

            // Normalise whitespace so stray spaces don't cause false mismatches.
            row.FirstName = row.FirstName?.Trim() ?? "";
            row.LastName = row.LastName?.Trim() ?? "";
            row.ClassName = row.ClassName?.Trim();
            row.SectionName = row.SectionName?.Trim();
            row.AcademicYear = row.AcademicYear?.Trim();

            if (string.IsNullOrWhiteSpace(row.FirstName)) errors.Add("First name is required");
            if (string.IsNullOrWhiteSpace(row.LastName)) errors.Add("Last name is required");

            // Dates
            if (!string.IsNullOrWhiteSpace(row.DateOfBirth))
            {
                var d = ParseDate(row.DateOfBirth);
                if (d is null) errors.Add("Invalid date of birth (use YYYY-MM-DD)");
                else row.DateOfBirth = d;
            }
            if (!string.IsNullOrWhiteSpace(row.AdmissionDate))
            {
                var d = ParseDate(row.AdmissionDate);
                if (d is null) errors.Add("Invalid admission date (use YYYY-MM-DD)");
                else row.AdmissionDate = d;
            }

            // Class
            if (!string.IsNullOrWhiteSpace(row.ClassName))
            {
                if (look.Classes.TryGetValue(row.ClassName.Trim(), out var cid)) row.ClassId = cid;
                else errors.Add($"Unknown class '{row.ClassName}'");
            }
            // Section (must belong to the class)
            if (!string.IsNullOrWhiteSpace(row.SectionName))
            {
                if (string.IsNullOrWhiteSpace(row.ClassName))
                    errors.Add("Section given without a class");
                else if (look.Sections.TryGetValue($"{row.ClassName.Trim()}|{row.SectionName.Trim()}", out var sec))
                    row.SectionId = sec.id;
                else errors.Add($"Unknown section '{row.SectionName}' for class '{row.ClassName}'");
            }
            // Academic year
            if (!string.IsNullOrWhiteSpace(row.AcademicYear))
            {
                if (look.Years.TryGetValue(row.AcademicYear.Trim(), out var yid)) row.AcademicYearId = yid;
                else errors.Add($"Unknown academic year '{row.AcademicYear}'");
            }

            if (errors.Count == 0) { row.Status = "Valid"; preview.Valid++; }
            else { row.Status = "Invalid"; row.Error = string.Join("; ", errors); preview.Invalid++; }
            preview.Rows.Add(row);
        }
        return preview;
    }

    /// <summary>Create every supplied row as a new student. Returns counts + per-row errors.</summary>
    public (int created, int failed, List<string> errors) CommitImport(int tenantId, long actorUserId, List<StudentImportRow> rows)
    {
        // Re-validate server-side so a tampered client can't bypass checks.
        var preview = ValidateImport(tenantId, rows.ToList());
        var created = 0; var failed = 0; var errors = new List<string>();

        foreach (var row in preview.Rows)
        {
            if (row.Status != "Valid") { failed++; errors.Add($"Row {row.RowNumber}: {row.Error}"); continue; }
            var vo = new StudentVO
            {
                StudentId = null,
                AdmissionNumber = "", // auto-generated
                FirstName = row.FirstName,
                MiddleName = row.MiddleName,
                LastName = row.LastName,
                Gender = row.Gender,
                DateOfBirth = row.DateOfBirth is null ? null : DateTime.Parse(row.DateOfBirth, CultureInfo.InvariantCulture),
                Nationality = row.Nationality,
                BloodGroup = row.BloodGroup,
                ClassId = row.ClassId,
                SectionId = row.SectionId,
                AcademicYearId = row.AcademicYearId,
                RollNumber = row.RollNumber,
                AdmissionDate = row.AdmissionDate is null ? null : DateTime.Parse(row.AdmissionDate, CultureInfo.InvariantCulture),
                GuardianName = row.GuardianName,
                GuardianRelation = row.Relationship,
                GuardianPhone = row.GuardianPhone,
                GuardianEmail = row.GuardianEmail,
                Email = row.Email,
                Phone = row.Phone,
                AddressLine1 = row.AddressLine1,
                City = row.City,
                State = row.State,
                PostalCode = row.PostalCode,
                Country = row.Country
            };
            var res = Save(tenantId, actorUserId, vo);
            if ((Common.ResultCodes)res.result_code == Common.ResultCodes.SUCCESS) created++;
            else { failed++; errors.Add($"Row {row.RowNumber}: {res.message}"); }
        }
        return (created, failed, errors);
    }
}

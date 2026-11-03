namespace EduNestIO.Common.DTOs;

/// <summary>
/// Create/update request for a student (VO). Note there is NO tenant_id here;
/// ownership is always derived server-side from the authenticated UserContext.
/// </summary>
public class StudentVO
{
    public long? StudentId { get; set; }
    public string AdmissionNumber { get; set; } = string.Empty;

    // Personal
    public string FirstName { get; set; } = string.Empty;
    public string? MiddleName { get; set; }
    public string LastName { get; set; } = string.Empty;
    public string? Gender { get; set; }
    public DateTime? DateOfBirth { get; set; }
    public string? Nationality { get; set; }
    public string? BloodGroup { get; set; }
    public string? PhotoUrl { get; set; }

    // Contact
    public string? Email { get; set; }
    public string? Phone { get; set; }

    // Address
    public string? AddressLine1 { get; set; }
    public string? AddressLine2 { get; set; }
    public string? City { get; set; }
    public string? State { get; set; }
    public string? PostalCode { get; set; }
    public string? Country { get; set; }

    // Academic
    public long? ClassId { get; set; }
    public long? SectionId { get; set; }
    public long? AcademicYearId { get; set; }
    public string? RollNumber { get; set; }
    public DateTime? AdmissionDate { get; set; }
    public string? Status { get; set; }

    // Guardian
    public string? GuardianName { get; set; }
    public string? GuardianRelation { get; set; }
    public string? GuardianPhone { get; set; }
    public string? GuardianAltPhone { get; set; }
    public string? GuardianEmail { get; set; }
}

/// <summary>One validated row of a student-import preview (sent back to the client, then returned to commit).</summary>
public class StudentImportRow
{
    public int RowNumber { get; set; }
    public string Status { get; set; } = "Valid";   // Valid | Invalid
    public string? Error { get; set; }

    public string FirstName { get; set; } = "";
    public string? MiddleName { get; set; }
    public string LastName { get; set; } = "";
    public string? Gender { get; set; }
    public string? DateOfBirth { get; set; }         // yyyy-MM-dd
    public string? Nationality { get; set; }
    public string? BloodGroup { get; set; }

    public string? ClassName { get; set; }
    public long? ClassId { get; set; }
    public string? SectionName { get; set; }
    public long? SectionId { get; set; }
    public string? AcademicYear { get; set; }
    public long? AcademicYearId { get; set; }
    public string? RollNumber { get; set; }
    public string? AdmissionDate { get; set; }       // yyyy-MM-dd

    public string? GuardianName { get; set; }
    public string? Relationship { get; set; }
    public string? GuardianPhone { get; set; }
    public string? GuardianEmail { get; set; }
    public string? Email { get; set; }
    public string? Phone { get; set; }
    public string? AddressLine1 { get; set; }
    public string? City { get; set; }
    public string? State { get; set; }
    public string? PostalCode { get; set; }
    public string? Country { get; set; }
}

/// <summary>Preview result for a student-import file.</summary>
public class StudentImportPreview
{
    public List<StudentImportRow> Rows { get; set; } = new();
    public int Valid { get; set; }
    public int Invalid { get; set; }
}

/// <summary>Commit request: the validated rows the user chose to import.</summary>
public class StudentImportCommitVO
{
    public List<StudentImportRow> Rows { get; set; } = new();
}

/// <summary>Query/filter request for listing students with pagination.</summary>
public class StudentQueryVO
{
    public string? Search { get; set; }
    public long? ClassId { get; set; }
    public long? SectionId { get; set; }
    public long? AcademicYearId { get; set; }
    public string? Status { get; set; }
    public int Page { get; set; } = 1;
    public int PageSize { get; set; } = 20;
    public string? SortBy { get; set; }
    public string? SortDir { get; set; }
}

/// <summary>Explicit status-change request (graduate/withdraw/deactivate/reactivate).</summary>
public class StudentStatusVO
{
    public string Status { get; set; } = string.Empty;
    public string? Reason { get; set; }
}

/// <summary>Bulk promote request: move the given students to a target class.</summary>
public class PromoteVO
{
    public List<long> StudentIds { get; set; } = new();
    public long ToClassId { get; set; }
    public long? ToSectionId { get; set; }
    public long? AcademicYearId { get; set; }
    public string? Note { get; set; }
}

/// <summary>Bulk graduate request (terminal).</summary>
public class GraduateVO
{
    public List<long> StudentIds { get; set; } = new();
    public string? Note { get; set; }
}

/// <summary>Bulk withdraw request (terminal).</summary>
public class WithdrawVO
{
    public List<long> StudentIds { get; set; } = new();
    public string? Reason { get; set; }
}

/// <summary>One row of a student's per-class enrollment history.</summary>
public class EnrollmentDTO
{
    public long enrollment_id { get; set; }
    public long? class_id { get; set; }
    public string? class_name { get; set; }
    public long? section_id { get; set; }
    public string? section_name { get; set; }
    public long? academic_year_id { get; set; }
    public string? academic_year_name { get; set; }
    public string? roll_number { get; set; }
    public string status { get; set; } = string.Empty;
    public DateTime? from_date { get; set; }
    public DateTime? to_date { get; set; }
    public string? note { get; set; }
}

/// <summary>Read model returned to the client (mirrors the DB jsonb, snake_case).</summary>
public class StudentDTO
{
    public long student_id { get; set; }
    public int tenant_id { get; set; }
    public string admission_number { get; set; } = string.Empty;
    public string first_name { get; set; } = string.Empty;
    public string? middle_name { get; set; }
    public string last_name { get; set; } = string.Empty;
    public string? gender { get; set; }
    public DateTime? date_of_birth { get; set; }
    public string? nationality { get; set; }
    public string? blood_group { get; set; }
    public string? photo_url { get; set; }
    public string? email { get; set; }
    public string? phone { get; set; }
    public string? address_line1 { get; set; }
    public string? address_line2 { get; set; }
    public string? city { get; set; }
    public string? state { get; set; }
    public string? postal_code { get; set; }
    public string? country { get; set; }
    public long? class_id { get; set; }
    public string? class_name { get; set; }
    public long? section_id { get; set; }
    public string? section_name { get; set; }
    public long? academic_year_id { get; set; }
    public string? academic_year_name { get; set; }
    public string? roll_number { get; set; }
    public DateTime? admission_date { get; set; }
    public string? status { get; set; }
    public string? status_reason { get; set; }
    public DateTime? status_changed_at { get; set; }
    public string? guardian_name { get; set; }
    public string? guardian_relation { get; set; }
    public string? guardian_phone { get; set; }
    public string? guardian_alt_phone { get; set; }
    public string? guardian_email { get; set; }
    public DateTime created_at { get; set; }
    public DateTime? updated_at { get; set; }
}

namespace EduNestIO.Common.Security;

/// <summary>Canonical role names (match database seed_reference_data).</summary>
public static class Roles
{
    public const string SaaSSuperAdmin = "SaaSSuperAdmin";
    public const string SchoolAdmin = "SchoolAdmin";
    public const string Principal = "Principal";
    public const string Accountant = "Accountant";
    public const string AdmissionOfficer = "AdmissionOfficer";
    public const string Teacher = "Teacher";
    public const string ClassTeacher = "ClassTeacher";
    public const string Librarian = "Librarian";
    public const string TransportManager = "TransportManager";
    public const string HRPayrollManager = "HRPayrollManager";
    public const string Student = "Student";
    public const string Guardian = "Guardian";
    public const string Receptionist = "Receptionist";
}

/// <summary>
/// Permission catalog (match database seed). Convention: "module.action".
/// Each module adds its permissions here and in 06_seed_reference_data.sql.
/// </summary>
public static class Permissions
{
    // Student Records (vertical slice)
    public const string StudentView = "student.view";
    public const string StudentCreate = "student.create";
    public const string StudentUpdate = "student.update";
    public const string StudentDelete = "student.delete";
    public const string StudentStatus = "student.status";
    public const string StudentPromote = "student.promote";

    // Academic Setup
    public const string AcademicView = "academic.view";
    public const string AcademicManage = "academic.manage";

    // Admissions
    public const string AdmissionView = "admission.view";
    public const string AdmissionManage = "admission.manage";
    public const string AdmissionConvert = "admission.convert";

    // Attendance
    public const string AttendanceView = "attendance.view";
    public const string AttendanceMark = "attendance.mark";

    // Fees & Finance
    public const string FeeView = "fee.view";
    public const string FeeManage = "fee.manage";
    public const string FeeCollect = "fee.collect";
    public const string FeeReverse = "fee.reverse";

    // Exams & Report Cards
    public const string ExamView = "exam.view";
    public const string ExamManage = "exam.manage";
    public const string ExamMarks = "exam.marks";
    public const string ExamPublish = "exam.publish";
    public const string ExamReportcard = "exam.reportcard";

    // Leave management + self-service portal
    public const string LeaveApply = "leave.apply";
    public const string LeaveManage = "leave.manage";
    public const string PortalSelf = "portal.self";

    // School settings
    public const string SettingsView = "settings.view";
    public const string SettingsManage = "settings.manage";

    // Timetable
    public const string TimetableView = "timetable.view";
    public const string TimetableManage = "timetable.manage";

    // Assignments
    public const string AssignmentView = "assignment.view";
    public const string AssignmentManage = "assignment.manage";
    public const string AssignmentSubmit = "assignment.submit";

    // Platform
    public const string TenantManage = "platform.tenant.manage";
}

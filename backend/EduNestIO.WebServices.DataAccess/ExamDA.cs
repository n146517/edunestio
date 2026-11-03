using EduNestIO.Common.Data;
using EduNestIO.Common.DTOs;

namespace EduNestIO.WebServices.DataAccess;

/// <summary>Data access for the Exams and Report Cards module.</summary>
public class ExamDA : DBBase
{
    public ExamDA(string connectionString = "") : base(connectionString) { }

    public DbResult ExamSave(int tenantId, object payload) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_exam_save", tenantId, payload);

    public DbResult ExamList(int tenantId, object payload) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_exam_list", tenantId, payload);

    public DbResult ExamGet(int tenantId, long examId) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_exam_get", tenantId,
            new { exam_id = examId });

    public DbResult SubjectAdd(int tenantId, object payload) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_exam_subject_add", tenantId, payload);

    public DbResult ClassSubjectsSave(int tenantId, object payload) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_exam_class_subjects_save", tenantId, payload);

    public DbResult ClassSubjectsList(int tenantId, long examId, long? classId) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_exam_class_subjects_list", tenantId,
            new { exam_id = examId, class_id = classId });

    public DbResult ScheduleSave(int tenantId, object payload) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_exam_schedule_save", tenantId, payload);

    public DbResult ScheduleList(int tenantId, long examId, long? classId) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_exam_schedule_list", tenantId,
            new { exam_id = examId, class_id = classId });

    public DbResult MarksSheet(int tenantId, long examSubjectId, long? sectionId) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_exam_marks_sheet", tenantId,
            new { exam_subject_id = examSubjectId, section_id = sectionId });

    public DbResult SubjectsForClass(int tenantId, long examId, long classId) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_exam_subjects_for_class", tenantId,
            new { exam_id = examId, class_id = classId });

    public DbResult ResolveExamSubject(int tenantId, long examId, long classId, long subjectId) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_exam_subject_resolve", tenantId,
            new { exam_id = examId, class_id = classId, subject_id = subjectId });

    public DbResult MarksSave(int tenantId, object payload) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_exam_marks_save", tenantId, payload);

    public DbResult Publish(int tenantId, object payload) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_exam_publish", tenantId, payload);

    public DbResult ResultPreview(int tenantId, long examId, long classId, long? sectionId) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_exam_result_preview", tenantId,
            new { exam_id = examId, class_id = classId, section_id = sectionId });

    public DbResult ReportCard(int tenantId, long examId, long studentId, bool requirePublished) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_exam_report_card", tenantId,
            new { exam_id = examId, student_id = studentId, require_published = requirePublished });

    public DbResult ReportCardClassList(int tenantId, long examId, long classId, long? sectionId) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_report_card_class_list", tenantId,
            new { exam_id = examId, class_id = classId, section_id = sectionId });
}

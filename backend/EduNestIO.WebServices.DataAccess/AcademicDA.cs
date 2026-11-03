using EduNestIO.Common.Data;
using EduNestIO.Common.DTOs;

namespace EduNestIO.WebServices.DataAccess;

/// <summary>Data access for the Academic Setup module (years, classes, sections, subjects).</summary>
public class AcademicDA : DBBase
{
    public AcademicDA(string connectionString = "") : base(connectionString) { }

    public DbResult AcademicYearSave(int tenantId, object payload) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_academic_year_save", tenantId, payload);
    public DbResult AcademicYearList(int tenantId) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_academic_year_list", tenantId, new { });

    public DbResult ClassSave(int tenantId, object payload) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_class_save", tenantId, payload);
    public DbResult ClassList(int tenantId) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_class_list", tenantId, new { });

    public DbResult SectionSave(int tenantId, object payload) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_section_save", tenantId, payload);
    public DbResult SectionList(int tenantId, long? classId) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_section_list", tenantId, new { class_id = classId });

    public DbResult SubjectSave(int tenantId, object payload) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_subject_save", tenantId, payload);
    public DbResult SubjectList(int tenantId) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_subject_list", tenantId, new { });
}

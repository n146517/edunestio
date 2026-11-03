using EduNestIO.Common.DTOs;
using EduNestIO.WebServices.DataAccess;
using static EduNestIO.WebServices.Business.DBManagerDA;

namespace EduNestIO.WebServices.Business;

/// <summary>
/// Business logic for Academic Setup. Follows the factory + finally-release pattern.
/// Tenant id is always the caller's (from the authenticated token).
/// </summary>
public class AcademicBL
{
    private static AcademicDA Da() => (AcademicDA)GetDBObject(DAType.Academic)!;

    public DbResult AcademicYearSave(int tenantId, AcademicYearVO vo)
    {
        AcademicDA? da = null;
        try { da = Da(); return da.AcademicYearSave(tenantId, vo); }
        finally { ReleaseDBObject(da); }
    }
    public DbResult AcademicYearList(int tenantId)
    {
        AcademicDA? da = null;
        try { da = Da(); return da.AcademicYearList(tenantId); }
        finally { ReleaseDBObject(da); }
    }

    public DbResult ClassSave(int tenantId, ClassVO vo)
    {
        AcademicDA? da = null;
        try { da = Da(); return da.ClassSave(tenantId, vo); }
        finally { ReleaseDBObject(da); }
    }
    public DbResult ClassList(int tenantId)
    {
        AcademicDA? da = null;
        try { da = Da(); return da.ClassList(tenantId); }
        finally { ReleaseDBObject(da); }
    }

    public DbResult SectionSave(int tenantId, SectionVO vo)
    {
        AcademicDA? da = null;
        try { da = Da(); return da.SectionSave(tenantId, vo); }
        finally { ReleaseDBObject(da); }
    }
    public DbResult SectionList(int tenantId, long? classId)
    {
        AcademicDA? da = null;
        try { da = Da(); return da.SectionList(tenantId, classId); }
        finally { ReleaseDBObject(da); }
    }

    public DbResult SubjectSave(int tenantId, SubjectVO vo)
    {
        AcademicDA? da = null;
        try { da = Da(); return da.SubjectSave(tenantId, vo); }
        finally { ReleaseDBObject(da); }
    }
    public DbResult SubjectList(int tenantId)
    {
        AcademicDA? da = null;
        try { da = Da(); return da.SubjectList(tenantId); }
        finally { ReleaseDBObject(da); }
    }
}

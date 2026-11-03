using EduNestIO.Common.DTOs;
using EduNestIO.WebServices.DataAccess;
using static EduNestIO.WebServices.Business.DBManagerDA;

namespace EduNestIO.WebServices.Business;

/// <summary>Business logic for per-tenant school settings.</summary>
public class SettingsBL
{
    private static SettingsDA Da() => (SettingsDA)GetDBObject(DAType.Settings)!;

    public DbResult Get(int tenantId)
    {
        SettingsDA? da = null;
        try { da = Da(); return da.Get(tenantId); }
        finally { ReleaseDBObject(da); }
    }

    public DbResult Save(int tenantId, SettingsVO vo)
    {
        SettingsDA? da = null;
        try { da = Da(); return da.Set(tenantId, new { attendance_mode = vo.AttendanceMode }); }
        finally { ReleaseDBObject(da); }
    }
}

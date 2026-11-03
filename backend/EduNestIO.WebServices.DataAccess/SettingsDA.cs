using EduNestIO.Common.Data;
using EduNestIO.Common.DTOs;

namespace EduNestIO.WebServices.DataAccess;

/// <summary>Data access for per-tenant school settings.</summary>
public class SettingsDA : DBBase
{
    public SettingsDA(string connectionString = "") : base(connectionString) { }

    public DbResult Get(int tenantId) =>
        DAHelper.ExecuteTenantJson(DbMaster, "core.fn_tenant_settings_get", tenantId, new { });

    public DbResult Set(int tenantId, object payload) =>
        DAHelper.ExecuteTenantJson(DbMaster, "core.fn_tenant_settings_set", tenantId, payload);
}

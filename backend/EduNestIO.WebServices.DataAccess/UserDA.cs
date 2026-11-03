using EduNestIO.Common.Data;
using EduNestIO.Common.DTOs;

namespace EduNestIO.WebServices.DataAccess;

/// <summary>Data access for user administration / dev seeding.</summary>
public class UserDA : DBBase
{
    public UserDA(string connectionString = "") : base(connectionString) { }

    public DbResult UpsertUser(int tenantId, object userPayload) =>
        DAHelper.ExecuteTenantJson(DbMaster, "core.fn_upsert_user", tenantId, userPayload);
}

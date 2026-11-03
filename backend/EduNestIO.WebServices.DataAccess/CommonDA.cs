using EduNestIO.Common.Data;
using EduNestIO.Common.DTOs;

namespace EduNestIO.WebServices.DataAccess;

/// <summary>Cross-cutting data access (audit, document numbering).</summary>
public class CommonDA : DBBase
{
    public CommonDA(string connectionString = "") : base(connectionString) { }

    public DbResult WriteAudit(int tenantId, object auditPayload) =>
        DAHelper.ExecuteTenantJson(DbMaster, "core.fn_write_audit", tenantId, auditPayload);

    public DbResult NextDocumentNumber(int tenantId, string seqKey) =>
        DAHelper.ExecuteTenantJson(DbMaster, "core.fn_next_document_number", tenantId, new { seq_key = seqKey });
}

using EduNestIO.Common.Data;
using EduNestIO.Common.DTOs;

namespace EduNestIO.WebServices.DataAccess;

/// <summary>Data access for Admissions & Enquiry CRM.</summary>
public class AdmissionDA : DBBase
{
    public AdmissionDA(string connectionString = "") : base(connectionString) { }

    public DbResult EnquirySave(int tenantId, object payload) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_enquiry_save", tenantId, payload);

    public DbResult EnquiryList(int tenantId, object payload) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_enquiry_list", tenantId, payload);

    public DbResult FollowupAdd(int tenantId, object payload) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_enquiry_followup_add", tenantId, payload);

    public DbResult Followups(int tenantId, long enquiryId) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_enquiry_followups", tenantId, new { enquiry_id = enquiryId });

    public DbResult Convert(int tenantId, object payload) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_enquiry_convert", tenantId, payload);

    public DbResult Funnel(int tenantId) =>
        DAHelper.ExecuteTenantJson(DbMaster, "academics.fn_admission_funnel", tenantId, new { });
}

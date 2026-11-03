using EduNestIO.Common.DTOs;
using EduNestIO.WebServices.DataAccess;
using Newtonsoft.Json.Linq;
using static EduNestIO.WebServices.Business.DBManagerDA;

namespace EduNestIO.WebServices.Business;

/// <summary>Business logic for Admissions & Enquiry CRM.</summary>
public class AdmissionBL
{
    private static AdmissionDA Da() => (AdmissionDA)GetDBObject(DAType.Admission)!;

    public DbResult EnquirySave(int tenantId, long actorUserId, EnquiryVO vo)
    {
        AdmissionDA? da = null;
        try
        {
            da = Da();
            var payload = JObject.FromObject(vo);
            payload["ActorUserId"] = actorUserId;
            return da.EnquirySave(tenantId, payload);
        }
        finally { ReleaseDBObject(da); }
    }

    public DbResult EnquiryList(int tenantId, EnquiryQueryVO q)
    {
        AdmissionDA? da = null;
        try
        {
            da = Da();
            return da.EnquiryList(tenantId, new { search = q.Search, stage = q.Stage, page = q.Page, page_size = q.PageSize });
        }
        finally { ReleaseDBObject(da); }
    }

    public DbResult FollowupAdd(int tenantId, long actorUserId, FollowupVO vo)
    {
        AdmissionDA? da = null;
        try
        {
            da = Da();
            var payload = JObject.FromObject(vo);
            payload["ActorUserId"] = actorUserId;
            return da.FollowupAdd(tenantId, payload);
        }
        finally { ReleaseDBObject(da); }
    }

    public DbResult Followups(int tenantId, long enquiryId)
    {
        AdmissionDA? da = null;
        try { da = Da(); return da.Followups(tenantId, enquiryId); }
        finally { ReleaseDBObject(da); }
    }

    public DbResult Convert(int tenantId, long actorUserId, ConvertEnquiryVO vo)
    {
        AdmissionDA? da = null;
        try
        {
            da = Da();
            var payload = JObject.FromObject(vo);
            payload["ActorUserId"] = actorUserId;
            return da.Convert(tenantId, payload);
        }
        finally { ReleaseDBObject(da); }
    }

    public DbResult Funnel(int tenantId)
    {
        AdmissionDA? da = null;
        try { da = Da(); return da.Funnel(tenantId); }
        finally { ReleaseDBObject(da); }
    }
}

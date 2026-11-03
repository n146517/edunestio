using EduNestIO.Common.DTOs;
using EduNestIO.Common.Security;
using EduNestIO.WebServices.Business;
using EduNestIO.WebServices.RestAPI.Filters;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace EduNestIO.WebServices.RestAPI.Controllers;

/// <summary>
/// Admissions and Enquiry CRM. Enquiries, follow-ups, funnel, and conversion of an
/// accepted enquiry into a student (reusing the Student save path server-side).
/// </summary>
[ApiController]
[Route("api/admissions")]
[Authorize]
[ServiceExceptionFilter]
public sealed class AdmissionController : BaseApiController
{
    private readonly AdmissionBL _bl = new();

    [HttpGet("enquiries")]
    [RequirePermission(Permissions.AdmissionView)]
    public ActionResult List([FromQuery] EnquiryQueryVO q) => Map(_bl.EnquiryList(CurrentUser.TenantId, q));

    [HttpPost("enquiries")]
    [RequirePermission(Permissions.AdmissionManage)]
    public ActionResult Save([FromBody] EnquiryVO vo)
    {
        var created = vo.EnquiryId is null;
        return Map(_bl.EnquirySave(CurrentUser.TenantId, CurrentUser.UserId, vo), created);
    }

    [HttpGet("enquiries/{id:long}/followups")]
    [RequirePermission(Permissions.AdmissionView)]
    public ActionResult Followups(long id) => Map(_bl.Followups(CurrentUser.TenantId, id));

    [HttpPost("enquiries/{id:long}/followups")]
    [RequirePermission(Permissions.AdmissionManage)]
    public ActionResult AddFollowup(long id, [FromBody] FollowupVO vo)
    {
        vo.EnquiryId = id;
        return Map(_bl.FollowupAdd(CurrentUser.TenantId, CurrentUser.UserId, vo), created: true);
    }

    [HttpPost("enquiries/{id:long}/convert")]
    [RequirePermission(Permissions.AdmissionConvert)]
    public ActionResult Convert(long id, [FromBody] ConvertEnquiryVO vo)
    {
        vo.EnquiryId = id;
        return Map(_bl.Convert(CurrentUser.TenantId, CurrentUser.UserId, vo), created: true);
    }

    [HttpGet("funnel")]
    [RequirePermission(Permissions.AdmissionView)]
    public ActionResult Funnel() => Map(_bl.Funnel(CurrentUser.TenantId));
}

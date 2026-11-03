using EduNestIO.Common.DTOs;
using EduNestIO.Common.Security;
using EduNestIO.WebServices.Business;
using EduNestIO.WebServices.RestAPI.Filters;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Mvc;

namespace EduNestIO.WebServices.RestAPI.Controllers;

[ApiController]
[Route("api/settings")]
[Authorize]
[ServiceExceptionFilter]
public sealed class SettingsController : BaseApiController
{
    private readonly SettingsBL _bl = new();

    /// <summary>Read this school's settings (incl. attendance mode).</summary>
    [HttpGet]
    [RequirePermission(Permissions.SettingsView, Permissions.AttendanceView)]
    public ActionResult Get() => Map(_bl.Get(CurrentUser.TenantId));

    /// <summary>Update this school's settings.</summary>
    [HttpPost]
    [RequirePermission(Permissions.SettingsManage)]
    public ActionResult Save([FromBody] SettingsVO vo) => Map(_bl.Save(CurrentUser.TenantId, vo));
}
